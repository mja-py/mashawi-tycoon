class_name FastSim
extends RefCounted
## Statistical day without a world, for headless balance runs (`--autodays`) and tests. It
## plays the visible day's rules on the same clock: the same arrivals, stop chances, buyer
## budget, parties, Throughput pipeline (sim-seconds), stock holds and sales. Each walker is
## a timed body instead of a rigged model: the walking takes the times DaySim was measured
## to take (Data.SERVICE "walk"), and restaurant servers carry meals and clear tables on
## the measured job times. Each sale consumes real stock and books real cash.

const STEP := 1.0 / 30.0
## A day that has not closed by then is broken; this only stops the loop.
const MAX_SECONDS := 600.0

var ctx: Dictionary
var rng: RandomNumberGenerator
var move := RandomNumberGenerator.new()
var loc: Dictionary
var tp: Throughput
var ledger := StockLedger.new()
var stats: Dictionary
var walk: Dictionary
var bodies := {}
var _next_id := 0
var _t := 0.0
var _handoff_until := 0.0
var _closing := false
var _buyers_out := 0
var _budget := 0
var _counter_level := 0
var _workers: Array = []
var _seats: Array = []
var _tables: Array = []
var _street_sum := 0.0
var _street_ticks := 0

static func run(context: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var sim := FastSim.new()
	return sim._run(context, r)

func _run(context: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	ctx = context
	rng = r
	move.seed = rng.seed ^ 73691
	loc = Data.LOCATIONS[ctx["location"]]
	var stage := int(ctx.get("stage", 0))
	_counter_level = int(ctx.get("counter_level", 0))
	_budget = int(ctx.get("buyers", Economy.buyer_budget(stage, _counter_level)))
	walk = ctx.get("walk", Economy.walk_times(stage, String(ctx["location"])))
	if not ctx.has("party"):
		ctx["party"] = Economy.party_weights(stage, String(ctx["location"]))
	if not ctx.has("patience_s"):
		ctx["patience_s"] = float(Data.SERVICE["patience_s"]) * float(loc.get("patience", 1.0))
	stats = {"_day": int(ctx.get("day", Game.day)), "passers": 0, "served": 0, "portions": 0, "revenue": 0.0, "cogs": 0.0,
		"sold": {}, "satisfaction_sum": 0.0, "wait_sum": 0.0, "left_wait": 0, "sold_out": 0, "queue_full": 0, "lost_rival": 0,
		"too_pricey": 0, "crowd": 0, "dine_in": 0}
	var seats := int(ctx.get("seats", 0))
	for i in range(seats):
		_seats.append({"holder": -1, "table": i / 2, "needs_clean": false})
	for i in range((seats + 1) / 2):
		_tables.append({"dirty": false, "assigned": false})
	for i in range(int(ctx.get("workers", 0)) if seats > 0 else 0):
		_workers.append({"busy": false, "until": 0.0, "done": Callable()})
	tp = Throughput.new()
	tp.setup(ctx, rng)
	tp.on_served = _on_served
	tp.on_gave_up = _on_gave_up
	tp.on_ordered = _on_ordered
	tp.on_left_seat = _on_left_seat
	tp.take_order = _take_order
	tp.counter_ready = _counter_ready
	tp.pickup_ready = _pickup_ready
	tp.waiting_in_line = _waiting_in_line
	tp.waiting_for_food = _waiting_for_food
	tp.dining_choice = _choose_dining
	tp.table_clean = func(table: int) -> bool: return table < 0 or table >= _tables.size() or not _tables[table]["dirty"]
	var hours: Array = ctx["hours"]
	var hour := float(hours[0])
	var end_hour := float(hours[1])
	var hour_s := Data.REAL_SECONDS_PER_GAME_HOUR
	while _t < MAX_SECONDS:
		_t += STEP
		_step_workers()
		_step_bodies()
		if not _closing:
			hour = minf(end_hour, hour + STEP / hour_s)
			var expected := Economy.arrival_rate(loc, ctx["weather"], hour, ctx) * STEP / hour_s
			var n := int(expected) + (1 if rng.randf() < expected - int(expected) else 0)
			for i in range(n):
				_spawn_passer()
			_street_sum += float(_buyers_out) / float(maxi(_budget, 1))
			_street_ticks += 1
		var before_line := tp.queue_payloads()
		var before_pickup := tp.waiting_payloads()
		tp.tick(STEP, hour)
		if before_line != tp.queue_payloads():
			_reflow_line()
		if before_pickup != tp.waiting_payloads():
			_reflow_pickup()
		if hour >= end_hour and not _closing:
			_closing = true
			tp.close_queue()
		if _closing and not tp.has_orders() and tp.seated.is_empty() and _t >= _handoff_until and _staff_idle():
			break
	stats["left_wait"] = int(tp.stats["left_wait"])
	stats["max_queue"] = int(tp.stats["max_queue"])
	stats["street"] = _street_sum / float(maxi(_street_ticks, 1))
	stats["util"] = Economy.street_util(tp.utilisation(), float(stats["street"]))
	stats["_seconds"] = _t
	return stats

# ---------------------------------------------------------------- bodies

## Walking times carry the walker's pace (World draws 0.85..1.2 x the base speed).
func _walk(key: String, pace: float) -> float:
	return float(walk[key]) * pace

func _new_body(visit: String, wants: String, roll: float) -> Dictionary:
	_next_id += 1
	var pace := 1.0 / move.randf_range(0.85, 1.2) / 0.985
	var b := {"id": _next_id, "visit": visit, "wants": wants, "roll": roll, "pace": pace, "phase": "in",
		"until": _t + _walk("in", pace), "slot": -1, "stand_at": INF, "order_end": -1.0, "item": "", "portions": 1,
		"seat": -1, "served": false}
	bodies[_next_id] = b
	_buyers_out += 1
	return b

func _leave(b: Dictionary, seconds: float) -> void:
	b["phase"] = "leave"
	b["until"] = _t + seconds
	b["slot"] = -1

func _step_bodies() -> void:
	for id in bodies.keys():
		var b: Dictionary = bodies[id]
		if b["phase"] == "leave" and _t >= float(b["until"]):
			_gone(b)
		elif b["phase"] == "in" and _t >= float(b["until"]):
			_decide(b)

func _gone(b: Dictionary) -> void:
	bodies.erase(b["id"])
	_buyers_out -= 1
	tp.remove(b["id"])
	ledger.release(b["id"])
	_release_seat(b)

func _candidates(wants: String) -> Array:
	var cands := Game.candidates(wants)
	for cand in cands:
		cand["stock"] = ledger.portions_free(cand["id"])
	return cands

func _look(wants: String) -> Dictionary:
	var out := {"best": 0.0, "ratio": 1.0, "stock": false, "cands": _candidates(wants)}
	for cand in out["cands"]:
		if float(cand["value"]) > float(out["best"]):
			out["best"] = float(cand["value"])
			out["ratio"] = float(Game.menu[cand["id"]]["price"]) / float(Data.MENU_ITEMS[cand["id"]]["base_price"])
		if int(cand["stock"]) > 0:
			out["stock"] = true
	return out

func _stop(best: float, queue_len: int, rivals: bool = true) -> float:
	if not rivals:
		return Economy.stop_probability(float(ctx["popularity"]), best * float(ctx["appeal"]), float(ctx["boost"]), queue_len, int(ctx["queue_cap"]))
	return Economy.stop_probability(float(ctx["popularity"]), best * float(ctx["appeal"]), float(ctx["boost"]), queue_len,
		int(ctx["queue_cap"]), float(ctx["competition"]), float(ctx["promo_power"]))

## DaySim._spawn_passer, with a body instead of a rigged walker.
func _spawn_passer() -> void:
	stats["passers"] += 1
	var wants := "drink" if rng.randf() < Economy.drink_share(ctx["weather"]) else "food"
	var look := _look(wants)
	var best := float(look["best"])
	var r := rng.randf()
	var p_room := _stop(best, 0)
	var p_any := _stop(best, 0, false)
	var visit := ""
	if r < p_room:
		visit = "buyer"
	elif r < p_any and float(ctx["competition"]) > 0.0:
		stats["lost_rival"] += 1
		visit = "rival"
	elif best < 0.55 and float(look["ratio"]) > 1.20 and r < p_room * 1.5:
		stats["too_pricey"] += 1
		visit = "pricey"
	if visit == "":
		return
	var room := _budget - _buyers_out
	if visit == "buyer" and room <= 0:
		stats["crowd"] += 1
		return
	if visit != "buyer" and room < int(Data.GUEST_BUDGET["spare_for_reactions"]):
		return
	rng.randf() # the walking direction
	_new_body(visit, wants, r)

## DaySim._on_decision at the stand.
func _decide(b: Dictionary) -> void:
	var pace := float(b["pace"])
	if _closing or b["visit"] == "rival":
		_leave(b, _walk("pass", pace))
		return
	if b["visit"] == "pricey":
		_leave(b, _walk("turn", pace))
		return
	var look := _look(String(b["wants"]))
	var cands: Array = look["cands"]
	if cands.is_empty():
		_leave(b, _walk("pass", pace))
		return
	var p := _stop(float(look["best"]), tp.queue_len())
	if tp.is_full():
		stats["queue_full"] += 1
		_leave(b, _walk("turn", pace))
	elif float(b["roll"]) < p:
		if not bool(look["stock"]):
			stats["sold_out"] += 1
			_leave(b, _walk("turn", pace))
			return
		b["item"] = Economy.pick_weighted(cands, rng)
		b["portions"] = Economy.pick_party(ctx["party"], rng)
		if tp.enqueue(b["id"], b["item"], b["portions"]):
			b["phase"] = "line"
			b["slot"] = tp.queue_len() - 1
			b["stand_at"] = _t + _walk("line", pace)
	else:
		_leave(b, _walk("pass", pace))

## Moving up the line takes a step; someone still walking up is simply redirected.
func _reflow_line() -> void:
	var line := tp.queue_payloads()
	for i in range(line.size()):
		var b: Dictionary = bodies.get(line[i], {})
		if b.is_empty() or int(b["slot"]) == i:
			continue
		b["slot"] = i
		b["stand_at"] = maxf(_t + _walk("step", float(b["pace"])), float(b["stand_at"]) - _walk("step", float(b["pace"])))

func _reflow_pickup() -> void:
	var line := tp.waiting_payloads()
	for i in range(line.size()):
		var b: Dictionary = bodies.get(line[i], {})
		if b.is_empty() or int(b["slot"]) == 100 + i:
			continue
		b["slot"] = 100 + i
		b["stand_at"] = maxf(_t + _walk("step", float(b["pace"])), float(b["stand_at"]) - _walk("step", float(b["pace"])))

func _standing(b: Dictionary) -> bool:
	return _t >= float(b["stand_at"])

# ---------------------------------------------------------------- pipeline callbacks

func _waiting_in_line(id: int) -> bool:
	var b: Dictionary = bodies.get(id, {})
	return not b.is_empty() and b["phase"] == "line" and int(b["slot"]) > 0 and _standing(b)

func _waiting_for_food(id: int) -> bool:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty():
		return false
	return (b["phase"] == "pickup" or b["phase"] == "seated") and _standing(b)

func _counter_ready(id: int, portions: int = 1) -> bool:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty() or b["phase"] != "line" or int(b["slot"]) != 0 or not _standing(b):
		return false
	if float(b["order_end"]) < 0.0:
		b["order_end"] = _t + Economy.order_seconds(portions, _counter_level)
	return _t >= float(b["order_end"])

func _take_order(id: int, item: String, portions: int) -> int:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty():
		return 0
	var held := ledger.hold(id, item, portions)
	if held <= 0:
		stats["sold_out"] += 1
		_release_seat(b)
		_leave(b, _walk("turn", float(b["pace"])))
		return 0
	b["portions"] = held
	return held

func _choose_dining(id: int, item: String) -> bool:
	if Data.MENU_ITEMS[item]["kind"] != "food":
		return false
	for i in range(_seats.size()):
		var s: Dictionary = _seats[i]
		if int(s["holder"]) >= 0 or bool(s["needs_clean"]) or bool(_tables[int(s["table"])]["dirty"]):
			continue
		s["holder"] = id
		bodies[id]["seat"] = i
		return true
	return false

func _on_ordered(id: int, _station: String) -> void:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty():
		return
	var pace := float(b["pace"])
	if int(b["seat"]) >= 0:
		b["phase"] = "seated"
		b["slot"] = -1
		b["stand_at"] = _t + _walk("seat", pace)
		return
	b["phase"] = "pickup"
	var i := maxi(tp.waiting_payloads().find(id), 0)
	b["slot"] = 100 + i
	b["stand_at"] = _t + _walk("pickup", pace) + i * _walk("step", pace)

func _pickup_ready(id: int) -> bool:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty() or not _standing(b):
		return false
	if b["phase"] == "seated":
		return _free_worker() >= 0
	return b["phase"] == "pickup" and int(b["slot"]) == 100 and _t >= _handoff_until

func _on_gave_up(id: int, reason: String) -> void:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty():
		return
	ledger.release(id)
	_leave(b, _walk("turn" if reason != "closing" else "out", float(b["pace"])))

func _on_served(id: int, item: String, wait_s: float, dine_in: bool, portions: int) -> void:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty():
		return
	if dine_in and int(b["seat"]) >= 0:
		var w := _free_worker()
		if w < 0:
			_settle(b, item, wait_s, true, portions) # cannot happen: pickup_ready checked a server
			return
		# The server walks to the pass, collects, carries and offers: then the money moves.
		_assign(w, _walk("deliver", 1.0), func() -> void:
			if bodies.has(id) and _settle(bodies[id], item, wait_s, true, portions):
				tp.seat_taken(id)
			_assign(w, _walk("back", 1.0), Callable()))
		return
	if _settle(b, item, wait_s, false, portions):
		var hand := Economy.handoff_seconds(int(b["portions"]), _counter_level)
		_handoff_until = _t + hand
		_leave(b, hand + _walk("out", float(b["pace"])))

func _settle(b: Dictionary, item: String, wait_s: float, dine_in: bool, portions: int) -> bool:
	if b["served"]:
		return false
	var spend := float(ctx.get("spend_mult", 1.0)) if dine_in else 1.0
	var sale := ledger.settle(b["id"], item, portions, spend, String(b["wants"]), dine_in, ctx["weather"], rng)
	var sold := int(sale["sold"])
	if sold <= 0:
		stats["sold_out"] += 1
		tp.remove(b["id"])
		if dine_in:
			_release_seat(b)
			_leave(b, _walk("seat_out", float(b["pace"])))
		else:
			_leave(b, _walk("turn", float(b["pace"])))
		return false
	b["served"] = true
	b["portions"] = sold
	stats["revenue"] += float(sale["total"])
	stats["cogs"] += float(sale["cogs"])
	stats["sold"][item] = int(stats["sold"].get(item, 0)) + sold
	for extra in sale["extras"]:
		stats["sold"][extra] = int(stats["sold"].get(extra, 0)) + int(sale["extras"][extra])
	Game.total_served += 1
	stats["served"] += 1
	stats["portions"] += sold
	stats["wait_sum"] += wait_s
	if dine_in:
		stats["dine_in"] += 1
	var price := float(Game.menu[item]["price"])
	stats["satisfaction_sum"] += Economy.satisfaction(Game.quality(item), price / float(Data.MENU_ITEMS[item]["base_price"]),
		clampf(wait_s / float(ctx["patience_s"]), 0.0, 1.0), loc, float(ctx["satisfaction_bonus"]) + (0.05 if dine_in else 0.0))
	return true

func _on_left_seat(id: int) -> int:
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty():
		return -1
	var table := int(_seats[int(b["seat"])]["table"]) if int(b["seat"]) >= 0 else -1
	_release_seat(b)
	_leave(b, _walk("seat_out", float(b["pace"])))
	return table

## Plot.release_seat: a used place needs clearing; the table goes dirty once nobody sits there.
func _release_seat(b: Dictionary) -> void:
	var i := int(b.get("seat", -1))
	if i < 0 or i >= _seats.size() or int(_seats[i]["holder"]) != int(b["id"]):
		return
	b["seat"] = -1
	var s: Dictionary = _seats[i]
	s["holder"] = -1
	s["needs_clean"] = bool(b["served"])
	var table := int(s["table"])
	var used := false
	for other in _seats:
		if int(other["table"]) != table:
			continue
		if int(other["holder"]) >= 0:
			return
		used = used or bool(other["needs_clean"])
	if used:
		_tables[table]["dirty"] = true
		_tables[table]["assigned"] = false

# ---------------------------------------------------------------- restaurant servers

func _free_worker() -> int:
	for i in range(_workers.size()):
		if not _workers[i]["busy"]:
			return i
	return -1

func _assign(w: int, seconds: float, done: Callable) -> void:
	if not done.is_valid() and seconds <= 0.0:
		_workers[w]["busy"] = false
		return
	_workers[w]["busy"] = true
	_workers[w]["until"] = _t + seconds
	_workers[w]["done"] = done

func _staff_idle() -> bool:
	for worker in _workers:
		if worker["busy"]:
			return false
	for table in _tables:
		if table["dirty"]:
			return false
	return true

## Finish jobs that are due; an idle server clears the next dirty table (DiningStaff.step).
func _step_workers() -> void:
	for i in range(_workers.size()):
		var worker: Dictionary = _workers[i]
		if worker["busy"] and _t >= float(worker["until"]):
			worker["busy"] = false
			var done: Callable = worker["done"]
			worker["done"] = Callable()
			if done.is_valid():
				done.call()
		if not worker["busy"]:
			for t in range(_tables.size()):
				if _tables[t]["dirty"] and not _tables[t]["assigned"]:
					_tables[t]["assigned"] = true
					_assign(i, _walk("clean", 1.0), _clear_table.bind(t))
					break

func _clear_table(t: int) -> void:
	_tables[t]["dirty"] = false
	_tables[t]["assigned"] = false
	for s in _seats:
		if int(s["table"]) == t:
			s["needs_clean"] = false

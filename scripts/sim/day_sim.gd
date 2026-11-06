class_name DaySim
extends Node
## Runs one business day: clock, passers-by, decisions, the counter -> kitchen -> seat
## pipeline (Throughput), sales, reactions.

signal clock_changed(hour: float)
signal stats_changed(stats: Dictionary)
signal event(text: String, kind: String)
signal sale_completed(items: Array[String], total: float)
signal finished(stats: Dictionary)

var world: World
var ctx: Dictionary
var loc: Dictionary
var weather_def: Dictionary
var hour: float = 10.0
var end_hour: float = 22.0
var running := false
const FINISH_SPEED := 12.0
const SHOWCASE_BEATS := [0.10, 0.28, 0.46, 0.64, 1.10, 4.75, 6.20, 7.40]
var finishing := false
var stats: Dictionary = {}
var tp: Throughput
var _rng := RandomNumberGenerator.new()
var _car_timer := 0.0
var _ambient_timer := 0.0
var _warned := {}
var _stats_tick := 0.0
var _hot_min: Dictionary = {}
var _seat_of: Dictionary = {}   # customer -> seat dictionary from the plot
var _handoff_left := 0.0
var _showcase_time := 0.0
var _showcase_step := 0

func start(context: Dictionary, w: World) -> void:
	world = w
	finishing = false
	world.set_customer_speed(1.0)
	ctx = context
	loc = Data.LOCATIONS[ctx["location"]]
	weather_def = Data.WEATHER[ctx["weather"]]
	hour = float(ctx["hours"][0])
	end_hour = float(ctx["hours"][1])
	stats = {"passers": 0, "served": 0, "revenue": 0.0, "cogs": 0.0, "sold": {}, "satisfaction_sum": 0.0,
		"left_wait": 0, "sold_out": 0, "queue_full": 0, "lost_rival": 0, "too_pricey": 0, "dine_in": 0, "queue": 0, "kitchen": 0, "seated": 0}
	_warned.clear()
	_stats_tick = 0.0
	_hot_min.clear()
	_seat_of.clear()
	_handoff_left = 0.0
	_showcase_time = 0.0
	_showcase_step = 0 if DevTools.has("character-demo") and Game.day == 1 else SHOWCASE_BEATS.size()
	_rng.randomize()
	tp = Throughput.new()
	ctx["visual"] = true
	tp.setup(ctx, _rng)
	tp.on_served = _on_served
	tp.on_gave_up = _on_gave_up
	tp.on_ordered = _on_ordered
	tp.on_left_seat = _on_left_seat
	tp.counter_ready = _counter_ready
	tp.pickup_ready = _pickup_ready
	tp.waiting_in_line = _waiting_in_line
	running = true
	_car_timer = 1.0
	_ambient_timer = 2.0
	world.set_time(hour, ctx["weather"])
	clock_changed.emit(hour)
	stats_changed.emit(stats)

func _process(delta: float) -> void:
	if not running:
		return
	if finishing:
		delta *= FINISH_SPEED
	_handoff_left = move_toward(_handoff_left, 0.0, delta)
	var game_min := delta * 60.0 / Data.REAL_SECONDS_PER_GAME_HOUR
	hour += game_min / 60.0
	if not finishing:
		world.set_time(hour, ctx["weather"])
		clock_changed.emit(hour)
	# passers-by
	if not finishing and _showcase_step < SHOWCASE_BEATS.size():
		_showcase_time += delta
		while _showcase_step < SHOWCASE_BEATS.size() and _showcase_time >= SHOWCASE_BEATS[_showcase_step]:
			_showcase_guest(_showcase_step)
			_showcase_step += 1
	else:
		var per_hour := Economy.arrival_rate(loc, ctx["weather"], hour, ctx)
		var expected := per_hour * delta / Data.REAL_SECONDS_PER_GAME_HOUR
		# Whole arrivals plus a fractional chance, including during Skip.
		var arrivals := int(expected) + (1 if _rng.randf() < expected - int(expected) else 0)
		for i in range(arrivals):
			_spawn_passer()
	# background life
	if not finishing:
		_car_timer -= delta
		if _car_timer <= 0.0:
			world.spawn_car()
			_car_timer = _rng.randf_range(2.5, 7.0) / maxf(0.4, float(loc["traffic"]))
		_ambient_timer -= delta
		if _ambient_timer <= 0.0:
			if not DevTools.has("character-demo") and world.walkers < World.MAX_WALKERS:
				world.spawn_walker(1 if _rng.randf() < 0.5 else -1, false)
			_ambient_timer = _rng.randf_range(3.0, 9.0) / maxf(0.4, float(loc["traffic"]))
	# the pipeline
	var before := tp.queue_payloads()
	var before_pickup := tp.waiting_payloads()
	tp.tick(game_min, hour)
	if before != tp.queue_payloads():
		_reflow()
	var pickup := tp.waiting_payloads()
	if before_pickup != pickup:
		for i in range(pickup.size()):
			var customer := pickup[i] as Customer
			if is_instance_valid(customer) and customer.slot != 100 + i:
				customer.go_to_slot(100 + i, world.pickup_slot(i))
	_bottleneck_watch(game_min)
	_stats_tick += delta / FINISH_SPEED if finishing else delta
	if _stats_tick > 0.25:
		_stats_tick = 0.0
		if finishing:
			world.set_time(minf(hour, end_hour), ctx["weather"])
			clock_changed.emit(hour)
		stats["queue"] = tp.queue_len()
		stats["kitchen"] = pickup.size()
		var seated := 0
		for diner in tp.seated:
			if diner.get("active", true):
				seated += 1
		stats["seated"] = seated
		stats_changed.emit(stats)
	if hour >= end_hour:
		_close()

## Continue this day's existing pipeline and inventory, with no new 3D presentation.
func finish_quickly() -> bool:
	if not running or finishing:
		return false
	finishing = true
	world.set_customer_speed(FINISH_SPEED)
	if world.cart:
		world.cart.set_serving(false)
	return true

func _stop_chance(best: float, queue_len: int) -> float:
	return Economy.stop_probability(float(ctx["popularity"]), best * float(ctx["appeal"]), float(ctx["boost"]), queue_len,
		int(ctx["queue_cap"]), float(ctx["competition"]), float(ctx["promo_power"]))

func _spawn_passer() -> void:
	stats["passers"] = int(stats["passers"]) + 1
	if DevTools.has("character-demo") and not finishing and world.walkers >= World.MAX_RIGGED_GUESTS:
		return
	var forced := false
	if world.walkers >= World.MAX_WALKERS:
		# Too crowded to show everyone: decide now, only show the ones who stop.
		var cands := Game.candidates("food")
		var best := 0.0
		for cand in cands:
			best = maxf(best, float(cand["value"]))
		if _rng.randf() >= _stop_chance(best, tp.queue_len()):
			return
		forced = true
	var c := world.spawn_walker(1 if _rng.randf() < 0.5 else -1, true, not finishing)
	c.forced_stop = forced
	c.reached_decision.connect(_on_decision)
	c.gone.connect(_on_gone)

func _on_decision(c: Customer) -> void:
	if not running:
		return
	c.wants = "drink" if _rng.randf() < Economy.drink_share(ctx["weather"]) else "food"
	var cands := Game.candidates(c.wants)
	var best := 0.0
	var best_price_ratio := 1.0
	var any_stock := false
	for cand in cands:
		if float(cand["value"]) > best:
			best = float(cand["value"])
			var id: String = cand["id"]
			best_price_ratio = float(Game.menu[id]["price"]) / float(Data.MENU_ITEMS[id]["base_price"])
		if int(cand["stock"]) > 0:
			any_stock = true
	if cands.is_empty():
		return
	var p := _stop_chance(best, tp.queue_len())
	var p_if_room := _stop_chance(best, 0)
	var p_no_rivals := Economy.stop_probability(float(ctx["popularity"]), best * float(ctx["appeal"]), float(ctx["boost"]), 0, int(ctx["queue_cap"]))
	var r := _rng.randf()
	if c.forced_stop:
		r = 0.0
	# lost to a rival stall: would have stopped if there were no competition
	if r >= p_if_room and r < p_no_rivals and float(ctx["competition"]) > 0.0:
		stats["lost_rival"] = int(stats["lost_rival"]) + 1
		if _rng.randf() < 0.35:
			c.say(Data.pick_bubble("rival", _rng), Color(1.0, 0.75, 0.5))
		_warn("rival", tr("ev.rival"))
		return
	if r < p or (c.forced_stop and not tp.is_full()):
		if not any_stock:
			stats["sold_out"] = int(stats["sold_out"]) + 1
			_reject(c, "sold_out", "price", Color("efa36f"))
			_warn("sold_out", tr("ev.sold_out_all"))
			return
		c.item = Economy.pick_weighted(cands, _rng)
		if tp.enqueue(c, c.item):
			var i := tp.queue_len() - 1
			c.go_to_slot(i, world.queue_slot(i))
		else:
			stats["queue_full"] = int(stats["queue_full"]) + 1
			_reject(c, "queue_full", "line-full", Color("ffc17d"))
	elif r < p_if_room and tp.is_full():
		stats["queue_full"] = int(stats["queue_full"]) + 1
		_reject(c, "queue_full", "line-full", Color("ffc17d"))
		_warn("queue_full", tr("ev.queue_full"))
	elif r < p_if_room * 1.5 and best < 0.55 and best_price_ratio > 1.20:
		_reject(c, "too_pricey", "price", Color("ffab81"))
		stats["too_pricey"] = int(stats.get("too_pricey", 0)) + 1
	elif _rng.randf() < 0.08:
		match ctx["weather"]:
			"hot": c.say(Data.pick_bubble("hot", _rng), Color(1, 0.8, 0.4))
			"sandstorm": c.say(Data.pick_bubble("sandstorm", _rng), Color(1, 0.85, 0.6))
			"breeze": c.say(Data.pick_bubble("breeze", _rng), Color(0.8, 0.95, 1))

func _on_gone(c: Customer) -> void:
	tp.remove(c)
	_release_seat(c)

## Someone in line ran out of patience (or the day ended).
func _on_gave_up(payload, reason: String) -> void:
	var c := payload as Customer
	if c == null or not is_instance_valid(c):
		return
	if reason == "closing":
		c.leave(tr("ev.closing"), Color(0.9, 0.9, 0.9), false)
		return
	stats["left_wait"] = int(stats["left_wait"]) + 1
	_reject(c, "too_slow", "angry", Color("ff9384"))
	_warn("slow", tr("ev.slow"))

func _reject(c: Customer, bubble_key: String, clip: String, color: Color) -> void:
	c.reject(world.queue_slot(0) + Vector3.FORWARD * 0.4, clip, Data.pick_bubble(bubble_key, _rng), color)

## The demo opens with a repeatable rush so players see every beat in one visit.
func _showcase_guest(step: int) -> void:
	var choices := Game.candidates("food")
	if choices.is_empty():
		return
	var item: String = choices[0]["id"]
	var i := tp.queue_len()
	var start := world.queue_slot(i) + Vector3(0.27, 0, 0.30)
	if step == 4 or step == 5:
		var lane := World.ARRIVAL_Z if Paving.DESIGNS.has(world.location_id) else World.WALK_Z
		start = Vector3(1.67 if step == 4 else 1.24, 0, lane)
	var guest := world.spawn_guest(-1, start)
	guest.decided = true
	guest.gone.connect(_on_gone)
	stats["passers"] += 1
	var price := float(Game.menu[item]["price"])
	if step == 5 and price > float(Data.MENU_ITEMS[item]["base_price"]) * 0.8:
		stats["too_pricey"] += 1
		guest.reject(world.queue_slot(0), "price", tr("bubble.quoted_price") % Loc.money(price), Color("ffab81"))
		return
	guest.item = item
	if tp.enqueue(guest, guest.item):
		guest.go_to_slot(i, world.queue_slot(i))
	else:
		stats["queue_full"] += 1
		_reject(guest, "queue_full", "line-full", Color("ffc17d"))

func _waiting_in_line(payload: Customer) -> bool:
	return finishing or not is_instance_valid(payload) or payload.state == Customer.State.QUEUED

func _counter_ready(payload: Customer) -> bool:
	if finishing or not is_instance_valid(payload):
		return true
	if _showcase_step < SHOWCASE_BEATS.size() and _showcase_time < 1.35:
		return false
	if payload.slot != 0 or payload.state != Customer.State.QUEUED:
		return false
	if not payload.order_shown:
		payload.order_shown = true
		payload.say(tr(Data.MENU_ITEMS[payload.item]["name"]), Color("ffe4ab"), 0.30, 0.90)
		payload.perform("order", "interact-right", 0.48)
	return payload.beat_left == 0.0

func _pickup_ready(payload: Customer) -> bool:
	if finishing or not is_instance_valid(payload):
		return true
	return _handoff_left == 0.0 and payload.slot == 100 and payload.state == Customer.State.QUEUED

## Order taken: step aside to the pickup spot while the kitchen cooks.
func _on_ordered(payload, _station: String) -> void:
	var c := payload as Customer
	if c == null or not is_instance_valid(c):
		return
	var i := tp.waiting_payloads().find(c)
	c.go_to_slot(100 + maxi(i, 0), world.pickup_slot(maxi(i, 0)))

func _reflow() -> void:
	var line := tp.queue_payloads()
	for i in range(line.size()):
		var c := line[i] as Customer
		if c == null or not is_instance_valid(c):
			continue
		if c.state == Customer.State.QUEUED or c.state == Customer.State.TO_SLOT:
			if c.slot != i:
				c.go_to_slot(i, world.queue_slot(i))

## Food handed over: sell, add-ons, satisfaction, then sit down or walk away.
func _on_served(payload, item: String, wait_min: float, dine_in: bool) -> void:
	var c := payload as Customer
	var price := float(Game.menu[item]["price"])
	if not Game.sell(item, price):
		stats["sold_out"] = int(stats["sold_out"]) + 1
		if c != null and is_instance_valid(c):
			_reject(c, "sold_out", "price", Color("efa36f"))
		_warn("sold_out", tr("ev.sold_out_item") % tr(Data.MENU_ITEMS[item]["name"]))
		tp.remove(payload)
		return
	var spend := float(ctx.get("spend_mult", 1.0)) if dine_in else 1.0
	var total := price * spend
	var cogs := Game.unit_cost(item)
	var sold_items: Array[String] = [item]
	stats["sold"][item] = int(stats["sold"].get(item, 0)) + 1
	var wants := c.wants if c != null and is_instance_valid(c) else "food"
	for extra in _addons(wants, c, dine_in):
		var ep := float(Game.menu[extra]["price"])
		if Game.sell(extra, ep):
			sold_items.append(extra)
			total += ep
			cogs += Game.unit_cost(extra)
			stats["sold"][extra] = int(stats["sold"].get(extra, 0)) + 1
	stats["revenue"] = float(stats["revenue"]) + total
	stats["cogs"] = float(stats["cogs"]) + cogs
	stats["served"] = int(stats["served"]) + 1
	if dine_in:
		stats["dine_in"] = int(stats["dine_in"]) + 1
	var ratio := price / float(Data.MENU_ITEMS[item]["base_price"])
	var wait_ratio := clampf(wait_min / float(ctx["patience_min"]), 0.0, 1.0)
	var s := Economy.satisfaction(Game.quality(item), ratio, wait_ratio, loc, float(ctx["satisfaction_bonus"]) + (0.05 if dine_in else 0.0))
	stats["satisfaction_sum"] = float(stats["satisfaction_sum"]) + s
	var key := Economy.bubble_for_satisfaction(s)
	var col := Color(0.35, 0.85, 0.4) if key == "great" else (Color(1, 1, 1) if key == "ok" else Color(0.95, 0.5, 0.3))
	var text := Data.pick_bubble(key, _rng)
	if key == "great":
		text += "  +" + Loc.money(total)
	if not finishing:
		Sfx.play("coin", -10.0, randf_range(0.95, 1.1))
	_check_stock_warnings()
	if not finishing:
		sale_completed.emit(sold_items, total)
	if c == null or not is_instance_valid(c):
		return
	if running and not finishing and c.model:
		_handoff_left = 0.72
		world.handoff(c, sold_items)
		c.say(text, col, 0.46)
		c.perform("collect", "pick-up", 0.72, _after_pickup.bind(c, dine_in))
	else:
		_after_pickup(c, dine_in)

func _after_pickup(c: Customer, dine_in: bool) -> void:
	if not running:
		c.leave()
		return
	var seat := _take_seat(c) if dine_in else {}
	if dine_in and not seat.is_empty():
		c.go_to_seat(seat)
		if not c.arrived.is_connected(_on_sat):
			c.arrived.connect(_on_sat)
	else:
		if dine_in:
			tp.remove(c) # no visual seat: eat on the go
		c.leave()

func _on_sat(c: Customer) -> void:
	if c.state == Customer.State.SEATED:
		tp.seat_taken(c)
		if world.plot and _seat_of.has(c):
			world.plot.show_meal(int(_seat_of[c]["table"]))

func _take_seat(c: Customer) -> Dictionary:
	if world.plot == null or not world.plot.has_method("free_seat"):
		return {}
	var seat: Dictionary = world.plot.free_seat()
	if seat.is_empty():
		return {}
	world.plot.take_seat(int(seat["idx"]), c)
	_seat_of[c] = seat
	return seat

func _release_seat(c: Customer) -> void:
	if not _seat_of.has(c):
		return
	var seat: Dictionary = _seat_of[c]
	_seat_of.erase(c)
	if world.plot != null:
		world.plot.release_seat(int(seat["idx"]), c)

## Done eating: the table is left dirty and the guest walks off.
func _on_left_seat(payload) -> void:
	var c := payload as Customer
	if c == null or not is_instance_valid(c):
		return
	_release_seat(c)
	c.react("emote-yes")
	c.leave_from_seat(Data.pick_bubble("dine_in", _rng), Color(0.6, 0.9, 0.6))

func _addons(wants: String, c, dine_in: bool) -> Array:
	var out := []
	if wants != "food":
		return out
	var bonus := 0.25 if dine_in else 0.0
	var drink_p := 0.3
	if ctx["weather"] == "hot":
		drink_p = 0.65
	elif ctx["weather"] == "breeze":
		drink_p = 0.2
	var sides := []
	for id in ["salad", "fries"]:
		if Game.is_on_sale(id) and Game.portions_possible(id) > 0:
			sides.append(id)
	if not sides.is_empty():
		var side: String = sides[_rng.randi_range(0, sides.size() - 1)]
		if _rng.randf() < (0.4 + bonus) * _addon_appeal(side):
			out.append(side)
	var drinks := []
	for id in ["soda", "laban", "karak"]:
		if Game.is_on_sale(id) and Game.portions_possible(id) > 0:
			drinks.append(id)
	if not drinks.is_empty():
		var pick: String = drinks[_rng.randi_range(0, drinks.size() - 1)]
		if _rng.randf() < (drink_p + bonus) * _addon_appeal(pick):
			out.append(pick)
	var sweets := []
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "sweet" and Game.is_on_sale(id) and Game.portions_possible(id) > 0:
			sweets.append(id)
	if not sweets.is_empty():
		var sw: String = sweets[_rng.randi_range(0, sweets.size() - 1)]
		if _rng.randf() < (0.35 + bonus) * _addon_appeal(sw):
			out.append(sw)
			if _rng.randf() < 0.3 and c != null and is_instance_valid(c):
				c.say(Data.pick_bubble("sweet", _rng), Color(1.0, 0.85, 0.6))
	return out

## 0..1 willingness to add an extra item, falling off as its price climbs above fair.
func _addon_appeal(id: String) -> float:
	var ratio := float(Game.menu[id]["price"]) / float(Data.MENU_ITEMS[id]["base_price"])
	return clampf(1.6 - ratio * 0.9, 0.0, 1.0)

## A stage that stays saturated for 20 game-minutes earns one "upgrade it" warning.
func _bottleneck_watch(game_min: float) -> void:
	var cap := int(ctx["queue_cap"])
	var hot := {"counter": tp.queue_len() >= cap - 1}
	for s in tp.backlog:
		hot[s] = tp.backlog[s].size() >= 4
	if int(ctx.get("seats", 0)) > 0:
		hot["seating"] = tp.seats_free() <= 0
	for s in hot:
		_hot_min[s] = (float(_hot_min.get(s, 0.0)) + game_min) if hot[s] else 0.0
		if _hot_min[s] >= 20.0:
			var name := tr("station.%s" % s) if Data.STATIONS.has(s) else tr("station.seating")
			_warn("bottleneck_" + s, tr("ev.bottleneck") % name)

func _check_stock_warnings() -> void:
	for id in Data.MENU_ITEMS:
		if Game.is_on_sale(id) and Game.portions_possible(id) == 0:
			_warn("out_" + id, tr("ev.out_of") % tr(Data.MENU_ITEMS[id]["name"]))

func _warn(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	if not finishing:
		event.emit(text, "warn")

func _close() -> void:
	running = false
	tp.flush()
	for c in _seat_of.keys():
		if is_instance_valid(c):
			_release_seat(c)
			c.leave_from_seat(tr("ev.closing"), Color(0.9, 0.9, 0.9))
	if world.cart:
		world.cart.set_serving(false)
	if finishing:
		world.clear_virtual_walkers()
	world.set_time(end_hour, ctx["weather"])
	clock_changed.emit(end_hour)
	stats["left_wait"] = int(stats["left_wait"]) # already counted as they gave up
	stats["util"] = tp.utilisation()
	stats["max_queue"] = int(tp.stats["max_queue"])
	stats_changed.emit(stats)
	finished.emit(stats)

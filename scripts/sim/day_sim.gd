class_name DaySim
extends Node
## Runs one business day: clock, passers-by, decisions, the counter -> kitchen -> seat
## pipeline (Throughput), sales, reactions. Every beat is in sim-seconds (Data.SERVICE),
## and every sale belongs to a rigged buyer on the street.

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
const STEP := 1.0 / 60.0
const MAX_FRAME_TIME := 0.1
const MAX_TICKS_PER_FRAME := 32
var _accumulator := 0.0
var playback_speed := 1.0
var _life_rng := RandomNumberGenerator.new()
var _seeded_movement := false
var _car_timer := 0.0
var _ambient_timer := 0.0
var _warned := {}
var _stats_tick := 0.0
var _hot_min: Dictionary = {}
var _seat_of: Dictionary = {}   # customer -> seat dictionary from the plot
var _handoff_left := 0.0
var _closing := false
var _pending_deliveries := {}
var ledger := StockLedger.new()
var _street_sum := 0.0
var _street_ticks := 0
var purchase_log: Array[Dictionary] = []
var _showcase_time := 0.0
var _showcase_step := 0

func start(context: Dictionary, w: World) -> void:
	world = w
	finishing = false
	_closing = false
	_pending_deliveries.clear()
	ledger.clear()
	purchase_log.clear()
	_street_sum = 0.0
	_street_ticks = 0
	world.reset_day_guests()
	world.set_day_managed(true)
	_accumulator = 0.0
	_seeded_movement = false
	playback_speed = 1.0
	ctx = context
	if world.plot:
		ctx["seats"] = mini(int(ctx["seats"]), world.plot.seats.size())
	loc = Data.LOCATIONS[ctx["location"]]
	weather_def = Data.WEATHER[ctx["weather"]]
	var stage := int(ctx.get("stage", 0))
	var counter_level := int(ctx.get("counter_level", 0))
	world.configure_guests(int(ctx.get("buyers", Economy.buyer_budget(stage, counter_level))), Economy.ambient_budget(stage))
	if not ctx.has("party"):
		ctx["party"] = Economy.party_weights(stage, String(ctx["location"]))
	if not ctx.has("patience_s"):
		ctx["patience_s"] = float(Data.SERVICE["patience_s"]) * float(loc.get("patience", 1.0))
	hour = float(ctx["hours"][0])
	end_hour = float(ctx["hours"][1])
	stats = {"_day": int(ctx.get("day", Game.day)), "passers": 0, "served": 0, "portions": 0, "revenue": 0.0, "cogs": 0.0, "sold": {},
		"satisfaction_sum": 0.0, "wait_sum": 0.0, "left_wait": 0, "sold_out": 0, "queue_full": 0, "lost_rival": 0, "too_pricey": 0,
		"crowd": 0, "dine_in": 0, "queue": 0, "kitchen": 0, "seated": 0}
	_warned.clear()
	_stats_tick = 0.0
	_hot_min.clear()
	_seat_of.clear()
	_handoff_left = 0.0
	_showcase_time = 0.0
	_showcase_step = 0 if DevTools.has("character-demo") and Game.day == 1 else SHOWCASE_BEATS.size()
	if Game.day_seed > 0:
		_rng.seed = Game.day_seed
	else:
		_rng.randomize()
	if DevTools.has("sim-seed"):
		_rng.seed = int(DevTools.get_flag("sim-seed"))
	tp = Throughput.new()
	ctx["visual"] = true
	tp.setup(ctx, _rng)
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
	tp.table_clean = _table_clean
	if world.plot:
		world.plot.service_open = true
		world.plot.service_stats = {"deliveries": 0, "cleaned": 0}
	running = true
	_car_timer = 1.0
	_ambient_timer = 2.0
	world.set_time(hour, ctx["weather"])
	clock_changed.emit(hour)
	stats_changed.emit(stats)

## All business actors consume identical fixed simulation ticks at every speed.
func set_playback_speed(value: float) -> void:
	playback_speed = maxf(value, 0.01)

func effective_speed() -> float:
	if playback_speed <= 2.0:
		return playback_speed
	if _handoff_left > 0.0:
		return 2.0
	if is_instance_valid(world):
		for guest in world.active_guests:
			if is_instance_valid(guest) and guest.state != Customer.State.DONE and guest.beat_left > 0.0:
				return 2.0
		if world.plot:
			for worker in world.plot.dining_staff:
				if worker.state == DiningStaff.State.COLLECT or worker.state == DiningStaff.State.DELIVER or worker.state == DiningStaff.State.CLEAN:
					return 2.0
	return playback_speed

func _process(delta: float) -> void:
	if not running:
		return
	_accumulator += minf(delta, MAX_FRAME_TIME)
	var ticks := 0
	var tick_time := _tick_time()
	while running and _accumulator + 0.0000001 >= tick_time and ticks < MAX_TICKS_PER_FRAME:
		_accumulator = maxf(0.0, _accumulator - tick_time)
		advance_tick()
		ticks += 1
		if running:
			tick_time = _tick_time()
	if ticks == MAX_TICKS_PER_FRAME:
		# Keep a partial tick. A hitch must not leave a backlog of full ticks.
		_accumulator = fmod(_accumulator, tick_time)
	if running:
		if ticks > 0:
			world.render_service()
			if not _closing:
				world.set_time(hour, ctx["weather"])
				clock_changed.emit(hour)
		_stats_tick += delta
		if _stats_tick >= 0.25:
			_stats_tick = fmod(_stats_tick, 0.25)
			_emit_stats()

## Wall-clock seconds one tick takes right now; ambient poses read the same pace.
func _tick_time() -> float:
	ModelLib.sim_speed = effective_speed()
	return STEP / ModelLib.sim_speed

## One fixed step for every business actor. Also driven directly by headless runs.
func advance_tick() -> void:
	if not _seeded_movement:
		world.guest_rng.seed = _rng.seed ^ 73691
		_life_rng.seed = _rng.seed ^ 97231
		_seeded_movement = true
	world.step_service(STEP)
	if world.plot:
		for worker in world.plot.dining_staff:
			worker.step(STEP)
	for guest in world.active_guests:
		if is_instance_valid(guest) and guest.state != Customer.State.DONE:
			guest.step(STEP)
	_tick(STEP)

func _tick(delta: float) -> void:
	_handoff_left = move_toward(_handoff_left, 0.0, delta)
	var game_min := delta * 60.0 / Data.REAL_SECONDS_PER_GAME_HOUR
	if not _closing:
		hour = minf(end_hour, hour + game_min / 60.0)
	# passers-by
	if not _closing and _showcase_step < SHOWCASE_BEATS.size():
		_showcase_time += delta
		while _showcase_step < SHOWCASE_BEATS.size() and _showcase_time >= SHOWCASE_BEATS[_showcase_step]:
			_showcase_guest(_showcase_step)
			_showcase_step += 1
	elif not _closing:
		var per_hour := Economy.arrival_rate(loc, ctx["weather"], hour, ctx)
		var expected := per_hour * delta / Data.REAL_SECONDS_PER_GAME_HOUR
		# Whole arrivals plus a fractional chance, including during Skip.
		var arrivals := int(expected) + (1 if _rng.randf() < expected - int(expected) else 0)
		for i in range(arrivals):
			_spawn_passer()
	# background life: cars and walkers that never buy, on their own budget
	if not _closing:
		_street_sum += float(world.buyers_on_street()) / float(maxi(world.buyer_limit, 1))
		_street_ticks += 1
		_car_timer -= delta
		if _car_timer <= 0.0:
			world.spawn_car()
			_car_timer = _life_rng.randf_range(2.5, 7.0) / maxf(0.4, float(loc["traffic"]))
		_ambient_timer -= delta
		if _ambient_timer <= 0.0:
			if not DevTools.has("character-demo") and world.walkers < World.MAX_WALKERS and world.ambient_room() > 0:
				world.spawn_walker(1 if _life_rng.randf() < 0.5 else -1, false)
			_ambient_timer = _life_rng.randf_range(3.0, 9.0) / maxf(0.4, float(loc["traffic"]))
	# the pipeline, in sim-seconds
	var before := tp.queue_payloads()
	var before_pickup := tp.waiting_payloads()
	tp.tick(delta, hour)
	if before != tp.queue_payloads():
		_reflow()
	var pickup := tp.waiting_payloads()
	if before_pickup != pickup:
		for i in range(pickup.size()):
			var customer := pickup[i] as Customer
			if is_instance_valid(customer) and not _seat_of.has(customer) and customer.slot != 100 + i \
					and (customer.state == Customer.State.QUEUED or customer.state == Customer.State.TO_SLOT):
				customer.go_to_slot(100 + i, world.pickup_slot(i))
	_bottleneck_watch(game_min)
	if hour >= end_hour and not _closing:
		_close()
	if _closing and not tp.has_orders() and tp.seated.is_empty() and _pending_deliveries.is_empty() and _handoff_left == 0.0:
		if world.plot == null or (not world.plot.staff_busy() and world.plot.dirty_tables().is_empty()):
			_publish_close()

func _emit_stats() -> void:
	stats["queue"] = tp.queue_len()
	stats["kitchen"] = tp.waiting_payloads().size()
	var seated := 0
	for diner in tp.seated:
		if diner.get("active", true):
			seated += 1
	stats["seated"] = seated
	stats_changed.emit(stats)

## Advance the clock while every buyer still reaches the counter or their table.
func finish_quickly() -> bool:
	if not running or finishing:
		return false
	finishing = true
	set_playback_speed(FINISH_SPEED)
	return true

func _stop_chance(best: float, queue_len: int) -> float:
	return Economy.stop_probability(float(ctx["popularity"]), best * float(ctx["appeal"]), float(ctx["boost"]), queue_len,
		int(ctx["queue_cap"]), float(ctx["competition"]), float(ctx["promo_power"]))

## Items of a kind on sale with their value today and the portions nobody is waiting for.
func _candidates(wants: String) -> Array:
	var cands := Game.candidates(wants)
	for cand in cands:
		cand["stock"] = ledger.portions_free(cand["id"])
	return cands

## Best value on offer for a kind of passer, the price ratio of that dish, and stock.
func _look(wants: String) -> Dictionary:
	var out := {"best": 0.0, "ratio": 1.0, "stock": false, "cands": _candidates(wants)}
	for cand in out["cands"]:
		if float(cand["value"]) > float(out["best"]):
			out["best"] = float(cand["value"])
			out["ratio"] = float(Game.menu[cand["id"]]["price"]) / float(Data.MENU_ITEMS[cand["id"]]["base_price"])
		if int(cand["stock"]) > 0:
			out["stock"] = true
	return out

## A passer arrives. Only those who would stop get one of the street's buyer places; when
## the street is full they walk on unseen (a crowd turn-away). A would-be rival or price
## refusal is shown only while the street has room to spare, so it never costs a sale.
func _spawn_passer() -> void:
	stats["passers"] = int(stats["passers"]) + 1
	var wants := "drink" if _rng.randf() < Economy.drink_share(ctx["weather"]) else "food"
	var look := _look(wants)
	var best := float(look["best"])
	var r := _rng.randf()
	var p_room := _stop_chance(best, 0)
	var p_any := Economy.stop_probability(float(ctx["popularity"]), best * float(ctx["appeal"]), float(ctx["boost"]), 0, int(ctx["queue_cap"]))
	var visit := ""
	if r < p_room:
		visit = "buyer"
	elif r < p_any and float(ctx["competition"]) > 0.0:
		stats["lost_rival"] = int(stats["lost_rival"]) + 1
		_warn("rival", tr("ev.rival"))
		visit = "rival"
	elif best < 0.55 and float(look["ratio"]) > 1.20 and r < p_room * 1.5:
		stats["too_pricey"] = int(stats.get("too_pricey", 0)) + 1
		visit = "pricey"
	if visit == "":
		return
	var room := world.buyer_room()
	if visit == "buyer" and room <= 0:
		stats["crowd"] = int(stats["crowd"]) + 1
		return
	if visit != "buyer" and room < int(Data.GUEST_BUDGET["spare_for_reactions"]):
		return
	var c := world.spawn_walker(1 if _rng.randf() < 0.5 else -1)
	if c.model == null:
		c._finish()
		return
	c.wants = wants
	c.visit = visit
	c.decision_roll = r
	c.reached_decision.connect(_on_decision)
	c.gone.connect(_on_gone)

func _on_decision(c: Customer) -> void:
	if not running or _closing or c.model == null:
		return
	if c.visit == "rival":
		if _life_rng.randf() < 0.35:
			c.say(Data.pick_bubble("rival", _life_rng), Color(1.0, 0.75, 0.5))
		return
	if c.visit == "pricey":
		_reject(c, "too_pricey", "price", Color("ffab81"))
		return
	if c.decision_roll < 0.0:
		c.wants = "drink" if _rng.randf() < Economy.drink_share(ctx["weather"]) else "food"
	var look := _look(c.wants)
	var cands: Array = look["cands"]
	if cands.is_empty():
		return
	var p := _stop_chance(float(look["best"]), tp.queue_len())
	var r := c.decision_roll if c.decision_roll >= 0.0 else _rng.randf()
	if c.forced_stop:
		r = 0.0
	if tp.is_full():
		stats["queue_full"] = int(stats["queue_full"]) + 1
		_reject(c, "queue_full", "line-full", Color("ffc17d"))
		_warn("queue_full", tr("ev.queue_full"))
	elif r < p or c.forced_stop:
		if not bool(look["stock"]):
			stats["sold_out"] = int(stats["sold_out"]) + 1
			_reject(c, "sold_out", "price", Color("efa36f"))
			_warn("sold_out", tr("ev.sold_out_all"))
			return
		c.item = Economy.pick_weighted(cands, _rng)
		c.portions = Economy.pick_party(ctx["party"], _rng)
		if tp.enqueue(c, c.item, c.portions):
			var i := tp.queue_len() - 1
			c.go_to_slot(i, world.queue_slot(i))
	elif _life_rng.randf() < 0.08:
		match ctx["weather"]:
			"hot": c.say(Data.pick_bubble("hot", _life_rng), Color(1, 0.8, 0.4))
			"sandstorm": c.say(Data.pick_bubble("sandstorm", _life_rng), Color(1, 0.85, 0.6))
			"breeze": c.say(Data.pick_bubble("breeze", _life_rng), Color(0.8, 0.95, 1))

func _on_gone(c: Customer) -> void:
	tp.remove(c)
	ledger.release(c)
	_pending_deliveries.erase(c)
	_release_seat(c)

## Someone in line ran out of patience (or the day ended).
func _on_gave_up(payload, reason: String) -> void:
	var c := payload as Customer
	if c == null or not is_instance_valid(c):
		return
	ledger.release(c)
	if reason == "closing":
		c.leave(tr("ev.closing"), Color(0.9, 0.9, 0.9), false)
		return
	stats["left_wait"] = int(stats["left_wait"]) + 1
	_reject(c, "too_slow", "angry", Color("ff9384"))
	_warn("slow", tr("ev.slow"))

func _reject(c: Customer, bubble_key: String, clip: String, color: Color) -> void:
	c.reject(world.queue_slot(0) + Vector3.FORWARD * 0.4, clip, Data.pick_bubble(bubble_key, _life_rng), color)

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
	if tp.enqueue(guest, guest.item, guest.portions):
		guest.go_to_slot(i, world.queue_slot(i))
	else:
		stats["queue_full"] += 1
		_reject(guest, "queue_full", "line-full", Color("ffc17d"))

## Standing behind someone is waiting. Walking up, and giving your own order, are not.
func _waiting_in_line(payload: Customer) -> bool:
	return is_instance_valid(payload) and payload.state == Customer.State.QUEUED and payload.slot > 0

## The kitchen is only keeping someone waiting once they stand at the pickup spot or sit.
func _waiting_for_food(payload: Customer) -> bool:
	if not is_instance_valid(payload):
		return false
	return payload.state == Customer.State.SEATED or (payload.state == Customer.State.QUEUED and payload.slot >= 100)

## The front buyer gives the order: a beat that lengthens with the party and shortens with
## the counter level. True once it has been given.
func _counter_ready(payload: Customer, portions: int = 1) -> bool:
	if not is_instance_valid(payload) or payload.model == null:
		return false
	if not finishing and _showcase_step < SHOWCASE_BEATS.size() and _showcase_time < 1.35:
		return false
	if payload.slot != 0 or payload.state != Customer.State.QUEUED:
		return false
	if not payload.order_shown:
		payload.order_shown = true
		var name := tr(Data.MENU_ITEMS[payload.item]["name"])
		if portions > 1:
			name = tr("bubble.order_party") % [name, portions]
		payload.say(name, Color("ffe4ab"), 0.30, 0.90)
		payload.perform("order", "interact-right", Economy.order_seconds(portions, int(ctx.get("counter_level", 0))))
	return payload.beat_left == 0.0

## The order is taken: hold the party's portions. Nothing left means a sold-out refusal.
func _take_order(payload: Customer, item: String, portions: int) -> int:
	if not is_instance_valid(payload) or payload.model == null:
		return 0
	var held := ledger.hold(payload, item, portions)
	if held <= 0:
		_sold_out(payload, item)
		return 0
	payload.portions = held
	return held

func _pickup_ready(payload: Customer) -> bool:
	if not is_instance_valid(payload) or payload.model == null:
		return false
	if _seat_of.has(payload):
		return payload.state == Customer.State.SEATED and world.plot.can_deliver()
	return _handoff_left == 0.0 and payload.slot == 100 and payload.state == Customer.State.QUEUED

func _choose_dining(c: Customer, item: String) -> bool:
	if not is_instance_valid(c) or c.model == null or Data.MENU_ITEMS[item]["kind"] != "food":
		return false
	return not _take_seat(c).is_empty()

func _table_clean(table: int) -> bool:
	return world.plot == null or table < 0 or table >= world.plot.tables.size() or not world.plot.tables[table]["dirty"]

## Order taken: step aside to the pickup spot (or walk to the booked chair) while it cooks.
func _on_ordered(payload, _station: String) -> void:
	var c := payload as Customer
	if c == null or not is_instance_valid(c):
		return
	if _seat_of.has(c):
		c.slot = Customer.DINING_SLOT
		c.go_to_seat(_seat_of[c])
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

## Food ready for the buyer: hand the bag over, or send a server to the table.
func _on_served(payload, item: String, wait_s: float, dine_in: bool, portions: int = 1) -> void:
	var c := payload as Customer
	if c == null or not is_instance_valid(c) or c.model == null:
		tp.remove(payload)
		ledger.release(payload)
		return
	if c.purchase_shown or _pending_deliveries.has(c):
		return
	if dine_in and _seat_of.has(c):
		# The meal on the tray stays promised to this table until it lands.
		if not ledger.holds(c) and ledger.hold(c, item, portions) <= 0:
			_sold_out(c, item)
			return
		_pending_deliveries[c] = true
		if not world.plot.deliver_meal(c, item, _deliver_order.bind(c, item, wait_s)):
			_pending_deliveries.erase(c)
			ledger.release(c)
			tp.remove(c)
			_release_seat(c)
			c.leave_from_seat()
		return
	_settle_sale(c, item, wait_s, false, portions)

## True while a whole portion of the item is free to sell (held orders excluded).
func _stock_available(item: String) -> bool:
	return ledger.portions_free(item) > 0

func _deliver_order(c: Customer, item: String, wait_s: float) -> bool:
	_pending_deliveries.erase(c)
	if not is_instance_valid(c) or c.state != Customer.State.SEATED:
		ledger.release(c)
		return false
	if not _settle_sale(c, item, wait_s, true, maxi(ledger.held_portions(c), 1)):
		return false
	tp.seat_taken(c)
	return true

func _sold_out(c: Customer, item: String) -> void:
	stats["sold_out"] = int(stats["sold_out"]) + 1
	tp.remove(c)
	ledger.release(c)
	_release_seat(c)
	if c.state == Customer.State.SEATED:
		c.leave_from_seat(Data.pick_bubble("sold_out", _life_rng), Color("efa36f"))
	else:
		_reject(c, "sold_out", "price", Color("efa36f"))
	_warn("sold_out", tr("ev.sold_out_item") % tr(Data.MENU_ITEMS[item]["name"]))

## The money changes hands: every portion of the party through Game.sell, add-ons per
## portion, one buyer (and one lifetime customer) per completed order.
func _settle_sale(c: Customer, item: String, wait_s: float, dine_in: bool, portions: int = 1) -> bool:
	if c.purchase_shown:
		return false
	var price := float(Game.menu[item]["price"])
	var spend := float(ctx.get("spend_mult", 1.0)) if dine_in else 1.0
	var wants := c.wants if c != null and is_instance_valid(c) else "food"
	var sale := ledger.settle(c, item, portions, spend, wants, dine_in, ctx["weather"], _rng)
	var sold := int(sale["sold"])
	if sold <= 0:
		_sold_out(c, item)
		return false
	var total := float(sale["total"])
	var cogs := float(sale["cogs"])
	var sold_items: Array[String] = []
	sold_items.assign(sale["items"])
	stats["sold"][item] = int(stats["sold"].get(item, 0)) + sold
	for extra in sale["extras"]:
		stats["sold"][extra] = int(stats["sold"].get(extra, 0)) + int(sale["extras"][extra])
	if sale["sweet"] and _life_rng.randf() < 0.3:
		c.say(Data.pick_bubble("sweet", _life_rng), Color(1.0, 0.85, 0.6))
	stats["revenue"] = float(stats["revenue"]) + total
	stats["cogs"] = float(stats["cogs"]) + cogs
	Game.total_served += 1
	stats["served"] = int(stats["served"]) + 1
	stats["portions"] = int(stats["portions"]) + sold
	stats["wait_sum"] = float(stats["wait_sum"]) + wait_s
	if dine_in:
		stats["dine_in"] = int(stats["dine_in"]) + 1
	var ratio := price / float(Data.MENU_ITEMS[item]["base_price"])
	var wait_ratio := clampf(wait_s / float(ctx["patience_s"]), 0.0, 1.0)
	var s := Economy.satisfaction(Game.quality(item), ratio, wait_ratio, loc, float(ctx["satisfaction_bonus"]) + (0.05 if dine_in else 0.0))
	stats["satisfaction_sum"] = float(stats["satisfaction_sum"]) + s
	var key := Economy.bubble_for_satisfaction(s)
	var col := Color(0.35, 0.85, 0.4) if key == "great" else (Color(1, 1, 1) if key == "ok" else Color(0.95, 0.5, 0.3))
	var text := tr(Data.MENU_ITEMS[item]["name"])
	_check_stock_warnings()
	c.purchase_shown = true
	if dine_in:
		c.say(text, col, 0.9)
	else:
		_play_pickup(c, sold_items, text, col, c.leave, sold)
	# Every sale shows its takings over the buyer (visual only; the money is already booked).
	world.sale_pop(c, total)
	if DevTools.has("uitest"):
		purchase_log.append({"customer": c.get_instance_id(), "item": item, "portions": sold, "dineIn": dine_in,
			"visible": c.model.is_visible_in_tree(), "state": c.state, "ordered": c.order_shown})
	_show_receipt(sold_items, total)
	return true

func service_view() -> Dictionary:
	var view := {"served": stats.get("served", 0), "portions": stats.get("portions", 0), "dineIn": stats.get("dine_in", 0),
		"purchases": purchase_log, "closing": _closing, "pending": _pending_deliveries.size(), "workers": [], "dirty": [],
		"deliveries": 0, "cleaned": 0, "buyers": world.buyers_on_street() if world else 0, "buyerLimit": world.buyer_limit if world else 0}
	if world and world.plot:
		view["dirty"] = world.plot.dirty_tables()
		view["deliveries"] = world.plot.service_stats["deliveries"]
		view["cleaned"] = world.plot.service_stats["cleaned"]
		for worker in world.plot.dining_staff:
			view["workers"].append({"state": worker.state, "tray": worker.tray.visible})
	return view

func _show_receipt(items: Array[String], total: float) -> void:
	Sfx.play("coin", -10.0, randf_range(0.95, 1.1))
	sale_completed.emit(items, total)

## The bag changes hands: the hatch is busy for a beat that grows with the party.
func _play_pickup(guest: Customer, items: Array[String], text: String, color: Color, done: Callable, portions: int = 1) -> void:
	var seconds := Economy.handoff_seconds(portions, int(ctx.get("counter_level", 0)))
	_handoff_left = seconds
	world.handoff(guest, items, seconds)
	guest.say(text, color, 0.46)
	guest.perform("collect", "pick-up", seconds, done)

func _take_seat(c: Customer) -> Dictionary:
	if world.plot == null or not world.plot.has_method("free_seat"):
		return {}
	var seat: Dictionary = world.plot.free_seat()
	if seat.is_empty():
		return {}
	world.plot.take_seat(int(seat["idx"]), c)
	c.seat = seat
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
func _on_left_seat(payload) -> int:
	var c := payload as Customer
	if c == null or not is_instance_valid(c):
		return -1
	var table := int(_seat_of.get(c, {}).get("table", -1))
	_release_seat(c)
	c.leave_from_seat(Data.pick_bubble("dine_in", _life_rng), Color(0.6, 0.9, 0.6))
	return table

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
	if _closing:
		return
	_closing = true
	hour = end_hour
	tp.close_queue()
	world.clear_virtual_walkers()
	world.set_time(end_hour, ctx["weather"])
	clock_changed.emit(end_hour)

## A street full of buyers points at the counter (its levels add buyer places), unless a
## kitchen station is the one keeping them there.
static func street_util(util: Dictionary, street: float) -> Dictionary:
	return Economy.street_util(util, street)

func _publish_close() -> void:
	if not running:
		return
	running = false
	world.render_service()
	world.set_day_managed(false)
	if world.plot:
		world.plot.service_open = false
		world.plot.set_serving(false)
	stats["util"] = street_util(tp.utilisation(), _street_sum / float(maxi(_street_ticks, 1)))
	stats["street"] = _street_sum / float(maxi(_street_ticks, 1))
	stats["max_queue"] = int(tp.stats["max_queue"])
	_emit_stats()
	finished.emit(stats)

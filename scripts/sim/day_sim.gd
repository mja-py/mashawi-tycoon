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
const HANDOFF_SECONDS := 0.72
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
var _reserved_ingredients := {}
var purchase_log: Array[Dictionary] = []
var _showcase_time := 0.0
var _showcase_step := 0

func start(context: Dictionary, w: World) -> void:
	world = w
	finishing = false
	_closing = false
	_pending_deliveries.clear()
	_reserved_ingredients.clear()
	purchase_log.clear()
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
	hour = float(ctx["hours"][0])
	end_hour = float(ctx["hours"][1])
	stats = {"_day": int(ctx.get("day", Game.day)), "passers": 0, "served": 0, "revenue": 0.0, "cogs": 0.0, "sold": {}, "satisfaction_sum": 0.0,
		"left_wait": 0, "sold_out": 0, "queue_full": 0, "lost_rival": 0, "too_pricey": 0, "dine_in": 0, "queue": 0, "kitchen": 0, "seated": 0}
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
	tp.counter_ready = _counter_ready
	tp.pickup_ready = _pickup_ready
	tp.waiting_in_line = _waiting_in_line
	tp.dining_choice = _choose_dining
	tp.table_clean = _table_clean
	tp.meal_finished = _meal_finished
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
	if not _seeded_movement:
		world.guest_rng.seed = _rng.seed ^ 73691
		_life_rng.seed = _rng.seed ^ 97231
		_seeded_movement = true
	_accumulator += minf(delta, MAX_FRAME_TIME)
	var ticks := 0
	var tick_time := STEP / effective_speed()
	while running and _accumulator + 0.0000001 >= tick_time and ticks < MAX_TICKS_PER_FRAME:
		_accumulator = maxf(0.0, _accumulator - tick_time)
		world.step_service(STEP)
		if world.plot:
			for worker in world.plot.dining_staff:
				worker.step(STEP)
		for guest in world.active_guests:
			if is_instance_valid(guest) and guest.state != Customer.State.DONE:
				guest.step(STEP)
		_tick(STEP)
		ticks += 1
		if running:
			tick_time = STEP / effective_speed()
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
	# background life
	if not _closing:
		_car_timer -= delta
		if _car_timer <= 0.0:
			world.spawn_car()
			_car_timer = _life_rng.randf_range(2.5, 7.0) / maxf(0.4, float(loc["traffic"]))
		_ambient_timer -= delta
		if _ambient_timer <= 0.0:
			if not DevTools.has("character-demo") and world.walkers < World.MAX_WALKERS:
				world.spawn_walker(1 if _life_rng.randf() < 0.5 else -1, false)
			_ambient_timer = _life_rng.randf_range(3.0, 9.0) / maxf(0.4, float(loc["traffic"]))
	# the pipeline
	var before := tp.queue_payloads()
	var before_pickup := tp.waiting_payloads()
	# Queue patience and dining follow the visible pace, including during Skip.
	var pipeline_min := game_min
	tp.tick(pipeline_min, hour)
	if before != tp.queue_payloads():
		_reflow()
	var pickup := tp.waiting_payloads()
	if before_pickup != pickup:
		for i in range(pickup.size()):
			var customer := pickup[i] as Customer
			if is_instance_valid(customer) and not _seat_of.has(customer) and customer.slot != 100 + i:
				customer.go_to_slot(100 + i, world.pickup_slot(i))
	_bottleneck_watch(pipeline_min)
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

func _spawn_passer() -> void:
	stats["passers"] = int(stats["passers"]) + 1
	if DevTools.has("character-demo") and world.walkers >= World.MAX_RIGGED_GUESTS:
		return
	# Reserve the animation budget for likely visitors. Ambient walkers still pass
	# by separately, and each visitor makes the same price/queue decision on arrival.
	var wants := "drink" if _rng.randf() < Economy.drink_share(ctx["weather"]) else "food"
	var best := 0.0
	for candidate in Game.candidates(wants):
		best = maxf(best, float(candidate["value"]))
	var decision := _rng.randf()
	if decision >= _stop_chance(best, 0) * 1.5:
		return
	var c := world.spawn_walker(1 if _rng.randf() < 0.5 else -1)
	if c.model == null:
		c._finish()
		return
	c.wants = wants
	c.decision_roll = decision
	c.reached_decision.connect(_on_decision)
	c.gone.connect(_on_gone)

func _on_decision(c: Customer) -> void:
	if not running or _closing or c.model == null:
		return
	if c.decision_roll < 0.0:
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
	var r := c.decision_roll if c.decision_roll >= 0.0 else _rng.randf()
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
	_release_delivery(c)
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
	return is_instance_valid(payload) and payload.state == Customer.State.QUEUED

func _counter_ready(payload: Customer) -> bool:
	if not is_instance_valid(payload) or payload.model == null:
		return false
	if not finishing and _showcase_step < SHOWCASE_BEATS.size() and _showcase_time < 1.35:
		return false
	if payload.slot != 0 or payload.state != Customer.State.QUEUED:
		return false
	if not payload.order_shown:
		payload.order_shown = true
		payload.say(tr(Data.MENU_ITEMS[payload.item]["name"]), Color("ffe4ab"), 0.30, 0.90)
		payload.perform("order", "interact-right", 0.48)
	return payload.beat_left == 0.0

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

func _meal_finished(c: Customer) -> bool:
	return not is_instance_valid(c) or c.eating_left == 0.0

## Order taken: step aside to the pickup spot while the kitchen cooks.
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

## Food handed over: sell, add-ons, satisfaction, then sit down or walk away.
func _on_served(payload, item: String, wait_min: float, dine_in: bool) -> void:
	var c := payload as Customer
	if c == null or not is_instance_valid(c) or c.model == null:
		tp.remove(payload)
		return
	if c.purchase_shown or _pending_deliveries.has(c):
		return
	if dine_in and _seat_of.has(c):
		if not _stock_available(item):
			_sold_out(c, item)
			return
		var needs := Economy.portion_ingredients(item, Game.menu[item])
		_pending_deliveries[c] = needs
		for ingredient in needs:
			_reserved_ingredients[ingredient] = int(_reserved_ingredients.get(ingredient, 0)) + int(needs[ingredient])
		if not world.plot.deliver_meal(c, item, _deliver_order.bind(c, item, wait_min)):
			_release_delivery(c)
			tp.remove(c)
			_release_seat(c)
			c.leave_from_seat()
		return
	_settle_sale(c, item, wait_min, false)

func _stock_available(item: String) -> bool:
	var needs := Economy.portion_ingredients(item, Game.menu[item])
	for ingredient in needs:
		if int(Game.inventory.get(ingredient, 0)) - int(_reserved_ingredients.get(ingredient, 0)) < int(needs[ingredient]):
			return false
	return true

func _release_delivery(c: Customer) -> void:
	if not _pending_deliveries.has(c):
		return
	var needs: Dictionary = _pending_deliveries[c]
	_pending_deliveries.erase(c)
	for ingredient in needs:
		_reserved_ingredients[ingredient] = int(_reserved_ingredients[ingredient]) - int(needs[ingredient])

func _deliver_order(c: Customer, item: String, wait_min: float) -> bool:
	_release_delivery(c)
	if not is_instance_valid(c) or c.state != Customer.State.SEATED:
		return false
	if not _settle_sale(c, item, wait_min, true):
		return false
	c.eating_left = 3.5
	tp.seat_taken(c)
	return true

func _sold_out(c: Customer, item: String) -> void:
	stats["sold_out"] = int(stats["sold_out"]) + 1
	tp.remove(c)
	_release_seat(c)
	if c.state == Customer.State.SEATED:
		c.leave_from_seat(Data.pick_bubble("sold_out", _rng), Color("efa36f"))
	else:
		_reject(c, "sold_out", "price", Color("efa36f"))
	_warn("sold_out", tr("ev.sold_out_item") % tr(Data.MENU_ITEMS[item]["name"]))

func _settle_sale(c: Customer, item: String, wait_min: float, dine_in: bool) -> bool:
	if c.purchase_shown:
		return false
	var price := float(Game.menu[item]["price"])
	var spend := float(ctx.get("spend_mult", 1.0)) if dine_in else 1.0
	if not _stock_available(item) or not Game.sell(item, price * spend):
		_sold_out(c, item)
		return false
	var total := price * spend
	var cogs := Game.unit_cost(item)
	var sold_items: Array[String] = [item]
	stats["sold"][item] = int(stats["sold"].get(item, 0)) + 1
	var wants := c.wants if c != null and is_instance_valid(c) else "food"
	for extra in _addons(wants, c, dine_in):
		var ep := float(Game.menu[extra]["price"])
		if _stock_available(extra) and Game.sell(extra, ep):
			sold_items.append(extra)
			total += ep
			cogs += Game.unit_cost(extra)
			stats["sold"][extra] = int(stats["sold"].get(extra, 0)) + 1
	stats["revenue"] = float(stats["revenue"]) + total
	stats["cogs"] = float(stats["cogs"]) + cogs
	Game.total_served += 1
	stats["served"] = int(stats["served"]) + 1
	if dine_in:
		stats["dine_in"] = int(stats["dine_in"]) + 1
	var ratio := price / float(Data.MENU_ITEMS[item]["base_price"])
	var wait_ratio := clampf(wait_min / float(ctx["patience_min"]), 0.0, 1.0)
	var s := Economy.satisfaction(Game.quality(item), ratio, wait_ratio, loc, float(ctx["satisfaction_bonus"]) + (0.05 if dine_in else 0.0))
	stats["satisfaction_sum"] = float(stats["satisfaction_sum"]) + s
	var key := Economy.bubble_for_satisfaction(s)
	var col := Color(0.35, 0.85, 0.4) if key == "great" else (Color(1, 1, 1) if key == "ok" else Color(0.95, 0.5, 0.3))
	var text := tr(Data.MENU_ITEMS[item]["name"])
	if key == "great":
		text += "  +" + Loc.money(total)
	_check_stock_warnings()
	c.purchase_shown = true
	if dine_in:
		c.say(text, col, 0.9)
	else:
		_play_pickup(c, sold_items, text, col, c.leave)
	if DevTools.has("uitest"):
		purchase_log.append({"customer": c.get_instance_id(), "item": item, "dineIn": dine_in,
			"visible": c.model.is_visible_in_tree(), "state": c.state, "ordered": c.order_shown})
	_show_receipt(sold_items, total)
	return true

func service_view() -> Dictionary:
	var view := {"served": stats.get("served", 0), "dineIn": stats.get("dine_in", 0), "purchases": purchase_log,
		"closing": _closing, "pending": _pending_deliveries.size(), "workers": [], "dirty": [], "deliveries": 0, "cleaned": 0}
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

func _play_pickup(guest: Customer, items: Array[String], text: String, color: Color, done: Callable) -> void:
	_handoff_left = HANDOFF_SECONDS
	world.handoff(guest, items, HANDOFF_SECONDS)
	guest.say(text, color, 0.46)
	guest.perform("collect", "pick-up", HANDOFF_SECONDS, done)

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
	c.leave_from_seat(Data.pick_bubble("dine_in", _rng), Color(0.6, 0.9, 0.6))
	return table

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
	if _closing:
		return
	_closing = true
	hour = end_hour
	tp.close_queue()
	world.clear_virtual_walkers()
	world.set_time(end_hour, ctx["weather"])
	clock_changed.emit(end_hour)

func _publish_close() -> void:
	if not running:
		return
	running = false
	world.render_service()
	world.set_day_managed(false)
	if world.plot:
		world.plot.service_open = false
		world.plot.set_serving(false)
	stats["util"] = tp.utilisation()
	stats["max_queue"] = int(tp.stats["max_queue"])
	_emit_stats()
	finished.emit(stats)

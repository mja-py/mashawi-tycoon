class_name DaySim
extends Node
## Runs one business day: clock, passers-by, decisions, queue, sales, reactions.

signal clock_changed(hour: float)
signal stats_changed(stats: Dictionary)
signal event(text: String, kind: String)
signal finished(stats: Dictionary)

var world: World
var ctx: Dictionary
var loc: Dictionary
var weather_def: Dictionary
var hour: float = 10.0
var end_hour: float = 22.0
var running := false
var stats: Dictionary = {}
var queue: Array[Customer] = []
var serve_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _car_timer := 0.0
var _ambient_timer := 0.0
var _warned := {}
var _stats_tick := 0.0

func start(context: Dictionary, w: World) -> void:
	world = w
	ctx = context
	loc = Data.LOCATIONS[ctx["location"]]
	weather_def = Data.WEATHER[ctx["weather"]]
	hour = float(ctx["hours"][0])
	end_hour = float(ctx["hours"][1])
	stats = {"passers": 0, "served": 0, "revenue": 0.0, "cogs": 0.0, "sold": {}, "satisfaction_sum": 0.0,
		"left_wait": 0, "sold_out": 0, "queue_full": 0, "lost_rival": 0, "too_pricey": 0}
	queue.clear()
	_warned.clear()
	serve_timer = 0.0
	_rng.randomize()
	running = true
	_car_timer = 1.0
	_ambient_timer = 2.0
	world.set_time(hour, ctx["weather"])
	clock_changed.emit(hour)
	stats_changed.emit(stats)

func _process(delta: float) -> void:
	if not running:
		return
	var game_min := delta * 60.0 / Data.REAL_SECONDS_PER_GAME_HOUR
	hour += game_min / 60.0
	world.set_time(hour, ctx["weather"])
	clock_changed.emit(hour)
	# passers-by
	var per_hour := Economy.traffic_per_hour(loc, ctx["weather"], hour, ctx["has_awning"])
	var expected := per_hour * delta / Data.REAL_SECONDS_PER_GAME_HOUR
	# Poisson-ish: whole arrivals plus a fractional chance, so fast-forward isn't capped per frame.
	var arrivals := int(expected) + (1 if _rng.randf() < expected - int(expected) else 0)
	for i in range(arrivals):
		_spawn_passer()
	# background life
	_car_timer -= delta
	if _car_timer <= 0.0:
		world.spawn_car()
		_car_timer = _rng.randf_range(2.5, 7.0) / maxf(0.4, float(loc["traffic"]))
	_ambient_timer -= delta
	if _ambient_timer <= 0.0:
		world.spawn_walker(1 if _rng.randf() < 0.5 else -1, false)
		_ambient_timer = _rng.randf_range(3.0, 9.0) / maxf(0.4, float(loc["traffic"]))
	# queue
	_tick_queue(game_min)
	_stats_tick += delta
	if _stats_tick > 0.25:
		_stats_tick = 0.0
		stats_changed.emit(stats)
	if hour >= end_hour:
		_close()

func _spawn_passer() -> void:
	stats["passers"] = int(stats["passers"]) + 1
	var forced := false
	if world.walkers >= World.MAX_WALKERS:
		# Too crowded to show everyone: decide now, only show the ones who stop.
		var cands := Game.candidates("food")
		var best := 0.0
		for cand in cands:
			best = maxf(best, float(cand["value"]))
		var p := Economy.stop_probability(Game.popularity, best, float(ctx["boost"]), queue.size(), int(ctx["queue_cap"]), float(ctx["competition"]), float(ctx["promo_power"]))
		if _rng.randf() >= p:
			return
		forced = true
	var c := world.spawn_walker(1 if _rng.randf() < 0.5 else -1, true)
	c.forced_stop = forced
	c.reached_decision.connect(_on_decision)
	c.gone.connect(_on_gone)

func _on_decision(c: Customer) -> void:
	if not running:
		return
	c.wants = "drink" if _rng.randf() < Economy.drink_share(ctx["weather"]) else "food"
	var cands := Game.candidates(c.wants)
	var best := 0.0
	var any_stock := false
	for cand in cands:
		best = maxf(best, float(cand["value"]))
		if int(cand["stock"]) > 0:
			any_stock = true
	if cands.is_empty():
		return
	var p := Economy.stop_probability(Game.popularity, best, float(ctx["boost"]), queue.size(), int(ctx["queue_cap"]), float(ctx["competition"]), float(ctx["promo_power"]))
	var p_if_room := Economy.stop_probability(Game.popularity, best, float(ctx["boost"]), 0, int(ctx["queue_cap"]), float(ctx["competition"]), float(ctx["promo_power"]))
	var p_no_rivals := Economy.stop_probability(Game.popularity, best, float(ctx["boost"]), 0, int(ctx["queue_cap"]))
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
	if r < p or (c.forced_stop and queue.size() < int(ctx["queue_cap"])):
		if not any_stock:
			stats["sold_out"] = int(stats["sold_out"]) + 1
			c.leave(Data.pick_bubble("sold_out", _rng), Color(0.9, 0.3, 0.2), true)
			_warn("sold_out", tr("ev.sold_out_all"))
			return
		c.item = Economy.pick_weighted(cands, _rng)
		queue.append(c)
		c.go_to_slot(queue.size() - 1, world.queue_slot(queue.size() - 1))
	elif r < p_if_room and queue.size() >= int(ctx["queue_cap"]):
		stats["queue_full"] = int(stats["queue_full"]) + 1
		c.say(Data.pick_bubble("queue_full", _rng), Color(0.9, 0.5, 0.2))
		_warn("queue_full", tr("ev.queue_full"))
	elif r < p_if_room * 1.3 and best < 0.55:
		c.say(Data.pick_bubble("too_pricey", _rng), Color(0.9, 0.4, 0.3))
		stats["too_pricey"] = int(stats.get("too_pricey", 0)) + 1
	elif _rng.randf() < 0.08:
		match ctx["weather"]:
			"hot": c.say(Data.pick_bubble("hot", _rng), Color(1, 0.8, 0.4))
			"sandstorm": c.say(Data.pick_bubble("sandstorm", _rng), Color(1, 0.85, 0.6))
			"breeze": c.say(Data.pick_bubble("breeze", _rng), Color(0.8, 0.95, 1))

func _on_gone(c: Customer) -> void:
	queue.erase(c)

func _tick_queue(game_min: float) -> void:
	if queue.is_empty():
		if world.cart:
			world.cart.set_serving(false)
		return
	var front := queue[0]
	if front.state == Customer.State.QUEUED:
		if world.cart:
			world.cart.set_serving(true)
		serve_timer += game_min
		if serve_timer >= float(ctx["service_min"]):
			serve_timer = 0.0
			_serve(front)
	# waiting patience
	for i in range(queue.size() - 1, 0, -1):
		var c := queue[i]
		# only time spent standing in line counts (walking up takes "minutes" at this time scale)
		if c.state != Customer.State.QUEUED:
			continue
		c.wait_min += game_min
		if c.wait_min > float(ctx["patience_min"]):
			queue.remove_at(i)
			stats["left_wait"] = int(stats["left_wait"]) + 1
			c.react("emote-no")
			c.leave(Data.pick_bubble("too_slow", _rng), Color(0.9, 0.35, 0.2), true)
			_warn("slow", tr("ev.slow"))
			_reflow()

func _reflow() -> void:
	for i in range(queue.size()):
		var c := queue[i]
		if c.state == Customer.State.QUEUED or c.state == Customer.State.TO_SLOT:
			if c.slot != i:
				c.go_to_slot(i, world.queue_slot(i))

func _serve(c: Customer) -> void:
	queue.erase(c)
	var price := float(Game.menu[c.item]["price"])
	if not Game.sell(c.item, price):
		stats["sold_out"] = int(stats["sold_out"]) + 1
		c.react("emote-no")
		c.leave(Data.pick_bubble("sold_out", _rng), Color(0.9, 0.3, 0.2), true)
		_warn("sold_out", tr("ev.sold_out_item") % tr(Data.MENU_ITEMS[c.item]["name"]))
		_reflow()
		return
	var total := price
	var cogs := Game.unit_cost(c.item)
	stats["sold"][c.item] = int(stats["sold"].get(c.item, 0)) + 1
	# add-ons
	for extra in _addons(c):
		var ep := float(Game.menu[extra]["price"])
		if Game.sell(extra, ep):
			total += ep
			cogs += Game.unit_cost(extra)
			stats["sold"][extra] = int(stats["sold"].get(extra, 0)) + 1
	stats["revenue"] = float(stats["revenue"]) + total
	stats["cogs"] = float(stats["cogs"]) + cogs
	stats["served"] = int(stats["served"]) + 1
	var ratio := price / float(Data.MENU_ITEMS[c.item]["base_price"])
	var wait_ratio := clampf(c.wait_min / float(ctx["patience_min"]), 0.0, 1.0)
	var s := Economy.satisfaction(Game.quality(c.item), ratio, wait_ratio, loc, float(ctx["satisfaction_bonus"]))
	stats["satisfaction_sum"] = float(stats["satisfaction_sum"]) + s
	var key := Economy.bubble_for_satisfaction(s)
	var col := Color(0.35, 0.85, 0.4) if key == "great" else (Color(1, 1, 1) if key == "ok" else Color(0.95, 0.5, 0.3))
	var text := Data.pick_bubble(key, _rng)
	if key == "great":
		text += "  +" + Loc.money(total)
	c.react("emote-yes" if key == "great" else "pick-up")
	c.leave(text, col, true)
	Sfx.play("coin", -10.0, randf_range(0.95, 1.1))
	_check_stock_warnings()
	_reflow()

func _addons(c: Customer) -> Array:
	var out := []
	if c.wants != "food":
		return out
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
		if _rng.randf() < 0.4 * _addon_appeal(side):
			out.append(side)
	var drinks := []
	for id in ["soda", "laban", "karak"]:
		if Game.is_on_sale(id) and Game.portions_possible(id) > 0:
			drinks.append(id)
	if not drinks.is_empty():
		var pick: String = drinks[_rng.randi_range(0, drinks.size() - 1)]
		if _rng.randf() < drink_p * _addon_appeal(pick):
			out.append(pick)
	var sweets := []
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "sweet" and Game.is_on_sale(id) and Game.portions_possible(id) > 0:
			sweets.append(id)
	if not sweets.is_empty():
		var sw: String = sweets[_rng.randi_range(0, sweets.size() - 1)]
		if _rng.randf() < 0.35 * _addon_appeal(sw):
			out.append(sw)
			if _rng.randf() < 0.3:
				c.say(Data.pick_bubble("sweet", _rng), Color(1.0, 0.85, 0.6))
	return out

## 0..1 willingness to add an extra item, falling off as its price climbs above fair.
func _addon_appeal(id: String) -> float:
	var ratio := float(Game.menu[id]["price"]) / float(Data.MENU_ITEMS[id]["base_price"])
	return clampf(1.6 - ratio * 0.9, 0.0, 1.0)

func _check_stock_warnings() -> void:
	for id in Data.MENU_ITEMS:
		if Game.is_on_sale(id) and Game.portions_possible(id) == 0:
			_warn("out_" + id, tr("ev.out_of") % tr(Data.MENU_ITEMS[id]["name"]))

func _warn(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	event.emit(text, "warn")

func _close() -> void:
	running = false
	for c in queue:
		if is_instance_valid(c):
			c.leave(tr("ev.closing"), Color(0.9, 0.9, 0.9), false)
	queue.clear()
	if world.cart:
		world.cart.set_serving(false)
	stats_changed.emit(stats)
	finished.emit(stats)

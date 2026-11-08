class_name FastSim
extends RefCounted
## Statistical day without visuals, for headless balance runs (`--autodays`). Shares the
## arrival, stop and pick rules with DaySim through Economy and Game, and the same
## counter -> kitchen -> seat pipeline through Throughput. Each sale consumes real stock.

static func run(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var loc: Dictionary = Data.LOCATIONS[ctx["location"]]
	var stats := {"_day": int(ctx.get("day", Game.day)), "passers": 0, "served": 0, "revenue": 0.0, "cogs": 0.0, "sold": {}, "satisfaction_sum": 0.0,
		"left_wait": 0, "sold_out": 0, "queue_full": 0, "lost_rival": 0, "too_pricey": 0, "dine_in": 0, "wait_sum": 0.0}
	var hours: Array = ctx["hours"]
	var h := float(hours[0])
	var comp := float(ctx["competition"])
	var promo := float(ctx["promo_power"])
	var pop := float(ctx.get("popularity", Game.popularity))
	var appeal := float(ctx.get("appeal", 1.0))
	var qcap := int(ctx["queue_cap"])
	var patience := float(ctx["patience_min"])
	var tp := Throughput.new()
	tp.setup(ctx, rng)
	tp.on_served = func(_payload, id: String, wait: float, dine: bool) -> void:
		var price := float(Game.menu[id]["price"])
		var spend := float(ctx.get("spend_mult", 1.0)) if dine else 1.0
		if not Game.sell(id, price * spend):
			stats["sold_out"] += 1
			return
		Game.total_served += 1
		stats["served"] += 1
		stats["revenue"] += price * spend
		stats["cogs"] += Game.unit_cost(id)
		stats["sold"][id] = int(stats["sold"].get(id, 0)) + 1
		_sell_addons(id, ctx, rng, dine, stats)
		if dine:
			stats["dine_in"] += 1
		stats["wait_sum"] += wait
		var s := Economy.satisfaction(Game.quality(id), price / float(Data.MENU_ITEMS[id]["base_price"]),
			clampf(wait / patience, 0.0, 1.0), loc, float(ctx["satisfaction_bonus"]) + (0.05 if dine else 0.0))
		stats["satisfaction_sum"] += s
	tp.on_gave_up = func(_payload, _reason: String) -> void:
		pass
	var cars_per_min := float(ctx.get("cars_per_hour", 0.0)) / 60.0
	var next_customer := 0
	while h < float(hours[1]):
		var step := 1.0 / 60.0
		var passers := Economy.arrival_rate(loc, ctx["weather"], h, ctx) * step
		var n := int(passers) + (1 if rng.randf() < passers - int(passers) else 0)
		for i in range(n):
			stats["passers"] += 1
			var wants := "drink" if rng.randf() < Economy.drink_share(ctx["weather"]) else "food"
			var cands := Game.candidates(wants)
			var best := 0.0
			var any_stock := false
			for cand in cands:
				best = maxf(best, float(cand["value"]))
				any_stock = any_stock or int(cand["stock"]) > 0
			if cands.is_empty():
				continue
			var p := Economy.stop_probability(pop, best * appeal, float(ctx["boost"]), tp.queue_len(), qcap, comp, promo)
			var p_room := Economy.stop_probability(pop, best * appeal, float(ctx["boost"]), 0, qcap, comp, promo)
			var p_no_rivals := Economy.stop_probability(pop, best * appeal, float(ctx["boost"]), 0, qcap)
			var r := rng.randf()
			if r < p:
				if not any_stock:
					stats["sold_out"] += 1
				else:
					tp.enqueue(next_customer, Economy.pick_weighted(cands, rng))
					next_customer += 1
			elif r < p_room and tp.is_full():
				stats["queue_full"] += 1
			elif r >= p_room and r < p_no_rivals and comp > 0.0:
				stats["lost_rival"] += 1
		# customers arriving by car (valet/parking) have already decided to stop
		if cars_per_min > 0.0 and rng.randf() < cars_per_min:
			var cands := Game.candidates("food")
			var ok := false
			for cand in cands:
				ok = ok or int(cand["stock"]) > 0
			if ok:
				if not tp.enqueue(next_customer, Economy.pick_weighted(cands, rng)):
					stats["queue_full"] += 1
				next_customer += 1
		tp.tick(1.0, h)
		h += step
	tp.flush()
	stats["left_wait"] = int(tp.stats["left_wait"])
	stats["max_queue"] = int(tp.stats["max_queue"])
	stats["util"] = tp.utilisation()
	return stats

## Apply the same add-on chances as a visible meal, with real inventory and cash.
static func _sell_addons(primary: String, ctx: Dictionary, rng: RandomNumberGenerator, dine: bool, stats: Dictionary) -> void:
	if Data.MENU_ITEMS[primary]["kind"] != "food": return
	var drink_p := 0.65 if ctx["weather"] == "hot" else (0.2 if ctx["weather"] == "breeze" else 0.3)
	var bonus := 0.25 if dine else 0.0
	for group in [["side", 0.4], ["drink", drink_p], ["sweet", 0.35]]:
		var ids := []
		for id in Data.MENU_ITEMS:
			if Data.MENU_ITEMS[id]["kind"] == group[0] and Game.is_on_sale(id) and Game.portions_possible(id) > 0:
				ids.append(id)
		if ids.is_empty(): continue
		var id: String = ids[rng.randi_range(0, ids.size() - 1)]
		var price := float(Game.menu[id]["price"])
		var ratio := price / float(Data.MENU_ITEMS[id]["base_price"])
		var chance: float = (float(group[1]) + bonus) * clampf(1.6 - ratio * 0.9, 0.0, 1.0)
		if rng.randf() < chance and Game.sell(id, price):
			stats["revenue"] += price
			stats["cogs"] += Game.unit_cost(id)
			stats["sold"][id] = int(stats["sold"].get(id, 0)) + 1

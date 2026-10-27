class_name FastSim
extends RefCounted
## Statistical day without visuals, for headless balance runs (`--autodays`). Shares the
## arrival, stop and pick rules with DaySim through Economy and Game. Known divergence:
## add-ons (sides, drinks, sweets after a grill) are DaySim-only, so revenue here is a floor.

static func run(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var loc: Dictionary = Data.LOCATIONS[ctx["location"]]
	var stats := {"passers": 0, "served": 0, "revenue": 0.0, "cogs": 0.0, "sold": {}, "satisfaction_sum": 0.0,
		"left_wait": 0, "sold_out": 0, "queue_full": 0, "lost_rival": 0, "too_pricey": 0}
	var hours: Array = ctx["hours"]
	var h := float(hours[0])
	var queue: Array[String] = []
	var capacity_per_min := 1.0 / float(ctx["service_min"])
	var serve_accum := 0.0
	var comp := float(ctx["competition"])
	var promo := float(ctx["promo_power"])
	while h < float(hours[1]):
		var step := 1.0 / 60.0
		var passers := Economy.traffic_per_hour(loc, ctx["weather"], h, ctx["has_awning"]) * step
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
			var p := Economy.stop_probability(Game.popularity, best, float(ctx["boost"]), queue.size(), int(ctx["queue_cap"]), comp, promo)
			var p_room := Economy.stop_probability(Game.popularity, best, float(ctx["boost"]), 0, int(ctx["queue_cap"]), comp, promo)
			var p_no_rivals := Economy.stop_probability(Game.popularity, best, float(ctx["boost"]), 0, int(ctx["queue_cap"]))
			var r := rng.randf()
			if r < p:
				if not any_stock:
					stats["sold_out"] += 1
				else:
					queue.append(Economy.pick_weighted(cands, rng))
			elif r < p_room and queue.size() >= int(ctx["queue_cap"]):
				stats["queue_full"] += 1
			elif r >= p_room and r < p_no_rivals and comp > 0.0:
				stats["lost_rival"] += 1
		serve_accum = minf(serve_accum + capacity_per_min, 1.0)
		while serve_accum >= 1.0 and not queue.is_empty():
			serve_accum -= 1.0
			var id: String = queue.pop_front()
			var price := float(Game.menu[id]["price"])
			if not Game.sell(id, price):
				stats["sold_out"] += 1
				continue
			stats["served"] += 1
			stats["revenue"] += price
			stats["cogs"] += Game.unit_cost(id)
			stats["sold"][id] = int(stats["sold"].get(id, 0)) + 1
			var s := Economy.satisfaction(Game.quality(id), price / float(Data.MENU_ITEMS[id]["base_price"]), 0.2, loc, float(ctx["satisfaction_bonus"]))
			stats["satisfaction_sum"] += s
		# anyone past the patience limit gives up (one per minute at most)
		if queue.size() > int(ctx["queue_cap"]):
			stats["left_wait"] += queue.size() - int(ctx["queue_cap"])
			queue.resize(int(ctx["queue_cap"]))
		h += step
	return stats

class_name FastSim
extends RefCounted
## Statistical day without visuals, for headless balance runs (`--autodays`). Shares the
## arrival, stop and pick rules with DaySim through Economy and Game, and the same
## counter -> kitchen -> seat pipeline through Throughput. Add-ons are approximated.

static func run(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var loc: Dictionary = Data.LOCATIONS[ctx["location"]]
	var stats := {"passers": 0, "served": 0, "revenue": 0.0, "cogs": 0.0, "sold": {}, "satisfaction_sum": 0.0,
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
		if not Game.sell(id, price):
			stats["sold_out"] += 1
			return
		stats["served"] += 1
		var spend := float(ctx.get("spend_mult", 1.0)) if dine else 1.0
		var addon := _addon_revenue(id, ctx)
		stats["revenue"] += price * spend + addon[0]
		stats["cogs"] += Game.unit_cost(id) + addon[1]
		stats["sold"][id] = int(stats["sold"].get(id, 0)) + 1
		if dine:
			stats["dine_in"] += 1
		stats["wait_sum"] += wait
		var s := Economy.satisfaction(Game.quality(id), price / float(Data.MENU_ITEMS[id]["base_price"]),
			clampf(wait / patience, 0.0, 1.0), loc, float(ctx["satisfaction_bonus"]) + (0.05 if dine else 0.0))
		stats["satisfaction_sum"] += s
	tp.on_gave_up = func(_payload, _reason: String) -> void:
		pass
	var cars_per_min := float(ctx.get("cars_per_hour", 0.0)) / 60.0
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
					tp.enqueue("", Economy.pick_weighted(cands, rng))
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
			if ok and not tp.enqueue("", Economy.pick_weighted(cands, rng)):
				stats["queue_full"] += 1
		tp.tick(1.0, h)
		h += step
	tp.flush()
	stats["left_wait"] = int(tp.stats["left_wait"])
	stats["max_queue"] = int(tp.stats["max_queue"])
	stats["util"] = tp.utilisation()
	return stats

## Expected [revenue, cost] from sides/drinks/sweets sold alongside one primary item.
static func _addon_revenue(primary: String, ctx: Dictionary) -> Array:
	if Data.MENU_ITEMS[primary]["kind"] != "food":
		return [0.0, 0.0]
	var rev := 0.0
	var cost := 0.0
	var drink_p := 0.3
	if ctx["weather"] == "hot":
		drink_p = 0.65
	elif ctx["weather"] == "breeze":
		drink_p = 0.2
	for group in [["side", 0.4], ["drink", drink_p], ["sweet", 0.35]]:
		var ids := []
		for id in Data.MENU_ITEMS:
			if Data.MENU_ITEMS[id]["kind"] == group[0] and Game.is_on_sale(id) and Game.portions_possible(id) > 0:
				ids.append(id)
		if ids.is_empty():
			continue
		var p_sum := 0.0
		var r_sum := 0.0
		var c_sum := 0.0
		for id in ids:
			var ratio := float(Game.menu[id]["price"]) / float(Data.MENU_ITEMS[id]["base_price"])
			var p: float = float(group[1]) * clampf(1.6 - ratio * 0.9, 0.0, 1.0)
			p_sum += p
			r_sum += p * float(Game.menu[id]["price"])
			c_sum += p * Game.unit_cost(id)
		rev += r_sum / ids.size()
		cost += c_sum / ids.size()
	return [rev, cost]

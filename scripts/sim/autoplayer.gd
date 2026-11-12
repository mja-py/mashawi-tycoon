class_name Autoplayer
extends RefCounted
## The headless balance player used by `--autodays` (main.gd) and tests/balance_curve.gd.
## Each prep it plans the day the way a sensible greedy player would: buy whatever pays
## itself back fastest (station levels, stages, items, dish upgrades, moves, promotions)
## while a cash buffer for tomorrow's stock and rent remains above the family-loan line, price the menu by the analytic estimate
## under a satisfaction floor, then stock up for the estimated portions. It only uses the
## actions a player has (Game.buy_*, set_*, start_marketing) and plans with Game.what_if.

## One whole day: prep (policy), opening, the day itself, the books and a ready goal.
## played = the visible DaySim through DayRunner (the caller builds the street and gives
## finished guests a frame to leave the tree between days), else the statistical FastSim.
## Returns {"stats", "report", "buys"}.
## What the last greedy() prep bought, as "kind:id" (stations, stages, items, moves, promos, dish upgrades).
static var last_buys: Array[String] = []

static func play_day(played: bool, runner: DaySim, world: World, policy: String = "greedy") -> Dictionary:
	Game.prepare_day()
	last_buys.clear()
	var buys := 0
	if policy == "basic":
		basic()
	else:
		buys = greedy()
	Game.begin_day()
	var stats: Dictionary
	if played:
		# The street and the stand as the player would see them after this morning's buys.
		world.set_location(Game.location)
		world.apply_visual()
		stats = DayRunner.play(runner, world, Game.sim_context())
		if stats["_unfinished"]:
			push_error("day %d did not close within %d ticks" % [Game.day, stats["_ticks"]])
	else:
		var day_rng := RandomNumberGenerator.new()
		day_rng.seed = Game.day_seed
		stats = FastSim.run(Game.sim_context(), day_rng)
	var report := Game.end_day(stats)
	if Game.goal_ready():
		Game.claim_goal()
	return {"stats": stats, "report": report, "buys": buys}

## Supplies for the day: cover the estimated portions x 1.3 for every item on sale.
static func supplies() -> void:
	var est := Economy.throughput_estimate(Game.sim_context())
	var expect := maxi(20, int(float(est["portions"]) * 1.3))
	var ds := Economy.drink_share(Game.forecast)
	var need := {}
	var food_vals := 0.0
	var drink_vals := 0.0
	var offer := Game.offer(true)
	for o in offer:
		if o["kind"] == "food":
			food_vals += float(o["value"])
		elif o["kind"] == "drink":
			drink_vals += float(o["value"])
	for o in offer:
		var count := 0.0
		match String(o["kind"]):
			"food": count = expect * (1.0 - ds) * float(o["value"]) / maxf(food_vals, 0.001)
			"drink": count = expect * (ds * float(o["value"]) / maxf(drink_vals, 0.001) + 0.3 / maxi(1, _count_kind("drink")))
			"side": count = expect * 0.3 / maxi(1, _count_kind("side"))
			"sweet": count = expect * 0.25 / maxi(1, _count_kind("sweet"))
		var per := Economy.portion_ingredients(o["id"], Game.menu[o["id"]])
		for ing in per:
			need[ing] = float(need.get(ing, 0.0)) + count * float(per[ing])
	for ing in need:
		while int(Game.inventory[ing]) < int(need[ing]):
			var packs: Array = Data.INGREDIENTS[ing]["packs"]
			var gap: int = int(need[ing]) - int(Game.inventory[ing])
			var idx := packs.size() - 1
			for i in range(packs.size()):
				if int(packs[i][0]) >= gap:
					idx = i
					break
			if not Game.buy_pack(ing, idx):
				break
	if DevTools.has("pricemult"):
		for id in Data.MENU_ITEMS:
			Game.set_price(id, float(Data.MENU_ITEMS[id]["base_price"]) * float(DevTools.get_flag("pricemult")))

static func _count_kind(kind: String) -> int:
	var n := 0
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == kind and Game.is_on_sale(id):
			n += 1
	return n

## Greedy investor: each prep, buy whatever pays itself back fastest while a cash buffer
## for tomorrow's stock and rent remains. Returns the number of purchases.
static func greedy() -> int:
	var started := Time.get_ticks_usec()
	_mult_cache.clear()
	var bought := 0
	var dbg := DevTools.has("dbg")
	var left: Array[String] = [] # places this prep already moved away from (no back and forth)
	for round in range(10):
		var base_profit := float(_priced({})["profit"])
		# tomorrow's stock and rent, kept above the line where the family steps in with a loan
		var buffer := Data.BAILOUT_BELOW + 1.5 * (float(Game.loc()["rent"]) + Game.daily_wages() + float(Game.history.back().get("cogs", 150.0)) if not Game.history.is_empty() else 300.0)
		# cash piling up means a longer horizon is fine
		var horizon := 1.0 if Game.money < 8000.0 else (2.0 if Game.money < 30000.0 else 4.0)
		# a dictionary: lambdas capture locals by value. "save" = the best payback among the
		# purchases out of reach today but affordable within SAVE_DAYS of recent profit.
		var pick := {"score": 0.0, "best": {}, "save": 0.0, "save_for": ""}
		var earning := _recent_profit(base_profit)
		# bonus = extra profit the day itself brings (a trip that completes a goal); reward = a
		# step on the goal ladder: the reward pays part of the price and, spread over a month,
		# counts as daily gain even when the estimate sees none
		var consider := func(kind: String, id: String, cost: float, ctx: Dictionary, max_payback: float, where: String = "", bonus: float = 0.0, reward: float = 0.0) -> void:
			if cost <= 0.0:
				return
			if kind == "move" and id in left:
				return
			var short := cost + buffer - Game.money
			if short > 0.0 and short > SAVE_DAYS * maxf(earning, 1.0):
				return
			var gain := float(Economy.throughput_estimate(ctx)["profit"]) - base_profit
			var net := cost
			if reward > 0.0:
				gain = maxf(gain, 0.0) + reward / 30.0
				net = maxf(cost - reward, 0.1 * cost)
			gain += bonus
			if dbg:
				print("    cand %s %s %s cost %.0f gain %.1f money %.0f buffer %.0f" % [kind, id, where, cost, gain, Game.money, buffer])
			if gain <= 0.0:
				return
			var payback := net / gain
			if payback > max_payback * horizon:
				return
			var score := gain / net
			if short > 0.0:
				# out of reach today: worth saving for, not buying
				if score > float(pick["save"]):
					pick["save"] = score
					pick["save_for"] = "%s:%s" % [kind, id]
				return
			if score > float(pick["score"]):
				pick["score"] = score
				pick["best"] = {"kind": kind, "id": id, "cost": cost, "where": where}
		# The current goal is worth chasing when a purchase or a trip completes it: its reward,
		# spread over a month, counts as daily gain (a goal already met waits for its claim).
		var goal := Game.current_goal()
		# A day that opens here completes a pending "trade a day at ..." goal: leaving forfeits it.
		var reward_here := 0.0
		if not goal.is_empty() and not Game.goal_ready():
			var req: Dictionary = goal["req"]
			var reward := float(goal["reward"].get("money", 0.0))
			match String(req["type"]):
				"station_level":
					# the reward comes once, after the last of the levels it asks for
					var sid := String(req["station"])
					var missing := int(req["n"]) - Game.station_level(sid)
					if Game.station_lock_reason(sid) == "" and missing > 0:
						consider.call("station", sid, Game.station_cost(sid), Game.what_if({"stations": {sid: Game.station_level(sid) + 1}}), 400.0, "", 0.0, reward / missing)
				"stage":
					if Game.stage_lock_reason() == "" and Game.stage_tier() < int(req["n"]):
						var nd := Game.next_stage_def()
						consider.call("stage", nd["id"], float(nd["cost"]), Game.what_if({"stage": Game.stage_tier() + 1}), 400.0, "", 0.0, reward)
				"location", "location_any":
					# a day somewhere else is worth it when the reward covers what that day loses
					var ids: Array = req.get("ids", [req.get("id", "")])
					if Game.location in ids:
						reward_here = reward
					else:
						for lid in ids:
							if Data.LOCATIONS.has(lid) and Game.location_unlocked(lid) and Game.location_stage_ok(lid):
								consider.call("move", lid, 25.0, _priced({"location": lid})["ctx"], 1.0, "", reward)
				"day_dine_in":
					# diners need chairs
					if Game.station_available("seating") and Game.station_lock_reason("seating") == "" and Game.terrace_seats() < 4:
						consider.call("station", "seating", Game.station_cost("seating"), Game.what_if({"stations": {"seating": Game.station_level("seating") + 1}}), 400.0, "", 0.0, reward)
				"item_unlocked":
					var iid := String(req["id"])
					if not Game.menu[iid]["unlocked"] and Game.item_available(iid):
						consider.call("item", iid, maxf(1.0, float(Data.MENU_ITEMS[iid]["unlock_cost"])), Game.what_if({"unlock": iid}), 400.0, "", 0.0, reward)
					elif not Game.menu[iid]["unlocked"]:
						var need := Game.required_station(Data.MENU_ITEMS[iid])
						if need != "" and Game.station_lock_reason(need) == "":
							consider.call("station", need, Game.station_cost(need), Game.what_if({"stations": {need: 1}, "unlock": iid}), 400.0, "", 0.0, reward)
		for id in Game.active_stations():
			if Game.station_lock_reason(id) != "":
				continue
			consider.call("station", id, Game.station_cost(id), Game.what_if({"stations": {id: Game.station_level(id) + 1}}), 30.0)
		var sites := _stage_sites()
		if not sites.is_empty():
			# a stage is worth what the best place it opens is worth (with a few seats if it has a terrace)
			var nxt := Game.next_stage_def()
			var t := Game.stage_tier() + 1
			var best_ctx := {}
			var best_profit := -INF
			var best_site := ""
			var best_bundle := float(nxt["cost"])
			for id in sites:
				var extra := {}
				var bundle := float(nxt["cost"])
				if float(nxt.get("dine_in", 0.0)) > 0.0:
					# a terrace needs a few tables (a plot already built here keeps its own)
					var have := Game.station_level("seating") if id == Game.location and Game.is_fixed() else 0
					extra = {"seating": maxi(have, 4)}
					for i in range(have, 4):
						bundle += Economy.station_cost(Data.STATIONS["seating"], i)
				var priced := _priced({"stage": t, "location": id, "stations": extra})
				if dbg:
					print("    site %s %s profit %.0f at x%.2f" % [nxt["id"], id, float(priced["profit"]), float(priced["mult"])])
				if float(priced["profit"]) > best_profit:
					best_profit = float(priced["profit"])
					best_ctx = priced["ctx"]
					best_site = id
					best_bundle = bundle
			if String(nxt["scope"]) == "rig":
				# the rig travels: buy it here, the move is weighed on its own afterwards
				best_site = ""
			consider.call("stage", nxt["id"], best_bundle, best_ctx, 60.0, best_site)
		for id in Data.MENU_ITEMS:
			if not Game.menu[id]["unlocked"] and Game.item_available(id):
				consider.call("item", id, maxf(float(Data.MENU_ITEMS[id]["unlock_cost"]), 1.0), Game.what_if({"unlock": id}), 30.0)
			elif Game.is_on_sale(id) and int(Game.menu[id]["level"]) < Data.MENU_ITEMS[id]["enhance"].size():
				# a dish upgrade: better food draws more buyers and bears a higher price
				consider.call("enhance", id, float(Data.MENU_ITEMS[id]["enhance"][int(Game.menu[id]["level"])]["cost"]), Game.what_if({"enhance": id}), 30.0)
		for id in Game.stage_locations():
			if id != Game.location and Game.location_unlocked(id) and Game.location_stage_ok(id):
				# each place at the prices it would get there (a dearer place takes dearer prices)
				consider.call("move", id, 25.0, _priced({"location": id})["ctx"], 1.0, "", -reward_here)
		if Game.competition() > 0.0:
			for id in Data.MARKETING:
				if not Game.marketing.has(id):
					consider.call("promo", id, float(Data.MARKETING[id]["cost"]), _ctx_with_boost(float(Data.MARKETING[id]["boost"])), float(Data.MARKETING[id]["days"]))
		var best: Dictionary = pick["best"]
		if best.is_empty():
			break
		if float(pick["save"]) > float(pick["score"]):
			# something that pays back faster is a few days of saving away
			if dbg:
				print("    saving for %s (%.4f > %.4f)" % [pick["save_for"], float(pick["save"]), float(pick["score"])])
			break
		var ok := false
		match String(best["kind"]):
			"station": ok = Game.buy_station_level(best["id"])
			"stage":
				# a plot is built where it pays best: move there first
				var site := String(best.get("where", ""))
				if site != "" and site != Game.location:
					Game.set_location(site)
				ok = Game.buy_stage()
			"item": ok = Game.unlock_item(best["id"])
			"enhance": ok = Game.enhance_item(best["id"])
			"move":
				var from := Game.location
				ok = Game.set_location(best["id"])
				if ok:
					left.append(from)
			"promo": ok = Game.start_marketing(best["id"])
		if not ok:
			break
		bought += 1
		last_buys.append("%s:%s" % [best["kind"], best["id"]])
	prices()
	# cheap quality: max the recipe once the first grill levels are in
	if Game.station_level("grill") >= 2:
		for id in Data.MENU_ITEMS:
			if Data.MENU_ITEMS[id]["recipe"] and Game.menu[id]["unlocked"]:
				Game.set_recipe(id, "meat", 3)
				Game.set_recipe(id, "veg", 3)
				Game.set_recipe(id, "sauce", 2)
	supplies()
	prep_usec += Time.get_ticks_usec() - started
	return bought

## Where the next stage could be built today. A rig stage is bought where you stand and goes
## wherever the rig goes (any place it may trade at); the first fixed plot can go up at any
## place you may trade at that has no plot yet and enough local reputation.
static func _stage_sites() -> Array:
	var nxt := Game.next_stage_def()
	if nxt.is_empty() or nxt.get("later", false):
		return []
	var t := Game.stage_tier() + 1
	var out := []
	if String(nxt["scope"]) == "rig":
		if Game.stage_lock_reason() == "":
			out.append(Game.location)
			for id in Game.stage_locations():
				if id != Game.location and Game.location_unlocked(id) and int(Data.LOCATIONS[id].get("min_stage", 0)) <= t:
					out.append(id)
		return out
	if Game.stage_lock_reason() == "":
		out.append(Game.location)
	if Game.is_fixed() or Game.rig_tier() < int(nxt.get("requires_rig", 0)):
		return out
	var rep_needed := float(nxt.get("requires_local_rep", 0.0))
	for id in Game.stage_locations():
		if id == Game.location or not Game.location_unlocked(id) or not Game.location_stage_ok(id):
			continue
		if Game.plot_stage_tier(id) >= Game.FIXED_FROM_TIER:
			continue
		if float(Game.plots.get(id, {}).get("reputation", Game.popularity)) >= rep_needed:
			out.append(id)
	return out

const PRICE_MULTS := [0.9, 1.0, 1.1, 1.2, 1.35, 1.5, 1.8]
## How many days of recent profit a player would save up for something that pays back faster.
const SAVE_DAYS := 20.0
## Price multipliers found during this prep, by setup.
static var _mult_cache := {}
## Time spent planning (all greedy() calls), for the balance run's timing line.
static var prep_usec := 0

## What the last week actually made a day (the estimate until there is a week of books).
static func _recent_profit(estimate: float) -> float:
	var n := mini(7, Game.history.size())
	if n == 0:
		return estimate
	var sum := 0.0
	for i in range(n):
		sum += float(Game.history[Game.history.size() - 1 - i].get("profit", 0.0))
	return sum / n

## The best whole-menu price multiplier for a setup (Game.what_if overrides, {} = as it
## stands): {"mult", "profit", "ctx"}. Never a price that leaves the average customer
## unhappy (reputation is the engine).
static func _priced(overrides: Dictionary) -> Dictionary:
	var key := str(overrides)
	if _mult_cache.has(key):
		# later rounds of the same prep reuse the multiplier the first one found
		var o := overrides.duplicate()
		o["price_mult"] = _mult_cache[key]
		var c := Game.what_if(o)
		return {"mult": _mult_cache[key], "profit": float(Economy.throughput_estimate(c)["profit"]), "ctx": c}
	var loc: Dictionary = Data.LOCATIONS[String(overrides.get("location", Game.location))]
	var best := {"mult": 1.0, "profit": -INF, "ctx": {}}
	for mult in PRICE_MULTS:
		var sat := Economy.satisfaction(Game.quality("chicken_tikka"), float(mult), 0.15, loc, Game.satisfaction_bonus())
		if sat < 0.62 and float(mult) > 1.0:
			continue
		var o := overrides.duplicate()
		o["price_mult"] = mult
		var ctx := Game.what_if(o)
		var pr := float(Economy.throughput_estimate(ctx)["profit"])
		if pr > float(best["profit"]):
			best = {"mult": mult, "profit": pr, "ctx": ctx}
	_mult_cache[key] = best["mult"]
	return best

## Try a few price multipliers on the whole menu and keep the one the estimate likes best.
static func prices() -> void:
	_mult_cache.erase(str({}))
	var mult := float(_priced({})["mult"])
	for id in Data.MENU_ITEMS:
		Game.set_price(id, float(Data.MENU_ITEMS[id]["base_price"]) * mult)

static func _ctx_with_boost(extra: float) -> Dictionary:
	var ctx := Game.sim_context()
	ctx["boost"] = float(ctx["boost"]) + extra
	return ctx

## The old player: supplies for 1.3x yesterday, Creek when popular, nothing else.
static func basic() -> void:
	var expect := 30
	if not Game.history.is_empty():
		expect = maxi(15, int(float(Game.history.back().get("portions", Game.history.back()["served"])) * 1.3))
	var target := {"bread": expect, "chicken": expect * 2, "veg": expect * 2, "sauce": expect, "charcoal": expect, "drink": int(expect * 0.5)}
	for ing in target:
		while int(Game.inventory[ing]) < int(target[ing]):
			var packs: Array = Data.INGREDIENTS[ing]["packs"]
			var gap: int = int(target[ing]) - int(Game.inventory[ing])
			var idx := packs.size() - 1
			for i in range(packs.size()):
				if int(packs[i][0]) >= gap:
					idx = i
					break
			if not Game.buy_pack(ing, idx):
				break
	if Game.popularity > 0.3 and Game.money > 1500 and Game.location == "fahidi":
		Game.set_location("creek")
	if DevTools.has("pricemult"):
		for id in Data.MENU_ITEMS:
			Game.set_price(id, float(Data.MENU_ITEMS[id]["base_price"]) * float(DevTools.get_flag("pricemult")))

class_name Economy
extends RefCounted
## Pure functions describing how customers react to prices, quality, weather and
## waiting, and how the station chain (counter -> kitchen -> seats) limits a day.
## No state in here, so everything is easy to test and tune.

const BASE_SERVICE_MIN := 2.0
const BASE_QUEUE_CAP := 4
const BASE_PATIENCE_MIN := 8.0
const PASSERS_PER_HOUR := 60.0
## Add-ons (sides, drinks, sweets) as a share of primary revenue in the analytic estimate.
const ADDON_REVENUE_FACTOR := 0.22
const DINE_IN_SPEND := 1.15
const REPUTATION_DECAY_PER_DAY := 0.004

static func recipe_quality(recipe: Dictionary) -> float:
	var meat := clampi(int(recipe.get("meat", 2)), 1, 3)
	var veg := clampi(int(recipe.get("veg", 2)), 0, 3)
	var sauce := clampi(int(recipe.get("sauce", 1)), 0, 3)
	var q: float = [0.55, 0.78, 0.88][meat - 1]
	q += [-0.12, -0.04, 0.04, 0.06][veg]
	q += [-0.10, 0.02, 0.04, -0.03][sauce]
	return q

## Quality in roughly 0.4 .. 1.25. 0.8 is "fine", 1.0 is "great".
static func item_quality(item_id: String, entry: Dictionary) -> float:
	var def: Dictionary = Data.MENU_ITEMS[item_id]
	var q := 0.8
	if def["recipe"]:
		q = recipe_quality(entry.get("recipe", {}))
	var level := int(entry.get("level", 0))
	var enh: Array = def["enhance"]
	for i in range(mini(level, enh.size())):
		q += float(enh[i]["quality"])
	return q

## Ingredient units needed for one portion of an item given its recipe.
static func portion_ingredients(item_id: String, entry: Dictionary) -> Dictionary:
	var def: Dictionary = Data.MENU_ITEMS[item_id]
	var out := {}
	var recipe: Dictionary = entry.get("recipe", {})
	for ing in def["ingredients"]:
		var amount = def["ingredients"][ing]
		if typeof(amount) == TYPE_STRING:
			out[ing] = int(recipe.get(String(amount).trim_prefix("@"), 1))
		else:
			out[ing] = int(amount)
	return out

static func unit_cost(item_id: String, entry: Dictionary) -> float:
	var cost := 0.0
	var needs := portion_ingredients(item_id, entry)
	for ing in needs:
		cost += needs[ing] * Data.reference_unit_price(ing)
	return cost

## [lowest, highest] whole-AED price a menu item may be sold for at a location (and stage).
static func price_range(item_id: String, loc: Dictionary, stage: Dictionary = {}) -> Array:
	var base := float(Data.MENU_ITEMS[item_id]["base_price"])
	var lo := maxf(1.0, floorf(base * Data.PRICE_MIN_MULT))
	var hi := maxf(lo, ceilf(base * Data.price_cap_mult(loc, stage)))
	return [lo, hi]

## How attractive an item is to a customer at this location and weather.
static func item_value(item_id: String, quality: float, price: float, loc: Dictionary, weather: Dictionary) -> float:
	var def: Dictionary = Data.MENU_ITEMS[item_id]
	var appeal := float(def["appeal"])
	if def["kind"] == "drink":
		appeal *= float(weather["drink"])
	else:
		appeal *= float(weather["food"])
	var ratio := price / float(def["base_price"])
	var care := float(loc.get("quality_care", 1.0))
	var tol := float(loc.get("price_tol", 1.0))
	return pow(maxf(quality, 0.05), care) * appeal / pow(maxf(ratio, 0.05), 1.6 / tol)

## Chance that a passer-by stops, given the best value on offer for what they want.
static func stop_probability(popularity: float, best_value: float, boost: float, queue_len: int, queue_cap: int,
		competition: float = 0.0, promo_power: float = 1.0) -> float:
	if queue_len >= queue_cap:
		return 0.0
	var p := 0.05 + 0.20 * popularity
	# No floor: an overpriced or awful menu really does empty the street.
	p *= clampf(best_value / 0.8, 0.0, 1.6)
	p *= 1.0 + boost * promo_power
	p *= 1.0 - competition_loss(competition, boost, promo_power)
	p *= 1.0 - 0.55 * float(queue_len) / float(queue_cap)
	return clampf(p, 0.0, 0.9)

## Share of would-be customers that rival stalls take. Promotion wins them back: at
## 0.45 effective boost the rivals are fully drowned out.
static func competition_loss(competition: float, boost: float, promo_power: float) -> float:
	if competition <= 0.0:
		return 0.0
	var cover := clampf(boost * promo_power / 0.45, 0.0, 1.0)
	return competition * (1.0 - cover)

## Expected passers-by per game hour.
static func traffic_per_hour(loc: Dictionary, weather_id: String, hour: float, has_awning: bool) -> float:
	var w: Dictionary = Data.WEATHER[weather_id]
	var penalty := (1.0 - float(w["traffic"])) * float(loc.get("exposure", 1.0))
	if weather_id == Data.BAD_WEATHER and has_awning:
		penalty *= 0.5
	var mult := clampf(1.0 - penalty, 0.05, 1.5)
	if weather_id == "hot":
		mult += float(loc.get("hot_bonus", 0.0))
	return PASSERS_PER_HOUR * float(loc["traffic"]) * mult * time_curve(loc, hour)

## Passers-by per hour with the stations that change it: shade (storm + heat), lights
## (evenings) and any event multiplier in the context.
static func arrival_rate(loc: Dictionary, weather_id: String, hour: float, ctx: Dictionary) -> float:
	var shade := int(ctx.get("shade_level", 0))
	var rate := traffic_per_hour(loc, weather_id, hour, shade >= 1)
	if weather_id == "hot":
		rate *= 1.0 + 0.04 * shade
	var lights := int(ctx.get("lights_level", 0))
	if lights > 0 and hour >= 18.0:
		rate *= 1.0 + 0.08 * lights
	return rate * float(ctx.get("traffic_mult", 1.0))

static func time_curve(loc: Dictionary, hour: float) -> float:
	var c := 0.45
	for peak in loc.get("peaks", []):
		var d: float = (hour - float(peak)) / 1.4
		c += 0.6 * exp(-0.5 * d * d)
	return c

## 0..1 satisfaction with a purchase.
static func satisfaction(quality: float, price_ratio: float, wait_ratio: float, loc: Dictionary, bonus: float) -> float:
	var care := float(loc.get("quality_care", 1.0))
	var s := 0.5 + (quality - 0.72) * 1.2 * care
	s -= maxf(0.0, price_ratio - 1.0) * 0.6
	s += minf(0.0, price_ratio - 1.0) * -0.3
	s -= wait_ratio * 0.25
	s += bonus
	return clampf(s, 0.0, 1.0)

static func bubble_for_satisfaction(s: float) -> String:
	if s >= 0.7:
		return "great"
	if s >= 0.4:
		return "ok"
	return "bad_quality"

## Share of customers who want a drink rather than food, by weather.
static func drink_share(weather_id: String) -> float:
	if weather_id == "hot":
		return 0.5
	if weather_id == "breeze":
		return 0.1
	return 0.22

## Weighted random pick among candidates ({"id", "value", "stock"}) that have stock.
static func pick_weighted(cands: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for cand in cands:
		if int(cand["stock"]) > 0:
			total += float(cand["value"])
	var r := rng.randf() * total
	for cand in cands:
		if int(cand["stock"]) <= 0:
			continue
		r -= float(cand["value"])
		if r <= 0.0:
			return cand["id"]
	return cands[0]["id"]

static func popularity_delta(stats: Dictionary, popularity: float) -> float:
	var served := int(stats.get("served", 0))
	var delta := -0.01
	if served > 0:
		var avg: float = float(stats.get("satisfaction_sum", 0.0)) / served
		delta = (avg - 0.5) * 0.35 * clampf(served / 25.0, 0.3, 1.0)
	# people who left the line or found you sold out talk too (as a share of everyone who tried)
	var lost := int(stats.get("left_wait", 0)) + int(stats.get("sold_out", 0))
	if lost > 0:
		delta -= 0.08 * float(lost) / float(lost + served)
	# Popularity is harder to raise near the top.
	if delta > 0.0:
		delta *= 1.0 - 0.6 * popularity
	return delta

## A plot you have not visited loses a little local reputation per day, never below 0.1.
static func reputation_decay(current: float, days_away: int) -> float:
	return maxf(0.1, current - REPUTATION_DECAY_PER_DAY * maxi(days_away, 0))

## What the street thinks of you here: mostly your name, partly this corner's own reputation.
static func effective_popularity(global_pop: float, local_rep: float) -> float:
	return clampf(0.6 * global_pop + 0.4 * local_rep, 0.05, 1.0)

# ---------------------------------------------------------------- stations

## Price of the next level of a station: base * growth^level, rounded to 10 (50 above 1000).
static func station_cost(def: Dictionary, level: int) -> float:
	var c := float(def["base"]) * pow(float(def["growth"]), level)
	return snappedf(c, 50.0 if c >= 1000.0 else 10.0)

static func station_level_cap(def: Dictionary, stage: Dictionary) -> int:
	var cap := int(def["max"])
	if cap >= 5:
		cap += int(stage.get("level_cap_bonus", 0))
	return cap

## Orders a counter takes per game minute. Level 0 = today's one vendor (2 min per order).
static func counter_capacity(level: int, staff_mult: float = 1.0) -> float:
	var def: Dictionary = Data.STATIONS["counter"]
	return float(def["orders_per_min"]) * (1.0 + float(def["per_level"]) * level) * staff_mult

static func queue_cap(counter_level: int, stage: Dictionary) -> int:
	return BASE_QUEUE_CAP + counter_level * int(Data.STATIONS["counter"]["queue_per_level"]) + int(stage.get("queue_bonus", 0))

## Portions a kitchen station finishes per game minute (0 while it is not owned yet).
static func kitchen_capacity(def: Dictionary, level: int, staff_mult: float = 1.0, event_mult: float = 1.0) -> float:
	if level < int(def.get("owned_from", 0)):
		return 0.0
	return float(def.get("cooks_per_min", 0.0)) * (1.0 + float(def.get("per_level", 0.0)) * level) * staff_mult * event_mult

## Capacity of a kitchen serving a demand mix: customers/min = 1 / sum(share_k / cap_k).
## Shares whose station has no capacity cannot be served and are left out of the mix.
static func kitchen_capacity_mix(caps: Dictionary, shares: Dictionary) -> float:
	var total := 0.0
	var inv := 0.0
	for k in shares:
		var share := float(shares[k])
		if share <= 0.0:
			continue
		if k == "":
			total += share # counter-only items need no kitchen time
			continue
		var cap := float(caps.get(k, 0.0))
		if cap <= 0.0:
			continue
		total += share
		inv += share / cap
	if inv <= 0.0:
		return INF
	return total / inv

## Customers a dining area turns over per minute.
static func seat_capacity(seats: int, dwell_min: float, clean_min: float) -> float:
	if seats <= 0:
		return 0.0
	return float(seats) / maxf(1.0, dwell_min + clean_min)

## Share of served customers who sit down to eat (0 without seats or below the kiosk).
static func dine_in_share(stage: Dictionary, seats: int) -> float:
	if seats <= 0:
		return 0.0
	return float(stage.get("dine_in", 0.0)) * clampf(seats / 12.0, 0.0, 1.0)

static func spend_multiplier(majlis_level: int = 0) -> float:
	return DINE_IN_SPEND + 0.03 * majlis_level

## Expected day on the station chain, analytically: per hour, demand = arrivals x stop chance
## (+ cars), capacity = min(counter, kitchen mix), served = cap * (1 - e^(-demand/cap)).
## Returns {want, served, left, dine_in, revenue, cogs, profit, util{station: 0..}, bottleneck}.
static func throughput_estimate(ctx: Dictionary) -> Dictionary:
	var loc: Dictionary = Data.LOCATIONS[ctx["location"]]
	var weather: String = ctx["weather"]
	var offer: Array = ctx.get("offer", [])
	var ds := drink_share(weather)
	var food_sum := 0.0
	var drink_sum := 0.0
	var best_food := 0.0
	var best_drink := 0.0
	for o in offer:
		if int(o.get("stock", 1)) <= 0:
			continue
		if o["kind"] == "food":
			food_sum += float(o["value"])
			best_food = maxf(best_food, float(o["value"]))
		elif o["kind"] == "drink":
			drink_sum += float(o["value"])
			best_drink = maxf(best_drink, float(o["value"]))
	var shares := {}
	var avg_price := 0.0
	var avg_cost := 0.0
	var station_of_kind: Dictionary = ctx.get("station_of_kind", {})
	for o in offer:
		if int(o.get("stock", 1)) <= 0:
			continue
		var share := 0.0
		if o["kind"] == "food" and food_sum > 0.0:
			share = (1.0 - ds) * float(o["value"]) / food_sum
		elif o["kind"] == "drink" and drink_sum > 0.0:
			share = ds * float(o["value"]) / drink_sum
		if share <= 0.0:
			continue
		var station: String = station_of_kind.get(String(o.get("station_kind", "")), "")
		shares[station] = float(shares.get(station, 0.0)) + share
		avg_price += share * float(o["price"])
		avg_cost += share * float(o["unit_cost"])
	var kitchen: Dictionary = ctx.get("kitchen", {})
	var mix_cap := kitchen_capacity_mix(kitchen, shares)
	var counter_cap := float(ctx.get("counter_cap", 0.5))
	var cap := minf(counter_cap, mix_cap)
	var appeal := float(ctx.get("appeal", 1.0))
	var pop := float(ctx.get("popularity", 0.2))
	var qcap := int(ctx.get("queue_cap", BASE_QUEUE_CAP))
	var comp := float(ctx.get("competition", 0.0))
	var promo := float(ctx.get("promo_power", 1.0))
	var boost := float(ctx.get("boost", 0.0))
	var seats := int(ctx.get("seats", 0))
	var dine_share := float(ctx.get("dine_in_share", 0.0))
	var seat_cap := seat_capacity(seats, float(ctx.get("dwell_min", 18.0)), float(ctx.get("clean_min", 3.0)))
	var hours: Array = ctx["hours"]
	var want_total := 0.0
	var served_total := 0.0
	var util := {"counter": 0.0}
	for s in kitchen:
		util[s] = 0.0
	if seats > 0:
		util["seating"] = 0.0
	var h := float(hours[0])
	while h < float(hours[1]):
		var arrivals := arrival_rate(loc, weather, h + 0.5, ctx)
		var p_food := stop_probability(pop, best_food * appeal, boost, 0, qcap, comp, promo)
		var p_drink := stop_probability(pop, best_drink * appeal, boost, 0, qcap, comp, promo)
		var want := arrivals * ((1.0 - ds) * p_food + ds * p_drink) / 60.0 + float(ctx.get("cars_per_hour", 0.0)) / 60.0
		var served := 0.0
		if cap > 0.0 and want > 0.0:
			served = cap * (1.0 - exp(-want / cap)) if cap != INF else want
		want_total += want * 60.0
		served_total += served * 60.0
		if counter_cap > 0.0:
			util["counter"] = maxf(util["counter"], want / counter_cap)
		for s in kitchen:
			var c := float(kitchen[s])
			if c > 0.0:
				util[s] = maxf(util[s], want * float(shares.get(s, 0.0)) / c)
		if seat_cap > 0.0:
			util["seating"] = maxf(util["seating"], served * dine_share / seat_cap)
		h += 1.0
	var dine_in := served_total * dine_share
	var spend := float(ctx.get("spend_mult", DINE_IN_SPEND))
	var revenue := served_total * avg_price * (1.0 + ADDON_REVENUE_FACTOR) * (1.0 + dine_share * (spend - 1.0))
	var cogs := served_total * avg_cost * (1.0 + ADDON_REVENUE_FACTOR * 0.6)
	var fixed := float(loc.get("rent", 0.0)) + float(ctx.get("wages", 0.0))
	return {
		"want": want_total, "served": served_total, "left": maxf(0.0, want_total - served_total), "dine_in": dine_in,
		"revenue": revenue, "cogs": cogs, "profit": revenue - cogs - fixed,
		"util": util, "bottleneck": bottleneck(util),
	}

## The station closest to overflowing (utilisation >= 0.85), or "arrivals" when everything
## idles below half capacity (you need customers, not equipment), or "".
static func bottleneck(util: Dictionary) -> String:
	var worst := ""
	var worst_u := 0.0
	var all_idle := true
	for s in util:
		var u := float(util[s])
		if u >= 0.5:
			all_idle = false
		if u > worst_u:
			worst_u = u
			worst = s
	if worst_u >= 0.85:
		return worst
	if all_idle:
		return "arrivals"
	return ""

## 0..1 progress of a goal against Game.goal_snapshot().
static func goal_progress(goal: Dictionary, snap: Dictionary) -> float:
	var req: Dictionary = goal["req"]
	var n := float(req.get("n", 1))
	match String(req["type"]):
		"day_served": return clampf(float(snap.get("day_served", 0)) / n, 0.0, 1.0)
		"day_profit": return clampf(float(snap.get("day_profit", 0.0)) / n, 0.0, 1.0)
		"day_dine_in": return clampf(float(snap.get("day_dine_in", 0)) / n, 0.0, 1.0)
		"total_served": return clampf(float(snap.get("total_served", 0)) / n, 0.0, 1.0)
		"stars": return clampf(float(snap.get("stars", 0.0)) / n, 0.0, 1.0)
		"levels_owned": return clampf(float(snap.get("levels_owned", 0)) / n, 0.0, 1.0)
		"stage": return clampf(float(snap.get("stage", 0)) / n, 0.0, 1.0)
		"station_level": return clampf(float(snap.get("stations", {}).get(String(req["station"]), 0)) / n, 0.0, 1.0)
		"location": return 1.0 if String(req["id"]) in snap.get("visited", []) else 0.0
		"location_any":
			for id in req.get("ids", []):
				if String(id) in snap.get("visited", []):
					return 1.0
			return 0.0
		"item_unlocked": return 1.0 if String(req["id"]) in snap.get("unlocked", []) else 0.0
	return 0.0

## Rough number of customers to expect today, for the supplies screen.
static func expected_customers(ctx: Dictionary) -> int:
	return int(round(throughput_estimate(ctx)["served"]))

## Cheapest combination of whole packs covering a deficit. Avoid filling a small
## shortage with a large bulk pack that costs more and spoils overnight.
static func supply_packs(packs: Array, deficit: int) -> Dictionary:
	if deficit <= 0:
		return {"cost": 0.0, "counts": []}
	var largest := 0
	for p in packs:
		largest = maxi(largest, int(p[0]))
	var limit := deficit + largest
	var costs := PackedFloat64Array()
	var choices := PackedInt32Array()
	costs.resize(limit)
	costs.fill(INF)
	choices.resize(limit)
	choices.fill(-1)
	costs[0] = 0.0
	for qty in range(1, limit):
		for i in range(packs.size()):
			var prev := qty - int(packs[i][0])
			if prev >= 0 and costs[prev] + float(packs[i][1]) < costs[qty]:
				costs[qty] = costs[prev] + float(packs[i][1])
				choices[qty] = i
	var best := deficit
	for qty in range(deficit, limit):
		if costs[qty] < costs[best]:
			best = qty
	var counts := []
	counts.resize(packs.size())
	counts.fill(0)
	var total := costs[best]
	while best > 0 and choices[best] >= 0:
		var idx := choices[best]
		counts[idx] += 1
		best -= int(packs[idx][0])
	return {"cost": total, "counts": counts}

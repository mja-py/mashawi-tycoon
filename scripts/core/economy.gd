class_name Economy
extends RefCounted
## Pure functions describing how customers react to prices, quality, weather and
## waiting. No state in here, so everything is easy to test and tune.

const BASE_SERVICE_MIN := 2.0
const BASE_QUEUE_CAP := 4
const BASE_PATIENCE_MIN := 8.0
const PASSERS_PER_HOUR := 30.0

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
	var p := 0.10 + 0.45 * popularity
	p *= clampf(best_value / 0.8, 0.15, 1.6)
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

## Rough number of customers to expect today, for the supplies screen.
static func expected_customers(loc: Dictionary, weather_id: String, hours: Array, popularity: float, boost: float, has_awning: bool) -> int:
	var total := 0.0
	var h := float(hours[0])
	while h < float(hours[1]):
		total += traffic_per_hour(loc, weather_id, h + 0.5, has_awning)
		h += 1.0
	var p := stop_probability(popularity, 0.85, boost, 0, 4, float(loc.get("competition", 0.0)), float(loc.get("promo_power", 1.0)))
	return int(round(total * p))

static func popularity_delta(stats: Dictionary, popularity: float) -> float:
	var served := int(stats.get("served", 0))
	var delta := -0.01
	if served > 0:
		var avg: float = float(stats.get("satisfaction_sum", 0.0)) / served
		delta = (avg - 0.5) * 0.25 * clampf(served / 25.0, 0.3, 1.0)
	delta -= (int(stats.get("left_wait", 0)) + int(stats.get("sold_out", 0))) * 0.001
	# Popularity is harder to raise near the top.
	if delta > 0.0:
		delta *= 1.0 - 0.6 * popularity
	return delta

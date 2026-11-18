class_name Economy
extends RefCounted
## Pure functions describing how customers react to prices, quality, weather and
## waiting, and how the station chain (counter -> kitchen -> seats) limits a day.
## No state in here, so everything is easy to test and tune.

const BASE_QUEUE_CAP := 4
const PASSERS_PER_HOUR := 60.0
const DINE_IN_SPEND := 1.35
## Add-on chances per food portion (DaySim._addons): side, drink by weather, sweet; a diner
## adds ADDON_DINE_BONUS to each. The pick within a kind is uniform.
const ADDON_SIDE := 0.4
const ADDON_SWEET := 0.35
const ADDON_DINE_BONUS := 0.25
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
	var p := base_stop_chance(popularity)
	# No floor: an overpriced or awful menu really does empty the street.
	p *= clampf(best_value / 0.8, 0.0, 1.6)
	p *= 1.0 + boost * promo_power
	p *= 1.0 - competition_loss(competition, boost, promo_power)
	p *= 1.0 - 0.55 * float(queue_len) / float(queue_cap)
	return clampf(p, 0.0, 0.9)

## How hard a popularity pulls passers-by in, 0..1 (Data.FAME_DRAW, linear between points).
static func fame_draw(popularity: float) -> float:
	var pts: Array = Data.FAME_DRAW
	var pop := clampf(popularity, 0.0, 1.0)
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if pop <= float(b[0]):
			var span := maxf(float(b[0]) - float(a[0]), 0.000001)
			return lerpf(float(a[1]), float(b[1]), (pop - float(a[0])) / span)
	return float(pts.back()[1])

## The chance a passer-by stops at the best value on offer, before value/promotion/line:
## the HUD's "x in 100 passers stop" line.
static func base_stop_chance(popularity: float) -> float:
	return 0.05 + 0.20 * fame_draw(popularity)

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
		penalty *= float(Data.STATIONS["shade"]["storm_cut"])
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
		rate *= 1.0 + float(Data.STATIONS["shade"]["hot_traffic_per_level"]) * shade
	var lights := int(ctx.get("lights_level", 0))
	var lamps: Dictionary = Data.STATIONS["lights"]
	if lights > 0 and hour >= float(lamps["evening_from"]):
		rate *= 1.0 + float(lamps["evening_traffic_per_level"]) * lights
	return rate * float(ctx.get("traffic_mult", 1.0))

## Passer-by multiplier of the opening buzz on a given day (Data.OPENING): "traffic" on day 1,
## a straight line down to 1.0 the day after the last buzz day.
static func opening_boost(day: int) -> float:
	var days := int(Data.OPENING["days"])
	if day > days or days <= 0:
		return 1.0
	var left := float(days - maxi(day, 1) + 1) / float(days)
	return 1.0 + (float(Data.OPENING["traffic"]) - 1.0) * left

## A campaign's price at a stage tier (Data.MARKETING "cost" x Data.PROMO_SCALE).
static func campaign_cost(def: Dictionary, stage: int) -> float:
	var scale: Array = Data.PROMO_SCALE
	return float(def["cost"]) * float(scale[clampi(stage, 0, scale.size() - 1)])

## The extra stop chance a campaign gives today (before the place's promo_power):
## offers to regulars grow with the guests served so far, a blogger's word follows how
## happy the recent guests were (Data.MARKETING notes).
static func campaign_boost(def: Dictionary, total_served: int, recent_satisfaction: float) -> float:
	var boost := float(def["boost"])
	if def.has("regulars_full"):
		boost *= clampf(float(total_served) / float(def["regulars_full"]), 0.0, 1.0)
	if def.has("sat_full"):
		var lo := float(def["sat_floor"])
		boost *= clampf((recent_satisfaction - lo) / (float(def["sat_full"]) - lo), 0.0, 1.0)
	return boost

## Popularity change when a reviewed campaign (the blogger) ends, from the guests'
## average satisfaction on its days.
static func campaign_review(def: Dictionary, satisfaction: float) -> float:
	if not def.has("review"):
		return 0.0
	if satisfaction >= float(def["review_good"]):
		return float(def["review"])
	if satisfaction < float(def["review_bad"]):
		return -float(def["review"])
	return 0.0

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
	var m := mood(s)
	return "bad_quality" if m == "bad" else m

## How a guest leaves: "great" (>= Data.MOOD_GREAT), "ok" (>= Data.MOOD_OK) or "bad".
static func mood(s: float) -> String:
	if s >= Data.MOOD_GREAT:
		return "great"
	if s >= Data.MOOD_OK:
		return "ok"
	return "bad"

## The value of an ordinary dish: a passer who would have stopped for one, finding nothing of
## the kind they want on the menu, counts as a "no_item" loss.
const NO_ITEM_VALUE := 0.8

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

## The fame change of a day's stats so far (the HUD's live trend; Game.end_day settles with
## fame_change): never below the level `popularity` has reached.
static func popularity_delta(stats: Dictionary, popularity: float) -> float:
	return float(fame_change(stats, popularity)["delta"])

## A day's guests in fame points (Data.FAME_POINTS): {up (from great and ok faces), down (from
## bad faces and lost guests, as a positive number), happy (great), content (ok), unhappy
## (bad), lost (left a slow line or met a sold-out dish)}. Books without the faces (older
## rows, hand-made stats) count every buyer by the day's average satisfaction.
static func fame_points(stats: Dictionary) -> Dictionary:
	var great := int(stats.get("mood_great", 0))
	var ok := int(stats.get("mood_ok", 0))
	var bad := int(stats.get("mood_bad", 0))
	var served := int(stats.get("served", 0))
	if great + ok + bad == 0 and served > 0:
		match mood(float(stats.get("satisfaction_sum", 0.0)) / served):
			"great": great = served
			"ok": ok = served
			_: bad = served
	var lost := maxi(0, int(stats.get("left_wait", 0))) + maxi(0, int(stats.get("sold_out", 0)))
	var pts: Dictionary = Data.FAME_POINTS
	return {"up": great * float(pts["great"]) + ok * float(pts["ok"]),
		"down": bad * -float(pts["bad"]) + lost * -float(pts["lost"]),
		"happy": great, "content": ok, "unhappy": bad, "lost": lost}

## Popularity one fame point is worth at a level: the level's bar over its "guests".
static func fame_step(level: int) -> float:
	var lvl := clampi(level, 0, Data.FAME_LEVELS.size() - 1)
	var top := 1.0 if lvl >= Data.FAME_LEVELS.size() - 1 else float(Data.FAME_LEVELS[lvl + 1]["from"])
	return (top - float(Data.FAME_LEVELS[lvl]["from"])) / float(Data.FAME_LEVELS[lvl]["guests"])

## Popularity after `points` fame points from `pop`, climbing through the levels: each level
## spends the points at its own (slower and slower) rate.
static func fame_after(pop: float, points: float) -> float:
	var p := clampf(pop, 0.0, 1.0)
	var left := points
	var guard := 0
	while left > 0.0 and p < 1.0 and guard < 16:
		guard += 1
		var lvl := fame_level(p)
		var top := 1.0 if lvl >= Data.FAME_LEVELS.size() - 1 else float(Data.FAME_LEVELS[lvl + 1]["from"])
		var step := fame_step(lvl)
		var room := maxf(0.0, top - p) / step
		if left <= room:
			p += left * step
			left = 0.0
		else:
			p = top
			left -= room
	return minf(p, 1.0)

## A day's fame from `pop`, guest by guest: the happy and content guests' points climb first
## (gain), then the unhappy faces and lost guests take theirs back at the level reached
## (loss), at most Data.FAME_DAY_LOSS_MAX and never below that level's threshold nor
## `floor_pop`. `rate` scales every point (local fame: Data.LOCAL_FAME_RATE).
## {gain, loss (positive), delta (= gain - loss), after, points: fame_points(stats)}.
static func fame_change(stats: Dictionary, pop: float, rate: float = 1.0, floor_pop: float = 0.0) -> Dictionary:
	var pts := fame_points(stats)
	var climbed := fame_after(pop, float(pts["up"]) * rate)
	var lvl := fame_level(climbed)
	var drop := minf(float(pts["down"]) * rate * fame_step(lvl), Data.FAME_DAY_LOSS_MAX)
	var after := maxf(climbed - drop, maxf(fame_floor(lvl), floor_pop))
	return {"gain": climbed - pop, "loss": climbed - after, "delta": after - pop, "after": after, "points": pts}

## A plot you have not visited loses a little local fame per day, never below 0.1 nor below
## `floor_pop` (the threshold of the best local level reached there: a level is never lost).
static func reputation_decay(current: float, days_away: int, floor_pop: float = 0.0) -> float:
	return maxf(maxf(0.1, floor_pop), current - REPUTATION_DECAY_PER_DAY * maxi(days_away, 0))

# ---------------------------------------------------------------- fame levels (Data.FAME_LEVELS)

## Popularity a hair under a threshold still counts as reaching it (float sums).
const FAME_EPS := 0.000001

## Index of the fame level a popularity value has reached.
static func fame_level(pop: float) -> int:
	var lvl := 0
	for i in range(Data.FAME_LEVELS.size()):
		if pop >= float(Data.FAME_LEVELS[i]["from"]) - FAME_EPS:
			lvl = i
	return lvl

## 0..1 along the bar from this level's threshold to the next; 1.0 at the top level.
static func fame_progress(pop: float) -> float:
	var lvl := fame_level(pop)
	if lvl >= Data.FAME_LEVELS.size() - 1:
		return 1.0
	var lo := float(Data.FAME_LEVELS[lvl]["from"])
	var hi := float(Data.FAME_LEVELS[lvl + 1]["from"])
	return clampf((pop - lo) / (hi - lo), 0.0, 1.0)

## Level plus the bar's progress (2.4 = level 2, 40% of the way to level 3); the top level
## counts as its index. Fame goals measure the climb with it.
static func fame_value(pop: float) -> float:
	var lvl := fame_level(pop)
	if lvl >= Data.FAME_LEVELS.size() - 1:
		return float(lvl)
	return float(lvl) + fame_progress(pop)

## The level a requirement (an unlock_pop, a requires_local_rep, a min_popularity) asks
## for: the lowest level whose threshold is at or above it, so the UI can name it.
static func fame_level_for(threshold: float) -> int:
	for i in range(Data.FAME_LEVELS.size()):
		if float(Data.FAME_LEVELS[i]["from"]) >= threshold - FAME_EPS:
			return i
	return Data.FAME_LEVELS.size() - 1

## The popularity a level starts at (the floor once it is reached).
static func fame_floor(level: int) -> float:
	return float(Data.fame_def(level)["from"])

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

# ---------------------------------------------------------------- service clock (sim-seconds)

## How much faster the counter takes orders and hands bags over than at level 0.
static func counter_speed(level: int) -> float:
	return 1.0 + float(Data.STATIONS["counter"]["per_level"]) * maxi(level, 0)

## Seconds a buyer spends giving the order of a party at the counter.
static func order_seconds(portions: int, counter_level: int) -> float:
	var s: Dictionary = Data.SERVICE
	return (float(s["order_s"]) + float(s["order_per_portion_s"]) * maxi(portions - 1, 0)) / counter_speed(counter_level)

## Seconds the pickup counter is busy handing a party's bag over.
static func handoff_seconds(portions: int, counter_level: int) -> float:
	var s: Dictionary = Data.SERVICE
	return (float(s["handoff_s"]) + float(s["handoff_per_portion_s"]) * maxi(portions - 1, 0)) / counter_speed(counter_level)

## One-portion orders the counter can take per sim-second (ignoring the walk up).
static func counter_capacity(level: int) -> float:
	return 1.0 / order_seconds(1, level)

static func queue_cap(counter_level: int, stage: Dictionary) -> int:
	return BASE_QUEUE_CAP + counter_level * int(Data.STATIONS["counter"]["queue_per_level"]) + int(stage.get("queue_bonus", 0))

## Portions a kitchen station finishes per sim-second (0 while it is not owned yet).
static func kitchen_capacity(id: String, level: int, stage: int = 0) -> float:
	var def: Dictionary = Data.STATIONS[id]
	var cook: Dictionary = Data.SERVICE["cook_s"]
	if level < int(def.get("owned_from", 0)) or not cook.has(id):
		return 0.0
	var crew: Array = Data.SERVICE["kitchen_crew"]
	return (1.0 + float(def.get("per_level", 0.0)) * level) / float(cook[id]) * float(crew[clampi(stage, 0, crew.size() - 1)])

## [[portions, weight], ...] for a buyer at this stage and place.
static func party_weights(stage: int, location_id: String) -> Array:
	var groups := float(Data.LOCATIONS.get(location_id, {}).get("groups", 1.0))
	var out := []
	for pair in Data.PARTY_SIZES[clampi(stage, 0, Data.PARTY_SIZES.size() - 1)]:
		out.append([int(pair[0]), float(pair[1]) * (groups if int(pair[0]) >= 3 else 1.0)])
	return out

static func party_mean(weights: Array) -> float:
	var total := 0.0
	var sum := 0.0
	for pair in weights:
		total += float(pair[1])
		sum += float(pair[0]) * float(pair[1])
	return sum / total if total > 0.0 else 1.0

## Mean of f(portions) over the party distribution.
static func party_average(weights: Array, f: Callable) -> float:
	var total := 0.0
	var sum := 0.0
	for pair in weights:
		total += float(pair[1])
		sum += float(f.call(int(pair[0]))) * float(pair[1])
	return sum / total if total > 0.0 else float(f.call(1))

## Draw one party size from the business RNG.
static func pick_party(weights: Array, rng: RandomNumberGenerator) -> int:
	if weights.is_empty():
		return 1
	var total := 0.0
	for pair in weights:
		total += float(pair[1])
	var r := rng.randf() * total
	for pair in weights:
		r -= float(pair[1])
		if r <= 0.0:
			return int(pair[0])
	return int(weights.back()[0])

## Buyers that may be on the street at once (see Data.GUEST_BUDGET).
static func buyer_budget(stage: int, counter_level: int) -> int:
	var b: Dictionary = Data.GUEST_BUDGET
	var t := clampi(stage, 0, b["buyers"].size() - 1)
	var n := int(b["buyers"][t]) + int(floor(Data.station_tier(counter_level) * float(b["per_counter_tier"])))
	return mini(mini(n, int(b["buyers_max"][t])), int(b["total_max"]) - ambient_budget(stage))

static func ambient_budget(stage: int) -> int:
	var b: Dictionary = Data.GUEST_BUDGET
	return int(b["ambient"][clampi(stage, 0, b["ambient"].size() - 1)])

## Chairs the terrace of a stage actually has room for (Plot builds tables of two).
static func terrace_seats(stage: int, seats: int) -> int:
	if stage < Plot.FIXED or seats < 2:
		return 0
	var gap := Plot.footprint(stage)
	var per_row := 0
	var x := Plot.FIRST_TABLE_X
	while x - 0.34 >= -gap + 0.03:
		per_row += 1
		x -= Plot.TABLE_PITCH
	var tables := mini(mini(seats, int(Plot.SEAT_CAP[clampi(stage, 0, Plot.SEAT_CAP.size() - 1)])) / 2, per_row * Plot.ROWS.size())
	return tables * 2

## Restaurant workers who carry meals and clear tables (Plot._configure_dining_staff).
static func dining_workers(stage: int, seats: int, staffroom: int) -> int:
	if stage < Plot.FIXED or seats < 2:
		return 0
	return mini(3, 1 + (1 if stage >= 4 and seats >= 4 else 0) + (1 if staffroom > 0 else 0))

## The day's wage bill (Data.WAGES) for a stand at `stage` running `stations` ({id: level})
## with `seats` chairs on its terrace: nothing at the cart and stall, the truck's helper, and
## from the kiosk up the cashier, the cooks and baristas of every running kitchen station
## (kitchen crew per station) and the dining workers the counter crew does not cover, at the
## stage's pay grade (whole 5 AED).
static func daily_wages(stage: int, stations: Dictionary, seats: int) -> float:
	var w: Dictionary = Data.WAGES
	if stage < Plot.FIXED:
		return float(w["helper"]) if stage >= int(w["helper_from"]) else 0.0
	var roles: Dictionary = w["roles"]
	var crew_table: Array = Data.SERVICE["kitchen_crew"]
	var crew := float(crew_table[clampi(stage, 0, crew_table.size() - 1)])
	var bill := float(roles["cashier"])
	for id in stations:
		var def: Dictionary = Data.STATIONS.get(id, {})
		if not def.has("kinds") or kitchen_capacity(id, int(stations[id]), stage) <= 0.0:
			continue
		var role := String(def.get("roles", ["cook"])[0])
		bill += float(roles.get(role, roles["cook"])) * crew
	var covered: Array = w["counter_covers_tables"]
	var servers := dining_workers(stage, seats, int(stations.get("staffroom", 0))) - int(covered[clampi(stage, 0, covered.size() - 1)])
	bill += float(roles["server"]) * maxi(0, servers)
	var grade: Array = w["grade"]
	return snappedf(bill * float(grade[clampi(stage, 0, grade.size() - 1)]), 5.0)

## What the visible walking costs at this stage and street (Data.SERVICE "walk").
static func walk_times(stage: int, location_id: String) -> Dictionary:
	var group := "cart" if stage < 2 else ("truck" if stage == 2 else "fixed")
	var street := "promenade" if Paving.DESIGNS.has(location_id) else "road"
	var out := WALK_DEFAULTS.duplicate()
	var measured: Dictionary = Data.SERVICE["walk"].get(group, {}).get(street, {})
	for k in measured:
		out[k] = float(measured[k])
	# A deeper terrace means longer walks to the far tables.
	if stage >= Plot.FIXED:
		var terrace: Dictionary = Data.SERVICE["walk"]["terrace"]
		for k in terrace:
			var extra: Array = terrace[k]
			out[k] = float(out[k]) + float(extra[clampi(stage - Plot.FIXED, 0, extra.size() - 1)])
	return out

## Legs that are the same everywhere (and fallbacks for walk_times), in sim-seconds.
const WALK_DEFAULTS := {"in": 5.22, "line": 1.6, "step": 0.7, "pickup": 0.5, "out": 7.0, "turn": 6.5,
	"pass": 8.6, "seat": 3.3, "seat_out": 7.0, "deliver": 4.1, "back": 1.5, "clean": 5.1}

static func addon_drink_chance(weather_id: String) -> float:
	return 0.65 if weather_id == "hot" else (0.2 if weather_id == "breeze" else 0.3)

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

## Share of served customers who sit down to eat (0 without seats or below the kiosk).
static func dine_in_share(stage: Dictionary, seats: int) -> float:
	if seats <= 0:
		return 0.0
	return float(stage.get("dine_in", 0.0)) * clampf(seats / 4.0, 0.0, 1.0)

static func spend_multiplier(majlis_level: int = 0) -> float:
	return DINE_IN_SPEND + float(Data.STATIONS["majlis"]["spend_per_level"]) * majlis_level

## Erlang loss: the chance an arrival finds all `servers` places taken at offered load `a`
## (arrivals x mean holding time). It does not depend on how holding times are spread.
static func erlang_b(servers: int, a: float) -> float:
	if servers <= 0:
		return 1.0
	var b := 1.0
	for k in range(1, servers + 1):
		b = a * b / (float(k) + a * b)
	return b

## Share of time at most `n` of `servers` places are taken at offered load `a`.
static func occupancy_at_most(servers: int, a: float, n: int) -> float:
	if n < 0:
		return 0.0
	var term := 1.0
	var total := 1.0
	var below := 1.0
	for k in range(1, servers + 1):
		term *= a / float(k)
		total += term
		if k <= n:
			below += term
	return below / total

## Mean wait in front of one server busy `rho` of the time with service time `service`.
## Mean wait in a queue of one server at utilisation rho (M/D/1). Past 0.97 the wait keeps
## climbing steeply instead of becoming infinite, so an overloaded station throttles the
## street smoothly in the estimate's balance.
static func _queue_wait(service: float, rho: float) -> float:
	var r := clampf(rho, 0.0, 0.97)
	var wait := service * r / (2.0 * (1.0 - r))
	if rho > 0.97:
		wait += service * (rho - 0.97) * 400.0
	return wait

## Estimates run so far (a cost meter for tests: the advisor's rank must stay cheap).
static var estimate_calls := 0

## The played day, analytically, on the same service clock as DaySim (Data.SERVICE). Per
## game hour the street's buyer places form a closed loop (_estimate_hour): a free place
## waits for the next passer who would stop, then is held for the walk in, the line, the
## order, the cooking, the handoff or the meal, and the walk out, queueing at the counter,
## the kitchen stations and the hatch; chairs and servers are a loss system beside it.
## Tests/sim_parity.gd holds it within 20% of the played day.
## Returns {want, served (buyers), portions, left, crowd, dine_in, revenue, cogs, profit,
## util{station: 0..}, bottleneck, wait (mean seconds a buyer waits in line and for the
## food), moods{great, ok, bad} (buyers a day by face), fame_points (the day's fame points:
## Data.FAME_POINTS over the faces and the buyers lost to the line)}.
static func throughput_estimate(ctx: Dictionary) -> Dictionary:
	estimate_calls += 1
	var loc_id := String(ctx["location"])
	var loc: Dictionary = Data.LOCATIONS[loc_id]
	var weather: String = ctx["weather"]
	var offer: Array = ctx.get("offer", [])
	var stage := int(ctx.get("stage", 0))
	var ds := drink_share(weather)
	var sums := {"food": 0.0, "drink": 0.0}
	var best := {"food": 0.0, "drink": 0.0}
	var best_ratio := {"food": 1.0, "drink": 1.0}
	for o in offer:
		var kind := String(o["kind"])
		if int(o.get("stock", 1)) <= 0 or not sums.has(kind):
			continue
		sums[kind] += float(o["value"])
		if float(o["value"]) > float(best[kind]):
			best[kind] = float(o["value"])
			best_ratio[kind] = float(o["price"]) / float(Data.MENU_ITEMS[o["id"]]["base_price"])
	var station_of_kind: Dictionary = ctx.get("station_of_kind", {})
	var kitchen: Dictionary = ctx.get("kitchen", {})
	var appeal := float(ctx.get("appeal", 1.0))
	var pop := float(ctx.get("popularity", 0.2))
	var qcap := int(ctx.get("queue_cap", BASE_QUEUE_CAP))
	var comp := float(ctx.get("competition", 0.0))
	var promo := float(ctx.get("promo_power", 1.0))
	var boost := float(ctx.get("boost", 0.0))
	# Who stops: a food or a drink seeker, each only when that kind is on offer.
	var want_mix := {"food": 1.0 - ds, "drink": ds}
	var kind_frac := {"food": 0.0, "drink": 0.0}
	var kind_total := 0.0
	for kind in want_mix:
		if float(sums[kind]) > 0.0:
			kind_frac[kind] = float(want_mix[kind]) * stop_probability(pop, float(best[kind]) * appeal, boost, 0, qcap, comp, promo)
			kind_total += float(kind_frac[kind])
	for kind in kind_frac:
		kind_frac[kind] = float(kind_frac[kind]) / kind_total if kind_total > 0.0 else 0.0
	# Per buyer: which station cooks the order, and the price and cost of one portion.
	var shares := {}
	var avg_price := 0.0
	var avg_cost := 0.0
	var food_share := float(kind_frac["food"])
	var food_price := 0.0
	var plates := [] # [share of buyers, quality, price ratio] per dish, for the faces
	for o in offer:
		var kind := String(o["kind"])
		if int(o.get("stock", 1)) <= 0 or not sums.has(kind) or float(sums[kind]) <= 0.0:
			continue
		var share := float(kind_frac[kind]) * float(o["value"]) / float(sums[kind])
		if share <= 0.0:
			continue
		plates.append([share, float(o.get("quality", 0.72)), float(o["price"]) / float(Data.MENU_ITEMS[o["id"]]["base_price"])])
		var station := String(station_of_kind.get(String(o.get("station_kind", "")), ""))
		if station != "" and float(kitchen.get(station, 0.0)) <= 0.0:
			station = ""
		shares[station] = float(shares.get(station, 0.0)) + share
		avg_price += share * float(o["price"])
		avg_cost += share * float(o["unit_cost"])
		if kind == "food":
			food_price += share * float(o["price"])
	# Add-ons each food portion may bring (DaySim._addons): uniform pick, price-dependent appeal.
	var addon_rev := 0.0
	var addon_cost := 0.0
	var addon_dine_rev := 0.0
	var addon_dine_cost := 0.0
	for group in [["side", ADDON_SIDE], ["drink", addon_drink_chance(weather)], ["sweet", ADDON_SWEET]]:
		var picks := []
		for o in offer:
			if String(o["kind"]) == String(group[0]) and int(o.get("stock", 1)) > 0:
				picks.append(o)
		if picks.is_empty():
			continue
		for o in picks:
			var appeal_i := clampf(1.6 - float(o["price"]) / float(Data.MENU_ITEMS[o["id"]]["base_price"]) * 0.9, 0.0, 1.0)
			var w_i := appeal_i / float(picks.size())
			addon_rev += float(group[1]) * w_i * float(o["price"])
			addon_cost += float(group[1]) * w_i * float(o["unit_cost"])
			addon_dine_rev += ADDON_DINE_BONUS * w_i * float(o["price"])
			addon_dine_cost += ADDON_DINE_BONUS * w_i * float(o["unit_cost"])
	var party: Array = ctx.get("party", party_weights(stage, loc_id))
	var m := party_mean(party)
	var m2 := party_average(party, func(p: int) -> float: return float(p * p))
	# Only parties that fit a table eat in.
	var dine_max := int(Data.SERVICE["dine_max_party"])
	var p_small := party_average(party, func(p: int) -> float: return 1.0 if p <= dine_max else 0.0)
	var m_small := party_average(party, func(p: int) -> float: return float(p) if p <= dine_max else 0.0) / maxf(p_small, 0.000001)
	var cl := int(ctx.get("counter_level", 0))
	var order_t := party_average(party, func(p: int) -> float: return order_seconds(p, cl))
	var hand_t := party_average(party, func(p: int) -> float: return handoff_seconds(p, cl))
	var w: Dictionary = ctx.get("walk", walk_times(stage, loc_id))
	var budget := int(ctx.get("buyers", buyer_budget(stage, cl)))
	var spare := int(Data.GUEST_BUDGET["spare_for_reactions"])
	var seats := int(ctx.get("seats", 0))
	var dine_share := float(ctx.get("dine_in_share", 0.0)) if seats > 0 else 0.0
	var workers := int(ctx.get("workers", dining_workers(stage, seats, 0)))
	if workers <= 0:
		dine_share = 0.0
	var dine_t := float(ctx.get("dine_s", Data.SERVICE["dine_s"]))
	var patience := float(ctx.get("patience_s", Data.SERVICE["patience_s"]))
	var hours: Array = ctx["hours"]
	var hour_s := Data.REAL_SECONDS_PER_GAME_HOUR
	var totals := {"want": 0.0, "buyers": 0.0, "left": 0.0, "crowd": 0.0, "diners": 0.0}
	var util := {"counter": 0.0}
	for s in kitchen:
		util[s] = 0.0
	if seats > 0:
		util["seating"] = 0.0
	var closing_gain := 0.0
	var wait_sum := 0.0 # buyer-weighted wait in line and for the food (beyond their own cooking)
	var h := float(hours[0])
	while h < float(hours[1]):
		var arrivals := arrival_rate(loc, weather, h + 0.5, ctx) / hour_s
		var pot := float(ctx.get("cars_per_hour", 0.0)) / hour_s
		var react_occ := 0.0
		for kind in want_mix:
			var share := float(want_mix[kind])
			if share <= 0.0 or float(sums[kind]) <= 0.0:
				continue
			var v := float(best[kind]) * appeal
			var p_room := stop_probability(pop, v, boost, 0, qcap, comp, promo)
			var p_any := stop_probability(pop, v, boost, 0, qcap)
			pot += arrivals * share * p_room
			var top := p_room
			if comp > 0.0 and p_any > p_room:
				react_occ += arrivals * share * (p_any - p_room) * (float(w["in"]) + float(w["pass"]))
				top = p_any
			if float(best[kind]) < 0.55 and float(best_ratio[kind]) > 1.20 and p_room * 1.5 > top:
				react_occ += arrivals * share * (p_room * 1.5 - top) * (float(w["in"]) + float(w["turn"]))
		var hp := {"w": w, "order_t": order_t, "hand_t": hand_t, "shares": shares, "kitchen": kitchen, "m": m, "m2": m2,
			"budget": budget, "spare": spare, "food_share": food_share, "dine_share": dine_share, "seats": seats,
			"workers": workers, "dine_t": dine_t, "qcap": qcap, "pot": pot, "react_occ": react_occ, "p_small": p_small}
		var r := _estimate_hour(hp)
		var accepted := float(r["x"])
		var buyers := accepted * float(r["join"])
		var wq := float(r["wq"])
		var rho_c := float(r["u_counter"])
		var left := buyers * clampf(rho_c, 0.0, 1.0) * exp(-patience / maxf(wq, 0.001))
		totals["want"] += pot * hour_s
		totals["buyers"] += (buyers - left) * hour_s
		totals["left"] += left * hour_s
		totals["crowd"] += maxf(0.0, pot - accepted) * hour_s
		totals["diners"] += buyers * float(r["dine"]) * hour_s
		wait_sum += (buyers - left) * (wq + float(r["post_wait"])) * hour_s
		# The day's edges: the first buyers meet empty queues, and orders taken before closing
		# are still served afterwards, while buyers walking up or waiting to order go home.
		closing_gain = (buyers - left) * (float(r["post_wait"]) - float(r["pre_order"]))
		var hour_util := {"counter": rho_c}
		var rho: Dictionary = r["rho"]
		for st in rho:
			hour_util[st] = float(rho[st])
		hour_util = street_util(hour_util, 1.0 - float(r["free"]) / float(maxi(budget, 1)))
		for st in hour_util:
			util[st] = maxf(float(util.get(st, 0.0)), float(hour_util[st]))
		if seats > 0:
			util["seating"] = maxf(float(util["seating"]), float(r["chair_load"]) / float(seats))
		h += 1.0
	totals["buyers"] = maxf(0.0, float(totals["buyers"]) + closing_gain)
	var served := float(totals["buyers"])
	var portions := served * m
	var dine_in := float(totals["diners"]) * served / maxf(served + float(totals["left"]), 0.001)
	var dine_portions := dine_in * m_small
	var food_portions := portions * food_share
	var spend := float(ctx.get("spend_mult", DINE_IN_SPEND))
	var dine_food_price := food_price / food_share if food_share > 0.0 else 0.0
	var revenue := portions * avg_price + dine_portions * dine_food_price * (spend - 1.0) \
		+ food_portions * addon_rev + dine_portions * addon_dine_rev
	var cogs := portions * avg_cost + food_portions * addon_cost + dine_portions * addon_dine_cost
	var fixed := float(loc.get("rent", 0.0)) + float(ctx.get("wages", 0.0))
	# The faces: each dish's satisfaction at the day's mean wait, and what they do to fame.
	var wait_mean := wait_sum / maxf(served, 0.001)
	var faces := mood_shares(plates, loc, float(ctx.get("satisfaction_bonus", 0.0)), wait_mean, patience, dine_in / maxf(served, 0.001))
	var moods := {"great": served * float(faces["great"]), "ok": served * float(faces["ok"]), "bad": served * float(faces["bad"])}
	var fp: Dictionary = Data.FAME_POINTS
	var points := float(moods["great"]) * float(fp["great"]) + float(moods["ok"]) * float(fp["ok"]) \
		+ float(moods["bad"]) * float(fp["bad"]) + float(totals["left"]) * float(fp["lost"])
	return {
		"want": float(totals["want"]), "served": served, "portions": portions, "left": float(totals["left"]),
		"crowd": float(totals["crowd"]), "dine_in": dine_in,
		"revenue": revenue, "cogs": cogs, "profit": revenue - cogs - fixed,
		"util": util, "bottleneck": bottleneck(util),
		"wait": wait_mean, "moods": moods, "fame_points": points,
	}

## Share of buyers leaving with each face ({great, ok, bad}, summing to 1) for dishes
## `plates` = [[share of buyers, quality, price ratio]], a day whose waits average
## `wait_mean` seconds (spread like a queue's: exponential) against `patience`, and
## `dine_frac` of buyers eating in (+0.05, as in the played day).
static func mood_shares(plates: Array, loc: Dictionary, bonus: float, wait_mean: float, patience: float, dine_frac: float) -> Dictionary:
	var total := 0.0
	var great := 0.0
	var fine := 0.0
	var d := clampf(dine_frac, 0.0, 1.0)
	for pl in plates:
		var share := float(pl[0])
		total += share
		for sit in [[1.0 - d, 0.0], [d, 0.05]]:
			if float(sit[0]) <= 0.0:
				continue
			var s0 := satisfaction(float(pl[1]), float(pl[2]), 0.0, loc, bonus + float(sit[1]))
			great += share * float(sit[0]) * _wait_within(s0 - Data.MOOD_GREAT, wait_mean, patience)
			fine += share * float(sit[0]) * _wait_within(s0 - Data.MOOD_OK, wait_mean, patience)
	if total <= 0.0:
		return {"great": 0.0, "ok": 0.0, "bad": 0.0}
	great /= total
	fine /= total
	return {"great": great, "ok": maxf(0.0, fine - great), "bad": maxf(0.0, 1.0 - fine)}

## Chance that a wait (exponential, mean `wait_mean`) costs less than `margin` satisfaction
## (a full patience of waiting costs 0.25).
static func _wait_within(margin: float, wait_mean: float, patience: float) -> float:
	if margin < 0.0:
		return 0.0
	var x := margin / 0.25
	if x >= 1.0 or wait_mean <= 0.001:
		return 1.0
	return 1.0 - exp(-x * patience / wait_mean)

## What `points` more fame points a day are worth in AED a day: the fame they add over
## `horizon` days (Data.FAME_HORIZON_DAYS) from `pop`, climbing through the levels, times
## `slope` (AED a day per unit of popularity: what the extra passers bring, from the
## estimate), averaged over the horizon (the fame comes in day by day).
static func fame_worth(points: float, pop: float, slope: float, horizon: float = -1.0) -> float:
	var days := Data.FAME_HORIZON_DAYS if horizon < 0.0 else horizon
	return slope * fame_reach(points, pop, days) * 0.5

## Popularity `points` fame points a day add (or take, never below the level) in `days` days.
static func fame_reach(points: float, pop: float, days: float) -> float:
	if points >= 0.0:
		return fame_after(pop, points * days) - pop
	var lvl := fame_level(pop)
	return -minf(minf(-points * fame_step(lvl), Data.FAME_DAY_LOSS_MAX) * days, pop - fame_floor(lvl))

## One game hour of the estimate. The street is a closed loop of `budget` buyer places
## (exact mean value analysis): a free place waits for the next passer who would stop
## (Poisson, rate pot), then the visit walks in, queues at the counter, waits for its
## station in the kitchen (parties of varying size), collects at the hatch or eats at a
## table, and walks out. An overloaded station then throttles the street the way the
## played day does: the places fill with people waiting, and newcomers walk on.
static func _estimate_hour(p: Dictionary) -> Dictionary:
	var w: Dictionary = p["w"]
	var shares: Dictionary = p["shares"]
	var kitchen: Dictionary = p["kitchen"]
	var m := float(p["m"])
	var m2 := float(p["m2"])
	var order_t := float(p["order_t"])
	var hand_t := float(p["hand_t"])
	var pot := maxf(float(p["pot"]), 0.000001)
	var seats := int(p["seats"])
	var food_share := float(p["food_share"])
	var step := float(w["step"])
	# Own cooking per station and the walk it overlaps (to the pickup spot or the chair).
	var own := {}
	var none_share := float(shares.get("", 0.0))
	for st in shares:
		if st != "":
			own[st] = m / float(kitchen[st])
	var overlap := func(walk: float) -> float:
		var t := none_share * walk
		for st in own:
			t += float(shares[st]) * maxf(0.0, walk - float(own[st]))
		return t
	var over_take: float = overlap.call(float(w["pickup"]))
	var over_dine: float = overlap.call(float(w["seat"]))
	var join := 1.0
	var dine_open := food_share * float(p["dine_share"]) * float(p["p_small"])
	var dine := dine_open if seats > 0 else 0.0
	var wd := 0.0
	var chair_block := 0.0
	var chair_load := 0.0
	var n_eff := float(p["budget"])
	var r := {}
	for outer in range(12):
		var zt := float(w["in"]) + float(w["line"])
		var z := join * (zt + (1.0 - dine) * (over_take + float(w["out"])) \
			+ dine * (over_dine + wd + float(w["deliver"]) + float(p["dine_t"]) + float(w["seat_out"]))) \
			+ (1.0 - join) * (float(w["in"]) + float(w["pass"]))
		var lo_n := int(floor(n_eff))
		var frac := n_eff - lo_n
		var a := _mva(lo_n, pot, z, join, dine, shares, own, m, m2, order_t, step, hand_t)
		r = a
		if frac > 0.001:
			var b := _mva(lo_n + 1, pot, z, join, dine, shares, own, m, m2, order_t, step, hand_t)
			r = {}
			for k in a:
				if a[k] is Dictionary:
					var mixed := {}
					for st in a[k]:
						mixed[st] = lerpf(float(a[k][st]), float(b[k][st]), frac)
					r[k] = mixed
				else:
					r[k] = lerpf(float(a[k]), float(b[k]), frac)
		var x := float(r["x"])
		# Standing in line (walking up included) puts the next passers off.
		var line_len := x * join * float(w["line"]) + float(r["q_counter"])
		var new_join := clampf(1.0 - 0.55 * line_len / float(p["qcap"]), 0.05, 1.0)
		var new_dine := 0.0
		if seats > 0 and float(p["dine_share"]) > 0.0:
			var waits := _server_waits(x * join * dine / float(maxi(int(p["workers"]), 1)), w)
			wd = float(waits["meal"])
			var cook := 0.0
			for st in own:
				cook += float(shares[st]) * (float(own[st]) + float(r["wait"][st]))
			var chair_t := maxf(float(w["seat"]), cook) + wd + float(w["deliver"]) + float(p["dine_t"]) + float(w["clean"]) * 0.5 + float(waits["table"])
			chair_load = x * join * dine_open * chair_t
			chair_block = erlang_b(seats, chair_load)
			new_dine = dine_open * (1.0 - chair_block)
		# Rival and price refusals only take places while plenty are free.
		var free := float(r["free"])
		var react_busy := float(p["react_occ"]) * _share_at_least(int(p["budget"]), free / maxf(float(p["budget"]), 1.0), int(p["spare"]))
		var new_n := maxf(1.0, float(p["budget"]) - react_busy)
		join = lerpf(join, new_join, 0.6)
		dine = lerpf(dine, new_dine, 0.6)
		n_eff = lerpf(n_eff, new_n, 0.6)
	r["join"] = join
	r["dine"] = dine
	r["chair_load"] = chair_load
	# Per buyer: the walk before the order, and the queueing after it (kitchen, hatch, server).
	r["pre_order"] = float(w["in"]) + float(w["line"]) + order_t
	var post := (1.0 - dine) * float(r["wait_hatch"]) + dine * wd
	for st in own:
		post += float(shares[st]) * float(r["wait"][st])
	r["post_wait"] = post
	return r

## How long a seated guest waits for a free server (meal) and a used table waits to be
## cleared (table), with `per_worker` diners a second for each worker. A worker takes a meal
## to a table as soon as one is waiting and clears tables in between, so meals queue ahead of
## the clearing (non-preemptive priority, M/G/1 per worker): a meal waits for the job in hand
## and for meals ahead of it; tables wait for every meal as well. Table clearing is one job
## per table of two, about 0.6 per diner.
static func _server_waits(per_worker: float, w: Dictionary) -> Dictionary:
	var meal_job := float(w["deliver"]) + float(w["back"])
	var clean_job := float(w["clean"])
	var tables := 0.6
	var rho_meal := per_worker * meal_job
	var rho_all := rho_meal + per_worker * tables * clean_job
	var residual := per_worker * (meal_job * meal_job + tables * clean_job * clean_job) / 2.0
	var meal := residual / maxf(1.0 - rho_meal, 0.03)
	var table := residual / (maxf(1.0 - rho_meal, 0.03) * maxf(1.0 - rho_all, 0.03))
	# Past full load the backlog grows through the day instead of settling.
	if rho_all > 0.97:
		table += clean_job * (rho_all - 0.97) * 400.0
	if rho_meal > 0.97:
		meal += meal_job * (rho_meal - 0.97) * 400.0
	return {"meal": meal, "table": table}

## Exact mean value analysis of n buyer places: the passer stream (one exponential server),
## the counter, every kitchen station and the hatch, plus the walking as pure delay z.
## Waits use the residual of the job in progress, so short deterministic beats and parties
## of mixed size queue the way they do on the street.
static func _mva(n: int, pot: float, z: float, join: float, dine: float, shares: Dictionary, own: Dictionary,
		m: float, m2: float, order_t: float, step: float, hand_t: float) -> Dictionary:
	var q_src := 0.0
	var q_c := 0.0
	var u_c := 0.0
	var q_h := 0.0
	var u_h := 0.0
	var q_k := {}
	var u_k := {}
	for st in own:
		q_k[st] = 0.0
		u_k[st] = 0.0
	var x := 0.0
	var r_c := 0.0
	var wait := {}
	var s_c := order_t + step
	var s_h := hand_t + step
	for i in range(1, n + 1):
		var r_src := (1.0 + q_src) / pot
		var w_c := maxf(0.0, q_c - u_c) * s_c + u_c * 0.5 * s_c
		r_c = join * (order_t + w_c)
		var r_k := 0.0
		for st in own:
			var res := m2 / (2.0 * m) * float(own[st]) / m
			var wk := maxf(0.0, float(q_k[st]) - float(u_k[st])) * float(own[st]) + float(u_k[st]) * res
			wait[st] = wk
			r_k += join * float(shares[st]) * (float(own[st]) + wk)
		var w_h := maxf(0.0, q_h - u_h) * s_h + u_h * 0.5 * hand_t
		var r_h := join * (1.0 - dine) * (hand_t + w_h)
		x = float(i) / (r_src + z + r_c + r_k + r_h)
		q_src = x * r_src
		q_c = x * r_c
		u_c = minf(1.0, x * join * s_c)
		q_h = x * r_h
		u_h = minf(1.0, x * join * (1.0 - dine) * hand_t)
		for st in own:
			q_k[st] = x * join * float(shares[st]) * (float(own[st]) + float(wait[st]))
			u_k[st] = minf(1.0, x * join * float(shares[st]) * float(own[st]))
	if n <= 0:
		for st in own:
			wait[st] = 0.0
	return {"x": x, "free": q_src, "q_counter": q_c, "u_counter": u_c, "wq": maxf(0.0, r_c / maxf(join, 0.001) - order_t),
		"rho": u_k.duplicate(), "wait": wait, "wait_hatch": maxf(0.0, q_h - u_h) * s_h + u_h * 0.5 * hand_t}

## Chance that at least k of n places are free when each is free with chance f.
static func _share_at_least(n: int, f: float, k: int) -> float:
	var below := 0.0
	var term := pow(1.0 - f, n)
	for i in range(0, mini(k, n + 1)):
		below += term
		if f >= 1.0:
			break
		term *= float(n - i) / float(i + 1) * f / maxf(1.0 - f, 0.000001)
	return clampf(1.0 - below, 0.0, 1.0)

## A street whose buyer places are full points at what keeps them there: a kitchen station
## that is itself busy (3/4 of the time or more), else the counter, whose levels add places.
static func street_util(util: Dictionary, street: float) -> Dictionary:
	var key := "counter"
	var worst := 0.75
	for s in util:
		if s != "counter" and s != "seating" and float(util[s]) >= worst:
			worst = float(util[s])
			key = s
	util[key] = maxf(float(util.get(key, 0.0)), 0.95 * clampf(street, 0.0, 1.0))
	return util

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
		"day_portions": return clampf(float(snap.get("day_portions", 0)) / n, 0.0, 1.0)
		"day_profit": return clampf(float(snap.get("day_profit", 0.0)) / n, 0.0, 1.0)
		"day_dine_in": return clampf(float(snap.get("day_dine_in", 0)) / n, 0.0, 1.0)
		"total_served": return clampf(float(snap.get("total_served", 0)) / n, 0.0, 1.0)
		"stars": return clampf(float(snap.get("stars", 0.0)) / n, 0.0, 1.0)
		# the climb to a fame level: level plus the bar's progress (fame_value)
		"fame": return clampf(float(snap.get("fame", 0.0)) / maxf(n, 1.0), 0.0, 1.0)
		"levels_owned": return clampf(float(snap.get("levels_owned", 0)) / n, 0.0, 1.0)
		"stage": return clampf(float(snap.get("stage", 0)) / n, 0.0, 1.0)
		"station_level": return clampf(float(snap.get("stations", {}).get(String(req["station"]), 0)) / n, 0.0, 1.0)
		"dish_level": return clampf(float(snap.get("dish_level", 0)) / n, 0.0, 1.0)
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
	var table := _pack_table(packs, deficit + _largest_pack(packs))
	var costs: PackedFloat64Array = table[0]
	var best := _cheapest_cover(costs, deficit)
	return {"cost": costs[best], "counts": _pack_counts(packs, table[1], best)}

## Stock bought ahead (what a cold box makes worth it): the cheapest whole packs for today's
## `deficit`, judged over two days. What is left tonight keeps `keep` of itself (1 - the
## spoil rate) and covers part of `tomorrow` (tomorrow's need, in units); tomorrow's gap is
## bought again at the cheapest whole-pack price. Buys past today's need only when that is
## cheaper over the two days than buying for today alone. {cost (today's bill), counts,
## qty (units bought), carry (units kept for tomorrow), two_day (today's bill + tomorrow's
## rebuy), plain_two_day (the same for the cheapest buy for today alone)}.
static func supply_packs_ahead(packs: Array, deficit: int, tomorrow: int, keep: float) -> Dictionary:
	if deficit <= 0:
		return {"cost": 0.0, "counts": [], "qty": 0, "carry": 0, "two_day": 0.0, "plain_two_day": 0.0}
	var largest := _largest_pack(packs)
	var need_next := maxi(0, tomorrow)
	var limit := deficit + need_next + largest
	var table := _pack_table(packs, limit)
	var costs: PackedFloat64Array = table[0]
	# cover[x] = the cheapest whole packs holding at least x units (tomorrow's rebuy)
	var cover := PackedFloat64Array()
	cover.resize(limit + 1)
	cover[limit] = INF
	for x in range(limit - 1, -1, -1):
		cover[x] = minf(costs[x], cover[x + 1])
	var two_day := func(q: int) -> Array:
		var left := q - deficit
		var kept := left - roundi(left * (1.0 - clampf(keep, 0.0, 1.0)))
		var gap := need_next - kept
		return [costs[q] + (cover[gap] if gap > 0 else 0.0), mini(kept, need_next)]
	var plain := _cheapest_cover(costs, deficit, deficit + largest)
	var plain_two: Array = two_day.call(plain)
	var best := plain
	var best_two: Array = plain_two
	for q in range(deficit, limit):
		if costs[q] == INF:
			continue
		var t: Array = two_day.call(q)
		if float(t[0]) < float(best_two[0]) - 0.005:
			best = q
			best_two = t
	return {"cost": costs[best], "counts": _pack_counts(packs, table[1], best), "qty": best, "carry": int(best_two[1]),
		"two_day": float(best_two[0]), "plain_two_day": float(plain_two[0])}

static func _largest_pack(packs: Array) -> int:
	var largest := 0
	for p in packs:
		largest = maxi(largest, int(p[0]))
	return largest

## [costs, choices]: the cheapest exact whole-pack cost of every quantity below `limit` (INF
## when no combination makes it) and the last pack of that combination.
static func _pack_table(packs: Array, limit: int) -> Array:
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
	return [costs, choices]

## The smallest quantity >= deficit (and below `below`, -1 = the table's end) with the lowest cost.
static func _cheapest_cover(costs: PackedFloat64Array, deficit: int, below: int = -1) -> int:
	var best := deficit
	for qty in range(deficit, costs.size() if below < 0 else mini(below, costs.size())):
		if costs[qty] < costs[best]:
			best = qty
	return best

static func _pack_counts(packs: Array, choices: PackedInt32Array, qty: int) -> Array:
	var counts := []
	counts.resize(packs.size())
	counts.fill(0)
	var q := qty
	while q > 0 and choices[q] >= 0:
		var idx := choices[q]
		counts[idx] += 1
		q -= int(packs[idx][0])
	return counts

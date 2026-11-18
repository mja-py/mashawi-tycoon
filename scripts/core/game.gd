extends Node
## Mutable game state: money, inventory, menu, the rig/plot stations, goals, location, day cycle.
## Emits `changed` whenever something the UI shows may have moved.

signal changed
signal notify(text: String, kind: String)
signal goal_claimed(goal: Dictionary)
## A fame level (Data.FAME_LEVELS index) was reached for the first time: city-wide
## (local = false) or at the place you stand (local = true).
signal fame_level_up(level: int, local: bool)

## 5: the campaigns of Data.MARKETING (older saves get the days left of removed ones refunded).
## 6: fame levels: `fame_best` and each plot's "fame_best" (derived from the stored values
## for older saves) floor popularity and local reputation; a level is never lost.
const SAVE_VERSION := 6
const HISTORY_LIMIT := 90
## Tests and headless runs point this elsewhere so the player's save is never touched.
var save_path := "user://save.json"
var persist := true
## Web: a copy of the save also goes to localStorage, which survives a killed tab even when
## the browser never got round to flushing Godot's IndexedDB file system.
const WEB_SAVE_KEY := "mashawi_save"
## A plot stage from this tier up belongs to the location, not to the mobile rig.
const FIXED_FROM_TIER := 3

var money: float = Data.START_MONEY
var day: int = 1
var popularity: float = Data.START_POPULARITY
## The highest fame level reached (Data.FAME_LEVELS index): popularity never drops below its
## threshold. Each plot keeps its own "fame_best" for its local reputation.
var fame_best: int = 0
var stage: String = "dubai"
var location: String = "fahidi"
var weather: String = "sunny"
var forecast: String = "sunny"
var inventory: Dictionary = {}
## Weighted-average price actually paid per unit of each ingredient.
var avg_cost: Dictionary = {}
var menu: Dictionary = {}
## The mobile stand: stage id (cart/stall/truck) and its station levels; travels with you.
var rig: Dictionary = {"stage": "cart", "stations": {}}
## Per location: fixed stage ("" until a kiosk is built), its stations, local reputation.
var plots: Dictionary = {}
var marketing: Dictionary = {}
var history: Array = []
var total_served: int = 0
var bailouts: int = 0
var goal_index: int = 0
var goals_claimed: Array = []
var stats: Dictionary = {}
var prepared_day := 0
var weather_day := 0
var day_seed := 0
var tutorial: Dictionary = GuideJourney.fresh()
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	new_game()

func new_game() -> void:
	money = Data.START_MONEY
	day = 1
	popularity = Data.START_POPULARITY
	fame_best = Economy.fame_level(popularity)
	stage = "dubai"
	location = "fahidi"
	inventory = {}
	avg_cost = {}
	for ing in Data.INGREDIENTS:
		inventory[ing] = 0
		avg_cost[ing] = Data.reference_unit_price(ing)
	menu = {}
	for id in Data.MENU_ITEMS:
		var def: Dictionary = Data.MENU_ITEMS[id]
		menu[id] = {
			"unlocked": bool(def["start"]),
			"enabled": bool(def["start"]),
			"price": float(def["base_price"]),
			"level": 0,
			"recipe": {"meat": 2, "veg": 2, "sauce": 1},
		}
	rig = {"stage": "cart", "stations": {}}
	plots = {}
	marketing = {}
	history = []
	total_served = 0
	bailouts = 0
	goal_index = 0
	goals_claimed = []
	stats = _new_stats()
	prepared_day = 0
	weather_day = 0
	day_seed = 0
	tutorial = GuideJourney.fresh()
	forecast = _roll_weather()
	weather = forecast
	_plot_entry(location)
	changed.emit()

func _new_stats() -> Dictionary:
	return {"best_day_profit": 0.0, "best_day_served": 0, "days_played": 0, "levels_bought": 0, "stages_built": 0,
		"total_profit": 0.0, "locations_visited": [location]}

## Called when the prep screen opens. A relative lends a little cash if you're broke,
## so a bad streak never ends the game outright. Plots you are away from slowly lose
## their local reputation.
func prepare_day() -> void:
	if prepared_day != day:
		# Once per day: reopening the prep screen (title, reload) is not a new loan.
		if money < Data.BAILOUT_BELOW and bailouts < Data.BAILOUT_MAX:
			bailouts += 1
			money += Data.BAILOUT_AMOUNT
			notify.emit(tr("ui.loan") % Loc.money(Data.BAILOUT_AMOUNT), "warn")
		for id in plots:
			if id == location:
				continue
			var p: Dictionary = plots[id]
			var away := day - int(p.get("last_visit", day))
			if away > 0 and plot_stage_tier(id) >= FIXED_FROM_TIER:
				# a local level once reached is never lost: the fading stops at its threshold
				p["reputation"] = Economy.reputation_decay(float(p["reputation"]), 1, Economy.fame_floor(_plot_best(p)))
		prepared_day = day
	var here := plot()
	here["last_visit"] = day
	changed.emit()

func expected_customers() -> int:
	return Economy.expected_customers(sim_context())

## Portions today's parties should buy (what the stock has to cover).
func expected_portions() -> int:
	return int(round(float(Economy.throughput_estimate(sim_context())["portions"])))

func food_on_sale() -> bool:
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "food" and is_on_sale(id) and portions_possible(id) > 0:
			return true
	return false

## True once today's weather and customers are fixed, i.e. the shop has opened.
func day_committed() -> bool:
	return weather_day == day

## Decide the real weather for the day that is about to start.
func begin_day() -> void:
	if day_committed():
		return
	if rng.randf() < Data.FORECAST_ACCURACY:
		weather = forecast
	else:
		weather = _roll_weather()
	weather_day = day
	day_seed = rng.randi_range(1, 2147483647)
	# A place counts as visited (places goals, the stats screen) once a day opens there,
	# not when the prep screen merely passes through it.
	if not stats["locations_visited"].has(location):
		stats["locations_visited"].append(location)
	# Commit the opening checkpoint before any live sale. Reloads replay this day.
	save()
	changed.emit()

# ---------------------------------------------------------------- queries

func loc() -> Dictionary:
	return Data.LOCATIONS[location]

func weather_def() -> Dictionary:
	return Data.WEATHER[weather]

## The plot record of a location (created on first use).
func _plot_entry(id: String) -> Dictionary:
	if not plots.has(id):
		# a new place starts from your city-wide name
		plots[id] = {"stage": "", "stations": {}, "reputation": popularity, "last_visit": day, "fame_best": Economy.fame_level(popularity)}
	return plots[id]

func plot() -> Dictionary:
	return _plot_entry(location)

func rig_tier() -> int:
	return Data.stage_tier_of(String(rig["stage"]))

## Tier of the fixed stage built at a location, or -1 when there is none.
func plot_stage_tier(id: String) -> int:
	if not plots.has(id) or String(plots[id].get("stage", "")) == "":
		return -1
	return Data.stage_tier_of(String(plots[id]["stage"]))

## The stage you sell from where you stand today: the plot's building, else your rig.
func stage_tier() -> int:
	return maxi(rig_tier(), plot_stage_tier(location))

func stage_def() -> Dictionary:
	return Data.stage_def(stage_tier())

## True when today's stage belongs to the location (kiosk and up).
func is_fixed() -> bool:
	return plot_stage_tier(location) >= FIXED_FROM_TIER

func _station_store() -> Dictionary:
	return plot()["stations"] if is_fixed() else rig["stations"]

func station_level(id: String) -> int:
	return int(_station_store().get(id, 0))

func station_available(id: String) -> bool:
	return id in stage_def()["stations"]

func station_cap(id: String) -> int:
	return Economy.station_level_cap(Data.STATIONS[id], stage_def())

func station_cost(id: String) -> float:
	return Economy.station_cost(Data.STATIONS[id], station_level(id))

## Every station usable at this stage with its level.
func active_stations() -> Dictionary:
	var out := {}
	for id in stage_def()["stations"]:
		out[id] = station_level(id)
	return out

## Station levels bought anywhere (rig + every plot), for goals.
func levels_owned() -> int:
	var n := 0
	for id in rig["stations"]:
		n += int(rig["stations"][id])
	for loc_id in plots:
		for id in plots[loc_id]["stations"]:
			n += int(plots[loc_id]["stations"][id])
	return n

func counter_capacity() -> float:
	return Economy.counter_capacity(station_level("counter"))

func queue_capacity() -> int:
	return Economy.queue_cap(station_level("counter"), stage_def())

## Kitchen station -> portions per sim-second, for the stations present at this stage.
func kitchen_caps() -> Dictionary:
	var out := {}
	for id in stage_def()["stations"]:
		var def: Dictionary = Data.STATIONS[id]
		if def.has("kinds"):
			out[id] = Economy.kitchen_capacity(id, station_level(id), stage_tier())
	return out

## Item station kind ("grill", "drink", ...) -> station id that cooks it here.
func station_of_kind() -> Dictionary:
	var out := {}
	for id in stage_def()["stations"]:
		for k in Data.STATIONS[id].get("kinds", []):
			out[k] = id
	return out

func seats() -> int:
	var n := 0
	for id in ["seating", "majlis"]:
		if station_available(id):
			n += station_level(id) * int(Data.STATIONS[id].get("seats_per_level", 0))
	return n

## Chairs actually set out on today's terrace (the plot builds tables of two up to its cap).
func terrace_seats() -> int:
	return Economy.terrace_seats(stage_tier(), seats())

## Overnight loss rate for an ingredient given the cold storage level.
func spoil_rate(ing: String) -> float:
	return spoil_rate_at(ing, station_level("coldbox"))

## Overnight loss rate for an ingredient with a cold box of `coldbox_level`.
func spoil_rate_at(ing: String, coldbox_level: int) -> float:
	var def: Dictionary = Data.INGREDIENTS[ing]
	var rate := float(def["spoil"])
	var cold: Dictionary = Data.STATIONS["coldbox"]
	var level := clampi(coldbox_level, 0, int(cold["max"]))
	if def["cold"] is bool and def["cold"]:
		rate = minf(rate, float(cold["spoil_meat"][level]))
	elif def["cold"] is String:
		rate = minf(rate, float(cold["spoil_veg"][level]))
	return rate

## Items on sale of a kind ("food" or "drink") with their value to today's crowd and stock.
func candidates(kind_wanted: String) -> Array:
	var out := []
	var l := loc()
	var w := weather_def()
	for id in Data.MENU_ITEMS:
		if not is_on_sale(id):
			continue
		var kind: String = Data.MENU_ITEMS[id]["kind"]
		if kind_wanted == "food" and kind != "food":
			continue
		if kind_wanted == "drink" and kind != "drink":
			continue
		var value := Economy.item_value(id, quality(id), float(menu[id]["price"]), l, w)
		out.append({"id": id, "value": value, "stock": portions_possible(id)})
	return out

## Everything on sale with value, price and cost (the analytic estimate's input).
func offer(assume_stock: bool = false) -> Array:
	var out := []
	var l := loc()
	var w: Dictionary = Data.WEATHER[forecast]
	for id in Data.MENU_ITEMS:
		if not is_on_sale(id):
			continue
		var def: Dictionary = Data.MENU_ITEMS[id]
		out.append({"id": id, "kind": def["kind"], "station_kind": def.get("station_kind", ""),
			"value": Economy.item_value(id, quality(id), float(menu[id]["price"]), l, w),
			"price": float(menu[id]["price"]), "unit_cost": unit_cost(id), "quality": quality(id),
			"stock": 999 if assume_stock else portions_possible(id)})
	return out

func quality(item_id: String) -> float:
	return Economy.item_quality(item_id, menu[item_id])

## Cost of one portion at the prices actually paid for the ingredients in stock.
func unit_cost(item_id: String) -> float:
	var cost := 0.0
	var needs := Economy.portion_ingredients(item_id, menu[item_id])
	for ing in needs:
		cost += needs[ing] * ingredient_cost(ing)
	return cost

func ingredient_cost(ing: String) -> float:
	return float(avg_cost.get(ing, Data.reference_unit_price(ing)))

func portions_possible(item_id: String) -> int:
	var needs := Economy.portion_ingredients(item_id, menu[item_id])
	var n := 999999
	for ing in needs:
		if needs[ing] <= 0:
			continue
		n = mini(n, int(inventory.get(ing, 0)) / int(needs[ing]))
	return n

func is_on_sale(item_id: String) -> bool:
	var m: Dictionary = menu[item_id]
	return m["unlocked"] and m["enabled"] and item_available(item_id)

## True when something of this kind ("food", "drink", "side", "sweet") is on the menu today.
func kind_on_sale(kind: String) -> bool:
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == kind and is_on_sale(id):
			return true
	return false

## True when this stage could sell something of the kind (its equipment fits here), bought or not.
func kind_possible(kind: String) -> bool:
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] != kind:
			continue
		var s := required_station(Data.MENU_ITEMS[id])
		if s == "" or station_available(s):
			return true
	return false

func competition() -> float:
	return float(loc().get("competition", 0.0))

func promo_power() -> float:
	return float(loc().get("promo_power", 1.0))

## Share of customers rivals take at this place with the current promotions.
func competition_loss() -> float:
	return Economy.competition_loss(competition(), marketing_boost() + attract_bonus(), promo_power())

## The station an item or ingredient needs, "" when none.
func required_station(def: Dictionary) -> String:
	return String(def.get("requires_station", ""))

func item_available(item_id: String) -> bool:
	var s := required_station(Data.MENU_ITEMS[item_id])
	return s == "" or (station_available(s) and station_level(s) >= 1)

func ingredient_available(ing: String) -> bool:
	var s := required_station(Data.INGREDIENTS[ing])
	return s == "" or (station_available(s) and station_level(s) >= 1)

## Can you set up at a location with your rig (or its own building)?
func location_stage_ok(id: String) -> bool:
	return maxi(rig_tier(), plot_stage_tier(id)) >= int(Data.LOCATIONS[id].get("min_stage", 0))

func attract_bonus() -> float:
	var b := 0.0
	for id in stage_def()["stations"]:
		b += float(Data.STATIONS[id].get("attract_per_level", 0.0)) * station_level(id)
	return b

## Satisfaction the stand's comforts add to every sale; on a hot day (`weather_id` "hot")
## the shade's cooling counts as well.
func satisfaction_bonus(weather_id: String = "") -> float:
	var b := 0.0
	for id in stage_def()["stations"]:
		b += float(Data.STATIONS[id].get("satisfaction_per_level", 0.0)) * station_level(id)
		if weather_id == "hot":
			b += float(Data.STATIONS[id].get("hot_satisfaction_per_level", 0.0)) * station_level(id)
	return b

## Extra stop chance from the campaigns running today (each scaled as Economy.campaign_boost).
func marketing_boost() -> float:
	var b := 0.0
	for id in marketing:
		if Data.MARKETING.has(id):
			b += campaign_boost(id)
	return b

## What one campaign adds to the stop chance today (running or not).
func campaign_boost(id: String) -> float:
	return Economy.campaign_boost(Data.MARKETING[id], total_served, recent_satisfaction())

## A campaign's price for the stand you have here.
func campaign_cost(id: String) -> float:
	return Economy.campaign_cost(Data.MARKETING[id], stage_tier())

## Average satisfaction of the guests served over the last week of books (each day weighted
## by its buyers); 0.6 before there are any.
func recent_satisfaction(days: int = 7) -> float:
	var sum := 0.0
	var n := 0
	for i in range(mini(days, history.size())):
		var r: Dictionary = history[history.size() - 1 - i]
		var served := int(r.get("served", 0))
		sum += float(r.get("satisfaction", 0.0)) * served
		n += served
	return sum / n if n > 0 else 0.6

## Why a campaign cannot start today ("" when it can; the price is checked on starting).
func marketing_lock_reason(id: String) -> String:
	if not Data.MARKETING.has(id):
		return tr("ui.b_soon")
	if marketing.has(id):
		return tr("ui.already_running")
	var def: Dictionary = Data.MARKETING[id]
	if popularity < float(def.get("min_popularity", 0.0)) - Economy.FAME_EPS:
		return tr("ui.a_needs_stars") % fame_name(Economy.fame_level_for(float(def["min_popularity"])))
	return ""

## What a campaign would bring if started today, without starting it (no state change, no
## RNG): the analytic estimate with and without its boost over each of its days (today on the
## forecast, later days sunny, the opening buzz day by day) at today's stand, menu and prices.
## {cost, days, boost, extra_buyers_per_day, extra_profit_total, net (profit less the price),
##  capped (the stand is already full on those days: it turns away Data.PROMO_FULL or more
##  would-be buyers for every one it serves, so most of the guests a campaign draws walk on)}.
## `quick` prices the first day only and repeats it (the advisor's shortlist; the campaign it
## then recommends gets the full preview).
func promo_preview(id: String, quick: bool = false) -> Dictionary:
	if not Data.MARKETING.has(id):
		return {}
	var def: Dictionary = Data.MARKETING[id]
	var days := int(def["days"])
	var cost := campaign_cost(id)
	var add := campaign_boost(id)
	var ctx := sim_context()
	ctx["weather"] = forecast
	var served := 0.0
	var crowd := 0.0
	var extra_served := 0.0
	var extra_profit := 0.0
	var memo := {}
	var span := 1 if quick else days
	for d in range(span):
		var c := ctx.duplicate()
		c["day"] = day + d
		c["traffic_mult"] = Economy.opening_boost(day + d)
		if d > 0:
			c["weather"] = "sunny"
		var key := "%s|%.4f" % [c["weather"], float(c["traffic_mult"])]
		if not memo.has(key):
			var base := Economy.throughput_estimate(c)
			var boosted := c.duplicate()
			boosted["boost"] = float(c["boost"]) + add
			var more := Economy.throughput_estimate(boosted)
			memo[key] = [float(more["served"]) - float(base["served"]), float(more["profit"]) - float(base["profit"]),
				float(base["served"]), float(base["crowd"])]
		extra_served += float(memo[key][0])
		extra_profit += float(memo[key][1])
		served += float(memo[key][2])
		crowd += float(memo[key][3])
	if quick:
		extra_served *= days
		extra_profit *= days
	return {"cost": cost, "days": days, "boost": add,
		"extra_buyers_per_day": extra_served / days, "extra_profit_total": extra_profit, "net": extra_profit - cost,
		"capped": crowd >= Data.PROMO_FULL * served}

## Today's wage bill for the stand where you stand (Economy.daily_wages, Data.WAGES).
func daily_wages() -> float:
	return Economy.daily_wages(stage_tier(), active_stations(), terrace_seats())

## Today's opening-buzz multiplier on passers-by (1.0 once the buzz is over), for the UI.
func opening_boost() -> float:
	return Economy.opening_boost(day)

## Legacy: popularity on the old five-star scale (the HUD's star row still reads it).
func stars() -> float:
	return popularity * 5.0

func local_reputation() -> float:
	return float(plot().get("reputation", popularity))

func effective_popularity() -> float:
	return Economy.effective_popularity(popularity, local_reputation())

# ---------------------------------------------------------------- fame (Data.FAME_LEVELS)

## The city-wide fame level reached (never lower than the best one ever reached).
func fame_level() -> int:
	return maxi(fame_best, Economy.fame_level(popularity))

## 0..1 along the city-wide bar to the next level (1.0 at the top).
func fame_progress() -> float:
	return Economy.fame_progress(popularity)

## Local fame at the place you stand: its level and the bar towards the next.
func local_fame_level() -> int:
	return _plot_best(plot())

func local_fame_progress() -> float:
	return Economy.fame_progress(local_reputation())

## A fame level's translated name ("Local favourite").
func fame_name(level: int) -> String:
	return tr(String(Data.fame_def(level)["name"]))

## The best local level a plot has reached (its stored best or what its value shows now).
func _plot_best(p: Dictionary) -> int:
	return maxi(int(p.get("fame_best", 0)), Economy.fame_level(float(p.get("reputation", popularity))))

## Every write of city-wide fame goes through here: never below the level reached, a new
## level is remembered and announced (fame_level_up). Returns true on a new level.
func set_popularity(value: float) -> bool:
	if is_nan(value) or is_inf(value):
		return false
	popularity = clampf(maxf(value, Economy.fame_floor(fame_best)), 0.05, 1.0)
	var lvl := Economy.fame_level(popularity)
	if lvl > fame_best:
		fame_best = lvl
		fame_level_up.emit(lvl, false)
		return true
	return false

## The same for a plot's local reputation (`announce` = it is the place you stand).
func set_local_fame(p: Dictionary, value: float, announce: bool = true) -> bool:
	if is_nan(value) or is_inf(value):
		return false
	var best := _plot_best(p)
	p["reputation"] = clampf(maxf(value, Economy.fame_floor(best)), 0.05, 1.0)
	var lvl := Economy.fame_level(float(p["reputation"]))
	p["fame_best"] = maxi(best, lvl)
	if lvl > best:
		if announce:
			fame_level_up.emit(lvl, true)
		return true
	return false

func location_unlocked(id: String) -> bool:
	return popularity >= float(Data.LOCATIONS[id].get("unlock_pop", 0.0)) - Economy.FAME_EPS

func stage_locations() -> Array:
	return Data.STAGES[stage]["locations"]

## What the 3D plot needs to know to draw today's stand.
func plot_state() -> Dictionary:
	return {"stage": stage_tier(), "stations": active_stations(), "staff": {}, "events": {},
		"site": {"layout": loc()["layout"], "location": location}}

## Legacy visual flags for the cart (until the Plot node replaces it).
func cart_upgrades() -> Dictionary:
	var up := {}
	if station_level("counter") >= 2:
		up["cart2"] = true
	if station_level("coldbox") >= 1:
		up["fridge"] = true
	if station_level("shade") >= 1:
		up["awning"] = true
	if station_level("music") >= 1:
		up["speaker"] = true
	if seats() > 0:
		up["seating"] = true
	if station_level("sweets") >= 1:
		up["sweets"] = true
	if station_level("grill") >= 4:
		up["helper"] = true
	if station_available("doner") and station_level("doner") >= 1:
		up["doner"] = true
	return up

# ---------------------------------------------------------------- goals

func current_goal() -> Dictionary:
	if goal_index >= Data.GOALS.size():
		return {}
	return Data.GOALS[goal_index]

func goal_snapshot() -> Dictionary:
	var last: Dictionary = history.back() if not history.is_empty() else {}
	var unlocked := []
	for id in menu:
		if menu[id]["unlocked"]:
			unlocked.append(id)
	var st := {}
	var best_stage := rig_tier()
	for id in Data.STATIONS:
		st[id] = int(rig["stations"].get(id, 0))
	for loc_id in plots:
		best_stage = maxi(best_stage, plot_stage_tier(loc_id))
		for id in plots[loc_id]["stations"]:
			st[id] = maxi(int(st.get(id, 0)), int(plots[loc_id]["stations"][id]))
	# the most improved dish (enhance levels bought)
	var dish_level := 0
	for id in menu:
		if menu[id]["unlocked"]:
			dish_level = maxi(dish_level, int(menu[id]["level"]))
	return {
		"day_served": int(last.get("served", 0)), "day_profit": float(last.get("profit", 0.0)), "day_dine_in": int(last.get("dine_in", 0)),
		"day_portions": int(last.get("portions", last.get("served", 0))),
		"total_served": total_served, "stars": stars(), "fame": maxf(Economy.fame_value(popularity), float(fame_level())),
		"levels_owned": levels_owned(), "stage": best_stage, "dish_level": dish_level,
		"stations": st, "visited": stats["locations_visited"], "unlocked": unlocked,
	}

## Move past goals already claimed (a save from before new goals were added to the ladder
## goes back to the first new one, then skips what it had claimed).
func _skip_claimed_goals() -> void:
	while goal_index < Data.GOALS.size() and String(Data.GOALS[goal_index]["id"]) in goals_claimed:
		goal_index += 1

## The first goal of the ladder not claimed yet.
func _first_open_goal() -> int:
	for i in range(Data.GOALS.size()):
		if not String(Data.GOALS[i]["id"]) in goals_claimed:
			return i
	return Data.GOALS.size()

func goal_progress() -> float:
	var g := current_goal()
	if g.is_empty():
		return 0.0
	return Economy.goal_progress(g, goal_snapshot())

func goal_ready() -> bool:
	return not current_goal().is_empty() and goal_progress() >= 1.0

func claim_goal() -> bool:
	if not goal_ready():
		return false
	var g := current_goal()
	var reward: Dictionary = g["reward"]
	money += float(reward.get("money", 0.0))
	if reward.has("popularity"):
		set_popularity(popularity + float(reward["popularity"]))
	goals_claimed.append(g["id"])
	goal_index += 1
	_skip_claimed_goals()
	notify.emit(tr("ui.g_claimed") % Loc.money(float(reward.get("money", 0.0))), "good")
	goal_claimed.emit(g)
	changed.emit()
	return true

# ---------------------------------------------------------------- actions

func _spend(amount: float) -> bool:
	if not is_finite(amount) or amount < 0.0:
		return false
	if amount > money + 0.0001:
		notify.emit(tr("ui.no_money"), "error")
		return false
	money -= amount
	return true

func buy_pack(ingredient: String, pack_index: int) -> bool:
	if not Data.INGREDIENTS.has(ingredient) or not ingredient_available(ingredient) or pack_index < 0 or pack_index >= Data.INGREDIENTS[ingredient]["packs"].size():
		return false
	var pack: Array = Data.INGREDIENTS[ingredient]["packs"][pack_index]
	if not _spend(float(pack[1])):
		return false
	var have := int(inventory.get(ingredient, 0))
	var add := int(pack[0])
	avg_cost[ingredient] = (have * ingredient_cost(ingredient) + float(pack[1])) / float(have + add)
	inventory[ingredient] = have + add
	changed.emit()
	return true

## One-tap daily top-up. Forecast, menu, recipes and existing stock all count;
## the quote is read-only and the whole purchase succeeds or nothing is bought.
## With a cold box it buys ahead where that is cheaper over two days (supply_plan), never
## past the cash left after today's rent and wages.
## {cost, orders [[ingredient, pack index, count]], customers, portions, ahead, saving}.
func daily_stock_plan() -> Dictionary:
	var ctx := sim_context()
	ctx["weather"] = forecast
	var est := Economy.throughput_estimate(ctx)
	var plan := supply_plan(stock_needs(ctx, est), stock_budget())
	plan["customers"] = int(round(float(est["served"])))
	plan["portions"] = int(round(float(est["portions"])))
	return plan

## Cash Stock today may spend: what is left after today's rent and wages.
func stock_budget() -> float:
	return maxf(0.0, money - float(loc()["rent"]) - daily_wages())

## Units of each ingredient a day needs (the plan's 10% buffer included), from a sim context
## and its estimate: every dish's share of the estimated portions, add-ons as DaySim rolls them.
func stock_needs(ctx: Dictionary, est: Dictionary) -> Dictionary:
	var w_id := String(ctx["weather"])
	# Parties order several portions each: stock follows portions, not buyers.
	var portions_due := float(est["portions"])
	var items: Array = ctx["offer"]
	var sums := {"food": 0.0, "drink": 0.0, "side": 0.0, "sweet": 0.0}
	var counts := {"food": 0, "drink": 0, "side": 0, "sweet": 0}
	for item in items:
		if item_available(item["id"]):
			sums[item["kind"]] += float(item["value"])
			counts[item["kind"]] += 1
	var ds := Economy.drink_share(w_id)
	var bonus := Economy.ADDON_DINE_BONUS * float(ctx["dine_in_share"])
	var drink_p := Economy.addon_drink_chance(w_id)
	var needs := {}
	for item in items:
		if not item_available(item["id"]):
			continue
		var kind: String = item["kind"]
		if float(sums.get(kind, 0.0)) <= 0.0:
			continue
		var share := 0.0
		if kind in ["food", "drink"]:
			share = (ds if kind == "drink" else 1.0 - ds) * float(item["value"]) / float(sums[kind])
		# Add-ons follow DaySim's uniform pick and its price-dependent appeal.
		if kind != "food":
			var base_price := float(Data.MENU_ITEMS[item["id"]]["base_price"])
			var appeal := clampf(1.6 - float(item["price"]) / base_price * 0.9, 0.0, 1.0)
			var chance := drink_p if kind == "drink" else (Economy.ADDON_SIDE if kind == "side" else Economy.ADDON_SWEET)
			if counts["food"] > 0:
				share += (1.0 - ds) * (chance + bonus) * appeal / int(counts[kind])
		var portions := ceili(portions_due * share * 1.1)
		var recipe := Economy.portion_ingredients(item["id"], menu[item["id"]])
		for ing in recipe:
			needs[ing] = int(needs.get(ing, 0)) + portions * int(recipe[ing])
	return needs

## The whole packs that cover `needs` (units by ingredient) beyond the stock in hand. With a
## cold box the plan buys ahead: each ingredient is judged over two days (today's need, then
## the same again tomorrow), and bigger, cheaper packs win when what survives the night
## (1 - spoil_rate) makes them cheaper (Economy.supply_packs_ahead). Without one it buys for
## today only. When buying ahead would cost more than `budget` (>= 0) the plan buys for today.
## {cost, orders [[ingredient, pack index, count]], ahead (buys past today's need),
##  saving (AED the two days save against buying for today only)}.
func supply_plan(needs: Dictionary, budget: float = -1.0) -> Dictionary:
	var cold := station_level("coldbox") >= 1
	var plain := {"cost": 0.0, "orders": [], "ahead": false, "saving": 0.0}
	var ahead := {"cost": 0.0, "orders": [], "ahead": false, "saving": 0.0}
	for ing in needs:
		if not Data.INGREDIENTS.has(ing):
			continue
		var deficit := int(needs[ing]) - int(inventory.get(ing, 0))
		if deficit <= 0:
			continue
		var packs: Array = Data.INGREDIENTS[ing]["packs"]
		_add_orders(plain, ing, Economy.supply_packs(packs, deficit))
		if cold:
			var q := Economy.supply_packs_ahead(packs, deficit, int(needs[ing]), 1.0 - spoil_rate(ing))
			_add_orders(ahead, ing, q)
			ahead["saving"] = float(ahead["saving"]) + float(q["plain_two_day"]) - float(q["two_day"])
	if cold and float(ahead["saving"]) > 0.0 and (budget < 0.0 or float(ahead["cost"]) <= budget):
		ahead["ahead"] = true
		return ahead
	return plain

func _add_orders(plan: Dictionary, ing: String, quote: Dictionary) -> void:
	plan["cost"] = float(plan["cost"]) + float(quote["cost"])
	var counts: Array = quote["counts"]
	for i in range(counts.size()):
		if int(counts[i]) > 0:
			plan["orders"].append([ing, i, int(counts[i])])

## AED a day the next cold box level would save here (0 at the top level): the overnight
## spoilage it would stop (the last week's books, at today's ingredient prices) plus half the
## two-day saving of buying today's estimated needs ahead (supply_plan). `est` = an estimate
## of today already made (the forecast's sim context), else one is run.
func coldbox_saving(est: Dictionary = {}) -> float:
	var level := station_level("coldbox")
	if level >= int(Data.STATIONS["coldbox"]["max"]) or not station_available("coldbox"):
		return 0.0
	var spoil := 0.0
	var n := mini(7, history.size())
	for i in range(n):
		var row: Dictionary = history[history.size() - 1 - i]
		var sp = row.get("spoiled", {})
		if not sp is Dictionary:
			continue
		for ing in sp:
			if not Data.INGREDIENTS.has(ing):
				continue
			var now := spoil_rate_at(ing, level)
			if now > 0.0:
				spoil += float(sp[ing]) * (1.0 - spoil_rate_at(ing, level + 1) / now) * ingredient_cost(ing)
	if n > 0:
		spoil /= n
	var ctx := sim_context()
	ctx["weather"] = forecast
	var e := est if not est.is_empty() else Economy.throughput_estimate(ctx)
	var needs := stock_needs(ctx, e)
	var bulk := 0.0
	for ing in needs:
		var need := int(needs[ing])
		if need <= 0:
			continue
		var packs: Array = Data.INGREDIENTS[ing]["packs"]
		var nxt := Economy.supply_packs_ahead(packs, need, need, 1.0 - spoil_rate_at(ing, level + 1))
		var save := float(nxt["plain_two_day"]) - float(nxt["two_day"])
		if level >= 1:
			var cur := Economy.supply_packs_ahead(packs, need, need, 1.0 - spoil_rate_at(ing, level))
			save -= float(cur["plain_two_day"]) - float(cur["two_day"])
		bulk += maxf(0.0, save) * 0.5
	return spoil + bulk

## AED a day one unit of popularity is worth here: what the extra passers it draws would buy,
## from the estimate at a little more fame (the price of fame in Economy.fame_worth).
## `ctx` / `base_profit` = a context and its estimated profit already in hand.
func fame_slope(ctx: Dictionary = {}, base_profit: float = INF) -> float:
	var c := ctx if not ctx.is_empty() else sim_context()
	var pop := float(c["popularity"])
	var step := 0.05
	var lo := c
	var hi := c.duplicate()
	var lo_profit := base_profit if is_finite(base_profit) else float(Economy.throughput_estimate(c)["profit"])
	if pop + step > 1.0:
		# at the very top: measure the step below instead
		lo = c.duplicate()
		lo["popularity"] = pop - step
		var top := lo_profit
		lo_profit = float(Economy.throughput_estimate(lo)["profit"])
		return maxf(0.0, (top - lo_profit) / step)
	hi["popularity"] = pop + step
	return maxf(0.0, (float(Economy.throughput_estimate(hi)["profit"]) - lo_profit) / step)

## What a purchase (Game.what_if overrides) does for fame, for the advisor ("about N more
## happy guests a day"): {happy (more green faces a day), points (more fame points a day),
## fame (popularity it adds over Data.FAME_HORIZON_DAYS), value (AED a day that fame is
## worth, Economy.fame_worth)}. Three estimates.
func quality_gain(overrides: Dictionary) -> Dictionary:
	var ctx := sim_context()
	var base := Economy.throughput_estimate(ctx)
	return fame_gain_of(base, Economy.throughput_estimate(what_if(overrides)), fame_slope(ctx, float(base["profit"])))

## The fame part of going from estimate `base` to estimate `after` (see quality_gain), with
## `slope` from fame_slope.
func fame_gain_of(base: Dictionary, after: Dictionary, slope: float) -> Dictionary:
	var pts := float(after["fame_points"]) - float(base["fame_points"])
	var pop := effective_popularity()
	return {"happy": float(after["moods"]["great"]) - float(base["moods"]["great"]), "points": pts,
		"fame": Economy.fame_reach(pts, pop, Data.FAME_HORIZON_DAYS), "value": Economy.fame_worth(pts, pop, slope)}

func stock_for_today() -> bool:
	var plan := daily_stock_plan()
	var cost := float(plan["cost"])
	# Leave the day's unavoidable bills in the till.
	if cost <= 0.0 or cost > stock_budget():
		return false
	money -= cost
	for order in plan["orders"]:
		var ing: String = order[0]
		var pack: Array = Data.INGREDIENTS[ing]["packs"][order[1]]
		var have := int(inventory.get(ing, 0))
		var qty := int(pack[0]) * int(order[2])
		avg_cost[ing] = (have * ingredient_cost(ing) + float(pack[1]) * int(order[2])) / float(have + qty)
		inventory[ing] = have + qty
	notify.emit(tr("ui.stock_done"), "good")
	changed.emit()
	return true

## [lowest, highest] price allowed for an item where the stand is today.
func price_range(item_id: String) -> Array:
	return Economy.price_range(item_id, loc(), stage_def())

func set_price(item_id: String, price: float) -> void:
	if not menu.has(item_id) or not is_finite(price):
		return
	var r := price_range(item_id)
	menu[item_id]["price"] = snappedf(clampf(price, float(r[0]), float(r[1])), 1.0)
	changed.emit()

## Pull every price back inside the current location's range. Returns the ids that moved.
func clamp_prices() -> Array:
	var moved := []
	for id in menu:
		var r := price_range(id)
		var p := snappedf(clampf(float(menu[id]["price"]), float(r[0]), float(r[1])), 1.0)
		if not is_equal_approx(p, float(menu[id]["price"])):
			menu[id]["price"] = p
			moved.append(id)
	return moved

func set_recipe(item_id: String, key: String, value: int) -> void:
	if not menu.has(item_id) or not Data.MENU_ITEMS[item_id]["recipe"] or not Data.RECIPE_SLIDERS.has(key):
		return
	var s: Dictionary = Data.RECIPE_SLIDERS[key]
	menu[item_id]["recipe"][key] = clampi(value, int(s["min"]), int(s["max"]))
	changed.emit()

func set_enabled(item_id: String, on: bool) -> void:
	if menu[item_id]["unlocked"]:
		menu[item_id]["enabled"] = on
		if not on:
			notify.emit(tr("ui.off_menu") % tr(Data.MENU_ITEMS[item_id]["name"]), "warn")
		changed.emit()

func unlock_item(item_id: String) -> bool:
	if menu[item_id]["unlocked"]:
		return false
	if not item_available(item_id):
		notify.emit(tr("ui.requires") % tr(Data.STATIONS[required_station(Data.MENU_ITEMS[item_id])]["name"]), "error")
		return false
	if not _spend(float(Data.MENU_ITEMS[item_id]["unlock_cost"])):
		return false
	menu[item_id]["unlocked"] = true
	menu[item_id]["enabled"] = true
	notify.emit(tr("ui.added") % tr(Data.MENU_ITEMS[item_id]["name"]), "good")
	changed.emit()
	return true

func enhance_item(item_id: String) -> bool:
	if not menu.has(item_id) or not menu[item_id]["unlocked"] or not item_available(item_id):
		return false
	var level := int(menu[item_id]["level"])
	var enh: Array = Data.MENU_ITEMS[item_id]["enhance"]
	if level >= enh.size():
		return false
	if not _spend(float(enh[level]["cost"])):
		return false
	menu[item_id]["level"] = level + 1
	notify.emit(tr("ui.enhanced") % [tr(Data.MENU_ITEMS[item_id]["name"]), tr(enh[level]["name"])], "good")
	changed.emit()
	return true

## Why a station cannot be levelled right now ("" when it can).
func station_lock_reason(id: String) -> String:
	var def: Dictionary = Data.STATIONS[id]
	if not station_available(id):
		return tr("ui.b_needs_stage") % tr(Data.stage_def(int(def["min_stage"]))["name"])
	if def.get("later", false):
		return tr("ui.b_soon")
	if station_level(id) >= station_cap(id):
		return tr("ui.b_maxed")
	return ""

func buy_station_level(id: String) -> bool:
	var why := station_lock_reason(id)
	if why != "":
		notify.emit(why, "error")
		return false
	if not _spend(station_cost(id)):
		return false
	var store := _station_store()
	store[id] = int(store.get(id, 0)) + 1
	stats["levels_bought"] = int(stats["levels_bought"]) + 1
	notify.emit(tr("ui.b_bought") % [tr(Data.STATIONS[id]["name"]), store[id]], "good")
	changed.emit()
	return true

## The next stage you could build here, {} at the top.
func next_stage_def() -> Dictionary:
	var t := stage_tier() + 1
	if t >= Data.PLOT_STAGES.size():
		return {}
	return Data.PLOT_STAGES[t]

## Why the next stage cannot be bought ("" when it can; the price is checked on purchase).
func stage_lock_reason() -> String:
	var nxt := next_stage_def()
	if nxt.is_empty():
		return tr("ui.b_top_stage")
	if nxt.get("later", false):
		return tr("ui.b_soon")
	if nxt.has("requires_rig") and rig_tier() < int(nxt["requires_rig"]):
		return tr("ui.b_needs_stage") % tr(Data.stage_def(int(nxt["requires_rig"]))["name"])
	if nxt.has("requires_local_rep") and local_reputation() < float(nxt["requires_local_rep"]) - Economy.FAME_EPS:
		return tr("ui.b_needs_rep") % fame_name(Economy.fame_level_for(float(nxt["requires_local_rep"])))
	return ""

## Build the next stage: rig stages replace the rig; a plot stage is built at this location.
## The first fixed stage takes over the rig's station levels (the rig is emptied).
func buy_stage() -> bool:
	var why := stage_lock_reason()
	if why != "":
		notify.emit(why, "error")
		return false
	var nxt := next_stage_def()
	if not _spend(float(nxt["cost"])):
		return false
	var tier := Data.stage_tier_of(String(nxt["id"]))
	if String(nxt["scope"]) == "rig":
		rig["stage"] = nxt["id"]
	else:
		var p := plot()
		var was_fixed := plot_stage_tier(location) >= FIXED_FROM_TIER
		p["stage"] = nxt["id"]
		if not was_fixed:
			for id in rig["stations"]:
				p["stations"][id] = int(p["stations"].get(id, 0)) + int(rig["stations"][id])
			rig["stations"] = {}
	stats["stages_built"] = int(stats["stages_built"]) + 1
	notify.emit(tr("ui.b_built") % tr(nxt["name"]), "good")
	clamp_prices()
	changed.emit()
	return true

func start_marketing(id: String) -> bool:
	var why := marketing_lock_reason(id)
	if why != "":
		notify.emit(why, "error")
		return false
	var def: Dictionary = Data.MARKETING[id]
	if not _spend(campaign_cost(id)):
		return false
	marketing[id] = int(def["days"])
	notify.emit(tr("ui.started") % tr(def["name"]), "good")
	changed.emit()
	return true

func set_location(id: String) -> bool:
	if not location_unlocked(id):
		notify.emit(tr("ui.rep_low"), "error")
		return false
	if not location_stage_ok(id):
		notify.emit(tr("ui.stage_needed") % tr(Data.stage_def(int(Data.LOCATIONS[id].get("min_stage", 0)))["name"]), "error")
		return false
	location = id
	var p := plot()
	p["last_visit"] = day
	if not clamp_prices().is_empty():
		notify.emit(tr("ui.m_price_clamped") % tr(loc()["name"]), "warn")
	changed.emit()
	return true

# ---------------------------------------------------------------- day cycle

func sim_context() -> Dictionary:
	var sd := stage_def()
	var tier := stage_tier()
	var n_seats := terrace_seats()
	var counter_level := station_level("counter")
	# Today's weather exists only once the day has opened; prep plans on the forecast.
	var w_id := weather if weather_day == day else forecast
	return {
		"day": day,
		"location": location,
		"weather": w_id,
		"hours": Data.location_hours(location),
		"stage": tier,
		"stations": active_stations(),
		"counter_level": counter_level,
		"counter_cap": counter_capacity(),
		"queue_cap": queue_capacity(),
		"buyers": Economy.buyer_budget(tier, counter_level),
		"party": Economy.party_weights(tier, location),
		"walk": Economy.walk_times(tier, location),
		"kitchen": kitchen_caps(),
		"station_of_kind": station_of_kind(),
		"seats": n_seats,
		"workers": Economy.dining_workers(tier, n_seats, station_level("staffroom") if station_available("staffroom") else 0),
		"dine_in_share": Economy.dine_in_share(sd, n_seats),
		"dine_s": float(Data.SERVICE["dine_s"]),
		"spend_mult": Economy.spend_multiplier(station_level("majlis") if station_available("majlis") else 0),
		"appeal": float(sd["appeal"]),
		"patience_s": float(Data.SERVICE["patience_s"]) * float(loc().get("patience", 1.0)),
		"boost": marketing_boost() + attract_bonus(),
		"competition": competition(),
		"promo_power": promo_power(),
		"shade_level": station_level("shade"),
		"lights_level": station_level("lights") if station_available("lights") else 0,
		"satisfaction_bonus": satisfaction_bonus(w_id),
		"popularity": effective_popularity(),
		"local_rep": local_reputation(),
		"offer": offer(true),
		"wages": daily_wages(),
		"cars_per_hour": 0.0,
		# the opening buzz (Data.OPENING): every sim and the estimate read it in arrival_rate
		"traffic_mult": opening_boost(),
	}

## The context a different setup would produce, without changing anything:
## overrides = {"stations": {id: level}, "stage": tier, "location": id, "unlock": item_id,
## "enhance": item_id (one more dish upgrade), "price_mult": m (every price at m x base,
## clamped to what that place allows)}.
func what_if(overrides: Dictionary) -> Dictionary:
	var saved_rig: Dictionary = rig.duplicate(true)
	var saved_plots: Dictionary = plots.duplicate(true)
	var saved_location := location
	var saved_menu: Dictionary = menu.duplicate(true)
	var saved_stats_visited: Array = stats["locations_visited"].duplicate()
	if overrides.has("location"):
		location = String(overrides["location"])
		_plot_entry(location)
	if overrides.has("stage"):
		var t := int(overrides["stage"])
		var def := Data.stage_def(t)
		if String(def["scope"]) == "rig":
			rig["stage"] = def["id"]
		else:
			var p := plot()
			if plot_stage_tier(location) < FIXED_FROM_TIER:
				for id in rig["stations"]:
					p["stations"][id] = int(p["stations"].get(id, 0)) + int(rig["stations"][id])
				rig["stations"] = {}
			p["stage"] = def["id"]
	if overrides.has("stations"):
		var store := _station_store()
		for id in overrides["stations"]:
			store[id] = int(overrides["stations"][id])
	if overrides.has("unlock"):
		menu[String(overrides["unlock"])]["unlocked"] = true
		menu[String(overrides["unlock"])]["enabled"] = true
	if overrides.has("enhance"):
		menu[String(overrides["enhance"])]["level"] = int(menu[String(overrides["enhance"])]["level"]) + 1
	if overrides.has("price_mult"):
		for id in menu:
			menu[id]["price"] = float(Data.MENU_ITEMS[id]["base_price"]) * float(overrides["price_mult"])
	if overrides.has("prices"):
		# single dishes at given prices, the rest of the menu as it is (the advisor's "+1 on this dish")
		for id in overrides["prices"]:
			if menu.has(id):
				menu[id]["price"] = float(overrides["prices"][id])
	clamp_prices()
	var ctx := sim_context()
	rig = saved_rig
	plots = saved_plots
	location = saved_location
	menu = saved_menu
	stats["locations_visited"] = saved_stats_visited
	return ctx

## Sell one portion of an item. Returns false if ingredients are missing.
func sell(item_id: String, price: float) -> bool:
	if not menu.has(item_id) or not is_on_sale(item_id) or not is_finite(price) or price < 0.0:
		return false
	var needs := Economy.portion_ingredients(item_id, menu[item_id])
	for ing in needs:
		if int(inventory.get(ing, 0)) < int(needs[ing]):
			return false
	for ing in needs:
		inventory[ing] = int(inventory[ing]) - int(needs[ing])
	money += price
	return true

## Close the books for the day. Returns the report dictionary shown to the player.
func end_day(day_stats: Dictionary) -> Dictionary:
	var ledger_day := int(day_stats.get("_day", day))
	if ledger_day != day:
		for report in history:
			if int(report.get("day", -1)) == ledger_day:
				return report
		return {}
	day_stats["_day"] = day
	var rent := float(loc()["rent"])
	var wages := daily_wages()
	money -= rent + wages
	var spoiled := {}
	var spoil_cost := 0.0
	for ing in Data.INGREDIENTS:
		var rate := spoil_rate(ing)
		var qty := int(inventory.get(ing, 0))
		var lost := roundi(qty * rate)
		if lost > 0:
			inventory[ing] = qty - lost
			spoiled[ing] = lost
			spoil_cost += lost * ingredient_cost(ing)
	# fame, guest by guest (Economy.fame_change): the city's and this place's own
	var pop_before := popularity
	var fame := Economy.fame_change(day_stats, popularity, 1.0, Economy.fame_floor(fame_best))
	var fame_up := set_popularity(float(fame["after"]))
	var pop_delta := popularity - pop_before
	var p := plot()
	var local_before := float(p["reputation"])
	var local := Economy.fame_change(day_stats, local_before, Data.LOCAL_FAME_RATE, Economy.fame_floor(_plot_best(p)))
	var local_up := set_local_fame(p, float(local["after"]))
	var local_delta := float(p["reputation"]) - local_before
	var guests: Dictionary = fame["points"]
	p["last_visit"] = day
	# what the day was sold at and under which campaigns (before today's campaigns tick down)
	var prices_today := {}
	for id in Data.MENU_ITEMS:
		if is_on_sale(id):
			prices_today[id] = float(menu[id]["price"])
	var promos_today: Array = marketing.keys()
	# a reviewed campaign (the blogger) that ends today moves popularity by its guests' mood
	var review := 0.0
	for id in marketing.keys():
		marketing[id] = int(marketing[id]) - 1
		if marketing[id] <= 0:
			marketing.erase(id)
			if Data.MARKETING.has(id):
				review += Economy.campaign_review(Data.MARKETING[id], _campaign_satisfaction(id, day_stats))
	if review != 0.0:
		if set_popularity(popularity + review):
			fame_up = true
		notify.emit(tr("mk.review_good") if review > 0.0 else tr("mk.review_bad"), "good" if review > 0.0 else "warn")
	var revenue := float(day_stats.get("revenue", 0.0))
	var cogs := float(day_stats.get("cogs", 0.0))
	var profit := revenue - cogs - rent - wages - spoil_cost
	var util: Dictionary = day_stats.get("util", {})
	var report := {
		"day": day,
		"location": location,
		"weather": weather,
		"stage": stage_tier(),
		"served": int(day_stats.get("served", 0)),
		"portions": int(day_stats.get("portions", day_stats.get("served", 0))),
		"passers": int(day_stats.get("passers", 0)),
		"dine_in": int(day_stats.get("dine_in", 0)),
		"revenue": revenue,
		"cogs": cogs,
		"rent": rent,
		"wages": wages,
		"spoiled": spoiled,
		"spoil_cost": spoil_cost,
		"profit": profit,
		"left_wait": int(day_stats.get("left_wait", 0)),
		"lost_rival": int(day_stats.get("lost_rival", 0)),
		"too_pricey": int(day_stats.get("too_pricey", 0)),
		"sold_out": int(day_stats.get("sold_out", 0)),
		"queue_full": int(day_stats.get("queue_full", 0)),
		"crowd": int(day_stats.get("crowd", 0)),
		"no_item": int(day_stats.get("no_item", 0)),
		"no_item_kinds": _int_dict(day_stats.get("no_item_kinds", {})),
		"closing": int(day_stats.get("closing", 0)),
		"mood_great": int(day_stats.get("mood_great", 0)),
		"mood_ok": int(day_stats.get("mood_ok", 0)),
		"mood_bad": int(day_stats.get("mood_bad", 0)),
		"wait": float(day_stats.get("wait_sum", 0.0)) / maxi(1, int(day_stats.get("served", 0))),
		"prices": prices_today,
		"promos": promos_today,
		"review": review,
		"satisfaction": (float(day_stats.get("satisfaction_sum", 0.0)) / maxi(1, int(day_stats.get("served", 0)))),
		"pop_delta": pop_delta,
		"popularity": popularity,
		"local_rep": float(p["reputation"]),
		"local_delta": local_delta,
		# the fame the guests brought (gain) and took back (loss, positive), city-wide and here;
		# pop_delta = fame_gain - fame_loss (the blogger's review is "review", on its own)
		"fame_gain": float(fame["gain"]),
		"fame_loss": float(fame["loss"]),
		"local_gain": float(local["gain"]),
		"local_loss": float(local["loss"]),
		# the guests behind it: happy (green faces), content (amber), and those who took fame
		# away (red faces plus guests lost to a slow line or a sold-out dish)
		"fame_happy": int(guests["happy"]),
		"fame_content": int(guests["content"]),
		"fame_unhappy": int(guests["unhappy"]) + int(guests["lost"]),
		# fame levels after the day (Data.FAME_LEVELS) and whether one was reached today
		"fame_level": fame_level(),
		"fame_up": fame_up,
		"local_fame_level": _plot_best(p),
		"local_fame_up": local_up,
		"util": util,
		"bottleneck": Economy.bottleneck(util),
		"sold": day_stats.get("sold", {}),
		"money": money,
	}
	stats["days_played"] = int(stats["days_played"]) + 1
	stats["total_profit"] = float(stats["total_profit"]) + profit
	stats["best_day_profit"] = maxf(float(stats["best_day_profit"]), profit)
	stats["best_day_served"] = maxi(int(stats["best_day_served"]), int(report["served"]))
	history.append(report)
	if history.size() > HISTORY_LIMIT:
		history = history.slice(history.size() - HISTORY_LIMIT)
	day += 1
	forecast = _roll_weather()
	report["goal_ready"] = goal_ready()
	save()
	changed.emit()
	return report

## Average satisfaction over a campaign's days: today's guests plus the books of the earlier
## days it ran (each day weighted by its buyers).
func _campaign_satisfaction(id: String, day_stats: Dictionary) -> float:
	var served := int(day_stats.get("served", 0))
	var sum := float(day_stats.get("satisfaction_sum", 0.0))
	var back := int(Data.MARKETING[id]["days"]) - 1
	for i in range(history.size() - 1, -1, -1):
		if back <= 0 or not (history[i].get("promos", []) as Array).has(id):
			break
		var n := int(history[i].get("served", 0))
		sum += float(history[i].get("satisfaction", 0.0)) * n
		served += n
		back -= 1
	return sum / served if served > 0 else 0.6 # nobody came: the blogger has nothing to say

func _roll_weather() -> String:
	var r := rng.randf()
	var acc := 0.0
	for id in Data.WEATHER_ODDS:
		acc += float(Data.WEATHER_ODDS[id])
		if r <= acc:
			return id
	return "sunny"

# ---------------------------------------------------------------- persistence

func _web() -> bool:
	return OS.has_feature("web")

func _web_storage() -> JavaScriptObject:
	return JavaScriptBridge.get_interface("localStorage")

## Raw JSON text of the web backup copy, or "" when there is none.
func _web_backup() -> String:
	if not _web():
		return ""
	var ls := _web_storage()
	if ls == null:
		return ""
	var v = ls.getItem(WEB_SAVE_KEY)
	return String(v) if v is String else ""

func _file_text() -> String:
	if not FileAccess.file_exists(save_path):
		return ""
	var f := FileAccess.open(save_path, FileAccess.READ)
	return f.get_as_text() if f else ""

## The newest valid save available: the user:// file or (web) the localStorage copy.
func _number(value: Variant, fallback: float = 0.0) -> float:
	if value is int or value is float or (value is String and value.is_valid_float()):
		var result := float(value)
		if is_finite(result): return result
	return fallback

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _identifier(value: Variant, fallback: String = "") -> String:
	return value if value is String else fallback

func _read_save() -> Dictionary:
	var best := {}
	for text in [_file_text(), _web_backup()]:
		if text == "":
			continue
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		if best.is_empty() or _number(parsed.get("saved_at", 0)) > _number(best.get("saved_at", 0)):
			best = parsed
	return best

func has_save() -> bool:
	return not _read_save().is_empty()

## Day and cash of the stored game, for the title screen ({} when there is none).
func save_summary() -> Dictionary:
	var d := _read_save()
	if d.is_empty():
		return {}
	return {"day": maxi(1, int(_number(d.get("day", 1), 1))), "money": _number(d.get("money", 0.0))}

func save() -> void:
	if not persist:
		return
	var data := {
		"version": SAVE_VERSION, "saved_at": Time.get_unix_time_from_system(),
		"money": money, "day": day, "popularity": popularity, "fame_best": fame_best,
		"stage": stage, "location": location, "weather": weather, "forecast": forecast, "prepared_day": prepared_day, "weather_day": weather_day, "day_seed": day_seed,
		"inventory": inventory, "avg_cost": avg_cost, "menu": menu, "marketing": marketing,
		"rig": rig, "plots": plots, "goal_index": goal_index, "goals_claimed": goals_claimed, "stats": stats,
		"history": history, "total_served": total_served, "bailouts": bailouts, "tutorial": tutorial,
	}
	var text := JSON.stringify(data)
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	if _web():
		var ls := _web_storage()
		if ls:
			ls.setItem(WEB_SAVE_KEY, text)

func load_game() -> bool:
	var parsed := _read_save()
	if parsed.is_empty():
		return false
	new_game()
	money = _number(parsed.get("money", money), money)
	day = int(_number(parsed.get("day", day), day))
	popularity = _number(parsed.get("popularity", popularity), popularity)
	# version 6: the best fame level reached (older saves: _validate derives it)
	fame_best = int(_number(parsed.get("fame_best", 0)))
	# saves from older versions may name places or weather that no longer exist
	if Data.STAGES.has(_identifier(parsed.get("stage"))):
		stage = _identifier(parsed["stage"])
	if Data.LOCATIONS.has(_identifier(parsed.get("location"))):
		location = _identifier(parsed["location"])
	if Data.WEATHER.has(_identifier(parsed.get("weather"))):
		weather = _identifier(parsed["weather"])
	if Data.WEATHER.has(_identifier(parsed.get("forecast"))):
		forecast = _identifier(parsed["forecast"])
	tutorial = GuideJourney.clean(parsed.get("tutorial", {}))
	prepared_day = int(_number(parsed.get("prepared_day", day), day))
	weather_day = int(_number(parsed.get("weather_day", 0)))
	day_seed = int(_number(parsed.get("day_seed", 0)))
	total_served = int(_number(parsed.get("total_served", 0)))
	bailouts = int(_number(parsed.get("bailouts", 0)))
	for ing in _dictionary(parsed.get("inventory", {})):
		if inventory.has(ing):
			inventory[ing] = int(_number(parsed["inventory"][ing]))
	for ing in _dictionary(parsed.get("avg_cost", {})):
		if avg_cost.has(ing):
			avg_cost[ing] = _number(parsed["avg_cost"][ing], Data.reference_unit_price(ing))
	for id in _dictionary(parsed.get("menu", {})):
		if menu.has(id) and parsed["menu"][id] is Dictionary:
			var m: Dictionary = parsed["menu"][id]
			menu[id]["unlocked"] = _flag(m.get("unlocked")) or bool(Data.MENU_ITEMS[id]["start"])
			menu[id]["enabled"] = _flag(m.get("enabled"))
			menu[id]["price"] = _number(m.get("price", menu[id]["price"]), menu[id]["price"])
			menu[id]["level"] = int(_number(m.get("level", 0)))
			for k in Data.RECIPE_SLIDERS:
				menu[id]["recipe"][k] = int(_number(_dictionary(m.get("recipe", {})).get(k, menu[id]["recipe"][k]), menu[id]["recipe"][k]))
	var save_version := int(_number(parsed.get("version", 1), 1))
	var refund := 0.0
	for id in _dictionary(parsed.get("marketing", {})):
		var left := int(_number(parsed["marketing"][id]))
		if Data.MARKETING.has(id):
			marketing[id] = left
		elif save_version < 5 and Data.LEGACY_MARKETING.has(id) and left > 0:
			# a campaign that no longer exists: its days left are paid back
			var old: Dictionary = Data.LEGACY_MARKETING[id]
			refund += float(old["cost"]) * float(mini(left, int(old["days"]))) / float(old["days"])
	history = parsed.get("history", []) if parsed.get("history") is Array else []
	if parsed.get("rig", null) is Dictionary:
		rig = {"stage": _identifier(parsed["rig"].get("stage"), "cart"), "stations": _int_dict(parsed["rig"].get("stations", {}))}
	plots = {}
	if parsed.get("plots", null) is Dictionary:
		for loc_id in parsed["plots"]:
			var p = parsed["plots"][loc_id]
			if Data.LOCATIONS.has(loc_id) and p is Dictionary:
				plots[loc_id] = {"stage": _identifier(p.get("stage")), "stations": _int_dict(p.get("stations", {})),
					"reputation": _number(p.get("reputation", popularity), popularity), "last_visit": int(_number(p.get("last_visit", day), day)),
					"fame_best": int(_number(p.get("fame_best", 0)))}
	goal_index = int(_number(parsed.get("goal_index", 0)))
	goals_claimed = parsed.get("goals_claimed", []) if parsed.get("goals_claimed", null) is Array else []
	stats = _new_stats()
	if parsed.get("stats", null) is Dictionary:
		for k in stats:
			if parsed["stats"].has(k):
				stats[k] = (parsed["stats"][k] if parsed["stats"][k] is Array else []) if k == "locations_visited" else _number(parsed["stats"][k])
	if save_version < 3:
		_migrate_legacy(parsed)
	_validate()
	if save_version <= 5:
		# release 4 added goals inside the ladder: an older save steps back to the first one it
		# has not done (claimed ones are skipped again after it)
		goal_index = mini(goal_index, _first_open_goal())
	if refund > 0.0:
		money += refund
		notify.emit(tr("ui.promo_refund") % Loc.money(refund), "good")
		save() # the refund is paid once: the save is version 5 from now on
	changed.emit()
	return true

## A saved flag counts only when it is literally true (strings and null are not).
func _flag(v) -> bool:
	return v is bool and v

func _int_dict(d) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in d:
			out[str(k)] = int(_number(d[k]))
	return out

## Saves from before the station system: vehicles become rig stages, one-off upgrades
## become station levels (or refunds where the station needs a stage you have not got).
func _migrate_legacy(parsed: Dictionary) -> void:
	var acc := {"refund": 0.0} # a dictionary so the lambda below can add to it
	var veh := _identifier(parsed.get("vehicle"), "cart")
	rig["stage"] = "truck" if veh in ["truck", "truck2"] else "cart"
	var st: Dictionary = rig["stations"]
	var stage_stations: Array = Data.stage_def(rig_tier())["stations"]
	var add := func(id: String, levels: int, cost: float) -> void:
		if id in stage_stations:
			st[id] = int(st.get(id, 0)) + levels
		else:
			acc["refund"] += cost
	var ups: Dictionary = parsed.get("upgrades", {}) if parsed.get("upgrades", null) is Dictionary else {}
	for id in ups:
		match String(id):
			"cart2": add.call("counter", 2, 750.0)
			"grill2": add.call("grill", 3, 1100.0)
			"fridge": add.call("coldbox", 1, 800.0)
			"fridge2": add.call("coldbox", 2, 2100.0)
			"awning": add.call("shade", 1, 550.0)
			"speaker": add.call("music", 1, 650.0)
			"neon":
				if "lights" in stage_stations:
					add.call("lights", 2, 1000.0)
				else:
					add.call("signage", 2, 1000.0)
			"sweets": add.call("sweets", 1, 2500.0)
			"helper": acc["refund"] += 300.0
			"seating": acc["refund"] += 800.0
	if _flag(_dictionary(_dictionary(parsed.get("menu", {})).get("fries", {})).get("unlocked")):
		if "fryer" in stage_stations:
			st["fryer"] = maxi(int(st.get("fryer", 0)), 1)
		else:
			menu["fries"]["unlocked"] = false
			acc["refund"] += 300.0
	for id in ["saffron_cake", "sago_halwa", "omani_halwa"]:
		if menu[id]["unlocked"] and int(st.get("sweets", 0)) < 1:
			menu[id]["unlocked"] = false
			acc["refund"] += float(Data.MENU_ITEMS[id]["unlock_cost"])
	var refund: float = acc["refund"]
	money += refund
	stats["days_played"] = maxi(int(stats["days_played"]), day - 1)
	stats["locations_visited"] = [location]
	_plot_entry(location)["reputation"] = popularity
	plots[location]["fame_best"] = Economy.fame_level(popularity)
	# skip the goals this player has already achieved (no retroactive cash)
	while goal_index < Data.GOALS.size() and Economy.goal_progress(Data.GOALS[goal_index], goal_snapshot()) >= 1.0:
		goals_claimed.append(Data.GOALS[goal_index]["id"])
		goal_index += 1
	notify.emit(tr("ui.migrated") % Loc.money(refund), "info")

## Bring a loaded save inside today's rules: price ranges change between versions, and a
## corrupt or hand-edited file must never produce NaN money or an impossible menu.
func _validate() -> void:
	tutorial = GuideJourney.clean(tutorial)
	if is_nan(money) or is_inf(money):
		money = 0.0
	if is_nan(popularity) or is_inf(popularity):
		popularity = Data.START_POPULARITY
	popularity = clampf(popularity, 0.05, 1.0)
	# a fame level once reached is never lost: the stored best (version 6) or, for older
	# saves, the level the stored popularity shows; popularity sits at or above its threshold
	fame_best = clampi(maxi(fame_best, Economy.fame_level(popularity)), 0, Data.FAME_LEVELS.size() - 1)
	popularity = maxf(popularity, Economy.fame_floor(fame_best))
	day = maxi(day, 1)
	prepared_day = clampi(prepared_day, 0, day)
	weather_day = clampi(weather_day, 0, day)
	day_seed = clampi(day_seed, 0, 2147483647)
	tutorial["started_day"] = mini(int(tutorial["started_day"]), day)
	total_served = maxi(total_served, 0)
	bailouts = clampi(bailouts, 0, Data.BAILOUT_MAX)
	# rig: a known mobile stage with known stations inside their caps
	var rig_stage := String(rig.get("stage", "cart"))
	if Data.stage_tier_of(rig_stage) >= FIXED_FROM_TIER or rig_stage != Data.PLOT_STAGES[Data.stage_tier_of(rig_stage)]["id"]:
		rig_stage = "cart"
	rig["stage"] = rig_stage
	rig["stations"] = _clean_stations(rig["stations"], Data.stage_def(rig_tier()))
	for loc_id in plots.keys():
		var p: Dictionary = plots[loc_id]
		var sid := String(p.get("stage", ""))
		if sid != "" and (Data.stage_tier_of(sid) < FIXED_FROM_TIER or sid != Data.PLOT_STAGES[Data.stage_tier_of(sid)]["id"]):
			sid = ""
		p["stage"] = sid
		p["stations"] = _clean_stations(p.get("stations", {}), Data.stage_def(Data.stage_tier_of(sid))) if sid != "" else {}
		var rep := float(p.get("reputation", popularity))
		p["reputation"] = Data.START_POPULARITY if is_nan(rep) or is_inf(rep) else clampf(rep, 0.05, 1.0)
		var best := clampi(maxi(int(_number(p.get("fame_best", 0))), Economy.fame_level(float(p["reputation"]))), 0, Data.FAME_LEVELS.size() - 1)
		p["fame_best"] = best
		p["reputation"] = maxf(float(p["reputation"]), Economy.fame_floor(best))
		p["last_visit"] = clampi(int(p.get("last_visit", day)), 1, day)
	if not location_stage_ok(location):
		location = "fahidi"
	_plot_entry(location)
	for ing in inventory:
		inventory[ing] = maxi(int(inventory[ing]), 0)
		if float(avg_cost[ing]) <= 0.0 or not is_finite(float(avg_cost[ing])):
			avg_cost[ing] = Data.reference_unit_price(ing)
	for id in menu:
		var enh: Array = Data.MENU_ITEMS[id]["enhance"]
		menu[id]["level"] = clampi(int(menu[id]["level"]), 0, enh.size())
		if is_nan(float(menu[id]["price"])):
			menu[id]["price"] = float(Data.MENU_ITEMS[id]["base_price"])
		for k in Data.RECIPE_SLIDERS:
			var s: Dictionary = Data.RECIPE_SLIDERS[k]
			menu[id]["recipe"][k] = clampi(int(menu[id]["recipe"][k]), int(s["min"]), int(s["max"]))
	clamp_prices()
	for id in marketing.keys():
		if not (id is String) or not Data.MARKETING.has(id) or int(_number(marketing[id])) < 1:
			marketing.erase(id)
		else:
			marketing[id] = mini(int(marketing[id]), int(Data.MARKETING[id]["days"]))
	goal_index = clampi(goal_index, 0, Data.GOALS.size())
	var known_goals := []
	for g in goals_claimed:
		for def in Data.GOALS:
			if g is String and def["id"] == g and not known_goals.has(g):
				known_goals.append(g)
	goals_claimed = known_goals
	_skip_claimed_goals()
	stats["best_day_profit"] = maxf(_number(stats.get("best_day_profit", 0.0)), 0.0)
	stats["total_profit"] = _number(stats.get("total_profit", 0.0))
	for k in ["best_day_served", "days_played", "levels_bought", "stages_built"]:
		stats[k] = maxi(int(stats.get(k, 0)), 0)
	var visited := []
	for v in stats.get("locations_visited", []):
		if v is String and Data.LOCATIONS.has(v) and not visited.has(v):
			visited.append(v)
	if not visited.has(location):
		visited.append(location)
	stats["locations_visited"] = visited
	var clean := []
	for r in history:
		if r is Dictionary and Data.LOCATIONS.has(_identifier(r.get("location"))) and Data.WEATHER.has(_identifier(r.get("weather"))):
			var row: Dictionary = r.duplicate(true)
			for k in ["day", "stage", "served", "portions", "passers", "dine_in", "left_wait", "lost_rival", "too_pricey", "sold_out", "queue_full", "crowd",
					"no_item", "closing", "mood_great", "mood_ok", "mood_bad"]:
				row[k] = maxi(0, int(_number(row.get(k, 0))))
			for k in ["profit", "money", "revenue", "cogs", "rent", "wages", "spoil_cost", "satisfaction", "pop_delta", "popularity", "local_rep", "local_delta", "review"]:
				row[k] = _number(row.get(k, 0.0))
			# version 6: the fame the day's guests brought and took (older rows: from the change)
			var pd := float(row["pop_delta"])
			var ld := float(row["local_delta"])
			for pair in [["fame_gain", maxf(pd, 0.0)], ["fame_loss", maxf(-pd, 0.0)], ["local_gain", maxf(ld, 0.0)], ["local_loss", maxf(-ld, 0.0)]]:
				row[pair[0]] = maxf(0.0, _number(row.get(pair[0], pair[1]), float(pair[1])))
			for k in ["fame_happy", "fame_content", "fame_unhappy"]:
				row[k] = maxi(0, int(_number(row.get(k, 0))))
			row["wait"] = maxf(0.0, _number(row.get("wait", 0.0)))
			# version 6: fame levels after the day (older rows: the level their value shows)
			row["fame_level"] = clampi(int(_number(row.get("fame_level", Economy.fame_level(float(row["popularity"]))))), 0, Data.FAME_LEVELS.size() - 1)
			row["local_fame_level"] = clampi(int(_number(row.get("local_fame_level", Economy.fame_level(float(row["local_rep"]))))), 0, Data.FAME_LEVELS.size() - 1)
			for k in ["fame_up", "local_fame_up"]:
				row[k] = _flag(row.get(k))
			row["bottleneck"] = _identifier(row.get("bottleneck"))
			row["sold"] = _int_dict(row.get("sold", {}))
			row["spoiled"] = _int_dict(row.get("spoiled", {}))
			row["util"] = _dictionary(row.get("util", {}))
			var kinds := {}
			var raw_kinds := _int_dict(row.get("no_item_kinds", {}))
			for kind in raw_kinds:
				if kind in ["food", "drink", "side", "sweet"] and int(raw_kinds[kind]) > 0:
					kinds[kind] = int(raw_kinds[kind])
			row["no_item_kinds"] = kinds
			var prices := {}
			var raw_prices := _dictionary(row.get("prices", {}))
			for id in raw_prices:
				var price := _number(raw_prices[id], -1.0)
				if Data.MENU_ITEMS.has(id) and price >= 0.0:
					prices[String(id)] = price
			row["prices"] = prices
			var promos := []
			for id in (row.get("promos") if row.get("promos") is Array else []):
				if id is String and Data.MARKETING.has(id) and not promos.has(id):
					promos.append(id)
			row["promos"] = promos
			clean.append(row)
	history = clean
	if history.size() > HISTORY_LIMIT:
		history = history.slice(history.size() - HISTORY_LIMIT)

## Keep only known stations the stage allows, levels clamped to their caps.
func _clean_stations(raw, stage_def_: Dictionary) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for id in raw:
			if Data.STATIONS.has(id) and id in stage_def_["stations"]:
				var lvl := clampi(int(raw[id]), 0, Economy.station_level_cap(Data.STATIONS[id], stage_def_))
				if lvl > 0:
					out[String(id)] = lvl
	return out

func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if _web():
		var ls := _web_storage()
		if ls:
			ls.removeItem(WEB_SAVE_KEY)

extends Node
## Mutable game state: money, inventory, menu, the rig/plot stations, goals, location, day cycle.
## Emits `changed` whenever something the UI shows may have moved.

signal changed
signal notify(text: String, kind: String)
signal goal_claimed(goal: Dictionary)

const SAVE_VERSION := 4
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
	if money < Data.BAILOUT_BELOW and bailouts < Data.BAILOUT_MAX:
		bailouts += 1
		money += Data.BAILOUT_AMOUNT
		notify.emit(tr("ui.loan") % Loc.money(Data.BAILOUT_AMOUNT), "warn")
	if prepared_day != day:
		for id in plots:
			if id == location:
				continue
			var p: Dictionary = plots[id]
			var away := day - int(p.get("last_visit", day))
			if away > 0 and plot_stage_tier(id) >= FIXED_FROM_TIER:
				p["reputation"] = Economy.reputation_decay(float(p["reputation"]), 1)
		prepared_day = day
	var here := plot()
	here["last_visit"] = day
	if not stats["locations_visited"].has(location):
		stats["locations_visited"].append(location)
	changed.emit()

func expected_customers() -> int:
	return Economy.expected_customers(sim_context())

func food_on_sale() -> bool:
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "food" and is_on_sale(id) and portions_possible(id) > 0:
			return true
	return false

## Decide the real weather for the day that is about to start.
func begin_day() -> void:
	if weather_day == day:
		return
	if rng.randf() < Data.FORECAST_ACCURACY:
		weather = forecast
	else:
		weather = _roll_weather()
	weather_day = day
	day_seed = rng.randi_range(1, 2147483647)
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
		plots[id] = {"stage": "", "stations": {}, "reputation": popularity, "last_visit": day}
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

## Kitchen station -> portions per minute, for the stations present at this stage.
func kitchen_caps() -> Dictionary:
	var out := {}
	for id in stage_def()["stations"]:
		var def: Dictionary = Data.STATIONS[id]
		if def.has("kinds"):
			out[id] = Economy.kitchen_capacity(def, station_level(id))
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

## Overnight loss rate for an ingredient given the cold storage level.
func spoil_rate(ing: String) -> float:
	var def: Dictionary = Data.INGREDIENTS[ing]
	var rate := float(def["spoil"])
	var cold: Dictionary = Data.STATIONS["coldbox"]
	var level := clampi(station_level("coldbox"), 0, 3)
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
			"price": float(menu[id]["price"]), "unit_cost": unit_cost(id),
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

func satisfaction_bonus() -> float:
	var b := 0.0
	for id in stage_def()["stations"]:
		b += float(Data.STATIONS[id].get("satisfaction_per_level", 0.0)) * station_level(id)
	return b

func marketing_boost() -> float:
	var b := 0.0
	for id in marketing:
		b += float(Data.MARKETING[id]["boost"])
	return b

func daily_wages() -> float:
	return 0.0

func stars() -> float:
	return popularity * 5.0

func local_reputation() -> float:
	return float(plot().get("reputation", popularity))

func effective_popularity() -> float:
	return Economy.effective_popularity(popularity, local_reputation())

func location_unlocked(id: String) -> bool:
	return popularity >= float(Data.LOCATIONS[id].get("unlock_pop", 0.0))

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
	for id in Data.STATIONS:
		st[id] = maxi(int(rig["stations"].get(id, 0)), station_level(id))
	return {
		"day_served": int(last.get("served", 0)), "day_profit": float(last.get("profit", 0.0)), "day_dine_in": int(last.get("dine_in", 0)),
		"total_served": total_served, "stars": stars(), "levels_owned": levels_owned(), "stage": stage_tier(),
		"stations": st, "visited": stats["locations_visited"], "unlocked": unlocked,
	}

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
	popularity = clampf(popularity + float(reward.get("popularity", 0.0)), 0.05, 1.0)
	goals_claimed.append(g["id"])
	goal_index += 1
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
func daily_stock_plan() -> Dictionary:
	var ctx := sim_context()
	ctx["weather"] = forecast
	var customers := Economy.expected_customers(ctx)
	var items: Array = ctx["offer"]
	var sums := {"food": 0.0, "drink": 0.0, "side": 0.0, "sweet": 0.0}
	var counts := {"food": 0, "drink": 0, "side": 0, "sweet": 0}
	for item in items:
		if item_available(item["id"]):
			sums[item["kind"]] += float(item["value"])
			counts[item["kind"]] += 1
	var ds := Economy.drink_share(forecast)
	var bonus := 0.25 * float(ctx["dine_in_share"])
	var drink_p := 0.65 if forecast == "hot" else (0.2 if forecast == "breeze" else 0.3)
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
			var chance := drink_p if kind == "drink" else (0.4 if kind == "side" else 0.35)
			if counts["food"] > 0:
				share += (1.0 - ds) * (chance + bonus) * appeal / int(counts[kind])
		var portions := ceili(customers * share * 1.1)
		var recipe := Economy.portion_ingredients(item["id"], menu[item["id"]])
		for ing in recipe:
			needs[ing] = int(needs.get(ing, 0)) + portions * int(recipe[ing])
	var orders := []
	var cost := 0.0
	for ing in needs:
		var deficit := int(needs[ing]) - int(inventory.get(ing, 0))
		if deficit <= 0:
			continue
		var quote := Economy.supply_packs(Data.INGREDIENTS[ing]["packs"], deficit)
		cost += float(quote["cost"])
		for i in range(quote["counts"].size()):
			if int(quote["counts"][i]) > 0:
				orders.append([ing, i, int(quote["counts"][i])])
	return {"cost": cost, "orders": orders, "customers": customers}

func stock_for_today() -> bool:
	var plan := daily_stock_plan()
	var cost := float(plan["cost"])
	# Leave the day's unavoidable bills in the till.
	if cost <= 0.0 or cost > maxf(0.0, money - float(loc()["rent"]) - daily_wages()):
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
	if nxt.has("requires_local_rep") and local_reputation() < float(nxt["requires_local_rep"]):
		return tr("ui.b_needs_rep") % (float(nxt["requires_local_rep"]) * 5.0)
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
	if marketing.has(id):
		notify.emit(tr("ui.already_running"), "error")
		return false
	var def: Dictionary = Data.MARKETING[id]
	if not _spend(float(def["cost"])):
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
	if not stats["locations_visited"].has(id):
		stats["locations_visited"].append(id)
	if not clamp_prices().is_empty():
		notify.emit(tr("ui.m_price_clamped") % tr(loc()["name"]), "warn")
	changed.emit()
	return true

# ---------------------------------------------------------------- day cycle

func sim_context() -> Dictionary:
	var sd := stage_def()
	var n_seats := seats()
	return {
		"day": day,
		"location": location,
		"weather": weather,
		"hours": Data.location_hours(location),
		"stage": stage_tier(),
		"stations": active_stations(),
		"counter_cap": counter_capacity(),
		"queue_cap": queue_capacity(),
		"kitchen": kitchen_caps(),
		"station_of_kind": station_of_kind(),
		"seats": n_seats,
		"dine_in_share": Economy.dine_in_share(sd, n_seats),
		"dwell_min": float(Data.STATIONS["seating"]["dwell_min"]),
		"clean_min": float(Data.STATIONS["seating"]["clean_min"]),
		"spend_mult": Economy.spend_multiplier(station_level("majlis") if station_available("majlis") else 0),
		"appeal": float(sd["appeal"]),
		"patience_min": Economy.BASE_PATIENCE_MIN * float(loc().get("patience", 1.0)),
		"boost": marketing_boost() + attract_bonus(),
		"competition": competition(),
		"promo_power": promo_power(),
		"shade_level": station_level("shade"),
		"lights_level": station_level("lights") if station_available("lights") else 0,
		"satisfaction_bonus": satisfaction_bonus(),
		"popularity": effective_popularity(),
		"local_rep": local_reputation(),
		"offer": offer(true),
		"wages": daily_wages(),
		"cars_per_hour": 0.0,
	}

## The context a different setup would produce, without changing anything:
## overrides = {"stations": {id: level}, "stage": tier, "location": id, "unlock": item_id}.
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
	var pop_delta := Economy.popularity_delta(day_stats, popularity)
	popularity = clampf(popularity + pop_delta, 0.05, 1.0)
	var p := plot()
	var local_delta := Economy.popularity_delta(day_stats, float(p["reputation"])) * 1.5
	p["reputation"] = clampf(float(p["reputation"]) + local_delta, 0.05, 1.0)
	p["last_visit"] = day
	for id in marketing.keys():
		marketing[id] = int(marketing[id]) - 1
		if marketing[id] <= 0:
			marketing.erase(id)
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
		"satisfaction": (float(day_stats.get("satisfaction_sum", 0.0)) / maxi(1, int(day_stats.get("served", 0)))),
		"pop_delta": pop_delta,
		"popularity": popularity,
		"local_rep": float(p["reputation"]),
		"local_delta": local_delta,
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
		"money": money, "day": day, "popularity": popularity,
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
			menu[id]["unlocked"] = bool(m.get("unlocked", false)) or bool(Data.MENU_ITEMS[id]["start"])
			menu[id]["enabled"] = bool(m.get("enabled", false))
			menu[id]["price"] = _number(m.get("price", menu[id]["price"]), menu[id]["price"])
			menu[id]["level"] = int(_number(m.get("level", 0)))
			for k in Data.RECIPE_SLIDERS:
				menu[id]["recipe"][k] = int(_number(_dictionary(m.get("recipe", {})).get(k, menu[id]["recipe"][k]), menu[id]["recipe"][k]))
	for id in _dictionary(parsed.get("marketing", {})):
		if Data.MARKETING.has(id):
			marketing[id] = int(_number(parsed["marketing"][id]))
	history = parsed.get("history", []) if parsed.get("history") is Array else []
	if parsed.get("rig", null) is Dictionary:
		rig = {"stage": _identifier(parsed["rig"].get("stage"), "cart"), "stations": _int_dict(parsed["rig"].get("stations", {}))}
	plots = {}
	if parsed.get("plots", null) is Dictionary:
		for loc_id in parsed["plots"]:
			var p = parsed["plots"][loc_id]
			if Data.LOCATIONS.has(loc_id) and p is Dictionary:
				plots[loc_id] = {"stage": _identifier(p.get("stage")), "stations": _int_dict(p.get("stations", {})),
					"reputation": _number(p.get("reputation", popularity), popularity), "last_visit": int(_number(p.get("last_visit", day), day))}
	goal_index = int(_number(parsed.get("goal_index", 0)))
	goals_claimed = parsed.get("goals_claimed", []) if parsed.get("goals_claimed", null) is Array else []
	stats = _new_stats()
	if parsed.get("stats", null) is Dictionary:
		for k in stats:
			if parsed["stats"].has(k):
				stats[k] = (parsed["stats"][k] if parsed["stats"][k] is Array else []) if k == "locations_visited" else _number(parsed["stats"][k])
	if int(_number(parsed.get("version", 1), 1)) < 3:
		_migrate_legacy(parsed)
	_validate()
	changed.emit()
	return true

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
	if bool(parsed.get("menu", {}).get("fries", {}).get("unlocked", false)):
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
		p["reputation"] = Data.START_POPULARITY if is_nan(rep) else clampf(rep, 0.05, 1.0)
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
		if int(marketing[id]) < 1:
			marketing.erase(id)
	goal_index = clampi(goal_index, 0, Data.GOALS.size())
	var known_goals := []
	for g in goals_claimed:
		for def in Data.GOALS:
			if g is String and def["id"] == g and not known_goals.has(g):
				known_goals.append(g)
	goals_claimed = known_goals
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
			for k in ["day", "stage", "served", "passers", "dine_in", "left_wait", "lost_rival", "too_pricey", "sold_out", "queue_full"]:
				row[k] = maxi(0, int(_number(row.get(k, 0))))
			for k in ["profit", "money", "revenue", "cogs", "rent", "wages", "spoil_cost", "satisfaction", "pop_delta", "popularity", "local_rep", "local_delta"]:
				row[k] = _number(row.get(k, 0.0))
			row["bottleneck"] = _identifier(row.get("bottleneck"))
			row["sold"] = _int_dict(row.get("sold", {}))
			row["spoiled"] = _int_dict(row.get("spoiled", {}))
			row["util"] = _dictionary(row.get("util", {}))
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

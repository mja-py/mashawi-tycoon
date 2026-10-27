extends Node
## Mutable game state: money, inventory, menu, upgrades, location, day cycle.
## Emits `changed` whenever something the UI shows may have moved.

signal changed
signal notify(text: String, kind: String)

const SAVE_VERSION := 1
const HISTORY_LIMIT := 90
## Tests and headless runs point this elsewhere so the player's save is never touched.
var save_path := "user://save.json"
var persist := true

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
var upgrades: Dictionary = {}
var vehicle: String = "cart"
var marketing: Dictionary = {}
var history: Array = []
var total_served: int = 0
var bailouts: int = 0
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
	upgrades = {}
	vehicle = "cart"
	marketing = {}
	history = []
	total_served = 0
	bailouts = 0
	forecast = _roll_weather()
	weather = forecast
	changed.emit()

## Called when the prep screen opens. A relative lends a little cash if you're broke,
## so a bad streak never ends the game outright.
func prepare_day() -> void:
	if money < Data.BAILOUT_BELOW and bailouts < Data.BAILOUT_MAX:
		bailouts += 1
		money += Data.BAILOUT_AMOUNT
		notify.emit(tr("ui.loan") % Loc.money(Data.BAILOUT_AMOUNT), "warn")
		changed.emit()

func expected_customers() -> int:
	return Economy.expected_customers(loc(), forecast, Data.location_hours(location), popularity, marketing_boost() + attract_bonus(), has_upgrade("awning"))

func food_on_sale() -> bool:
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "food" and is_on_sale(id) and portions_possible(id) > 0:
			return true
	return false

## Decide the real weather for the day that is about to start.
func begin_day() -> void:
	if rng.randf() < Data.FORECAST_ACCURACY:
		weather = forecast
	else:
		weather = _roll_weather()
	changed.emit()

# ---------------------------------------------------------------- queries

func loc() -> Dictionary:
	return Data.LOCATIONS[location]

func weather_def() -> Dictionary:
	return Data.WEATHER[weather]

## Overnight loss rate for an ingredient given the fridge upgrades.
func spoil_rate(ing: String) -> float:
	var def: Dictionary = Data.INGREDIENTS[ing]
	var rate := float(def["spoil"])
	if def["cold"] is bool and def["cold"]:
		if has_upgrade("fridge2"):
			rate = 0.0
		elif has_upgrade("fridge"):
			rate = float(Data.UPGRADES["fridge"]["spoil_meat"])
	elif def["cold"] is String and has_upgrade("fridge2"):
		rate = 0.0
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
	return m["unlocked"] and m["enabled"]

func has_upgrade(id: String) -> bool:
	return upgrades.has(id)

func vehicle_def() -> Dictionary:
	return Data.VEHICLES[vehicle]

func vehicle_tier() -> int:
	return int(vehicle_def()["tier"])

func service_time_min() -> float:
	var t := Economy.BASE_SERVICE_MIN * float(vehicle_def().get("service", 1.0))
	for id in upgrades:
		t *= float(Data.UPGRADES[id].get("service", 1.0))
	return t

func queue_capacity() -> int:
	var c := Economy.BASE_QUEUE_CAP + int(vehicle_def().get("queue", 0))
	for id in upgrades:
		c += int(Data.UPGRADES[id].get("queue", 0))
	return c

func competition() -> float:
	return float(loc().get("competition", 0.0))

func promo_power() -> float:
	return float(loc().get("promo_power", 1.0))

## Share of customers rivals take at this place with the current promotions.
func competition_loss() -> float:
	return Economy.competition_loss(competition(), marketing_boost() + attract_bonus(), promo_power())

func item_available(item_id: String) -> bool:
	var def: Dictionary = Data.MENU_ITEMS[item_id]
	return not def.has("requires") or has_upgrade(def["requires"])

func ingredient_available(ing: String) -> bool:
	var def: Dictionary = Data.INGREDIENTS[ing]
	return not def.has("requires") or has_upgrade(def["requires"])

func location_vehicle_ok(id: String) -> bool:
	return vehicle_tier() >= int(Data.LOCATIONS[id].get("vehicle", 0))

func buy_vehicle(id: String) -> bool:
	var def: Dictionary = Data.VEHICLES[id]
	if int(def["tier"]) <= vehicle_tier():
		return false
	if int(def["tier"]) > vehicle_tier() + 1:
		notify.emit(tr("ui.veh_order"), "error")
		return false
	if not _spend(float(def["cost"])):
		return false
	vehicle = id
	notify.emit(tr("ui.bought") % tr(def["name"]), "good")
	changed.emit()
	return true

func attract_bonus() -> float:
	var b := 0.0
	for id in upgrades:
		b += float(Data.UPGRADES[id].get("attract", 0.0))
	return b

func satisfaction_bonus() -> float:
	var b := 0.0
	for id in upgrades:
		b += float(Data.UPGRADES[id].get("satisfaction", 0.0))
	return b

func marketing_boost() -> float:
	var b := 0.0
	for id in marketing:
		b += float(Data.MARKETING[id]["boost"])
	return b

func daily_wages() -> float:
	var w := 0.0
	for id in upgrades:
		w += float(Data.UPGRADES[id].get("wage", 0.0))
	return w

func stars() -> float:
	return popularity * 5.0

func location_unlocked(id: String) -> bool:
	return popularity >= float(Data.LOCATIONS[id].get("unlock_pop", 0.0))

func stage_locations() -> Array:
	return Data.STAGES[stage]["locations"]

# ---------------------------------------------------------------- actions

func _spend(amount: float) -> bool:
	if amount > money + 0.0001:
		notify.emit(tr("ui.no_money"), "error")
		return false
	money -= amount
	return true

func buy_pack(ingredient: String, pack_index: int) -> bool:
	var pack: Array = Data.INGREDIENTS[ingredient]["packs"][pack_index]
	if not _spend(float(pack[1])):
		return false
	var have := int(inventory.get(ingredient, 0))
	var add := int(pack[0])
	avg_cost[ingredient] = (have * ingredient_cost(ingredient) + float(pack[1])) / float(have + add)
	inventory[ingredient] = have + add
	changed.emit()
	return true

func set_price(item_id: String, price: float) -> void:
	menu[item_id]["price"] = snappedf(clampf(price, 1.0, 200.0), 1.0)
	changed.emit()

func set_recipe(item_id: String, key: String, value: int) -> void:
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
		notify.emit(tr("ui.requires") % tr(Data.UPGRADES[Data.MENU_ITEMS[item_id]["requires"]]["name"]), "error")
		return false
	if not _spend(float(Data.MENU_ITEMS[item_id]["unlock_cost"])):
		return false
	menu[item_id]["unlocked"] = true
	menu[item_id]["enabled"] = true
	notify.emit(tr("ui.added") % tr(Data.MENU_ITEMS[item_id]["name"]), "good")
	changed.emit()
	return true

func enhance_item(item_id: String) -> bool:
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

func buy_upgrade(id: String) -> bool:
	if upgrades.has(id):
		return false
	var def: Dictionary = Data.UPGRADES[id]
	if def.has("requires") and not upgrades.has(def["requires"]):
		notify.emit(tr("ui.requires") % tr(Data.UPGRADES[def["requires"]]["name"]), "error")
		return false
	if int(def.get("requires_vehicle", 0)) > vehicle_tier():
		notify.emit(tr("ui.requires") % tr(Data.VEHICLES[Data.vehicle_for_tier(int(def["requires_vehicle"]))]["name"]), "error")
		return false
	if not _spend(float(def["cost"])):
		return false
	upgrades[id] = true
	notify.emit(tr("ui.bought") % tr(def["name"]), "good")
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
	if not location_vehicle_ok(id):
		notify.emit(tr("ui.veh_needed"), "error")
		return false
	location = id
	changed.emit()
	return true

# ---------------------------------------------------------------- day cycle

func sim_context() -> Dictionary:
	return {
		"location": location,
		"weather": weather,
		"hours": Data.location_hours(location),
		"service_min": service_time_min(),
		"queue_cap": queue_capacity(),
		"patience_min": Economy.BASE_PATIENCE_MIN * float(loc().get("patience", 1.0)),
		"boost": marketing_boost() + attract_bonus(),
		"competition": competition(),
		"promo_power": promo_power(),
		"has_awning": has_upgrade("awning"),
		"satisfaction_bonus": satisfaction_bonus(),
	}

## Sell one portion of an item. Returns false if ingredients are missing.
func sell(item_id: String, price: float) -> bool:
	var needs := Economy.portion_ingredients(item_id, menu[item_id])
	for ing in needs:
		if int(inventory.get(ing, 0)) < int(needs[ing]):
			return false
	for ing in needs:
		inventory[ing] = int(inventory[ing]) - int(needs[ing])
	money += price
	total_served += 1
	return true

## Close the books for the day. Returns the report dictionary shown to the player.
func end_day(stats: Dictionary) -> Dictionary:
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
	var pop_delta := Economy.popularity_delta(stats, popularity)
	popularity = clampf(popularity + pop_delta, 0.05, 1.0)
	for id in marketing.keys():
		marketing[id] = int(marketing[id]) - 1
		if marketing[id] <= 0:
			marketing.erase(id)
	var revenue := float(stats.get("revenue", 0.0))
	var cogs := float(stats.get("cogs", 0.0))
	var report := {
		"day": day,
		"location": location,
		"weather": weather,
		"served": int(stats.get("served", 0)),
		"passers": int(stats.get("passers", 0)),
		"revenue": revenue,
		"cogs": cogs,
		"rent": rent,
		"wages": wages,
		"spoiled": spoiled,
		"spoil_cost": spoil_cost,
		"profit": revenue - cogs - rent - wages - spoil_cost,
		"left_wait": int(stats.get("left_wait", 0)),
		"lost_rival": int(stats.get("lost_rival", 0)),
		"too_pricey": int(stats.get("too_pricey", 0)),
		"sold_out": int(stats.get("sold_out", 0)),
		"queue_full": int(stats.get("queue_full", 0)),
		"satisfaction": (float(stats.get("satisfaction_sum", 0.0)) / maxi(1, int(stats.get("served", 0)))),
		"pop_delta": pop_delta,
		"popularity": popularity,
		"sold": stats.get("sold", {}),
		"money": money,
	}
	history.append(report)
	if history.size() > HISTORY_LIMIT:
		history = history.slice(history.size() - HISTORY_LIMIT)
	day += 1
	forecast = _roll_weather()
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

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func save() -> void:
	if not persist:
		return
	var data := {
		"version": SAVE_VERSION, "money": money, "day": day, "popularity": popularity,
		"stage": stage, "location": location, "weather": weather, "forecast": forecast,
		"inventory": inventory, "avg_cost": avg_cost, "menu": menu, "upgrades": upgrades, "marketing": marketing,
		"history": history, "total_served": total_served, "bailouts": bailouts, "vehicle": vehicle,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	new_game()
	money = float(parsed.get("money", money))
	day = int(parsed.get("day", day))
	popularity = float(parsed.get("popularity", popularity))
	# saves from older versions may name places or weather that no longer exist
	if Data.STAGES.has(String(parsed.get("stage", ""))):
		stage = String(parsed["stage"])
	if Data.LOCATIONS.has(String(parsed.get("location", ""))):
		location = String(parsed["location"])
	if Data.WEATHER.has(String(parsed.get("weather", ""))):
		weather = String(parsed["weather"])
	if Data.WEATHER.has(String(parsed.get("forecast", ""))):
		forecast = String(parsed["forecast"])
	total_served = int(parsed.get("total_served", 0))
	bailouts = int(parsed.get("bailouts", 0))
	if Data.VEHICLES.has(String(parsed.get("vehicle", ""))):
		vehicle = String(parsed["vehicle"])
	for ing in parsed.get("inventory", {}):
		if inventory.has(ing):
			inventory[ing] = int(parsed["inventory"][ing])
	for ing in parsed.get("avg_cost", {}):
		if avg_cost.has(ing):
			avg_cost[ing] = float(parsed["avg_cost"][ing])
	for id in parsed.get("menu", {}):
		if menu.has(id):
			var m: Dictionary = parsed["menu"][id]
			menu[id]["unlocked"] = bool(m.get("unlocked", false))
			menu[id]["enabled"] = bool(m.get("enabled", false))
			menu[id]["price"] = float(m.get("price", menu[id]["price"]))
			menu[id]["level"] = int(m.get("level", 0))
			for k in Data.RECIPE_SLIDERS:
				menu[id]["recipe"][k] = int(m.get("recipe", {}).get(k, menu[id]["recipe"][k]))
	for id in parsed.get("upgrades", {}):
		if Data.UPGRADES.has(id):
			upgrades[id] = true
	for id in parsed.get("marketing", {}):
		if Data.MARKETING.has(id):
			marketing[id] = int(parsed["marketing"][id])
	history = parsed.get("history", [])
	changed.emit()
	return true

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

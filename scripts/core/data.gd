extends Node
## Static game definitions for Mashawi Tycoon (Dubai edition). All text fields are
## translation keys (see assets/i18n/strings.csv); money is in AED.

const START_MONEY := 1500.0
const BAILOUT_BELOW := 200.0
const BAILOUT_AMOUNT := 600.0
const BAILOUT_MAX := 6
const START_POPULARITY := 0.22
const DAY_START_HOUR := 10
const DAY_END_HOUR := 22
const REAL_SECONDS_PER_GAME_HOUR := 10.0

const INGREDIENTS := {
	"bread": {"name": "ing.bread", "unit": "unit.pcs", "spoil": 0.05, "cold": false, "model": "food/pita-stack",
		"packs": [[20, 10.0], [100, 42.0], [300, 110.0]]},
	"chicken": {"name": "ing.chicken", "unit": "unit.portions", "spoil": 0.35, "cold": true, "model": "food/chicken-tray",
		"packs": [[10, 18.0], [40, 62.0], [120, 165.0]]},
	"mutton": {"name": "ing.mutton", "unit": "unit.portions", "spoil": 0.35, "cold": true, "model": "food/lamb-tray",
		"packs": [[10, 30.0], [40, 105.0], [120, 280.0]]},
	"mince": {"name": "ing.mince", "unit": "unit.portions", "spoil": 0.35, "cold": true, "model": "food/kofta-tray",
		"packs": [[10, 22.0], [40, 76.0], [120, 200.0]]},
	"veg": {"name": "ing.veg", "unit": "unit.portions", "spoil": 0.20, "cold": "veg", "model": "food/salad-bowl",
		"packs": [[20, 10.0], [80, 34.0], [200, 75.0]]},
	"sauce": {"name": "ing.sauce", "unit": "unit.portions", "spoil": 0.02, "cold": false, "model": "food/bottle-ketchup",
		"packs": [[20, 5.0], [100, 18.0], [300, 45.0]]},
	"charcoal": {"name": "ing.charcoal", "unit": "unit.pcs", "spoil": 0.0, "cold": false, "model": "food/charcoal-bag",
		"packs": [[30, 12.0], [120, 40.0], [400, 110.0]]},
	"yogurt": {"name": "ing.yogurt", "unit": "unit.cups", "spoil": 0.15, "cold": false, "model": "food/cup",
		"packs": [[12, 20.0], [48, 68.0], [144, 175.0]]},
	"drink": {"name": "ing.drink", "unit": "unit.cans", "spoil": 0.0, "cold": false, "model": "food/soda-can",
		"packs": [[12, 18.0], [48, 62.0], [144, 165.0]]},
	"karak": {"name": "ing.karak", "unit": "unit.cups", "spoil": 0.0, "cold": false, "model": "food/karak-cup",
		"packs": [[20, 12.0], [80, 40.0], [200, 90.0]]},
	"fries": {"name": "ing.fries", "unit": "unit.portions", "spoil": 0.0, "cold": false, "model": "food/fries",
		"packs": [[20, 32.0], [80, 110.0], [200, 240.0]]},
	"cake": {"name": "ing.cake", "unit": "unit.slices", "spoil": 0.25, "cold": "veg", "model": "food/saffron-cake", "requires": "sweets",
		"packs": [[10, 45.0], [40, 160.0], [120, 420.0]]},
	"sago": {"name": "ing.sago", "unit": "unit.portions", "spoil": 0.15, "cold": false, "model": "food/sago-halwa", "requires": "sweets",
		"packs": [[10, 28.0], [40, 100.0], [120, 270.0]]},
	"halwa": {"name": "ing.halwa", "unit": "unit.portions", "spoil": 0.05, "cold": false, "model": "food/omani-halwa", "requires": "sweets",
		"packs": [[10, 38.0], [40, 135.0], [120, 360.0]]},
}

## Dubai cafeteria mashawi: priced per skewer, bread and salad on the side.
const MENU_ITEMS := {
	"chicken_tikka": {"name": "item.chicken_tikka", "desc": "item.chicken_tikka.desc", "start": true, "unlock_cost": 0.0, "base_price": 10.0,
		"appeal": 1.0, "kind": "food", "model": "food/chicken-skewer", "recipe": true, "meat_ingredient": "chicken",
		"ingredients": {"bread": 1, "chicken": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 1},
		"enhance": [{"name": "item.chicken_tikka.e1", "cost": 350.0, "quality": 0.08}, {"name": "item.chicken_tikka.e2", "cost": 600.0, "quality": 0.08},
			{"name": "item.chicken_tikka.e3", "cost": 1000.0, "quality": 0.10}]},
	"mutton_tikka": {"name": "item.mutton_tikka", "desc": "item.mutton_tikka.desc", "start": false, "unlock_cost": 450.0, "base_price": 14.0,
		"appeal": 1.05, "kind": "food", "model": "food/mutton-skewer", "recipe": true, "meat_ingredient": "mutton",
		"ingredients": {"bread": 1, "mutton": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 1},
		"enhance": [{"name": "item.mutton_tikka.e1", "cost": 450.0, "quality": 0.08}, {"name": "item.mutton_tikka.e2", "cost": 800.0, "quality": 0.08},
			{"name": "item.mutton_tikka.e3", "cost": 1400.0, "quality": 0.10}]},
	"kebab": {"name": "item.kebab", "desc": "item.kebab.desc", "start": false, "unlock_cost": 350.0, "base_price": 10.0,
		"appeal": 0.9, "kind": "food", "model": "food/kebab-skewer", "recipe": true, "meat_ingredient": "mince",
		"ingredients": {"bread": 1, "mince": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 1},
		"enhance": [{"name": "item.kebab.e1", "cost": 300.0, "quality": 0.08}, {"name": "item.kebab.e2", "cost": 550.0, "quality": 0.08},
			{"name": "item.kebab.e3", "cost": 1000.0, "quality": 0.10}]},
	"sandwich": {"name": "item.sandwich", "desc": "item.sandwich.desc", "start": true, "unlock_cost": 0.0, "base_price": 7.0,
		"appeal": 0.85, "kind": "food", "model": "food/tikka-sandwich", "recipe": false, "meat_ingredient": "chicken",
		"ingredients": {"bread": 1, "chicken": 1, "veg": 1, "sauce": 1, "charcoal": 1},
		"enhance": [{"name": "item.sandwich.e1", "cost": 250.0, "quality": 0.08}, {"name": "item.sandwich.e2", "cost": 500.0, "quality": 0.1}]},
	"mixed": {"name": "item.mixed", "desc": "item.mixed.desc", "start": false, "unlock_cost": 1200.0, "base_price": 45.0,
		"appeal": 1.15, "kind": "food", "model": "food/mashawi-platter", "recipe": true, "meat_ingredient": "mutton",
		"ingredients": {"bread": 2, "mutton": "@meat", "chicken": "@meat", "mince": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 3},
		"enhance": [{"name": "item.mixed.e1", "cost": 600.0, "quality": 0.08}, {"name": "item.mixed.e2", "cost": 1000.0, "quality": 0.08},
			{"name": "item.mixed.e3", "cost": 1800.0, "quality": 0.10}]},
	"salad": {"name": "item.salad", "desc": "item.salad.desc", "start": true, "unlock_cost": 0.0, "base_price": 5.0,
		"appeal": 0.4, "kind": "side", "model": "food/salad-bowl", "recipe": false,
		"ingredients": {"veg": 2},
		"enhance": [{"name": "item.salad.e1", "cost": 150.0, "quality": 0.1}]},
	"fries": {"name": "item.fries", "desc": "item.fries.desc", "start": false, "unlock_cost": 300.0, "base_price": 7.0,
		"appeal": 0.6, "kind": "side", "model": "food/fries", "recipe": false,
		"ingredients": {"fries": 1},
		"enhance": [{"name": "item.fries.e1", "cost": 250.0, "quality": 0.1}, {"name": "item.fries.e2", "cost": 700.0, "quality": 0.12}]},
	"laban": {"name": "item.laban", "desc": "item.laban.desc", "start": true, "unlock_cost": 0.0, "base_price": 4.0,
		"appeal": 0.5, "kind": "drink", "model": "food/cup", "recipe": false,
		"ingredients": {"yogurt": 1},
		"enhance": [{"name": "item.laban.e1", "cost": 250.0, "quality": 0.12}]},
	"soda": {"name": "item.soda", "desc": "item.soda.desc", "start": true, "unlock_cost": 0.0, "base_price": 4.0,
		"appeal": 0.5, "kind": "drink", "model": "food/soda-can", "recipe": false,
		"ingredients": {"drink": 1},
		"enhance": [{"name": "item.soda.e1", "cost": 200.0, "quality": 0.1}]},
	"karak": {"name": "item.karak", "desc": "item.karak.desc", "start": false, "unlock_cost": 150.0, "base_price": 2.0,
		"appeal": 0.55, "kind": "drink", "model": "food/karak-cup", "recipe": false,
		"ingredients": {"karak": 1},
		"enhance": [{"name": "item.karak.e1", "cost": 250.0, "quality": 0.12}]},
	"saffron_cake": {"name": "item.saffron_cake", "desc": "item.saffron_cake.desc", "start": false, "unlock_cost": 400.0, "base_price": 12.0,
		"appeal": 0.8, "kind": "sweet", "model": "food/saffron-cake", "recipe": false, "requires": "sweets",
		"ingredients": {"cake": 1},
		"enhance": [{"name": "item.saffron_cake.e1", "cost": 350.0, "quality": 0.1}, {"name": "item.saffron_cake.e2", "cost": 700.0, "quality": 0.12}]},
	"sago_halwa": {"name": "item.sago_halwa", "desc": "item.sago_halwa.desc", "start": false, "unlock_cost": 300.0, "base_price": 8.0,
		"appeal": 0.65, "kind": "sweet", "model": "food/sago-halwa", "recipe": false, "requires": "sweets",
		"ingredients": {"sago": 1},
		"enhance": [{"name": "item.sago_halwa.e1", "cost": 300.0, "quality": 0.1}, {"name": "item.sago_halwa.e2", "cost": 600.0, "quality": 0.12}]},
	"omani_halwa": {"name": "item.omani_halwa", "desc": "item.omani_halwa.desc", "start": false, "unlock_cost": 500.0, "base_price": 10.0,
		"appeal": 0.75, "kind": "sweet", "model": "food/omani-halwa", "recipe": false, "requires": "sweets",
		"ingredients": {"halwa": 1},
		"enhance": [{"name": "item.omani_halwa.e1", "cost": 400.0, "quality": 0.1}, {"name": "item.omani_halwa.e2", "cost": 800.0, "quality": 0.12}]},
}

const MENU_GROUPS := [["food", "menu.group.grill"], ["side", "menu.group.side"], ["drink", "menu.group.drink"], ["sweet", "menu.group.sweet"]]

## What you sell from. Bigger vehicles reach busier places and serve faster.
const VEHICLES := {
	"cart": {"name": "veh.cart", "desc": "veh.cart.desc", "cost": 0.0, "tier": 0, "queue": 0, "service": 1.0, "icon": "icons/stand-big"},
	"truck": {"name": "veh.truck", "desc": "veh.truck.desc", "cost": 2500.0, "tier": 1, "queue": 2, "service": 0.85, "icon": "icons/truck", "model": "cars/delivery"},
	"truck2": {"name": "veh.truck2", "desc": "veh.truck2.desc", "cost": 7000.0, "tier": 2, "queue": 4, "service": 0.75, "icon": "icons/truck-big", "model": "cars/truck"},
}

const RECIPE_SLIDERS := {
	"meat": {"name": "recipe.meat", "min": 1, "max": 3, "default": 2},
	"veg": {"name": "recipe.veg", "min": 0, "max": 3, "default": 2},
	"sauce": {"name": "recipe.sauce", "min": 0, "max": 3, "default": 1},
}

const WEATHER := {
	"sunny": {"name": "weather.sunny", "traffic": 1.0, "drink": 1.0, "food": 1.0, "sky": Color(0.58, 0.8, 0.98), "light": 1.05},
	"hot": {"name": "weather.hot", "traffic": 0.85, "drink": 1.9, "food": 0.85, "sky": Color(0.86, 0.82, 0.7), "light": 1.2},
	"cloudy": {"name": "weather.cloudy", "traffic": 0.95, "drink": 0.85, "food": 1.0, "sky": Color(0.76, 0.79, 0.82), "light": 0.8},
	"sandstorm": {"name": "weather.sandstorm", "traffic": 0.4, "drink": 0.7, "food": 0.9, "sky": Color(0.8, 0.66, 0.44), "light": 0.55},
	"breeze": {"name": "weather.breeze", "traffic": 1.2, "drink": 0.8, "food": 1.15, "sky": Color(0.55, 0.78, 0.98), "light": 1.0},
}
const WEATHER_ODDS := {"sunny": 0.40, "hot": 0.25, "cloudy": 0.15, "sandstorm": 0.08, "breeze": 0.12}
const FORECAST_ACCURACY := 0.72
const BAD_WEATHER := "sandstorm"

## "vehicle" = the tier needed to set up there; "competition" = share of customers rival stalls
## take unless you promote; "promo_power" = how much louder promotions are in that crowd.
const LOCATIONS := {
	"fahidi": {"name": "loc.fahidi", "desc": "loc.fahidi.desc", "rent": 0.0, "traffic": 0.55, "price_tol": 1.0, "quality_care": 0.8,
		"patience": 1.0, "exposure": 1.0, "peaks": [13.0, 19.0], "layout": "fahidi", "unlock_pop": 0.0, "vehicle": 0},
	"creek": {"name": "loc.creek", "desc": "loc.creek.desc", "rent": 125.0, "traffic": 0.85, "price_tol": 0.85, "quality_care": 0.9,
		"patience": 1.2, "exposure": 1.6, "hot_bonus": 0.2, "peaks": [13.0, 17.0], "layout": "creek", "unlock_pop": 0.0, "vehicle": 0},
	"metro": {"name": "loc.metro", "desc": "loc.metro.desc", "rent": 200.0, "traffic": 1.15, "price_tol": 0.95, "quality_care": 0.7,
		"patience": 0.6, "exposure": 0.7, "peaks": [9.0, 18.0], "layout": "metro", "unlock_pop": 0.2, "vehicle": 1},
	"jbr": {"name": "loc.jbr", "desc": "loc.jbr.desc", "rent": 275.0, "traffic": 0.95, "price_tol": 1.1, "quality_care": 0.9,
		"patience": 1.1, "exposure": 1.8, "hot_bonus": 0.8, "peaks": [14.0, 18.0], "layout": "jbr", "unlock_pop": 0.3, "vehicle": 1},
	"downtown": {"name": "loc.downtown", "desc": "loc.downtown.desc", "rent": 450.0, "traffic": 1.6, "price_tol": 1.3, "quality_care": 1.3,
		"patience": 0.9, "exposure": 0.9, "peaks": [12.5, 19.5], "layout": "downtown", "unlock_pop": 0.45, "vehicle": 1},
	"mall": {"name": "loc.mall", "desc": "loc.mall.desc", "rent": 600.0, "traffic": 1.8, "price_tol": 1.25, "quality_care": 1.2,
		"patience": 1.0, "exposure": 0.0, "peaks": [13.0, 20.0], "layout": "mall", "unlock_pop": 0.5, "vehicle": 2,
		"competition": 0.55, "promo_power": 1.8},
	"gv": {"name": "loc.gv", "desc": "loc.gv.desc", "rent": 500.0, "traffic": 2.0, "price_tol": 1.15, "quality_care": 1.1,
		"patience": 1.0, "exposure": 0.8, "peaks": [20.0, 23.0], "layout": "gv", "unlock_pop": 0.6, "vehicle": 2, "hours": [16, 24],
		"competition": 0.7, "promo_power": 2.0},
}

const STAGES := {
	"dubai": {"name": "stage.dubai", "locations": ["fahidi", "creek", "metro", "jbr", "downtown", "mall", "gv"]},
}

const UPGRADES := {
	"cart2": {"name": "up.cart2", "desc": "up.cart2.desc", "cost": 750.0, "queue": 3, "icon": "icons/stand-big"},
	"grill2": {"name": "up.grill2", "desc": "up.grill2.desc", "cost": 1100.0, "service": 0.7, "icon": "icons/grill-double"},
	"fridge": {"name": "up.fridge", "desc": "up.fridge.desc", "cost": 800.0, "spoil_meat": 0.1, "icon": "icons/fridge"},
	"fridge2": {"name": "up.fridge2", "desc": "up.fridge2.desc", "cost": 2100.0, "requires": "fridge", "spoil_meat": 0.0, "spoil_veg": 0.0, "icon": "icons/cooler"},
	"awning": {"name": "up.awning", "desc": "up.awning.desc", "cost": 550.0, "icon": "icons/shade-sail"},
	"speaker": {"name": "up.speaker", "desc": "up.speaker.desc", "cost": 650.0, "attract": 0.08, "icon": "icons/speaker"},
	"neon": {"name": "up.neon", "desc": "up.neon.desc", "cost": 1000.0, "attract": 0.12, "icon": "icons/neon-sign"},
	"seating": {"name": "up.seating", "desc": "up.seating.desc", "cost": 800.0, "satisfaction": 0.08, "icon": "icons/majlis"},
	"helper": {"name": "up.helper", "desc": "up.helper.desc", "cost": 300.0, "service": 0.65, "wage": 60.0, "icon": "icons/helper"},
	"sweets": {"name": "up.sweets", "desc": "up.sweets.desc", "cost": 2500.0, "requires_vehicle": 1, "icon": "food/sweets-counter"},
}

const MARKETING := {
	"fliers": {"name": "mk.fliers", "desc": "mk.fliers.desc", "cost": 150.0, "days": 1, "boost": 0.15, "icon": "icons/fliers"},
	"posters": {"name": "mk.posters", "desc": "mk.posters.desc", "cost": 450.0, "days": 3, "boost": 0.15, "icon": "icons/posters"},
	"social": {"name": "mk.social", "desc": "mk.social.desc", "cost": 750.0, "days": 7, "boost": 0.12, "icon": "icons/social"},
	"radio": {"name": "mk.radio", "desc": "mk.radio.desc", "cost": 1300.0, "days": 5, "boost": 0.30, "icon": "icons/radio"},
}

## Thought-bubble keys per mood; the number of lines per mood is in BUBBLE_COUNT.
const BUBBLE_COUNT := {"great": 5, "ok": 4, "bad_quality": 4, "too_pricey": 3, "too_slow": 3, "queue_full": 2,
	"sold_out": 3, "hot": 2, "sandstorm": 2, "breeze": 2, "rival": 3, "sweet": 2}

## The vehicle id that unlocks a given tier ("cart" for 0).
static func vehicle_for_tier(tier: int) -> String:
	for id in VEHICLES:
		if int(VEHICLES[id]["tier"]) == tier:
			return id
	return "cart"

## Reference unit price = the cheapest bulk price (used for unit cost estimates).
static func reference_unit_price(ingredient: String) -> float:
	var packs: Array = INGREDIENTS[ingredient]["packs"]
	var best := INF
	for p in packs:
		best = minf(best, float(p[1]) / float(p[0]))
	return best

static func location_hours(location_id: String) -> Array:
	var loc: Dictionary = LOCATIONS[location_id]
	if loc.has("hours"):
		return loc["hours"]
	return [DAY_START_HOUR, DAY_END_HOUR]

static func pick_bubble(key: String, rng: RandomNumberGenerator) -> String:
	var n := int(BUBBLE_COUNT.get(key, 1))
	return TranslationServer.translate("bubble.%s.%d" % [key, rng.randi_range(1, n)])

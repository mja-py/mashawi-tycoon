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

## Menu prices may range from PRICE_MIN_MULT x base price up to a cap that grows with the
## location's rent (cap = PRICE_CAP_BASE + PRICE_CAP_PER_RENT * rent, or the location's own
## "price_cap") plus the plot stage's "price_cap_bonus". Free Fahidi at the cart: 1.5x.
const PRICE_MIN_MULT := 0.5
const PRICE_CAP_BASE := 1.5
const PRICE_CAP_PER_RENT := 0.001

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
	"cake": {"name": "ing.cake", "unit": "unit.slices", "spoil": 0.25, "cold": "veg", "model": "food/saffron-cake", "requires_station": "sweets",
		"packs": [[10, 45.0], [40, 160.0], [120, 420.0]]},
	"sago": {"name": "ing.sago", "unit": "unit.portions", "spoil": 0.15, "cold": false, "model": "food/sago-halwa", "requires_station": "sweets",
		"packs": [[10, 28.0], [40, 100.0], [120, 270.0]]},
	"halwa": {"name": "ing.halwa", "unit": "unit.portions", "spoil": 0.05, "cold": false, "model": "food/omani-halwa", "requires_station": "sweets",
		"packs": [[10, 38.0], [40, 135.0], [120, 360.0]]},
}

## Dubai cafeteria mashawi: priced per skewer, bread and salad on the side. "station_kind" is
## the kitchen station that cooks the item (see STATIONS "kinds"); items without one are
## handed over at the counter. "requires_station" = that station must be at level 1 or more.
const MENU_ITEMS := {
	"chicken_tikka": {"name": "item.chicken_tikka", "desc": "item.chicken_tikka.desc", "start": true, "unlock_cost": 0.0, "base_price": 10.0,
		"appeal": 1.0, "kind": "food", "station_kind": "grill", "model": "food/chicken-skewer", "recipe": true, "meat_ingredient": "chicken",
		"ingredients": {"bread": 1, "chicken": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 1},
		"enhance": [{"name": "item.chicken_tikka.e1", "cost": 350.0, "quality": 0.08}, {"name": "item.chicken_tikka.e2", "cost": 600.0, "quality": 0.08},
			{"name": "item.chicken_tikka.e3", "cost": 1000.0, "quality": 0.10}]},
	"mutton_tikka": {"name": "item.mutton_tikka", "desc": "item.mutton_tikka.desc", "start": false, "unlock_cost": 450.0, "base_price": 14.0,
		"appeal": 1.05, "kind": "food", "station_kind": "grill", "model": "food/mutton-skewer", "recipe": true, "meat_ingredient": "mutton",
		"ingredients": {"bread": 1, "mutton": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 1},
		"enhance": [{"name": "item.mutton_tikka.e1", "cost": 450.0, "quality": 0.08}, {"name": "item.mutton_tikka.e2", "cost": 800.0, "quality": 0.08},
			{"name": "item.mutton_tikka.e3", "cost": 1400.0, "quality": 0.10}]},
	"kebab": {"name": "item.kebab", "desc": "item.kebab.desc", "start": false, "unlock_cost": 350.0, "base_price": 10.0,
		"appeal": 0.9, "kind": "food", "station_kind": "grill", "model": "food/kebab-skewer", "recipe": true, "meat_ingredient": "mince",
		"ingredients": {"bread": 1, "mince": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 1},
		"enhance": [{"name": "item.kebab.e1", "cost": 300.0, "quality": 0.08}, {"name": "item.kebab.e2", "cost": 550.0, "quality": 0.08},
			{"name": "item.kebab.e3", "cost": 1000.0, "quality": 0.10}]},
	"sandwich": {"name": "item.sandwich", "desc": "item.sandwich.desc", "start": true, "unlock_cost": 0.0, "base_price": 7.0,
		"appeal": 0.85, "kind": "food", "station_kind": "grill", "model": "food/tikka-sandwich", "recipe": false, "meat_ingredient": "chicken",
		"ingredients": {"bread": 1, "chicken": 1, "veg": 1, "sauce": 1, "charcoal": 1},
		"enhance": [{"name": "item.sandwich.e1", "cost": 250.0, "quality": 0.08}, {"name": "item.sandwich.e2", "cost": 500.0, "quality": 0.1}]},
	"shawarma": {"name": "item.shawarma", "desc": "item.shawarma.desc", "start": false, "unlock_cost": 300.0, "base_price": 12.0,
		"appeal": 1.1, "kind": "food", "station_kind": "doner", "model": "food/doner-wrap", "recipe": true, "meat_ingredient": "chicken",
		"requires_station": "doner",
		"ingredients": {"bread": 1, "chicken": "@meat", "veg": "@veg", "sauce": "@sauce"},
		"enhance": [{"name": "item.shawarma.e1", "cost": 400.0, "quality": 0.08}, {"name": "item.shawarma.e2", "cost": 700.0, "quality": 0.08},
			{"name": "item.shawarma.e3", "cost": 1200.0, "quality": 0.10}]},
	"mixed": {"name": "item.mixed", "desc": "item.mixed.desc", "start": false, "unlock_cost": 1200.0, "base_price": 45.0,
		"appeal": 0.5, "kind": "food", "station_kind": "grill", "model": "food/mashawi-platter", "recipe": true, "meat_ingredient": "mutton",
		"ingredients": {"bread": 2, "mutton": "@meat", "chicken": "@meat", "mince": "@meat", "veg": "@veg", "sauce": "@sauce", "charcoal": 3},
		"enhance": [{"name": "item.mixed.e1", "cost": 600.0, "quality": 0.08}, {"name": "item.mixed.e2", "cost": 1000.0, "quality": 0.08},
			{"name": "item.mixed.e3", "cost": 1800.0, "quality": 0.10}]},
	"salad": {"name": "item.salad", "desc": "item.salad.desc", "start": true, "unlock_cost": 0.0, "base_price": 5.0,
		"appeal": 0.4, "kind": "side", "station_kind": "", "model": "food/salad-bowl", "recipe": false,
		"ingredients": {"veg": 2},
		"enhance": [{"name": "item.salad.e1", "cost": 150.0, "quality": 0.1}]},
	"fries": {"name": "item.fries", "desc": "item.fries.desc", "start": false, "unlock_cost": 300.0, "base_price": 7.0,
		"appeal": 0.6, "kind": "side", "station_kind": "fry", "model": "food/fries", "recipe": false, "requires_station": "fryer",
		"ingredients": {"fries": 1},
		"enhance": [{"name": "item.fries.e1", "cost": 250.0, "quality": 0.1}, {"name": "item.fries.e2", "cost": 700.0, "quality": 0.12}]},
	"laban": {"name": "item.laban", "desc": "item.laban.desc", "start": true, "unlock_cost": 0.0, "base_price": 4.0,
		"appeal": 0.5, "kind": "drink", "station_kind": "drink", "model": "food/cup", "recipe": false,
		"ingredients": {"yogurt": 1},
		"enhance": [{"name": "item.laban.e1", "cost": 250.0, "quality": 0.12}]},
	"soda": {"name": "item.soda", "desc": "item.soda.desc", "start": true, "unlock_cost": 0.0, "base_price": 4.0,
		"appeal": 0.5, "kind": "drink", "station_kind": "drink", "model": "food/soda-can", "recipe": false,
		"ingredients": {"drink": 1},
		"enhance": [{"name": "item.soda.e1", "cost": 200.0, "quality": 0.1}]},
	"karak": {"name": "item.karak", "desc": "item.karak.desc", "start": false, "unlock_cost": 150.0, "base_price": 2.0,
		"appeal": 0.55, "kind": "drink", "station_kind": "drink", "model": "food/karak-cup", "recipe": false,
		"ingredients": {"karak": 1},
		"enhance": [{"name": "item.karak.e1", "cost": 250.0, "quality": 0.12}]},
	"saffron_cake": {"name": "item.saffron_cake", "desc": "item.saffron_cake.desc", "start": false, "unlock_cost": 400.0, "base_price": 12.0,
		"appeal": 0.8, "kind": "sweet", "station_kind": "sweet", "model": "food/saffron-cake", "recipe": false, "requires_station": "sweets",
		"ingredients": {"cake": 1},
		"enhance": [{"name": "item.saffron_cake.e1", "cost": 350.0, "quality": 0.1}, {"name": "item.saffron_cake.e2", "cost": 700.0, "quality": 0.12}]},
	"sago_halwa": {"name": "item.sago_halwa", "desc": "item.sago_halwa.desc", "start": false, "unlock_cost": 300.0, "base_price": 8.0,
		"appeal": 0.65, "kind": "sweet", "station_kind": "sweet", "model": "food/sago-halwa", "recipe": false, "requires_station": "sweets",
		"ingredients": {"sago": 1},
		"enhance": [{"name": "item.sago_halwa.e1", "cost": 300.0, "quality": 0.1}, {"name": "item.sago_halwa.e2", "cost": 600.0, "quality": 0.12}]},
	"omani_halwa": {"name": "item.omani_halwa", "desc": "item.omani_halwa.desc", "start": false, "unlock_cost": 500.0, "base_price": 10.0,
		"appeal": 0.75, "kind": "sweet", "station_kind": "sweet", "model": "food/omani-halwa", "recipe": false, "requires_station": "sweets",
		"ingredients": {"halwa": 1},
		"enhance": [{"name": "item.omani_halwa.e1", "cost": 400.0, "quality": 0.1}, {"name": "item.omani_halwa.e2", "cost": 800.0, "quality": 0.12}]},
}

const MENU_GROUPS := [["food", "menu.group.grill"], ["side", "menu.group.side"], ["drink", "menu.group.drink"], ["sweet", "menu.group.sweet"]]

## What you sell from, in order. Index = tier. Stages 0-2 are the mobile "rig" that travels
## with you; from the kiosk up the stage belongs to the location ("plot"). "stations" lists
## every station slot available at that stage (cumulative). "later" = data only for now.
const PLOT_STAGES := [
	{"id": "cart", "name": "plot.cart", "desc": "plot.cart.desc", "cost": 0.0, "scope": "rig", "max_staff": 0,
		"appeal": 1.0, "price_cap_bonus": 0.0, "queue_bonus": 0, "dine_in": 0.0, "level_cap_bonus": 0, "icon": "icons/stand-big",
		"stations": ["counter", "grill", "karak", "coldbox", "signage", "shade", "music"]},
	{"id": "stall", "name": "plot.stall", "desc": "plot.stall.desc", "cost": 2000.0, "scope": "rig", "max_staff": 1,
		"appeal": 1.05, "price_cap_bonus": 0.10, "queue_bonus": 1, "dine_in": 0.0, "level_cap_bonus": 0, "icon": "icons/shade-sail",
		"stations": ["counter", "grill", "karak", "coldbox", "signage", "shade", "music", "doner", "fryer", "lights"]},
	{"id": "truck", "name": "plot.truck", "desc": "plot.truck.desc", "cost": 6000.0, "scope": "rig", "max_staff": 2,
		"appeal": 1.10, "price_cap_bonus": 0.20, "queue_bonus": 2, "dine_in": 0.0, "level_cap_bonus": 0, "icon": "icons/truck-big", "model": "cars/truck",
		"stations": ["counter", "grill", "karak", "coldbox", "signage", "shade", "music", "doner", "fryer", "lights", "sweets"]},
	{"id": "kiosk", "name": "plot.kiosk", "desc": "plot.kiosk.desc", "cost": 25000.0, "scope": "plot", "max_staff": 4,
		"appeal": 1.20, "price_cap_bonus": 0.35, "queue_bonus": 3, "dine_in": 0.25, "level_cap_bonus": 0, "icon": "icons/kiosk",
		"requires_rig": 2, "requires_local_rep": 0.4,
		"stations": ["counter", "grill", "karak", "coldbox", "signage", "shade", "music", "doner", "fryer", "lights", "sweets", "seating", "valet", "juice"]},
	{"id": "restaurant", "name": "plot.restaurant", "desc": "plot.restaurant.desc", "cost": 90000.0, "scope": "plot", "max_staff": 7,
		"appeal": 1.35, "price_cap_bonus": 0.60, "queue_bonus": 4, "dine_in": 0.45, "level_cap_bonus": 0, "icon": "icons/restaurant",
		"requires_rig": 2, "requires_local_rep": 0.55, "branchable": true,
		"stations": ["counter", "grill", "karak", "coldbox", "signage", "shade", "music", "doner", "fryer", "lights", "sweets", "seating", "valet", "juice",
			"majlis", "washroom", "staffroom", "office"]},
	{"id": "flagship", "name": "plot.flagship", "desc": "plot.flagship.desc", "cost": 300000.0, "scope": "plot", "max_staff": 10,
		"appeal": 1.50, "price_cap_bonus": 0.90, "queue_bonus": 5, "dine_in": 0.60, "level_cap_bonus": 5, "icon": "icons/flagship",
		"requires_rig": 2, "requires_local_rep": 0.7, "branchable": true, "unlocks_city": "sharjah",
		"stations": ["counter", "grill", "karak", "coldbox", "signage", "shade", "music", "doner", "fryer", "lights", "sweets", "seating", "valet", "juice",
			"majlis", "washroom", "staffroom", "office"]},
]

const STATION_GROUPS := [["front", "build.group.front"], ["kitchen", "build.group.kitchen"], ["dining", "build.group.dining"], ["extras", "build.group.extras"]]
## Visual tiers: a station looks different from level 1, 4, 7 and 10 (station_tier()).
const STATION_TIERS := [1, 4, 7, 10]

## Stations with levels: cost(level -> level+1) = base * growth^level. Level 0 is the basic
## equipment that comes with the stage ("owned_from": 1 means the station does nothing until
## its first level is bought). "scope": rig stations travel with you, plot stations stay.
const STATIONS := {
	"counter": {"name": "station.counter", "desc": "station.counter.desc", "effect": "station.counter.effect", "group": "front",
		"base": 250.0, "growth": 1.22, "max": 20, "min_stage": 0, "scope": "any", "icon": "icons/stand-big",
		"orders_per_min": 0.5, "per_level": 0.35, "queue_per_level": 1, "roles": ["cashier"]},
	"grill": {"name": "station.grill", "desc": "station.grill.desc", "effect": "station.grill.effect", "group": "kitchen",
		"base": 300.0, "growth": 1.22, "max": 25, "min_stage": 0, "scope": "any", "icon": "icons/grill-double",
		"cooks_per_min": 0.6, "per_level": 0.30, "kinds": ["grill"], "roles": ["cook"]},
	"doner": {"name": "station.doner", "desc": "station.doner.desc", "effect": "station.doner.effect", "group": "kitchen",
		"base": 900.0, "growth": 1.22, "max": 20, "min_stage": 1, "scope": "any", "icon": "food/doner-spit", "owned_from": 1,
		"cooks_per_min": 0.8, "per_level": 0.30, "kinds": ["doner"], "roles": ["cook"], "unlocks_items": ["shawarma"]},
	"fryer": {"name": "station.fryer", "desc": "station.fryer.desc", "effect": "station.fryer.effect", "group": "kitchen",
		"base": 400.0, "growth": 1.22, "max": 15, "min_stage": 1, "scope": "any", "icon": "icons/fryer", "owned_from": 1,
		"cooks_per_min": 1.0, "per_level": 0.30, "kinds": ["fry"], "roles": ["cook"], "unlocks_items": ["fries"]},
	"karak": {"name": "station.karak", "desc": "station.karak.desc", "effect": "station.karak.effect", "group": "kitchen",
		"base": 200.0, "growth": 1.22, "max": 15, "min_stage": 0, "scope": "any", "icon": "icons/karak-station",
		"cooks_per_min": 1.5, "per_level": 0.30, "kinds": ["drink"], "roles": ["barista"]},
	"sweets": {"name": "station.sweets", "desc": "station.sweets.desc", "effect": "station.sweets.effect", "group": "kitchen",
		"base": 2500.0, "growth": 1.25, "max": 10, "min_stage": 2, "scope": "any", "icon": "food/sweets-counter", "owned_from": 1,
		"cooks_per_min": 1.0, "per_level": 0.30, "kinds": ["sweet"], "roles": ["cook"], "unlocks_items": ["saffron_cake", "sago_halwa", "omani_halwa"]},
	"juice": {"name": "station.juice", "desc": "station.juice.desc", "effect": "station.juice.effect", "group": "kitchen",
		"base": 1800.0, "growth": 1.20, "max": 10, "min_stage": 3, "scope": "plot", "icon": "icons/juice-bar", "owned_from": 1, "later": true,
		"cooks_per_min": 1.2, "per_level": 0.30, "kinds": ["juice"], "roles": ["barista"]},
	"coldbox": {"name": "station.coldbox", "desc": "station.coldbox.desc", "effect": "station.coldbox.effect", "group": "kitchen",
		"base": 800.0, "growth": 1.5, "max": 3, "min_stage": 0, "scope": "any", "icon": "icons/fridge",
		"spoil_meat": [0.35, 0.10, 0.10, 0.0], "spoil_veg": [0.20, 0.20, 0.0, 0.0]},
	"signage": {"name": "station.signage", "desc": "station.signage.desc", "effect": "station.signage.effect", "group": "extras",
		"base": 500.0, "growth": 1.25, "max": 15, "min_stage": 0, "scope": "any", "icon": "icons/neon-sign",
		"attract_per_level": 0.04},
	"lights": {"name": "station.lights", "desc": "station.lights.desc", "effect": "station.lights.effect", "group": "extras",
		"base": 600.0, "growth": 1.25, "max": 10, "min_stage": 1, "scope": "any", "icon": "icons/string-lights",
		"evening_traffic_per_level": 0.08, "evening_from": 18.0},
	"music": {"name": "station.music", "desc": "station.music.desc", "effect": "station.music.effect", "group": "extras",
		"base": 650.0, "growth": 1.3, "max": 5, "min_stage": 0, "scope": "any", "icon": "icons/speaker",
		"satisfaction_per_level": 0.02, "attract_per_level": 0.03},
	"shade": {"name": "station.shade", "desc": "station.shade.desc", "effect": "station.shade.effect", "group": "extras",
		"base": 550.0, "growth": 1.25, "max": 8, "min_stage": 0, "scope": "any", "icon": "icons/shade-sail",
		"hot_cut_per_level": 0.10, "storm_cut": 0.5},
	"seating": {"name": "station.seating", "desc": "station.seating.desc", "effect": "station.seating.effect", "group": "dining",
		"base": 1200.0, "growth": 1.22, "max": 25, "min_stage": 3, "scope": "plot", "icon": "icons/table-set", "owned_from": 1,
		"seats_per_level": 2, "dwell_min": 45.0, "clean_min": 5.0, "roles": ["server", "cleaner"]},
	"majlis": {"name": "station.majlis", "desc": "station.majlis.desc", "effect": "station.majlis.effect", "group": "dining",
		"base": 6000.0, "growth": 1.25, "max": 10, "min_stage": 4, "scope": "plot", "icon": "icons/majlis", "owned_from": 1,
		"seats_per_level": 4, "satisfaction_per_level": 0.04, "spend_per_level": 0.03},
	"valet": {"name": "station.valet", "desc": "station.valet.desc", "effect": "station.valet.effect", "group": "front",
		"base": 3000.0, "growth": 1.20, "max": 15, "min_stage": 3, "scope": "plot", "icon": "icons/valet", "owned_from": 1, "later": true,
		"cars_per_hour_per_level": 4.0, "roles": ["host"]},
	"washroom": {"name": "station.washroom", "desc": "station.washroom.desc", "effect": "station.washroom.effect", "group": "dining",
		"base": 4000.0, "growth": 1.30, "max": 5, "min_stage": 4, "scope": "plot", "icon": "icons/mop-bucket", "owned_from": 1, "later": true,
		"satisfaction_per_level": 0.03, "seats_supported_per_level": 12, "roles": ["cleaner"]},
	"staffroom": {"name": "station.staffroom", "desc": "station.staffroom.desc", "effect": "station.staffroom.effect", "group": "extras",
		"base": 5000.0, "growth": 1.30, "max": 5, "min_stage": 4, "scope": "plot", "icon": "icons/helper", "owned_from": 1, "later": true,
		"staff_per_level": 1, "xp_mult_per_level": 0.2},
	"office": {"name": "station.office", "desc": "station.office.desc", "effect": "station.office.effect", "group": "extras",
		"base": 0.0, "growth": 1.0, "max": 1, "min_stage": 4, "scope": "plot", "icon": "icons/helper", "later": true,
		"roles": ["manager"], "virtual": true},
}

## Older saves bought these one-off upgrades and vehicles; load_game() turns them into
## station levels, stages or refunds (see Game._migrate_legacy).
const LEGACY_VEHICLES := {"cart": 0.0, "truck": 2500.0, "truck2": 7000.0}
const LEGACY_UPGRADES := {
	"cart2": {"name": "up.cart2", "cost": 750.0}, "grill2": {"name": "up.grill2", "cost": 1100.0},
	"fridge": {"name": "up.fridge", "cost": 800.0}, "fridge2": {"name": "up.fridge2", "cost": 2100.0},
	"awning": {"name": "up.awning", "cost": 550.0}, "speaker": {"name": "up.speaker", "cost": 650.0},
	"neon": {"name": "up.neon", "cost": 1000.0}, "seating": {"name": "up.seating", "cost": 800.0},
	"helper": {"name": "up.helper", "cost": 300.0}, "sweets": {"name": "up.sweets", "cost": 2500.0},
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

## "min_stage" = the plot stage tier needed to set up there; "competition" = share of customers
## rival stalls take unless you promote; "promo_power" = how much louder promotions are in that
## crowd; "car_access" = how well a valet/parking station works here (customers by car).
const LOCATIONS := {
	"fahidi": {"name": "loc.fahidi", "desc": "loc.fahidi.desc", "rent": 0.0, "traffic": 0.55, "price_tol": 1.0, "quality_care": 0.8,
		"patience": 1.0, "exposure": 1.0, "peaks": [13.0, 19.0], "layout": "fahidi", "unlock_pop": 0.0, "min_stage": 0, "car_access": 0.3},
	"creek": {"name": "loc.creek", "desc": "loc.creek.desc", "rent": 125.0, "traffic": 0.85, "price_tol": 0.85, "quality_care": 0.9,
		"patience": 1.2, "exposure": 1.6, "hot_bonus": 0.2, "peaks": [13.0, 17.0], "layout": "creek", "unlock_pop": 0.0, "min_stage": 0, "car_access": 0.6},
	"metro": {"name": "loc.metro", "desc": "loc.metro.desc", "rent": 200.0, "traffic": 1.05, "price_tol": 0.95, "quality_care": 0.7,
		"patience": 0.6, "exposure": 0.7, "peaks": [9.0, 18.0], "layout": "metro", "unlock_pop": 0.2, "min_stage": 1, "car_access": 0.4},
	"jbr": {"name": "loc.jbr", "desc": "loc.jbr.desc", "rent": 275.0, "traffic": 0.95, "price_tol": 1.1, "quality_care": 0.9,
		"patience": 1.1, "exposure": 1.8, "hot_bonus": 0.8, "peaks": [14.0, 18.0], "layout": "jbr", "unlock_pop": 0.3, "min_stage": 1, "car_access": 0.8},
	"downtown": {"name": "loc.downtown", "desc": "loc.downtown.desc", "rent": 450.0, "traffic": 1.35, "price_tol": 1.3, "quality_care": 1.3,
		"patience": 0.9, "exposure": 0.9, "peaks": [12.5, 19.5], "layout": "downtown", "unlock_pop": 0.45, "min_stage": 2, "car_access": 1.0},
	"mall": {"name": "loc.mall", "desc": "loc.mall.desc", "rent": 600.0, "traffic": 1.45, "price_tol": 1.25, "quality_care": 1.2,
		"patience": 1.0, "exposure": 0.0, "peaks": [13.0, 20.0], "layout": "mall", "unlock_pop": 0.5, "min_stage": 2, "car_access": 1.2,
		"competition": 0.55, "promo_power": 1.8},
	"gv": {"name": "loc.gv", "desc": "loc.gv.desc", "rent": 500.0, "traffic": 1.6, "price_tol": 1.15, "quality_care": 1.1,
		"patience": 1.0, "exposure": 0.8, "peaks": [20.0, 23.0], "layout": "gv", "unlock_pop": 0.6, "min_stage": 2, "hours": [16, 24], "car_access": 1.0,
		"competition": 0.7, "promo_power": 2.0},
}

const STAGES := {
	"dubai": {"name": "stage.dubai", "locations": ["fahidi", "creek", "metro", "jbr", "downtown", "mall", "gv"]},
}

const MARKETING := {
	"fliers": {"name": "mk.fliers", "desc": "mk.fliers.desc", "cost": 150.0, "days": 1, "boost": 0.15, "icon": "icons/fliers"},
	"posters": {"name": "mk.posters", "desc": "mk.posters.desc", "cost": 450.0, "days": 3, "boost": 0.15, "icon": "icons/posters"},
	"social": {"name": "mk.social", "desc": "mk.social.desc", "cost": 750.0, "days": 7, "boost": 0.12, "icon": "icons/social"},
	"radio": {"name": "mk.radio", "desc": "mk.radio.desc", "cost": 1300.0, "days": 5, "boost": 0.30, "icon": "icons/radio"},
}

## The goal ladder: one goal at a time, claimed from the Goals tab. "req" types are evaluated
## by Economy.goal_progress() against Game.goal_snapshot(). "say" = the mentor's line on claim.
const MENTOR := "mentor.saeed"
const GOALS := [
	{"id": "first_30", "req": {"type": "day_served", "n": 30}, "reward": {"money": 150.0}, "say": "goal.first_30.say"},
	{"id": "counter1", "req": {"type": "station_level", "station": "counter", "n": 1}, "reward": {"money": 200.0}, "say": "goal.counter1.say"},
	{"id": "stars15", "req": {"type": "stars", "n": 1.5}, "reward": {"money": 250.0, "popularity": 0.02}, "say": "goal.stars15.say"},
	{"id": "served200", "req": {"type": "total_served", "n": 200}, "reward": {"money": 300.0}, "say": "goal.served200.say"},
	{"id": "creek", "req": {"type": "location", "id": "creek"}, "reward": {"money": 300.0}, "say": "goal.creek.say"},
	{"id": "grill3", "req": {"type": "station_level", "station": "grill", "n": 3}, "reward": {"money": 400.0}, "say": "goal.grill3.say"},
	{"id": "stall", "req": {"type": "stage", "n": 1}, "reward": {"money": 600.0}, "say": "goal.stall.say"},
	{"id": "shawarma", "req": {"type": "item_unlocked", "id": "shawarma"}, "reward": {"money": 500.0}, "say": "goal.shawarma.say"},
	{"id": "profit400", "req": {"type": "day_profit", "n": 400.0}, "reward": {"money": 600.0}, "say": "goal.profit400.say"},
	{"id": "stars25", "req": {"type": "stars", "n": 2.5}, "reward": {"money": 800.0}, "say": "goal.stars25.say"},
	{"id": "truck", "req": {"type": "stage", "n": 2}, "reward": {"money": 1500.0}, "say": "goal.truck.say"},
	{"id": "downtown", "req": {"type": "location_any", "ids": ["downtown", "mall", "gv"]}, "reward": {"money": 1500.0}, "say": "goal.downtown.say"},
	{"id": "levels20", "req": {"type": "levels_owned", "n": 20}, "reward": {"money": 2000.0}, "say": "goal.levels20.say"},
	{"id": "kiosk", "req": {"type": "stage", "n": 3}, "reward": {"money": 5000.0}, "say": "goal.kiosk.say"},
	{"id": "diners50", "req": {"type": "day_dine_in", "n": 50}, "reward": {"money": 4000.0}, "say": "goal.diners50.say"},
	{"id": "served300", "req": {"type": "day_served", "n": 300}, "reward": {"money": 5000.0}, "say": "goal.served300.say"},
	{"id": "levels60", "req": {"type": "levels_owned", "n": 60}, "reward": {"money": 8000.0}, "say": "goal.levels60.say"},
	{"id": "stars45", "req": {"type": "stars", "n": 4.5}, "reward": {"money": 10000.0}, "say": "goal.stars45.say"},
]

## Thought-bubble keys per mood; the number of lines per mood is in BUBBLE_COUNT.
const BUBBLE_COUNT := {"great": 5, "ok": 4, "bad_quality": 4, "too_pricey": 3, "too_slow": 3, "queue_full": 2,
	"sold_out": 3, "hot": 2, "sandstorm": 2, "breeze": 2, "rival": 3, "sweet": 2, "dine_in": 2}

## 0 = not owned, then 1..4 as the level crosses STATION_TIERS (visual tiers).
static func station_tier(level: int) -> int:
	var t := 0
	for threshold in STATION_TIERS:
		if level >= int(threshold):
			t += 1
	return t

static func stage_def(tier: int) -> Dictionary:
	return PLOT_STAGES[clampi(tier, 0, PLOT_STAGES.size() - 1)]

static func stage_tier_of(id: String) -> int:
	for i in range(PLOT_STAGES.size()):
		if PLOT_STAGES[i]["id"] == id:
			return i
	return 0

## Reference unit price = the cheapest bulk price (used for unit cost estimates).
static func reference_unit_price(ingredient: String) -> float:
	var packs: Array = INGREDIENTS[ingredient]["packs"]
	var best := INF
	for p in packs:
		best = minf(best, float(p[1]) / float(p[0]))
	return best

## Highest price multiple of the base price allowed at a location (see PRICE_CAP_BASE).
static func price_cap_mult(loc: Dictionary, stage: Dictionary = {}) -> float:
	var cap := PRICE_CAP_BASE + PRICE_CAP_PER_RENT * float(loc.get("rent", 0.0))
	if loc.has("price_cap"):
		cap = float(loc["price_cap"])
	return cap + float(stage.get("price_cap_bonus", 0.0))

static func location_hours(location_id: String) -> Array:
	var loc: Dictionary = LOCATIONS[location_id]
	if loc.has("hours"):
		return loc["hours"]
	return [DAY_START_HOUR, DAY_END_HOUR]

static func pick_bubble(key: String, rng: RandomNumberGenerator) -> String:
	var n := int(BUBBLE_COUNT.get(key, 1))
	return TranslationServer.translate("bubble.%s.%d" % [key, rng.randi_range(1, n)])

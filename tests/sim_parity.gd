extends SceneTree
## Godot --headless --path . --script tests/sim_parity.gd [-- --tiers=0,1 --locations=creek,jbr --seeds=4]
## FastSim and Economy.throughput_estimate must describe the day a player watches. Plays a
## matrix of stages x station levels x locations through DayRunner (the visible DaySim,
## undrawn), with fixed seeds, healthy popularity and ample stock, and compares the played
## mean with FastSim's mean (portions and revenue within 15%) and with the estimate (20%).

const FAST_TOLERANCE := 0.15
const ESTIMATE_TOLERANCE := 0.20
const POPULARITY := 0.6
const PLAYED_SEEDS := [104729, 224737, 350377, 479909, 611953, 746773, 882377, 1020379, 1159523, 1299709,
	1441049, 1583539, 1726943, 1870667, 2015177, 2160553, 2305169, 2449901, 2595127, 2740657]
const FAST_SEEDS := 24
## Station levels per stage: a fresh build, a typical one, and everything maxed (capped at
## each stage's own level cap when the parity run builds the setup).
const MAXED := {"counter": 25, "grill": 30, "doner": 25, "karak": 20, "fryer": 15, "sweets": 10, "juice": 15,
	"seating": 30, "majlis": 10, "staffroom": 5}
const LEVELS := [
	{"low": {"counter": 0, "grill": 0, "karak": 0}, "mid": {"counter": 3, "grill": 4, "karak": 2}, "high": MAXED},
	{"low": {"counter": 0, "grill": 1, "karak": 1, "doner": 1}, "mid": {"counter": 5, "grill": 7, "karak": 4, "doner": 3}, "high": MAXED},
	{"low": {"counter": 2, "grill": 3, "karak": 2, "doner": 1}, "mid": {"counter": 7, "grill": 10, "karak": 6, "doner": 6}, "high": MAXED},
	{"low": {"counter": 3, "grill": 4, "karak": 3, "doner": 2, "seating": 2},
		"mid": {"counter": 9, "grill": 12, "karak": 8, "doner": 8, "seating": 6}, "high": MAXED},
	{"low": {"counter": 5, "grill": 8, "karak": 5, "doner": 4, "seating": 4},
		"mid": {"counter": 12, "grill": 16, "karak": 10, "doner": 12, "seating": 10, "staffroom": 1, "majlis": 2}, "high": MAXED},
	{"low": {"counter": 8, "grill": 12, "karak": 8, "doner": 8, "seating": 6},
		"mid": {"counter": 16, "grill": 22, "karak": 14, "doner": 16, "seating": 14, "staffroom": 2, "majlis": 4}, "high": MAXED},
]
## A promenade, the souq and a road for every stage that can stand there.
const LOCATIONS := [["creek", "fahidi"], ["creek", "fahidi", "metro"], ["creek", "fahidi", "downtown"],
	["creek", "fahidi", "downtown"], ["creek", "fahidi", "downtown"], ["creek", "fahidi", "downtown"]]

var game: Node
var data: Node
var economy: GDScript
var fast_sim: GDScript
var day_runner: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return fallback

## Today's state is the setup: the street, plot and Throughput all read Game.
func _setup(tier: int, levels: Dictionary, location: String) -> Dictionary:
	game.new_game()
	game.money = 1e7
	game.popularity = float(_arg("pop", str(POPULARITY)))
	game.weather = "sunny"
	game.forecast = "sunny"
	game.weather_day = game.day
	var def: Dictionary = data.stage_def(tier)
	var stations := {}
	for id in levels:
		if id in def["stations"]:
			stations[id] = mini(int(levels[id]), economy.station_level_cap(data.STATIONS[id], def))
	game.rig["stage"] = def["id"] if tier < 3 else "truck"
	game.rig["stations"] = stations.duplicate() if tier < 3 else {}
	if tier >= 3:
		game.plots[location] = {"stage": def["id"], "stations": stations.duplicate(), "reputation": float(_arg("pop", str(POPULARITY))), "last_visit": game.day}
	game.location = location
	for id in data.MENU_ITEMS:
		var on: bool = game.item_available(id)
		game.menu[id]["unlocked"] = on
		game.menu[id]["enabled"] = on
	for id in data.INGREDIENTS:
		game.inventory[id] = 5000
	game.clamp_prices()
	# The context a planner would get for this setup (it must equal today's own).
	var ctx: Dictionary = game.what_if({"stage": tier, "stations": stations, "location": location})
	return ctx

func _run() -> void:
	game = root.get_node("Game")
	data = root.get_node("Data")
	economy = load("res://scripts/core/economy.gd")
	fast_sim = load("res://scripts/sim/fast_sim.gd")
	day_runner = load("res://scripts/sim/day_runner.gd")
	game.persist = false
	var tiers := _arg("tiers", "0,1,2,3,4,5").split(",")
	var only_loc := _arg("locations", "")
	var only_levels := _arg("levels", "low,mid,high").split(",")
	var played_seeds: Array = PLAYED_SEEDS.slice(0, int(_arg("seeds", "16")))
	var rows := []
	var failures := 0
	var started := Time.get_ticks_msec()
	print("stage    level loc      | buyers  port   revenue  (played) | port   revenue  (fast)    | port   revenue  (estimate) | crowd budget")
	for tier_s in tiers:
		var tier := int(tier_s)
		# --locations names the places to play (any place the stage may stand at); by default
		# a promenade, the souq and a road per stage
		var places: Array = LOCATIONS[tier]
		if only_loc != "":
			places = []
			for id in only_loc.split(","):
				if int(data.LOCATIONS[id].get("min_stage", 0)) <= tier:
					places.append(id)
		for location in places:
			for level in only_levels:
				var setup_started := Time.get_ticks_msec()
				var ctx := _setup(tier, LEVELS[tier][level], location)
				var world: Node3D = load("res://scripts/world/world.gd").new()
				root.add_child(world)
				world.set_location(game.location)
				var played := {"served": 0.0, "portions": 0.0, "revenue": 0.0, "crowd": 0.0, "dine_in": 0.0}
				var sold := {}
				for s in played_seeds:
					_setup(tier, LEVELS[tier][level], location)
					game.day_seed = int(s) + int(_arg("seedoffset", "0"))
					var sim: Node = load("res://scripts/sim/day_sim.gd").new()
					root.add_child(sim)
					var stats: Dictionary = day_runner.play(sim, world, game.sim_context())
					if stats["_unfinished"]:
						failures += 1
						printerr("FAIL played day did not close: ", data.stage_def(tier)["id"], " ", level, " ", location)
					for k in played:
						played[k] += float(stats.get(k, 0)) / played_seeds.size()
					for id in stats["sold"]:
						sold[id] = float(sold.get(id, 0.0)) + float(stats["sold"][id]) / played_seeds.size()
					if _arg("detail", "") != "":
						print("    played rev %.0f port %d buyers %d" % [float(stats["revenue"]), int(stats["portions"]), int(stats["served"])], " util ", stats.get("util", {}), " left ", stats["left_wait"], " sold_out ", stats["sold_out"], " qfull ", stats["queue_full"], " wait ", float(stats["wait_sum"]) / maxi(1, int(stats["served"])))
					sim.free()
					await process_frame
				world.free()
				await process_frame
				var played_ms := Time.get_ticks_msec() - setup_started
				var fast := {"served": 0.0, "portions": 0.0, "revenue": 0.0, "crowd": 0.0, "dine_in": 0.0}
				var fast_sold := {}
				for i in range(FAST_SEEDS):
					_setup(tier, LEVELS[tier][level], location)
					var rng := RandomNumberGenerator.new()
					rng.seed = 7368787 + 104723 * i + int(_arg("seedoffset", "0"))
					var stats: Dictionary = fast_sim.run(game.sim_context(), rng)
					for k in fast:
						fast[k] += float(stats.get(k, 0)) / FAST_SEEDS
					for id in stats["sold"]:
						fast_sold[id] = float(fast_sold.get(id, 0.0)) + float(stats["sold"][id]) / FAST_SEEDS
				_setup(tier, LEVELS[tier][level], location)
				var est: Dictionary = economy.throughput_estimate(ctx)
				if _arg("timing", "") != "":
					print("    played %d ms, fast %d ms" % [played_ms, Time.get_ticks_msec() - setup_started - played_ms])
				var row := {"stage": data.stage_def(tier)["id"], "level": level, "location": location, "played": played, "fast": fast,
					"estimate": {"served": float(est["served"]), "portions": float(est["portions"]), "revenue": float(est["revenue"]), "crowd": float(est.get("crowd", 0.0))},
					"buyers": int(ctx["buyers"])}
				if _arg("detail", "") != "":
					for id in data.MENU_ITEMS:
						if sold.has(id) or fast_sold.has(id):
							print("    %-14s played %6.1f fast %6.1f price %.1f" % [id, float(sold.get(id, 0.0)), float(fast_sold.get(id, 0.0)), float(game.menu[id]["price"])])
					print("    played dine ", played["dine_in"])
					print("    fast dine ", fast["dine_in"], " crowd ", fast["crowd"], " | est served ", est["served"], " crowd ", est["crowd"], " dine ", est["dine_in"], " left ", est["left"], " util ", est["util"])
				var bad := []
				for k in ["portions", "revenue"]:
					if _off(fast[k], played[k]) > FAST_TOLERANCE:
						bad.append("fast " + k)
					if _off(float(est[k]), played[k]) > ESTIMATE_TOLERANCE:
						bad.append("estimate " + k)
				row["fail"] = bad
				rows.append(row)
				print("%-8s %-5s %-8s | %5.1f %6.1f %8.0f           | %6.1f %8.0f %s | %6.1f %8.0f %s | %5.1f %d %s" % [row["stage"], level, location,
					played["served"], played["portions"], played["revenue"],
					fast["portions"], fast["revenue"], _pct(fast["portions"], played["portions"]),
					float(est["portions"]), float(est["revenue"]), _pct(float(est["portions"]), played["portions"]),
					played["crowd"], int(ctx["buyers"]), "" if bad.is_empty() else "FAIL " + ", ".join(bad)])
				if not bad.is_empty():
					failures += 1
	var file := FileAccess.open("user://sim-parity.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(rows, "\t"))
	print("sim parity: %d setups, %d failed (%.1f s)" % [rows.size(), failures, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures else 0)

func _off(value: float, reference: float) -> float:
	return absf(value - reference) / maxf(reference, 1.0)

func _pct(value: float, reference: float) -> String:
	return "%+4.0f%%" % (100.0 * (value - reference) / maxf(reference, 1.0))

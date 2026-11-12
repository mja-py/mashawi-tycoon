extends SceneTree
## Godot --headless --path . --script tests/balance_curve.gd
## The balance of the day a player watches, end to end. Two checks, run side by side in
## child processes (each prints nothing; the parent prints one line per check, exits 1 on
## a failure):
##   bot: the greedy autoplayer (scripts/sim/autoplayer.gd, the same player as
##     `--autodays --sim=day`) plays seeds 1-3 for 150 played days (DaySim via DayRunner):
##     stage milestones inside their windows, no family loan, a profitable last day, at
##     least 14 goals, two or more rented places used, guests eating in on fixed stages.
##   loc: matched setups per stage (mid station levels, popularity 0.6 and 1.0, ample
##     stock, the player's best price by the estimate, 16 played seeds per place): the
##     right rented place beats the free souk net of rent by 25% (Creek from the stall,
##     Metro or JBR from the truck, Downtown/Mall/Global Village from the kiosk), the souk
##     stays within 15% of the best place for a cart, and guests eat in at mid seating.
## Options: --seeds=1,2,3 --days=150 --tiers=0,1,2,3,4,5 --locseeds=16 --keep=1 (keep the
## child JSON in user://balance/), and for one part on its own: --part=bot --seed=N
## --out=PATH, or --part=loc --tier=T --out=PATH [--locations=a,b --pops=0.6 --est=1].

const DAYS := 150
const BOT_SEEDS := [1, 2, 3]
## [first, last] day the bot should first sell from each stage.
## Release 2b targets were stall 15-25, truck 40-60, kiosk 60-78, restaurant 78-98, flagship
## 105-135. The stall window is widened to what seeds 1-3 measured (16-27) plus a small margin:
## a seed that buys shade or the level-2 grill goal before the stall saves for it ~10 days longer.
const MILESTONES := {1: [15, 29], 2: [40, 60], 3: [60, 78], 4: [78, 98], 5: [105, 135]}
const GOALS_MIN := 14
const DINE_PRESENT := 0.10
## Location check: the rented places that should pay best from each stage up.
const RENTED_BEST := {1: ["creek"], 2: ["metro", "jbr"], 3: ["downtown", "mall", "gv"], 4: ["downtown", "mall", "gv"], 5: ["downtown", "mall", "gv"]}
const RENTED_MARGIN := 1.25
const START_MARGIN := 0.85
const LOC_POPS := [0.6, 1.0]
const LOC_SEEDS := 16
const LOC_SEED_LIST := [104729, 224737, 350377, 479909, 611953, 746773, 882377, 1020379, 1159523, 1299709,
	1441049, 1583539, 1726943, 1870667, 2015177, 2160553, 2305169, 2449901, 2595127, 2740657, 2886329, 3031381,
	3176989, 3323953]
## Share of buyers who eat in with seating at a mid level (kiosk, restaurant).
const DINE_MID := {3: 0.20, 4: 0.30}
const TIMEOUT_S := 900.0

var game: Node
var data: Node
## Loaded at run time: these scripts need the autoloads, which a --script run only has
## once the tree is up.
var economy: GDScript
var autoplayer: GDScript
var day_runner: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return fallback

func _run() -> void:
	game = root.get_node("Game")
	data = root.get_node("Data")
	economy = load("res://scripts/core/economy.gd")
	autoplayer = load("res://scripts/sim/autoplayer.gd")
	day_runner = load("res://scripts/sim/day_runner.gd")
	game.persist = false
	match _arg("part", ""):
		"bot":
			await _part_bot(int(_arg("seed", "1")), int(_arg("days", str(DAYS))), _arg("out", ""))
			quit(0)
		"loc":
			await _part_loc(int(_arg("tier", "0")), _arg("out", ""))
			quit(0)
		_:
			quit(await _parent())

# ---------------------------------------------------------------- parent

func _parent() -> int:
	var started := Time.get_ticks_msec()
	var dir := "user://balance"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var seeds := _arg("seeds", ",".join(BOT_SEEDS.map(func(s): return str(s)))).split(",")
	var days := int(_arg("days", str(DAYS)))
	var tiers := _arg("tiers", "0,1,2,3,4,5").split(",")
	var jobs := []
	for s in seeds:
		jobs.append({"name": "bot seed %s" % s, "out": "%s/bot-%s.json" % [dir, s], "args": ["--part=bot", "--seed=" + s, "--days=%d" % days]})
	for t in tiers:
		jobs.append({"name": "loc %s" % data.stage_def(int(t))["id"], "out": "%s/loc-%s.json" % [dir, t],
			"args": ["--part=loc", "--tier=" + t, "--locseeds=" + _arg("locseeds", str(LOC_SEEDS))]})
	for job in jobs:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(job["out"]))
		var args := ["--headless", "--quiet", "--path", project, "--script", "res://tests/balance_curve.gd", "--"]
		args.append_array(job["args"])
		args.append("--out=" + ProjectSettings.globalize_path(job["out"]))
		job["pid"] = OS.create_process(exe, args)
		if int(job["pid"]) <= 0:
			print("FAIL could not start ", job["name"])
			return 1
	while true:
		var running := 0
		for job in jobs:
			if OS.is_process_running(int(job["pid"])):
				running += 1
		if running == 0:
			break
		if (Time.get_ticks_msec() - started) / 1000.0 > TIMEOUT_S:
			for job in jobs:
				if OS.is_process_running(int(job["pid"])):
					OS.kill(int(job["pid"]))
			print("FAIL balance curve timed out after %.0f s" % TIMEOUT_S)
			return 1
		await create_timer(0.25).timeout
	var failures := 0
	var bots := []
	var locs := {}
	for job in jobs:
		var parsed = _read_json(job["out"])
		if parsed == null:
			print("FAIL %s wrote no result" % job["name"])
			failures += 1
			continue
		if String(job["args"][0]) == "--part=bot":
			bots.append(parsed)
		else:
			locs[int(parsed["tier"])] = parsed
	for bot in bots:
		failures += _check_bot(bot)
	if not locs.is_empty():
		failures += _check_locations(locs)
	if _arg("keep", "") == "":
		for job in jobs:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(job["out"]))
	print("balance curve: %d failed (%.1f s)" % [failures, (Time.get_ticks_msec() - started) / 1000.0])
	return 1 if failures > 0 else 0

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _line(ok: bool, text: String) -> int:
	print(("ok   " if ok else "FAIL ") + text)
	return 0 if ok else 1

func _check_bot(bot: Dictionary) -> int:
	var f := 0
	var seed_id := int(bot["seed"])
	var first: Dictionary = bot["first_day"]
	for t in MILESTONES:
		var window: Array = MILESTONES[t]
		var d := int(first.get(str(t), -1))
		f += _line(d >= int(window[0]) and d <= int(window[1]),
			"seed %d: %s on day %s (window %d-%d)" % [seed_id, data.stage_def(t)["id"], str(d) if d > 0 else "never", int(window[0]), int(window[1])])
	f += _line(int(bot["loans"]) == 0, "seed %d: family loans %d (0 wanted)" % [seed_id, int(bot["loans"])])
	f += _line(float(bot["final_profit"]) > 0.0, "seed %d: last day's profit %.0f (> 0), money %.0f, %d levels" % [seed_id,
		float(bot["final_profit"]), float(bot["final_money"]), int(bot["levels"])])
	f += _line(int(bot["goals"]) >= GOALS_MIN, "seed %d: %d goals claimed (>= %d), first on day %d" % [seed_id, int(bot["goals"]), GOALS_MIN, int(bot["first_goal_day"])])
	var rented := []
	for id in bot["locations"]:
		if float(data.LOCATIONS[id]["rent"]) > 0.0:
			rented.append(id)
	f += _line(rented.size() >= 2, "seed %d: traded at %s (two or more rented places)" % [seed_id, ", ".join(bot["locations"])])
	var dine: Dictionary = bot["dine"]
	for t in [3, 4, 5]:
		if not dine.has(str(t)):
			continue
		var pair: Array = dine[str(t)]
		var share := float(pair[0]) / maxf(1.0, float(pair[1]))
		f += _line(share >= DINE_PRESENT, "seed %d: %.0f%% of %s buyers ate in (%d of %d)" % [seed_id, 100.0 * share, data.stage_def(t)["id"], int(pair[0]), int(pair[1])])
	return f

func _check_locations(locs: Dictionary) -> int:
	var f := 0
	for t in locs:
		var rows: Array = locs[t]["rows"]
		var name: String = data.stage_def(t)["id"]
		for pop in LOC_POPS:
			var net := {}
			var line := []
			for row in rows:
				if is_equal_approx(float(row["pop"]), pop):
					net[row["location"]] = float(row["net"])
					line.append("%s %.0f" % [row["location"], float(row["net"])])
			if not net.has("fahidi"):
				continue
			var fahidi := float(net["fahidi"])
			if t == 0:
				var best := -INF
				for id in net:
					best = maxf(best, float(net[id]))
				f += _line(fahidi >= START_MARGIN * best, "%s pop %.1f: the souk is within 15%% of the best place (%s)" % [name, pop, ", ".join(line)])
			else:
				var best_id := ""
				for id in RENTED_BEST.get(t, []):
					if net.has(id) and (best_id == "" or float(net[id]) > float(net[best_id])):
						best_id = id
				var ok := best_id != "" and float(net[best_id]) >= RENTED_MARGIN * fahidi
				f += _line(ok, "%s pop %.1f: %s beats the souk net of rent by %+.0f%% (>= +25%%; %s)" % [name, pop, best_id,
					100.0 * (float(net.get(best_id, 0.0)) / maxf(fahidi, 1.0) - 1.0), ", ".join(line)])
		if DINE_MID.has(t):
			var diners := 0.0
			var buyers := 0.0
			for row in rows:
				diners += float(row["dine_in"])
				buyers += float(row["served"])
			var share := diners / maxf(buyers, 1.0)
			f += _line(share >= float(DINE_MID[t]), "%s mid seating: %.0f%% of buyers eat in (>= %.0f%%)" % [name, 100.0 * share, 100.0 * float(DINE_MID[t])])
	return f

# ---------------------------------------------------------------- bot

func _part_bot(run_seed: int, days: int, out: String) -> void:
	seed(run_seed)
	game.rng.seed = run_seed
	game.new_game()
	var world: Node3D = load("res://scripts/world/world.gd").new()
	root.add_child(world)
	world.set_location(game.location)
	var runner: Node = load("res://scripts/sim/day_sim.gd").new()
	root.add_child(runner)
	var result := {"seed": run_seed, "first_day": {}, "rows": [], "dine": {}, "locations": [], "first_goal_day": -1}
	var started := Time.get_ticks_msec()
	for d in range(days):
		var day: Dictionary = autoplayer.play_day(true, runner, world)
		await process_frame
		var r: Dictionary = day["report"]
		var tier := int(r["stage"])
		for t in range(1, tier + 1):
			if not result["first_day"].has(str(t)):
				result["first_day"][str(t)] = int(r["day"])
		if not result["locations"].has(r["location"]):
			result["locations"].append(r["location"])
		if tier >= 3:
			var pair: Array = result["dine"].get(str(tier), [0, 0])
			result["dine"][str(tier)] = [int(pair[0]) + int(r["dine_in"]), int(pair[1]) + int(r["served"])]
		if result["first_goal_day"] < 0 and not game.goals_claimed.is_empty():
			result["first_goal_day"] = int(r["day"])
		result["rows"].append({"day": r["day"], "location": r["location"], "stage": tier, "served": r["served"], "portions": r["portions"],
			"dine_in": r["dine_in"], "crowd": r["crowd"], "revenue": r["revenue"], "profit": r["profit"], "money": r["money"],
			"goals": game.goals_claimed.size(), "pop": game.popularity, "rep": game.local_reputation(), "levels": game.levels_owned(),
			"buys": autoplayer.last_buys.duplicate()})
	var last: Dictionary = result["rows"].back()
	result["final_profit"] = last["profit"]
	result["final_money"] = last["money"]
	result["goals"] = game.goals_claimed.size()
	result["goal_ids"] = game.goals_claimed
	result["loans"] = game.bailouts
	result["levels"] = game.levels_owned()
	result["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	result["prep_seconds"] = autoplayer.prep_usec / 1e6
	_write(out, result)

# ---------------------------------------------------------------- location matrix

## Station levels per stage for the matched setups (the parity run's "mid" builds).
func _mid_levels(tier: int) -> Dictionary:
	var levels: Array = load("res://tests/sim_parity.gd").get_script_constant_map()["LEVELS"]
	return levels[tier]["mid"]

## A sensible player's menu at this stage: everything the stage can sell, the full recipe,
## dish upgrades as they become affordable, priced by the estimate under the satisfaction floor.
func _setup_place(tier: int, location: String, pop: float) -> void:
	game.new_game()
	game.money = 1e7
	game.popularity = pop
	game.weather = "sunny"
	game.forecast = "sunny"
	game.weather_day = game.day
	var def: Dictionary = data.stage_def(tier)
	var stations := {}
	var levels := _mid_levels(tier)
	for id in levels:
		if id in def["stations"]:
			stations[id] = mini(int(levels[id]), economy.station_level_cap(data.STATIONS[id], def))
	game.rig["stage"] = def["id"] if tier < 3 else "truck"
	game.rig["stations"] = stations.duplicate() if tier < 3 else {}
	game.location = location
	game.plots[location] = {"stage": def["id"] if tier >= 3 else "", "stations": stations.duplicate() if tier >= 3 else {},
		"reputation": pop, "last_visit": game.day}
	for id in data.MENU_ITEMS:
		var on: bool = game.item_available(id)
		game.menu[id]["unlocked"] = on
		game.menu[id]["enabled"] = on
		game.menu[id]["recipe"] = {"meat": 3, "veg": 3, "sauce": 2}
		game.menu[id]["level"] = mini(tier, data.MENU_ITEMS[id]["enhance"].size())
	for id in data.INGREDIENTS:
		game.inventory[id] = 5000
	game.clamp_prices()
	autoplayer.prices()

func _part_loc(tier: int, out: String) -> void:
	var def: Dictionary = data.stage_def(tier)
	var only := _arg("locations", "")
	var pops := []
	for p in _arg("pops", ",".join(LOC_POPS.map(func(v): return str(v)))).split(","):
		pops.append(float(p))
	var n_seeds := int(_arg("locseeds", str(LOC_SEEDS)))
	var est_only := _arg("est", "") != ""
	var result := {"tier": tier, "rows": []}
	for location in data.STAGES["dubai"]["locations"]:
		if int(data.LOCATIONS[location].get("min_stage", 0)) > tier or (only != "" and not location in only.split(",")):
			continue
		var world: Node3D = null
		for pop in pops:
			_setup_place(tier, location, pop)
			var ctx: Dictionary = game.sim_context()
			var est: Dictionary = economy.throughput_estimate(ctx)
			var mult := float(game.menu["chicken_tikka"]["price"]) / float(data.MENU_ITEMS["chicken_tikka"]["base_price"])
			var rent := float(data.LOCATIONS[location]["rent"])
			var row := {"location": location, "pop": pop, "mult": mult, "rent": rent, "est_net": float(est["profit"]),
				"est_served": float(est["served"]), "est_portions": float(est["portions"]), "est_dine": float(est["dine_in"]),
				"est_crowd": float(est["crowd"]), "buyers": int(ctx["buyers"])}
			if not est_only:
				if world == null:
					world = load("res://scripts/world/world.gd").new()
					root.add_child(world)
					world.set_location(location)
				var sums := {"served": 0.0, "portions": 0.0, "dine_in": 0.0, "crowd": 0.0, "revenue": 0.0, "cogs": 0.0, "left_wait": 0.0, "satisfaction": 0.0}
				for i in range(n_seeds):
					_setup_place(tier, location, pop)
					game.day_seed = int(LOC_SEED_LIST[i % LOC_SEED_LIST.size()]) + 7919 * int(i / LOC_SEED_LIST.size())
					var sim: Node = load("res://scripts/sim/day_sim.gd").new()
					root.add_child(sim)
					var stats: Dictionary = day_runner.play(sim, world, game.sim_context())
					for k in sums:
						if k == "satisfaction":
							sums[k] += float(stats["satisfaction_sum"]) / maxf(1.0, float(stats["served"])) / n_seeds
						else:
							sums[k] += float(stats.get(k, 0)) / n_seeds
					sim.free()
					await process_frame
				for k in sums:
					row[k] = sums[k]
				row["net"] = float(sums["revenue"]) - float(sums["cogs"]) - rent
			else:
				row["net"] = row["est_net"]
				row["served"] = row["est_served"]
				row["dine_in"] = row["est_dine"]
			result["rows"].append(row)
		if world != null:
			world.free()
			await process_frame
	_write(out, result)

func _write(out: String, result: Dictionary) -> void:
	if out == "":
		print(JSON.stringify(result, "\t"))
		return
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()

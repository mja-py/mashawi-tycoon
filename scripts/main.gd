extends Node
## Phase orchestration: Title -> Prep -> Day -> Report -> Prep ...

enum Phase { TITLE, PREP, DAY, REPORT }

var world: World
var sim: DaySim
var hud: Node
var phase: Phase = Phase.TITLE
var speed := 1.0
var _quality_time := 0.0
var _quality_frames := 0
var _quality_warmup := 4.0
var _web_visibility_callback: JavaScriptObject

func _ready() -> void:
	world = World.new()
	add_child(world)
	sim = DaySim.new()
	add_child(sim)
	sim.finished.connect(_on_day_finished)
	var hud_script := load("res://scripts/ui/hud.gd")
	if hud_script:
		hud = hud_script.new()
		hud.main = self
		add_child(hud)
	Game.changed.connect(_on_game_changed)
	_apply_dev_flags()
	if OS.has_feature("web"):
		_apply_web_quality()
		_web_visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility)
		JavaScriptBridge.get_interface("window").godotSetPaused = _web_visibility_callback
		JavaScriptBridge.eval("if (window.godotSyncVisibility) window.godotSyncVisibility()")
		# tells the HTML shell to drop its loading overlay
		JavaScriptBridge.eval("window.dispatchEvent(new Event('godot-ready'))")

func _on_web_visibility(args: Array) -> void:
	# A phone call, app switch or portrait rotate guard must not spend the day
	# while the player cannot see or control the stand.
	if not args.is_empty():
		get_tree().paused = bool(args[0])
		_publish_state()

## Sustained slow frames lower only the 3D resolution; menus/text stay crisp.
## Use real frame time: the player's simulation speed must not change this decision.
func _process(_delta: float) -> void:
	if not OS.has_feature("web") or DevTools.has("scale3d"):
		return
	var dt := get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	if _quality_warmup > 0.0:
		_quality_warmup -= dt
		return
	# Ignore tab suspension and one-off long frames from opening a menu.
	if dt > 0.2:
		_quality_time = 0.0
		_quality_frames = 0
		return
	_quality_time += dt
	_quality_frames += 1
	if _quality_time < 3.0:
		return
	var fps := _quality_frames / _quality_time
	var vp := get_viewport()
	if fps < 42.0:
		vp.scaling_3d_scale = maxf(0.6, vp.scaling_3d_scale - 0.05)
	_quality_time = 0.0
	_quality_frames = 0

## WebGL starts at 75-100% resolution, then can step down to 60% on slow devices.
## The UI stays at full resolution. `?dev=--scale3d=1` disables adaptation for comparisons.
func _apply_web_quality() -> void:
	if DevTools.has("scale3d"):
		return
	var dpr := float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(1.6 / maxf(dpr, 1.0), 0.75, 1.0)

func _apply_dev_flags() -> void:
	if DevTools.has("location"):
		Game.location = DevTools.get_flag("location")
	if DevTools.has("weather"):
		Game.weather = DevTools.get_flag("weather")
		Game.forecast = Game.weather
	if DevTools.has("money"):
		Game.money = float(DevTools.get_flag("money"))
	if DevTools.has("lang"):
		Loc.lang = DevTools.get_flag("lang")
		TranslationServer.set_locale(Loc.lang)
		Loc.language_changed.emit()
	if DevTools.has("stage"):
		# --stage=3 forces a plot stage for screenshots (rig for 0-2, this location's plot above)
		var t := int(DevTools.get_flag("stage"))
		if t < Game.FIXED_FROM_TIER:
			Game.rig["stage"] = Data.stage_def(t)["id"]
		else:
			Game.rig["stage"] = "truck"
			Game.plot()["stage"] = Data.stage_def(t)["id"]
	if DevTools.has("scale3d"):
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = float(DevTools.get_flag("scale3d"))
	if DevTools.has("stations"):
		# --stations=grill:4,seating:7 sets station levels for screenshots
		for pair in DevTools.get_flag("stations").split(","):
			var kv := pair.split(":")
			if kv.size() == 2 and Data.STATIONS.has(kv[0]):
				Game._station_store()[kv[0]] = int(kv[1])
	if DevTools.has("autodays"):
		Game.persist = false
		_autoplay(int(DevTools.get_flag("autodays")))
		return
	if DevTools.has("gallery"):
		_gallery(DevTools.get_flag("gallery"))
		if DevTools.has("screenshot"):
			await get_tree().create_timer(2.0, true, false, true).timeout
			await DevTools.screenshot(DevTools.get_flag("screenshot"))
			get_tree().quit()
		return
	if DevTools.has("checkscripts"):
		_check_scripts()
		return
	if DevTools.has("tests"):
		Game.save_path = "user://save_test.json"
		add_child(load("res://tests/run_tests.gd").new())
		return
	world.set_location(Game.location)
	if DevTools.has("screenshot"):
		Game.persist = false # screenshot runs never overwrite the player's save
	var ph := DevTools.get_flag("phase", "title")
	match ph:
		"day":
			_stock_up_for_test()
			start_day(true)
			if DevTools.has("speed"):
				set_speed(float(DevTools.get_flag("speed")))
		"prep":
			show_prep()
			if DevTools.has("panel") and hud:
				_stock_up_for_test()
				hud.open_panel(DevTools.get_flag("panel"))
		"report":
			_stock_up_for_test()
			start_day(true)
			set_speed(16.0)
		_:
			show_title()
	if DevTools.has("screenshot"):
		var delay := float(DevTools.get_flag("delay", "2.0"))
		await get_tree().create_timer(delay, true, false, true).timeout
		await DevTools.screenshot(DevTools.get_flag("screenshot"))
		get_tree().quit()

func _stock_up_for_test() -> void:
	for ing in Data.INGREDIENTS:
		Game.inventory[ing] = 60
	if DevTools.has("speed"):
		set_speed(float(DevTools.get_flag("speed")))

func _on_game_changed() -> void:
	if world.cart:
		if hud and phase == Phase.PREP and world.visual_needs_reload():
			hud.fade_through(world.apply_visual)
		else:
			world.apply_visual()
	if phase == Phase.PREP:
		Game.save()
		_publish_state()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			# Android backgrounding / desktop close: keep the prep-phase state.
			if phase == Phase.PREP or phase == Phase.REPORT:
				Game.save()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Android back: close an open panel, otherwise leave the app only from the title.
			if hud and hud.current_panel != "":
				hud.close_panel()
			elif phase == Phase.TITLE:
				get_tree().quit()
			elif phase == Phase.PREP:
				Game.save()
				show_title()

# ---------------------------------------------------------------- phases

## Web: mirror the phase and save state to the page (window.godotState) so browser tests
## can check them without reading pixels.
func _publish_state() -> void:
	if not OS.has_feature("web"):
		return
	var names := ["title", "prep", "day", "report"]
	JavaScriptBridge.eval("window.godotState = {phase: '%s', hasSave: %s, day: %d, money: %d, panel: '%s', paused: %s, menuItem: '%s', finishing: %s}" % [
		names[phase], "true" if Game.has_save() else "false", Game.day, int(Game.money), hud.current_panel if hud else "",
		"true" if get_tree().paused else "false", hud.selected_dish if hud else "", "true" if sim.finishing else "false"])

func show_title() -> void:
	phase = Phase.TITLE
	world.set_drift(true)
	if hud:
		hud.show_title()
	_publish_state()

func new_game() -> void:
	Game.new_game()
	_enter_prep(func():
		if hud:
			hud.show_dialog(tr("ui.w_title"), [tr("ui.w1"), tr("ui.w2"), tr("ui.w3"), tr("ui.w4")], tr("ui.w_go")))

func continue_game() -> void:
	Game.load_game()
	_enter_prep(Callable())

## Title -> prep behind a short curtain (the street is rebuilt for the saved place).
func _enter_prep(then: Callable) -> void:
	var go := func():
		show_prep()
		if then.is_valid():
			then.call()
	if hud:
		hud.fade_through(go)
	else:
		go.call()

func show_prep() -> void:
	phase = Phase.PREP
	world.set_drift(false)
	set_speed(1.0)
	Game.prepare_day()
	world.set_location(Game.location)
	world.set_time(Data.location_hours(Game.location)[0], Game.forecast)
	if hud:
		hud.show_prep()
	Game.save()
	_publish_state()

func start_day(skip_weather_roll: bool = false) -> void:
	phase = Phase.DAY
	if not skip_weather_roll:
		Game.begin_day()
	world.set_location(Game.location)
	if hud:
		hud.show_day()
	sim.start(Game.sim_context(), world)
	world.push_in()
	set_speed(1.0)
	_publish_state()

func set_speed(s: float) -> void:
	speed = s
	Engine.time_scale = 1.0 if sim.finishing else s

func skip_day() -> void:
	if phase != Phase.DAY or not sim.finish_quickly():
		return
	set_speed(DaySim.FINISH_SPEED)
	if hud:
		hud.show_finishing()
	_publish_state()

func _on_day_finished(stats: Dictionary) -> void:
	sim.finishing = false
	world.set_customer_speed(1.0)
	set_speed(1.0)
	phase = Phase.REPORT
	var report := Game.end_day(stats)
	if hud:
		hud.show_report(report)
		if Game.persist:
			Game.notify.emit(tr("ui.saved"), "info")
	_publish_state()

## Dev: compile every script in the project (with autoloads available) and report errors.
func _check_scripts() -> void:
	var bad := 0
	var total := 0
	for dir in ["res://scripts", "res://scripts/core", "res://scripts/sim", "res://scripts/world", "res://scripts/ui", "res://tests"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			total += 1
			var scr = ResourceLoader.load(dir + "/" + f, "GDScript", ResourceLoader.CACHE_MODE_REUSE)
			if scr == null or not (scr as GDScript).can_instantiate():
				bad += 1
				print("[check] FAILED ", dir, "/", f)
	print("[check] %d scripts, %d failed" % [total, bad])
	get_tree().quit(1 if bad > 0 else 0)

## Dev: lay out every model of a folder in a labelled grid to compare them.
func _gallery(folder: String) -> void:
	var dir := DirAccess.open("res://assets/models/" + folder)
	if dir == null:
		return
	var names := []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			names.append(f.trim_suffix(".glb"))
	names.sort()
	var cols := int(ceil(sqrt(names.size() * 1.6)))
	var font: Font = UiTheme.font()
	world.set_location(Game.location)
	var grid := Node3D.new()
	world.add_child(grid)
	ModelLib.plane(grid, Vector2(60, 60), Vector3(0, 0.02, 0), Color(0.5, 0.7, 0.4))
	for i in range(names.size()):
		var x := (i % cols) * 1.6 - cols * 0.8
		var z := int(i / cols) * 1.6
		ModelLib.spawn(folder + "/" + names[i], grid, Vector3(x, 0.03, z), 0, 1.0)
		var l := Label3D.new()
		l.text = names[i]
		l.font = font
		l.font_size = 36
		l.pixel_size = 0.004
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(x, 0.05, z + 0.7)
		grid.add_child(l)
	world.camera.size = cols * 1.6 * 0.75
	var rows := int(ceil(names.size() / float(cols)))
	var target := Vector3(0, 0.3, rows * 0.8 - 0.4)
	world.camera.position = target + world.camera.transform.basis.z * 30.0

# ---------------------------------------------------------------- balance autoplay (headless)

func _autoplay(days: int) -> void:
	## Simulates N days with a greedy "best next purchase" player and prints a growth table
	## (uses FastSim). `--policy=basic` keeps the old supplies-only player.
	print("day | loc      | st | weather   | passers served  dine | revenue   profit | money     pop  rep | lvl | bottleneck")
	var total_profit := 0.0
	var buys := 0
	for d in range(days):
		if DevTools.get_flag("policy", "greedy") == "basic":
			_policy_basic()
		else:
			buys += _policy_greedy()
		Game.begin_day()
		var stats := FastSim.run(Game.sim_context(), Game.rng)
		if DevTools.has("dbg"):
			var ctx := Game.sim_context()
			print("    ctx pop %.2f appeal %.2f counter %.2f kitchen %s qcap %d prices %s" % [ctx["popularity"], ctx["appeal"], ctx["counter_cap"], str(ctx["kitchen"]), ctx["queue_cap"], str(Game.menu["chicken_tikka"]["price"])])
			print("    stats served %d sat_avg %.2f wait_avg %.1f sold_out %d queue_full %d left_wait %d max_queue %d util %s" % [stats["served"], float(stats["satisfaction_sum"]) / maxi(1, int(stats["served"])), float(stats["wait_sum"]) / maxi(1, int(stats["served"])), stats["sold_out"], stats["queue_full"], stats["left_wait"], stats["max_queue"], str(stats["util"])])
		var r := Game.end_day(stats)
		total_profit += float(r["profit"])
		if Game.goal_ready():
			Game.claim_goal()
		print("%3d | %-8s | %2d | %-9s | %5d %5d %5d | %7.0f %7.0f | %8.0f %.2f %.2f | %3d | %s" % [r["day"], r["location"], r["stage"], r["weather"],
			r["passers"], r["served"], r["dine_in"], r["revenue"], r["profit"], r["money"], r["popularity"], r["local_rep"], Game.levels_owned(), r["bottleneck"]])
		if int(r["day"]) % 10 == 0:
			print("    ... total profit %.0f, %d purchases, goals claimed %d" % [total_profit, buys, Game.goals_claimed.size()])
	get_tree().quit()

## Supplies for the day: cover the estimated customers x 1.3 for every item on sale.
func _policy_supplies() -> void:
	var est := Economy.throughput_estimate(Game.sim_context())
	var expect := maxi(20, int(float(est["served"]) * 1.3))
	var ds := Economy.drink_share(Game.forecast)
	var need := {}
	var food_vals := 0.0
	var drink_vals := 0.0
	var offer := Game.offer(true)
	for o in offer:
		if o["kind"] == "food":
			food_vals += float(o["value"])
		elif o["kind"] == "drink":
			drink_vals += float(o["value"])
	for o in offer:
		var count := 0.0
		match String(o["kind"]):
			"food": count = expect * (1.0 - ds) * float(o["value"]) / maxf(food_vals, 0.001)
			"drink": count = expect * (ds * float(o["value"]) / maxf(drink_vals, 0.001) + 0.3 / maxi(1, _count_kind("drink")))
			"side": count = expect * 0.3 / maxi(1, _count_kind("side"))
			"sweet": count = expect * 0.25 / maxi(1, _count_kind("sweet"))
		var per := Economy.portion_ingredients(o["id"], Game.menu[o["id"]])
		for ing in per:
			need[ing] = float(need.get(ing, 0.0)) + count * float(per[ing])
	for ing in need:
		while int(Game.inventory[ing]) < int(need[ing]):
			var packs: Array = Data.INGREDIENTS[ing]["packs"]
			var gap: int = int(need[ing]) - int(Game.inventory[ing])
			var idx := packs.size() - 1
			for i in range(packs.size()):
				if int(packs[i][0]) >= gap:
					idx = i
					break
			if not Game.buy_pack(ing, idx):
				break
	if DevTools.has("pricemult"):
		for id in Data.MENU_ITEMS:
			Game.set_price(id, float(Data.MENU_ITEMS[id]["base_price"]) * float(DevTools.get_flag("pricemult")))

func _count_kind(kind: String) -> int:
	var n := 0
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == kind and Game.is_on_sale(id):
			n += 1
	return n

## Greedy investor: each prep, buy whatever pays itself back fastest while a cash buffer
## for tomorrow's stock and rent remains. Returns the number of purchases.
func _policy_greedy() -> int:
	var bought := 0
	for round in range(10):
		var base := Economy.throughput_estimate(Game.sim_context())
		var base_profit := float(base["profit"])
		var buffer := 1.5 * (float(Game.loc()["rent"]) + Game.daily_wages() + float(Game.history.back().get("cogs", 150.0)) if not Game.history.is_empty() else 300.0)
		# cash piling up means a longer horizon is fine
		var horizon := 1.0 if Game.money < 8000.0 else (2.0 if Game.money < 30000.0 else 4.0)
		var pick := {"score": 0.0, "best": {}} # a dictionary: lambdas capture locals by value
		var consider := func(kind: String, id: String, cost: float, ctx: Dictionary, max_payback: float) -> void:
			if cost <= 0.0 or Game.money - cost < buffer:
				return
			var gain := float(Economy.throughput_estimate(ctx)["profit"]) - base_profit
			if DevTools.has("dbg"):
				print("    cand %s %s cost %.0f gain %.1f money %.0f buffer %.0f" % [kind, id, cost, gain, Game.money, buffer])
			if gain <= 0.0:
				return
			var payback := cost / gain
			if payback > max_payback * horizon:
				return
			var score := gain / cost
			if score > float(pick["score"]):
				pick["score"] = score
				pick["best"] = {"kind": kind, "id": id, "cost": cost}
		# the current goal is worth chasing when it is a purchase (the reward pays part of it)
		var goal := Game.current_goal()
		if not goal.is_empty():
			var req: Dictionary = goal["req"]
			var reward := float(goal["reward"].get("money", 0.0))
			match String(req["type"]):
				"station_level":
					var sid := String(req["station"])
					if Game.station_lock_reason(sid) == "" and Game.station_level(sid) < int(req["n"]):
						consider.call("station", sid, maxf(1.0, Game.station_cost(sid) - reward), Game.what_if({"stations": {sid: Game.station_level(sid) + 1}}), 400.0)
				"stage":
					if Game.stage_lock_reason() == "" and Game.stage_tier() < int(req["n"]):
						var nd := Game.next_stage_def()
						consider.call("stage", nd["id"], maxf(1.0, float(nd["cost"]) - reward), Game.what_if({"stage": Game.stage_tier() + 1}), 400.0)
				"item_unlocked":
					var iid := String(req["id"])
					if not Game.menu[iid]["unlocked"] and Game.item_available(iid):
						consider.call("item", iid, maxf(1.0, float(Data.MENU_ITEMS[iid]["unlock_cost"]) - reward), Game.what_if({"unlock": iid}), 400.0)
					elif not Game.menu[iid]["unlocked"]:
						var need := Game.required_station(Data.MENU_ITEMS[iid])
						if need != "" and Game.station_lock_reason(need) == "":
							consider.call("station", need, maxf(1.0, Game.station_cost(need) - reward), Game.what_if({"stations": {need: 1}, "unlock": iid}), 400.0)
		for id in Game.active_stations():
			if Game.station_lock_reason(id) != "":
				continue
			consider.call("station", id, Game.station_cost(id), Game.what_if({"stations": {id: Game.station_level(id) + 1}}), 30.0)
		if Game.stage_lock_reason() == "":
			# a stage is worth what the best place it opens is worth (with a few seats if it has a terrace)
			var nxt := Game.next_stage_def()
			var t := Game.stage_tier() + 1
			var extra := {}
			var bundle := float(nxt["cost"])
			if float(nxt.get("dine_in", 0.0)) > 0.0:
				extra = {"seating": 4}
				for i in range(4):
					bundle += Economy.station_cost(Data.STATIONS["seating"], i)
			var best_ctx := Game.what_if({"stage": t, "stations": extra})
			var best_profit := float(Economy.throughput_estimate(best_ctx)["profit"])
			if String(nxt["scope"]) == "rig":
				for id in Game.stage_locations():
					if id != Game.location and Game.location_unlocked(id) and int(Data.LOCATIONS[id].get("min_stage", 0)) <= t:
						var c := Game.what_if({"stage": t, "location": id})
						var pr := float(Economy.throughput_estimate(c)["profit"])
						if pr > best_profit:
							best_profit = pr
							best_ctx = c
			consider.call("stage", nxt["id"], bundle, best_ctx, 60.0)
		for id in Data.MENU_ITEMS:
			if not Game.menu[id]["unlocked"] and Game.item_available(id):
				consider.call("item", id, maxf(float(Data.MENU_ITEMS[id]["unlock_cost"]), 1.0), Game.what_if({"unlock": id}), 30.0)
		for id in Game.stage_locations():
			if id != Game.location and Game.location_unlocked(id) and Game.location_stage_ok(id):
				consider.call("move", id, 25.0, Game.what_if({"location": id}), 1.0)
		if Game.competition() > 0.0:
			for id in Data.MARKETING:
				if not Game.marketing.has(id):
					consider.call("promo", id, float(Data.MARKETING[id]["cost"]), _ctx_with_boost(float(Data.MARKETING[id]["boost"])), float(Data.MARKETING[id]["days"]))
		var best: Dictionary = pick["best"]
		if best.is_empty():
			break
		var ok := false
		match String(best["kind"]):
			"station": ok = Game.buy_station_level(best["id"])
			"stage": ok = Game.buy_stage()
			"item": ok = Game.unlock_item(best["id"])
			"move": ok = Game.set_location(best["id"])
			"promo": ok = Game.start_marketing(best["id"])
		if not ok:
			break
		bought += 1
	_policy_prices()
	# cheap quality: max the recipe once the first grill levels are in
	if Game.station_level("grill") >= 2:
		for id in Data.MENU_ITEMS:
			if Data.MENU_ITEMS[id]["recipe"] and Game.menu[id]["unlocked"]:
				Game.set_recipe(id, "meat", 3)
				Game.set_recipe(id, "veg", 3)
				Game.set_recipe(id, "sauce", 2)
	if Game.money > 3000.0:
		for id in Data.MENU_ITEMS:
			if Game.menu[id]["unlocked"] and int(Game.menu[id]["level"]) < Data.MENU_ITEMS[id]["enhance"].size():
				var cost := float(Data.MENU_ITEMS[id]["enhance"][int(Game.menu[id]["level"])]["cost"])
				if Game.money - cost > 2500.0:
					Game.enhance_item(id)
					bought += 1
	_policy_supplies()
	return bought

## Try a few price multipliers on the whole menu and keep the one the estimate likes best.
func _policy_prices() -> void:
	var best_mult := 1.0
	var best_profit := -INF
	var loc := Game.loc()
	for mult in [0.9, 1.0, 1.1, 1.2, 1.35, 1.5, 1.8]:
		# never a price that leaves the average customer unhappy (reputation is the engine)
		var sat := Economy.satisfaction(Game.quality("chicken_tikka"), float(mult), 0.15, loc, Game.satisfaction_bonus())
		if sat < 0.62 and float(mult) > 1.0:
			continue
		for id in Data.MENU_ITEMS:
			Game.set_price(id, float(Data.MENU_ITEMS[id]["base_price"]) * mult)
		var pr := float(Economy.throughput_estimate(Game.sim_context())["profit"])
		if pr > best_profit:
			best_profit = pr
			best_mult = mult
	for id in Data.MENU_ITEMS:
		Game.set_price(id, float(Data.MENU_ITEMS[id]["base_price"]) * best_mult)

func _ctx_with_boost(extra: float) -> Dictionary:
	var ctx := Game.sim_context()
	ctx["boost"] = float(ctx["boost"]) + extra
	return ctx

## The old player: supplies for 1.3x yesterday, Creek when popular, nothing else.
func _policy_basic() -> void:
	var expect := 30
	if not Game.history.is_empty():
		expect = maxi(15, int(float(Game.history.back()["served"]) * 1.3))
	var target := {"bread": expect, "chicken": expect * 2, "veg": expect * 2, "sauce": expect, "charcoal": expect, "drink": int(expect * 0.5)}
	for ing in target:
		while int(Game.inventory[ing]) < int(target[ing]):
			var packs: Array = Data.INGREDIENTS[ing]["packs"]
			var gap: int = int(target[ing]) - int(Game.inventory[ing])
			var idx := packs.size() - 1
			for i in range(packs.size()):
				if int(packs[i][0]) >= gap:
					idx = i
					break
			if not Game.buy_pack(ing, idx):
				break
	if Game.popularity > 0.3 and Game.money > 1500 and Game.location == "fahidi":
		Game.set_location("creek")
	if DevTools.has("pricemult"):
		for id in Data.MENU_ITEMS:
			Game.set_price(id, float(Data.MENU_ITEMS[id]["base_price"]) * float(DevTools.get_flag("pricemult")))

extends Node
## Phase orchestration: Title -> Prep -> Day -> Report -> Prep ...

enum Phase { TITLE, PREP, DAY, REPORT }

const FRAME_CAPS := [30, 60]
const RENDER_SCALES := [0, 50, 65, 80, 100] # 0 = Auto
const GRAPHICS_PATH := "user://graphics.cfg"
const GRAPHICS_WEB_KEY := "mashawi_graphics"

var world: World
var sim: DaySim
var hud: Node
var phase: Phase = Phase.TITLE
var frame_cap := 60
var render_scale := 0
var _graphics_open := false
var _guide_open := false
var _guide_backdrop_scale := 1.0
var _quality_time := 0.0
var _quality_frames := 0
var _quality_warmup := 4.0
var _web_visibility_callback: JavaScriptObject

func _ready() -> void:
	_load_graphics()
	Engine.max_fps = frame_cap
	_apply_render_scale()
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
		_web_visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility)
		JavaScriptBridge.get_interface("window").godotSetPaused = _web_visibility_callback
		JavaScriptBridge.eval("if (window.godotSyncVisibility) window.godotSyncVisibility()")
		# Keep the HTML loading art up until the canvas has actually drawn.
		await RenderingServer.frame_post_draw
		JavaScriptBridge.eval("window.dispatchEvent(new Event('godot-ready'))")

func _on_web_visibility(args: Array) -> void:
	# A phone call, app switch or portrait rotate guard must not spend the day
	# while the player cannot see or control the stand.
	if not args.is_empty():
		get_tree().paused = bool(args[0])
		_publish_state()

## Sustained slow frames lower only the 3D resolution; menus/text stay crisp.
## Use real frame time: the player's simulation speed must not change this decision.
func _process(dt: float) -> void:
	if not OS.has_feature("web") or render_scale != 0 or _graphics_open or DevTools.has("scale3d"):
		return
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
	if fps < (54.0 if frame_cap == 60 else 26.0):
		vp.scaling_3d_scale = maxf(0.50, vp.scaling_3d_scale - 0.05)
	_quality_time = 0.0
	_quality_frames = 0

## Scale only the 3D buffer. The controls and text stay at canvas resolution.
func _apply_render_scale() -> void:
	if DevTools.has("scale3d"):
		return
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var scale := render_scale / 100.0 if render_scale > 0 else 1.0
	if render_scale == 0 and OS.has_feature("web"):
		var dpr := float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
		scale = clampf(1.6 / maxf(dpr, 1.0), 0.75, 1.0)
	vp.scaling_3d_scale = scale

func set_graphics(fps: int, scale: int) -> void:
	if fps not in FRAME_CAPS or scale not in RENDER_SCALES:
		return
	frame_cap = fps
	Engine.max_fps = fps
	if render_scale != scale:
		render_scale = scale
		_apply_render_scale()
	_quality_frames = 0
	_quality_time = 0.0
	_quality_warmup = 2.0
	if OS.has_feature("web"):
		var json := JSON.stringify({"fps": frame_cap, "scale": render_scale})
		JavaScriptBridge.eval("try { localStorage.setItem('%s', JSON.stringify(%s)); } catch (_) {}" % [GRAPHICS_WEB_KEY, json])
	else:
		var config := ConfigFile.new()
		config.set_value("graphics", "fps", frame_cap)
		config.set_value("graphics", "scale", render_scale)
		config.save(GRAPHICS_PATH)

func _load_graphics() -> void:
	var prefs: Variant = {}
	if OS.has_feature("web"):
		var saved: Variant = JavaScriptBridge.eval("try { localStorage.getItem('%s') || ''; } catch (_) { ''; }" % GRAPHICS_WEB_KEY)
		if saved is String and not saved.is_empty():
			prefs = JSON.parse_string(saved)
	else:
		var config := ConfigFile.new()
		if config.load(GRAPHICS_PATH) == OK:
			prefs = {"fps": config.get_value("graphics", "fps", frame_cap), "scale": config.get_value("graphics", "scale", render_scale)}
	if prefs is Dictionary:
		var fps: Variant = prefs.get("fps")
		var scale: Variant = prefs.get("scale")
		if (fps is int or fps is float) and int(fps) in FRAME_CAPS:
			frame_cap = int(fps)
		if (scale is int or scale is float) and int(scale) in RENDER_SCALES:
			render_scale = int(scale)

func set_graphics_open(open: bool) -> void:
	_graphics_open = open
	if not open and _guide_open:
		get_viewport().scaling_3d_scale = _guide_backdrop_scale
		_guide_open = false
	# Pause the street and simulation so settings can still accept input.
	var mode := Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT
	world.process_mode = mode
	sim.process_mode = mode
	_quality_frames = 0
	_quality_time = 0.0

func set_guide_open() -> void:
	if not _guide_open:
		_guide_backdrop_scale = get_viewport().scaling_3d_scale
		_guide_open = true
		# Spend pixels on the host while the dimmed street is behind an opaque card.
		get_viewport().scaling_3d_scale = minf(_guide_backdrop_scale, 0.5)

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
		if _autoplay_started:
			return # a seeded run re-applies the state flags above, nothing below
		_autoplay_started = true
		Game.persist = false
		_autoplay(int(DevTools.get_flag("autodays")))
		return
	if DevTools.has("cast-review"):
		_cast_review()
		if DevTools.has("screenshot"):
			await get_tree().create_timer(float(DevTools.get_flag("delay", "1.0")), true, false, true).timeout
			await DevTools.screenshot(DevTools.get_flag("screenshot"))
			get_tree().quit()
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
	if DevTools.has("character-demo"):
		Game.persist = false
		Game.weather = "sunny"
		Game.forecast = "sunny"
		# Show both crew members while honoring a higher showcase upgrade.
		Game.rig["stations"]["grill"] = maxi(4, int(Game.rig["stations"].get("grill", 0)))
		Game.menu["chicken_tikka"]["level"] = 3
		Game.stock_for_today()
		show_prep()
		if Game.stage_tier() == 0:
			world.preview_cart()
		var demo_panel := DevTools.get_flag("panel")
		if demo_panel in ["menu", "place", "build", "supplies", "promote"]:
			hud.open_panel(demo_panel)
		return
	world.set_location(Game.location)
	if DevTools.has("screenshot"):
		Game.persist = false # screenshot runs never overwrite the player's save
	var ph := DevTools.get_flag("phase", "title")
	match ph:
		"day":
			_stock_up_for_test()
			phase = Phase.PREP
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
			phase = Phase.PREP
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
	# A stage or tier purchase is revealed by the HUD once the Build panel has closed.
	if world.cart and not (hud and hud.holds_world_visual()):
		if hud and phase == Phase.PREP and not hud.is_transitioning() and world.visual_needs_reload():
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
			if hud and hud.is_transitioning():
				return
			if hud and hud.close_graphics():
				return
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
	_enter_prep(Game.new_game, func():
		if hud:
			hud.start_tutorial(true))

func continue_game() -> void:
	_enter_prep(Game.load_game, func():
		if hud:
			hud.resume_tutorial()
		# A day that already opened carries on from its checkpoint. Its weather is
		# known by now, so a return to planning would let the player plan around it.
		if Game.day_committed():
			start_day())

## Title -> prep behind a short curtain (the street is rebuilt for the saved place).
func _enter_prep(load_state: Callable, then: Callable = Callable()) -> void:
	var go := func():
		if load_state.call() == false:
			# The save could not be read: do not write a fresh game over it.
			show_title()
			return
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
	if phase != Phase.PREP:
		return
	phase = Phase.DAY
	if DevTools.has("character-demo") and Game.day == 1:
		Game.weather = "sunny"
	elif not skip_weather_roll:
		Game.begin_day()
	if hud:
		hud.flush_reveal() # a purchase bought a moment ago is built before the day reads the plot
	world.set_location(Game.location)
	if hud:
		hud.show_day()
	sim.start(Game.sim_context(), world)
	world.push_in()
	set_speed(1.0)
	_publish_state()

func set_speed(s: float) -> void:
	sim.set_playback_speed(s)

func skip_day() -> void:
	if phase != Phase.DAY or not sim.finish_quickly():
		return
	set_speed(DaySim.FINISH_SPEED)
	if hud:
		hud.show_finishing(sim.hour, sim.end_hour)
	_publish_state()

func _on_day_finished(stats: Dictionary) -> void:
	if phase != Phase.DAY or int(stats.get("_day", Game.day)) != Game.day:
		return
	sim.finishing = false
	set_speed(1.0)
	phase = Phase.REPORT
	var report := Game.end_day(stats)
	if not hud:
		_publish_state()
		return
	hud.fade_through(func():
		hud.show_report(report)
		if Game.persist:
			Game.notify.emit(tr("ui.saved"), "info")
		_publish_state())

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

## Dev: compare the approved reference and shared outfit variants.
func _cast_review() -> void:
	Game.persist = false
	hud.root.hide()
	world.camera.rotation = Vector3.ZERO
	world.camera.position = Vector3(0, 0.82, 6)
	world.camera.size = 2.5
	world.sun.rotation_degrees = Vector3(-25, -28, 0)
	world.sun.shadow_enabled = false
	world.env.environment.background_mode = Environment.BG_COLOR
	world.env.environment.background_color = Color("d9c3a0")
	if DevTools.has("cast-bg"):
		world.env.environment.background_color = Color(DevTools.get_flag("cast-bg"))
	world.env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.env.environment.ambient_light_color = Color("fff0df")
	world.env.environment.ambient_light_energy = 0.8
	ModelLib.ambient_variety = false # stills must show the requested frame
	var actors: Array[Node3D] = [
		ModelLib.spawn_guest("creek-abaya", world, Vector3(-1.65, 0, 0), 1.65),
		ModelLib.spawn_crew(true, world, Vector3(-0.55, 0, 0), 0, 1.65),
		ModelLib.spawn_guest("souq-abaya", world, Vector3(0.55, 0, 0), 1.65),
		ModelLib.spawn_crew(false, world, Vector3(1.65, 0, 0), 0, 1.65)]
	if DevTools.has("cast-all"):
		# Every shipped character full length, for dress and modesty reviews.
		for actor in actors:
			actor.queue_free()
		actors.clear()
		var ids: Array = ModelLib.GUEST_HEIGHTS.keys()
		ids.sort()
		ids.append_array(ModelLib.GUEST_VARIANTS.keys())
		var per_row := 7
		for i in ids.size() + 1:
			var at := Vector3((float(i % per_row) - (per_row - 1) * 0.5) * 1.05, 1.0 - 2.05 * float(i / per_row), 0)
			if i < ids.size():
				actors.append(ModelLib.spawn_guest(ids[i], world, at, 1.65))
			else:
				actors.append(ModelLib.spawn("crew/filipina-server", world, at, 0, 1.0))
		world.camera.position = Vector3(0, 0.9, 6)
		world.camera.size = 4.3
	for actor in actors:
		var clip := DevTools.get_flag("cast-clip", "idle")
		ModelLib.play_loop(actor, clip)
		var animation := ModelLib.animation_player(actor)
		animation.advance(float(DevTools.get_flag("cast-time", "0.5")))
		animation.pause()
	if DevTools.has("cast-detail"):
		var selected := clampi(int(DevTools.get_flag("cast-detail")), 0, actors.size() - 1)
		for i in actors.size():
			actors[i].visible = i == selected
		actors[selected].position = Vector3.ZERO
		world.camera.position = Vector3(0, 1.42, 3)
		world.camera.size = 0.7

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

var _autoplay_started := false

func _autoplay(days: int) -> void:
	## Simulates N days with a greedy "best next purchase" player and prints a growth table.
	## `--sim=day` plays the real visible day (DaySim) without drawing it; the default
	## `--sim=fast` is the statistical FastSim. `--seed=N` makes a run repeatable.
	## `--policy=basic` keeps the old supplies-only player.
	var played := DevTools.get_flag("sim", "fast") == "day"
	if DevTools.has("seed"):
		var run_seed := int(DevTools.get_flag("seed"))
		seed(run_seed)
		Game.rng.seed = run_seed
		Game.new_game()
		_apply_dev_flags()
	var runner: DaySim
	if played:
		# A sim of its own: the HUD listens to the player's one.
		runner = DaySim.new()
		add_child(runner)
	print("sim %s | seed %s" % ["day (played)" if played else "fast", DevTools.get_flag("seed", "random")])
	print("day | loc      | st | weather   | passers served  port  dine crowd | revenue   profit | money     pop  rep | lvl | lost: wait full out | bottleneck")
	var total_profit := 0.0
	var buys := 0
	var started := Time.get_ticks_msec()
	for d in range(days):
		var day := Autoplayer.play_day(played, runner, world, DevTools.get_flag("policy", "greedy"))
		if played:
			# Let finished guests leave the tree before the next street is built.
			await get_tree().process_frame
		var stats: Dictionary = day["stats"]
		var r: Dictionary = day["report"]
		buys += int(day["buys"])
		if DevTools.has("dbg"):
			var ctx := Game.sim_context()
			print("    ctx pop %.2f appeal %.2f counter %.2f kitchen %s qcap %d prices %s" % [ctx["popularity"], ctx["appeal"], ctx["counter_cap"], str(ctx["kitchen"]), ctx["queue_cap"], str(Game.menu["chicken_tikka"]["price"])])
			print("    stats served %d portions %d crowd %d buyers %d sat_avg %.2f wait_avg %.1f sold_out %d queue_full %d left_wait %d max_queue %d util %s" % [stats["served"], int(stats.get("portions", 0)), int(stats.get("crowd", 0)), int(ctx["buyers"]), float(stats["satisfaction_sum"]) / maxi(1, int(stats["served"])), float(stats.get("wait_sum", 0.0)) / maxi(1, int(stats["served"])), stats["sold_out"], stats["queue_full"], stats["left_wait"], stats.get("max_queue", 0), str(stats.get("util", {}))])
		total_profit += float(r["profit"])
		print("%3d | %-8s | %2d | %-9s | %5d %5d %5d %5d %5d | %7.0f %7.0f | %8.0f %.2f %.2f | %3d | %4d %4d %4d | %s" % [r["day"], r["location"], r["stage"], r["weather"],
			r["passers"], r["served"], int(r.get("portions", r["served"])), r["dine_in"], int(r.get("crowd", 0)), r["revenue"], r["profit"], r["money"], r["popularity"], r["local_rep"], Game.levels_owned(),
			int(stats.get("left_wait", 0)), int(stats.get("queue_full", 0)), int(stats.get("sold_out", 0)), r["bottleneck"]])
		if int(r["day"]) % 10 == 0:
			print("    ... total profit %.0f, %d purchases, goals claimed %d, loans %d" % [total_profit, buys, Game.goals_claimed.size(), Game.bailouts])
	print("autoplay: %d days in %.1f s, total profit %.0f, %d purchases, %d goals, %d loans" % [days, (Time.get_ticks_msec() - started) / 1000.0,
		total_profit, buys, Game.goals_claimed.size(), Game.bailouts])
	get_tree().quit()

## The policies (greedy investor, prices, supplies, the old basic player) live in
## scripts/sim/autoplayer.gd so tests/balance_curve.gd plays the same player.

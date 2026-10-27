extends Node
## Phase orchestration: Title -> Prep -> Day -> Report -> Prep ...

enum Phase { TITLE, PREP, DAY, REPORT }

var world: World
var sim: DaySim
var hud: Node
var phase: Phase = Phase.TITLE
var speed := 1.0

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
		# tells the HTML shell to drop its loading overlay
		JavaScriptBridge.eval("window.dispatchEvent(new Event('godot-ready'))")

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
	if DevTools.has("vehicle"):
		Game.vehicle = DevTools.get_flag("vehicle")
	if DevTools.has("upgrades"):
		for u in DevTools.get_flag("upgrades").split(","):
			Game.upgrades[u] = true
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
		world.cart.apply_upgrades(Game.upgrades)
		world.cart.apply_vehicle(Game.vehicle)
	if phase == Phase.PREP:
		Game.save()

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

func show_title() -> void:
	phase = Phase.TITLE
	if hud:
		hud.show_title()

func new_game() -> void:
	Game.new_game()
	world.set_location(Game.location)
	show_prep()
	if hud:
		hud.show_dialog(tr("ui.w_title"), [tr("ui.w1"), tr("ui.w2"), tr("ui.w3"), tr("ui.w4")], tr("ui.w_go"))

func continue_game() -> void:
	if Game.load_game():
		world.set_location(Game.location)
	show_prep()

func show_prep() -> void:
	phase = Phase.PREP
	set_speed(1.0)
	Game.prepare_day()
	world.set_location(Game.location)
	world.set_time(Data.location_hours(Game.location)[0], Game.forecast)
	if hud:
		hud.show_prep()

func start_day(skip_weather_roll: bool = false) -> void:
	phase = Phase.DAY
	if not skip_weather_roll:
		Game.begin_day()
	world.set_location(Game.location)
	if hud:
		hud.show_day()
	sim.start(Game.sim_context(), world)
	set_speed(1.0)

func set_speed(s: float) -> void:
	speed = s
	Engine.time_scale = s

func skip_day() -> void:
	set_speed(12.0)

func _on_day_finished(stats: Dictionary) -> void:
	set_speed(1.0)
	phase = Phase.REPORT
	var report := Game.end_day(stats)
	if hud:
		hud.show_report(report)

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
	## Simulates N days with a simple "sensible player" policy and prints a table (uses FastSim).
	print("day | loc      | weather | passers served | revenue   profit | money    pop")
	for d in range(days):
		_policy_prepare()
		Game.begin_day()
		var stats := FastSim.run(Game.sim_context(), Game.rng)
		var r := Game.end_day(stats)
		print("%3d | %-8s | %-7s | %5d %5d    | %7.2f %7.2f | %7.2f %.2f" % [r["day"], r["location"], r["weather"], r["passers"], r["served"], r["revenue"], r["profit"], r["money"], r["popularity"]])
	get_tree().quit()

func _policy_prepare() -> void:
	# buy for ~1.3x yesterday's customers (30 on day one), smallest pack that covers the gap
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
	if Game.money > 2000 and not Game.has_upgrade("fridge"):
		Game.buy_upgrade("fridge")
	if Game.money > 2500 and Game.menu["chicken_tikka"]["level"] < 3:
		Game.enhance_item("chicken_tikka")

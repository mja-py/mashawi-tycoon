class_name World
extends Node3D
## The 2.5D street. Builds a location from a layout, owns the camera, light,
## environment and the cart, and spawns walkers / cars for the simulation.

const SKYSCRAPERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c",
	"building-skyscraper-d", "building-skyscraper-e"]
const CARS := ["sedan", "sedan-sports", "hatchback-sports", "suv", "suv-luxury", "van", "delivery", "truck", "taxi", "police"]
const HALF_W := 7
const FRONT_Z := -1.62
## width, depth of the Kenney building models (origin centred)
const BUILDING_DIMS := {
	"building-i": [1.24, 1.3], "building-k": [2.08, 0.94], "building-l": [1.37, 1.4], "building-m": [1.24, 1.24],
	"building-skyscraper-a": [1.36, 1.36], "building-skyscraper-b": [1.36, 1.36], "building-skyscraper-c": [1.28, 1.39],
	"building-skyscraper-d": [1.28, 1.39], "building-skyscraper-e": [1.29, 1.24],
}
const WALK_Z := -0.62
const NEAR_WALK_Z := 0.95
const ARRIVAL_Z := -0.46
const PROMENADE_Z := 0.01
const CART_POS := Vector3(0.0, 0.0, -1.42)
const WALK_EDGE := 5.6
const MAX_WALKERS := 16
const MAX_RIGGED_GUESTS := 6
## The first few faces establish each district. The same compact set is reused
## in different combinations for service customers and background walkers.
const DISTRICT_CAST := {
	"fahidi": ["creek-kandura", "creek-abaya", "souq-man", "souq-woman", "city-commuter", "beach-walker"],
	"creek": ["beach-walker", "creek-abaya", "creek-kandura", "souq-woman", "souq-man"],
	"metro": ["city-commuter", "souq-man", "creek-kandura", "souq-woman", "city-commuter", "creek-abaya"],
	"jbr": ["jbr-modest-swimmer", "jbr-local-swimmer", "beach-walker", "souq-man", "creek-abaya", "souq-woman"],
	"downtown": ["downtown-fashion", "downtown-tailored", "city-commuter", "village-evening", "creek-kandura", "souq-woman"],
	"mall": ["creek-abaya", "city-commuter", "creek-kandura", "souq-woman", "souq-man", "beach-walker"],
	"gv": ["village-evening", "downtown-tailored", "creek-kandura", "downtown-fashion", "souq-woman", "souq-man"],
}
const BUILDING_ROT := 0.0
const ROAD_ROT := 0.0

var camera: Camera3D
## Orthographic camera size per plot stage (wider plots need more room).
const STAGE_CAM := [3.6, 3.9, 4.4, 5.0, 5.3, 5.6]
const PLAY_CAMERA_ROTATION := Vector3(-33, 14, 0)
const SOUQ_CAMERA_ROTATION := Vector3(-19, -9, 0)
const SOUQ_CART_CAM := 3.10
var _cam_base := Vector3.ZERO
var _play_rotation := PLAY_CAMERA_ROTATION
var _cam_tween: Tween
var _cart_preview := false
var _drift := false
var _drift_t := 0.0
var _beach_crowns: Array[Node3D] = []
var _breeze_time := 0.0
var sun: DirectionalLight3D
var env: WorldEnvironment
var cart: MashawiStand
## The build-out (stand rig, kiosk, stations, seats); owns `cart` for stages 0-2.
var plot: Plot = null
## Half-width of the street gap left for the plot at the current location (0 = none).
var _gap := 0.0
var location_id := ""
var _level: Node3D
var _lamps: Array[OmniLight3D] = []
var _rng := RandomNumberGenerator.new()
## static small parts of the level, flushed into _level as MultiMeshes
var _batch := MeshBatch.new()
var _sky_day := Color(0.55, 0.78, 0.98)
var _sand: GPUParticles3D
var walkers := 0
var _rigged_guests := 0
var _next_guest := 0
var _next_passer := 2
var customer_speed := 1.0

func _ready() -> void:
	_setup_camera()
	_setup_light()
	_setup_sandstorm()

func _setup_sandstorm() -> void:
	_sand = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.5, 1.6, 5.0)
	# sandstorm: fast, low, wind-blown grains
	mat.direction = Vector3(1, -0.25, 0.1)
	mat.spread = 8.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0, -1.5, 0)
	_sand.process_material = mat
	_sand.amount = 140 if OS.has_feature("web") else 300
	_sand.lifetime = 0.9
	_sand.position = Vector3(-7.0, 1.6, -0.5)
	_sand.visibility_aabb = AABB(Vector3(-10, -6, -8), Vector3(20, 8, 16))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.02, 0.02)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.72, 0.5, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = m
	_sand.draw_pass_1 = mesh
	_sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sand.emitting = false
	_sand.visible = false
	add_child(_sand)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.4
	camera.near = 0.1
	camera.far = 60.0
	camera.rotation_degrees = PLAY_CAMERA_ROTATION
	add_child(camera)
	var target := Vector3(0.0, 0.38, -1.05)
	camera.position = target + camera.transform.basis.z * 22.0
	_cam_base = camera.position
	camera.current = true

func _setup_light() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.light_energy = 1.0
	add_child(sun)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = _sky_day
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.95)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	# Glow is a full-screen multi-pass effect; too costly for WebGL on phones.
	e.glow_enabled = not OS.has_feature("web")
	e.glow_intensity = 0.35
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.2
	env.environment = e
	add_child(env)

## Camera size for a stage; animated when the plot grows under the player's eyes.
func frame_stage(tier: int, animate: bool = false) -> void:
	var size := _stage_camera_size(tier)
	if _cam_tween:
		_cam_tween.kill()
	if not animate or absf(camera.size - size) < 0.01:
		camera.size = size
		return
	_cam_tween = create_tween()
	_cam_tween.tween_property(camera, "size", size, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _stage_camera_size(tier: int) -> float:
	return SOUQ_CART_CAM if location_id == "fahidi" and tier == 0 else STAGE_CAM[clampi(tier, 0, STAGE_CAM.size() - 1)]

## Opening the stand: a short push-in towards the plot.
func push_in() -> void:
	var preview := _cart_preview
	if _cart_preview:
		_cart_preview = false
		cart.preview_crew(false)
	if preview and location_id == "fahidi" and Game.stage_tier() == 0:
		camera.rotation_degrees = SOUQ_CAMERA_ROTATION
		camera.position = _cam_base
		camera.size = SOUQ_CART_CAM
		return
	camera.rotation_degrees = _play_rotation
	camera.position = _cam_base
	var size := _stage_camera_size(_stage_at(location_id))
	if _cam_tween:
		_cam_tween.kill()
	camera.size = size * 1.06
	_cam_tween = create_tween()
	_cam_tween.tween_property(camera, "size", size, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func preview_cart() -> void:
	_cart_preview = true
	cart.preview_crew(true)
	if _cam_tween:
		_cam_tween.kill()
	camera.rotation_degrees = Vector3(-14, 0, 0)
	camera.position = Vector3(0, 0.49, -1.42) + camera.transform.basis.z * 22.0
	camera.size = 1.47
	sun.light_energy = 0.5
	env.environment.ambient_light_energy = 0.4

## Title screen: the camera drifts slowly sideways so the street feels alive.
func set_drift(on: bool) -> void:
	if on == _drift:
		return
	_drift = on
	if not on:
		var tw := create_tween()
		tw.tween_property(camera, "position", _cam_base, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _drift:
		_drift_t += delta
		camera.position = _cam_base + camera.transform.basis.x * sin(_drift_t * 0.22) * 0.45
	if not _beach_crowns.is_empty():
		_breeze_time += delta
		for i in range(_beach_crowns.size()):
			var phase := _breeze_time * 1.1 + i * 1.6
			_beach_crowns[i].rotation.x = sin(phase * 0.84) * 0.028
			_beach_crowns[i].rotation.z = sin(phase) * 0.042

## True when redrawing the stand would rebuild the whole street (plot gap changed).
func visual_needs_reload() -> bool:
	return location_id != "" and Plot.footprint(_stage_at(location_id)) != _gap

# ---------------------------------------------------------------- building

## Rebuild the current place (after a language switch or vehicle change).
func reload() -> void:
	var id := location_id
	location_id = ""
	set_location(id)

func set_location(id: String) -> void:
	if id == location_id:
		return
	location_id = id
	if _level:
		_level.queue_free()
	_lamps.clear()
	_beach_crowns.clear()
	walkers = 0
	_rigged_guests = 0
	_next_guest = 0
	_next_passer = 2
	_level = Node3D.new()
	add_child(_level)
	_batch = MeshBatch.new()
	_rng.seed = hash(id)
	var tier := _stage_at(id)
	_gap = Plot.footprint(tier)
	var layout: String = Data.LOCATIONS[id]["layout"]
	var souq := layout == "fahidi"
	_play_rotation = PLAY_CAMERA_ROTATION
	var focus := Vector3(0.0, 0.38, -1.05)
	match layout:
		"fahidi":
			_play_rotation = SOUQ_CAMERA_ROTATION
			focus = Vector3(0.08, 0.72, -1.56)
		"metro":
			_play_rotation = Vector3(-24, 12, 0)
			focus = Vector3(0.05, 0.61, -1.50)
		"jbr":
			_play_rotation = Vector3(-27, 12, 0)
			focus = Vector3(0.03, 0.48, -1.20)
	if tier == 2:
		_play_rotation.x = maxf(_play_rotation.x, -21.0)
	camera.rotation_degrees = _play_rotation
	_cam_base = focus + camera.transform.basis.z * 22.0
	camera.position = _cam_base
	if not souq:
		_build_ground(layout)
	match layout:
		"fahidi": SouqScenery.new(_batch, _rng).build(_level, _gap)
		"creek": _build_creek()
		"metro": _build_metro()
		"jbr": _build_jbr()
		"downtown": _build_downtown()
		"mall": _build_mall()
		"gv": _build_gv()
	plot = Plot.new()
	plot.position = Plot.PLOT_POS
	cart = plot.cart
	_level.add_child(plot)
	frame_stage(_stage_at(id))
	apply_visual()
	if float(Data.LOCATIONS[id].get("competition", 0.0)) > 0.0:
		_rival_stalls()
	_batch.flush(_level)
	set_time(Data.location_hours(id)[0], Game.weather)

## Stage tier sold from at a location (the rig, or the fixed plot built there).
func _stage_at(id: String) -> int:
	if id == Game.location:
		return Game.stage_tier()
	return maxi(Game.rig_tier(), Game.plot_stage_tier(id))

## True when x (with half-width `half`) clears the plot gap.
func _clear_of_gap(x: float, half: float = 0.0, margin: float = 0.0) -> bool:
	return _gap <= 0.0 or absf(x) - half >= _gap + margin

## A sidewalk prop on the stand's side of the street, skipped where the plot needs the room.
func _side_prop(model: String, pos: Vector3, rot: float = 0.0, scale: float = 1.0) -> void:
	if _gap > 0.0 and absf(pos.x) < _gap + 1.0 and pos.z > -2.6 and pos.z < -0.8:
		return
	_batch.add_model(model, Transform3D(Basis(Vector3.UP, deg_to_rad(rot)).scaled(Vector3.ONE * scale), pos))

## Static imported scenery shares geometry and materials across the whole street.
func _scenery(model: String, pos: Vector3, rot: float = 0.0, scale: float = 1.0) -> void:
	_batch.add_model(model, Transform3D(Basis(Vector3.UP, deg_to_rad(rot)).scaled(Vector3.ONE * scale), pos))

func _pick(arr: Array) -> String:
	return arr[_rng.randi_range(0, arr.size() - 1)]

func _pick_any(arr: Array) -> Variant:
	return arr[_rng.randi_range(0, arr.size() - 1)]

func _build_ground(layout: String) -> void:
	if Paving.DESIGNS.has(layout):
		var size := Vector2(32, 5.6)
		var center := Vector3(0, 0.006, 0.88)
		if layout == "mall" or layout == "gv":
			size.y = 12.0
			center.z = -2.4
		Paving.build(_level, layout, size, center)
		return
	var sidewalk := "roads/tile-low"
	var paving := ModelLib.flat_material(Color("a9aaa5") if layout == "metro" else Color("c2b8a7"))
	var road_basis := Basis(Vector3.UP, deg_to_rad(ROAD_ROT))
	for x in range(-HALF_W, HALF_W + 1):
		_batch.add_model("roads/road-straight", Transform3D(road_basis, Vector3(x, 0, 0)))
		if layout != "downtown":
			_batch.add_model(sidewalk, Transform3D(Basis.IDENTITY, Vector3(x, 0, -1)), paving)
			_batch.add_model(sidewalk, Transform3D(Basis.IDENTITY, Vector3(x, 0, 1)), paving)
			_batch.add_model(sidewalk, Transform3D(Basis.IDENTITY, Vector3(x, 0, -2)), paving)
	if layout == "downtown":
		Paving.build(_level, "boulevard", Vector2(30, 2.15), Vector3(0, 0.005, -1.59))
		Paving.build(_level, "boulevard", Vector2(30, 1.58), Vector3(0, 0.005, 1.30))
	ModelLib.plane(_level, Vector2(40, 40), Vector3(0, -0.015, 0), Color("a99f8d"))

func _lamp(x: float, z: float, rot: float, model: String = "roads/light-curved") -> void:
	_scenery(model, Vector3(x, 0, z), rot)
	var l := OmniLight3D.new()
	l.position = Vector3(x, 0.66, z + (0.18 if rot == 0.0 else -0.18))
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 1.4
	l.omni_range = 2.4
	l.visible = false
	_level.add_child(l)
	_lamps.append(l)

## Packs buildings side by side so their fronts line up on `front_z`. On the building
## line the plot's gap (if any) is left empty.
func _fitted_row(models: Array, front_z: float, scale: float = 1.0, gap: float = 0.06) -> void:
	var x := -HALF_W - 1.5
	var last := ""
	var hole := _gap if is_equal_approx(front_z, FRONT_Z) else 0.0
	while x <= HALF_W + 1.5:
		var m := _pick(models)
		if m == last and models.size() > 1:
			m = _pick(models)
		last = m
		var dims: Array = BUILDING_DIMS.get(m, [1.0, 1.0])
		var w: float = float(dims[0]) * scale
		var d: float = float(dims[1]) * scale
		if hole > 0.0 and x < hole and x + w > -hole:
			# try a narrower model that still fits before the gap, else jump past it
			var fit := ""
			for cand in models:
				if x + float(BUILDING_DIMS.get(cand, [1.0, 1.0])[0]) * scale <= -hole:
					fit = cand
					break
			if fit == "":
				x = hole + gap
				continue
			m = fit
			dims = BUILDING_DIMS.get(m, [1.0, 1.0])
			w = float(dims[0]) * scale
			d = float(dims[1]) * scale
		_batch.add_model("buildings/" + m, Transform3D(Basis(Vector3.UP, deg_to_rad(BUILDING_ROT)).scaled(Vector3.ONE * scale), Vector3(x + w / 2.0, 0, front_z - d / 2.0)))
		x += w + gap

func _skyline(models: Array, z: float, scale: float) -> void:
	_fitted_row(models, z, scale, 0.1)

# ---------------------------------------------------------------- Gulf architecture

const PALMS := ["nature/tree_palm", "nature/tree_palmBend", "nature/tree_palmTall", "nature/tree_palmShort", "nature/tree_palmDetailedTall"]

func _gulf_building(pos: Vector3, w: float, d: float, h: float, tone: Color, tower: bool, awning: bool = false) -> Node3D:
	return GulfArch.building(_level, _rng, _batch, pos, w, d, h, tone, tower, awning)

func _gulf_row(front_z: float, scale: float = 1.0, towers: float = 0.45, awnings: float = 0.0) -> void:
	var front := is_equal_approx(front_z, FRONT_Z)
	GulfArch.row(_level, _rng, _batch, HALF_W, front_z, scale, towers, awnings, _gap if front else 0.0, 1.9 if front else 0.0)

static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)

func _palms_along(z: float, count: int, spread: float = 7.5, min_x_gap: float = 1.4) -> void:
	for i in range(count):
		var x := -spread + (i + 0.5) * (2.0 * spread / count) + _rng.randf_range(-0.3, 0.3)
		if absf(x) < min_x_gap or (z < 0.0 and not _clear_of_gap(x, 0.3)):
			continue
		var pos := Vector3(x, 0, z + _rng.randf_range(-0.1, 0.1))
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.65, 0.9))
		_batch.add_model(_pick(PALMS), Transform3D(basis, pos))

# ---------------------------------------------------------------- locations

func _build_creek() -> void:
	# Creek Park: lawn, palms and the creek behind
	ModelLib.plane(_level, Vector2(40, 13), Vector3(0, -0.016, 1.25), Color("748d52"))
	ModelLib.plane(_level, Vector2(40, 8), Vector3(0, -0.07, -9.10), Color("477d87"))
	ModelLib.plane(_level, Vector2(40, 0.35), Vector3(0, -0.008, -5.1), Color("b6a285"))
	var fx := -HALF_W - 0.5
	while fx <= HALF_W + 0.5:
		if absf(fx) > maxf(1.9, _gap + 0.5):
			_scenery("nature/fence_simple", Vector3(fx, 0, -1.85), 0)
		fx += 1.0
	var placed: Array[Vector3] = []
	var tries := 0
	while placed.size() < 18 and tries < 300:
		tries += 1
		var x := _rng.randf_range(-8.5, 8.5)
		var z := _rng.randf_range(-4.8, -2.1)
		if absf(x) < maxf(1.6, _gap + 0.4) and z > -2.9:
			continue
		var ok := true
		for p in placed:
			if p.distance_to(Vector3(x, 0, z)) < 1.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(Vector3(x, 0, z))
		if _rng.randf() < 0.65:
			_scenery(_pick(PALMS), Vector3(x, 0, z), _rng.randf() * 360, _rng.randf_range(0.7, 1.0))
		else:
			_scenery(_pick(["nature/tree_oak", "nature/tree_fat", "nature/tree_detailed"]), Vector3(x, 0, z), _rng.randf() * 360, _rng.randf_range(0.6, 0.85))
	for i in range(18):
		var m := _pick(["nature/plant_bush", "nature/plant_bushSmall", "nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA", "nature/grass_large"])
		var fp := Vector3(_rng.randf_range(-7.5, 7.5), 0, _rng.randf_range(-2.4, -1.95))
		var rot := _rng.randf() * 360
		var sc := _rng.randf_range(0.5, 0.75)
		if _clear_of_gap(fp.x, 0.2):
			_scenery(m, fp, rot, sc)
	for i in range(4):
		_scenery(_pick(["kaykit/rock_single_A", "kaykit/rock_single_B"]), Vector3(_rng.randf_range(-8.0, 8.0), 0, _rng.randf_range(-4.5, -2.3)), _rng.randf() * 360, 0.8)
	for bx in [-3.4, 3.6]:
		_side_prop("kaykit/bench", Vector3(bx, 0, -1.3), 0, 1.5)
		_scenery("furniture/table-set", Vector3(bx + 0.2, 0, -3.05), 25.0, 0.88)
		_batch.add_cyl(0.40, 0.018, Color("b6a285"), _at(Vector3(bx + 0.2, -0.007, -3.05)), 0.0, 24)
	_side_prop("kaykit/bush", Vector3(-2.4, 0, -1.3), 0, 1.3)
	_side_prop("kaykit/bush", Vector3(2.5, 0, -1.3), 0, 1.3)
	_lamp(-3.2, -0.62, 0, "roads/light-square")
	_lamp(3.2, -0.62, 0, "roads/light-square")
	_lamp(-1.2, 0.62, 180, "roads/light-square")
	_palms_along(1.45, 4, 6.0, 1.0)

func _build_metro() -> void:
	# An elevated shell station with a glazed concourse and metal ribs.
	_skyline(SKYSCRAPERS + ["building-k", "building-l", "building-m"], -3.6, 1.5)
	_metro_station(Vector3(0.18, 0, -2.90 if _gap < 2.4 else -3.68))
	for sx in [-1.9, 1.9]:
		if _clear_of_gap(sx * 2.0, 0.7):
			_gulf_building(Vector3(sx * 2.0, 0, FRONT_Z - 0.6), 1.4, 1.2, 1.2, GulfArch.WHITE_WASH, false)
	_scenery("roads/road-sign-street", Vector3(-2.5, 0, -0.62), 0)
	_scenery("roads/traffic-light", Vector3(5.5, 0, -0.62), 0)
	_scenery("roads/traffic-light", Vector3(-6.2, 0, 0.62), 180)
	_lamp(2.6, -0.62, 0, "roads/light-square")
	_lamp(-5.0, -0.62, 0, "roads/light-square")
	_lamp(0.8, 0.62, 180, "roads/light-square")
	_scenery("cars/taxi", Vector3(3.6, 0, 0.3), 90, 0.21)
	_scenery("cars/taxi", Vector3(4.4, 0, 0.3), 90, 0.21)
	_side_prop("kaykit/bench", Vector3(-3.6, 0, -1.3), 0, 1.5)
	_palms_along(1.45, 5, 6.5, 1.0)

func _metro_station(p: Vector3) -> void:
	var concrete := Color("bbb2a3")
	var bronze := Color("b68d58")
	var gold := Color("d3ab75")
	var glass := Color("4a6974")
	_batch.add_box(Vector3(5.4, 0.14, 1.38), concrete, _at(p + Vector3(0, 0.76, 0)))
	_batch.add_box(Vector3(3.85, 0.44, 1.18), glass, _at(p + Vector3(0, 1.03, 0)))
	for x in [-1.48, 1.48]:
		_batch.add_box(Vector3(0.31, 0.72, 0.65), concrete, _at(p + Vector3(x, 0.36, 0)))
		_batch.add_box(Vector3(0.69, 0.12, 0.72), concrete, _at(p + Vector3(x, 0.68, 0)))
	for i in range(10):
		var x := (i - 4.5) * 0.39
		_batch.add_box(Vector3(0.026, 0.42, 0.035), concrete, _at(p + Vector3(x, 1.02, 0.606)))
	for i in range(12):
		var a := (i + 0.5) * PI / 12.0
		var z := cos(a) * 0.71
		var y := 1.05 + sin(a) * 0.50
		var span := 4.80 - sin(a) * 0.63
		var basis := Basis(Vector3.RIGHT, atan2(0.50 * cos(a), 0.71 * sin(a)))
		_batch.add_box(Vector3(span, 0.035, 0.205), gold if i % 4 != 0 else bronze,
			Transform3D(basis, p + Vector3(0, y, z)))
	_batch.add_box(Vector3(0.90, 0.60, 0.62), glass, _at(p + Vector3(2.03, 0.30, 0.67)))
	_batch.add_box(Vector3(0.97, 0.055, 0.70), bronze, _at(p + Vector3(2.03, 0.62, 0.67)))

func _build_jbr() -> void:
	# JBR: sand, sea, parasols and the towers across the bay
	ModelLib.plane(_level, Vector2(40, 9), Vector3(0, 0.002, -2.35), Color("cfb68e"))
	ModelLib.plane(_level, Vector2(60, 14), Vector3(0, 0.008, -10.70), Color("458da0"))
	ModelLib.plane(_level, Vector2(40, 0.41), Vector3(0, 0.005, -3.65), Color("ad9b7e"))
	ModelLib.plane(_level, Vector2(40, 0.12), Vector3(0, 0.010, -3.74), Color("b7d3ce"))
	for i in range(8):
		var x := -8.0 + i * 2.2 + _rng.randf_range(-0.3, 0.3)
		_scenery("buildings/" + _pick(SKYSCRAPERS), Vector3(x, 0, -12.5), 0, 1.4)
	var inner := maxf(1.8, _gap)
	for side in [-1.0, 1.0]:
		_beach_palm(Vector3(side * (inner + 0.56), 0, -2.29), -17.0 * side)
		_beach_shade(Vector3(side * (inner + 1.65), 0, -2.38))
		for i in range(2):
			var x: float = side * (inner + 2.70 + 0.94 * i)
			_scenery("buildings/detail-parasol-a" if i == 0 else "buildings/detail-parasol-b",
				Vector3(x, 0, -3.09 + 0.16 * i), 24.0 * side, 0.94)
		_scenery("nature/tree_palmDetailedTall", Vector3(side * 2.83, 0.043, 1.56), 23.0 * side, 0.86)
	_lamp(-3.0, -0.62, 0)
	_lamp(3.0, -0.62, 0)
	_scenery("kaykit/bench", Vector3(-1.5, 0, 1.4), 180, 1.5)

func _beach_palm(p: Vector3, angle: float) -> void:
	var palm := ModelLib.spawn("nature/tree_palmDetailedTall", _level, p + Vector3.UP * 0.042, angle, 0.84)
	if palm == null:
		return
	var leaves := palm.find_children("leafs*", "MeshInstance3D", true, false)
	if leaves.is_empty():
		return
	# Pivot at the imported crown so the trunks stay planted beside the shelter.
	var pivot := Node3D.new()
	pivot.name = "PalmCrown"
	palm.add_child(pivot)
	pivot.global_position = (leaves[0] as Node3D).global_position
	for leaf in leaves:
		leaf.reparent(pivot)
	_beach_crowns.append(pivot)

func _beach_shade(p: Vector3) -> void:
	var frame := Color("674f43")
	_batch.add_box(Vector3(0.84, 0.055, 0.55), frame, _at(p + Vector3.UP * 0.029))
	for x in [-0.37, 0.37]:
		for z in [-0.23, 0.23]:
			_batch.add_box(Vector3(0.036, 0.82, 0.036), frame, _at(p + Vector3(x, 0.41, z)))
	for i in range(9):
		var x := (i - 4) * 0.096
		_batch.add_box(Vector3(0.095, 0.031, 0.56), Color("397c80") if i % 3 == 0 else Color("e2ccaa"),
			_at(p + Vector3(x, 0.83, 0)))
	_scenery("kaykit/bench", p + Vector3(0, 0.066, -0.08), 0, 1.05)

func _build_downtown() -> void:
	GulfArch.burj(_level, _batch, Vector3(4.6, 0, -2.5))
	_skyline(SKYSCRAPERS, -3.6, 1.6)
	_fitted_row(SKYSCRAPERS + ["building-k", "building-l", "building-m", "building-i"], FRONT_Z)
	_lamp(-4.2, -0.62, 0, "roads/light-curved-double")
	_lamp(4.2, -0.62, 0, "roads/light-curved-double")
	_lamp(-1.6, 0.62, 180, "roads/light-square")
	_lamp(2.0, 0.62, 180, "roads/light-square")
	_scenery("roads/traffic-light", Vector3(6.0, 0, -0.62), 0)
	_side_prop("suburban/planter", Vector3(-2.6, 0, -1.3), 0)
	_side_prop("kaykit/bench", Vector3(2.6, 0, -1.3), 0, 1.5)
	_scenery("kaykit/bench", Vector3(-4.4, 0, 1.4), 180, 1.5)
	_palms_along(1.45, 5, 6.5, 1.0)
	_scenery("cars/taxi", Vector3(-4.0, 0, 0.3), 90, 0.21)

func _build_mall() -> void:
	# Mall food court: shop fronts, planters and skylight columns
	var x := -HALF_W - 1.5
	var shop_cols := [Color(0.85, 0.3, 0.25), Color(0.25, 0.5, 0.75), Color(0.3, 0.65, 0.45), Color(0.9, 0.65, 0.2), Color(0.55, 0.35, 0.65)]
	var k := 0
	while x <= HALF_W + 1.5:
		var w := _rng.randf_range(1.4, 2.2)
		if _gap > 0.0 and x < _gap and x + w > -_gap:
			if -_gap - x >= 1.0:
				w = -_gap - x - 0.05
			else:
				x = _gap + 0.1
				continue
		var sp := Vector3(x + w / 2.0, 0, FRONT_Z - 0.6)
		_batch.add_box(Vector3(w, 1.5, 1.2), Color(0.96, 0.95, 0.92), _at(sp + Vector3(0, 0.75, 0)))
		_batch.add_box(Vector3(w - 0.2, 0.9, 0.04), Color(0.6, 0.75, 0.9, 0.9), _at(sp + Vector3(0, 0.5, 0.61)))
		_batch.add_box(Vector3(w - 0.1, 0.25, 0.06), shop_cols[k % shop_cols.size()], _at(sp + Vector3(0, 1.2, 0.62)))
		_batch.add_box(Vector3(w, 0.06, 1.3), Color(0.8, 0.8, 0.8), _at(sp + Vector3(0, 1.53, 0.0)))
		x += w + 0.1
		k += 1
	for cx in [-6.0, -2.0, 2.0, 6.0]:
		_batch.add_cyl(0.08, 1.9, Color(0.88, 0.88, 0.86), _at(Vector3(cx, 0.95, -0.62)))
		_scenery("nature/pot_large", Vector3(cx + 0.5, 0, 1.4), 0, 0.8)
		_scenery("nature/tree_palmShort", Vector3(cx + 0.5, 0.12, 1.4), 0, 0.5)
	for bx in [-4.2, 4.4]:
		_scenery("kaykit/bench", Vector3(bx, 0, 1.4), 180, 1.5)

func _build_gv() -> void:
	# Global Village: souk stalls, lanterns and Gulf facades
	_gulf_row(-3.4, 1.3, 0.4)
	_gulf_row(FRONT_Z, 1.0, 0.3, 0.6)
	_village_gateway(Vector3(-maxf(1.62, _gap - 0.35), 0, -2.64))
	for x in [-5.2, -3.0, 3.0, 5.2]:
		if not _clear_of_gap(x, 0.5, 0.05):
			continue
		var sp := Vector3(x, 0, -1.4)
		_batch.add_box(Vector3(0.9, 0.5, 0.5), Color(0.3, 0.25, 0.2), _at(sp + Vector3(0, 0.25, 0)))
		_batch.add_box(Vector3(1.0, 0.04, 0.7), _pick_any([Color(0.85, 0.35, 0.2), Color(0.25, 0.55, 0.75), Color(0.9, 0.7, 0.2)]), _at(sp + Vector3(0, 0.95, 0)))
		for sx in [-0.45, 0.45]:
			_batch.add_box(Vector3(0.03, 0.5, 0.03), Color(0.2, 0.2, 0.2), _at(sp + Vector3(sx, 0.7, 0.3)))
	for x in range(-HALF_W, HALF_W + 1):
		if absf(x + 0.5) < 1.9:
			continue # the garland stops either side of the stand instead of crossing its sign
		var col: Color = _pick_any([Color(1.0, 0.55, 0.2), Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.3)])
		_batch.add_cyl(0.05, 0.08, col, _at(Vector3(x + 0.5, 1.15 - absf(fmod(x, 2.0)) * 0.06, -0.55)), 2.5)
		_batch.add_box(Vector3(0.5, 0.008, 0.008), Color(0.2, 0.2, 0.2), _at(Vector3(x + 0.5, 1.25, -0.55)))
		if int(x) % 3 == 0:
			var l := OmniLight3D.new()
			l.position = Vector3(x + 0.5, 1.1, -0.5)
			l.light_color = col
			l.light_energy = 1.0
			l.omni_range = 2.2
			l.visible = false
			_level.add_child(l)
			_lamps.append(l)
	_lamp(-1.8, 0.62, 180)
	_lamp(2.4, 0.62, 180)
	_palms_along(1.45, 4, 6.0, 1.0)

func _village_gateway(p: Vector3) -> void:
	# A lit, wave-trimmed festival gate echoes the UAE pavilion beside the walk.
	var sand := Color("c6a178")
	var brass := Color("b18551")
	var teal := Color("34676f")
	var spring := 0.80
	var radius := 0.53
	for sign in [-1.0, 1.0]:
		var x: float = sign * radius
		_batch.add_box(Vector3(0.16, spring, 0.26), sand, _at(p + Vector3(x, spring * 0.5, 0)))
		_batch.add_box(Vector3(0.20, 0.07, 0.30), brass, _at(p + Vector3(x, spring - 0.075, 0)))
		_batch.add_box(Vector3(0.039, 0.52, 0.019), teal, _at(p + Vector3(x, 0.39, 0.139)))
	for i in range(13):
		var a := float(i) * PI / 12.0
		var point := p + Vector3(radius * cos(a), spring + radius * sin(a), 0)
		var turn := Basis(Vector3.BACK, a)
		_batch.add_box(Vector3(0.17, 0.143, 0.24), sand, Transform3D(turn, point))
		_batch.add_box(Vector3(0.089, 0.117, 0.018), teal if i % 2 else brass, Transform3D(turn, point + Vector3.BACK * 0.126))
		_batch.add_box(Vector3(0.032, 0.029, 0.016), Color("e9ba76"), Transform3D(turn, point + Vector3.BACK * 0.139), 0.8)

## Rival food counters flanking the player at competitive places.
func _rival_stalls() -> void:
	var cols := [Color(0.2, 0.45, 0.7), Color(0.85, 0.55, 0.15), Color(0.3, 0.6, 0.35), Color(0.6, 0.25, 0.55)]
	var i := 0
	# rivals move out past the plot's gap (and the pickup spots on its +X side)
	var inner := maxf(3.2, _gap + 0.65 + (1.0 if _gap > 0.0 else 0.0))
	for x in [-inner, -inner - 2.4, inner, inner + 2.4]:
		var st := Node3D.new()
		st.position = Vector3(x, 0, -1.45)
		_level.add_child(st)
		var col: Color = cols[i % cols.size()]
		var sp := st.position
		_batch.add_box(Vector3(1.0, 0.5, 0.5), col.darkened(0.3), _at(sp + Vector3(0, 0.25, 0)))
		_batch.add_box(Vector3(1.0, 0.12, 0.52), Color(0.95, 0.92, 0.85), _at(sp + Vector3(0, 0.56, 0)))
		for sx in [-0.46, 0.46]:
			_batch.add_box(Vector3(0.03, 0.6, 0.03), Color(0.2, 0.2, 0.2), _at(sp + Vector3(sx, 0.9, 0.2)))
		_batch.add_box(Vector3(1.1, 0.04, 0.6), col, _at(sp + Vector3(0, 1.2, 0.05)))
		_batch.add_box(Vector3(0.8, 0.22, 0.03), Color(0.98, 0.96, 0.9), _at(sp + Vector3(0, 1.34, 0.3)))
		var l := Label3D.new()
		l.text = tr("rival.%d" % (i % 5 + 1))
		l.font = UiTheme.font()
		l.font_size = 64
		l.pixel_size = 0.0028
		l.modulate = col.darkened(0.2)
		l.position = Vector3(0, 1.34, 0.32)
		st.add_child(l)
		var vendor_id := "souq-woman" if i % 2 != 0 else "souq-man"
		var vendor := ModelLib.spawn_guest(vendor_id, st, Vector3(0, 0, -0.45))
		if vendor:
			ModelLib.play_loop(vendor, "idle")
		i += 1

# ---------------------------------------------------------------- time of day

func set_time(hour: float, weather_id: String) -> void:
	var w: Dictionary = Data.WEATHER[weather_id]
	var day_factor := 1.0
	if hour > 17.0:
		day_factor = clampf(1.0 - (hour - 17.0) / 5.0, 0.12, 1.0)
	var sky: Color = w["sky"]
	var night_sky := Color(0.07, 0.08, 0.17)
	var e := env.environment
	e.background_color = sky.lerp(night_sky, 1.0 - day_factor)
	# Compatibility/WebGL has no filmic tonemapping. Keep whites below clipping so
	# plaster, paving and food retain their colour on Safari as well as native.
	e.ambient_light_color = Color("bccbd0").lerp(Color("617696"), 1.0 - day_factor)
	e.ambient_light_energy = lerpf(0.32, 0.52, day_factor)
	var warm := Color(1.0, 0.95, 0.88)
	var dusk := Color(1.0, 0.65, 0.4)
	var night := Color(0.55, 0.6, 0.9)
	var dusk_t := clampf((hour - 17.0) / 2.5, 0.0, 1.0)
	var night_t := clampf((hour - 19.5) / 2.0, 0.0, 1.0)
	sun.light_color = warm.lerp(dusk, dusk_t).lerp(night, night_t)
	sun.light_energy = float(w["light"]) * lerpf(0.18, 0.78 if OS.has_feature("web") else 1.0, day_factor)
	sun.rotation_degrees.x = lerpf(-52.0, -20.0, dusk_t)
	var lamps_on := day_factor < 0.6 or weather_id == Data.BAD_WEATHER
	var sandstorm := weather_id == Data.BAD_WEATHER
	if _sand.visible != sandstorm:
		_sand.visible = sandstorm
		_sand.emitting = sandstorm
	for l in _lamps:
		l.visible = lamps_on
	if plot:
		plot.set_night(day_factor < 0.6 or sandstorm)

# ---------------------------------------------------------------- spawning

func set_customer_speed(value: float) -> void:
	customer_speed = value
	if plot:
		plot.simulation_speed = value
	if _level:
		for node in _level.get_children():
			if node is Customer:
				node.simulation_speed = value
				if value > 1.0 and node.bubble:
					node.bubble.visible = false

func spawn_walker(direction: int, potential_customer: bool = true, with_visuals: bool = true) -> Customer:
	var z := WALK_Z if potential_customer else NEAR_WALK_Z
	if Paving.DESIGNS.has(location_id):
		z = ARRIVAL_Z if potential_customer else PROMENADE_Z + 0.45
	var start := Vector3(-WALK_EDGE * direction, 0, z + randf_range(-0.1, 0.1))
	return spawn_guest(direction, start, potential_customer, with_visuals)

func spawn_guest(direction: int, start: Vector3, potential_customer: bool = true, with_visuals: bool = true) -> Customer:
	# Keep room for service actors when the promenade already has passersby.
	var limit := MAX_RIGGED_GUESTS if potential_customer else MAX_RIGGED_GUESTS - 2
	var rigged := with_visuals and _rigged_guests < limit
	if not rigged and not potential_customer:
		return null
	var c := Customer.new()
	c.simulation_speed = customer_speed
	c.on_promenade = Paving.DESIGNS.has(location_id)
	if plot:
		c.order_facing = plot.service_front(false)
		c.pickup_facing = plot.service_front(true)
	_level.add_child(c)
	var model_id := ""
	if rigged:
		var cast: Array = DISTRICT_CAST[location_id]
		if potential_customer:
			model_id = cast[_next_guest % cast.size()]
			_next_guest += 1
		else:
			model_id = cast[_next_passer % cast.size()]
			_next_passer += 1
		_rigged_guests += 1
	c.setup(model_id, direction, start, WALK_EDGE * direction, -1.25 * direction)
	if not potential_customer:
		c.decided = true
	walkers += 1
	c.gone.connect(func(_c):
		walkers -= 1
		if rigged:
			_rigged_guests -= 1)
	return c

func clear_virtual_walkers() -> void:
	for node in _level.get_children():
		if node is Customer and node.bubble == null:
			node._finish()

func queue_slot(index: int) -> Vector3:
	if plot != null and plot.has_method("queue_slot"):
		return plot.queue_slot(index)
	return CART_POS + Vector3(0.05 + 0.5 * index, 0, 0.42 + 0.02 * index)

## Where customers wait for their food after ordering (beside the counter, away from the line).
func pickup_slot(index: int) -> Vector3:
	if plot != null and plot.has_method("pickup_slot"):
		return plot.pickup_slot(index)
	return CART_POS + Vector3(-0.55 - 0.42 * (index % 4), 0, 0.5 + 0.3 * int(index / 4))

## Follow the staff hand during the offer, then carry the bag with the guest.
func handoff(customer: Customer) -> void:
	var actor := plot.server() if plot else null
	if actor == null or customer.model == null:
		return
	customer.face_point(actor.global_position)
	ModelLib.play_once(actor, "interact-right")
	var animation := ModelLib.animation_player(actor)
	if animation:
		animation.advance(0.0)
		animation.seek(0.45, true)
		animation.speed_scale = 1.6
	var bag := Node3D.new()
	_level.add_child(bag)
	var paper := Color("e6b574")
	ModelLib.box(bag, Vector3(0.126, 0.148, 0.078), Vector3.ZERO, paper)
	ModelLib.box(bag, Vector3(0.13, 0.023, 0.082), Vector3(0.0, 0.07, 0.0), paper.darkened(0.12))
	for z in [-0.04, 0.04]:
		ModelLib.box(bag, Vector3(0.065, 0.049, 0.003), Vector3(0.0, 0.0, z), Color("286458"))
	var offset := Vector3.DOWN * 0.062
	bag.global_position = ModelLib.hand_position(actor) + offset
	var truck := plot.stage == 2
	var motion := bag.create_tween()
	motion.tween_method(func(progress: float):
		if is_instance_valid(customer) and is_instance_valid(actor):
			var from := ModelLib.hand_position(actor)
			var to := ModelLib.hand_position(customer.model)
			var point := from.lerp(to, smoothstep(0.25, 0.8, progress)) + offset
			if truck:
				var z := (point.z - CART_POS.z) / FoodTruck.SCALE
				var lift := smoothstep(0.10, 0.23, z) * (1.0 - smoothstep(0.46, 0.58, z))
				point.y = lerpf(point.y, maxf(point.y, FoodTruck.SILL_Y * FoodTruck.SCALE + 0.08), lift)
			bag.global_position = point
		, 0.0, 1.0, 0.58)
	motion.tween_callback(func():
		if is_instance_valid(customer):
			customer.take_bag(bag)
		else:
			bag.queue_free())

## Redraw the stand from the game state (stations, stage). A stage that needs a
## different street gap rebuilds the whole location first.
func apply_visual() -> void:
	if visual_needs_reload():
		reload()
		return
	if location_id != "":
		frame_stage(_stage_at(location_id), true)
	if cart:
		var v: Dictionary = Game.legacy_visual()
		cart.apply_upgrades(v["upgrades"])
		cart.apply_vehicle(v["vehicle"])
	if plot != null:
		plot.apply(_plot_state_for(location_id))

## Game.plot_state() for today's place; a previewed other place gets its own stage and levels.
func _plot_state_for(id: String) -> Dictionary:
	var st: Dictionary = Game.plot_state()
	if id == Game.location or id == "":
		return st
	var tier := _stage_at(id)
	var store: Dictionary = Game.rig["stations"]
	if Game.plot_stage_tier(id) >= Game.FIXED_FROM_TIER and Game.plots.has(id):
		store = Game.plots[id]["stations"]
	var stations := {}
	for sid in Data.stage_def(tier)["stations"]:
		stations[sid] = int(store.get(sid, 0))
	return {"stage": tier, "stations": stations, "staff": {}, "events": {},
		"site": {"layout": Data.LOCATIONS[id]["layout"], "location": id}}

func spawn_car() -> void:
	if Paving.DESIGNS.has(location_id):
		return
	var dir := 1 if randf() < 0.5 else -1
	var car := Car.new()
	_level.add_child(car)
	var z := 0.22 if dir > 0 else -0.22
	car.setup("cars/" + CARS[randi() % CARS.size()], dir, Vector3(-HALF_W - 2.0 if dir > 0 else HALF_W + 2.0, 0, z), (HALF_W + 2.0) * dir)

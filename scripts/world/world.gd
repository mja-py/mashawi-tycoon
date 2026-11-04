class_name World
extends Node3D
## The 2.5D street. Builds a location from a layout, owns the camera, light,
## environment and the cart, and spawns walkers / cars for the simulation.

const SKYSCRAPERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c",
	"building-skyscraper-d", "building-skyscraper-e"]
const CARS := ["sedan", "sedan-sports", "hatchback-sports", "suv", "suv-luxury", "van", "delivery", "truck", "taxi", "police"]
const PEOPLE := ["female-a", "female-b", "female-c", "female-d", "female-e", "female-f",
	"male-a", "male-b", "male-c", "male-d", "male-e", "male-f"]
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
const CART_POS := Vector3(0.0, 0.0, -1.42)
const WALK_EDGE := 5.6
const MAX_WALKERS := 16
const BUILDING_ROT := 0.0
const ROAD_ROT := 0.0

var camera: Camera3D
## Orthographic camera size per plot stage (wider plots need more room).
const STAGE_CAM := [3.6, 3.9, 4.4, 5.0, 5.3, 5.6]
var _cam_base := Vector3.ZERO
var _cam_tween: Tween
var _drift := false
var _drift_t := 0.0
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
	camera.rotation_degrees = Vector3(-33, 14, 0)
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
	var size: float = STAGE_CAM[clampi(tier, 0, STAGE_CAM.size() - 1)]
	if _cam_tween:
		_cam_tween.kill()
	if not animate or absf(camera.size - size) < 0.01:
		camera.size = size
		return
	_cam_tween = create_tween()
	_cam_tween.tween_property(camera, "size", size, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Opening the stand: a short push-in towards the plot.
func push_in() -> void:
	var size: float = STAGE_CAM[clampi(_stage_at(location_id), 0, STAGE_CAM.size() - 1)]
	if _cam_tween:
		_cam_tween.kill()
	camera.size = size * 1.06
	_cam_tween = create_tween()
	_cam_tween.tween_property(camera, "size", size, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

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
	walkers = 0
	_level = Node3D.new()
	add_child(_level)
	_batch = MeshBatch.new()
	_rng.seed = hash(id)
	_gap = Plot.footprint(_stage_at(id))
	var layout: String = Data.LOCATIONS[id]["layout"]
	_build_ground(layout)
	match layout:
		"fahidi": _build_fahidi()
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
	var sidewalk := "roads/tile-low"
	var paving := ModelLib.flat_material(Color("c9b99e") if layout in ["fahidi", "gv"] else Color("b9c4bf"))
	var grass := Color(0.45, 0.66, 0.32)
	var sand := Color(0.91, 0.82, 0.58)
	var road_basis := Basis(Vector3.UP, deg_to_rad(ROAD_ROT))
	for x in range(-HALF_W, HALF_W + 1):
		_batch.add_model("roads/road-straight", Transform3D(road_basis, Vector3(x, 0, 0)))
		_batch.add_model(sidewalk, Transform3D(Basis.IDENTITY, Vector3(x, 0, -1)), paving)
		_batch.add_model(sidewalk, Transform3D(Basis.IDENTITY, Vector3(x, 0, 1)), paving)
		if layout in ["fahidi", "metro", "downtown", "gv", "mall"]:
			_batch.add_model(sidewalk, Transform3D(Basis.IDENTITY, Vector3(x, 0, -2)), paving)
	# big base plane so nothing shows the void
	var base_col := grass
	if layout in ["jbr", "fahidi"]:
		base_col = sand
	elif layout in ["downtown", "metro", "gv"]:
		base_col = Color(0.62, 0.62, 0.6)
	elif layout == "mall":
		base_col = Color(0.9, 0.88, 0.84)
	ModelLib.plane(_level, Vector2(40, 40), Vector3(0, -0.015, 0), base_col)
	if layout == "fahidi":
		ModelLib.plane(_level, Vector2(40, 3), Vector3(0, 0.005, 2.9), Color(0.9, 0.83, 0.65))

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

func _build_fahidi() -> void:
	# Al Fahidi: wind-tower lane
	_gulf_row(-3.4, 1.35, 0.5)
	GulfArch.mosque(_level, Vector3(4.5, 0, -4.6), 1.2)
	_gulf_row(FRONT_Z, 1.0, 0.45, 0.5)
	_lamp(-3.6, -0.62, 0)
	_lamp(3.6, -0.62, 0)
	_lamp(-1.8, 0.62, 180)
	_lamp(5.2, 0.62, 180)
	_side_prop("suburban/planter", Vector3(-2.4, 0, -1.3), 0)
	_side_prop("kaykit/bench", Vector3(2.6, 0, -1.3), 0, 1.5)
	_side_prop("nature/pot_large", Vector3(4.4, 0, -1.3), 0, 0.8)
	_palms_along(1.45, 6, 7.0, 0.0)
	_scenery("kaykit/bench", Vector3(0.6, 0, 1.4), 180, 1.5)
	for x in [-6.0, -3.5, 1.5, 4.0, 6.5]:
		_scenery("nature/plant_bushSmall", Vector3(x, 0, 2.3), _rng.randf() * 360, 0.6)

func _build_creek() -> void:
	# Creek Park: lawn, palms and the creek behind
	ModelLib.plane(_level, Vector2(40, 4), Vector3(0, 0.004, -3.5), Color(0.42, 0.64, 0.3))
	ModelLib.plane(_level, Vector2(40, 8), Vector3(0, 0.008, -9.0), Color(0.3, 0.6, 0.78))
	ModelLib.plane(_level, Vector2(40, 0.3), Vector3(0, 0.012, -5.2), Color(0.88, 0.84, 0.7))
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
	_side_prop("kaykit/bush", Vector3(-2.4, 0, -1.3), 0, 1.3)
	_side_prop("kaykit/bush", Vector3(2.5, 0, -1.3), 0, 1.3)
	_lamp(-3.2, -0.62, 0, "roads/light-square")
	_lamp(3.2, -0.62, 0, "roads/light-square")
	_lamp(-1.2, 0.62, 180, "roads/light-square")
	_palms_along(1.45, 4, 6.0, 1.0)

func _build_metro() -> void:
	# Metro: the gold shell station with towers behind
	_skyline(SKYSCRAPERS + ["building-k", "building-l", "building-m"], -3.6, 1.5)
	var st := Node3D.new()
	# the station steps back when a kiosk stands in front of it
	st.position = Vector3(0, 0, -2.6 if _gap <= 0.0 else -3.5)
	_level.add_child(st)
	var gold := Color(0.85, 0.7, 0.35)
	ModelLib.box(st, Vector3(4.4, 0.9, 1.6), Vector3(0, 0.45, 0), Color(0.55, 0.7, 0.85))
	var shell := ModelLib.cylinder(st, 0.95, 4.6, Vector3(0, 0.85, 0), gold)
	shell.rotation.z = PI / 2
	shell.scale = Vector3(1, 1, 0.75)
	# ticket booth off to the side so the stand never pokes into it
	ModelLib.box(st, Vector3(1.2, 0.5, 0.5), Vector3(2.4, 0.25, 0.95), gold)
	ModelLib.box(st, Vector3(0.9, 0.35, 0.04), Vector3(2.4, 0.2, 1.21), Color(0.25, 0.3, 0.38))
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

func _build_jbr() -> void:
	# JBR: sand, sea, parasols and the towers across the bay
	ModelLib.plane(_level, Vector2(40, 8), Vector3(0, 0.003, -2.4), Color(0.93, 0.85, 0.62))
	ModelLib.plane(_level, Vector2(60, 10), Vector3(0, 0.01, -8.3), Color(0.25, 0.62, 0.85))
	ModelLib.plane(_level, Vector2(40, 0.25), Vector3(0, 0.015, -3.4), Color(0.85, 0.93, 0.95))
	for i in range(8):
		var x := -8.0 + i * 2.2 + _rng.randf_range(-0.3, 0.3)
		_scenery("buildings/" + _pick(SKYSCRAPERS), Vector3(x, 0, -12.5), 0, 1.4)
	_palms_along(-2.0, 9, 7.5, 1.0)
	for i in range(6):
		_scenery(_pick(["buildings/detail-parasol-a", "buildings/detail-parasol-b"]),
			Vector3(_rng.randf_range(-7.0, 7.0), 0, _rng.randf_range(-3.2, -2.5)), _rng.randf() * 360, 1.0)
	_lamp(-3.0, -0.62, 0)
	_lamp(3.0, -0.62, 0)
	_scenery("kaykit/bench", Vector3(-1.5, 0, 1.4), 180, 1.5)
	_palms_along(1.45, 4, 6.0, 1.0)

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
	# Mall food court: marble floor, shop fronts, planters and skylight columns
	ModelLib.plane(_level, Vector2(40, 10), Vector3(0, 0.004, -5.0), Color(0.93, 0.91, 0.87))
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
		var vendor := ModelLib.spawn("gulf:male" if i % 2 == 0 else "people/character-male-%s" % ["a", "c", "e"][i % 3], st, Vector3(0, 0, -0.45), 0, 0.62)
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

func spawn_walker(direction: int, potential_customer: bool = true) -> Customer:
	var c := Customer.new()
	_level.add_child(c)
	var z := WALK_Z if potential_customer else NEAR_WALK_Z
	var start := Vector3(-WALK_EDGE if direction > 0 else WALK_EDGE, 0, z + randf_range(-0.1, 0.1))
	# a Dubai mix: Emirati locals in kandura and abaya alongside residents and tourists
	var model := "people/character-%s" % PEOPLE[randi() % PEOPLE.size()]
	if randf() < 0.45:
		model = "gulf:female" if randf() < 0.5 else "gulf:male"
	c.setup(model, direction, start, -start.x, -1.25 * direction)
	if not potential_customer:
		c.decided = true
	walkers += 1
	c.gone.connect(func(_c): walkers -= 1)
	return c

func queue_slot(index: int) -> Vector3:
	if plot != null and plot.has_method("queue_slot"):
		return plot.queue_slot(index)
	return CART_POS + Vector3(0.05 + 0.5 * index, 0, 0.42 + 0.02 * index)

## Where customers wait for their food after ordering (beside the counter, away from the line).
func pickup_slot(index: int) -> Vector3:
	if plot != null and plot.has_method("pickup_slot"):
		return plot.pickup_slot(index)
	return CART_POS + Vector3(-0.55 - 0.42 * (index % 4), 0, 0.5 + 0.3 * int(index / 4))

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
	var dir := 1 if randf() < 0.5 else -1
	var car := Car.new()
	_level.add_child(car)
	var z := 0.22 if dir > 0 else -0.22
	car.setup("cars/" + CARS[randi() % CARS.size()], dir, Vector3(-HALF_W - 2.0 if dir > 0 else HALF_W + 2.0, 0, z), (HALF_W + 2.0) * dir)

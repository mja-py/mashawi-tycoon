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
var sun: DirectionalLight3D
var env: WorldEnvironment
var cart: MashawiStand
var location_id := ""
var _level: Node3D
var _lamps: Array[OmniLight3D] = []
var _rng := RandomNumberGenerator.new()
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
	_sand.amount = 500
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
	var target := Vector3(0.2, 0.3, -0.85)
	camera.position = target + camera.transform.basis.z * 22.0
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
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.2
	env.environment = e
	add_child(env)

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
	_rng.seed = hash(id)
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
	cart = MashawiStand.new()
	cart.position = CART_POS
	cart.scale = Vector3.ONE * MashawiStand.CART_SCALE
	_level.add_child(cart)
	cart.apply_upgrades(Game.upgrades)
	cart.apply_vehicle(Game.vehicle)
	if float(Data.LOCATIONS[id].get("competition", 0.0)) > 0.0:
		_rival_stalls()
	set_time(Data.location_hours(id)[0], Game.weather)

func _pick(arr: Array) -> String:
	return arr[_rng.randi_range(0, arr.size() - 1)]

func _pick_any(arr: Array) -> Variant:
	return arr[_rng.randi_range(0, arr.size() - 1)]

func _build_ground(layout: String) -> void:
	var sidewalk := "roads/tile-low"
	var grass := Color(0.45, 0.66, 0.32)
	var sand := Color(0.91, 0.82, 0.58)
	for x in range(-HALF_W, HALF_W + 1):
		ModelLib.spawn("roads/road-straight", _level, Vector3(x, 0, 0), ROAD_ROT)
		ModelLib.spawn(sidewalk, _level, Vector3(x, 0, -1), 0)
		ModelLib.spawn(sidewalk, _level, Vector3(x, 0, 1), 0)
		if layout in ["fahidi", "metro", "downtown", "gv", "mall"]:
			ModelLib.spawn(sidewalk, _level, Vector3(x, 0, -2), 0)
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
	var n := ModelLib.spawn(model, _level, Vector3(x, 0, z), rot)
	var l := OmniLight3D.new()
	l.position = Vector3(x, 0.66, z + (0.18 if rot == 0.0 else -0.18))
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 1.4
	l.omni_range = 2.4
	l.visible = false
	_level.add_child(l)
	_lamps.append(l)

## Packs buildings side by side so their fronts line up on `front_z`.
func _fitted_row(models: Array, front_z: float, scale: float = 1.0, gap: float = 0.06) -> void:
	var x := -HALF_W - 1.5
	var last := ""
	while x <= HALF_W + 1.5:
		var m := _pick(models)
		if m == last and models.size() > 1:
			m = _pick(models)
		last = m
		var dims: Array = BUILDING_DIMS.get(m, [1.0, 1.0])
		var w: float = float(dims[0]) * scale
		var d: float = float(dims[1]) * scale
		ModelLib.spawn("buildings/" + m, _level, Vector3(x + w / 2.0, 0, front_z - d / 2.0), BUILDING_ROT, scale)
		x += w + gap

func _skyline(models: Array, z: float, scale: float) -> void:
	_fitted_row(models, z, scale, 0.1)

# ---------------------------------------------------------------- Gulf architecture

const SAND := Color(0.93, 0.87, 0.74)
const WHITE_WASH := Color(0.96, 0.94, 0.88)
const OCHRE := Color(0.87, 0.75, 0.57)
const PALMS := ["nature/tree_palm", "nature/tree_palmBend", "nature/tree_palmTall", "nature/tree_palmShort", "nature/tree_palmDetailedTall"]

## A traditional Gulf house: plastered box, parapet, arched windows, teak beams,
## optionally a barjeel (wind tower) on the roof and a shop awning at the door.
func _gulf_building(pos: Vector3, w: float, d: float, h: float, tone: Color, tower: bool, awning: bool = false) -> Node3D:
	var b := Node3D.new()
	b.position = pos
	_level.add_child(b)
	var dark := tone.darkened(0.25)
	var wood := Color(0.42, 0.27, 0.15)
	ModelLib.box(b, Vector3(w, h, d), Vector3(0, h / 2.0, 0), tone)
	# parapet with crenellations
	for sx in [-1.0, 1.0]:
		ModelLib.box(b, Vector3(0.05, 0.08, d), Vector3(sx * (w / 2.0 - 0.025), h + 0.04, 0), dark)
	for sz in [-1.0, 1.0]:
		ModelLib.box(b, Vector3(w, 0.08, 0.05), Vector3(0, h + 0.04, sz * (d / 2.0 - 0.025)), dark)
	var n := int(w / 0.16)
	for i in range(n):
		if i % 2 == 0:
			ModelLib.box(b, Vector3(0.08, 0.06, 0.05), Vector3(-w / 2.0 + 0.08 + i * 0.16, h + 0.11, d / 2.0 - 0.025), dark)
	# teak beams poking out under the roof line
	for i in range(int(w / 0.2)):
		var beam := ModelLib.cylinder(b, 0.015, 0.1, Vector3(-w / 2.0 + 0.1 + i * 0.2, h - 0.12, d / 2.0 + 0.03), wood)
		beam.rotation.x = PI / 2
	# arched windows on the front, two floors
	var floors := maxi(1, int(h / 0.45))
	var cols := maxi(1, int(w / 0.3))
	for f in range(floors):
		for c in range(cols):
			var x := -w / 2.0 + (c + 0.5) * (w / cols)
			var y := 0.22 + f * (h / floors)
			if f == 0 and c == cols / 2:
				continue
			ModelLib.box(b, Vector3(0.1, 0.16, 0.02), Vector3(x, y, d / 2.0 + 0.005), Color(0.25, 0.3, 0.38))
			var arch := ModelLib.cylinder(b, 0.05, 0.02, Vector3(x, y + 0.08, d / 2.0 + 0.005), Color(0.25, 0.3, 0.38))
			arch.rotation.x = PI / 2
			ModelLib.box(b, Vector3(0.14, 0.02, 0.04), Vector3(x, y - 0.09, d / 2.0 + 0.015), WHITE_WASH)
	# arched door
	var dx := -w / 2.0 + (cols / 2 + 0.5) * (w / cols)
	ModelLib.box(b, Vector3(0.16, 0.3, 0.02), Vector3(dx, 0.15, d / 2.0 + 0.005), wood)
	var da := ModelLib.cylinder(b, 0.08, 0.02, Vector3(dx, 0.3, d / 2.0 + 0.005), wood)
	da.rotation.x = PI / 2
	if awning:
		var can := ModelLib.box(b, Vector3(0.5, 0.03, 0.28), Vector3(dx, 0.5, d / 2.0 + 0.14), _pick_any([Color(0.55, 0.14, 0.16), Color(0.2, 0.45, 0.5), Color(0.85, 0.6, 0.2)]))
		can.rotation.x = deg_to_rad(12)
	if tower:
		var tx := w / 2.0 - 0.2
		var tz := -d / 2.0 + 0.2
		var th := 0.55
		ModelLib.box(b, Vector3(0.3, th, 0.3), Vector3(tx, h + th / 2.0, tz), tone.lightened(0.05))
		for side in range(4):
			for k in range(3):
				var off := -0.09 + k * 0.09
				var sp := Vector3(tx + off, h + th / 2.0, tz + 0.155) if side < 2 else Vector3(tx + 0.155, h + th / 2.0, tz + off)
				if side == 1:
					sp.z = tz - 0.155
				if side == 3:
					sp.x = tx - 0.155
				ModelLib.box(b, Vector3(0.02, th - 0.1, 0.02), sp, dark)
		ModelLib.box(b, Vector3(0.36, 0.05, 0.36), Vector3(tx, h + th + 0.025, tz), dark)
	return b

## A row of Gulf houses packed along X with their fronts on front_z.
func _gulf_row(front_z: float, scale: float = 1.0, towers: float = 0.45, awnings: float = 0.0) -> void:
	var x := -HALF_W - 1.5
	while x <= HALF_W + 1.5:
		var w := _rng.randf_range(0.8, 1.5) * scale
		var d := _rng.randf_range(0.8, 1.1) * scale
		var h := _rng.randf_range(0.8, 1.35) * scale
		var tone: Color = _pick_any([SAND, WHITE_WASH, OCHRE, SAND])
		_gulf_building(Vector3(x + w / 2.0, 0, front_z - d / 2.0), w, d, h, tone, _rng.randf() < towers, _rng.randf() < awnings)
		x += w + 0.08

func _mosque(pos: Vector3, scale: float = 1.0) -> void:
	var m := Node3D.new()
	m.position = pos
	m.scale = Vector3.ONE * scale
	_level.add_child(m)
	ModelLib.box(m, Vector3(1.6, 0.7, 1.2), Vector3(0, 0.35, 0), WHITE_WASH)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	dome.mesh = sm
	dome.material_override = ModelLib.flat_material(Color(0.35, 0.65, 0.6))
	dome.position = Vector3(0, 0.7, 0)
	m.add_child(dome)
	ModelLib.cylinder(m, 0.03, 0.3, Vector3(0, 1.3, 0), Color(0.85, 0.7, 0.3))
	for sx in [-0.95, 0.95]:
		ModelLib.cylinder(m, 0.09, 1.9, Vector3(sx, 0.95, 0.4), WHITE_WASH)
		ModelLib.cylinder(m, 0.13, 0.08, Vector3(sx, 1.6, 0.4), Color(0.35, 0.65, 0.6))
		var cap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.11
		cm.height = 0.3
		cap.mesh = cm
		cap.material_override = ModelLib.flat_material(Color(0.35, 0.65, 0.6))
		cap.position = Vector3(sx, 2.0, 0.4)
		m.add_child(cap)

func _burj(pos: Vector3) -> void:
	var b := Node3D.new()
	b.position = pos
	_level.add_child(b)
	var glass := Color(0.72, 0.8, 0.9)
	var tiers := [[0.5, 0.9], [0.36, 0.8], [0.25, 0.7], [0.15, 0.6], [0.08, 0.5]]
	var y := 0.0
	for t in tiers:
		var r: float = t[0]
		var h: float = t[1]
		ModelLib.cylinder(b, r, h, Vector3(0, y + h / 2.0, 0), glass)
		for k in range(3):
			var a := k * TAU / 3.0
			ModelLib.cylinder(b, r * 0.55, h * 0.75, Vector3(cos(a) * r * 0.8, y + h * 0.375, sin(a) * r * 0.8), glass.darkened(0.08))
		y += h
	var spire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.08
	cm.height = 1.0
	spire.mesh = cm
	spire.material_override = ModelLib.flat_material(Color(0.8, 0.85, 0.92))
	spire.position = Vector3(0, y + 0.5, 0)
	b.add_child(spire)

func _palms_along(z: float, count: int, spread: float = 7.5, min_x_gap: float = 1.4) -> void:
	for i in range(count):
		var x := -spread + (i + 0.5) * (2.0 * spread / count) + _rng.randf_range(-0.3, 0.3)
		if absf(x) < min_x_gap:
			continue
		ModelLib.spawn(_pick(PALMS), _level, Vector3(x, 0, z + _rng.randf_range(-0.1, 0.1)), _rng.randf() * 360, _rng.randf_range(0.65, 0.9))

# ---------------------------------------------------------------- locations

func _build_fahidi() -> void:
	# Al Fahidi: wind-tower lane
	_gulf_row(-3.4, 1.35, 0.5)
	_mosque(Vector3(4.5, 0, -4.6), 1.2)
	_gulf_row(FRONT_Z, 1.0, 0.45, 0.5)
	_lamp(-3.6, -0.62, 0)
	_lamp(3.6, -0.62, 0)
	_lamp(-1.8, 0.62, 180)
	_lamp(5.2, 0.62, 180)
	ModelLib.spawn("suburban/planter", _level, Vector3(-2.4, 0, -1.3), 0)
	ModelLib.spawn("kaykit/bench", _level, Vector3(2.6, 0, -1.3), 0, 1.5)
	ModelLib.spawn("nature/pot_large", _level, Vector3(4.4, 0, -1.3), 0, 0.8)
	_palms_along(1.45, 6, 7.0, 0.0)
	ModelLib.spawn("kaykit/bench", _level, Vector3(0.6, 0, 1.4), 180, 1.5)
	for x in [-6.0, -3.5, 1.5, 4.0, 6.5]:
		ModelLib.spawn("nature/plant_bushSmall", _level, Vector3(x, 0, 2.3), _rng.randf() * 360, 0.6)

func _build_creek() -> void:
	# Creek Park: lawn, palms and the creek behind
	ModelLib.plane(_level, Vector2(40, 4), Vector3(0, 0.004, -3.5), Color(0.42, 0.64, 0.3))
	ModelLib.plane(_level, Vector2(40, 8), Vector3(0, 0.008, -9.0), Color(0.3, 0.6, 0.78))
	ModelLib.plane(_level, Vector2(40, 0.3), Vector3(0, 0.012, -5.2), Color(0.88, 0.84, 0.7))
	var fx := -HALF_W - 0.5
	while fx <= HALF_W + 0.5:
		if absf(fx) > 1.9:
			ModelLib.spawn("nature/fence_simple", _level, Vector3(fx, 0, -1.85), 0)
		fx += 1.0
	var placed: Array[Vector3] = []
	var tries := 0
	while placed.size() < 18 and tries < 300:
		tries += 1
		var x := _rng.randf_range(-8.5, 8.5)
		var z := _rng.randf_range(-4.8, -2.1)
		if absf(x) < 1.6 and z > -2.9:
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
			ModelLib.spawn(_pick(PALMS), _level, Vector3(x, 0, z), _rng.randf() * 360, _rng.randf_range(0.7, 1.0))
		else:
			ModelLib.spawn(_pick(["nature/tree_oak", "nature/tree_fat", "nature/tree_detailed"]), _level, Vector3(x, 0, z), _rng.randf() * 360, _rng.randf_range(0.6, 0.85))
	for i in range(18):
		ModelLib.spawn(_pick(["nature/plant_bush", "nature/plant_bushSmall", "nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA", "nature/grass_large"]),
			_level, Vector3(_rng.randf_range(-7.5, 7.5), 0, _rng.randf_range(-2.4, -1.95)), _rng.randf() * 360, _rng.randf_range(0.5, 0.75))
	for i in range(4):
		ModelLib.spawn(_pick(["kaykit/rock_single_A", "kaykit/rock_single_B"]), _level, Vector3(_rng.randf_range(-8.0, 8.0), 0, _rng.randf_range(-4.5, -2.3)), _rng.randf() * 360, 0.8)
	for bx in [-3.4, 3.6]:
		ModelLib.spawn("kaykit/bench", _level, Vector3(bx, 0, -1.3), 0, 1.5)
	ModelLib.spawn("kaykit/bush", _level, Vector3(-2.4, 0, -1.3), 0, 1.3)
	ModelLib.spawn("kaykit/bush", _level, Vector3(2.5, 0, -1.3), 0, 1.3)
	_lamp(-3.2, -0.62, 0, "roads/light-square")
	_lamp(3.2, -0.62, 0, "roads/light-square")
	_lamp(-1.2, 0.62, 180, "roads/light-square")
	_palms_along(1.45, 4, 6.0, 1.0)

func _build_metro() -> void:
	# Metro: the gold shell station with towers behind
	_skyline(SKYSCRAPERS + ["building-k", "building-l", "building-m"], -3.6, 1.5)
	var st := Node3D.new()
	st.position = Vector3(0, 0, -2.6)
	_level.add_child(st)
	var gold := Color(0.85, 0.7, 0.35)
	ModelLib.box(st, Vector3(4.4, 0.9, 1.6), Vector3(0, 0.45, 0), Color(0.55, 0.7, 0.85))
	var shell := ModelLib.cylinder(st, 0.95, 4.6, Vector3(0, 0.85, 0), gold)
	shell.rotation.z = PI / 2
	shell.scale = Vector3(1, 1, 0.75)
	ModelLib.box(st, Vector3(1.2, 0.5, 0.5), Vector3(0, 0.25, 0.95), gold)
	ModelLib.box(st, Vector3(0.9, 0.35, 0.04), Vector3(0, 0.2, 1.21), Color(0.25, 0.3, 0.38))
	for sx in [-1.9, 1.9]:
		_gulf_building(Vector3(sx * 2.0, 0, FRONT_Z - 0.6), 1.4, 1.2, 1.2, WHITE_WASH, false)
	ModelLib.spawn("roads/road-sign-street", _level, Vector3(-2.5, 0, -0.62), 0)
	ModelLib.spawn("roads/traffic-light", _level, Vector3(5.5, 0, -0.62), 0)
	ModelLib.spawn("roads/traffic-light", _level, Vector3(-6.2, 0, 0.62), 180)
	_lamp(2.6, -0.62, 0, "roads/light-square")
	_lamp(-5.0, -0.62, 0, "roads/light-square")
	_lamp(0.8, 0.62, 180, "roads/light-square")
	ModelLib.spawn("cars/taxi", _level, Vector3(3.6, 0, 0.3), 90, 0.21)
	ModelLib.spawn("cars/taxi", _level, Vector3(4.4, 0, 0.3), 90, 0.21)
	ModelLib.spawn("kaykit/bench", _level, Vector3(-3.6, 0, -1.3), 0, 1.5)
	_palms_along(1.45, 5, 6.5, 1.0)

func _build_jbr() -> void:
	# JBR: sand, sea, parasols and the towers across the bay
	ModelLib.plane(_level, Vector2(40, 8), Vector3(0, 0.003, -2.4), Color(0.93, 0.85, 0.62))
	ModelLib.plane(_level, Vector2(60, 10), Vector3(0, 0.01, -8.3), Color(0.25, 0.62, 0.85))
	ModelLib.plane(_level, Vector2(40, 0.25), Vector3(0, 0.015, -3.4), Color(0.85, 0.93, 0.95))
	for i in range(8):
		var x := -8.0 + i * 2.2 + _rng.randf_range(-0.3, 0.3)
		ModelLib.spawn("buildings/" + _pick(SKYSCRAPERS), _level, Vector3(x, 0, -12.5), 0, 1.4)
	_palms_along(-2.0, 9, 7.5, 1.0)
	for i in range(6):
		ModelLib.spawn(_pick(["buildings/detail-parasol-a", "buildings/detail-parasol-b"]), _level,
			Vector3(_rng.randf_range(-7.0, 7.0), 0, _rng.randf_range(-3.2, -2.5)), _rng.randf() * 360, 1.0)
	_lamp(-3.0, -0.62, 0)
	_lamp(3.0, -0.62, 0)
	ModelLib.spawn("kaykit/bench", _level, Vector3(-1.5, 0, 1.4), 180, 1.5)
	_palms_along(1.45, 4, 6.0, 1.0)

func _build_downtown() -> void:
	_burj(Vector3(4.6, 0, -2.5))
	_skyline(SKYSCRAPERS, -3.6, 1.6)
	_fitted_row(SKYSCRAPERS + ["building-k", "building-l", "building-m", "building-i"], FRONT_Z)
	_lamp(-4.2, -0.62, 0, "roads/light-curved-double")
	_lamp(4.2, -0.62, 0, "roads/light-curved-double")
	_lamp(-1.6, 0.62, 180, "roads/light-square")
	_lamp(2.0, 0.62, 180, "roads/light-square")
	ModelLib.spawn("roads/traffic-light", _level, Vector3(6.0, 0, -0.62), 0)
	ModelLib.spawn("suburban/planter", _level, Vector3(-2.6, 0, -1.3), 0)
	ModelLib.spawn("kaykit/bench", _level, Vector3(2.6, 0, -1.3), 0, 1.5)
	ModelLib.spawn("kaykit/bench", _level, Vector3(-4.4, 0, 1.4), 180, 1.5)
	_palms_along(1.45, 5, 6.5, 1.0)
	ModelLib.spawn("cars/taxi", _level, Vector3(-4.0, 0, 0.3), 90, 0.21)

func _build_mall() -> void:
	# Mall food court: marble floor, shop fronts, planters and skylight columns
	ModelLib.plane(_level, Vector2(40, 10), Vector3(0, 0.004, -5.0), Color(0.93, 0.91, 0.87))
	var x := -HALF_W - 1.5
	var shop_cols := [Color(0.85, 0.3, 0.25), Color(0.25, 0.5, 0.75), Color(0.3, 0.65, 0.45), Color(0.9, 0.65, 0.2), Color(0.55, 0.35, 0.65)]
	var k := 0
	while x <= HALF_W + 1.5:
		var w := _rng.randf_range(1.4, 2.2)
		var sh := Node3D.new()
		sh.position = Vector3(x + w / 2.0, 0, FRONT_Z - 0.6)
		_level.add_child(sh)
		ModelLib.box(sh, Vector3(w, 1.5, 1.2), Vector3(0, 0.75, 0), Color(0.96, 0.95, 0.92))
		ModelLib.box(sh, Vector3(w - 0.2, 0.9, 0.04), Vector3(0, 0.5, 0.61), Color(0.6, 0.75, 0.9, 0.9))
		ModelLib.box(sh, Vector3(w - 0.1, 0.25, 0.06), Vector3(0, 1.2, 0.62), shop_cols[k % shop_cols.size()])
		ModelLib.box(sh, Vector3(w, 0.06, 1.3), Vector3(0, 1.53, 0.0), Color(0.8, 0.8, 0.8))
		x += w + 0.1
		k += 1
	for cx in [-6.0, -2.0, 2.0, 6.0]:
		ModelLib.cylinder(_level, 0.08, 1.9, Vector3(cx, 0.95, -0.62), Color(0.88, 0.88, 0.86))
		ModelLib.spawn("nature/pot_large", _level, Vector3(cx + 0.5, 0, 1.4), 0, 0.8)
		ModelLib.spawn("nature/tree_palmShort", _level, Vector3(cx + 0.5, 0.12, 1.4), 0, 0.5)
	for bx in [-4.2, 4.4]:
		ModelLib.spawn("kaykit/bench", _level, Vector3(bx, 0, 1.4), 180, 1.5)

func _build_gv() -> void:
	# Global Village: souk stalls, lanterns and Gulf facades
	_gulf_row(-3.4, 1.3, 0.4)
	_gulf_row(FRONT_Z, 1.0, 0.3, 0.6)
	for x in [-5.2, -3.0, 3.0, 5.2]:
		var st := Node3D.new()
		st.position = Vector3(x, 0, -1.4)
		_level.add_child(st)
		ModelLib.box(st, Vector3(0.9, 0.5, 0.5), Vector3(0, 0.25, 0), Color(0.3, 0.25, 0.2))
		ModelLib.box(st, Vector3(1.0, 0.04, 0.7), Vector3(0, 0.95, 0), _pick_any([Color(0.85, 0.35, 0.2), Color(0.25, 0.55, 0.75), Color(0.9, 0.7, 0.2)]))
		for sx in [-0.45, 0.45]:
			ModelLib.box(st, Vector3(0.03, 0.5, 0.03), Vector3(sx, 0.7, 0.3), Color(0.2, 0.2, 0.2))
	for x in range(-HALF_W, HALF_W + 1):
		var col: Color = _pick_any([Color(1.0, 0.55, 0.2), Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.3)])
		ModelLib.cylinder(_level, 0.05, 0.08, Vector3(x + 0.5, 1.15 - absf(fmod(x, 2.0)) * 0.06, -0.55), col, 2.5)
		ModelLib.box(_level, Vector3(0.5, 0.008, 0.008), Vector3(x + 0.5, 1.25, -0.55), Color(0.2, 0.2, 0.2))
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
	for x in [-3.2, -5.6, 3.2, 5.6]:
		var st := Node3D.new()
		st.position = Vector3(x, 0, -1.45)
		_level.add_child(st)
		var col: Color = cols[i % cols.size()]
		ModelLib.box(st, Vector3(1.0, 0.5, 0.5), Vector3(0, 0.25, 0), col.darkened(0.3))
		ModelLib.box(st, Vector3(1.0, 0.12, 0.52), Vector3(0, 0.56, 0), Color(0.95, 0.92, 0.85))
		for sx in [-0.46, 0.46]:
			ModelLib.box(st, Vector3(0.03, 0.6, 0.03), Vector3(sx, 0.9, 0.2), Color(0.2, 0.2, 0.2))
		ModelLib.box(st, Vector3(1.1, 0.04, 0.6), Vector3(0, 1.2, 0.05), col)
		ModelLib.box(st, Vector3(0.8, 0.22, 0.03), Vector3(0, 1.34, 0.3), Color(0.98, 0.96, 0.9))
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
	e.ambient_light_color = e.background_color.lightened(0.3)
	e.ambient_light_energy = lerpf(0.35, 0.75, day_factor)
	var warm := Color(1.0, 0.95, 0.88)
	var dusk := Color(1.0, 0.65, 0.4)
	var night := Color(0.55, 0.6, 0.9)
	var dusk_t := clampf((hour - 17.0) / 2.5, 0.0, 1.0)
	var night_t := clampf((hour - 19.5) / 2.0, 0.0, 1.0)
	sun.light_color = warm.lerp(dusk, dusk_t).lerp(night, night_t)
	sun.light_energy = float(w["light"]) * lerpf(0.18, 1.0, day_factor)
	sun.rotation_degrees.x = lerpf(-52.0, -20.0, dusk_t)
	var lamps_on := day_factor < 0.6 or weather_id == Data.BAD_WEATHER
	var sandstorm := weather_id == Data.BAD_WEATHER
	if _sand.visible != sandstorm:
		_sand.visible = sandstorm
		_sand.emitting = sandstorm
	for l in _lamps:
		l.visible = lamps_on
	if cart:
		cart.set_night(day_factor < 0.6)

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
	return CART_POS + Vector3(0.05 + 0.5 * index, 0, 0.42 + 0.02 * index)

func spawn_car() -> void:
	var dir := 1 if randf() < 0.5 else -1
	var car := Car.new()
	_level.add_child(car)
	var z := 0.22 if dir > 0 else -0.22
	car.setup("cars/" + CARS[randi() % CARS.size()], dir, Vector3(-HALF_W - 2.0 if dir > 0 else HALF_W + 2.0, 0, z), (HALF_W + 2.0) * dir)

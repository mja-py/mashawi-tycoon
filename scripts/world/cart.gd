class_name MashawiStand
extends Node3D
## The player's mashawi stand, assembled from primitives plus food props.
## Faces +Z (towards the camera). Visuals react to purchased upgrades.

const CART_SCALE := 0.72
const CHAR_SCALE := 0.6 / CART_SCALE
var _spit: Node3D
var _vendor: Node3D
var _helper: Node3D
var _neon: Label3D
var _neon_light: OmniLight3D
var _awning_big: Node3D
var _speaker: Node3D
var _fridge: Node3D
var _seating: Node3D
var _body: Node3D
var _chassis: Array[Node3D] = []
var _truck: Node3D
var _roof: Node3D
var _vehicle := ""
var _upgrades: Dictionary = {}
var _sweets: Node3D
var _grill_glow: MeshInstance3D
var _serving := false

func _ready() -> void:
	_build()

func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var red := Color(0.52, 0.13, 0.16)
	var cream := Color(0.97, 0.92, 0.80)
	var wood := Color(0.50, 0.33, 0.18)
	var gold := Color(0.85, 0.66, 0.25)
	var dark := Color(0.16, 0.14, 0.13)
	# wheels
	for sx in [-0.5, 0.5]:
		var w := ModelLib.cylinder(_body, 0.11, 0.06, Vector3(sx, 0.11, 0.12), dark)
		w.rotation.z = PI / 2
		_chassis.append(w)
	# chassis + counter
	_chassis.append(ModelLib.box(_body, Vector3(1.1, 0.42, 0.55), Vector3(0, 0.34, 0), red))
	# food truck body (vehicle upgrade) sits behind the counter
	_truck = Node3D.new()
	_truck.visible = false
	add_child(_truck)
	# sweets display (upgrade)
	_sweets = Node3D.new()
	_sweets.visible = false
	add_child(_sweets)
	ModelLib.spawn("food/sweets-counter", _sweets, Vector3(1.1, 0.0, 0.15), 0, 2.2)
	ModelLib.box(_body, Vector3(1.1, 0.14, 0.56), Vector3(0, 0.48, 0), cream)
	ModelLib.box(_body, Vector3(1.2, 0.04, 0.66), Vector3(0, 0.57, 0), wood)
	ModelLib.box(_body, Vector3(1.22, 0.02, 0.03), Vector3(0, 0.585, 0.33), gold)
	ModelLib.box(_body, Vector3(1.12, 0.03, 0.02), Vector3(0, 0.42, 0.285), gold)
	# posts and roof (hidden when selling from a truck, which brings its own)
	_roof = Node3D.new()
	_body.add_child(_roof)
	for sx in [-0.52, 0.52]:
		for sz in [-0.25, 0.25]:
			ModelLib.box(_roof, Vector3(0.035, 0.6, 0.035), Vector3(sx, 0.88, sz), dark)
	var roof := ModelLib.box(_roof, Vector3(1.25, 0.05, 0.72), Vector3(0, 1.2, 0.0), red)
	roof.rotation.x = deg_to_rad(6)
	_stripes(roof, 1.25, 0.72)
	# big awning (upgrade)
	_awning_big = Node3D.new()
	_body.add_child(_awning_big)
	var canvas := ModelLib.box(_awning_big, Vector3(1.5, 0.04, 0.5), Vector3(0, 1.14, 0.58), red)
	canvas.rotation.x = deg_to_rad(14)
	_stripes(canvas, 1.5, 0.5)
	_awning_big.visible = false
	# menu board on the roof front
	ModelLib.box(_roof, Vector3(0.9, 0.22, 0.03), Vector3(0, 1.32, 0.36), cream)
	var title := _sign(_roof, Vector3(0, 1.32, 0.38), 72, 0.0028)
	# rotating spit
	_spit = Node3D.new()
	_spit.position = Vector3(-0.33, 0.59, -0.05)
	_body.add_child(_spit)
	if ModelLib.spawn("food/doner-spit", _spit, Vector3.ZERO, 0, 0.55) == null:
		ModelLib.cylinder(_spit, 0.085, 0.34, Vector3(0, 0.24, 0), Color(0.62, 0.36, 0.18))
	# heater behind the spit
	ModelLib.box(_body, Vector3(0.1, 0.42, 0.14), Vector3(-0.33, 0.82, -0.2), dark)
	ModelLib.box(_body, Vector3(0.06, 0.34, 0.02), Vector3(-0.33, 0.82, -0.125), Color(1.0, 0.45, 0.1), 2.0)
	# charcoal grill (mangal) with glowing coals and smoke
	ModelLib.box(_body, Vector3(0.42, 0.08, 0.3), Vector3(0.12, 0.63, -0.05), dark)
	_grill_glow = ModelLib.box(_body, Vector3(0.38, 0.01, 0.26), Vector3(0.12, 0.672, -0.05), Color(1.0, 0.4, 0.05), 1.5)
	for i in range(7):
		ModelLib.box(_body, Vector3(0.04, 0.03, 0.04), Vector3(-0.04 + (i % 4) * 0.09, 0.685, -0.12 + int(i / 4) * 0.12), Color(0.12, 0.1, 0.1), 0.0)
	var smoke := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.15, 0.01, 0.1)
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.alpha_curve = ct
	smoke.process_material = pm
	smoke.amount = 26
	smoke.lifetime = 1.8
	smoke.position = Vector3(0.12, 0.7, -0.05)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 0.85, 0.85, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	smoke.draw_pass_1 = sm
	_body.add_child(smoke)
	for i in range(4):
		var sk := ModelLib.spawn("food/skewer" if i % 2 == 0 else "food/skewer-vegetables", _body, Vector3(0.12, 0.69, -0.16 + i * 0.075), 0, 0.5)
		if sk:
			sk.rotation.y = deg_to_rad(90)
	# sodas and bread on the counter
	for i in range(4):
		ModelLib.spawn("food/soda-can", _body, Vector3(0.38 + (i % 2) * 0.08, 0.59, -0.18 + int(i / 2) * 0.09), 0, 0.3)
	ModelLib.spawn("food/pita-stack", _body, Vector3(0.42, 0.59, 0.14), 20, 0.5)
	ModelLib.spawn("food/salad-bowl", _body, Vector3(-0.1, 0.59, 0.18), 0, 0.42)
	ModelLib.spawn("food/charcoal-bag", _body, Vector3(0.62, 0.0, -0.1), -20, 0.7)
	ModelLib.spawn("food/mutton-skewer", _body, Vector3(-0.1, 0.595, -0.22), 90, 0.4)
	ModelLib.spawn("food/bottle-ketchup", _body, Vector3(-0.05, 0.59, 0.2), 0, 0.4)
	ModelLib.spawn("food/bottle-musterd", _body, Vector3(0.03, 0.59, 0.22), 0, 0.4)
	# neon sign (upgrade)
	_neon = Label3D.new()
	_neon.text = title.text
	_neon.font = UiTheme.font()
	_neon.font_size = 80
	_neon.pixel_size = 0.004
	_neon.modulate = Color(1.0, 0.25, 0.6)
	_neon.outline_modulate = Color(1.0, 0.7, 0.9)
	_neon.outline_size = 10
	_neon.position = Vector3(0, 1.62, 0.1)
	_neon.visible = false
	_body.add_child(_neon)
	_neon_light = OmniLight3D.new()
	_neon_light.light_color = Color(1.0, 0.4, 0.7)
	_neon_light.light_energy = 1.6
	_neon_light.omni_range = 2.2
	_neon_light.position = Vector3(0, 1.5, 0.5)
	_neon_light.visible = false
	_body.add_child(_neon_light)
	# speaker (upgrade)
	_speaker = Node3D.new()
	_body.add_child(_speaker)
	ModelLib.box(_speaker, Vector3(0.16, 0.26, 0.16), Vector3(0.72, 0.13, -0.1), dark)
	ModelLib.cylinder(_speaker, 0.05, 0.02, Vector3(0.72, 0.16, -0.01), Color(0.4, 0.4, 0.42)).rotation.x = PI / 2
	_speaker.visible = false
	# fridge (upgrade)
	_fridge = Node3D.new()
	_body.add_child(_fridge)
	ModelLib.box(_fridge, Vector3(0.34, 0.6, 0.34), Vector3(-0.85, 0.3, -0.45), Color(0.92, 0.94, 0.96))
	ModelLib.box(_fridge, Vector3(0.02, 0.2, 0.03), Vector3(-0.67, 0.35, -0.3), dark)
	_fridge.visible = false
	# seating (upgrade)
	_seating = Node3D.new()
	add_child(_seating)
	for sx in [-1.5, 1.5]:
		ModelLib.cylinder(_seating, 0.03, 0.4, Vector3(sx, 0.2, 0.1), dark)
		ModelLib.cylinder(_seating, 0.22, 0.03, Vector3(sx, 0.41, 0.1), cream)
		ModelLib.spawn("buildings/detail-parasol-a", _seating, Vector3(sx, 0.0, 0.1), 0, 1.0)
		for a in [0.0, 2.1, 4.2]:
			ModelLib.cylinder(_seating, 0.07, 0.03, Vector3(sx + cos(a) * 0.3, 0.24, 0.1 + sin(a) * 0.3), wood)
	_seating.visible = false
	# vendor
	# they stand at the ends of the counter so the roof never hides them
	_vendor = _spawn_person("gulf:female", Vector3(-0.82, 0.0, 0.12))
	_helper = _spawn_person("gulf:male", Vector3(0.84, 0.0, 0.12))
	if _vendor:
		_vendor.rotation.y = deg_to_rad(35)
	if _helper:
		_helper.rotation.y = deg_to_rad(-35)
	_helper.visible = false

func _stripes(roof: MeshInstance3D, w: float, d: float) -> void:
	var n := int(w / 0.18)
	for i in range(n):
		if i % 2 == 0:
			continue
		var s := ModelLib.box(roof, Vector3(0.18, 0.052, d), Vector3(-w / 2 + 0.09 + i * 0.18, 0.0, 0.0), Color(0.97, 0.93, 0.82))

func _spawn_person(model: String, pos: Vector3) -> Node3D:
	var n := ModelLib.spawn(model, self, pos, 0, CHAR_SCALE)
	if n:
		ModelLib.play_loop(n, "idle")
	return n

func apply_vehicle(vehicle: String) -> void:
	if vehicle == _vehicle:
		return
	_vehicle = vehicle
	for c in _truck.get_children():
		c.queue_free()
	var def: Dictionary = Data.VEHICLES.get(vehicle, {})
	var is_truck: bool = def.has("model")
	_truck.visible = is_truck
	_roof.visible = not is_truck
	for c in _chassis:
		c.visible = not is_truck
	if is_truck:
		var scale := 0.62 if vehicle == "truck" else 0.72
		ModelLib.spawn(def["model"], _truck, Vector3(0.0, 0.0, -0.75), 90, scale)
		# open serving window, awning and a maroon stripe on the side facing the counter
		var top := 0.95 if vehicle == "truck" else 1.15
		ModelLib.box(_truck, Vector3(0.95, 0.4, 0.04), Vector3(0, top - 0.42, -0.36), Color(0.15, 0.2, 0.3))
		ModelLib.box(_truck, Vector3(1.15, 0.08, 0.04), Vector3(0, 0.32, -0.36), Color(0.52, 0.13, 0.16))
		var aw := ModelLib.box(_truck, Vector3(1.2, 0.04, 0.5), Vector3(0, top, -0.1), Color(0.52, 0.13, 0.16))
		aw.rotation.x = deg_to_rad(12)
		_stripes(aw, 1.2, 0.5)
		ModelLib.box(_truck, Vector3(1.1, 0.26, 0.05), Vector3(0, top + 0.2, -0.6), Color(0.97, 0.92, 0.80))
		_sign(_truck, Vector3(0, top + 0.2, -0.57), 80, 0.0028)
		if vehicle == "truck2":
			ModelLib.box(_truck, Vector3(1.1, 0.03, 0.03), Vector3(0, top + 0.36, -0.58), Color(1.0, 0.25, 0.6), 2.0)
	# the neon sign sits above whatever roof is in use
	_neon.position = Vector3(0, (1.6 if vehicle == "truck" else 1.85) if is_truck else 1.62, 0.1)
	_neon_light.position.y = _neon.position.y - 0.1
	_update_width()

## Counter width follows the Bigger Stand upgrade and the vehicle; the crew and fridge
## stand just past the counter ends whatever the width.
func _update_width() -> void:
	var wide := 1.25 if _upgrades.has("cart2") else 1.0
	if _vehicle == "truck":
		wide = maxf(wide, 1.15)
	elif _vehicle == "truck2":
		wide = maxf(wide, 1.3)
	_body.scale.x = wide
	if _vendor:
		_vendor.position.x = -(0.62 * wide + 0.22)
	if _helper:
		_helper.position.x = 0.62 * wide + 0.24
	if _fridge:
		_fridge.position.x = -(0.62 * wide + 0.3) + 0.85 - 0.62

## The stand's name board (roof or truck).
func _sign(parent: Node3D, pos: Vector3, font_size: int, pixel_size: float) -> Label3D:
	var l := Label3D.new()
	l.text = tr("ui.sign")
	l.font = UiTheme.font()
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = Color(0.45, 0.1, 0.1)
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	return l

func apply_upgrades(upgrades: Dictionary) -> void:
	_upgrades = upgrades
	_sweets.visible = upgrades.has("sweets")
	_awning_big.visible = upgrades.has("awning")
	_neon.visible = upgrades.has("neon")
	_speaker.visible = upgrades.has("speaker")
	_fridge.visible = upgrades.has("fridge") or upgrades.has("fridge2")
	_seating.visible = upgrades.has("seating")
	_helper.visible = upgrades.has("helper")
	_update_width()

func set_night(is_night: bool) -> void:
	_neon_light.visible = is_night and _neon.visible
	_neon.outline_size = 16 if is_night else 6

func set_serving(on: bool) -> void:
	if on == _serving:
		return
	_serving = on
	if _vendor:
		ModelLib.play_loop(_vendor, "interact-right" if on else "idle", 1.4 if on else 1.0)
	if _helper and _helper.visible:
		ModelLib.play_loop(_helper, "pick-up" if on else "idle", 1.2 if on else 1.0)

func _process(delta: float) -> void:
	if _spit:
		_spit.rotation.y += delta * 1.2

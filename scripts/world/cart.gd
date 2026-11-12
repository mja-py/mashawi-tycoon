class_name MashawiStand
extends Node3D
## The player's mashawi stand, assembled from primitives plus food props.
## Faces +Z (towards the camera). Visuals react to purchased upgrades.

const CART_SCALE := 0.72
const CREW_HEIGHT := 0.64 / CART_SCALE
var _spit: Node3D
var _spit_rotor: Node3D
var _vendor: Node3D
var _helper: Node3D
var _neon: Label3D
var _neon_on := false
## Painted name boards (cart roof, truck); hidden while the neon replaces them.
var _title: Label3D
var _neon_light: OmniLight3D
var _awning_big: Node3D
var _speaker: Node3D
var _fridge: Node3D
var _seating: Node3D
var _body: Node3D
var _chassis: Array[Node3D] = []
var _wheels: Array[Node3D] = []
var _skirt: Node3D
## Stage 1 (stall): wheels off, the plot's canopy replaces the roof.
var stall := false
## Called with set_serving(on) so the Plot can animate its own crew (kiosk and up).
var serving_hook: Callable
var _roof: Node3D
var _truck := false
var _upgrades: Dictionary = {}
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
	var teal := Color("164d52")
	# wheels
	for sx in [-0.5, 0.5]:
		var w := ModelLib.cylinder(_body, 0.11, 0.06, Vector3(sx, 0.11, 0.12), dark)
		w.rotation.z = PI / 2
		_wheels.append(w)
	_skirt = ModelLib.box(_body, Vector3(1.06, 0.14, 0.5), Vector3(0, 0.07, 0), wood.darkened(0.2))
	_skirt.visible = false
	# chassis + counter
	_chassis.append(ModelLib.box(_body, Vector3(1.1, 0.42, 0.55), Vector3(0, 0.34, 0), teal))
	ModelLib.box(_body, Vector3(1.1, 0.14, 0.56), Vector3(0, 0.48, 0), cream)
	ModelLib.box(_body, Vector3(1.2, 0.04, 0.66), Vector3(0, 0.57, 0), wood)
	ModelLib.box(_body, Vector3(1.22, 0.02, 0.03), Vector3(0, 0.585, 0.33), gold)
	ModelLib.box(_body, Vector3(1.12, 0.03, 0.02), Vector3(0, 0.42, 0.285), gold)
	# Teak slats, brass corners and a tiny skewer seal make the cart recognisable
	# without textures, normal maps or extra downloads.
	for x in [-0.48, -0.36, -0.24, 0.24, 0.36, 0.48]:
		ModelLib.box(_body, Vector3(0.012, 0.22, 0.014), Vector3(x, 0.28, 0.283), teal.lightened(0.18))
	for x in [-0.53, 0.53]:
		ModelLib.box(_body, Vector3(0.025, 0.36, 0.025), Vector3(x, 0.3, 0.284), gold)
	var seal := ModelLib.cylinder(_body, 0.09, 0.012, Vector3(0, 0.29, 0.29), gold)
	seal.rotation.x = PI / 2
	for i in range(3):
		ModelLib.box(_body, Vector3(0.034, 0.025, 0.012), Vector3(-0.042 + i * 0.042, 0.29, 0.304), red)
	ModelLib.box(_body, Vector3(0.145, 0.009, 0.012), Vector3(0, 0.29, 0.307), cream)
	# posts and roof (hidden when selling from a truck, which brings its own)
	_roof = Node3D.new()
	_body.add_child(_roof)
	for sx in [-0.52, 0.52]:
		for sz in [-0.25, 0.25]:
			ModelLib.box(_roof, Vector3(0.035, 0.6, 0.035), Vector3(sx, 0.88, sz), dark)
	var roof := ModelLib.box(_roof, Vector3(1.25, 0.05, 0.72), Vector3(0, 1.2, 0.0), red)
	roof.rotation.x = deg_to_rad(6)
	PlotBuilders.stripes(roof, 1.25, 0.72)
	for i in range(7):
		ModelLib.box(_roof, Vector3(0.17, 0.065, 0.025), Vector3(-0.54 + i * 0.18, 1.14, 0.36), red if i % 2 == 0 else cream)
	# big awning (upgrade)
	_awning_big = Node3D.new()
	_body.add_child(_awning_big)
	var canvas := ModelLib.box(_awning_big, Vector3(1.5, 0.04, 0.5), Vector3(0, 1.14, 0.58), red)
	canvas.rotation.x = deg_to_rad(14)
	PlotBuilders.stripes(canvas, 1.5, 0.5)
	_awning_big.visible = false
	# menu board on the roof front
	ModelLib.box(_roof, Vector3(0.9, 0.22, 0.03), Vector3(0, 1.32, 0.36), cream)
	_title = PlotBuilders.sign(_roof, Vector3(0, 1.32, 0.38), 72, 0.0028)
	# rotating spit
	_spit = Node3D.new()
	_spit.position = Vector3(-0.33, 0.59, -0.05)
	_body.add_child(_spit)
	var roast := ModelLib.spawn("food/doner-spit", _spit, Vector3.ZERO, 0, 0.55)
	if roast:
		_spit_rotor = roast.find_child("SpitRotor", true, false) as Node3D
	# heater behind the spit
	ModelLib.box(_spit, Vector3(0.1, 0.42, 0.14), Vector3(0, 0.23, -0.15), dark)
	ModelLib.box(_spit, Vector3(0.06, 0.34, 0.02), Vector3(0, 0.23, -0.075), Color(1.0, 0.45, 0.1), 2.0)
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
	smoke.amount = 12
	smoke.lifetime = 1.8
	smoke.position = Vector3(0.12, 0.7, -0.05)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 0.85, 0.85, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	smoke.draw_pass_1 = sm
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_neon.text = _title.text
	_neon.font = UiTheme.font()
	_neon.font_size = 80
	_neon.pixel_size = 0.004
	_neon.modulate = Color(1.0, 0.25, 0.6)
	_neon.outline_modulate = Color(1.0, 0.7, 0.9)
	_neon.outline_size = 10
	_neon.visible = false
	add_child(_neon)
	_neon_light = OmniLight3D.new()
	_neon_light.light_color = Color(1.0, 0.4, 0.7)
	_neon_light.light_energy = 0.60
	_neon_light.omni_range = 1.40
	_neon_light.position = Vector3(0, 1.5, 0.5)
	_neon_light.visible = false
	add_child(_neon_light)
	# hospitality (upgrade; retain the legacy independently hidden _speaker group)
	_speaker = Node3D.new()
	_body.add_child(_speaker)
	var b := MeshBatch.new()
	var brass := gold
	var timber := Color("503520")
	var date_brown := Color("442719")
	var hospitality_center := Vector3(0.72, 0, -0.10)
	var table_top := 0.130
	var shelf_size := Vector3(0.160, 0.014, 0.160)
	var leg_height := table_top - shelf_size.y
	var leg_size := Vector3(0.016, leg_height, 0.016)
	var leg_spacing := 0.057
	b.add_box(shelf_size, timber, Transform3D(Basis.IDENTITY, hospitality_center + Vector3.UP * (table_top - shelf_size.y * 0.5)))
	for side_x in [-1.0, 1.0]:
		for side_z in [-1.0, 1.0]:
			var leg_center := Vector3(side_x * leg_spacing, leg_height * 0.5, side_z * leg_spacing)
			b.add_box(leg_size, timber, Transform3D(Basis.IDENTITY, hospitality_center + leg_center))
	var tray_center := hospitality_center + Vector3(-0.032, table_top + 0.003, 0.035)
	var tray_radius := 0.032
	var tray_height := 0.006
	var date_radius := 0.009
	var date_height := 0.010
	var date_offsets := [Vector3(-0.012, 0.008, 0), Vector3(0.009, 0.008, -0.009), Vector3(0.003, 0.014, 0.008)]
	b.add_cyl(tray_radius, tray_height, brass, Transform3D(Basis.IDENTITY, tray_center), 0.0, 12)
	for offset: Vector3 in date_offsets:
		b.add_cyl(date_radius, date_height, date_brown, Transform3D(Basis.IDENTITY, tray_center + offset), 0.0, 8)
	# Fresh tapered meshes give the belly/lid real slopes; cached resources stay untouched.
	var taper := func(center: Vector3, lower_radius: float, upper_radius: float, height: float, color: Color, sides: int = 10) -> void:
		var shape := CylinderMesh.new()
		shape.bottom_radius = lower_radius
		shape.top_radius = upper_radius
		shape.height = height
		shape.radial_segments = sides
		shape.rings = 1
		shape.material = ModelLib.flat_material(color)
		b.add_mesh("hospitality_%d" % shape.get_instance_id(), shape, Transform3D(Basis.IDENTITY, center))
	var dallah := func(origin: Vector3, size: float) -> void:
		# Radius/height profile: foot, rounded belly, narrow waist, flared neck, pointed lid.
		var body_profile := [Vector2(0.031, 0.000), Vector2(0.043, 0.014),
			Vector2(0.052, 0.042), Vector2(0.047, 0.070), Vector2(0.025, 0.105),
			Vector2(0.023, 0.132), Vector2(0.037, 0.149), Vector2(0.039, 0.155),
			Vector2(0.008, 0.179), Vector2(0.0, 0.192)]
		for i in range(body_profile.size() - 1):
			var lower: Vector2 = body_profile[i]
			var upper: Vector2 = body_profile[i + 1]
			var center := origin + Vector3.UP * (lower.y + upper.y) * 0.5 * size
			taper.call(center, lower.x * size, upper.x * size, (upper.y - lower.y) * size, brass)
		# Broad crescent spout and an open curved handle lie in X/Y, facing the camera.
		var spout_points := [Vector3(0.037, 0.052, 0), Vector3(0.067, 0.073, 0),
			Vector3(0.081, 0.104, 0), Vector3(0.091, 0.135, 0), Vector3(0.109, 0.154, 0)]
		var spout_radii := [0.016, 0.013, 0.010, 0.006]
		var handle_points := [Vector3(-0.027, 0.135, 0), Vector3(-0.064, 0.144, 0),
			Vector3(-0.084, 0.122, 0), Vector3(-0.086, 0.087, 0),
			Vector3(-0.064, 0.058, 0), Vector3(-0.045, 0.058, 0)]
		var handle_radius := 0.007
		var stroke_sides := 8
		for stroke in [spout_points, handle_points]:
			for i in range(stroke.size() - 1):
				var start: Vector3 = origin + stroke[i] * size
				var end: Vector3 = origin + stroke[i + 1] * size
				var direction := end - start
				var radius: float = (spout_radii[i] if stroke == spout_points else handle_radius) * size
				var axis := Basis(Quaternion(Vector3.UP, direction.normalized()))
				b.add_cyl(radius, direction.length() + radius * 0.4, brass,
					Transform3D(axis, (start + end) * 0.5), 0.0, stroke_sides)
	var pot_origin := hospitality_center + Vector3(0.018, table_top, -0.027)
	var pot_scale := 0.53
	dallah.call(pot_origin, pot_scale)
	# Bake this local batch's palette into vertex colours: one surface / one draw call.
	# Read primitive arrays only; never alter ModelLib's cached meshes or materials.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for key in b._order:
		var group: Dictionary = b._groups[key]
		var source: Mesh = group["mesh"]
		for surface in range(source.get_surface_count()):
			var arrays := source.surface_get_arrays(surface)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material := group["mat"] as StandardMaterial3D
			if material == null:
				material = source.surface_get_material(surface) as StandardMaterial3D
			var color := material.albedo_color
			for transform: Transform3D in group["xforms"]:
				var offset := vertices.size()
				var normal_basis := transform.basis.inverse().transposed()
				for i in range(source_vertices.size()):
					vertices.append(transform * source_vertices[i])
					normals.append((normal_basis * source_normals[i]).normalized())
					colors.append(color)
				for index in source_indices:
					indices.append(offset + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var corner := ArrayMesh.new()
	corner.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var palette := ModelLib.flat_material_unique(Color.WHITE)
	palette.vertex_color_use_as_albedo = true
	palette.vertex_color_is_srgb = true
	corner.surface_set_material(0, palette)
	b = MeshBatch.new()
	b.add_mesh("hospitality", corner, Transform3D.IDENTITY)
	b.flush(_speaker)
	_speaker.visible = false
	# fridge (upgrade)
	_fridge = Node3D.new()
	_body.add_child(_fridge)
	# beside the counter on the pavement (behind the cart it would sink into a shop front)
	ModelLib.box(_fridge, Vector3(0.33, 0.52, 0.34), Vector3(-0.85, 0.26, -0.18), Color("90a5a2"))
	ModelLib.box(_fridge, Vector3(0.30, 0.41, 0.025), Vector3(-0.85, 0.285, 0.006), Color("c0ccc5"))
	ModelLib.box(_fridge, Vector3(0.022, 0.16, 0.028), Vector3(-0.75, 0.33, 0.023), dark)
	ModelLib.box(_fridge, Vector3(0.26, 0.038, 0.020), Vector3(-0.85, 0.046, 0.006), dark)
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
	_vendor = ModelLib.spawn_crew(true, self, Vector3(-0.82, 0.0, 0.12), 20, CREW_HEIGHT)
	_helper = ModelLib.spawn_crew(false, self, Vector3(0.84, 0.0, 0.12), -20, CREW_HEIGHT)
	preview_crew(false)
	if _helper:
		_helper.hide()
	# The small decorative pieces are rigid; roofs/upgrades retain their own batches
	# so hiding them never leaves stray geometry floating in the truck or stall.
	ModelLib.batch_primitives(_body, [_roof, _awning_big, _speaker, _fridge, _spit] + _chassis + _wheels, false)
	for group in [_roof, _awning_big, _speaker, _fridge]:
		ModelLib.batch_primitives(group)

func preview_crew(active: bool) -> void:
	# A serving gesture is a one-shot: looping it snaps the arm back every cycle.
	if _vendor:
		if active:
			ModelLib.play_once(_vendor, "interact-right")
		else:
			ModelLib.play_loop(_vendor, "idle")
	if _helper:
		ModelLib.play_loop(_helper, "idle")

func server() -> Node3D:
	return _vendor

func set_truck(on: bool) -> void:
	if on == _truck:
		return
	_truck = on
	_refresh_frame()
	_place_neon()
	_update_width()

## Neon name (signage tier 3+): replaces the painted name on whichever board is in use
## (cart roof, stall canopy, truck) instead of floating above it.
func set_neon(on: bool) -> void:
	_neon_on = on
	_neon.visible = on
	_place_neon()

func _place_neon() -> void:
	if _truck:
		_neon.position = (FoodTruck.SIGN + Vector3.BACK * 0.009) * FoodTruck.SCALE / CART_SCALE
		_neon.font_size = 66
		_neon.pixel_size = 0.0026 * FoodTruck.SCALE / CART_SCALE
	elif stall:
		# the canopy board is built by the Plot in plot space (stand scale 0.72)
		_neon.position = Vector3(0, 1.14 / 0.72, 0.52 / 0.72)
		_neon.font_size = 72
		_neon.pixel_size = 0.0026 / 0.72
	else:
		_neon.position = Vector3(0, 1.32, 0.40)
		_neon.font_size = 72
		_neon.pixel_size = 0.0028
	_neon_light.position = _neon.position + Vector3(0, -0.1, 0.5)
	if _title:
		_title.visible = not _neon_on

## Wheels / roof / skirt for the current vehicle and stall mode.
func _refresh_frame() -> void:
	_body.visible = not _truck
	_roof.visible = not _truck and not stall
	for c in _chassis:
		c.visible = not _truck
	for w in _wheels:
		w.visible = not _truck and not stall
	_skirt.visible = stall and not _truck

func set_stall(on: bool) -> void:
	stall = on
	if _body:
		_refresh_frame()
		_place_neon()

## Counter width follows the Bigger Stand upgrade and the vehicle; the crew and fridge
## stand just past the counter ends whatever the width.
func _update_width() -> void:
	var wide := 1.25 if _upgrades.has("cart2") else 1.0
	_body.scale.x = wide
	if _vendor:
		_vendor.position = FoodTruck.VENDOR * FoodTruck.SCALE / CART_SCALE if _truck else Vector3(-(0.62 * wide + 0.22), 0.004, 0.12)
	if _helper:
		_helper.position = FoodTruck.HELPER * FoodTruck.SCALE / CART_SCALE if _truck else Vector3(0.62 * wide + 0.24, 0.004, 0.12)

func apply_upgrades(upgrades: Dictionary) -> void:
	_upgrades = upgrades
	_awning_big.visible = upgrades.has("awning")
	_speaker.visible = upgrades.has("speaker")
	_fridge.visible = upgrades.has("fridge") or upgrades.has("fridge2")
	_spit.visible = not upgrades.has("doner")
	_seating.visible = upgrades.has("seating")
	if _helper:
		_helper.visible = upgrades.has("helper")
	_update_width()

func set_night(is_night: bool) -> void:
	_neon_light.visible = is_night and _neon.visible
	_neon.outline_size = 16 if is_night else 6

func set_serving(on: bool) -> void:
	if on == _serving:
		return
	_serving = on
	if serving_hook.is_valid():
		serving_hook.call(on)
	if _vendor:
		ModelLib.play_loop(_vendor, "interact-right" if on else "idle", 1.4 if on else 1.0)
	if _helper and _helper.visible:
		ModelLib.play_loop(_helper, "idle")

func _process(delta: float) -> void:
	if _spit_rotor and _body.visible and _spit.visible:
		_spit_rotor.rotate_y(delta * 0.65)

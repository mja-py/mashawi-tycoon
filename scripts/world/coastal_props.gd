class_name CoastalProps
extends RefCounted
## Shared, vertex-colored scenery meshes. Only the two palms beside the beach
## shelters have separate moving crowns. Static copies are batched per mesh.

const PALM_TOP := Vector3(0.17, 1.46, 0.06)
const BARK := Color("8f6242")
const LEAF := Color("407646")
const STONE := Color("b0a083")
const WATER := preload("res://scripts/world/souq_water.gdshader")

static var _meshes := {}
static var _finish: StandardMaterial3D

static func palm(batch: MeshBatch, xform: Transform3D) -> void:
	batch.add_mesh("palm_trunk", _mesh("palm_trunk"), xform)
	batch.add_mesh("palm_crown", _mesh("palm_crown"), xform.translated_local(PALM_TOP))

static func wind_palm(batch: MeshBatch, parent: Node3D, xform: Transform3D) -> Node3D:
	batch.add_mesh("palm_trunk", _mesh("palm_trunk"), xform)
	# Keep the crown's animated rotation separate from the trunk's scale and yaw.
	var base := Node3D.new()
	base.transform = xform.translated_local(PALM_TOP)
	parent.add_child(base)
	var crown := MeshInstance3D.new()
	crown.name = "PalmCrown"
	crown.mesh = _mesh("palm_crown")
	base.add_child(crown)
	return crown

static func place(batch: MeshBatch, kind: String, xform: Transform3D) -> void:
	batch.add_mesh(kind, _mesh(kind), xform)

static func water(parent: Node3D, shore: Vector3, depth: float, beach: bool = false) -> void:
	var surface := MeshInstance3D.new()
	surface.name = "CoastalWater"
	surface.mesh = ModelLib.plane_mesh(Vector2(52.0, depth))
	surface.position = shore - Vector3.BACK * (depth * 0.5 - (0.26 if beach else 0.0))
	var material := ShaderMaterial.new()
	material.shader = WATER
	material.set_shader_parameter("beach", beach)
	material.set_shader_parameter("shore_edge", depth * 0.5 - (0.26 if beach else 0.0))
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(surface)

static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"palm_trunk":
			_trunk(s, PALM_TOP, 0.087, 0.048, BARK, 20)
		"palm_crown":
			_crown(s)
		"ghaf":
			_ghaf(s)
		"shrub":
			_bulge(s, Vector3(0, 0.11, 0), Vector3(0.21, 0.14, 0.17), Color("6b8e50"), 8.0)
			_bulge(s, Vector3(0.16, 0.075, 0.06), Vector3(0.14, 0.10, 0.12), Color("779953"), 2.0)
			_bulge(s, Vector3(-0.14, 0.082, 0.06), Vector3(0.13, 0.10, 0.12), Color("587b44"), 4.0)
		"limestone":
			_bulge(s, Vector3(0, 0.059, 0), Vector3(0.24, 0.17, 0.19), STONE, 2.0)
			_bulge(s, Vector3(0.24, 0.031, 0.09), Vector3(0.125, 0.095, 0.11), STONE.lightened(0.10), 6.0)
			_bulge(s, Vector3(-0.20, 0.013, 0.14), Vector3(0.085, 0.057, 0.079), STONE.darkened(0.10), 3.0)
		"parasol", "parasol_coral":
			_parasol(s, Color("bd6856") if kind == "parasol_coral" else Color("3e8278"))
		"shelter_canvas":
			_shelter_canvas(s)
		"bench":
			_bench(s)
	s.generate_normals()
	s.index()
	if _finish == null:
		_finish = StandardMaterial3D.new()
		_finish.vertex_color_use_as_albedo = true
		_finish.vertex_color_is_srgb = true
		_finish.roughness = 0.95
		_finish.cull_mode = BaseMaterial3D.CULL_DISABLED
	s.set_material(_finish)
	var mesh := s.commit()
	_meshes[kind] = mesh
	return mesh

static func _triangle(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	s.set_color(color)
	s.add_vertex(a)
	s.add_vertex(b)
	s.add_vertex(c)

static func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(s, a, b, c, color)
	_triangle(s, a, c, d, color)

static func _trunk(s: SurfaceTool, tip: Vector3, root: float, top: float, color: Color, rings: int) -> void:
	var bands: Array[PackedVector3Array] = []
	for i in range(rings + 1):
		var t := float(i) / rings
		var center := tip * Vector3(t * t, t, t * t)
		var radius := lerpf(root, top, t) * (1.0 + 0.15 * exp(-t * 18.0))
		radius *= 1.03 if i % 2 == 0 else 0.95
		var band := PackedVector3Array()
		for j in range(9):
			var a := TAU * j / 9.0
			band.append(center + Vector3(cos(a) * radius, 0, sin(a) * radius))
		bands.append(band)
	for i in range(rings):
		for j in range(9):
			var k := (j + 1) % 9
			var tone := color.lightened(0.04 * sin(j * 1.6 + i * 0.48)) if i % 2 == 0 else color.darkened(0.09)
			_quad(s, bands[i][j], bands[i][k], bands[i + 1][k], bands[i + 1][j], tone)

static func _crown(s: SurfaceTool) -> void:
	_bulge(s, Vector3(0, -0.032, 0), Vector3(0.10, 0.092, 0.091), Color("706745"), 3.0)
	for i in range(12):
		var upper := i >= 8
		var a := float(i) * (TAU / (4.0 if upper else 8.0)) + sin(i * 2.3) * 0.15
		var forward := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var length := (0.54 if upper else 0.76) + sin(i * 2.75) * 0.10
		var rise := (0.27 if upper else 0.17) + 0.025 * cos(i * 1.8)
		var end_y := 0.18 if upper else -0.21
		var tone := Color("649348").darkened(0.05 * sin(i * 4.1)) if upper else LEAF.darkened(0.07 + 0.04 * cos(i * 3.4))
		for j in range(8):
			var t := float(j) / 8.0
			var next := float(j + 1) / 8.0
			var start := _frond_axis(forward, length, rise, end_y, t)
			var finish := _frond_axis(forward, length, rise, end_y, next)
			var root_w := 0.012 * (1.0 - t) + 0.029 * sin(PI * t)
			var tip_w := 0.012 * (1.0 - next) + 0.029 * sin(PI * next)
			_quad(s, start - side * root_w, start + side * root_w,
				finish + side * tip_w, finish - side * tip_w, tone.lightened(0.08))
			for sign in [-1.0, 1.0]:
				var at := t + (0.08 if sign > 0.0 else 0.04)
				var base := _frond_axis(forward, length, rise, end_y, at)
				var wide := (0.038 + 0.155 * sin(PI * at)) * (1.0 - 0.35 * at)
				var tip: Vector3 = base + forward * (0.10 * (1.0 - t) + 0.025) + side * (wide * sign) - Vector3.UP * (0.048 + 0.04 * at)
				var middle := base.lerp(tip, 0.48) + Vector3.UP * 0.012
				var spread := forward * (0.036 + 0.024 * sin(PI * t))
				var leaf_color := tone.lightened(0.009 * j + 0.035 * cos(i + j * 1.7))
				_triangle(s, base, middle - spread, middle, leaf_color.darkened(0.09))
				_triangle(s, middle - spread, tip, middle, leaf_color.darkened(0.05))
				_triangle(s, base, middle, middle + spread, leaf_color)
				_triangle(s, middle, tip, middle + spread, leaf_color.lightened(0.035))

static func _frond_axis(direction: Vector3, length: float, rise: float, end_y: float, t: float) -> Vector3:
	return direction * (length * t) + Vector3.UP * (sin(PI * t) * rise + end_y * t * t)

static func _bulge(s: SurfaceTool, p: Vector3, size: Vector3, tone: Color, seed: float) -> void:
	const SEGMENTS := 10
	const RINGS := 6
	var bands: Array[PackedVector3Array] = []
	for i in range(RINGS + 1):
		var band := PackedVector3Array()
		var b := (float(i) / RINGS - 0.5) * PI
		for j in range(SEGMENTS):
			var a := TAU * j / SEGMENTS
			var direction := Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b))
			var scale := 1.0 + (0.11 * sin(a * 3.0 + b * 2.0 + seed) + 0.07 * sin(a * 5.0 - b + seed)) * cos(b)
			band.append(p + direction * size * scale)
		bands.append(band)
	for i in range(RINGS):
		for j in range(SEGMENTS):
			var k := (j + 1) % SEGMENTS
			var shade := tone.darkened(0.16 * (1.0 - float(i) / RINGS)).lightened(0.035 * sin(j * 1.7 + seed))
			_quad(s, bands[i][j], bands[i][k], bands[i + 1][k], bands[i + 1][j], shade)

static func _ghaf(s: SurfaceTool) -> void:
	_trunk(s, Vector3(0.06, 0.89, 0), 0.084, 0.038, BARK.darkened(0.14), 8)
	for i in range(5):
		var a := i * TAU / 5.0
		var branch := Vector3(cos(a) * 0.41, 0.91 + 0.11 * sin(i * 1.9), sin(a) * 0.33)
		_bulge(s, branch, Vector3(0.34, 0.16, 0.26), Color("638451").lightened(0.06 * sin(i * 2.2)), float(i))
	_bulge(s, Vector3(0.06, 1.08, -0.06), Vector3(0.37, 0.19, 0.32), Color("78945a"), 5.0)

static func _parasol(s: SurfaceTool, color: Color) -> void:
	_trunk(s, Vector3(0, 0.74, 0), 0.019, 0.015, Color("8c7662"), 4)
	_bulge(s, Vector3(0, 0.03, 0), Vector3(0.11, 0.065, 0.11), Color("b7a28b"), 2.0)
	for i in range(8):
		var tone := color if i % 2 == 0 else Color("e9d9ad")
		for j in range(3):
			var a := (float(i) + float(j) / 3.0) * TAU / 8.0
			var b := (float(i) + float(j + 1) / 3.0) * TAU / 8.0
			var left := Vector3(cos(a), 0, sin(a))
			var right := Vector3(cos(b), 0, sin(b))
			var peak := Vector3.UP * 0.79
			var mid := Vector3.UP * 0.746
			var edge := Vector3.UP * 0.66
			_triangle(s, peak, mid + left * 0.22, mid + right * 0.22, tone)
			_quad(s, mid + left * 0.22, edge + left * 0.39, edge + right * 0.39, mid + right * 0.22, tone)
			var dip := Vector3.UP * (0.031 if j == 1 else 0.019)
			_quad(s, edge + left * 0.39, edge + left * 0.39 - dip,
				edge + right * 0.39 - dip, edge + right * 0.39, tone.darkened(0.10))

static func _shelter_canvas(s: SurfaceTool) -> void:
	for stripe in range(9):
		var tone := Color("3f8277") if stripe % 2 == 0 else Color("ebd9ad")
		var x := (stripe - 4.5) * 0.098
		for j in range(8):
			var t := float(j) / 8.0
			var end := float(j + 1) / 8.0
			var a := Vector3(x, 0.805 + sin(PI * t) * 0.067, (t - 0.5) * 0.62)
			var b := Vector3(x, 0.805 + sin(PI * end) * 0.067, (end - 0.5) * 0.62)
			_quad(s, a, a + Vector3.RIGHT * 0.098, b + Vector3.RIGHT * 0.098, b, tone)
		var lip := Vector3(x, 0.805, 0.311)
		var edge := lip + Vector3.RIGHT * 0.098
		var hem := lip.lerp(edge, 0.5) - Vector3.UP * 0.041
		_quad(s, lip, edge, edge - Vector3.UP * 0.028, lip - Vector3.UP * 0.028, tone)
		_triangle(s, lip - Vector3.UP * 0.028, edge - Vector3.UP * 0.028, hem, tone)

static func _bench(s: SurfaceTool) -> void:
	var bronze := Color("605648")
	var teak := Color("a37451")
	for x in [-0.211, 0.211]:
		_rounded_plank(s, Vector3(x, 0.034, 0.004), Vector3(0.045, 0.068, 0.18), bronze)
		_rounded_plank(s, Vector3(x, 0.085, -0.038), Vector3(0.041, 0.155, 0.046), bronze)
		_rounded_plank(s, Vector3(x, 0.205, -0.091), Vector3(0.033, 0.20, 0.032), bronze)
		_rounded_plank(s, Vector3(x, 0.224, -0.004), Vector3(0.040, 0.027, 0.172), bronze)
	for z in [-0.057, 0.0, 0.057]:
		_rounded_plank(s, Vector3(0, 0.156, z), Vector3(0.55, 0.027, 0.050), teak.lightened(z))
	for y in [0.211, 0.260, 0.309]:
		_rounded_plank(s, Vector3(0, y, -0.076 - (y - 0.211) * 0.12), Vector3(0.55, 0.038, 0.031), teak)

static func _rounded_plank(s: SurfaceTool, center: Vector3, size: Vector3, tone: Color) -> void:
	var rim := PackedVector3Array()
	var radius := minf(size.x, size.z) * 0.27
	for i in range(4):
		var a := i * PI * 0.5
		var x := signf(cos(a + PI * 0.25)) * (size.x * 0.5 - radius)
		var z := signf(sin(a + PI * 0.25)) * (size.z * 0.5 - radius)
		for j in range(3):
			var angle := a + j * PI * 0.25
			rim.append(center + Vector3(x + cos(angle) * radius, 0, z + sin(angle) * radius))
	var half_h := Vector3.UP * (size.y * 0.5)
	for i in range(rim.size()):
		var a := rim[i]
		var b := rim[(i + 1) % rim.size()]
		_triangle(s, center + half_h, a + half_h, b + half_h, tone.lightened(0.07))
		_triangle(s, center - half_h, b - half_h, a - half_h, tone.darkened(0.15))
		_quad(s, a - half_h, b - half_h, b + half_h, a + half_h, tone)

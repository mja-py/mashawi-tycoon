class_name SouqScenery
extends RefCounted
## The Al Seef starter plaza. Batch repeated details so the Creek vista stays
## cheap alongside the animated service queue.

const QUAY_Z := -2.77
const PLASTER := Color("bb8f64")
const STONE := Color("d8b690")
const TRIM := Color("c19a73")
const TIMBER := Color("573b2d")
const DECK := Color("89634a")
const SHADOW := Color("40342c")
const BRASS := Color("be904f")
const TEAL := Color("357b76")
const RUST := Color("a9513a")
const CLOTH := Color("d6c19b")

var _batch: MeshBatch
var _rng: RandomNumberGenerator

func _init(batch: MeshBatch, rng: RandomNumberGenerator) -> void:
	_batch = batch
	_rng = rng

func build(parent: Node3D, gap: float) -> void:
	Paving.build(parent, "fahidi", Vector2(32, 9.46), Vector3(0, -0.008, 2.0))
	_creek(parent)
	# An asymmetric opening keeps the wind tower, shopfront and moored abra in view.
	var west := -maxf(1.88, gap + 0.72)
	var east := maxf(3.06, gap + 0.88)
	_shop(Vector3(west, 0, -2.18), 1.32, 1.02, STONE, RUST)
	_wind_tower(Vector3(west + 0.21, 0.90, -2.28))
	_shop(Vector3(west - 1.78, 0, -2.34), 1.76, 1.16, PLASTER, TEAL)
	_shop(Vector3(east, 0, -2.24), 1.60, 1.14, PLASTER, TEAL)
	_shop(Vector3(east + 1.94, 0, -2.20), 1.82, 0.93, STONE, RUST)
	_market_sign(parent, Vector3(west, 0.765, -1.48))
	_display(Vector3(west - 0.49, 0, -1.36), TEAL)
	_display(Vector3(east + 0.54, 0, -1.41), RUST)
	_textiles(Vector3(east - 0.70, 0, -1.56))
	_lantern(Vector3(west + 0.53, 0.69, -1.67))
	_lantern(Vector3(east - 0.60, 0.75, -1.72))
	CoastalProps.palm(_batch, Transform3D(Basis(Vector3.UP, -0.7).scaled(Vector3.ONE * 0.88), Vector3(west - 1.04, 0, -1.24)))
	CoastalProps.palm(_batch, Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3.ONE * 0.80), Vector3(east - 1.04, 0, -2.47)))
	for x in [west - 1.21, east - 1.08]:
		CoastalProps.place(_batch, "shrub", Transform3D(Basis.from_scale(Vector3.ONE * 0.49), Vector3(x, 0, -2.58)))

func _box(pos: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	_batch.add_box(size, color, Transform3D(basis, pos))

func _beam(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var along := b - a
	var basis := Basis.looking_at(along, Vector3.UP)
	_box((a + b) * 0.5, Vector3(width, width, along.length()), color, basis)

func _creek(parent: Node3D) -> void:
	CoastalProps.water(parent, Vector3(0, -0.18, QUAY_Z), 14.0)
	_box(Vector3(0, -0.14, QUAY_Z), Vector3(30, 0.26, 0.17), PLASTER)
	for i in range(-23, 24):
		var x := i * 0.38
		_box(Vector3(x, -0.028, QUAY_Z), Vector3(0.373, 0.065, 0.23), STONE)
		if x > 0.65 and x < 2.3:
			continue
		_box(Vector3(x, 0.139, QUAY_Z), Vector3(0.044, 0.27, 0.044), TIMBER)
		_box(Vector3(x, 0.278, QUAY_Z), Vector3(0.062, 0.025, 0.062), DECK)
		if i < 23 and not (x > 0.25 and x < 0.65):
			_beam(Vector3(x, 0.16, QUAY_Z), Vector3(x + 0.19, 0.119, QUAY_Z), 0.012, CLOTH)
			_beam(Vector3(x + 0.19, 0.119, QUAY_Z), Vector3(x + 0.38, 0.16, QUAY_Z), 0.012, CLOTH)
	# A timber landing joins the stone quay just behind the main shop.
	for i in range(12):
		_box(Vector3(1.52, -0.048 - i * 0.004, QUAY_Z - 0.045 - i * 0.047), Vector3(1.57, 0.033, 0.043), DECK if i % 3 else TIMBER)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.062
	ring.outer_radius = 0.089
	ring.rings = 16
	ring.ring_segments = 6
	for x in [0.79, 2.25]:
		_box(Vector3(x, -0.022, QUAY_Z - 0.58), Vector3(0.075, 0.28, 0.075), TIMBER)
		var float_ring := MeshInstance3D.new()
		float_ring.mesh = ring
		float_ring.material_override = ModelLib.flat_material(RUST)
		float_ring.rotation.x = PI / 2.0
		float_ring.position = Vector3(x, 0.092, QUAY_Z - 0.53)
		parent.add_child(float_ring)
	_abra(parent, Vector3(1.48, -0.13, QUAY_Z - 0.92))
	_beam(Vector3(0.79, 0.085, QUAY_Z - 0.58), Vector3(0.63, -0.028, QUAY_Z - 0.92), 0.012, CLOTH)
	_beam(Vector3(2.25, 0.085, QUAY_Z - 0.58), Vector3(2.31, -0.018, QUAY_Z - 0.92), 0.012, CLOTH)
	# Far-bank sea wall and a few soft silhouettes give the open water a horizon.
	_box(Vector3(0, -0.18, -8.3), Vector3(29, 0.46, 0.55), TRIM)
	_box(Vector3(0, 0.03, -8.6), Vector3(32, 0.12, 1.0), STONE)
	for i in range(11):
		var x := -12.0 + i * 2.35
		var h := 0.33 + _rng.randf() * 0.36
		var w := 1.23 + _rng.randf() * 0.53
		var tone := Color("a88e75") if i % 2 else Color("b49b81")
		_box(Vector3(x, h / 2.0, -9.29), Vector3(w, h, 0.84), tone)
		_box(Vector3(x, h, -9.29), Vector3(w + 0.06, 0.038, 0.87), tone.lightened(0.08))
		for j in [-1, 0, 1]:
			_box(Vector3(x + j * w * 0.25, h * 0.59, -8.86), Vector3(0.08, 0.10, 0.025), Color("776a60"))
		if i % 3 == 0:
			CoastalProps.palm(_batch, Transform3D(Basis.from_scale(Vector3.ONE * 0.67), Vector3(x + 0.92, 0, -9.06)))

func _shop(p: Vector3, w: float, h: float, tone: Color, fabric: Color) -> void:
	_box(p + Vector3(0, h * 0.5, 0), Vector3(w, h, 0.82), tone)
	var front := p + Vector3(0, 0, 0.42)
	_box(front + Vector3(0, 0.08, 0.013), Vector3(w + 0.014, 0.16, 0.034), TRIM)
	_box(p + Vector3(0, h + 0.02, 0), Vector3(w + 0.07, 0.053, 0.9), TRIM)
	_box(p + Vector3(0, h + 0.06, 0.4), Vector3(w, 0.055, 0.09), tone)
	for side in [-1.0, 1.0]:
		for i in range(5):
			var brick_w := 0.083 if i % 2 == 0 else 0.124
			var x: float = side * (w * 0.5 - brick_w * 0.5)
			_box(front + Vector3(x, 0.205 + i * 0.108, 0), Vector3(brick_w - 0.005, 0.098, 0.035), TRIM)
		for i in range(3):
			var x: float = side * (w * 0.28 + (i - 1) * 0.052)
			_box(front + Vector3(x, h - 0.215, 0.009), Vector3(0.028, 0.085, 0.025), DECK)
	for i in range(7):
		var x := (i - 3) * w / 8.0
		_box(front + Vector3(x, h - 0.095, 0.032), Vector3(0.032, 0.033, 0.124), TIMBER)
	# Teak doors inside a layered arch, with masonry joints and stone voussoirs.
	_box(front + Vector3(0, 0.235, 0.018), Vector3(0.356, 0.47, 0.029), SHADOW)
	_batch.add_cyl(0.178, 0.029, SHADOW, Transform3D(Basis(Vector3.RIGHT, PI / 2), front + Vector3(0, 0.47, 0.018)), 0.0, 24)
	for i in range(6):
		_box(front + Vector3((i - 2.5) * 0.05, 0.235, 0.034), Vector3(0.047, 0.46, 0.013), DECK if i % 2 == 0 else TIMBER)
	for i in range(11):
		var a := i * PI / 10.0
		_box(front + Vector3(cos(a) * 0.198, 0.47 + sin(a) * 0.198, 0.042), Vector3(0.047, 0.06, 0.053), STONE if i % 3 else TRIM, Basis(Vector3.BACK, a))
	for side in [-1.0, 1.0]:
		for y in [0.075, 0.205, 0.335]:
			_box(front + Vector3(side * 0.198, y, 0.043), Vector3(0.051, 0.126, 0.058), STONE)
		var shutter := front + Vector3(side * w * 0.34, 0.47, 0.024)
		_box(shutter, Vector3(0.19, 0.25, 0.048), TIMBER)
		_box(shutter + Vector3(0, -0.13, 0.013), Vector3(0.224, 0.03, 0.07), TRIM)
		for i in range(5):
			_box(shutter + Vector3(0, (i - 2) * 0.039, 0.029), Vector3(0.145, 0.026, 0.018), TEAL, Basis(Vector3.RIGHT, 0.28))
	_box(front + Vector3(0, 0.078, 0.044), Vector3(0.32, 0.027, 0.014), TIMBER)
	_box(front + Vector3(0.055, 0.245, 0.051), Vector3(0.029, 0.024, 0.019), BRASS)
	# Striped cloth is high enough to leave the door and market sign clear.
	for i in range(9):
		_box(front + Vector3((i - 4) * 0.071, h - 0.135, 0.145), Vector3(0.071, 0.022, 0.28), fabric if i % 2 == 0 else CLOTH, Basis(Vector3.RIGHT, 0.16))

func _wind_tower(p: Vector3) -> void:
	_box(p + Vector3.UP * 0.12, Vector3(0.62, 0.24, 0.58), PLASTER)
	_box(p + Vector3.UP * 0.25, Vector3(0.66, 0.049, 0.62), TRIM)
	for x in [-0.263, 0.263]:
		for z in [-0.247, 0.247]:
			_box(p + Vector3(x, 0.49, z), Vector3(0.097, 0.49, 0.095), STONE)
	for side in range(4):
		var turn := Basis(Vector3.UP, side * PI / 2.0)
		_box(p + turn * Vector3(0, 0.305, 0.266), Vector3(0.51, 0.05, 0.054), TRIM, turn)
		_box(p + turn * Vector3(0, 0.665, 0.266), Vector3(0.51, 0.045, 0.054), TRIM, turn)
		for x in [-0.138, 0.0, 0.138]:
			_box(p + turn * Vector3(x, 0.485, 0.249), Vector3(0.024, 0.34, 0.037), TIMBER, turn)
			_box(p + turn * Vector3(x, 0.585, 0.277), Vector3(0.067, 0.067, 0.018), DECK, turn * Basis(Vector3.BACK, PI / 4.0))
		_beam(p + turn * Vector3(-0.34, 0.40, 0.28), p + turn * Vector3(0.34, 0.40, 0.28), 0.028, TIMBER)
	_box(p + Vector3.UP * 0.73, Vector3(0.68, 0.09, 0.64), STONE)
	_box(p + Vector3.UP * 0.79, Vector3(0.72, 0.046, 0.67), TRIM)

func _market_sign(parent: Node3D, p: Vector3) -> void:
	for x in [-0.26, 0.26]:
		_box(p + Vector3(x, 0.074, -0.027), Vector3(0.02, 0.085, 0.05), TIMBER)
	_box(p, Vector3(0.62, 0.151, 0.035), TIMBER)
	_box(p + Vector3.BACK * 0.022, Vector3(0.58, 0.122, 0.017), TEAL)
	for i in range(2):
		var label := Label3D.new()
		label.text = ["سوق السيف", "SOUK AL SEEF"][i]
		label.font = UiTheme.font()
		label.font_size = 42
		label.pixel_size = 0.00145 if i == 0 else 0.00105
		label.outline_size = 0
		label.modulate = Color("ffebc6")
		label.position = p + Vector3(0, 0.026 - i * 0.054, 0.034)
		parent.add_child(label)

func _display(p: Vector3, color: Color) -> void:
	_box(p + Vector3.UP * 0.073, Vector3(0.26, 0.146, 0.21), TIMBER)
	for i in range(3):
		_box(p + Vector3((i - 1) * 0.079, 0.157, 0), Vector3(0.073, 0.036, 0.23), color if i != 1 else CLOTH, Basis(Vector3.UP, (i - 1) * 0.12))
	_box(p + Vector3(0.225, 0.05, -0.04), Vector3(0.153, 0.1, 0.15), DECK)
	_batch.add_cyl(0.065, 0.056, BRASS, Transform3D(Basis.IDENTITY, p + Vector3(0.225, 0.127, -0.04)), 0.0, 12)

func _textiles(p: Vector3) -> void:
	# Short hanging lengths evoke the souq's textile stalls without occupying the path.
	for x in [-0.19, 0.19]:
		_box(p + Vector3(x, 0.258, 0), Vector3(0.023, 0.51, 0.029), TIMBER)
		_box(p + Vector3(x, 0.022, 0), Vector3(0.054, 0.042, 0.16), DECK)
	_box(p + Vector3.UP * 0.50, Vector3(0.405, 0.021, 0.025), TIMBER)
	for i in range(3):
		var x := (i - 1) * 0.113
		var length := 0.27 + 0.04 * (i % 2)
		_box(p + Vector3(x, 0.49 - length * 0.5, 0.021), Vector3(0.100, length, 0.022), [RUST, TEAL, CLOTH][i])
		for hem in [0.028, 0.065]:
			_box(p + Vector3(x, 0.49 - length + hem, 0.034), Vector3(0.100, 0.018, 0.008), BRASS)

func _lantern(p: Vector3) -> void:
	_box(p + Vector3(0, 0.075, -0.022), Vector3(0.035, 0.026, 0.111), TIMBER)
	_box(p, Vector3(0.043, 0.09, 0.046), BRASS)
	_box(p + Vector3.BACK * 0.026, Vector3(0.029, 0.052, 0.009), CLOTH)
	_box(p + Vector3.UP * 0.055, Vector3(0.056, 0.026, 0.056), TIMBER)

func _abra(parent: Node3D, p: Vector3) -> void:
	# Shaped timber hull with a shallow keel and upturned bow and stern.
	var profile := [Vector3(-0.98, 0.14, 0.01), Vector3(-0.67, 0.06, 0.19), Vector3(0.0, 0.045, 0.235),
		Vector3(0.63, 0.065, 0.19), Vector3(0.98, 0.16, 0.01)]
	var hull := SurfaceTool.new()
	hull.begin(Mesh.PRIMITIVE_TRIANGLES)
	hull.set_smooth_group(-1)
	for i in range(profile.size() - 1):
		var a: Vector3 = profile[i]
		var b: Vector3 = profile[i + 1]
		for side in [-1.0, 1.0]:
			var rail_a := Vector3(a.x, a.y + 0.10, a.z * side)
			var rail_b := Vector3(b.x, b.y + 0.10, b.z * side)
			var chine_a := Vector3(a.x * 0.97, a.y, a.z * side * 0.60)
			var chine_b := Vector3(b.x * 0.97, b.y, b.z * side * 0.60)
			var faces := [rail_a, rail_b, chine_a, chine_a, rail_b, chine_b]
			if side > 0.0:
				faces.reverse()
			for vertex in faces:
				hull.add_vertex(vertex)
			_beam(p + rail_a, p + rail_b, 0.026, DECK)
	_box(p + Vector3.UP * 0.124, Vector3(1.44, 0.04, 0.305), TIMBER)
	hull.generate_normals()
	var body := MeshInstance3D.new()
	body.mesh = hull.commit()
	body.material_override = ModelLib.flat_material(PLASTER.darkened(0.36))
	body.position = p
	parent.add_child(body)
	for x in [-0.55, 0.54]:
		_box(p + Vector3(x, 0.21, 0), Vector3(0.10, 0.034, 0.40), DECK)
		for z in [-0.163, 0.163]:
			_box(p + Vector3(x, 0.30, z), Vector3(0.019, 0.31, 0.019), TIMBER)
	for i in range(7):
		var z := (i - 3) * 0.069
		var y := 0.469 - absf(z) * 0.22
		_box(p + Vector3(0, y, z), Vector3(1.31, 0.019, 0.073), TEAL if i in [0, 6] else CLOTH, Basis(Vector3.RIGHT, signf(z) * 0.20))

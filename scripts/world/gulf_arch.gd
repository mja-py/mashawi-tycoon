class_name GulfArch
extends RefCounted
## Procedural Gulf architecture (houses, mosque, Burj). Bodies are individual
## meshes; the many small repeated parts go into a MeshBatch whose transforms
## are in `parent` space, so flush the batch into that same parent.

const SAND := Color(0.93, 0.87, 0.74)
const WHITE_WASH := Color(0.96, 0.94, 0.88)
const OCHRE := Color(0.87, 0.75, 0.57)
const WOOD := Color(0.42, 0.27, 0.15)
const GLASS := Color(0.25, 0.3, 0.38)
const AWNINGS := [Color(0.55, 0.14, 0.16), Color(0.2, 0.45, 0.5), Color(0.85, 0.6, 0.2)]

static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)

static func _at_rx(p: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, angle), p)

## A traditional Gulf house: plastered box, parapet, arched windows, teak beams,
## optionally a barjeel (wind tower) on the roof and a shop awning at the door.
static func building(parent: Node3D, rng: RandomNumberGenerator, batch: MeshBatch, pos: Vector3, w: float, d: float, h: float,
		tone: Color, tower: bool, awning: bool = false) -> Node3D:
	var b := Node3D.new()
	b.position = pos
	parent.add_child(b)
	var dark := tone.darkened(0.25)
	ModelLib.box(b, Vector3(w, h, d), Vector3(0, h / 2.0, 0), tone)
	# parapet with crenellations
	for sx in [-1.0, 1.0]:
		batch.add_box(Vector3(0.05, 0.08, d), dark, _at(pos + Vector3(sx * (w / 2.0 - 0.025), h + 0.04, 0)))
	for sz in [-1.0, 1.0]:
		batch.add_box(Vector3(w, 0.08, 0.05), dark, _at(pos + Vector3(0, h + 0.04, sz * (d / 2.0 - 0.025))))
	var n := int(w / 0.16)
	for i in range(n):
		if i % 2 == 0:
			batch.add_box(Vector3(0.08, 0.06, 0.05), dark, _at(pos + Vector3(-w / 2.0 + 0.08 + i * 0.16, h + 0.11, d / 2.0 - 0.025)))
	# teak beams poking out under the roof line
	for i in range(int(w / 0.2)):
		batch.add_cyl(0.015, 0.1, WOOD, _at_rx(pos + Vector3(-w / 2.0 + 0.1 + i * 0.2, h - 0.12, d / 2.0 + 0.03), PI / 2))
	# arched windows on the front, two floors
	var floors := maxi(1, int(h / 0.45))
	var cols := maxi(1, int(w / 0.3))
	for f in range(floors):
		for c in range(cols):
			var x := -w / 2.0 + (c + 0.5) * (w / cols)
			var y := 0.22 + f * (h / floors)
			if f == 0 and c == cols / 2:
				continue
			batch.add_box(Vector3(0.1, 0.16, 0.02), GLASS, _at(pos + Vector3(x, y, d / 2.0 + 0.005)))
			batch.add_cyl(0.05, 0.02, GLASS, _at_rx(pos + Vector3(x, y + 0.08, d / 2.0 + 0.005), PI / 2))
			batch.add_box(Vector3(0.14, 0.02, 0.04), WHITE_WASH, _at(pos + Vector3(x, y - 0.09, d / 2.0 + 0.015)))
	# arched door
	var dx := -w / 2.0 + (cols / 2 + 0.5) * (w / cols)
	batch.add_box(Vector3(0.16, 0.3, 0.02), WOOD, _at(pos + Vector3(dx, 0.15, d / 2.0 + 0.005)))
	batch.add_cyl(0.08, 0.02, WOOD, _at_rx(pos + Vector3(dx, 0.3, d / 2.0 + 0.005), PI / 2))
	if awning:
		var col: Color = AWNINGS[rng.randi_range(0, AWNINGS.size() - 1)]
		batch.add_box(Vector3(0.5, 0.03, 0.28), col, _at_rx(pos + Vector3(dx, 0.5, d / 2.0 + 0.14), deg_to_rad(12)))
	if tower:
		var tx := w / 2.0 - 0.2
		var tz := -d / 2.0 + 0.2
		var th := 0.55
		batch.add_box(Vector3(0.3, th, 0.3), tone.lightened(0.05), _at(pos + Vector3(tx, h + th / 2.0, tz)))
		for side in range(4):
			for k in range(3):
				var off := -0.09 + k * 0.09
				var sp := Vector3(tx + off, h + th / 2.0, tz + 0.155) if side < 2 else Vector3(tx + 0.155, h + th / 2.0, tz + off)
				if side == 1:
					sp.z = tz - 0.155
				if side == 3:
					sp.x = tx - 0.155
				batch.add_box(Vector3(0.02, th - 0.1, 0.02), dark, _at(pos + sp))
		batch.add_box(Vector3(0.36, 0.05, 0.36), dark, _at(pos + Vector3(tx, h + th + 0.025, tz)))
	return b

## A row of Gulf houses packed along X (from -half_w-1.5 to half_w+1.5) with their fronts on front_z.
## `hole` > 0 leaves x in (-hole, hole) empty (the player's plot).
static func row(parent: Node3D, rng: RandomNumberGenerator, batch: MeshBatch, half_w: float, front_z: float,
		scale: float = 1.0, towers: float = 0.45, awnings: float = 0.0, hole: float = 0.0, clear: float = 0.0) -> void:
	var tones := [SAND, WHITE_WASH, OCHRE, SAND]
	var x := -half_w - 1.5
	while x <= half_w + 1.5:
		var w := rng.randf_range(0.8, 1.5) * scale
		if hole > 0.0 and x < hole and x + w > -hole:
			if -hole - x >= 0.6 * scale:
				w = -hole - x - 0.04
			else:
				x = hole + 0.04
				continue
		var d := rng.randf_range(0.8, 1.1) * scale
		var h := rng.randf_range(0.8, 1.35) * scale
		var tone: Color = tones[rng.randi_range(0, tones.size() - 1)]
		var tower := rng.randf() < towers
		# no shop awning right behind the stand (|x| < clear): it would hang over the vendor's head
		var awning := rng.randf() < awnings and not (clear > 0.0 and x < clear and x + w > -clear)
		building(parent, rng, batch, Vector3(x + w / 2.0, 0, front_z - d / 2.0), w, d, h, tone, tower, awning)
		x += w + 0.08

static func mosque(parent: Node3D, pos: Vector3, scale: float = 1.0) -> void:
	var m := Node3D.new()
	m.position = pos
	m.scale = Vector3.ONE * scale
	parent.add_child(m)
	var teal := Color(0.35, 0.65, 0.6)
	ModelLib.box(m, Vector3(1.6, 0.7, 1.2), Vector3(0, 0.35, 0), WHITE_WASH)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	dome.mesh = sm
	dome.material_override = ModelLib.flat_material(teal)
	dome.position = Vector3(0, 0.7, 0)
	m.add_child(dome)
	ModelLib.cylinder(m, 0.03, 0.3, Vector3(0, 1.3, 0), Color(0.85, 0.7, 0.3))
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.11
	cm.height = 0.3
	for sx in [-0.95, 0.95]:
		ModelLib.cylinder(m, 0.09, 1.9, Vector3(sx, 0.95, 0.4), WHITE_WASH)
		ModelLib.cylinder(m, 0.13, 0.08, Vector3(sx, 1.6, 0.4), teal)
		var cap := MeshInstance3D.new()
		cap.mesh = cm
		cap.material_override = ModelLib.flat_material(teal)
		cap.position = Vector3(sx, 2.0, 0.4)
		m.add_child(cap)

static func burj(parent: Node3D, batch: MeshBatch, pos: Vector3) -> void:
	var glass := Color(0.72, 0.8, 0.9)
	var tiers := [[0.5, 0.9], [0.36, 0.8], [0.25, 0.7], [0.15, 0.6], [0.08, 0.5]]
	var y := 0.0
	for t in tiers:
		var r: float = t[0]
		var h: float = t[1]
		batch.add_cyl(r, h, glass, _at(pos + Vector3(0, y + h / 2.0, 0)))
		for k in range(3):
			var a := k * TAU / 3.0
			batch.add_cyl(r * 0.55, h * 0.75, glass.darkened(0.08), _at(pos + Vector3(cos(a) * r * 0.8, y + h * 0.375, sin(a) * r * 0.8)))
		y += h
	var spire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.08
	cm.height = 1.0
	spire.mesh = cm
	spire.material_override = ModelLib.flat_material(Color(0.8, 0.85, 0.92))
	spire.position = pos + Vector3(0, y + 0.5, 0)
	parent.add_child(spire)

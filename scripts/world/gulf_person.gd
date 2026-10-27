class_name GulfPerson
extends Node3D
## Procedural chibi Emirati character built from primitives in the proportions of the
## Kenney mini characters (about 0.78 units tall). Men wear a white kandura with ghutra
## and agal; women a black abaya and shayla with gold trim. Animation is code driven
## (set_anim), so no rig is needed. Faces +Z.

var female := false
var _t := 0.0
var _anim := "idle"
var _once_left := 0.0
var _root: Node3D
var _body: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _speed := 1.0

const SKINS := [Color(0.93, 0.78, 0.64), Color(0.85, 0.66, 0.5), Color(0.72, 0.52, 0.38), Color(0.58, 0.4, 0.28)]

func _ready() -> void:
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var skin: Color = SKINS[rng.randi_range(0, SKINS.size() - 1)]
	var white := Color(0.97, 0.97, 0.94)
	var black := Color(0.06, 0.06, 0.08)
	var gold := Color(0.85, 0.68, 0.3)
	var robe := black if female else white
	_root = Node3D.new()
	add_child(_root)
	_body = Node3D.new()
	_root.add_child(_body)
	# robe: tapered cylinder, slightly wider at the hem
	var robe_mesh := CylinderMesh.new()
	robe_mesh.top_radius = 0.13
	robe_mesh.bottom_radius = 0.18
	robe_mesh.height = 0.4
	robe_mesh.radial_segments = 14
	var rm := MeshInstance3D.new()
	rm.mesh = robe_mesh
	rm.material_override = ModelLib.flat_material(robe)
	rm.position = Vector3(0, 0.2, 0)
	_body.add_child(rm)
	# shoulders / collar
	ModelLib.cylinder(_body, 0.14, 0.05, Vector3(0, 0.405, 0), robe)
	if female:
		# gold embroidery band at the hem and cuffs
		ModelLib.cylinder(_body, 0.182, 0.02, Vector3(0, 0.02, 0), gold)
		ModelLib.box(_body, Vector3(0.07, 0.08, 0.04), Vector3(0.2, 0.2, 0.04), _pick(rng, [Color(0.7, 0.2, 0.3), Color(0.2, 0.4, 0.6), Color(0.85, 0.6, 0.2)]))
	else:
		# kandura placket and tassel (tarboosh) line
		ModelLib.box(_body, Vector3(0.03, 0.2, 0.01), Vector3(0, 0.36, 0.135), Color(0.88, 0.88, 0.84))
		ModelLib.cylinder(_body, 0.006, 0.18, Vector3(0.03, 0.33, 0.14), Color(0.9, 0.9, 0.86))
		# sandals peeking out
		for sx in [-0.06, 0.06]:
			ModelLib.box(_body, Vector3(0.07, 0.025, 0.1), Vector3(sx, 0.012, 0.1), Color(0.45, 0.3, 0.18))
	# arms
	_arm_l = _arm(Vector3(-0.17, 0.38, 0), robe, skin)
	_arm_r = _arm(Vector3(0.17, 0.38, 0), robe, skin)
	# head
	_head = Node3D.new()
	_head.position = Vector3(0, 0.42, 0)
	_body.add_child(_head)
	ModelLib.box(_head, Vector3(0.3, 0.3, 0.27), Vector3(0, 0.16, 0), skin)
	# face
	for sx in [-0.07, 0.07]:
		ModelLib.box(_head, Vector3(0.045, 0.055, 0.01), Vector3(sx, 0.18, 0.14), Color(0.12, 0.1, 0.1))
	ModelLib.box(_head, Vector3(0.06, 0.015, 0.01), Vector3(0, 0.1, 0.14), Color(0.6, 0.3, 0.3))
	if female:
		# shayla wrapped around the head, face open at the front
		ModelLib.box(_head, Vector3(0.34, 0.34, 0.1), Vector3(0, 0.16, -0.11), black)
		ModelLib.box(_head, Vector3(0.34, 0.08, 0.31), Vector3(0, 0.33, -0.01), black)
		for sx in [-0.165, 0.165]:
			ModelLib.box(_head, Vector3(0.03, 0.34, 0.29), Vector3(sx, 0.16, -0.02), black)
		ModelLib.box(_head, Vector3(0.3, 0.025, 0.01), Vector3(0, 0.3, 0.14), gold)
	else:
		# ghutra: white cloth over the head with side and back flaps, held by a black agal
		var cloth := Color(1.0, 1.0, 0.99)
		ModelLib.box(_head, Vector3(0.34, 0.07, 0.31), Vector3(0, 0.33, -0.01), cloth)
		ModelLib.box(_head, Vector3(0.34, 0.34, 0.07), Vector3(0, 0.14, -0.16), cloth)
		for sx in [-0.165, 0.165]:
			ModelLib.box(_head, Vector3(0.035, 0.32, 0.29), Vector3(sx, 0.12, -0.02), cloth)
		var agal := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.14
		tm.outer_radius = 0.2
		tm.rings = 24
		tm.ring_segments = 8
		agal.mesh = tm
		agal.material_override = ModelLib.flat_material(black)
		agal.position = Vector3(0, 0.345, -0.01)
		agal.scale = Vector3(1, 0.6, 1)
		_head.add_child(agal)
		if rng.randf() < 0.5:
			# beard
			ModelLib.box(_head, Vector3(0.24, 0.06, 0.03), Vector3(0, 0.03, 0.125), Color(0.15, 0.1, 0.08))

func _arm(pos: Vector3, robe: Color, skin: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	_body.add_child(pivot)
	ModelLib.cylinder(pivot, 0.045, 0.3, Vector3(0, -0.15, 0), robe)
	var hand := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	hand.mesh = sm
	hand.material_override = ModelLib.flat_material(skin)
	hand.position = Vector3(0, -0.32, 0)
	pivot.add_child(hand)
	return pivot

func _pick(rng: RandomNumberGenerator, arr: Array) -> Color:
	return arr[rng.randi_range(0, arr.size() - 1)]

## Animation names match the Kenney character clips the game already uses.
func set_anim(name: String, speed: float = 1.0) -> void:
	if name in ["emote-yes", "emote-no", "pick-up", "interact-right", "interact-left"]:
		_once_left = 0.9
	_anim = name
	_speed = speed

func _process(delta: float) -> void:
	_t += delta * _speed
	var walk := _anim in ["walk", "sprint"]
	if walk:
		var ph := _t * 9.0
		_root.position.y = absf(sin(ph)) * 0.02
		_body.rotation.z = sin(ph) * 0.03
		_arm_l.rotation.x = sin(ph) * 0.5
		_arm_r.rotation.x = -sin(ph) * 0.5
		_head.rotation = Vector3(0, 0, -sin(ph) * 0.03)
	else:
		_root.position.y = sin(_t * 2.0) * 0.004
		_body.rotation.z = 0.0
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, 0.15)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, 0.15)
		_head.rotation = Vector3.ZERO
	if _once_left > 0.0:
		_once_left -= delta
		var k := 1.0 - _once_left / 0.9
		match _anim:
			"emote-yes":
				_head.rotation.x = sin(k * TAU * 2.0) * 0.25
			"emote-no":
				_head.rotation.y = sin(k * TAU * 2.0) * 0.4
			"pick-up", "interact-right":
				_arm_r.rotation.x = -sin(k * PI) * 1.6
			"interact-left":
				_arm_l.rotation.x = -sin(k * PI) * 1.6
		if _once_left <= 0.0:
			_anim = "idle"

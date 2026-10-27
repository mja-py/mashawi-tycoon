class_name ModelLib
extends RefCounted
## Loads Kenney GLB scenes by short name ("roads/road-straight") with caching.

static var _cache := {}

static func scene(name: String) -> PackedScene:
	if _cache.has(name):
		return _cache[name]
	var path := "res://assets/models/%s.glb" % name
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("Model missing: " + path)
	_cache[name] = ps
	return ps

static func spawn(name: String, parent: Node, pos: Vector3 = Vector3.ZERO, rot_y_deg: float = 0.0, scale: float = 1.0) -> Node3D:
	if name.begins_with("gulf:"):
		var gp := GulfPerson.new()
		gp.female = name.ends_with("female")
		gp.position = pos
		gp.rotation.y = deg_to_rad(rot_y_deg)
		gp.scale = Vector3.ONE * scale
		parent.add_child(gp)
		return gp
	var ps := scene(name)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = pos
	n.rotation.y = deg_to_rad(rot_y_deg)
	n.scale = Vector3.ONE * scale
	parent.add_child(n)
	return n

static func animation_player(root: Node) -> AnimationPlayer:
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer

static func play_loop(root: Node, anim: String, speed: float = 1.0) -> void:
	if root.has_method("set_anim"):
		root.set_anim(anim, speed)
		return
	var ap := animation_player(root)
	if ap == null:
		return
	if not ap.has_animation(anim):
		return
	ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
	ap.speed_scale = speed
	if ap.current_animation != anim:
		ap.play(anim, 0.15)

static func play_once(root: Node, anim: String, then: String = "idle") -> void:
	if root.has_method("set_anim"):
		root.set_anim(anim)
		return
	var ap := animation_player(root)
	if ap == null or not ap.has_animation(anim):
		return
	ap.get_animation(anim).loop_mode = Animation.LOOP_NONE
	ap.play(anim, 0.1)
	if then != "" and ap.has_animation(then):
		ap.queue(then)
		ap.get_animation(then).loop_mode = Animation.LOOP_LINEAR

static func flat_material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = flat_material(color, emission)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mi.mesh = mesh
	mi.material_override = flat_material(color, emission)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func plane(parent: Node, size: Vector2, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = flat_material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi

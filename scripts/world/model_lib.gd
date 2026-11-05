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

## Fit the rigged stand crew to the scale of the cart and kiosk.
static func spawn_crew(female: bool, parent: Node, pos: Vector3, rot_y_deg: float, scale: float) -> Node3D:
	var path := "crew/abaya-lady" if female else "crew/kandura-man"
	var fitted_scale := scale * 0.78 / (1.622 if female else 1.714)
	# The source feet sit about 1 cm below the rig origin in the idle clip.
	return spawn(path, parent, pos + Vector3.UP * 0.011 * fitted_scale, rot_y_deg, fitted_scale)

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
	ap.clear_queue()
	ap.speed_scale = 1.0
	ap.get_animation(anim).loop_mode = Animation.LOOP_NONE
	ap.play(anim, 0.1)
	if then != "" and ap.has_animation(then):
		ap.queue(then)
		ap.get_animation(then).loop_mode = Animation.LOOP_LINEAR

static func hand_position(actor: Node3D) -> Vector3:
	var skeleton: Skeleton3D
	if actor.has_meta("_hand_skeleton"):
		skeleton = actor.get_meta("_hand_skeleton") as Skeleton3D
	if skeleton == null and not actor.has_meta("_no_hand_skeleton"):
		var rigs := actor.find_children("*", "Skeleton3D", true, false)
		if rigs.is_empty():
			actor.set_meta("_no_hand_skeleton", true)
		else:
			skeleton = rigs[0] as Skeleton3D
			actor.set_meta("_hand_skeleton", skeleton)
	if skeleton:
		var hand := skeleton.find_bone("RightHand")
		if hand >= 0:
			return skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
	return actor.to_global(Vector3(-0.17, 0.41, 0.16))

## Shared flat material per (colour, emission). Callers must not mutate the
## result; use flat_material_unique() when the material is changed later.
static var _mats := {}
static var _meshes := {}
static var _model_meshes := {}

static func flat_material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key := material_key(color, emission)
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = flat_material_unique(color, emission)
		_mats[key] = m
	return m

static func material_key(color: Color, emission: float = 0.0) -> String:
	return "%d|%.2f" % [color.to_rgba32(), maxf(emission, 0.0)]

static func flat_material_unique(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func _k(v: float) -> String:
	return "%.4f" % v

## Shared primitive meshes keyed by rounded size (never mutate them).
static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box|%s|%s|%s" % [_k(size.x), _k(size.y), _k(size.z)]
	var mesh: BoxMesh = _meshes.get(key)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return mesh

static func cylinder_mesh(radius: float, height: float, segs: int = 16) -> CylinderMesh:
	var key := "cyl|%s|%s|%d" % [_k(radius), _k(height), segs]
	var mesh: CylinderMesh = _meshes.get(key)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = segs
		_meshes[key] = mesh
	return mesh

static func plane_mesh(size: Vector2) -> PlaneMesh:
	var key := "plane|%s|%s" % [_k(size.x), _k(size.y)]
	var mesh: PlaneMesh = _meshes.get(key)
	if mesh == null:
		mesh = PlaneMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return mesh

## Every mesh of a model as [Mesh, Transform3D relative to the model root],
## with surface override materials baked into a duplicated mesh. Cached.
static func meshes_of(name: String) -> Array:
	if _model_meshes.has(name):
		return _model_meshes[name]
	var out := []
	var ps := scene(name)
	if ps != null:
		var root := ps.instantiate() as Node3D
		_collect_meshes(root, Transform3D.IDENTITY, out, true)
		root.free()
	_model_meshes[name] = out
	return out

## The first mesh of a model (see meshes_of), or null.
static func mesh_of(name: String) -> Mesh:
	var all := meshes_of(name)
	return all[0][0] if not all.is_empty() else null

static func _collect_meshes(n: Node, xf: Transform3D, out: Array, is_root: bool) -> void:
	var here := xf
	if n is Node3D and not is_root:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		var needs := mi.material_override != null
		for s in range(mesh.get_surface_count()):
			if mi.get_surface_override_material(s) != null:
				needs = true
		if needs and mesh is ArrayMesh:
			var am := (mesh as ArrayMesh).duplicate() as ArrayMesh
			for s in range(am.get_surface_count()):
				var mat: Material = mi.material_override
				if mat == null:
					mat = mi.get_surface_override_material(s)
				if mat != null:
					am.surface_set_material(s, mat)
			mesh = am
		out.append([mesh, here])
	for c in n.get_children():
		_collect_meshes(c, here, out, false)

static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh(size)
	mi.material_override = flat_material(color, emission)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = cylinder_mesh(radius, height)
	mi.material_override = flat_material(color, emission)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func plane(parent: Node, size: Vector2, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = plane_mesh(size)
	mi.material_override = flat_material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi

## Collapse rigid primitive details by material, retaining the transform hierarchy
## for animated joints and independently hidden upgrades. Shared meshes stay intact.
static func batch_primitives(root: Node3D, skip: Array = [], shadows: bool = true) -> void:
	var batch := MeshBatch.new()
	_batch_primitives(root, Transform3D.IDENTITY, batch, skip, true)
	for mi in batch.flush(root):
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _batch_primitives(n: Node, xf: Transform3D, batch: MeshBatch, skip: Array, is_root: bool = false) -> void:
	if n in skip:
		return
	var here := xf
	if n is Node3D and not is_root:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat and mi.mesh is BoxMesh:
			var emission := mat.emission_energy_multiplier if mat.emission_enabled else 0.0
			batch.add_box((mi.mesh as BoxMesh).size, mat.albedo_color, here, emission)
			mi.mesh = null
	for child in n.get_children():
		_batch_primitives(child, here, batch, skip)

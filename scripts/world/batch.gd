class_name MeshBatch
extends RefCounted
## Collects many static copies of the same mesh + material and emits one
## MultiMeshInstance3D per (mesh, material) pair, so a row of houses costs a
## few draw calls instead of hundreds. Boxes and cylinders share a unit mesh
## scaled per instance (axis-aligned scale keeps their normals exact).
## Transforms are in the space of the node passed to flush().

var _groups := {}
var _order: Array[String] = []

func _add(key: String, mesh: Mesh, mat: Material, xform: Transform3D) -> void:
	var g: Dictionary = _groups.get(key, {})
	if g.is_empty():
		g = {"mesh": mesh, "mat": mat, "xforms": []}
		_groups[key] = g
		_order.append(key)
	g["xforms"].append(xform)

static func _scaled(xform: Transform3D, s: Vector3) -> Transform3D:
	return Transform3D(xform.basis * Basis.from_scale(s), xform.origin)

func add_box(size: Vector3, color: Color, xform: Transform3D, emission := 0.0) -> void:
	_add("box|" + ModelLib.material_key(color, emission), ModelLib.box_mesh(Vector3.ONE),
		ModelLib.flat_material(color, emission), _scaled(xform, size))

func add_cyl(radius: float, height: float, color: Color, xform: Transform3D, emission := 0.0, segs := 16) -> void:
	_add("cyl%d|%s" % [segs, ModelLib.material_key(color, emission)], ModelLib.cylinder_mesh(1.0, 1.0, segs),
		ModelLib.flat_material(color, emission), _scaled(xform, Vector3(radius, height, radius)))

func add_mesh(name: String, mesh: Mesh, xform: Transform3D) -> void:
	_add("mesh|" + name, mesh, null, xform)

## A Kenney model by short name, drawn with its own (imported) materials.
func add_model(name: String, xform: Transform3D, material: Material = null) -> void:
	var parts := ModelLib.meshes_of(name)
	for i in range(parts.size()):
		_add("model|%s|%d|%s" % [name, i, str(material.get_rid()) if material else ""], parts[i][0], material, xform * (parts[i][1] as Transform3D))

func is_empty() -> bool:
	return _order.is_empty()

func flush(parent: Node3D) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for key in _order:
		var g: Dictionary = _groups[key]
		var xforms: Array = g["xforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if g["mat"] != null:
			mmi.material_override = g["mat"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mmi)
		out.append(mmi)
	_groups.clear()
	_order.clear()
	return out

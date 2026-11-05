class_name Paving
extends RefCounted
## One filtered surface per pedestrian district. Colors describe the paving,
## walking band and border in that order.

const SURFACE := preload("res://scripts/world/paving.gdshader")
const DESIGNS := {
	"fahidi": [Color("ad9279"), Color("ba9b80"), Color("7a5746"), Vector2(0.69, 0.42), -0.17, 0.37, true],
	"creek": [Color("ab9782"), Color("a77766"), Color("d2b48d"), Vector2(0.72, 0.44), 0.25, 0.47, false],
	"jbr": [Color("c1ae95"), Color("9baca0"), Color("f0d1a8"), Vector2(0.77, 0.46), 0.23, 0.48, false],
	"mall": [Color("c2c0b9"), Color("abada9"), Color("676f73"), Vector2(0.9, 0.68), 0.3, 0.61, false],
	"gv": [Color("b49779"), Color("ab8370"), Color("75494a"), Vector2(0.58, 0.46), 0.31, 0.52, true],
	"boulevard": [Color("96918d"), Color("b6a898"), Color("726854"), Vector2(0.91, 0.53), -0.88, 0.27, true],
}

static func build(parent: Node3D, layout: String, size: Vector2, center: Vector3) -> void:
	var design: Array = DESIGNS[layout]
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("stone", design[0])
	material.set_shader_parameter("walk", design[1])
	material.set_shader_parameter("inlay", design[2])
	material.set_shader_parameter("slab", design[3])
	material.set_shader_parameter("walk_center", design[4])
	material.set_shader_parameter("walk_half_width", design[5])
	material.set_shader_parameter("mosaic", design[6])
	var mesh := MeshInstance3D.new()
	mesh.mesh = ModelLib.plane_mesh(size)
	mesh.material_override = material
	mesh.position = center
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

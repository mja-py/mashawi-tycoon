class_name FoodTruck
extends RefCounted
## Plot-space coordinates relative to the mobile stand. The same service points
## drive the hatch, staff, equipment and customer movement.

const SCALE := 0.88
const SILL_Y := 0.44
const HATCH_Z := 0.38
const GRILL := Vector3(-0.18, SILL_Y, 0.29)
const FRYER := Vector3(0.23, SILL_Y, 0.29)
const SWEETS := Vector3(0.60, SILL_Y, 0.29)
const TEA := Vector3(0.98, SILL_Y, 0.26)
const VENDOR := Vector3(-0.59, 0.24, 0.13)
const HELPER := Vector3(0.94, 0.24, 0.09)
const PICKUP := Vector3(-0.68, 0, 0.67)
const ORDER := Vector3(-0.29, 0, 0.67)
const SIGN := Vector3(0.24, 1.11, 0.455)

const ENAMEL := Color("22645f")
const DARK_TEAL := Color("194640")
const STONE := Color("e0c6a0")
const CAB_GLASS := Color("526b70")
const METAL := Color("a68e74")
const WHEEL := Color("302d2b")
const STEEL := Color("aeaaa0")
const EXTRACTOR := Vector3(0.05, 1.232, -0.20)

static func build(parent: Node3D) -> Label3D:
	var b := MeshBatch.new()
	# Wheelbase and cab are part of the same shell, with a visible kitchen floor.
	b.add_box(Vector3(2.80, 0.13, 0.86), WHEEL, _at(Vector3(-0.07, 0.19, -0.03)))
	for x in [-1.16, 0.96]:
		for z in [-0.43, 0.37]:
			var axle := Basis(Vector3.RIGHT, PI / 2)
			b.add_cyl(0.152, 0.10, WHEEL, Transform3D(axle, Vector3(x, 0.153, z)), 0.0, 20)
			b.add_cyl(0.082, 0.106, METAL, Transform3D(axle, Vector3(x, 0.153, z)), 0.0, 16)
			b.add_cyl(0.051, 0.116, DARK_TEAL, Transform3D(axle, Vector3(x, 0.153, z)), 0.0, 12)
			b.add_cyl(0.025, 0.121, STEEL, Transform3D(axle, Vector3(x, 0.153, z)), 0.0, 12)
	b.add_box(Vector3(0.74, 0.39, 0.79), ENAMEL, _at(Vector3(-1.15, 0.397, -0.04)))
	b.add_box(Vector3(0.49, 0.26, 0.71), CAB_GLASS, _at(Vector3(-1.05, 0.70, -0.04)))
	b.add_box(Vector3(0.54, 0.046, 0.77), STONE, _at(Vector3(-1.06, 0.84, -0.04)))
	b.add_box(Vector3(0.04, 0.235, 0.72), CAB_GLASS, Transform3D(Basis(Vector3.BACK, -0.18), Vector3(-1.30, 0.70, -0.04)))
	b.add_box(Vector3(0.55, 0.025, 0.79), DARK_TEAL, _at(Vector3(-1.06, 0.57, -0.04)))
	b.add_box(Vector3(0.07, 0.08, 0.84), METAL, _at(Vector3(-1.52, 0.25, -0.04)))
	for z in [-0.30, 0.21]:
		b.add_box(Vector3(0.021, 0.08, 0.10), STONE, _at(Vector3(-1.533, 0.47, z)), 0.25)
	b.add_box(Vector3(0.09, 0.018, 0.026), METAL, _at(Vector3(-1.01, 0.49, 0.363)))
	# A framed mirror, with the stalk fastened to the cab rather than the hatch.
	b.add_box(Vector3(0.027, 0.020, 0.10), WHEEL, _at(Vector3(-1.24, 0.65, 0.36)))
	b.add_box(Vector3(0.035, 0.082, 0.031), DARK_TEAL, _at(Vector3(-1.24, 0.675, 0.42)))
	b.add_box(Vector3(0.026, 0.066, 0.007), STEEL, _at(Vector3(-1.24, 0.675, 0.438)))
	# A genuine opening, with glass limited to the cab and display case.
	b.add_box(Vector3(2.12, 0.075, 0.90), PlotBuilders.DARK, _at(Vector3(0.24, 0.201, -0.056)))
	b.add_box(Vector3(2.12, 0.87, 0.053), STONE, _at(Vector3(0.24, 0.666, -0.49)), 0.15)
	for x in [-0.80, 1.28]:
		b.add_box(Vector3(0.056, 0.86, 0.88), ENAMEL, _at(Vector3(x, 0.67, -0.048)))
		b.add_box(Vector3(0.051, 0.58, 0.038), STONE, _at(Vector3(x, 0.72, HATCH_Z)))
	b.add_box(Vector3(2.13, 0.16, 0.08), DARK_TEAL, _at(Vector3(0.24, 0.35, HATCH_Z - 0.04)))
	b.add_box(Vector3(2.13, 0.03, 0.26), PlotBuilders.WOOD, _at(Vector3(0.24, SILL_Y - 0.015, HATCH_Z - 0.06)))
	b.add_box(Vector3(2.17, 0.072, 0.98), ENAMEL, _at(Vector3(0.24, 1.15, -0.05)))
	b.add_box(Vector3(2.02, 0.031, 0.82), STONE, _at(Vector3(0.24, 1.20, -0.06)))
	b.add_box(Vector3(2.10, 0.139, 0.06), DARK_TEAL, _at(Vector3(0.24, 1.105, 0.411)))
	b.add_box(Vector3(2.18, 0.016, 0.055), METAL, _at(Vector3(0.24, 1.035, 0.402)))
	for i in range(13):
		var x := -0.75 + i * 0.162
		b.add_box(Vector3(0.162, 0.018, 0.13), ENAMEL if i % 2 == 0 else STONE,
			Transform3D(Basis(Vector3.RIGHT, 0.14), Vector3(x, 1.021, HATCH_Z + 0.018)))
	for i in range(5):
		b.add_box(Vector3(0.29, 0.025, 0.012), METAL, _at(Vector3(-0.51 + i * 0.36, 0.351, HATCH_Z + 0.008)))
	for x in [PICKUP.x, ORDER.x]:
		b.add_box(Vector3(0.22, 0.062, 0.022), DARK_TEAL, _at(Vector3(x, 0.31, HATCH_Z + 0.005)))
	# A shallow steel shroud with a dark recess and stationary rim around the rotor.
	b.add_box(Vector3(0.31, 0.052, 0.28), STEEL, _at(EXTRACTOR + Vector3.UP * 0.014))
	b.add_cyl(0.116, 0.018, METAL, _at(EXTRACTOR + Vector3.UP * 0.045), 0.0, 20)
	b.add_cyl(0.095, 0.010, WHEEL, _at(EXTRACTOR + Vector3.UP * 0.053), 0.0, 20)
	b.flush(parent)
	var rotor := Node3D.new()
	rotor.name = "ExtractorRotor"
	rotor.position = EXTRACTOR + Vector3.UP * 0.061
	parent.add_child(rotor)
	var blades := MeshBatch.new()
	blades.add_cyl(0.024, 0.015, STEEL, Transform3D.IDENTITY, 0.0, 12)
	for i in range(4):
		var turn := Basis(Vector3.UP, i * PI / 2.0)
		blades.add_box(Vector3(0.034, 0.008, 0.059), STEEL, Transform3D(turn * Basis(Vector3.BACK, 0.27), turn * Vector3(0, 0.003, 0.052)))
	for mesh in blades.flush(rotor):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return PlotBuilders.sign(parent, SIGN, 66, 0.0026, "ui.sign", STONE)

static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)

class_name PlotBuilders
extends RefCounted
## Shared pieces for the stand and the plot build-out (canopy stripes, name boards,
## mangals, smoke, string lights, lanterns). All static; callers own the nodes.

## Every model the plot spawns, so tools/unused_assets.sh sees them as used.
const PROPS := {
	"barrel": "food/barrel", "carton": "food/carton", "bag": "food/bag", "pot": "food/pot",
	"bowl": "food/bowl", "board": "food/cutting-board", "cone": "cars/cone", "dumpster": "street/dumpster",
	"pole": "street/electricity-pole", "wires": "street/electricity-wires",
	"awning": "buildings/detail-awning-wide", "parasol_a": "buildings/detail-parasol-a", "parasol_b": "buildings/detail-parasol-b",
	"table": "furniture/table-set", "planter": "suburban/planter", "bush": "nature/plant_bush",
	"pita": "food/pita-stack", "tajine": "food/tajine", "doner": "food/doner-spit", "fries": "food/fries",
	"styrofoam": "food/styrofoam", "samovar": "props/samovar", "cup_tea": "food/cup-tea", "pot_stew": "food/pot-stew",
	"sweets": "food/sweets-counter", "cake": "food/cake", "plate": "food/plate", "cup": "food/cup",
	"neon_frame": "props/neon-frame", "pylon": "props/pylon-sign", "lantern": "props/lantern", "fan": "props/pedestal-fan",
	"skewer": "food/skewer", "skewer_veg": "food/skewer-vegetables", "charcoal": "food/charcoal-bag",
}

const RED := Color(0.52, 0.13, 0.16)
const CREAM := Color(0.97, 0.92, 0.80)
const WOOD := Color(0.50, 0.33, 0.18)
const GOLD := Color(0.85, 0.66, 0.25)
const DARK := Color(0.16, 0.14, 0.13)
const STEEL := Color(0.72, 0.74, 0.76)
const COAL := Color(1.0, 0.4, 0.05)

static func spawn(key: String, parent: Node, pos: Vector3, rot_y_deg: float = 0.0, scale: float = 1.0, shadow: bool = true) -> Node3D:
	var n := ModelLib.spawn(PROPS[key], parent, pos, rot_y_deg, scale)
	if n and not shadow:
		no_shadow(n)
	return n

## Small props do not need to cast shadows (each shadow caster is another draw call).
static func no_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		no_shadow(c)

## Cream stripes across a canopy box of size w x d (children of the canopy mesh).
static func stripes(roof: Node3D, w: float, d: float, col: Color = Color(0.97, 0.93, 0.82), h: float = 0.052) -> void:
	var n := int(w / 0.18)
	for i in range(n):
		if i % 2 == 1:
			ModelLib.box(roof, Vector3(0.18, h, d), Vector3(-w / 2 + 0.09 + i * 0.18, 0.0, 0.0), col)

## The stand's name board text.
static func sign(parent: Node3D, pos: Vector3, font_size: int, pixel_size: float, key: String = "ui.sign",
		color: Color = Color(0.45, 0.1, 0.1)) -> Label3D:
	var l := Label3D.new()
	l.text = TranslationServer.translate(key)
	l.font = UiTheme.font()
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	return l

## n charcoal mangals side by side starting at pos (one 0.17 wide each). Returns the coal glow meshes.
static func grill(parent: Node3D, pos: Vector3, n: int, batch: MeshBatch = null) -> Array:
	var glows := []
	for i in range(n):
		var p := pos + Vector3(i * 0.2, 0, 0)
		var body := Vector3(0.17, 0.06, 0.13)
		if batch:
			batch.add_box(body, DARK, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.03, 0)))
		else:
			ModelLib.box(parent, body, p + Vector3(0, 0.03, 0), DARK)
		glows.append(ModelLib.box(parent, Vector3(0.15, 0.008, 0.11), p + Vector3(0, 0.064, 0), COAL, 1.6))
		var sk := spawn("skewer" if i % 2 == 0 else "skewer_veg", parent, p + Vector3(0, 0.07, 0.0), 90, 0.32, false)
		if sk:
			sk.rotation.y = deg_to_rad(90)
	return glows

## Grill smoke rising from pos (keep these few: one GPUParticles3D each).
static func smoke(parent: Node3D, pos: Vector3, extents: Vector3 = Vector3(0.08, 0.01, 0.06), amount: int = 16) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.18
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, 0.12, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.alpha_curve = ct
	p.process_material = pm
	p.amount = amount
	p.lifetime = 1.6
	p.position = pos
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.056
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 0.85, 0.85, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	p.draw_pass_1 = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p

## Fine water mist (misting fan).
static func mist(parent: Node3D, pos: Vector3, dir: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 18.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, -0.1, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.6
	p.process_material = pm
	p.amount = 24
	p.lifetime = 1.0
	p.position = pos
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = m
	p.draw_pass_1 = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p

const BULB_COLS := [Color(1.0, 0.82, 0.45), Color(1.0, 0.55, 0.3), Color(1.0, 0.92, 0.7)]

## A sagging strand from a to b: wire pieces into the batch, bulbs as one MultiMesh
## (returned so set_night can swap its material).
static func string_lights(parent: Node3D, batch: MeshBatch, a: Vector3, b: Vector3, n: int, sag: float = 0.08) -> MultiMeshInstance3D:
	var pts: Array[Vector3] = []
	for i in range(n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	for i in range(n):
		var mid := (pts[i] + pts[i + 1]) * 0.5
		var d := pts[i + 1] - pts[i]
		var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.FORWARD)
		batch.add_box(Vector3(0.008, 0.008, d.length()), DARK, Transform3D(basis, mid))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	sm.radial_segments = 8
	sm.rings = 4
	mm.mesh = sm
	mm.instance_count = n - 1
	for i in range(1, n):
		mm.set_instance_transform(i - 1, Transform3D(Basis.IDENTITY, pts[i] - Vector3(0, 0.025, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bulb_material(false)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

static func bulb_material(night: bool) -> StandardMaterial3D:
	return ModelLib.flat_material(Color(1.0, 0.85, 0.5), 3.0 if night else 0.4)

## Night glass for the lantern model's "amber glass" surface (surface 1).
static func lantern_glass(night: bool) -> Material:
	return ModelLib.flat_material(Color(1.0, 0.68, 0.3), 3.5) if night else null

## A thin post from the ground to height h into the batch.
static func post(batch: MeshBatch, pos: Vector3, h: float, col: Color = DARK, w: float = 0.03) -> void:
	batch.add_box(Vector3(w, h, w), col, Transform3D(Basis.IDENTITY, pos + Vector3(0, h / 2.0, 0)))

## Night-only point light (caller registers it for set_night).
static func omni(parent: Node3D, pos: Vector3, col: Color, energy: float = 1.2, rng: float = 2.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.visible = false
	parent.add_child(l)
	return l

static var _lantern_night: Mesh

## The lantern model's mesh; the night copy has an emissive amber glass surface.
static func lantern_mesh(night: bool) -> Mesh:
	var base := ModelLib.mesh_of(PROPS["lantern"])
	if base == null or not night:
		return base
	if _lantern_night == null:
		var am := (base as ArrayMesh).duplicate() as ArrayMesh
		if am.get_surface_count() > 1:
			am.surface_set_material(1, lantern_glass(true))
		_lantern_night = am
	return _lantern_night

## Many lanterns as one MultiMesh (swap .multimesh.mesh with lantern_mesh() at night).
static func lantern_batch(parent: Node3D, xforms: Array) -> MultiMeshInstance3D:
	var mesh := lantern_mesh(false)
	if mesh == null or xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

## A lantern hanging at p (scaled), as a transform for lantern_batch().
static func lantern_at(p: Vector3, scale: float = 1.0) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * scale), p)

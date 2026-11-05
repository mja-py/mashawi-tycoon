class_name Plot
extends Node3D
## The player's site on the street: the stand rig for stages 0-2 (cart, stall, truck)
## and the fixed kiosk with its terrace from stage 3 up, plus every station's visual
## tier, the seats customers sit at and the night lights. Origin = the building line
## at x 0 (World.FRONT_Z); +Z faces the street. apply(state) is idempotent: each piece
## lives under a key in _built and only missing / unwanted keys are (re)built / freed.

const PLOT_POS := Vector3(0.0, 0.0, -1.62)
## Half-width of the hole the street rows leave for the plot, per stage.
## The truck (stage 2) needs a short gap too, or its body sits inside the houses.
const GAP := [1.05, 1.65, 1.8, 2.4, 3.0, 3.6]
const SEAT_CAP := [0, 0, 0, 10, 12, 16]
const FIXED := 3
const MAX_SMOKE := 3
## stages 0-2: the stand sits at World.CART_POS
const STAND_POS := Vector3(0.0, 0.0, 0.2)
const STAND_SCALE := 0.72
## kiosk (plot space)
const K_X := 0.75
const K_W := 1.9
const K_BACK := -0.95
const K_FRONT := 0.15
const K_H := 1.25
const WIN_W := 1.5
const WIN_TOP := 0.91
const COUNTER_Y := 0.41
## kitchen line: just behind the window sill (the camera looks down, so only things
## close to the window show through it)
const LINE_Z := -0.01
const CREW_Y := 0.16
const CHIMNEY_Z := -0.5
## terrace
const TABLE_SCALE := 0.75
const CHAIR_X := 0.19
const ROWS := [0.12, -0.3, -0.72]
const AISLE_Z := 0.52
const RAIL_Z := 0.72

const CREAM := Color(0.96, 0.9, 0.78)
const TRIM := Color(0.52, 0.13, 0.16)
const TILE := Color(0.55, 0.75, 0.72)
const FLOOR := Color(0.36, 0.3, 0.26)
const STEEL := Color(0.72, 0.74, 0.76)
const DECK := Color(0.78, 0.66, 0.5)

var cart: MashawiStand
var stage := -1
var _gap := 0.0
var _built := {}
var _night := false
var _night_set := false
var _lights: Array = []
var _lanterns: Array = []
var _bulbs: Array = []
var _neon: Array = []
var _night_only: Array = []
var _spits: Array = []
var _fans: Array = []
var _smokes: Array = []
var _crew: Array = []
var _t := 0.0
var simulation_speed := 1.0
## {idx, table, pos (plot space), facing, approach (plot space), y_off, who}
var seats: Array = []
## {pos, node (plate holder), dirty, left}
var tables: Array = []
var _slots: Array = []
var _music_spot := Vector3.ZERO
var _helper: Node3D
var _board: Label3D
var _applied := false
var _stall_board: Label3D

func _init() -> void:
	cart = MashawiStand.new()
	cart.position = STAND_POS
	cart.scale = Vector3.ONE * STAND_SCALE
	cart.serving_hook = _on_serving
	add_child(cart)

## Half-width of the street gap a stage needs (0 = none).
static func footprint(stage_tier: int) -> float:
	return float(GAP[clampi(stage_tier, 0, GAP.size() - 1)])

# ---------------------------------------------------------------- state

func apply(state: Dictionary) -> void:
	var st := clampi(int(state.get("stage", 0)), 0, GAP.size() - 1)
	if st != stage:
		for k in _built.keys():
			_free_key(k)
		stage = st
		_gap = footprint(st)
		seats.clear()
		tables.clear()
		_layout_terrace()
	var stations: Dictionary = state.get("stations", {})
	var wanted := _wanted(stations)
	for k in _built.keys():
		if not wanted.has(k):
			_free_key(k)
	_prune()
	cart.visible = stage < FIXED
	cart.process_mode = Node.PROCESS_MODE_INHERIT if stage < FIXED else Node.PROCESS_MODE_DISABLED
	cart.set_stall(stage == 1)
	var any := false
	for k in wanted:
		if _built.has(k):
			continue
		var n := Node3D.new()
		n.name = k.replace(":", "_")
		add_child(n)
		_built[k] = n
		var spec: Array = wanted[k]
		callv(spec[0], [n] + spec.slice(1))
		if _applied:
			_grow(n)
		any = true
	# from neon signage up the neon replaces the painted name (one name per stand, never two)
	var neon := _tier(stations, "signage") >= 3
	if _alive(_board):
		_board.visible = not neon
	if _alive(_stall_board):
		_stall_board.visible = not neon
	cart.set_neon(neon and stage < FIXED)
	if _alive(_helper):
		# a second pair of hands once the grill or the counter is busy enough
		_helper.visible = int(stations.get("grill", 0)) >= 4 or int(stations.get("counter", 0)) >= 4
	if any:
		_night_set = false
		set_night(_night)
	_applied = true

## A freshly bought piece rises out of the ground (build feedback after a purchase).
func _grow(n: Node3D) -> void:
	n.scale.y = 0.05
	var tw := n.create_tween()
	tw.tween_property(n, "scale:y", 1.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _tier(stations: Dictionary, id: String) -> int:
	return Data.station_tier(int(stations.get(id, 0))) if stations.has(id) else -1

## key -> [builder method, args...]
func _wanted(stations: Dictionary) -> Dictionary:
	var w := {}
	var s := str(stage)
	w["stage:" + s] = ["_build_stage"]
	if stage < FIXED:
		var lt := _tier(stations, "lights")
		if lt > 0:
			w["station:lights:%d:%s" % [lt, s]] = ["_rig_lights", lt]
		return w
	for id in ["counter", "grill"]:
		# the kiosk always comes with a till and one mangal
		var t := maxi(_tier(stations, id), 1) if stations.has(id) else 1
		w["station:%s:%d:%s" % [id, t, s]] = ["_st_" + id, t]
	for id in ["doner", "fryer", "karak", "sweets", "signage", "lights", "music", "shade"]:
		var t := _tier(stations, id)
		if t > 0:
			w["station:%s:%d:%s" % [id, t, s]] = ["_st_" + id, t]
	var cold := clampi(int(stations.get("coldbox", 0)), 0, 3)
	if cold > 0:
		w["station:coldbox:%d:%s" % [mini(cold, 3) / 3 + 1, s]] = ["_st_coldbox", mini(cold, 3) / 3 + 1]
	var n_seats := mini(int(stations.get("seating", 0)) * int(Data.STATIONS["seating"].get("seats_per_level", 2)), int(SEAT_CAP[stage]))
	var n_tables := mini(n_seats / 2, _slots.size())
	if n_tables > 0:
		w["seating:%d:%s" % [n_tables, s]] = ["_build_seating", n_tables]
	return w

func _free_key(k: String) -> void:
	var n: Node = _built.get(k)
	_built.erase(k)
	if n and is_instance_valid(n):
		n.queue_free()
	if k.begins_with("seating:"):
		seats.clear()
		tables.clear()

static func _alive(n) -> bool:
	return n != null and is_instance_valid(n) and not (n as Node).is_queued_for_deletion()

func _prune() -> void:
	for arr in [_lights, _lanterns, _bulbs, _neon, _night_only, _spits, _fans, _smokes, _crew]:
		for i in range(arr.size() - 1, -1, -1):
			if not _alive(arr[i]):
				arr.remove_at(i)

func _light(parent: Node3D, pos: Vector3, col: Color, energy: float = 1.2, rng: float = 2.0) -> OmniLight3D:
	# hard cap: 4 point lights per plot (the cart's own neon light counts at stages 0-2)
	if _lights.size() >= (3 if stage < FIXED else 4):
		return null
	var l := PlotBuilders.omni(parent, pos, col, energy, rng)
	_lights.append(l)
	return l

func _smoke(parent: Node3D, pos: Vector3, extents: Vector3, amount: int) -> void:
	if _smokes.size() >= MAX_SMOKE - (1 if stage < FIXED else 0):
		return
	_smokes.append(PlotBuilders.smoke(parent, pos, extents, amount))

# ---------------------------------------------------------------- contract for the sim

func queue_slot(i: int) -> Vector3:
	if stage < FIXED:
		return World.CART_POS + Vector3(0.05 + 0.5 * i, 0, 0.42 + 0.02 * i)
	return position + Vector3(K_X - 0.35 + 0.48 * i, 0, 0.76 + 0.012 * i)

func pickup_slot(i: int) -> Vector3:
	var actor := server()
	var base := actor.global_position if actor else World.CART_POS
	base.y = 0.0
	return base + Vector3(-0.14 - 0.34 * i, 0.0, (0.40 if stage < FIXED else 0.69) + 0.07 * i)

func server() -> Node3D:
	if stage < FIXED:
		return cart.server()
	return _crew[0] if not _crew.is_empty() and _alive(_crew[0]) else null

## A seat counts as held only while its customer is actually headed for it or sitting
## (a take-away guest handed a seat without using it does not block it).
static func _holds(who) -> bool:
	return who != null and is_instance_valid(who) and who is Customer and not (who as Customer).seat.is_empty()

func free_seat() -> Dictionary:
	for s in seats:
		if _holds(s["who"]):
			continue
		if bool(tables[int(s["table"])]["dirty"]):
			continue
		return {"idx": s["idx"], "table": s["table"], "pos": position + (s["pos"] as Vector3), "facing": s["facing"],
			"approach": position + (s["approach"] as Vector3), "y_off": s["y_off"]}
	return {}

func take_seat(idx: int, who) -> void:
	if idx >= 0 and idx < seats.size():
		seats[idx]["who"] = who

func release_seat(idx: int) -> void:
	if idx >= 0 and idx < seats.size() and not _holds(seats[idx]["who"]):
		seats[idx]["who"] = null

func set_table_dirty(table: int, dirty: bool) -> void:
	if table < 0 or table >= tables.size():
		return
	var t: Dictionary = tables[table]
	t["dirty"] = dirty
	# nobody on the sim side buses tables yet: clear them after the cleaning time
	t["left"] = maxf(float(Data.STATIONS["seating"].get("clean_min", 3.0)) * Data.REAL_SECONDS_PER_GAME_HOUR / 60.0, 1.0)
	if _alive(t["node"]):
		(t["node"] as Node3D).visible = dirty

func dirty_tables() -> Array:
	var out := []
	for i in range(tables.size()):
		if tables[i]["dirty"]:
			out.append(i)
	return out

func set_serving(on: bool) -> void:
	cart.set_serving(on)

func _on_serving(on: bool) -> void:
	_serving = on
	for i in range(_crew.size()):
		var c: Node3D = _crew[i]
		if _alive(c) and c.visible:
			ModelLib.play_loop(c, "interact-right" if on and i == 0 else "idle", 1.3 if on and i == 0 else 1.0)

var _serving := false

func set_night(is_night: bool) -> void:
	if is_night == _night and _night_set:
		return
	_night = is_night
	_night_set = true
	cart.set_night(is_night)
	_prune()
	for l in _lights:
		l.visible = is_night
	var lm := PlotBuilders.lantern_mesh(is_night)
	for m in _lanterns:
		(m as MultiMeshInstance3D).multimesh.mesh = lm
	for b in _bulbs:
		(b as GeometryInstance3D).material_override = PlotBuilders.bulb_material(is_night)
	for n in _neon:
		(n as Label3D).outline_size = 18 if is_night else 6
	for n in _night_only:
		(n as Node3D).visible = is_night

func _process(delta: float) -> void:
	_t += delta
	for s in _spits:
		if is_instance_valid(s):
			(s as Node3D).rotation.y += delta * 1.2
	for f in _fans:
		if is_instance_valid(f):
			(f as Node3D).rotation.y = sin(_t * 0.8) * 0.7
	for t in tables:
		if t["dirty"]:
			t["left"] = float(t["left"]) - delta * simulation_speed
			if float(t["left"]) <= 0.0:
				set_table_dirty(tables.find(t), false)

# ---------------------------------------------------------------- helpers

static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)

static func _rx(p: Vector3, a: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, a), p)

func _crew_member(parent: Node3D, female: bool, pos: Vector3, rot: float = 0.0) -> Node3D:
	var n := ModelLib.spawn_crew(female, parent, pos, rot, 0.6)
	if n:
		ModelLib.play_loop(n, "idle")
		_crew.append(n)
	return n

func _label(parent: Node3D, pos: Vector3, key: String, size: int, px: float, col: Color) -> Label3D:
	var l := PlotBuilders.sign(parent, pos, size, px, key, col)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l

# ---------------------------------------------------------------- stages

func _build_stage(n: Node3D) -> void:
	match stage:
		0: _build_cart_court(n)
		1: _build_stall(n)
		2: _build_truck(n)
		_: _build_kiosk(n)

## A little souk courtyard gives the first cart its own silhouette and a clear queue.
## All decoration is batched; the pavement stays level with the pedestrian path.
func _build_cart_court(n: Node3D) -> void:
	var b := MeshBatch.new()
	b.add_box(Vector3(2.02, 0.025, 1.35), Color("d5ba91"), _at(Vector3(0, 0.004, 0.05)))
	for x in range(-4, 5):
		for z in range(5):
			var col := Color("c6a47c") if (x + z) % 2 == 0 else Color("dfc7a2")
			b.add_box(Vector3(0.216, 0.008, 0.24), col, _at(Vector3(x * 0.223, 0.021, -0.47 + z * 0.25)))
	for sx in [-0.91, 0.91]:
		b.add_box(Vector3(0.24, 0.25, 0.27), Color("b56849"), _at(Vector3(sx, 0.13, -0.34)))
		b.add_box(Vector3(0.27, 0.035, 0.3), PlotBuilders.CREAM, _at(Vector3(sx, 0.26, -0.34)))
		for i in range(3):
			b.add_cyl(0.075, 0.14 if i == 1 else 0.1, Color("3e8271") if i == 1 else Color("65935d"), _at(Vector3(sx - 0.065 + i * 0.065, 0.32, -0.34)), 0.0, 6)
		PlotBuilders.post(b, Vector3(sx, 0, -0.55), 1.34, PlotBuilders.WOOD, 0.025)
	_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(-0.91, 1.34, -0.55), Vector3(0.91, 1.34, -0.55), 9, 0.16))
	# Small pavement inlay leads the eye to the serving counter, clear of the walking lane.
	for sx in [-0.18, 0.18]:
		b.add_box(Vector3(0.055, 0.009, 0.14), PlotBuilders.GOLD, _at(Vector3(sx, 0.027, 0.62)))
	b.flush(n)

## Stage 1: canopy on four posts over the wheel-less stand, A-board and props.
func _build_stall(n: Node3D) -> void:
	n.position = STAND_POS
	var b := MeshBatch.new()
	for sx in [-0.62, 0.62]:
		for sz in [-0.17, 0.4]:
			PlotBuilders.post(b, Vector3(sx, 0, sz), 1.0 + (0.05 if sz < 0 else 0.0), PlotBuilders.WOOD, 0.035)
	var canopy := ModelLib.box(n, Vector3(1.42, 0.03, 0.78), Vector3(0, 1.03, 0.11), PlotBuilders.RED)
	canopy.rotation.x = deg_to_rad(5)
	PlotBuilders.stripes(canopy, 1.42, 0.78, Color(0.97, 0.93, 0.82), 0.032)
	# scalloped valance at the front
	for i in range(8):
		b.add_box(Vector3(0.16, 0.06, 0.01), PlotBuilders.RED if i % 2 == 0 else PlotBuilders.CREAM,
			_at(Vector3(-0.63 + i * 0.18, 0.98, 0.505)))
	b.add_box(Vector3(1.0, 0.17, 0.03), PlotBuilders.CREAM, _at(Vector3(0, 1.14, 0.48)))
	b.add_box(Vector3(1.04, 0.02, 0.035), PlotBuilders.GOLD, _at(Vector3(0, 1.235, 0.48)))
	_stall_board = _label(n, Vector3(0, 1.14, 0.5), "ui.sign", 72, 0.0026, Color(0.45, 0.1, 0.1))
	# A-board menu: two leaning boards
	var ab := Node3D.new()
	ab.position = Vector3(-1.42, 0, 0.6)
	ab.rotation.y = deg_to_rad(20)
	n.add_child(ab)
	for side in [-1.0, 1.0]:
		var pnl := ModelLib.box(ab, Vector3(0.24, 0.34, 0.02), Vector3(0, 0.16, side * 0.06), Color(0.2, 0.18, 0.16))
		pnl.rotation.x = side * deg_to_rad(-12)
	ModelLib.box(ab, Vector3(0.2, 0.26, 0.004), Vector3(0, 0.17, 0.08), Color(0.25, 0.32, 0.28))
	var menu := _label(ab, Vector3(0, 0.25, 0.085), "ui.menu", 40, 0.0022, Color(0.97, 0.93, 0.82))
	menu.rotation.x = deg_to_rad(-12)
	# props: barrels, a carton and a sack by the side, a prep table with pot, bowl and board
	PlotBuilders.spawn("barrel", n, Vector3(-1.5, 0, -0.08), 10, 0.35)
	PlotBuilders.spawn("barrel", n, Vector3(-1.78, 0, 0.0), 40, 0.32)
	b.add_box(Vector3(0.42, 0.3, 0.28), PlotBuilders.WOOD, _at(Vector3(1.2, 0.15, -0.02)))
	b.add_box(Vector3(0.46, 0.025, 0.32), PlotBuilders.CREAM, _at(Vector3(1.2, 0.31, -0.02)))
	PlotBuilders.spawn("pot", n, Vector3(1.09, 0.32, -0.04), 0, 0.2, false)
	PlotBuilders.spawn("bowl", n, Vector3(1.3, 0.32, 0.06), 0, 0.2, false)
	PlotBuilders.spawn("board", n, Vector3(1.3, 0.32, -0.08), 90, 0.2, false)
	PlotBuilders.spawn("carton", n, Vector3(1.53, 0, -0.08), 0, 0.4)
	PlotBuilders.spawn("bag", n, Vector3(1.68, 0, 0.02), -20, 0.4)
	b.flush(n)

## Stage 2: the food truck (drawn by the stand) + cones at the kerb, a dumpster and a power hookup.
func _build_truck(n: Node3D) -> void:
	n.position = STAND_POS
	PlotBuilders.spawn("cone", n, Vector3(-1.25, 0, 0.98), 0, 0.26)
	PlotBuilders.spawn("cone", n, Vector3(1.3, 0, 0.98), 30, 0.26)
	PlotBuilders.spawn("dumpster", n, Vector3(1.6, 0, -0.02), -90, 1.2)
	PlotBuilders.spawn("pole", n, Vector3(-1.55, 0, -0.1), 0, 2.0)
	var b := MeshBatch.new()
	# cable from the pole to the truck: one continuous sagging line
	var pts: Array[Vector3] = []
	for i in range(7):
		var t := i / 6.0
		pts.append(Vector3(-1.48 + t * 0.7, 0.85 - 0.6 * t + 0.25 * t * t, -0.1))
	for i in range(6):
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		b.add_box(Vector3(0.012, 0.012, a.distance_to(c) + 0.01), PlotBuilders.DARK, Transform3D(Basis.looking_at(c - a, Vector3.UP), (a + c) / 2.0))
	b.flush(n)

## Stage 3+: a fixed booth at the building line with a service window and a terrace on its -X side.
func _build_kiosk(n: Node3D) -> void:
	var b := MeshBatch.new()
	var x0 := K_X - K_W / 2.0
	var x1 := K_X + K_W / 2.0
	var d := K_FRONT - K_BACK
	var zc := (K_FRONT + K_BACK) / 2.0
	var th := 0.06
	# walls
	b.add_box(Vector3(K_W, K_H, th), CREAM, _at(Vector3(K_X, K_H / 2.0, K_BACK + th / 2.0)))
	for sx in [x0 + th / 2.0, x1 - th / 2.0]:
		b.add_box(Vector3(th, K_H, d), CREAM, _at(Vector3(sx, K_H / 2.0, zc)))
	var fz := K_FRONT - th / 2.0
	b.add_box(Vector3(K_W, COUNTER_Y, th), CREAM, _at(Vector3(K_X, COUNTER_Y / 2.0, fz)))
	b.add_box(Vector3(K_W, K_H - WIN_TOP, th), CREAM, _at(Vector3(K_X, (WIN_TOP + K_H) / 2.0, fz)))
	var side_w := (K_W - WIN_W) / 2.0
	for sx in [x0 + side_w / 2.0, x1 - side_w / 2.0]:
		b.add_box(Vector3(side_w, WIN_TOP - COUNTER_Y, th), CREAM, _at(Vector3(sx, (WIN_TOP + COUNTER_Y) / 2.0, fz)))
	# red base band and gold window frame
	b.add_box(Vector3(K_W + 0.01, 0.1, d + 0.01), TRIM, _at(Vector3(K_X, 0.05, zc)))
	b.add_box(Vector3(WIN_W + 0.04, 0.025, 0.02), PlotBuilders.GOLD, _at(Vector3(K_X, WIN_TOP, K_FRONT + 0.005)))
	for sx in [K_X - WIN_W / 2.0, K_X + WIN_W / 2.0]:
		b.add_box(Vector3(0.025, WIN_TOP - COUNTER_Y, 0.02), PlotBuilders.GOLD, _at(Vector3(sx, (WIN_TOP + COUNTER_Y) / 2.0, K_FRONT + 0.005)))
	# inside: dark floor, tiled back wall and the steel kitchen line behind the sill
	# raised floor so the crew shows above the kitchen line
	b.add_box(Vector3(K_W - 0.12, CREW_Y, d - 0.12), FLOOR, _at(Vector3(K_X, CREW_Y / 2.0, zc)))
	b.add_box(Vector3(K_W - 0.14, 0.7, 0.01), TILE, _at(Vector3(K_X, 0.35, K_BACK + th + 0.006)))
	b.add_box(Vector3(K_W - 0.14, COUNTER_Y - 0.02, 0.2), Color(0.5, 0.4, 0.32), _at(Vector3(K_X, (COUNTER_Y - 0.02) / 2.0, LINE_Z)))
	b.add_box(Vector3(K_W - 0.14, 0.02, 0.21), STEEL, _at(Vector3(K_X, COUNTER_Y - 0.01, LINE_Z)))
	# wood counter slab protruding through the window
	b.add_box(Vector3(WIN_W + 0.1, 0.04, 0.17), PlotBuilders.WOOD, _at(Vector3(K_X, COUNTER_Y + 0.02, K_FRONT + 0.03)))
	# roof slab, parapet and a hood + chimney over the grill
	b.add_box(Vector3(K_W + 0.12, 0.06, d + 0.12), CREAM.darkened(0.08), _at(Vector3(K_X, K_H + 0.03, zc + 0.03)))
	for sz in [K_BACK - 0.02, K_FRONT + 0.08]:
		b.add_box(Vector3(K_W + 0.12, 0.08, 0.04), TRIM, _at(Vector3(K_X, K_H + 0.1, sz)))
	for sx in [x0 - 0.04, x1 + 0.04]:
		b.add_box(Vector3(0.04, 0.08, d + 0.12), TRIM, _at(Vector3(sx, K_H + 0.1, zc + 0.03)))
	b.add_cyl(0.05, 0.4, STEEL.darkened(0.3), _at(Vector3(x0 + 0.3, K_H + 0.15, CHIMNEY_Z)))
	b.add_cyl(0.07, 0.03, STEEL.darkened(0.4), _at(Vector3(x0 + 0.3, K_H + 0.36, CHIMNEY_Z)))
	# signboard on the roof front with the stand name
	b.add_box(Vector3(1.5, 0.28, 0.05), CREAM, _at(Vector3(K_X, K_H + 0.2, K_FRONT + 0.06)))
	b.add_box(Vector3(1.54, 0.03, 0.06), TRIM, _at(Vector3(K_X, K_H + 0.355, K_FRONT + 0.06)))
	_board = _label(n, Vector3(K_X, K_H + 0.2, K_FRONT + 0.09), "ui.sign", 96, 0.0032, Color(0.45, 0.1, 0.1))
	var aw := PlotBuilders.spawn("awning", n, Vector3(K_X, WIN_TOP + 0.02, K_FRONT - 0.13), 0, 1.0)
	if aw:
		aw.scale = Vector3(1.95, 0.8, 1.4)
	# crew behind the counter
	# crew stand at the window ends so the stations behind them stay visible
	_crew_member(n, true, Vector3(K_X - 0.36, CREW_Y, -0.22), 15)
	_helper = _crew_member(n, false, Vector3(K_X + 0.36, CREW_Y, -0.24), -15)
	_build_terrace(n, b)
	b.flush(n)

# ---------------------------------------------------------------- terrace + seating

func _layout_terrace() -> void:
	_slots.clear()
	if stage < FIXED:
		return
	var cols := []
	var x := -0.6
	while x - 0.25 >= -_gap + 0.04:
		cols.append(x)
		x -= 0.7
	for r in range(ROWS.size()):
		for c in range(cols.size()):
			if r == ROWS.size() - 1 and c == cols.size() - 1:
				_music_spot = Vector3(cols[c], 0, ROWS[r])
				continue
			_slots.append({"x": cols[c], "z": ROWS[r], "row": r, "col": c})

func _build_terrace(n: Node3D, b: MeshBatch) -> void:
	var left := -_gap + 0.03
	var right := -0.28
	b.add_box(Vector3(right - left, 0.012, RAIL_Z + 0.1 - (K_BACK + 0.05)), DECK,
		_at(Vector3((left + right) / 2.0, 0.006, (RAIL_Z + 0.1 + K_BACK + 0.05) / 2.0)))
	# planters with bushes as a low rail, between the chair lanes
	var xs := []
	for s in _slots:
		if int(s["row"]) == 0:
			xs.append(float(s["x"]))
	for x in xs:
		# small enough to stay clear of the chair lanes either side (table x +- 0.19)
		b.add_model(PlotBuilders.PROPS["planter"], Transform3D(Basis.from_scale(Vector3.ONE * 0.5), Vector3(x, 0, RAIL_Z)))
		b.add_model(PlotBuilders.PROPS["bush"], Transform3D(Basis.from_scale(Vector3.ONE * 0.38), Vector3(x, 0.09, RAIL_Z)))
	# two parasols over the middle row
	var mid := []
	for s in _slots:
		if int(s["row"]) == 1:
			mid.append(s)
	if mid.size() >= 1:
		PlotBuilders.spawn("parasol_a", n, Vector3(mid[0]["x"], 0, mid[0]["z"]), 0, 1.35)
	if mid.size() >= 3:
		PlotBuilders.spawn("parasol_b", n, Vector3(mid[2]["x"], 0, mid[2]["z"]), 30, 1.35)

func _build_seating(n: Node3D, count: int) -> void:
	seats.clear()
	tables.clear()
	var b := MeshBatch.new()
	var y_off := 0.17 * TABLE_SCALE
	for i in range(mini(count, _slots.size())):
		var s: Dictionary = _slots[i]
		var p := Vector3(s["x"], 0, s["z"])
		b.add_model(PlotBuilders.PROPS["table"], Transform3D(Basis.from_scale(Vector3.ONE * TABLE_SCALE), p))
		var dirt := Node3D.new()
		dirt.position = p + Vector3(0, 0.24 * TABLE_SCALE, 0)
		dirt.visible = false
		n.add_child(dirt)
		PlotBuilders.spawn("plate", dirt, Vector3(-0.03, 0, 0), 0, 0.2, false)
		PlotBuilders.spawn("cup", dirt, Vector3(0.08, 0, 0.04), 0, 0.2, false)
		ModelLib.box(dirt, Vector3(0.05, 0.012, 0.04), Vector3(0.05, 0.006, -0.05), Color(0.95, 0.95, 0.92))
		tables.append({"pos": p, "node": dirt, "dirty": false, "left": 0.0})
		for side in [-1.0, 1.0]:
			var chair := p + Vector3(side * CHAIR_X, 0, 0)
			var lane: float = chair.x if int(s["row"]) == 0 else chair.x + side * 0.15
			seats.append({"idx": 0, "table": i, "pos": chair, "facing": -side * PI / 2.0,
				"approach": Vector3(lane, 0, AISLE_Z), "y_off": y_off, "who": null})
	# hand out the seats closest to the pickup spots first (shortest walk with the food)
	var pick := pickup_slot(0) - position
	seats.sort_custom(func(a, c): return (a["approach"] as Vector3).distance_to(pick) + (a["pos"] as Vector3).distance_to(a["approach"]) \
		< (c["approach"] as Vector3).distance_to(pick) + (c["pos"] as Vector3).distance_to(c["approach"]))
	for k in range(seats.size()):
		seats[k]["idx"] = k
	b.flush(n)

# ---------------------------------------------------------------- stations (kiosk)

func _st_counter(n: Node3D, t: int) -> void:
	var b := MeshBatch.new()
	var y := COUNTER_Y + 0.04
	var z := K_FRONT + 0.03
	var tx := K_X + 0.5
	b.add_box(Vector3(0.14, 0.07, 0.1), PlotBuilders.DARK, _at(Vector3(tx, y + 0.035, z)))
	var screen := ModelLib.box(n, Vector3(0.1, 0.06, 0.006), Vector3(tx, y + 0.1, z + 0.02), Color(0.3, 0.9, 0.85), 1.5)
	screen.rotation.x = deg_to_rad(-20)
	if t >= 2:
		b.add_box(Vector3(0.05, 0.03, 0.07), Color(0.25, 0.25, 0.28), _at(Vector3(tx + 0.13, y + 0.015, z + 0.02)))
		b.add_box(Vector3(0.03, 0.004, 0.02), Color(0.3, 0.9, 0.4), _at(Vector3(tx + 0.13, y + 0.032, z + 0.0)), 1.5)
	if t >= 3:
		# longer counter: a side wing beside the kiosk where orders are handed out
		var wx := K_X + K_W / 2.0 + 0.26
		b.add_box(Vector3(0.5, COUNTER_Y, 0.26), PlotBuilders.WOOD.darkened(0.15), _at(Vector3(wx, COUNTER_Y / 2.0, 0.1)))
		b.add_box(Vector3(0.54, 0.04, 0.3), PlotBuilders.WOOD, _at(Vector3(wx, COUNTER_Y + 0.02, 0.1)))
		b.add_box(Vector3(0.5, 0.05, 0.005), TRIM, _at(Vector3(wx, COUNTER_Y - 0.06, 0.235)))
		PlotBuilders.spawn("cup", n, Vector3(wx - 0.12, COUNTER_Y + 0.04, 0.1), 0, 0.15, false)
		PlotBuilders.spawn("styrofoam", n, Vector3(wx + 0.12, COUNTER_Y + 0.04, 0.08), 0, 0.1, false)
	if t >= 4:
		var gx := K_X + 0.12
		var glass := ModelLib.box(n, Vector3(0.34, 0.13, 0.12), Vector3(gx, y + 0.065, z), Color(0.75, 0.9, 1.0))
		glass.material_override = _glass_mat()
		b.add_box(Vector3(0.36, 0.015, 0.14), PlotBuilders.GOLD, _at(Vector3(gx, y + 0.135, z)))
		PlotBuilders.spawn("pita", n, Vector3(gx - 0.07, y, z), 0, 0.22, false)
		PlotBuilders.spawn("pita", n, Vector3(gx + 0.08, y, z), 40, 0.22, false)
	b.flush(n)

static var _glass: StandardMaterial3D

static func _glass_mat() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.75, 0.9, 1.0, 0.35)
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.roughness = 0.1
	return _glass

func _st_grill(n: Node3D, t: int) -> void:
	var b := MeshBatch.new()
	var count := clampi(t, 1, 3)
	var x0 := K_X - K_W / 2.0 + 0.13
	PlotBuilders.grill(n, Vector3(x0, COUNTER_Y, LINE_Z), count, b)
	# smoke leaves through the chimney
	_smoke(n, Vector3(K_X - K_W / 2.0 + 0.3, K_H + 0.4, CHIMNEY_Z), Vector3(0.03, 0.01, 0.03), 10 + 6 * count)
	PlotBuilders.spawn("charcoal", n, Vector3(x0 - 0.02, 0, -0.5), 0, 0.5, false)
	if t >= 4:
		# brick oven with a tajine outside the kiosk's right wall
		var ox := K_X + K_W / 2.0 + 0.34
		b.add_box(Vector3(0.4, 0.34, 0.32), Color(0.68, 0.36, 0.25), _at(Vector3(ox, 0.17, -0.3)))
		b.add_cyl(0.16, 0.12, Color(0.62, 0.32, 0.22), _at(Vector3(ox, 0.4, -0.3)))
		b.add_box(Vector3(0.16, 0.12, 0.01), PlotBuilders.COAL, _at(Vector3(ox, 0.14, -0.135)), 1.8)
		PlotBuilders.spawn("tajine", n, Vector3(ox, 0.46, -0.3), 0, 0.18, false)
	b.flush(n)

func _st_doner(n: Node3D, t: int) -> void:
	var count := 2 if t >= 3 else 1
	for i in range(count):
		var x := K_X - 0.2 + i * 0.2
		var spit := Node3D.new()
		spit.position = Vector3(x, COUNTER_Y, LINE_Z)
		n.add_child(spit)
		PlotBuilders.spawn("doner", spit, Vector3.ZERO, 0, 0.36)
		_spits.append(spit)
		ModelLib.box(n, Vector3(0.12, 0.3, 0.02), Vector3(x, COUNTER_Y + 0.18, LINE_Z - 0.1), Color(1.0, 0.45, 0.1), 1.8)

func _st_fryer(n: Node3D, t: int) -> void:
	var x := K_X + 0.23
	ModelLib.box(n, Vector3(0.18, 0.08, 0.16), Vector3(x, COUNTER_Y + 0.04, LINE_Z), STEEL)
	ModelLib.box(n, Vector3(0.14, 0.01, 0.12), Vector3(x, COUNTER_Y + 0.085, LINE_Z), Color(0.85, 0.65, 0.2))
	PlotBuilders.spawn("fries", n, Vector3(x + 0.05, COUNTER_Y + 0.08, LINE_Z + 0.05), 0, 0.22, false)
	if t >= 3:
		# a shelf of take-away boxes above the fryer
		ModelLib.box(n, Vector3(0.26, 0.02, 0.1), Vector3(x, COUNTER_Y + 0.26, LINE_Z - 0.06), PlotBuilders.WOOD)
		PlotBuilders.spawn("styrofoam", n, Vector3(x + 0.02, COUNTER_Y + 0.27, LINE_Z - 0.06), 0, 0.12, false)

func _st_karak(n: Node3D, t: int) -> void:
	var xs := [K_X + 0.47]
	if t >= 2:
		xs.append(K_X + 0.67)
	for x in xs:
		PlotBuilders.spawn("samovar", n, Vector3(x, COUNTER_Y, LINE_Z), 0, 1.3)
	for i in range(3):
		PlotBuilders.spawn("cup_tea", n, Vector3(K_X - 0.33 + i * 0.07, COUNTER_Y + 0.04, K_FRONT + 0.06), 0, 0.22, false)
	if t >= 3:
		# tea counter: a stew pot of karak and more glasses on the line
		PlotBuilders.spawn("pot_stew", n, Vector3(K_X + 0.83, COUNTER_Y, LINE_Z), 0, 0.17, false)
		ModelLib.box(n, Vector3(0.24, 0.02, 0.1), Vector3(K_X + 0.57, COUNTER_Y + 0.26, LINE_Z - 0.06), PlotBuilders.WOOD)
		for i in range(3):
			PlotBuilders.spawn("cup_tea", n, Vector3(K_X + 0.5 + i * 0.07, COUNTER_Y + 0.27, LINE_Z - 0.06), 0, 0.2, false)

func _st_sweets(n: Node3D, t: int) -> void:
	var p := Vector3(K_X - 0.55, COUNTER_Y + 0.04, K_FRONT + 0.03)
	PlotBuilders.spawn("sweets", n, p, 0, 0.75)
	if t >= 2:
		PlotBuilders.spawn("cake", n, p + Vector3(-0.05, 0.165, 0), 0, 0.16, false)
		PlotBuilders.spawn("plate", n, p + Vector3(0.07, 0.165, 0), 0, 0.12, false)

func _st_coldbox(n: Node3D, count: int) -> void:
	var b := MeshBatch.new()
	for i in range(count):
		var x := K_X + K_W / 2.0 + 0.2 + i * 0.3
		b.add_box(Vector3(0.26, 0.46, 0.24), Color(0.92, 0.94, 0.96), _at(Vector3(x, 0.23, -0.78)))
		b.add_box(Vector3(0.2, 0.3, 0.005), Color(0.6, 0.8, 0.95), _at(Vector3(x, 0.27, -0.657)))
		b.add_box(Vector3(0.02, 0.12, 0.02), PlotBuilders.DARK, _at(Vector3(x + 0.09, 0.3, -0.65)))
	b.flush(n)

func _st_signage(n: Node3D, t: int) -> void:
	var b := MeshBatch.new()
	var y := K_H + 0.2
	var z := K_FRONT + 0.06
	# painted: gold frame and a menu panel beside the window
	b.add_box(Vector3(1.56, 0.03, 0.06), PlotBuilders.GOLD, _at(Vector3(K_X, y - 0.155, z)))
	for sx in [-0.77, 0.77]:
		b.add_box(Vector3(0.03, 0.3, 0.06), PlotBuilders.GOLD, _at(Vector3(K_X + sx, y, z)))
	var mx := K_X - K_W / 2.0 + 0.1
	b.add_box(Vector3(0.14, 0.32, 0.01), Color(0.2, 0.25, 0.22), _at(Vector3(mx, 0.66, K_FRONT + 0.006)))
	for i in range(4):
		b.add_box(Vector3(0.09, 0.012, 0.004), PlotBuilders.CREAM, _at(Vector3(mx, 0.75 - i * 0.05, K_FRONT + 0.013)))
	if t >= 2:
		# lit: a warm strip under the board, on at night
		var strip := ModelLib.box(n, Vector3(1.5, 0.02, 0.02), Vector3(K_X, y - 0.18, z + 0.04), Color(1.0, 0.9, 0.6), 3.0)
		_night_only.append(strip)
		for sx in [-0.5, 0.5]:
			b.add_box(Vector3(0.04, 0.04, 0.12), PlotBuilders.DARK, _at(Vector3(K_X + sx, y + 0.17, z + 0.06)))
	if t >= 3:
		# neon tube frame mounted on the board, pink name inside it
		var ny := y - 0.15
		PlotBuilders.spawn("neon_frame", n, Vector3(K_X, ny, z + 0.04), 0, 1.2, false)
		var neon := _label(n, Vector3(K_X, y + 0.0, z + 0.07), "ui.sign", 80, 0.0034, Color(1.0, 0.25, 0.6))
		neon.outline_modulate = Color(1.0, 0.7, 0.9)
		neon.outline_size = 6
		_neon.append(neon)
		_light(n, Vector3(K_X, ny + 0.1, K_FRONT + 0.6), Color(1.0, 0.45, 0.7), 0.8, 2.0)
	if t >= 4:
		var py := PlotBuilders.spawn("pylon", n, Vector3(-_gap - 0.25, 0, 0.62), 0, 0.95)
		if py:
			_label(py, Vector3(0, 0.92, 0.1), "ui.sign", 56, 0.0026, Color(0.45, 0.1, 0.1))
	b.flush(n)

func _st_lights(n: Node3D, t: int) -> void:
	var b := MeshBatch.new()
	var left := -_gap + 0.03
	var right := -0.27
	var back := K_BACK + 0.05
	var front := RAIL_Z
	var top := 1.05
	var lx := []
	# tier 1: two lantern posts at the back corners of the terrace
	for x in [left + 0.02, right]:
		PlotBuilders.post(b, Vector3(x, 0, back), top, PlotBuilders.DARK, 0.035)
		var inward := 1.0 if x < -1.0 else -1.0
		b.add_box(Vector3(0.14, 0.02, 0.02), PlotBuilders.DARK, _at(Vector3(x + inward * 0.06, top - 0.02, back)))
		lx.append(PlotBuilders.lantern_at(Vector3(x + inward * 0.11, top - 0.27, back), 1.1))
	_light(n, Vector3((left + right) / 2.0, top - 0.1, back + 0.4), Color(1.0, 0.78, 0.45), 1.3, 2.4)
	if t >= 2:
		# string lights across the terrace on two more posts at the front
		for x in [left, right]:
			PlotBuilders.post(b, Vector3(x, 0, front), top, PlotBuilders.DARK, 0.03)
		_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(left, top, back), Vector3(right, top, back), 12, 0.06))
		_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(left, top, front), Vector3(right, top, front), 12, 0.08))
		_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(left, top, back), Vector3(right, top, front), 14, 0.1))
		_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(right, top, back), Vector3(left, top, front), 14, 0.1))
		_light(n, Vector3((left + right) / 2.0, top - 0.15, (back + front) / 2.0), Color(1.0, 0.82, 0.5), 1.1, 2.4)
	if t >= 3:
		# six lanterns hanging from the strands
		for i in range(6):
			var u := (i % 3 + 0.5) / 3.0
			var z := lerpf(back, front, 0.3 if i < 3 else 0.75)
			lx.append(PlotBuilders.lantern_at(Vector3(lerpf(left, right, u), top - 0.22, z), 0.7))
		_light(n, Vector3(K_X, 1.0, K_FRONT + 0.45), Color(1.0, 0.8, 0.5), 1.0, 2.0)
	if t >= 4:
		# lantern canopy: a timber lattice over the terrace with more lanterns
		var w := right - left
		var dz := front - back
		for i in range(5):
			b.add_box(Vector3(w, 0.03, 0.03), PlotBuilders.WOOD, _at(Vector3((left + right) / 2.0, top + 0.03, back + dz * i / 4.0)))
		for x in [left, (left + right) / 2.0, right]:
			b.add_box(Vector3(0.03, 0.03, dz), PlotBuilders.WOOD, _at(Vector3(x, top + 0.06, (back + front) / 2.0)))
		for i in range(4):
			lx.append(PlotBuilders.lantern_at(Vector3(lerpf(left, right, (i + 0.5) / 4.0), top - 0.16, (back + front) / 2.0), 0.7))
	var mmi := PlotBuilders.lantern_batch(n, lx)
	if mmi:
		_lanterns.append(mmi)
	b.flush(n)

func _st_music(n: Node3D, t: int) -> void:
	var b := MeshBatch.new()
	var p := _music_spot
	var base := 0.0
	if t >= 4:
		base = 0.06
		b.add_box(Vector3(0.62, 0.06, 0.4), PlotBuilders.WOOD.darkened(0.1), _at(p + Vector3(0, 0.03, 0)))
		b.add_box(Vector3(0.64, 0.015, 0.42), TRIM, _at(p + Vector3(0, 0.0675, 0)))
	var spk := [p + Vector3(0.22, base, -0.06)] if t < 2 else [p + Vector3(-0.24, base, -0.08), p + Vector3(0.24, base, -0.08)]
	for s in spk:
		var h := 0.0 if t < 2 else 0.32
		if h > 0.0:
			PlotBuilders.post(b, s, h, PlotBuilders.DARK, 0.025)
		b.add_box(Vector3(0.12, 0.18, 0.11), PlotBuilders.DARK, _at(s + Vector3(0, h + 0.09, 0)))
		b.add_cyl(0.035, 0.012, Color(0.4, 0.4, 0.42), _rx(s + Vector3(0, h + 0.1, 0.06), PI / 2))
	if t >= 3:
		# an oud player on a stool
		b.add_cyl(0.06, 0.13, PlotBuilders.WOOD, _at(p + Vector3(0, base + 0.065, 0.02)))
		var player := ModelLib.spawn(PlotBuilders.PROPS["oud"], n, p + Vector3(0, base + 0.08, 0.02), 0, 0.62)
		if player:
			ModelLib.play_loop(player, "holding-both", 0.6)
			b.add_box(Vector3(0.08, 0.12, 0.03), Color(0.55, 0.32, 0.15), _at(p + Vector3(0.0, base + 0.25, 0.14)))
	b.flush(n)

func _st_shade(n: Node3D, t: int) -> void:
	var b := MeshBatch.new()
	# tier 1: one more parasol over the back row
	for s in _slots:
		if int(s["row"]) == 2 and int(s["col"]) == 1:
			PlotBuilders.spawn("parasol_b", n, Vector3(s["x"], 0, s["z"]), 15, 1.35)
	if t >= 2:
		# shade sail over the back of the terrace on two tall posts
		var left := -_gap + 0.08
		var right := -0.3
		for x in [left, right]:
			PlotBuilders.post(b, Vector3(x, 0, K_BACK + 0.08), 1.35, Color(0.85, 0.85, 0.82), 0.035)
		var sail := ModelLib.box(n, Vector3(right - left, 0.012, 0.95), Vector3((left + right) / 2.0, 1.22, -0.48), Color(0.97, 0.95, 0.9))
		sail.rotation.x = deg_to_rad(-14)
		sail.material_override = _sail_mat()
		sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if t >= 3:
		var fan := PlotBuilders.spawn("fan", n, Vector3(-0.28, 0, -0.62), -60, 0.9)
		if fan:
			var head := fan.find_child("head", true, false) as Node3D
			if head:
				_fans.append(head)
			if t >= 4:
				PlotBuilders.mist(n, Vector3(-0.32, 0.48, -0.58), Vector3(-1, -0.15, 0.4))
	b.flush(n)

static var _sail: StandardMaterial3D

static func _sail_mat() -> StandardMaterial3D:
	if _sail == null:
		_sail = StandardMaterial3D.new()
		_sail.albedo_color = Color(0.97, 0.95, 0.9, 0.82)
		_sail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sail.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _sail

# ---------------------------------------------------------------- stages 1-2 lights

func _rig_lights(n: Node3D, t: int) -> void:
	n.position = STAND_POS
	var b := MeshBatch.new()
	var top := 1.3
	var xs := [-0.92, 0.92]
	var pz := 0.2
	var lx := []
	for x in xs:
		PlotBuilders.post(b, Vector3(x, 0, pz), top, PlotBuilders.DARK, 0.03)
		lx.append(PlotBuilders.lantern_at(Vector3(x, top - 0.02, pz), 1.1))
	_light(n, Vector3(0, 1.0, 0.5), Color(1.0, 0.78, 0.45), 1.2, 2.2)
	if t >= 2:
		_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(xs[0], top, pz), Vector3(xs[1], top, pz), 14, 0.07))
		_light(n, Vector3(0, 1.1, 0.0), Color(1.0, 0.82, 0.5), 0.9, 2.0)
	if t >= 3:
		for i in range(4):
			lx.append(PlotBuilders.lantern_at(Vector3(lerpf(xs[0], xs[1], (i + 0.5) / 4.0), top - 0.3, pz), 0.9))
	if t >= 4:
		_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(xs[0], top - 0.05, pz), Vector3(xs[0] - 0.35, 0.02, pz - 0.3), 8, 0.05))
		_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(xs[1], top - 0.05, pz), Vector3(xs[1] + 0.35, 0.02, pz - 0.3), 8, 0.05))
	var mmi := PlotBuilders.lantern_batch(n, lx)
	if mmi:
		_lanterns.append(mmi)
	b.flush(n)

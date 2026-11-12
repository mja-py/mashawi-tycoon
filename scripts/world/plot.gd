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
const GAP := [1.05, 1.65, 1.8, 3.65, 3.95, 4.95]
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
const CHAIR_X := 0.218
const TABLE_PITCH := 1.05
const FIRST_TABLE_X := -1.03
const ROWS := [0.28, -0.63]
const AISLE_Z := -0.17
const FRONT_AISLE_Z := 0.74
const ENTRY_X := -0.35
const DECK_Y := 0.018

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
## {idx, table, pos, facing, route (plot space), y_off, who}
var seats: Array = []
## {pos, node (plate holder), dirty, left}
var tables: Array = []
var _slots: Array = []
var _music_spot := Vector3.ZERO
var _helper: Node3D
var _board: Label3D
var _applied := false
var _stall_board: Label3D
var _truck_board: Label3D
var _extractor: Node3D
var dining_staff: Array[DiningStaff] = []
var staff_collect: Callable
var service_open := false
var clean_seconds := 1.4
var service_stats := {"deliveries": 0, "cleaned": 0}

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
	var site: Dictionary = state.get("site", {})
	var wanted := _wanted(stations, Paving.DESIGNS.has(site.get("layout", "")))
	for k in _built.keys():
		if not wanted.has(k):
			_free_key(k)
	_prune()
	cart.visible = stage < FIXED
	cart.process_mode = Node.PROCESS_MODE_INHERIT if stage < FIXED else Node.PROCESS_MODE_DISABLED
	cart.set_truck(stage == 2)
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
	if _alive(_truck_board):
		_truck_board.visible = not neon
	cart.set_neon(neon and stage < FIXED)
	if _alive(_helper):
		# a second pair of hands once the grill or the counter is busy enough
		_helper.visible = int(stations.get("grill", 0)) >= 4 or int(stations.get("counter", 0)) >= 4
	_configure_dining_staff(stations)
	if any:
		_night_set = false
		set_night(_night)
	_applied = true

## A freshly bought piece rises out of the ground (build feedback after a purchase).
func _grow(n: Node3D) -> void:
	var full_height := n.scale.y
	n.scale.y = full_height * 0.05
	var tw := n.create_tween()
	tw.tween_property(n, "scale:y", full_height, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _tier(stations: Dictionary, id: String) -> int:
	return Data.station_tier(int(stations.get(id, 0))) if stations.has(id) else -1

## key -> [builder method, args...]
func _wanted(stations: Dictionary, paved: bool) -> Dictionary:
	var w := {}
	var s := str(stage)
	w["stage:" + s] = ["_build_stage", paved]
	if stage < FIXED:
		var lt := _tier(stations, "lights")
		if lt > 0:
			w["station:lights:%d:%s" % [lt, s]] = ["_rig_lights", lt]
		if stage >= 1:
			for id in ["doner", "fryer", "sweets"]:
				var t := _tier(stations, id)
				if t > 0:
					w["rig:%s:%d:%s" % [id, t, s]] = ["_build_mobile_equipment", id, t]
		var tea := _tier(stations, "karak")
		if tea > 0:
			w["rig:karak:%d:%s" % [tea, s]] = ["_build_mobile_equipment", "karak", tea]
		if stage == 2:
			for id in ["counter", "grill", "shade", "music", "coldbox"]:
				var t := _tier(stations, id)
				if t > 0 or id == "grill":
					w["rig:%s:%d:%s" % [id, t, s]] = ["_build_mobile_equipment", id, t]
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
	var dining := int(stations.get("seating", 0)) * int(Data.STATIONS["seating"]["seats_per_level"])
	var majlis := int(stations.get("majlis", 0)) * int(Data.STATIONS["majlis"]["seats_per_level"])
	var n_seats := mini(dining + majlis, int(SEAT_CAP[stage]))
	var n_tables := mini(n_seats / 2, _slots.size())
	if n_tables > 0:
		var lounge := mini(n_tables, majlis / 2)
		if dining > 0 and majlis > 0 and n_tables > 1:
			lounge = clampi(roundi(float(n_tables * majlis) / float(dining + majlis)), 1, n_tables - 1)
		w["seating:%d:%d:%s" % [n_tables, lounge, s]] = ["_build_seating", n_tables, lounge]
	return w

func _free_key(k: String) -> void:
	var n: Node = _built.get(k)
	_built.erase(k)
	if n and is_instance_valid(n):
		remove_child(n)
		n.queue_free()
	if k.begins_with("seating:"):
		for worker in dining_staff:
			remove_child(worker)
			worker.queue_free()
		dining_staff.clear()
		seats.clear()
		tables.clear()

static func _alive(n) -> bool:
	return n != null and is_instance_valid(n) and (n as Node).is_inside_tree() and not (n as Node).is_queued_for_deletion()

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
	if stage < 2:
		return World.CART_POS + Vector3(0.05 + 0.5 * i, 0, 0.42 + 0.02 * i)
	var front := World.CART_POS + FoodTruck.ORDER * FoodTruck.SCALE if stage == 2 else position + Vector3(K_X + 0.41, 0, 0.58)
	# Compress the tail into the street bounds at high counter levels.
	var rank := float(i)
	front.x += rank * 0.43 / (1.0 + 0.073 * rank)
	return front

func pickup_slot(i: int) -> Vector3:
	if stage >= 2:
		var first := World.CART_POS + FoodTruck.PICKUP * FoodTruck.SCALE if stage == 2 else position + Vector3(K_X - 0.40, 0, 0.58)
		var offset := float(i)
		return first + Vector3(-offset * 0.35 / (1.0 + 0.075 * offset), 0, minf(offset * 0.052, 0.22))
	var actor := server()
	var base := actor.global_position if actor else World.CART_POS
	base.y = 0.0
	return base + Vector3(-0.14 - 0.34 * i, 0.0, (0.40 if stage < FIXED else 0.69) + 0.07 * i)

func service_front(pickup: bool) -> Vector3:
	if stage < 2:
		return World.CART_POS
	var slot := pickup_slot(0) if pickup else queue_slot(0)
	return slot + Vector3(0, 0, -0.34)

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
		if _holds(s["who"]) or bool(s.get("needs_clean", false)):
			continue
		if bool(tables[int(s["table"])]["dirty"]):
			continue
		var route: Array[Vector3] = []
		for point in s["route"]:
			route.append(position + point)
		return {"idx": s["idx"], "table": s["table"], "pos": position + (s["pos"] as Vector3),
			"facing": s["facing"], "route": route, "y_off": s["y_off"]}
	return {}

func take_seat(idx: int, who) -> void:
	if idx >= 0 and idx < seats.size():
		seats[idx]["who"] = who

func release_seat(idx: int, who: Customer) -> void:
	if idx < 0 or idx >= seats.size() or seats[idx]["who"] != who:
		return
	var table := int(seats[idx]["table"])
	seats[idx]["who"] = null
	seats[idx]["needs_clean"] = bool(tables[table]["meals"][idx % 2].visible)
	for s in seats:
		if int(s["table"]) == table and _holds(s["who"]):
			return
	if seats[idx]["needs_clean"] or tables[table]["node"].visible:
		set_table_dirty(table, true)

func show_meal(table: int, item: String = "", seat_index: int = -1) -> Node3D:
	if table >= 0 and table < tables.size() and _alive(tables[table]["node"]):
		tables[table]["node"].show()
		var meal: Node3D = tables[table]["meals"][maxi(seat_index, 0) % 2]
		meal.show()
		if not item.is_empty():
			return ModelLib.served_food(meal, item, 0.095)
	return null

func set_table_dirty(table: int, dirty: bool) -> void:
	if table < 0 or table >= tables.size():
		return
	var t: Dictionary = tables[table]
	t["dirty"] = dirty
	t["assigned"] = false
	if _alive(t["node"]):
		(t["node"] as Node3D).visible = dirty
	if not dirty:
		for s in seats:
			if int(s["table"]) == table:
				s["needs_clean"] = false
		for meal in t["meals"]:
			meal.hide()
			for food in meal.get_children():
				if food.name.begins_with("Served_"):
					meal.remove_child(food)
					food.queue_free()

func dirty_tables() -> Array:
	var out := []
	for i in range(tables.size()):
		if tables[i]["dirty"]:
			out.append(i)
	return out

func unclaimed_dirty_table() -> int:
	for i in range(tables.size()):
		if tables[i]["dirty"] and not tables[i]["assigned"]:
			return i
	return -1

func _configure_dining_staff(stations: Dictionary) -> void:
	var count := 0
	if stage >= FIXED and not tables.is_empty():
		count = mini(3, 1 + (1 if stage >= 4 and seats.size() >= 4 else 0) + (1 if int(stations.get("staffroom", 0)) > 0 else 0))
	clean_seconds = maxf(0.9, 1.6 - 0.12 * int(stations.get("washroom", 0)))
	while dining_staff.size() > count:
		var worker: DiningStaff = dining_staff.pop_back()
		remove_child(worker)
		worker.queue_free()
	while dining_staff.size() < count:
		var worker := DiningStaff.new()
		add_child(worker)
		worker.setup(self, dining_staff.size())
		dining_staff.append(worker)

func staff_home(index: int) -> Vector3:
	return Vector3(ENTRY_X + 0.26 * index, DECK_Y, FRONT_AISLE_Z + 0.14)

func staff_pickup() -> Vector3:
	return Vector3(K_X - 0.4, DECK_Y, 0.62)

func staff_table_route(table: int) -> Array[Vector3]:
	var point: Vector3 = tables[table]["pos"]
	var aisle := AISLE_Z if point.z < AISLE_Z else FRONT_AISLE_Z
	return [Vector3(ENTRY_X, DECK_Y, FRONT_AISLE_Z), Vector3(ENTRY_X, DECK_Y, aisle),
		Vector3(point.x, DECK_Y, aisle), Vector3(point.x, DECK_Y, point.z + 0.31)]

func can_deliver() -> bool:
	for worker in dining_staff:
		if worker.available():
			return true
	return false

func deliver_meal(customer: Customer, item: String, done: Callable) -> bool:
	for worker in dining_staff:
		if worker.available():
			worker.deliver(customer, item, done)
			return true
	return false

func staff_busy() -> bool:
	for worker in dining_staff:
		if worker.state != DiningStaff.State.IDLE:
			return true
	return false

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
	if _alive(_extractor):
		_extractor.rotate_y(delta * 4.5)
	for s in _spits:
		if is_instance_valid(s):
			(s as Node3D).rotate_y(delta * 0.65)
	for f in _fans:
		if is_instance_valid(f):
			(f as Node3D).rotation.y = sin(_t * 0.8) * 0.7

# ---------------------------------------------------------------- helpers

static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)

static func _rx(p: Vector3, a: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, a), p)

func _crew_member(parent: Node3D, female: bool, pos: Vector3, rot: float = 0.0) -> Node3D:
	var n := ModelLib.spawn_crew(female, parent, pos, rot, 0.55)
	if n:
		ModelLib.play_loop(n, "idle")
		_crew.append(n)
	return n

func _label(parent: Node3D, pos: Vector3, key: String, size: int, px: float, col: Color) -> Label3D:
	var l := PlotBuilders.sign(parent, pos, size, px, key, col)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l

# ---------------------------------------------------------------- stages

func _build_stage(n: Node3D, paved: bool) -> void:
	match stage:
		0: _build_cart_court(n, paved)
		1: _build_stall(n)
		2: _build_truck(n)
		_: _build_kiosk(n)

## A little souk courtyard gives the first cart its own silhouette and a clear queue.
## All decoration is batched; the pavement stays level with the pedestrian path.
func _build_cart_court(n: Node3D, paved: bool) -> void:
	var b := MeshBatch.new()
	if not paved:
		b.add_box(Vector3(2.02, 0.025, 1.35), Color("c5ae94"), _at(Vector3(0, 0.004, 0.05)))
	for sx in [-0.91, 0.91]:
		b.add_box(Vector3(0.24, 0.25, 0.27), Color("b56849"), _at(Vector3(sx, 0.13, -0.34)))
		b.add_box(Vector3(0.27, 0.035, 0.3), PlotBuilders.CREAM, _at(Vector3(sx, 0.26, -0.34)))
		for i in range(3):
			b.add_cyl(0.075, 0.14 if i == 1 else 0.1, Color("3e8271") if i == 1 else Color("65935d"), _at(Vector3(sx - 0.065 + i * 0.065, 0.32, -0.34)), 0.0, 6)
		PlotBuilders.post(b, Vector3(sx, 0, -0.55), 1.34, PlotBuilders.WOOD, 0.025)
	_bulbs.append(PlotBuilders.string_lights(n, b, Vector3(-0.91, 1.34, -0.55), Vector3(0.91, 1.34, -0.55), 9, 0.16))
	_light(n, Vector3(0, 0.85, 0.58), Color("ffce91"), 0.95, 1.55)
	# Small pavement inlay leads the eye to the serving counter, clear of the walking lane.
	for sx in [-0.18, 0.18]:
		b.add_box(Vector3(0.047, 0.008, 0.12), Color("987c57"), _at(Vector3(sx, 0.024, 0.62)))
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
	_light(n, Vector3(0, 0.90, 0.52), Color("ffd39d"), 0.90, 1.60)
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

## Stage 2: the open service hatch has a real counter and fitted kitchen.
func _build_truck(n: Node3D) -> void:
	n.position = STAND_POS
	n.scale = Vector3.ONE * FoodTruck.SCALE
	_truck_board = FoodTruck.build(n)
	_extractor = n.get_node("ExtractorRotor") as Node3D
	_bulbs.append(ModelLib.box(n, Vector3(0.74, 0.016, 0.018), Vector3(0.22, 0.98, 0.08), Color("c9ae82")))
	_light(n, Vector3(0.22, 0.84, 0.29), Color("ffdfb2"), 0.55, 1.35)
	var b := MeshBatch.new()
	b.add_box(Vector3(0.12, 0.072, 0.10), PlotBuilders.DARK, _at(Vector3(-0.45, FoodTruck.SILL_Y + 0.036, 0.30)))
	b.add_box(Vector3(0.09, 0.035, 0.006), Color("73aa8d"), _at(Vector3(-0.45, FoodTruck.SILL_Y + 0.06, 0.352)))
	b.flush(n)
	_smoke(n, FoodTruck.EXTRACTOR + Vector3.UP * 0.082, Vector3(0.023, 0.008, 0.023), 8)
	_service_markers(n, FoodTruck.PICKUP.x, FoodTruck.ORDER.x, FoodTruck.HATCH_Z + 0.024, 0.31)
	for x in [FoodTruck.PICKUP.x, FoodTruck.ORDER.x]:
		ModelLib.box(n, Vector3(0.18, 0.006, 0.025), Vector3(x, 0.015, 0.68), PlotBuilders.GOLD)

func _build_mobile_equipment(n: Node3D, station: String, t: int) -> void:
	n.position = STAND_POS
	if stage == 2:
		n.scale = Vector3.ONE * FoodTruck.SCALE
	match station:
		"fryer":
			var p := FoodTruck.FRYER
			if stage == 1:
				p = Vector3(1.18, 0.315, 0.11)
			PlotBuilders.fryer(n, p, t)
		"sweets":
			PlotBuilders.dessert_case(n, FoodTruck.SWEETS, t)
		"doner":
			var p := Vector3(-0.10, 0.423, -0.048) if stage == 2 else Vector3(-0.90, 0.33, -0.34)
			var bottom := 0.24 if stage == 2 else 0.0
			ModelLib.box(n, Vector3(0.296, p.y - bottom, 0.27), Vector3(p.x, (p.y + bottom) * 0.5, p.z - 0.015), FoodTruck.DARK_TEAL)
			var rotor := PlotBuilders.shawarma(n, p)
			if rotor:
				_spits.append(rotor)
		"karak":
			var p := FoodTruck.TEA if stage == 2 else Vector3(1.30, 0.33, -0.03)
			if stage == 0:
				p = Vector3(0.68, 0.34, -0.15)
				ModelLib.box(n, Vector3(0.23, 0.32, 0.22), p - Vector3.UP * 0.18, PlotBuilders.WOOD)
				ModelLib.box(n, Vector3(0.26, 0.023, 0.24), p - Vector3.UP * 0.012, PlotBuilders.GOLD)
			PlotBuilders.spawn("samovar", n, p, 0, 0.85 if stage == 0 else 1.10)
			PlotBuilders.spawn("cup_tea", n, p + Vector3(-0.09, 0, 0.05), 0, 0.20, false)
		"coldbox":
			if stage == 2:
				var p := Vector3(1.08, 0.24, -0.30)
				var height := 0.29 + 0.035 * t
				ModelLib.box(n, Vector3(0.29, height, 0.25), p + Vector3.UP * (height * 0.5), STEEL)
				ModelLib.box(n, Vector3(0.25, 0.022, 0.018), p + Vector3(0, height - 0.066, 0.134), PlotBuilders.DARK)
		"counter":
			if t >= 2:
				ModelLib.box(n, Vector3(0.052, 0.028, 0.071), Vector3(-0.53, FoodTruck.SILL_Y + 0.014, 0.36), PlotBuilders.STEEL)
		"grill":
			var b := MeshBatch.new()
			PlotBuilders.grill(n, FoodTruck.GRILL - Vector3(0.08, 0, 0), 2 if t >= 2 else 1, b)
			if t >= 3:
				b.add_box(Vector3(0.065, 0.008, 0.082), STEEL, _at(Vector3(0.046, FoodTruck.SILL_Y + 0.004, 0.28)))
			b.flush(n)
		"shade":
			# Retractable side awning attaches to the cargo wall, clear of the hatch and name.
			var depth := 0.12 + 0.035 * t
			var hinge := Node3D.new()
			hinge.position = Vector3(1.305, 1.055, -0.035)
			hinge.rotation.y = PI / 2.0
			n.add_child(hinge)
			var canopy := ModelLib.box(hinge, Vector3(0.72, 0.019, depth), Vector3(0, -0.018, depth * 0.5), Color("bbab86"))
			canopy.rotation.x = 0.12
			PlotBuilders.stripes(canopy, 0.72, depth, FoodTruck.ENAMEL, 0.021)
			ModelLib.box(hinge, Vector3(0.75, 0.043, 0.033), Vector3.ZERO, FoodTruck.DARK_TEAL)
			for x in [-0.29, 0.29]:
				var from := Vector3(x, -0.11, 0)
				var to := Vector3(x, -0.038, depth * 0.9)
				var arm := ModelLib.box(hinge, Vector3(0.014, 0.014, from.distance_to(to)), (from + to) * 0.5, FoodTruck.STEEL)
				arm.basis = Basis.looking_at(to - from, Vector3.UP)
		"music":
			var b := MeshBatch.new()
			var brass := Color("c79a43")
			var timber := Color("503520")
			var date_brown := Color("442719")
			var cream := Color("efe0bb")
			# Counter-height hospitality ledge on the customer-right exterior, outside the food line.
			var shelf_x := 1.280 if stage == 2 else 0.840
			var shelf_y := FoodTruck.SILL_Y if stage == 2 else 0.425
			var shelf_z := 0.540 if stage == 2 else 0.430
			var shelf_center := Vector3(shelf_x, shelf_y, shelf_z)
			var shelf_size := Vector3(0.352, 0.018, 0.208)
			var shelf_top := shelf_y + shelf_size.y * 0.5
			var bracket_size := Vector3(0.024 if stage == 2 else 0.256, 0.060, 0.220)
			var bracket_offset := Vector3(0 if stage == 2 else -0.116, -0.030, -0.070)
			b.add_box(shelf_size, timber, _at(shelf_center))
			b.add_box(bracket_size, timber, _at(shelf_center + bracket_offset))
			if stage == 1:
				# A plain backing separates the brass silhouette from the prep-table food.
				b.add_box(Vector3(0.352, 0.230, 0.014), cream, _at(Vector3(shelf_x, shelf_top + 0.115, shelf_z - 0.116)))
			var tray_center := Vector3(shelf_x - 0.088, shelf_top + 0.0064, shelf_z + 0.0192)
			var tray_radius := 0.0592
			var tray_height := 0.0128
			var date_radius := 0.016
			var date_height := 0.0176
			var date_offsets := [Vector3(-0.014, 0.009, 0), Vector3(0.010, 0.009, -0.010), Vector3(0.006, 0.015, 0.010)]
			b.add_cyl(tray_radius, tray_height, brass, _at(tray_center), 0.0, 12)
			for offset: Vector3 in date_offsets:
				b.add_cyl(date_radius, date_height, date_brown, _at(tray_center + offset * 1.6), 0.0, 8)
			# Fresh tapered meshes give the belly/lid real slopes; cached resources stay untouched.
			var taper := func(center: Vector3, lower_radius: float, upper_radius: float, height: float, color: Color, sides: int = 10) -> void:
				var shape := CylinderMesh.new()
				shape.bottom_radius = lower_radius
				shape.top_radius = upper_radius
				shape.height = height
				shape.radial_segments = sides
				shape.rings = 1
				shape.material = ModelLib.flat_material(color)
				b.add_mesh("hospitality_%d" % shape.get_instance_id(), shape, Transform3D(Basis.IDENTITY, center))
			var dallah := func(origin: Vector3, size: float) -> void:
				# Radius/height profile: foot, rounded belly, narrow waist, flared neck, pointed lid.
				var body_profile := [Vector2(0.031, 0.000), Vector2(0.043, 0.014),
					Vector2(0.052, 0.042), Vector2(0.047, 0.070), Vector2(0.025, 0.105),
					Vector2(0.023, 0.132), Vector2(0.037, 0.149), Vector2(0.039, 0.155),
					Vector2(0.008, 0.179), Vector2(0.0, 0.192)]
				for i in range(body_profile.size() - 1):
					var lower: Vector2 = body_profile[i]
					var upper: Vector2 = body_profile[i + 1]
					var center := origin + Vector3.UP * (lower.y + upper.y) * 0.5 * size
					taper.call(center, lower.x * size, upper.x * size, (upper.y - lower.y) * size, brass)
				# Broad crescent spout and an open curved handle lie in X/Y, facing the camera.
				var spout_points := [Vector3(0.037, 0.052, 0), Vector3(0.067, 0.073, 0),
					Vector3(0.081, 0.104, 0), Vector3(0.091, 0.135, 0), Vector3(0.109, 0.154, 0)]
				var spout_radii := [0.016, 0.013, 0.010, 0.006]
				var handle_points := [Vector3(-0.027, 0.135, 0), Vector3(-0.064, 0.144, 0),
					Vector3(-0.084, 0.122, 0), Vector3(-0.086, 0.087, 0),
					Vector3(-0.064, 0.058, 0), Vector3(-0.045, 0.058, 0)]
				var handle_radius := 0.007
				var stroke_sides := 8
				for stroke in [spout_points, handle_points]:
					for i in range(stroke.size() - 1):
						var start: Vector3 = origin + stroke[i] * size
						var end: Vector3 = origin + stroke[i + 1] * size
						var direction := end - start
						var radius: float = (spout_radii[i] if stroke == spout_points else handle_radius) * size
						var axis := Basis(Quaternion(Vector3.UP, direction.normalized()))
						b.add_cyl(radius, direction.length() + radius * 0.4, brass,
							Transform3D(axis, (start + end) * 0.5), 0.0, stroke_sides)
			var pot_origin := Vector3(shelf_x + 0.0512, shelf_top, shelf_z - 0.016)
			var pot_scale := 0.96
			dallah.call(pot_origin, pot_scale)
			if t >= 2:
				var cups_origin := Vector3(shelf_x + 0.0832, shelf_top, shelf_z + 0.0656)
				var cup_pitch := 0.0144
				var cup_height := 0.0256
				var cup_lower_radius := 0.0144
				var cup_upper_radius := 0.0224
				for i in range(2):
					var cup_center := cups_origin + Vector3.UP * (cup_height * 0.5 + i * cup_pitch)
					taper.call(cup_center, cup_lower_radius, cup_upper_radius, cup_height, cream)
			# Bake this local batch's palette into vertex colours: one surface / one draw call.
			# Read primitive arrays only; never alter ModelLib's cached meshes or materials.
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			var indices := PackedInt32Array()
			for key in b._order:
				var group: Dictionary = b._groups[key]
				var source: Mesh = group["mesh"]
				for surface in range(source.get_surface_count()):
					var arrays := source.surface_get_arrays(surface)
					var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					var material := group["mat"] as StandardMaterial3D
					if material == null:
						material = source.surface_get_material(surface) as StandardMaterial3D
					var color := material.albedo_color
					for transform: Transform3D in group["xforms"]:
						var offset := vertices.size()
						var normal_basis := transform.basis.inverse().transposed()
						for i in range(source_vertices.size()):
							vertices.append(transform * source_vertices[i])
							normals.append((normal_basis * source_normals[i]).normalized())
							colors.append(color)
						for index in source_indices:
							indices.append(offset + index)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_INDEX] = indices
			var corner := ArrayMesh.new()
			corner.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var palette := ModelLib.flat_material_unique(Color.WHITE)
			palette.vertex_color_use_as_albedo = true
			palette.vertex_color_is_srgb = true
			corner.surface_set_material(0, palette)
			b = MeshBatch.new()
			b.add_mesh("hospitality", corner, Transform3D.IDENTITY)
			b.flush(n)

func _service_markers(n: Node3D, pickup_x: float, order_x: float, z: float, y: float) -> void:
	PlotBuilders.sign(n, Vector3(pickup_x, y, z), 52, 0.0013, "scene.pickup", CREAM)
	PlotBuilders.sign(n, Vector3(order_x, y, z), 52, 0.0013, "scene.order", CREAM)

## Stage 3+: a fixed booth at the building line with a service window and a terrace on its -X side.
func _build_kiosk(n: Node3D) -> void:
	var b := MeshBatch.new()
	var x0 := K_X - K_W / 2.0
	var x1 := K_X + K_W / 2.0
	var d := K_FRONT - K_BACK
	var zc := (K_FRONT + K_BACK) / 2.0
	var th := 0.06
	var house := stage >= 4
	var wall_col := Color("e1c7a2") if house else CREAM
	var roof_y := (1.48 if stage >= 5 else 1.28) if house else K_H
	# Keep the kitchen shell's inner faces, sill and rectangular opening unchanged.
	b.add_box(Vector3(K_W, roof_y, th), wall_col, _at(Vector3(K_X, roof_y / 2.0, K_BACK + th / 2.0)))
	for sx in [x0 + th / 2.0, x1 - th / 2.0]:
		b.add_box(Vector3(th, roof_y, d), wall_col, _at(Vector3(sx, roof_y / 2.0, zc)))
	var fz := K_FRONT - th / 2.0
	b.add_box(Vector3(K_W, COUNTER_Y, th), wall_col, _at(Vector3(K_X, COUNTER_Y / 2.0, fz)))
	b.add_box(Vector3(K_W, roof_y - WIN_TOP, th), wall_col, _at(Vector3(K_X, (WIN_TOP + roof_y) / 2.0, fz)))
	var side_w := (K_W - WIN_W) / 2.0
	for sx in [x0 + side_w / 2.0, x1 - side_w / 2.0]:
		b.add_box(Vector3(side_w, WIN_TOP - COUNTER_Y, th), wall_col, _at(Vector3(sx, (WIN_TOP + COUNTER_Y) / 2.0, fz)))
	var base_h := 0.1
	var base_lip := 0.01
	b.add_box(Vector3(K_W + base_lip, base_h, d + base_lip), TRIM, _at(Vector3(K_X, base_h / 2.0, zc)))
	if not house:
		var frame_w := 0.025
		var frame_d := 0.02
		var frame_z := K_FRONT + 0.005
		b.add_box(Vector3(WIN_W + 0.04, frame_w, frame_d), PlotBuilders.GOLD, _at(Vector3(K_X, WIN_TOP, frame_z)))
		for sx in [K_X - WIN_W / 2.0, K_X + WIN_W / 2.0]:
			b.add_box(Vector3(frame_w, WIN_TOP - COUNTER_Y, frame_d), PlotBuilders.GOLD, _at(Vector3(sx, (WIN_TOP + COUNTER_Y) / 2.0, frame_z)))
	# Inside: original raised floor, tiled back wall and kitchen line.
	b.add_box(Vector3(K_W - 0.12, CREW_Y, d - 0.12), FLOOR, _at(Vector3(K_X, CREW_Y / 2.0, zc)))
	b.add_box(Vector3(K_W - 0.14, 0.7, 0.01), TILE, _at(Vector3(K_X, 0.35, K_BACK + th + 0.006)))
	b.add_box(Vector3(K_W - 0.14, COUNTER_Y - 0.02, 0.2), Color(0.5, 0.4, 0.32), _at(Vector3(K_X, (COUNTER_Y - 0.02) / 2.0, LINE_Z)))
	b.add_box(Vector3(K_W - 0.14, 0.02, 0.21), STEEL, _at(Vector3(K_X, COUNTER_Y - 0.01, LINE_Z)))
	b.add_box(Vector3(WIN_W + 0.1, 0.04, 0.17), PlotBuilders.WOOD, _at(Vector3(K_X, COUNTER_Y + 0.02, K_FRONT + 0.03)))
	if house:
		_heritage_roof(b, roof_y, wall_col)
	else:
		var roof_h := 0.06
		var roof_lip := 0.12
		var parapet_h := 0.08
		var parapet_w := 0.04
		var parapet_y := K_H + 0.1
		b.add_box(Vector3(K_W + roof_lip, roof_h, d + roof_lip), CREAM.darkened(0.08), _at(Vector3(K_X, K_H + roof_h / 2.0, zc + 0.03)))
		for sz in [K_BACK - 0.02, K_FRONT + 0.08]:
			b.add_box(Vector3(K_W + roof_lip, parapet_h, parapet_w), TRIM, _at(Vector3(K_X, parapet_y, sz)))
		for sx in [x0 - 0.04, x1 + 0.04]:
			b.add_box(Vector3(parapet_w, parapet_h, d + roof_lip), TRIM, _at(Vector3(sx, parapet_y, zc + 0.03)))
		_arish_shade(b)
	# Original extractor position stays aligned with the grill and its smoke.
	var chimney_r := 0.05
	var chimney_h := 0.4
	var chimney_y := K_H + 0.15
	var chimney_x := x0 + 0.3
	var cap_r := 0.07
	var cap_h := 0.03
	var cap_y := K_H + 0.36
	b.add_cyl(chimney_r, chimney_h, STEEL.darkened(0.3), _at(Vector3(chimney_x, chimney_y, CHIMNEY_Z)))
	b.add_cyl(cap_r, cap_h, STEEL.darkened(0.4), _at(Vector3(chimney_x, cap_y, CHIMNEY_Z)))
	# Sign backing and text retain the exact coordinates used by _st_signage.
	var board_size := Vector3(1.5, 0.28, 0.05)
	var board_y := K_H + 0.2
	var board_z := K_FRONT + 0.06
	var board_cap := Vector3(1.54, 0.03, 0.06)
	var board_cap_y := K_H + 0.355
	b.add_box(board_size, CREAM, _at(Vector3(K_X, board_y, board_z)))
	b.add_box(board_cap, PlotBuilders.WOOD if house else TRIM, _at(Vector3(K_X, board_cap_y, board_z)))
	_board = _label(n, Vector3(K_X, board_y, K_FRONT + 0.09), "ui.sign", 96, 0.0032, Color(0.45, 0.1, 0.1))
	_crew_member(n, true, Vector3(K_X - 0.36, CREW_Y, -0.22), 15)
	_helper = _crew_member(n, false, Vector3(K_X + 0.36, CREW_Y, -0.24), -15)
	if house:
		_dress_restaurant(n, b)
	_build_terrace(n, b)
	b.flush(n)

## A shallow arish shade; no supports or valance in the serving opening.
func _arish_shade(b: MeshBatch) -> void:
	var width := WIN_W + 0.20
	var depth := 0.22
	var center_z := K_FRONT + 0.065
	var shade_y := WIN_TOP + 0.10
	var rib_size := Vector3(0.035, 0.025, depth + 0.04)
	var rib_spacing := width / 4.0
	var frond_count := 19
	var frond_w := width / frond_count * 0.82
	var frond_h := 0.018
	for i in range(5):
		var x := K_X - width / 2.0 + i * rib_spacing
		b.add_box(rib_size, PlotBuilders.WOOD, _at(Vector3(x, shade_y, center_z)))
	for i in range(frond_count):
		var x := K_X - width / 2.0 + (i + 0.5) * width / frond_count
		b.add_box(Vector3(frond_w, frond_h, depth), DECK, _at(Vector3(x, shade_y + rib_size.y / 2.0 + frond_h / 2.0, center_z)))
	var edge_size := Vector3(width + 0.04, 0.035, 0.025)
	b.add_box(edge_size, PlotBuilders.WOOD, _at(Vector3(K_X, shade_y, center_z + depth / 2.0)))

func _dress_restaurant(n: Node3D, b: MeshBatch) -> void:
	var sand := Color("e1c7a2")
	var green := Color("205c50")
	var bronze := Color("ab8253")
	var front := K_FRONT + 0.018
	var roof_y := 1.48 if stage >= 5 else 1.28
	var depth := K_FRONT - K_BACK
	var center_z := (K_FRONT + K_BACK) / 2.0
	var outer_x := K_X + K_W / 2.0
	# Thicken outwards only: original inner wall faces and kitchen remain intact.
	var cheek_w := 0.04
	var cheek_x := K_W / 2.0 + cheek_w / 2.0
	for side in [-1.0, 1.0]:
		b.add_box(Vector3(cheek_w, roof_y, depth), sand, _at(Vector3(K_X + side * cheek_x, roof_y / 2.0, center_z)))
	var back_depth := 0.05
	b.add_box(Vector3(K_W + cheek_w * 2.0, roof_y, back_depth), sand, _at(Vector3(K_X, roof_y / 2.0, K_BACK - back_depth / 2.0)))
	var pier_w := 0.10
	var pier_depth := 0.11
	var pier_offset := K_W / 2.0 - pier_w / 2.0
	for side in [-1.0, 1.0]:
		b.add_box(Vector3(pier_w, roof_y, pier_depth), CREAM, _at(Vector3(K_X + side * pier_offset, roof_y / 2.0, K_FRONT)))
	_arch_frame(b)
	# Original plinth and service labels: same positions and clear approach.
	var plinth_size := Vector3(K_W, 0.25, 0.025)
	var plinth_y := 0.227
	var rail_size := Vector3(K_W + 0.04, 0.038, 0.044)
	var rail_y := 0.366
	b.add_box(plinth_size, green, _at(Vector3(K_X, plinth_y, front)))
	b.add_box(rail_size, bronze, _at(Vector3(K_X, rail_y, front)))
	var marker_size := Vector3(0.30, 0.075, 0.015)
	var marker_y := 0.301
	var marker_z := front + 0.026
	var inlay_size := Vector3(0.22, 0.009, 0.036)
	var inlay_y := 0.022
	var inlay_z := 0.57
	for x in [K_X - 0.40, K_X + 0.41]:
		b.add_box(marker_size, green, _at(Vector3(x, marker_y, marker_z)))
		b.add_box(inlay_size, bronze, _at(Vector3(x, inlay_y, inlay_z)))
	_service_markers(n, K_X - 0.40, K_X + 0.41, front + 0.035, 0.301)
	# Fitted timber panels on the visible +X wall, clear of the external stations.
	var panel_w := 0.30
	var panel_h := 0.35
	var panel_y := 0.89
	var panel_x := outer_x + cheek_w + 0.016
	var panel_zs := [K_BACK + 0.25, K_BACK + 0.73]
	for z in panel_zs:
		_heritage_lattice(b, Vector3(panel_x, panel_y, z), panel_w, panel_h, PI / 2.0)
	# Only the existing BACK edge of the terrace has a screen: never a front arcade.
	var left := -_gap + 0.14
	var right := -0.33
	var back := -1.04
	var screen_top := 0.87
	var screen_bottom := 0.31
	var screen_h := screen_top - screen_bottom
	var bay_count := ceili((right - left) / 0.52)
	var bay_w := (right - left) / bay_count
	var screen_cap := Vector3(right - left, 0.07, 0.16)
	var screen_post_w := 0.07
	for x in [left, right]:
		PlotBuilders.post(b, Vector3(x, 0, back), screen_top, PlotBuilders.WOOD, screen_post_w)
	for i in range(bay_count):
		var x := left + (i + 0.5) * bay_w
		_heritage_lattice(b, Vector3(x, (screen_top + screen_bottom) / 2.0, back), bay_w, screen_h)
	b.add_box(screen_cap, CREAM, _at(Vector3((left + right) / 2.0, screen_top, back)))
	# Hanging lanterns share one mesh batch and the existing day/night glass swap.
	var lanterns: Array = []
	var bracket_size := Vector3(0.035, 0.035, 0.17)
	var bracket_y := 1.17
	var bracket_z := K_FRONT + 0.07
	var chain_size := Vector3(0.014, 0.055, 0.014)
	var chain_y := bracket_y - chain_size.y / 2.0
	var lantern_y := bracket_y - 0.24
	var lantern_z := K_FRONT + 0.145
	var lantern_scale := 0.80
	for side in [-1.0, 1.0]:
		var x: float = K_X + side * pier_offset
		b.add_box(bracket_size, PlotBuilders.WOOD, _at(Vector3(x, bracket_y, bracket_z)))
		b.add_box(chain_size, PlotBuilders.WOOD, _at(Vector3(x, chain_y, lantern_z)))
		lanterns.append(PlotBuilders.lantern_at(Vector3(x, lantern_y, lantern_z), lantern_scale))
	if stage >= 5:
		# A raised rooftop terrace band, with timber balustrade in its side recesses.
		var band_bottom := 1.27
		var band_top := 1.43
		var band_h := band_top - band_bottom
		var band_w := 0.72
		var band_center_z := center_z - 0.02
		for side in [-1.0, 1.0]:
			var band_x: float = K_X + side * (K_W / 2.0 + cheek_w + 0.018)
			_heritage_lattice(b, Vector3(band_x, (band_bottom + band_top) / 2.0, band_center_z), band_w, band_h, PI / 2.0)
		var upper_bracket_y := roof_y + 0.10
		var upper_lantern_y := upper_bracket_y - 0.24
		var side_bracket_size := Vector3(bracket_size.z, bracket_size.y, bracket_size.x)
		var side_bracket_x := outer_x + cheek_w + 0.07
		var side_lantern_x := outer_x + cheek_w + 0.145
		for z in panel_zs:
			b.add_box(side_bracket_size, PlotBuilders.WOOD, _at(Vector3(side_bracket_x, upper_bracket_y, z)))
			b.add_box(chain_size, PlotBuilders.WOOD, _at(Vector3(side_lantern_x, upper_bracket_y - chain_size.y / 2.0, z)))
			lanterns.append(PlotBuilders.lantern_at(Vector3(side_lantern_x, upper_lantern_y, z), lantern_scale))
		_wind_tower(b, roof_y, sand)
	var mmi := PlotBuilders.lantern_batch(n, lanterns)
	if mmi:
		_lanterns.append(mmi)

## Thick pale coping with broad crenels, plus exposed chandal beam ends.
func _heritage_roof(b: MeshBatch, roof_y: float, sand: Color) -> void:
	var depth := K_FRONT - K_BACK
	var center_z := (K_FRONT + K_BACK) / 2.0
	var roof_lip := 0.10
	var slab_h := 0.05
	var parapet_h := 0.08 if stage >= 5 else 0.10
	var parapet_w := 0.09
	var parapet_y := roof_y + slab_h + parapet_h / 2.0
	var front_z := K_FRONT - 0.025
	var back_z := K_BACK - 0.005
	var side_offset := K_W / 2.0
	var crenel_h := 0.065
	var crenel_w := 0.16
	var crenel_y := roof_y + slab_h + parapet_h + crenel_h / 2.0
	var front_count := 7
	var side_count := 4
	b.add_box(Vector3(K_W + roof_lip, slab_h, depth + roof_lip), CREAM, _at(Vector3(K_X, roof_y + slab_h / 2.0, center_z)))
	for z in [front_z, back_z]:
		b.add_box(Vector3(K_W + roof_lip, parapet_h, parapet_w), sand, _at(Vector3(K_X, parapet_y, z)))
		for i in range(front_count):
			var x := K_X - side_offset + i * K_W / (front_count - 1)
			b.add_box(Vector3(crenel_w, crenel_h, parapet_w), CREAM, _at(Vector3(x, crenel_y, z)))
	for side in [-1.0, 1.0]:
		var x: float = K_X + side * side_offset
		b.add_box(Vector3(parapet_w, parapet_h, depth), sand, _at(Vector3(x, parapet_y, center_z)))
		for i in range(1, side_count - 1):
			var z := lerpf(back_z, front_z, float(i) / (side_count - 1))
			b.add_box(Vector3(parapet_w, crenel_h, crenel_w), CREAM, _at(Vector3(x, crenel_y, z)))
	var beam_r := 0.018
	var beam_length := 0.16
	var beam_y := roof_y - 0.09
	var beam_count := 9
	var beam_span := K_W - 0.18
	var beam_front_z := K_FRONT + 0.045
	for i in range(beam_count):
		var x := K_X - beam_span / 2.0 + i * beam_span / (beam_count - 1)
		b.add_cyl(beam_r, beam_length, PlotBuilders.WOOD, _rx(Vector3(x, beam_y, beam_front_z), PI / 2.0))
	var side_beam_count := 4
	var side_beam_x := K_X + K_W / 2.0 + 0.04
	var side_beam_span := depth - 0.24
	for i in range(side_beam_count):
		var z := center_z - side_beam_span / 2.0 + i * side_beam_span / (side_beam_count - 1)
		b.add_cyl(beam_r, beam_length, PlotBuilders.WOOD, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(side_beam_x, beam_y, z)))

## A pointed surround outside the full rectangular aperture, including its top corners.
func _arch_frame(b: MeshBatch) -> void:
	var trim_w := 0.045
	var trim_d := 0.035
	var jamb_offset := WIN_W / 2.0 + trim_w / 2.0 + 0.008
	var spring_y := WIN_TOP + 0.055
	var shoulder_y := WIN_TOP + 0.20
	var apex_y := WIN_TOP + 0.32
	var shoulder_offset := WIN_W * 0.29
	var face_z := K_FRONT + 0.038
	var jamb_h := spring_y - COUNTER_Y
	for side in [-1.0, 1.0]:
		var foot := Vector3(K_X + side * jamb_offset, spring_y, face_z)
		var shoulder := Vector3(K_X + side * shoulder_offset, shoulder_y, face_z)
		var apex := Vector3(K_X, apex_y, face_z)
		b.add_box(Vector3(trim_w, jamb_h, trim_d), DECK, _at(Vector3(foot.x, (spring_y + COUNTER_Y) / 2.0, face_z)))
		_heritage_bar(b, foot, shoulder, trim_w, trim_d, DECK)
		_heritage_bar(b, shoulder, apex, trim_w, trim_d, DECK)

## Box segments use the same cached unit mesh as all other building details.
func _heritage_bar(b: MeshBatch, a: Vector3, end: Vector3, width: float, depth: float, col: Color, frame: Transform3D = Transform3D.IDENTITY) -> void:
	var delta := end - a
	var basis := Basis(Vector3.BACK, -atan2(delta.x, delta.y))
	var size := Vector3(width, delta.length(), depth)
	b.add_box(size, col, frame * Transform3D(basis, (a + end) / 2.0))

## Clipped diagonal laths form real open diamonds, rather than a solid panel texture.
func _heritage_lattice(b: MeshBatch, center: Vector3, width: float, height: float, yaw: float = 0.0) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var rail_w := 0.026
	var rail_d := 0.025
	var lath_w := 0.012
	var lath_d := 0.014
	var pitch := 0.12
	var half_w := (width - rail_w) / 2.0
	var half_h := (height - rail_w) / 2.0
	var line_count := ceili((half_w + half_h) / pitch)
	for side in [-1.0, 1.0]:
		b.add_box(Vector3(rail_w, height, rail_d), PlotBuilders.WOOD, frame * _at(Vector3(side * half_w, 0, 0)))
		b.add_box(Vector3(width, rail_w, rail_d), PlotBuilders.WOOD, frame * _at(Vector3(0, side * half_h, 0)))
	for direction in [-1.0, 1.0]:
		for i in range(-line_count, line_count + 1):
			var offset := i * pitch
			var low := maxf(-half_h, -half_w - offset)
			var high := minf(half_h, half_w - offset)
			if high - low < lath_w:
				continue
			var a := Vector3(direction * (low + offset), low, 0)
			var end := Vector3(direction * (high + offset), high, 0)
			_heritage_bar(b, a, end, lath_w, lath_d, PlotBuilders.WOOD, frame)

## Square, genuinely open barjeel at the rear +X corner, away from the -X terrace.
func _wind_tower(b: MeshBatch, roof_y: float, sand: Color) -> void:
	var tower_w := 0.46
	var corner_inset := 0.29
	var center := Vector3(K_X + K_W / 2.0 - corner_inset, 0, K_BACK + corner_inset)
	var neck_h := 0.22
	var sill_h := 0.05
	var sill_w := 0.52
	var vent_h := 0.38
	var vent_bottom := roof_y + neck_h + sill_h
	var vent_top := vent_bottom + vent_h
	var vent_y := (vent_bottom + vent_top) / 2.0
	var post_w := 0.06
	var post_offset := (tower_w - post_w) / 2.0
	var cap_h := 0.07
	var cap_w := 0.57
	var cap_y := vent_top + cap_h / 2.0
	var crown_h := 0.03
	var crown_w := 0.49
	var crown_y := vent_top + cap_h + crown_h / 2.0
	# At stage 5: top = 1.48 + .22 + .05 + .38 + .07 + .03 = 2.23.
	b.add_box(Vector3(tower_w, neck_h, tower_w), sand, _at(center + Vector3.UP * (roof_y + neck_h / 2.0)))
	b.add_box(Vector3(sill_w, sill_h, sill_w), CREAM, _at(center + Vector3.UP * (roof_y + neck_h + sill_h / 2.0)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.add_box(Vector3(post_w, vent_h, post_w), sand, _at(center + Vector3(sx * post_offset, vent_y, sz * post_offset)))
	var brace_half := tower_w / 2.0 - post_w
	var brace_w := 0.018
	var brace_d := 0.018
	var vent_face := tower_w / 2.0 - brace_d / 2.0
	var brace_half_h := vent_h / 2.0 - 0.025
	for face in range(4):
		var yaw := face * PI / 2.0
		var frame := Transform3D(Basis(Vector3.UP, yaw), center + Vector3.UP * vent_y)
		for direction in [-1.0, 1.0]:
			var a := Vector3(-brace_half, -direction * brace_half_h, vent_face)
			var end := Vector3(brace_half, direction * brace_half_h, vent_face)
			_heritage_bar(b, a, end, brace_w, brace_d, PlotBuilders.WOOD, frame)
	b.add_box(Vector3(cap_w, cap_h, cap_w), CREAM, _at(center + Vector3.UP * cap_y))
	b.add_box(Vector3(crown_w, crown_h, crown_w), sand, _at(center + Vector3.UP * crown_y))
	var pole_r := 0.018
	var pole_length := tower_w + 0.18
	var pole_y := vent_bottom + 0.035
	var pole_offset := 0.14
	for side in [-1.0, 1.0]:
		b.add_cyl(pole_r, pole_length, PlotBuilders.WOOD, _rx(center + Vector3(side * pole_offset, pole_y, 0), PI / 2.0))
		b.add_cyl(pole_r, pole_length, PlotBuilders.WOOD, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), center + Vector3(0, pole_y, side * pole_offset)))

# ---------------------------------------------------------------- terrace + seating

func _layout_terrace() -> void:
	_slots.clear()
	if stage < FIXED:
		return
	_music_spot = Vector3(3.36, 0, -0.04) # Side-wall pocket: tier-4 bounds x 3.15..3.57, z -0.36..0.28.
	for r in range(ROWS.size()):
		var x := FIRST_TABLE_X
		while x - 0.34 >= -_gap + 0.03:
			_slots.append(Vector3(x, 0, ROWS[r]))
			x -= TABLE_PITCH

func _build_terrace(n: Node3D, b: MeshBatch) -> void:
	var left := -_gap + 0.03
	var right := -0.28
	var back := -1.12
	var front := FRONT_AISLE_Z + 0.12
	var center := (left + right) * 0.5
	b.add_box(Vector3(right - left, DECK_Y, front - back), DECK, _at(Vector3(center, DECK_Y * 0.5, (front + back) * 0.5)))
	var inlay := Color("ab815d")
	for z in [AISLE_Z - 0.12, AISLE_Z + 0.12, front - 0.065]:
		b.add_box(Vector3(right - left - 0.04, 0.005, 0.028), inlay, _at(Vector3(center, DECK_Y + 0.002, z)))
	# Only the perimeter has planters. The front approach and side entry stay open.
	for z in [-0.92, 0.63]:
		var p := Vector3(left + 0.08, DECK_Y, z)
		b.add_box(Vector3(0.14, 0.10, 0.18), Color("976950"), _at(p + Vector3.UP * 0.05))
		b.add_box(Vector3(0.156, 0.025, 0.195), Color("bc9670"), _at(p + Vector3.UP * 0.10))
		b.add_model(PlotBuilders.PROPS["bush"], Transform3D(Basis.from_scale(Vector3.ONE * 0.38), p + Vector3.UP * 0.108))
	if stage == 3:
		PlotBuilders.spawn("parasol_a", n, Vector3(left + 0.3, DECK_Y, -0.93), 15, 1.10)

func _build_seating(n: Node3D, count: int, lounge: int) -> void:
	seats.clear()
	tables.clear()
	var b := MeshBatch.new()
	var walnut := Color("5c4334")
	var cloth := Color("e1c7a2")
	var teal := Color("39726a")
	for i in range(mini(count, _slots.size())):
		var p: Vector3 = _slots[i] + Vector3.UP * DECK_Y
		var is_majlis := i >= count - lounge
		var tabletop := 0.265 if is_majlis else 0.289
		if is_majlis:
			_majlis_rug(b, p)
		b.add_cyl(0.05, 0.022, walnut, _at(p + Vector3.UP * 0.011), 0.0, 12)
		b.add_cyl(0.025, tabletop - 0.009, walnut, _at(p + Vector3.UP * (tabletop * 0.5 + 0.002)), 0.0, 12)
		b.add_cyl(0.143, 0.026, walnut, _at(p + Vector3.UP * tabletop), 0.0, 20)
		b.add_cyl(0.121, 0.007, cloth, _at(p + Vector3.UP * (tabletop + 0.015)), 0.0, 20)
		var meal := Node3D.new()
		meal.position = p + Vector3.UP * (tabletop + 0.019)
		meal.visible = false
		n.add_child(meal)
		var meals: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var place := Node3D.new()
			place.position.x = side * 0.062
			place.hide()
			meal.add_child(place)
			PlotBuilders.spawn("plate", place, Vector3.ZERO, 0, 0.18, false)
			PlotBuilders.spawn("cup", place, Vector3(0, 0, -0.063), 0, 0.12, false)
			meals.append(place)
		tables.append({"pos": p, "node": meal, "meals": meals, "dirty": false, "assigned": false})
		for side in [-1.0, 1.0]:
			var chair := p + Vector3(side * CHAIR_X, 0, 0)
			if is_majlis:
				_majlis_seat(b, chair, side, walnut)
			else:
				b.add_box(Vector3(0.147, 0.029, 0.16), teal, _at(chair + Vector3.UP * 0.185))
				for z in [-0.059, 0.059]:
					for x in [-0.055, 0.055]:
						b.add_box(Vector3(0.017, 0.17, 0.017), walnut, _at(chair + Vector3(x, 0.085, z)))
				b.add_box(Vector3(0.025, 0.17, 0.155), walnut, _at(chair + Vector3(side * 0.066, 0.258, 0)))
			var route: Array[Vector3] = [Vector3(chair.x, 0, FRONT_AISLE_Z)]
			if p.z < AISLE_Z:
				route = [Vector3(ENTRY_X, 0, FRONT_AISLE_Z), Vector3(ENTRY_X, 0, AISLE_Z), Vector3(chair.x, 0, AISLE_Z)]
			seats.append({"idx": seats.size(), "table": i, "pos": Vector3(chair.x, 0, chair.z), "facing": -side * PI / 2.0,
				"route": route, "y_off": 0.027, "who": null, "needs_clean": false})
	b.flush(n)

func _majlis_rug(b: MeshBatch, p: Vector3) -> void:
	b.add_box(Vector3(0.60, 0.006, 0.42), Color("813a40"), _at(p + Vector3.UP * 0.006))
	for z in [-0.184, -0.157, 0.157, 0.184]:
		b.add_box(Vector3(0.58, 0.003, 0.009), PlotBuilders.GOLD, _at(p + Vector3(0, 0.010, z)))

func _majlis_seat(b: MeshBatch, chair: Vector3, side: float, wood: Color) -> void:
	var red := Color("a64d51")
	b.add_box(Vector3(0.15, 0.135, 0.185), wood, _at(chair + Vector3.UP * 0.084))
	b.add_box(Vector3(0.15, 0.049, 0.185), red, _at(chair + Vector3.UP * 0.176))
	b.add_box(Vector3(0.031, 0.105, 0.185), red.darkened(0.19), _at(chair + Vector3(side * 0.067, 0.237, 0)))
	for z in [-0.066, 0.066]:
		b.add_box(Vector3(0.152, 0.003, 0.012), PlotBuilders.GOLD, _at(chair + Vector3(0, 0.202, z)))

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
		var roast := PlotBuilders.spawn("doner", spit, Vector3.ZERO, 0, 0.36)
		var rotor := roast.find_child("SpitRotor", true, false) as Node3D if roast else null
		if rotor:
			_spits.append(rotor)
		ModelLib.box(n, Vector3(0.12, 0.3, 0.02), Vector3(x, COUNTER_Y + 0.18, LINE_Z - 0.1), Color(1.0, 0.45, 0.1), 1.8)

func _st_fryer(n: Node3D, t: int) -> void:
	PlotBuilders.fryer(n, Vector3(K_X + 0.16, COUNTER_Y, LINE_Z), t)

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
	PlotBuilders.dessert_case(n, Vector3(K_X + 0.46, COUNTER_Y + 0.04, K_FRONT + 0.01), t)

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
	var front := FRONT_AISLE_Z
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
	# Face the +X/+Z camera; keep the full carpet outside the desk/oven and walking strip.
	n.position = _music_spot
	n.rotation.y = PI / 2.0
	var p := Vector3.ZERO
	var timber := Color("503520")
	var brass := Color("c79a43")
	var date_brown := Color("442719")
	var cream := Color("efe0bb")
	var clay := Color("984636")
	var palm_green := Color("456943")
	var platform_size := Vector3(0.64, 0.032, 0.42)
	var carpet_size := Vector3(0.62, 0.008, 0.40)
	var carpet_center := Vector3(0, 0.036, 0)
	var border_y := 0.041
	var border_inset := Vector2(0.288, 0.178)
	var border_thickness := 0.002
	var border_width := 0.008
	var base := 0.040 if t >= 4 else 0.0
	if t >= 4:
		b.add_box(platform_size, timber, _at(p + Vector3.UP * platform_size.y * 0.5))
		b.add_box(carpet_size, clay, _at(p + carpet_center))
		for side in [-1.0, 1.0]:
			var long_border := Vector3(carpet_size.x - border_width * 4, border_thickness, border_width)
			var short_border := Vector3(border_width, border_thickness, carpet_size.z - border_width * 4)
			b.add_box(long_border, brass, _at(p + Vector3(0, border_y, side * border_inset.y)))
			b.add_box(short_border, brass, _at(p + Vector3(side * border_inset.x, border_y, 0)))
	# Low side table: four dark wooden legs, with dates kept forward of the coffee pot.
	var table_center := p + Vector3(-0.080, base, 0.025)
	var table_size := Vector3(0.38, 0.020, 0.27)
	var table_top := 0.235
	var leg_height := table_top - table_size.y
	var leg_size := Vector3(0.023, leg_height, 0.023)
	var leg_spacing := Vector2(0.160, 0.105)
	b.add_box(table_size, timber, _at(table_center + Vector3.UP * (table_top - table_size.y * 0.5)))
	for side_x in [-1.0, 1.0]:
		for side_z in [-1.0, 1.0]:
			var leg_center := Vector3(side_x * leg_spacing.x, leg_height * 0.5, side_z * leg_spacing.y)
			b.add_box(leg_size, timber, _at(table_center + leg_center))
	var tray_center := p + Vector3(-0.170, base + table_top + 0.006, 0.070)
	var tray_radius := 0.075
	var tray_height := 0.012
	var tray_sides := 12
	var date_radius := 0.018
	var date_height := 0.020
	var date_stretch := Vector3(1.0, 1.0, 0.65)
	var date_offsets := [Vector3(-0.030, 0.015, -0.015), Vector3(0.008, 0.015, -0.025),
		Vector3(0.033, 0.015, 0.006), Vector3(-0.017, 0.015, 0.022),
		Vector3(0.012, 0.030, 0.004)]
	b.add_cyl(tray_radius, tray_height, brass, _at(tray_center), 0.0, tray_sides)
	for offset: Vector3 in date_offsets:
		b.add_cyl(date_radius, date_height, date_brown,
			Transform3D(Basis.from_scale(date_stretch), tray_center + offset), 0.0, 8)
	# Fresh tapered meshes give the belly/lid real slopes; cached resources stay untouched.
	var taper := func(center: Vector3, lower_radius: float, upper_radius: float, height: float, color: Color, sides: int = 10) -> void:
		var shape := CylinderMesh.new()
		shape.bottom_radius = lower_radius
		shape.top_radius = upper_radius
		shape.height = height
		shape.radial_segments = sides
		shape.rings = 1
		shape.material = ModelLib.flat_material(color)
		b.add_mesh("hospitality_%d" % shape.get_instance_id(), shape, Transform3D(Basis.IDENTITY, center))
	var dallah := func(origin: Vector3, size: float) -> void:
		# Radius/height profile: foot, rounded belly, narrow waist, flared neck, pointed lid.
		var body_profile := [Vector2(0.031, 0.000), Vector2(0.043, 0.014),
			Vector2(0.052, 0.042), Vector2(0.047, 0.070), Vector2(0.025, 0.105),
			Vector2(0.023, 0.132), Vector2(0.037, 0.149), Vector2(0.039, 0.155),
			Vector2(0.008, 0.179), Vector2(0.0, 0.192)]
		for i in range(body_profile.size() - 1):
			var lower: Vector2 = body_profile[i]
			var upper: Vector2 = body_profile[i + 1]
			var center := origin + Vector3.UP * (lower.y + upper.y) * 0.5 * size
			taper.call(center, lower.x * size, upper.x * size, (upper.y - lower.y) * size, brass)
		# Face the spout/handle toward the camera independently of the quarter-turned table.
		var spout_points := [Vector3(0.037, 0.052, 0), Vector3(0.067, 0.073, 0),
			Vector3(0.081, 0.104, 0), Vector3(0.091, 0.135, 0), Vector3(0.109, 0.154, 0)]
		var spout_radii := [0.016, 0.013, 0.010, 0.006]
		var handle_points := [Vector3(-0.027, 0.135, 0), Vector3(-0.064, 0.144, 0),
			Vector3(-0.084, 0.122, 0), Vector3(-0.086, 0.087, 0),
			Vector3(-0.064, 0.058, 0), Vector3(-0.045, 0.058, 0)]
		var handle_radius := 0.007
		var stroke_sides := 8
		var coffee_facing := Basis(Vector3.UP, deg_to_rad(-76))
		for stroke in [spout_points, handle_points]:
			for i in range(stroke.size() - 1):
				var start: Vector3 = origin + coffee_facing * stroke[i] * size
				var end: Vector3 = origin + coffee_facing * stroke[i + 1] * size
				var direction := end - start
				var radius: float = (spout_radii[i] if stroke == spout_points else handle_radius) * size
				var axis := Basis(Quaternion(Vector3.UP, direction.normalized()))
				b.add_cyl(radius, direction.length() + radius * 0.4, brass,
					Transform3D(axis, (start + end) * 0.5), 0.0, stroke_sides)
	if t >= 2:
		var pot_origin := p + Vector3(-0.015, base + table_top, -0.025)
		var pot_scale := 1.0
		dallah.call(pot_origin, pot_scale)
		# Three nested, handleless finjan; brass rims separate the cream cup silhouettes.
		var cups_origin := p + Vector3(0.060, base + table_top, 0.100)
		var cup_count := 3
		var cup_pitch := 0.014
		var cup_height := 0.025
		var cup_lower_radius := 0.014
		var cup_upper_radius := 0.021
		var cup_rim_height := 0.003
		for i in range(cup_count):
			var cup_center := cups_origin + Vector3.UP * (cup_height * 0.5 + i * cup_pitch)
			taper.call(cup_center, cup_lower_radius, cup_upper_radius, cup_height, cream)
			var rim_center := cups_origin + Vector3.UP * (cup_height + i * cup_pitch)
			b.add_cyl(cup_upper_radius, cup_rim_height, brass, _at(rim_center), 0.0, 10)
	if t >= 3:
		# Mabkhara on its own small stand, clear of the side table and palm pot.
		var burner_origin := p + Vector3(0.225, base, 0.095)
		var stand_top := 0.160
		var stand_size := Vector3(0.115, 0.018, 0.115)
		var stand_leg_height := stand_top - stand_size.y
		var stand_leg_size := Vector3(0.018, stand_leg_height, 0.018)
		var stand_leg_spacing := 0.043
		b.add_box(stand_size, timber, _at(burner_origin + Vector3.UP * (stand_top - stand_size.y * 0.5)))
		for side_x in [-1.0, 1.0]:
			for side_z in [-1.0, 1.0]:
				var leg_center := Vector3(side_x * stand_leg_spacing, stand_leg_height * 0.5, side_z * stand_leg_spacing)
				b.add_box(stand_leg_size, timber, _at(burner_origin + leg_center))
		# Four-sided tapered pedestal / bowl. Rotate diagonal cylinder corners to X/Z.
		var burner_profile := [Vector2(0.052, 0.000), Vector2(0.052, 0.014),
			Vector2(0.027, 0.057), Vector2(0.057, 0.102)]
		var square_turn := Basis(Vector3.UP, PI / 4.0)
		for i in range(burner_profile.size() - 1):
			var lower: Vector2 = burner_profile[i]
			var upper: Vector2 = burner_profile[i + 1]
			var shape := CylinderMesh.new()
			shape.bottom_radius = lower.x
			shape.top_radius = upper.x
			shape.height = upper.y - lower.y
			shape.radial_segments = 4
			shape.rings = 1
			shape.material = ModelLib.flat_material(brass)
			var center := burner_origin + Vector3.UP * (stand_top + (lower.y + upper.y) * 0.5)
			b.add_mesh("mabkhara_%d" % i, shape, Transform3D(square_turn, center))
		var coal_size := Vector3(0.064, 0.003, 0.064)
		var coal_height := stand_top + 0.103
		var horn_size := Vector3(0.014, 0.032, 0.014)
		var horn_spacing := 0.033
		var horn_center_y := stand_top + 0.114
		b.add_box(coal_size, date_brown, _at(burner_origin + Vector3.UP * coal_height))
		for side_x in [-1.0, 1.0]:
			for side_z in [-1.0, 1.0]:
				var horn_center := Vector3(side_x * horn_spacing, horn_center_y, side_z * horn_spacing)
				b.add_box(horn_size, brass, _at(burner_origin + horn_center))
	if t >= 4:
		var palm_origin := p + Vector3(0.225, base, -0.125)
		var pot_height := 0.070
		var pot_lower_radius := 0.032
		var pot_upper_radius := 0.045
		var trunk_height := 0.245
		var trunk_radius := 0.011
		var leaf_reach := 0.078
		var leaf_peak_radius := 0.034
		var leaf_peak_height := 0.365
		var leaf_tip_height := 0.305
		var leaf_width := 0.023
		var leaf_depth := 0.007
		var leaf_count := 6
		taper.call(palm_origin + Vector3.UP * pot_height * 0.5, pot_lower_radius, pot_upper_radius, pot_height, clay)
		b.add_cyl(trunk_radius, trunk_height, timber, _at(palm_origin + Vector3.UP * (pot_height + trunk_height * 0.5)), 0.0, 8)
		var crown := palm_origin + Vector3.UP * (pot_height + trunk_height)
		for i in range(leaf_count):
			var angle := TAU * i / leaf_count
			var radial := Vector3(cos(angle), 0, sin(angle))
			var leaf_start := crown
			var leaf_peak := palm_origin + radial * leaf_peak_radius + Vector3.UP * leaf_peak_height
			var leaf_tip := palm_origin + radial * leaf_reach + Vector3.UP * leaf_tip_height
			for segment in [[leaf_start, leaf_peak], [leaf_peak, leaf_tip]]:
				var start: Vector3 = segment[0]
				var end: Vector3 = segment[1]
				var direction := end - start
				var leaf_size := Vector3(leaf_width, leaf_depth, direction.length())
				var leaf_axis := Basis.looking_at(direction, Vector3.UP)
				b.add_box(leaf_size, palm_green, Transform3D(leaf_axis, (start + end) * 0.5))
	# Bake this local batch's palette into vertex colours: one surface / one draw call.
	# Read primitive arrays only; never alter ModelLib's cached meshes or materials.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for key in b._order:
		var group: Dictionary = b._groups[key]
		var source: Mesh = group["mesh"]
		for surface in range(source.get_surface_count()):
			var arrays := source.surface_get_arrays(surface)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material := group["mat"] as StandardMaterial3D
			if material == null:
				material = source.surface_get_material(surface) as StandardMaterial3D
			var color := material.albedo_color
			for transform: Transform3D in group["xforms"]:
				var offset := vertices.size()
				var normal_basis := transform.basis.inverse().transposed()
				for i in range(source_vertices.size()):
					vertices.append(transform * source_vertices[i])
					normals.append((normal_basis * source_normals[i]).normalized())
					colors.append(color)
				for index in source_indices:
					indices.append(offset + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var corner := ArrayMesh.new()
	corner.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var palette := ModelLib.flat_material_unique(Color.WHITE)
	palette.vertex_color_use_as_albedo = true
	palette.vertex_color_is_srgb = true
	corner.surface_set_material(0, palette)
	b = MeshBatch.new()
	b.add_mesh("hospitality", corner, Transform3D.IDENTITY)
	b.flush(n)

func _st_shade(n: Node3D, t: int) -> void:
	var b := MeshBatch.new()
	# tier 1: one more parasol over the back row
	PlotBuilders.spawn("parasol_b", n, Vector3(-_gap + 0.12, DECK_Y, -0.92), 15, 1.15)
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
	if stage == 2:
		n.scale = Vector3.ONE * FoodTruck.SCALE
		var strip := ModelLib.box(n, Vector3(1.88, 0.018, 0.023), Vector3(0.23, 0.983, 0.36), Color("c9ae82"))
		_bulbs.append(strip)
		for x in [-0.79, 1.27]:
			b.add_box(Vector3(0.064, 0.046, 0.04), FoodTruck.STEEL, _at(Vector3(x, 0.963, 0.388)))
			if t >= 2:
				_bulbs.append(ModelLib.box(n, Vector3(0.044, 0.027, 0.012), Vector3(x, 0.963, 0.413), Color("c9ae82")))
		_light(n, Vector3(0.19, 0.86, 0.49), Color("ffd9a3"), 0.44 + 0.08 * t, 1.35)
		b.flush(n)
		return
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

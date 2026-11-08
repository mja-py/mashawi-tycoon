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
			for x in ([1.215] if t == 1 else [-0.765, 1.215]):
				var p := Vector3(x, 0.953, 0.226)
				b.add_box(Vector3(0.074, 0.089, 0.061), PlotBuilders.DARK, _at(p))
				b.add_cyl(0.022, 0.008, FoodTruck.STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), p + Vector3.BACK * 0.034), 0.0, 12)
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
	if stage >= 4:
		_dress_restaurant(n, b)
	_build_terrace(n, b)
	b.flush(n)

func _dress_restaurant(n: Node3D, b: MeshBatch) -> void:
	var green := Color("205c50")
	var bronze := Color("ab8253")
	var ivory := Color("e1c7a2")
	var front := K_FRONT + 0.018
	# A tiled plinth, a timber service bar, and a fascia continuous with the roof.
	b.add_box(Vector3(K_W, 0.25, 0.025), green, _at(Vector3(K_X, 0.227, front)))
	for i in range(17):
		var x := K_X + (i - 8) * 0.103
		b.add_box(Vector3(0.036, 0.036, 0.009), bronze,
			Transform3D(Basis(Vector3.BACK, PI / 4.0), Vector3(x, 0.201, front + 0.017)))
	b.add_box(Vector3(K_W + 0.04, 0.038, 0.044), bronze, _at(Vector3(K_X, 0.366, front)))
	b.add_box(Vector3(K_W + 0.14, 0.106, 0.13), green, _at(Vector3(K_X, 1.041, front + 0.018)))
	b.add_box(Vector3(K_W + 0.19, 0.028, 0.18), bronze, _at(Vector3(K_X, 1.107, front + 0.01)))
	for x in [K_X - 0.40, K_X + 0.41]:
		b.add_box(Vector3(0.30, 0.075, 0.015), green, _at(Vector3(x, 0.301, front + 0.026)))
		b.add_box(Vector3(0.22, 0.009, 0.036), bronze, _at(Vector3(x, 0.022, 0.57)))
	_service_markers(n, K_X - 0.40, K_X + 0.41, front + 0.035, 0.301)
	# The screened back wall keeps the terrace open to the street and camera.
	var left := -_gap + 0.14
	var right := -0.33
	var back := -1.04
	for x in [left, right]:
		b.add_box(Vector3(0.07, 0.87, 0.07), PlotBuilders.WOOD, _at(Vector3(x, 0.435, back)))
	b.add_box(Vector3(right - left, 0.062, 0.08), PlotBuilders.WOOD, _at(Vector3((left + right) * 0.5, 0.85, back)))
	b.add_box(Vector3(right - left, 0.047, 0.047), PlotBuilders.WOOD, _at(Vector3((left + right) * 0.5, 0.307, back)))
	for i in range(floori((right - left) / 0.13)):
		var x := left + 0.11 + i * 0.13
		b.add_box(Vector3(0.035, 0.52, 0.026), PlotBuilders.WOOD, _at(Vector3(x, 0.57, back)))
	b.add_box(Vector3(right - left, 0.07, 0.20), ivory, _at(Vector3((left + right) * 0.5, 0.87, back + 0.038)))
	if stage >= 5:
		# Flagship: a second roofline and repeating bronze fins over the lounge.
		b.add_box(Vector3(right - left + 0.16, 0.09, 0.51), green, _at(Vector3((left + right) * 0.5, 1.06, back + 0.16)))
		for i in range(11):
			var x := lerpf(left, right, float(i) / 10.0)
			b.add_box(Vector3(0.037, 0.038, 0.60), bronze, _at(Vector3(x, 1.122, back + 0.17)))

# ---------------------------------------------------------------- terrace + seating

func _layout_terrace() -> void:
	_slots.clear()
	if stage < FIXED:
		return
	_music_spot = Vector3(-_gap + 0.24, 0, -0.99)
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
		var player := ModelLib.spawn_guest("souq-man", n, p + Vector3(0, base + 0.08, 0.02), 0.54)
		if player:
			ModelLib.play_loop(player, "sit", 0.6)
			b.add_box(Vector3(0.08, 0.12, 0.03), Color(0.55, 0.32, 0.15), _at(p + Vector3(0.0, base + 0.25, 0.14)))
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

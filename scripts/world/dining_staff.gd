class_name DiningStaff
extends Node3D
## One restaurant worker completes a delivery or clears a table before taking another job.

enum State { IDLE, WALK, COLLECT, DELIVER, CLEAN }

var site: Plot
var index := 0
var state: State = State.IDLE
var model: Node3D
var tray: Node3D
var _cloth: Node3D
var _route: Array[Vector3] = []
var _arrive: Callable
var _after_work: Callable
var _work_left := 0.0
var _yaw := 0.0
var _customer: Customer
var _item := ""
var _table := -1
var _on_delivery: Callable
var _tray_from := Vector3.ZERO
var _tray_transfer := 1.0

func setup(plot: Plot, worker_index: int) -> void:
	site = plot
	index = worker_index
	position = site.staff_home(index)
	model = ModelLib.spawn("crew/filipina-server", self, Vector3.ZERO, 0, 0.66 / 1.65)
	tray = Node3D.new()
	add_child(tray)
	ModelLib.box(tray, Vector3(0.22, 0.016, 0.17), Vector3.ZERO, Color("b28a58"))
	tray.hide()
	_cloth = Node3D.new()
	add_child(_cloth)
	ModelLib.box(_cloth, Vector3(0.065, 0.008, 0.05), Vector3.ZERO, Color("ede0c9"))
	_cloth.hide()
	ModelLib.play_loop(model, "idle")

func available() -> bool:
	return state == State.IDLE and is_instance_valid(model)

func deliver(customer: Customer, item: String, done: Callable) -> void:
	_customer = customer
	_item = item
	_on_delivery = done
	_walk([site.staff_pickup()], _collect)

func _collect() -> void:
	ModelLib.play_once(site.server(), "interact-right")
	_work(State.COLLECT, "interact-right", 0.5, _carry_meal)

func _carry_meal() -> void:
	if not is_instance_valid(_customer) or _customer.seat.is_empty():
		_return_home()
		return
	_set_food(_item)
	tray.show()
	_table = int(_customer.seat["table"])
	_walk(site.staff_table_route(_table), _offer_meal)

func _offer_meal() -> void:
	_face(site.to_global(site.tables[_table]["pos"]))
	_work(State.DELIVER, "interact-right", 0.7, _place_meal)

func _place_meal() -> void:
	if is_instance_valid(_customer) and _customer.state == Customer.State.SEATED and _on_delivery.is_valid():
		if _on_delivery.call():
			var food := site.show_meal(_table, _item, int(_customer.seat["idx"]))
			if food:
				var target := food.position
				food.global_position = tray.global_position + Vector3.UP * 0.025
				food.create_tween().tween_property(food, "position", target, 0.28).set_trans(Tween.TRANS_SINE)
			site.service_stats["deliveries"] += 1
	tray.hide()
	_return_home()

func _clean(table: int) -> void:
	_table = table
	site.tables[table]["assigned"] = true
	_walk(site.staff_table_route(table), _wipe_table)

func _wipe_table() -> void:
	_face(site.to_global(site.tables[_table]["pos"]))
	_cloth.show()
	_work(State.CLEAN, "clean", site.clean_seconds, _clear_table)

func _clear_table() -> void:
	_cloth.hide()
	site.set_table_dirty(_table, false)
	site.service_stats["cleaned"] += 1
	_set_food("")
	tray.show()
	_tray_from = site.tables[_table]["node"].global_position
	_tray_transfer = 0.0
	create_tween().tween_property(self, "_tray_transfer", 1.0, 0.35)
	_work(State.COLLECT, "interact-right", 0.35, _return_home)

func _return_home() -> void:
	_customer = null
	_on_delivery = Callable()
	var aisle := Plot.AISLE_Z if position.z < Plot.AISLE_Z else Plot.FRONT_AISLE_Z
	_walk([Vector3(position.x, Plot.DECK_Y, aisle), Vector3(Plot.ENTRY_X, Plot.DECK_Y, aisle), site.staff_home(index)], _idle)

func _idle() -> void:
	tray.hide()
	_yaw = 0.0
	state = State.IDLE
	ModelLib.play_loop(model, "idle")

func _set_food(item: String) -> void:
	for node in tray.get_children():
		if node.name == "Dish":
			tray.remove_child(node)
			node.queue_free()
	var dish := Node3D.new()
	dish.name = "Dish"
	tray.add_child(dish)
	if item.is_empty():
		PlotBuilders.spawn("plate", dish, Vector3.UP * 0.012, 0, 0.23, false)
		PlotBuilders.spawn("cup", dish, Vector3(0.055, 0.018, 0.0), 0, 0.12, false)
	else:
		ModelLib.served_food(dish, item)

func _walk(points: Array[Vector3], done: Callable) -> void:
	_route.assign(points)
	_arrive = done
	state = State.WALK
	ModelLib.play_loop(model, "carry" if tray.visible else "walk", 1.1)

func _work(mode: State, clip: String, seconds: float, done: Callable) -> void:
	state = mode
	_work_left = seconds
	_after_work = done
	ModelLib.play_once(model, clip)

func _face(point: Vector3) -> void:
	var direction := point - global_position
	if direction.length_squared() > 0.0001:
		_yaw = atan2(direction.x, direction.z)

func _process(delta: float) -> void:
	if model == null:
		return
	model.rotation.y = rotate_toward(model.rotation.y, _yaw, delta * 8.0)
	if _cloth.visible:
		_cloth.global_position = ModelLib.hand_position(model) + Vector3.DOWN * 0.015
		_cloth.global_rotation = Vector3(0.0, model.global_rotation.y, 0.0)
	if tray.visible:
		var hands := ModelLib.hand_position(model).lerp(ModelLib.hand_position(model, "LeftHand"), 0.5) + Vector3.DOWN * 0.015
		tray.global_position = _tray_from.lerp(hands, smoothstep(0.0, 1.0, _tray_transfer))
		tray.global_rotation = Vector3(0.0, model.global_rotation.y, 0.0)
	if state == State.WALK:
		var target := _route[0]
		position = position.move_toward(target, delta * 0.88)
		_face(site.to_global(target))
		if position.distance_to(target) < 0.015:
			_route.pop_front()
			if _route.is_empty():
				var next := _arrive
				_arrive = Callable()
				next.call()
	elif _work_left > 0.0:
		_work_left = move_toward(_work_left, 0.0, delta)
		if _work_left == 0.0:
			var next := _after_work
			_after_work = Callable()
			next.call()
	elif state == State.IDLE and site.service_open:
		var dirty := site.unclaimed_dirty_table()
		if dirty >= 0:
			_clean(dirty)

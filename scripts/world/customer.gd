class_name Customer
extends Node3D
## A passer-by who may become a customer. Walks along the sidewalk, decides at the
## stand, queues, buys, maybe sits down to eat, reacts, leaves. Pure visuals + movement;
## DaySim decides.

signal reached_decision(customer: Customer)
signal arrived(customer: Customer)
signal gone(customer: Customer)

enum State { WALK, TO_SLOT, QUEUED, TO_SEAT, SEATED, REACT, LEAVE, DONE }

const WALK_SPEED := 0.8

var state: State = State.WALK
var dir: int = 1
var speed: float = WALK_SPEED
var decided := false
var decision_x := 0.0
var exit_x := 7.0
var target := Vector3.ZERO
var model: Node3D
var bubble: Label3D
var wants: String = "food"
var forced_stop := false
var on_promenade := false
var item: String = ""
var wait_min: float = 0.0
var slot: int = -1
var seat: Dictionary = {}
var _path: Array[Vector3] = []
var _bubble_tween: Tween
## Skip accelerates only customer movement; meshes and UI animate at normal speed.
var simulation_speed := 1.0
var order_shown := false
var beat_left := 0.0
var _yaw := 0.0
var _after_beat: Callable
var _bag: Node3D

func setup(female: bool, direction: int, start: Vector3, end_x: float, decide_x: float, with_visuals: bool = true) -> void:
	dir = direction
	position = start
	exit_x = end_x
	decision_x = decide_x
	speed = WALK_SPEED * randf_range(0.85, 1.2)
	# A virtual customer still walks, queues, eats and pays through the same rules,
	# without allocating a mesh, skeleton, material, speech label or GPU shader.
	if not with_visuals:
		return
	model = ModelLib.spawn_guest(female, self)
	if model:
		ModelLib.play_loop(model, "walk", speed / WALK_SPEED * 1.6)
	_face_direction()
	if model:
		model.rotation.y = _yaw
	bubble = Label3D.new()
	bubble.font = UiTheme.font()
	bubble.font_size = 44
	bubble.pixel_size = 0.0028
	bubble.outline_size = 12
	bubble.outline_modulate = Color(0.22, 0.1, 0.04, 0.95)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.position = Vector3(0, 0.66, 0)
	bubble.visible = false
	add_child(bubble)

func _face_direction() -> void:
	_yaw = deg_to_rad(90 if dir > 0 else -90)

func face_point(point: Vector3) -> void:
	var d := point - global_position
	if absf(d.x) + absf(d.z) > 0.01:
		_yaw = atan2(d.x, d.z)

func _walk_towards(pos: Vector3) -> void:
	if model:
		ModelLib.play_loop(model, "walk", 1.6)
		face_point(pos)

func go_to_slot(index: int, pos: Vector3) -> void:
	slot = index
	target = pos
	_path.clear()
	if on_promenade and index < 100 and position.z >= SouqScenery.ARRIVAL_Z - 0.1:
		# Walk alongside the line first, then turn into the assigned spot.
		if absf(pos.x - position.x) > 0.25:
			target = Vector3(pos.x, 0.0, SouqScenery.ARRIVAL_Z)
			_path.append(pos)
	state = State.TO_SLOT
	_walk_towards(target)

## Walk to a seat ({idx, table, pos, facing, approach, y_off}) and sit down there.
func go_to_seat(s: Dictionary) -> void:
	seat = s
	_path = [s["pos"]]
	target = s.get("approach", s["pos"])
	state = State.TO_SEAT
	_walk_towards(target)

func _sit_down() -> void:
	state = State.SEATED
	position = seat["pos"]
	if model:
		_yaw = float(seat.get("facing", PI))
		model.position.y = float(seat.get("y_off", 0.0))
		ModelLib.play_loop(model, "sit")
	arrived.emit(self)

## Stand up from the table and walk off along the sidewalk.
func leave_from_seat(text: String = "", color: Color = Color.WHITE) -> void:
	if text != "":
		say(text, color)
	if model:
		model.position.y = 0.0
	var approach: Vector3 = seat.get("approach", position) if not seat.is_empty() else position
	seat = {}
	var lane := SouqScenery.PROMENADE_Z if on_promenade else World.WALK_Z
	_path = [Vector3(approach.x, 0, lane)]
	target = approach
	state = State.TO_SEAT
	_leaving_after_path = true
	_walk_towards(target)

var _leaving_after_path := false

func leave(text: String = "", color: Color = Color.WHITE, hold: bool = false) -> void:
	if text != "":
		say(text, color)
	if hold:
		perform("idle", "idle", 0.4, _start_leaving)
		return
	_start_leaving()

## Hold the pose at the counter before moving on to the next part of the visit.
func perform(clip: String, fallback: String, seconds: float, then: Callable = Callable()) -> void:
	if simulation_speed > 1.0:
		if then.is_valid():
			then.call()
		return
	if model:
		var player := ModelLib.animation_player(model)
		var anim := clip if player and player.has_animation(clip) else fallback
		ModelLib.play_once(model, anim)
	beat_left = seconds
	if then.is_valid():
		state = State.REACT
		_after_beat = then

func reject(point: Vector3, reason: String, text: String, color: Color) -> void:
	# Look across at the line, then pivot away. The side angle keeps hands readable.
	face_point(Vector3(point.x, position.y, position.z + 0.24))
	dir = -dir
	exit_x = -exit_x
	say(text, color)
	perform(reason, "emote-no", 1.18, _start_leaving)

func take_bag(bag: Node3D) -> void:
	_bag = bag
	bag.reparent(self)
	bag.global_position = ModelLib.hand_position(model) + Vector3.DOWN * 0.062

func _start_leaving() -> void:
	if state == State.DONE:
		return
	var lane_z := World.WALK_Z + 0.20
	var step_to_lane := position.z < World.WALK_Z - 0.1
	if on_promenade:
		if slot >= 100:
			# Pickup is on the left. Exit past the vendor rather than across the line.
			dir = -1
			exit_x = -World.WALK_EDGE
		lane_z = SouqScenery.PROMENADE_Z if slot >= 0 else SouqScenery.ARRIVAL_Z
		step_to_lane = absf(position.z - lane_z) > 0.12
	if step_to_lane:
		target = Vector3(position.x, 0, lane_z)
		_path.clear()
		_leaving_after_path = true
		state = State.TO_SEAT
		_walk_towards(target)
		return
	state = State.LEAVE
	target = Vector3(exit_x, 0, position.z)
	if model:
		ModelLib.play_loop(model, "walk", 1.6)
	_face_direction()

func say(text: String, color: Color = Color.WHITE, duration: float = 1.0) -> void:
	if bubble == null or simulation_speed > 1.0:
		return
	bubble.text = text
	bubble.modulate = Color(color.r, color.g, color.b, 1.0)
	bubble.visible = true
	bubble.scale = Vector3.ONE * 0.6
	if _bubble_tween:
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_property(bubble, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_interval(duration)
	_bubble_tween.tween_property(bubble, "modulate:a", 0.0, 0.4)
	_bubble_tween.tween_callback(func(): bubble.visible = false)

func react(anim: String) -> void:
	if model and simulation_speed == 1.0 and state != State.SEATED:
		ModelLib.play_once(model, anim, "idle")

func _process(delta: float) -> void:
	delta *= simulation_speed
	if model:
		model.rotation.y = rotate_toward(model.rotation.y, _yaw, 10.0 * delta)
		if is_instance_valid(_bag):
			_bag.global_position = ModelLib.hand_position(model) + Vector3.DOWN * 0.062
	if beat_left > 0.0:
		beat_left = 0.0 if simulation_speed > 1.0 else move_toward(beat_left, 0.0, delta)
		if beat_left == 0.0 and _after_beat.is_valid():
			var next := _after_beat
			_after_beat = Callable()
			next.call()
		return
	match state:
		State.WALK:
			position.x += dir * speed * delta
			if not decided and (position.x - decision_x) * dir >= 0.0:
				decided = true
				reached_decision.emit(self)
			if (position.x - exit_x) * dir >= 0.0:
				_finish()
		State.TO_SLOT:
			var d := target - position
			d.y = 0
			if d.length() < 0.03:
				position = target
				if not _path.is_empty():
					target = _path.pop_front()
					_walk_towards(target)
					return
				state = State.QUEUED
				face_point(World.CART_POS)
				if model:
					ModelLib.play_loop(model, "idle")
				arrived.emit(self)
			else:
				position += d.normalized() * minf(speed * 1.1 * delta, d.length())
		State.TO_SEAT:
			var d := target - position
			d.y = 0
			if d.length() < 0.03:
				position = target
				if not _path.is_empty():
					target = _path.pop_front()
					_walk_towards(target)
				elif _leaving_after_path:
					_leaving_after_path = false
					_start_leaving()
				else:
					_sit_down()
			else:
				position += d.normalized() * minf(speed * 1.1 * delta, d.length())
		State.LEAVE:
			position.x += dir * speed * delta
			if (position.x - exit_x) * dir >= 0.0:
				_finish()
		_:
			pass

func _finish() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	gone.emit(self)
	queue_free()

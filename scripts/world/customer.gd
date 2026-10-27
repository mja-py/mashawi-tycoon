class_name Customer
extends Node3D
## A passer-by who may become a customer. Walks along the sidewalk, decides at the
## cart, queues, buys, reacts, leaves. Pure visuals + movement; DaySim decides.

signal reached_decision(customer: Customer)
signal arrived(customer: Customer)
signal gone(customer: Customer)

enum State { WALK, TO_SLOT, QUEUED, LEAVE, DONE }

const SCALE := 0.62
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
var item: String = ""
var wait_min: float = 0.0
var slot: int = -1
var _bubble_tween: Tween

func setup(model_name: String, direction: int, start: Vector3, end_x: float, decide_x: float) -> void:
	dir = direction
	position = start
	exit_x = end_x
	decision_x = decide_x
	speed = WALK_SPEED * randf_range(0.85, 1.2)
	model = ModelLib.spawn(model_name, self, Vector3.ZERO, 0, SCALE)
	if model:
		ModelLib.play_loop(model, "walk", speed / WALK_SPEED * 1.6)
	_face_direction()
	bubble = Label3D.new()
	bubble.font = UiTheme.font()
	bubble.font_size = 44
	bubble.pixel_size = 0.0045
	bubble.outline_size = 16
	bubble.outline_modulate = Color(0.22, 0.1, 0.04, 0.95)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.position = Vector3(0, 0.72, 0)
	bubble.visible = false
	add_child(bubble)

func _face_direction() -> void:
	if model:
		model.rotation.y = deg_to_rad(90 if dir > 0 else -90)

func face_cart() -> void:
	if model:
		model.rotation.y = PI

func go_to_slot(index: int, pos: Vector3) -> void:
	slot = index
	target = pos
	state = State.TO_SLOT
	if model:
		ModelLib.play_loop(model, "walk", 1.6)
		var d := pos - position
		model.rotation.y = atan2(d.x, d.z)

func leave(text: String = "", color: Color = Color.WHITE, hold: bool = false) -> void:
	if text != "":
		say(text, color)
	if hold:
		if model:
			ModelLib.play_loop(model, "idle")
		await get_tree().create_timer(0.55).timeout
	state = State.LEAVE
	target = Vector3(exit_x, 0, position.z)
	if model:
		ModelLib.play_loop(model, "walk", 1.6)
	_face_direction()

func say(text: String, color: Color = Color.WHITE) -> void:
	bubble.text = text
	bubble.modulate = Color(color.r, color.g, color.b, 1.0)
	bubble.visible = true
	bubble.scale = Vector3.ONE * 0.6
	if _bubble_tween:
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_property(bubble, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_interval(1.5)
	_bubble_tween.tween_property(bubble, "modulate:a", 0.0, 0.4)
	_bubble_tween.tween_callback(func(): bubble.visible = false)

func react(anim: String) -> void:
	if model:
		ModelLib.play_once(model, anim, "idle")

func _process(delta: float) -> void:
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
				state = State.QUEUED
				face_cart()
				if model:
					ModelLib.play_loop(model, "idle")
				arrived.emit(self)
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

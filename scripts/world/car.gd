class_name Car
extends Node3D
## Background traffic. Drives along X and frees itself off-screen. A car pulls away and
## brakes with a real rate, keeps its distance from the one ahead instead of driving
## through it, turns its wheels with the road speed and settles on its springs.
## Ambient only: its own randomness, never the business RNG.

const SCALE := 0.21
const ACCEL := 0.9        # units/s^2 pulling away
const BRAKE := 2.4        # units/s^2 braking
const GAP := 0.42         # clear road kept behind the car ahead
const WHEEL_RADIUS := 0.3 * SCALE
const PITCH := 0.022      # radians of nose dive / squat per unit of acceleration

var dir: int = 1
## Road speed right now, and the speed this driver likes to cruise at.
var speed: float = 1.3
var cruise: float = 1.3
var exit_x: float = 8.0
var length := 0.6
var _wheels: Array[Node3D] = []
var _pitch := 0.0

func setup(model_name: String, direction: int, start: Vector3, end_x: float) -> void:
	dir = direction
	position = start
	exit_x = end_x
	cruise = randf_range(1.0, 1.6)
	speed = cruise
	var model := ModelLib.spawn(model_name, self, Vector3.ZERO, 90 if dir > 0 else -90, SCALE)
	if model == null:
		return
	for part in model.find_children("wheel*", "Node3D", true, false):
		_wheels.append(part as Node3D)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		length = maxf(length, (mi.transform * mi.get_aabb()).size.z * SCALE)

## The nearest car ahead in this lane, or null.
func _leader() -> Car:
	var best: Car = null
	var best_d := INF
	for other in get_parent().get_children():
		if other == self or not (other is Car):
			continue
		var car := other as Car
		if car.dir != dir or car.is_queued_for_deletion():
			continue
		var d := (car.position.x - position.x) * dir
		if d > 0.0 and d < best_d:
			best_d = d
			best = car
	return best

func _process(delta: float) -> void:
	var limit := cruise
	var ahead := _leader()
	if ahead:
		# room left before the kept gap; the speed from which the brakes still stop in it
		var room := (ahead.position.x - position.x) * dir - (length + ahead.length) * 0.5 - GAP
		limit = minf(cruise, ahead.speed + sqrt(maxf(0.0, 2.0 * BRAKE * 0.7 * room)))
	var before := speed
	speed = move_toward(speed, limit, (BRAKE if limit < speed else ACCEL) * delta)
	position.x += dir * speed * delta
	# wheels roll with the road, the body dips under braking and squats pulling away
	var roll := speed * delta / WHEEL_RADIUS
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.RIGHT, roll)
	var accel := (speed - before) / maxf(delta, 0.0001)
	_pitch = lerpf(_pitch, clampf(accel, -BRAKE, ACCEL) * PITCH, minf(1.0, delta * 6.0))
	rotation.z = dir * _pitch
	if (position.x - exit_x) * dir >= 0.0:
		queue_free()

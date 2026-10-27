class_name Car
extends Node3D
## Background traffic. Drives along X and frees itself off-screen.

var dir: int = 1
var speed: float = 1.3
var exit_x: float = 8.0

func setup(model_name: String, direction: int, start: Vector3, end_x: float) -> void:
	dir = direction
	position = start
	exit_x = end_x
	speed = randf_range(1.0, 1.6)
	ModelLib.spawn(model_name, self, Vector3.ZERO, 90 if dir > 0 else -90, 0.21)

func _process(delta: float) -> void:
	position.x += dir * speed * delta
	if (position.x - exit_x) * dir >= 0.0:
		queue_free()

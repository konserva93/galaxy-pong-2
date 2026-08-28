extends Area3D

## Мяч: баллистическое движение (парабола) — гравитация действует на vy,
## позиция обновляется по velocity * delta. Отбивание, гол/аут — в задачах 1.4/1.6.

@export var ball_gravity: float = -20.0

var velocity: Vector3 = Vector3.ZERO


func _physics_process(delta: float) -> void:
	velocity.y += ball_gravity * delta
	position += velocity * delta


func launch(new_velocity: Vector3) -> void:
	velocity = new_velocity

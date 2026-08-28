extends Node3D

## Главная сцена: собирает поле, вёсла, мяч и камеру.
## Игровой цикл (счёт, состояния, сигналы) добавляется в задачах 1.6/1.7.

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.look_at(Vector3.ZERO, Vector3.UP)

extends Node3D

## Главная сцена: собирает поле, вёсла, мяч и камеру.
## Игровой цикл (счёт, состояния, сигналы) добавляется в задачах 1.6/1.7.

const BALL_LAUNCH_VY: float = 8.0

@onready var _camera: Camera3D = $Camera3D
@onready var _ball: Area3D = $Ball


func _ready() -> void:
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	# Временный тестовый запуск баллистики мяча для задачи 1.3.
	# Будет заменён подачей от GameManager в задаче 1.7.
	_ball.launch(Vector3(0.0, BALL_LAUNCH_VY, -6.0))

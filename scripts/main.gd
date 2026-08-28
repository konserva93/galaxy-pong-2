extends Node3D

## Главная сцена: собирает поле, вёсла, мяч и камеру.
## Игровой цикл (счёт, состояния, сигналы) добавляется в задачах 1.6/1.7.

const BALL_LAUNCH_VY: float = 8.0
const BALL_LAUNCH_VELOCITY: Vector3 = Vector3(0.0, BALL_LAUNCH_VY, 5.0)

@onready var _camera: Camera3D = $Camera3D
@onready var _ball: Area3D = $Ball

var _ball_start_position: Vector3


func _ready() -> void:
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_ball_start_position = _ball.position
	_ball.point_scored.connect(GameManager.register_point)
	# Временный тестовый запуск мяча в сторону игрока для задач 1.3/1.4.
	# Будет заменён подачей от GameManager в задаче 1.7.
	_ball.launch(BALL_LAUNCH_VELOCITY)


func _physics_process(_delta: float) -> void:
	# Временный авто-возврат мяча для удобства ручного теста удара (задача 1.4),
	# чтобы не перезапускать сцену каждый промах. Настоящее правило гола/аута —
	# в задаче 1.6, настоящая подача — в 1.7; это заменит текущий костыль.
	if _ball.position.y < 0.0:
		_ball.position = _ball_start_position
		_ball.launch(BALL_LAUNCH_VELOCITY)

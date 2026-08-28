extends Node3D

## Главная сцена: собирает поле, вёсла, мяч и камеру; сама не хранит
## игровую логику — счёт, подачу и завершение игры ведёт GameManager
## (autoload, см. game_manager.gd).

@onready var _camera: Camera3D = $Camera3D
@onready var _ball: Area3D = $Ball
@onready var _player_paddle: Area3D = $PlayerPaddle
@onready var _ai_paddle: Area3D = $AIPaddle


func _ready() -> void:
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_ball.point_scored.connect(GameManager.register_point)
	GameManager.restart_requested.connect(_on_restart_requested)
	GameManager.register_ball(_ball, _ball.position)
	GameManager.start_first_serve()


func _on_restart_requested() -> void:
	_player_paddle.reset_position()
	_ai_paddle.reset_position()

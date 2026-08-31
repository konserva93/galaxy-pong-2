extends Node3D

## Главная сцена: собирает поле, вёсла, мяч и камеру; сама не хранит
## игровую логику — счёт, подачу и завершение игры ведёт GameManager
## (autoload, см. game_manager.gd).

@onready var _camera: Camera3D = $Camera3D
@onready var _ball: Area3D = $Ball
@onready var _player_paddle: Area3D = $PlayerPaddle
@onready var _ai_paddle: Area3D = $AIPaddle
@onready var _paddle_hit_sound: AudioStreamPlayer = $Audio/PaddleHitSound
@onready var _goal_sound: AudioStreamPlayer = $Audio/GoalSound
@onready var _ambient_music: AudioStreamPlayer = $Audio/AmbientMusic


func _ready() -> void:
	# Шину надёжнее назначать в коде, а не полагаться на bus="SFX"/"Music" в
	# самой .tscn: в экспортированном билде (не в редакторе) статическое
	# значение из сцены резолвится в "Master" -- похоже на гонку, где узел
	# получает бас до того, как audio/default_bus_layout.tres (project.godot)
	# точно догружен. Settings (autoload) -- предыдущий по порядку, к этому
	# моменту шины уже точно существуют.
	_paddle_hit_sound.bus = "SFX"
	_goal_sound.bus = "SFX"
	_ambient_music.bus = "Music"

	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_ball.point_scored.connect(GameManager.register_point)
	_ball.point_scored.connect(_on_point_scored)
	_ball.paddle_hit.connect(_on_paddle_hit)
	Settings.sfx_previewed.connect(_on_paddle_hit)
	GameManager.restart_requested.connect(_on_restart_requested)
	GameManager.register_ball(_ball, _ball.position)
	GameManager.start_first_serve()

	# Зацикливание, выставленное в .wav.import через headless CLI (без реального
	# импорт-дока редактора), не долетало до итогового ресурса при загрузке
	# (см. задача 5.1) — надёжно сработала только установка loop_mode в коде.
	# ВАЖНО: делать это ДО play(), а не полагаться на autoplay сцены — дочерние
	# узлы получают _ready() раньше родителя, так что autoplay успел бы запустить
	# проигрывание со старым (незацикленным) loop_mode ресурса ДО этой строки;
	# смена loop_mode уже начавшегося проигрывания на него не влияет — ambient
	# доигрывал первые 8 секунд и молчал до конца партии, это и было замечено.
	var ambient_stream: AudioStreamWAV = _ambient_music.stream
	if ambient_stream != null:
		ambient_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# loop_end по умолчанию 0 (пустой диапазон зацикливания -- луп молчал бы
		# сразу, а не проигрывал весь клип) -- явно указываем конец в сэмплах.
		ambient_stream.loop_begin = 0
		ambient_stream.loop_end = int(ambient_stream.get_length() * ambient_stream.mix_rate)
	_ambient_music.play()


func _on_restart_requested() -> void:
	_player_paddle.reset_position()
	_ai_paddle.reset_position()


func _on_paddle_hit() -> void:
	_paddle_hit_sound.play()


func _on_point_scored(_winner: String) -> void:
	_goal_sound.play()

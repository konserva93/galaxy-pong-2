extends Node

## Autoload: игровое состояние, счёт, сигналы игрового цикла.
##
## Мяч регистрируется через register_ball() (см. main.gd) — GameManager сам
## не хранит сцену, только берёт нужные ссылки/стартовую позицию оттуда.
## После каждого очка (сигнал ball.point_scored → register_point): счёт
## обновляется, при достижении SCORE_TO_WIN — game_over и подачи
## останавливаются; иначе — пауза GOAL_PAUSE_SECONDS и автоподача в сторону
## принимающего (того, кто пропустил предыдущее очко — GameDesign 3.4).

signal score_changed(player_score: int, ai_score: int)
signal game_over(winner: String)
signal state_changed(new_state: String)

const SCORE_TO_WIN: int = 7

@export var goal_pause_seconds: float = 1.0
@export var serve_launch_vy: float = 8.0
@export var serve_horizontal_speed: float = 5.0

var player_score: int = 0
var ai_score: int = 0
var is_game_over: bool = false

var _ball: Area3D
var _ball_start_position: Vector3


func register_ball(ball: Area3D, start_position: Vector3) -> void:
	_ball = ball
	_ball_start_position = start_position


## Первая подача за партию — без предшествующего гола, без паузы. Направление
## по умолчанию — в сторону игрока; в дизайн-документе не оговорено явно
## (только подача "после гола" описана точно), это делегированное умолчание.
func start_first_serve() -> void:
	_serve_toward("player")


func register_point(winner: String) -> void:
	if is_game_over:
		return

	if winner == "player":
		player_score += 1
	else:
		ai_score += 1
	score_changed.emit(player_score, ai_score)

	if player_score >= SCORE_TO_WIN or ai_score >= SCORE_TO_WIN:
		is_game_over = true
		var overall_winner := "player" if player_score >= SCORE_TO_WIN else "ai"
		# Экрана победы/поражения ещё нет (задача 4.3) — без этого сообщения
		# игра просто молча перестаёт подавать мяч, что на плейтесте выглядит
		# как "мяч потерялся" без объяснения причины.
		print("GAME OVER — победил: %s (счёт %d:%d). Экран окончания игры — задача 4.3; чтобы сыграть снова, перезапустите сцену." % [overall_winner, player_score, ai_score])
		game_over.emit(overall_winner)
		return

	var receiver := "ai" if winner == "player" else "player"
	# process_in_physics=true: пауза отсчитывается по физическим тикам, а не
	# по idle-времени — держит её на той же временной шкале, что и всю
	# остальную игровую логику (и что предсказуемо для headless-тестов).
	await _ball.get_tree().create_timer(goal_pause_seconds, true, true).timeout
	_serve_toward(receiver)


func _serve_toward(receiver: String) -> void:
	if _ball == null:
		return

	_ball.position = _ball_start_position
	var z_direction := 1.0 if receiver == "player" else -1.0
	_ball.launch(Vector3(0.0, serve_launch_vy, serve_horizontal_speed * z_direction))

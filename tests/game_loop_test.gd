extends SceneTree

## Регрессия для GameManager.gd + main.gd (задача 1.7) и двух фиксов, найденных
## на плейтесте сразу после неё:
## - при старте сцены сразу происходит первая подача (без паузы);
## - point_scored увеличивает счёт и эмитит score_changed;
## - после гола — пауза goal_pause_seconds, затем автоподача в сторону
##   принимающего (того, кто ПРОПУСТИЛ предыдущее очко — GameDesign 3.4);
## - мяч замирает и скрывается сразу в момент гола (а не продолжает падать/
##   лететь на виду всю паузу — было "мяч долго падает после гола");
## - розыгрыш без единого удара, ушедший в аут, всё равно доходит до подачи
##   (было "иногда не возвращается" — см. ball.gd _check_out_of_bounds);
## - по достижении SCORE_TO_WIN — game_over и подачи прекращаются.
##
## Важно: точки начисляются через ball._score_point(winner), а не через
## point_scored.emit(...) напрямую — emit() не замораживает мяч, и он
## продолжал бы реально жить своей физикой в фоне между проверками, что на
## практике уже приводило к гонке параллельных таймеров паузы в GameManager
## и ложным провалам последующих секций.
##
## Запуск: см. reference-godot-cli в памяти проекта.

var _ok := true
var _score_changed_events: Array = []
var _game_over_winner: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _on_score_changed(player_score: int, ai_score: int) -> void:
	_score_changed_events.append([player_score, ai_score])


func _on_game_over(winner: String) -> void:
	_game_over_winner = winner


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)

	var game_manager: Node = root.get_node("GameManager")
	var ball: Area3D = main.get_node("Ball")
	game_manager.score_changed.connect(_on_score_changed)
	game_manager.game_over.connect(_on_game_over)

	await physics_frame
	print("--- initial serve ---")
	print("ball.velocity=%s (expect nonzero, launched immediately, no pause)" % ball.velocity)
	_ok = _ok and ball.velocity.length() > 0.0

	await _check_point_and_reserve(game_manager, ball)
	await _check_ball_freezes_and_hides_during_pause(game_manager, ball)
	await _check_unhit_out_of_bounds_still_recovers(game_manager, ball)
	await _check_game_over_stops_serving(game_manager, ball)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_point_and_reserve(game_manager: Node, ball: Area3D) -> void:
	print("--- point scored -> score_changed, pause, then serve toward receiver ---")

	_score_changed_events.clear()
	var start_pos: Vector3 = ball.position
	# AI получает очко (игрок "пропустил") -> принимающий следующей подачи — игрок (Z>0).
	ball._score_point("ai")
	await physics_frame

	print("score after point: player=%d ai=%d, events=%s" % [game_manager.player_score, game_manager.ai_score, _score_changed_events])
	_ok = _ok and game_manager.ai_score == 1
	_ok = _ok and _score_changed_events == [[0, 1]]

	# Во время паузы мяч не должен телепортироваться обратно в центр раньше времени.
	await physics_frame
	print("mid-pause ball.position=%s (should not yet equal start %s)" % [ball.position, start_pos])

	# Ждём чуть дольше объявленной паузы (goal_pause_seconds по умолчанию 1с).
	var frames_to_wait: int = int((game_manager.goal_pause_seconds + 0.5) * 60.0)
	for i in range(frames_to_wait):
		await physics_frame

	print("after pause: ball.position=%s ball.velocity=%s (expect vz>0, served toward player)" % [ball.position, ball.velocity])
	_ok = _ok and ball.velocity.z > 0.0


func _check_ball_freezes_and_hides_during_pause(game_manager: Node, ball: Area3D) -> void:
	print("--- ball freezes in place and hides during the goal pause (not visibly falling) ---")

	ball.launch(Vector3(0.0, 8.0, -3.0))
	await physics_frame
	ball._score_point("player")
	await physics_frame

	print("right after point: visible=%s" % ball.visible)
	_ok = _ok and ball.visible == false

	var frozen_pos: Vector3 = ball.position
	var frozen_vel: Vector3 = ball.velocity
	for i in range(20): # намного меньше, чем goal_pause_seconds*60 -- ещё внутри паузы
		await physics_frame
	print("20 frames into the pause: position=%s (expect unchanged %s), velocity=%s (expect unchanged %s)" % [ball.position, frozen_pos, ball.velocity, frozen_vel])
	_ok = _ok and ball.position.is_equal_approx(frozen_pos)
	_ok = _ok and ball.velocity.is_equal_approx(frozen_vel)

	var frames_remaining: int = int(game_manager.goal_pause_seconds * 60.0) - 20 + 10
	for i in range(frames_remaining):
		await physics_frame
	print("after full pause: visible=%s velocity=%s (expect visible again, moving)" % [ball.visible, ball.velocity])
	_ok = _ok and ball.visible == true
	_ok = _ok and not ball.velocity.is_equal_approx(frozen_vel)


func _check_unhit_out_of_bounds_still_recovers(game_manager: Node, ball: Area3D) -> void:
	print("--- a serve that goes out untouched still completes a full score+serve cycle (regression: used to fly away forever) ---")

	ball.launch(Vector3(30.0, 0.0, 0.0)) # быстро уйдёт за пределы поля по X, никто не отбивал
	var events_before: int = game_manager.ai_score + game_manager.player_score
	var frames: int = 0
	var max_frames: int = 300 # 5 секунд с запасом -- если завис, тест сам не зависнет
	while (game_manager.ai_score + game_manager.player_score) == events_before and frames < max_frames:
		await physics_frame
		frames += 1
	print("scored after %d frames (max %d)" % [frames, max_frames])
	_ok = _ok and frames < max_frames

	# Дожидаемся окончания паузы и новой подачи -- мяч должен снова стать видимым и полететь.
	var frames_to_wait: int = int((game_manager.goal_pause_seconds + 0.5) * 60.0)
	for i in range(frames_to_wait):
		await physics_frame
	print("after recovery: visible=%s velocity=%s (expect visible, moving again)" % [ball.visible, ball.velocity])
	_ok = _ok and ball.visible == true
	_ok = _ok and ball.velocity.length() > 0.0


func _check_game_over_stops_serving(game_manager: Node, ball: Area3D) -> void:
	print("--- reaching SCORE_TO_WIN triggers game_over and stops further serves ---")

	# Форсируем счёт почти до победы, чтобы не ждать реальные 7 очков.
	game_manager.player_score = game_manager.SCORE_TO_WIN - 1
	game_manager.ai_score = 0
	_game_over_winner = ""

	ball._score_point("player")
	await physics_frame

	print("player_score=%d game_over_winner=%s" % [game_manager.player_score, _game_over_winner])
	_ok = _ok and game_manager.player_score == game_manager.SCORE_TO_WIN
	_ok = _ok and _game_over_winner == "player"
	_ok = _ok and game_manager.is_game_over

	# После game_over повторный point_scored не должен ничего менять.
	var score_before := [game_manager.player_score, game_manager.ai_score]
	ball.point_scored.emit("ai")
	await physics_frame
	print("after game_over, extra point ignored: score=%s (expect unchanged %s)" % [[game_manager.player_score, game_manager.ai_score], score_before])
	_ok = _ok and [game_manager.player_score, game_manager.ai_score] == score_before

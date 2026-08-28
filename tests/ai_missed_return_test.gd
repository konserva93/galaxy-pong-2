extends SceneTree

## Регрессия для paddle_ai.gd::_check_missed_return (отладочный вывод "AI
## missed a return", добавлен по запросу вместе с d21-прицеливанием):
## - когда мяч летит к AI (velocity.z < 0), AI активно реагирует
##   (_was_reacting), но реального удара не происходит (весло физически не
##   успело/промахнулось) -- срабатывание фиксируется ровно один раз, когда
##   мяч пересекает paddle_hit_height сверху вниз;
## - когда AI реально ловит мяч (весло рядом с точкой приземления) --
##   срабатывания НЕ происходит;
## - когда мяч падает (пересекает paddle_hit_height), но летит НЕ к AI
##   (velocity.z >= 0 -- значит, это не "мяч AI", AI и не должен был его
##   ловить) -- срабатывания не происходит.
##
## Запуск: см. reference-godot-cli в памяти проекта.

var _ok := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var ai: Area3D = main.get_node("AIPaddle")
	var ball: Area3D = main.get_node("Ball")
	var game_manager: Node = root.get_node("GameManager")
	# Тест сам ставит мяч в нужные сценарии напрямую -- отключаем реальный
	# GameManager, чтобы его собственная логика гола/паузы/подачи не мешала
	# (см. тот же приём и его обоснование в ai_paddle_test.gd).
	if ball.point_scored.is_connected(game_manager.register_point):
		ball.point_scored.disconnect(game_manager.register_point)

	await _check_real_miss_is_detected(ai, ball)
	await _check_real_catch_is_not_flagged(ai, ball)
	await _check_no_reaction_no_flag(ai, ball)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_real_miss_is_detected(ai: Area3D, ball: Area3D) -> void:
	print("--- AI reacting but paddle far from landing spot -> flagged exactly once ---")

	ball.position = Vector3(0.0, 3.0, -2.0)
	ball.launch(Vector3(0.0, 0.0, -5.0)) # launch(), не просто velocity= -- сбрасывает _point_scored_this_rally/visible от предыдущего сценария
	ai.position = Vector3(3.4, 1.0, -6.0) # далеко от места приземления, вне досягаемости на этой скорости
	ai._previous_position = ai.position
	ai._was_reacting = true
	ai._current_error = Vector2.ZERO
	ai._prev_ball_y = ball.position.y
	ai._missed_return_count = 0

	for i in range(90):
		await physics_frame

	print("missed_return_count=%d (expect exactly 1)" % ai._missed_return_count)
	_ok = _ok and ai._missed_return_count == 1


func _check_real_catch_is_not_flagged(ai: Area3D, ball: Area3D) -> void:
	print("--- AI reacting and actually positioned at the landing spot -> not flagged ---")

	ball.position = Vector3(0.0, 3.0, -2.0)
	ball.launch(Vector3(0.0, 0.0, -5.0)) # сбрасывает состояние розыгрыша от предыдущего сценария (см. первую проверку)
	var landing: Vector2 = ai._predict_ball_landing() # учитывает снос по Z за время падения
	ai.position = Vector3(landing.x, 1.0, landing.y) # уже на месте приземления
	ai._previous_position = ai.position
	ai._was_reacting = true
	ai._current_error = Vector2.ZERO
	ai._prev_ball_y = ball.position.y
	ai._missed_return_count = 0

	for i in range(90):
		await physics_frame

	print("missed_return_count=%d (expect 0), ball.velocity.z=%.2f (expect > 0 -- was actually hit)" % [ai._missed_return_count, ball.velocity.z])
	_ok = _ok and ai._missed_return_count == 0
	_ok = _ok and ball.velocity.z > 0.0


func _check_no_reaction_no_flag(ai: Area3D, ball: Area3D) -> void:
	print("--- ball falls and crosses hit height, but flies AWAY from AI -> not 'AI's ball', not flagged ---")

	ball.position = Vector3(0.0, 3.0, -2.0)
	ball.launch(Vector3(0.0, 0.0, 5.0)) # к игроку, не к AI -- AI не должен реагировать вовсе; launch() сбрасывает состояние от предыдущего сценария
	ai.position = Vector3(3.4, 1.0, -6.0)
	ai._previous_position = ai.position
	ai._was_reacting = false
	ai._current_error = Vector2.ZERO
	ai._prev_ball_y = ball.position.y
	ai._missed_return_count = 0

	for i in range(90):
		await physics_frame

	print("missed_return_count=%d (expect 0 -- ball wasn't heading toward AI, so it's not 'AI's ball')" % ai._missed_return_count)
	_ok = _ok and ai._missed_return_count == 0

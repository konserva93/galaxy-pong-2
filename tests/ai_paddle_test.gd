extends SceneTree

## Регрессия для paddle_ai.gd:
## - прогноз времени пересечения мячом paddle_hit_height (аналитическое
##   решение параболы) против известной кинематики;
## - весло преследует прогнозируемую точку, когда мяч летит к нему;
## - весло возвращается к центру своей половины (idle), когда мяч летит от
##   него;
## - границы половины AI строго отрицательны по Z (регрессия бага, когда
##   формула визуальной коррекции у центральной линии для стороны AI давала
##   положительный z_max — см. project memory).
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

	# Этот тест напрямую подставляет ball.position/velocity, чтобы проверить
	# именно логику преследования/idle-возврата весла AI в изоляции. Если не
	# отключить связь со счётом, реальный GameManager может (и будет: мяч,
	# запущенный с vy=0 из y=10, по факту касается пола ещё ВНУТРИ первого
	# 60-кадрового цикла из-за полу-неявного Эйлера) зафиксировать гол и сам
	# запустить новую подачу в сторону AI прямо посреди фазы "мяч улетает от
	# AI" -- это сбивало весло с idle-возврата и делало тест флейки.
	if ball.point_scored.is_connected(game_manager.register_point):
		ball.point_scored.disconnect(game_manager.register_point)

	_check_landing_time_prediction(ai)
	await _check_tracking_and_idle_return(ai, ball)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_landing_time_prediction(ai: Area3D) -> void:
	print("--- landing-time prediction vs. known kinematics ---")

	# y0=3, vy=0 (апекс), g=-20, цель=1 -> падение на 2 юнита: t=sqrt(2*2/20)=0.44721
	var t: float = ai._time_to_reach_height(3.0, 0.0, -20.0, 1.0)
	print("t(y0=3,vy=0,g=-20,target=1)=%.5f (expect ~0.44721)" % t)
	_ok = _ok and absf(t - 0.44721) < 0.001

	# Мяч уже на нужной высоте и падает -- пересечение "сейчас", t=0.
	var t2: float = ai._time_to_reach_height(1.0, -5.0, -20.0, 1.0)
	print("t(already at height, falling)=%.5f (expect 0.0)" % t2)
	_ok = _ok and absf(t2 - 0.0) < 0.001

	# Дискриминант < 0 -- решения нет (мяч никогда не достигнет этой высоты).
	var t3: float = ai._time_to_reach_height(-5.0, 0.0, -20.0, 1.0)
	print("t(never reaches, discriminant<0)=%.5f (expect -1.0)" % t3)
	_ok = _ok and t3 == -1.0


func _check_tracking_and_idle_return(ai: Area3D, ball: Area3D) -> void:
	print("--- tracking approaching ball / idle return when ball moves away ---")

	print("AI half bounds: x=[%.3f,%.3f] z=[%.3f,%.3f]" % [ai._bounds.x_min, ai._bounds.x_max, ai._bounds.z_min, ai._bounds.z_max])
	_ok = _ok and ai._bounds.z_min < 0.0 and ai._bounds.z_max < 0.0

	# Мяч высоко в воздухе, вне досягаемости весла за отведённое время -- не
	# будет поймано за тест, что позволяет чисто проверить именно логику
	# преследования (velocity.z остаётся < 0 -- мяч всё ещё летит к AI).
	ball.position = Vector3(3.0, 10.0, -2.0)
	ball.velocity = Vector3(0.0, 0.0, -5.0)
	ai.position = Vector3(0.0, 1.0, -6.0)
	ai._previous_position = ai.position

	for i in range(60):
		await physics_frame
	print("after tracking (ball unreachable): ai.position=%s ball.velocity=%s" % [ai.position, ball.velocity])
	_ok = _ok and ai.position.x > 1.0
	_ok = _ok and ball.velocity.z < 0.0 # подтверждает, что удара не произошло

	ball.velocity = Vector3(0.0, 0.0, 5.0) # мяч теперь летит от AI
	var home_z: float = (ai._bounds.z_min + ai._bounds.z_max) / 2.0
	for i in range(200):
		await physics_frame
	print("after ball heads away: ai.position=%s (expect x~0, z~%.3f)" % [ai.position, home_z])
	_ok = _ok and absf(ai.position.x) < 0.1
	_ok = _ok and absf(ai.position.z - home_z) < 0.1

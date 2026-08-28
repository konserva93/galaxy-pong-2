extends SceneTree

## Регрессия для формулы удара и связанных фиксов в ball.gd:
## - направление/сила отскока (центр весла, смещение, вклад скорости весла);
## - промах (XZ мяча вне площади весла — удар не засчитывается);
## - однократность удара за один заход мяча под весло (регрессия бага
##   "мяч вязнет в весле" при пересчитывании удара каждый кадр);
## - отскок всегда в сторону соперника, даже при попадании у "своего" края
##   весла или сильном движении весла назад в момент удара;
## - работает одинаково для PlayerPaddle и AIPaddle (общая группа "paddles").
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

	var player: Area3D = main.get_node("PlayerPaddle")
	var ai: Area3D = main.get_node("AIPaddle")
	var ball: Area3D = main.get_node("Ball")

	await _check_hit_formula(player, ball)
	await _check_no_repeated_hit(player, ball)
	await _check_always_forward(player, ball)
	await _check_ai_hit_bounces_toward_player(ai, ball)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_hit_formula(paddle: Area3D, ball: Area3D) -> void:
	print("--- hit formula (center / offset / paddle-velocity / miss) ---")

	# Центр весла, весло неподвижно -> чистый базовый импульс (X=0, Z=-forward_speed).
	paddle.position = Vector3(1.0, 1.0, 5.0)
	paddle._previous_position = paddle.position
	paddle.velocity = Vector3.ZERO
	ball.position = Vector3(1.0, 1.05, 5.0)
	ball.velocity = Vector3(0.0, -4.0, 0.0)
	await physics_frame
	var expect_center := Vector3(0.0, ball.ball_launch_vy, -ball.ball_hit_forward_speed)
	print("[center] velocity=%s expected=%s" % [ball.velocity, expect_center])
	_ok = _ok and ball.velocity.is_equal_approx(expect_center)

	# Смещение от центра -> добавляет к X и к базовой Z-силе (не заменяет её).
	paddle.position = Vector3(2.0, 1.0, 5.0) # half_size=(1.0, 0.9)
	paddle._previous_position = paddle.position
	paddle.velocity = Vector3.ZERO
	ball.position = Vector3(2.5, 1.05, 4.7) # offset x=0.5/1.0=0.5, z=-0.3/0.9=-0.333
	ball.velocity = Vector3(0.0, -4.0, 0.0)
	await physics_frame
	var expect_x: float = 0.5 * ball.ball_hit_horizontal_factor
	var expect_z: float = -(ball.ball_hit_forward_speed + absf(-0.3 / 0.9) * ball.ball_hit_horizontal_factor)
	print("[offset] velocity=%s expected x=%.3f z=%.3f" % [ball.velocity, expect_x, expect_z])
	_ok = _ok and is_equal_approx(ball.velocity.x, expect_x)
	_ok = _ok and is_equal_approx(ball.velocity.z, expect_z)

	# Вклад скорости весла в момент удара (paddle.gd сам каждый кадр пересчитывает
	# velocity=(position-previous)/delta, поэтому имитируем движение через
	# previous_position, а не напрямую через velocity).
	var desired_paddle_velocity := Vector3(3.0, 0.0, -2.0)
	paddle.position = Vector3(0.0, 1.0, 5.0)
	paddle._previous_position = paddle.position - desired_paddle_velocity * (1.0 / 60.0)
	ball.position = Vector3(0.0, 1.05, 5.0)
	ball.velocity = Vector3(0.0, -4.0, 0.0)
	await physics_frame
	var influence: float = ball.paddle_velocity_influence
	var expect_c: Vector3 = Vector3(0.0, ball.ball_launch_vy, -ball.ball_hit_forward_speed) + desired_paddle_velocity * influence
	print("[paddle velocity] velocity=%s expected=%s" % [ball.velocity, expect_c])
	_ok = _ok and ball.velocity.is_equal_approx(expect_c)

	# Мимо весла (XZ вне площади) -> удар не засчитывается, мяч продолжает падать.
	paddle.position = Vector3(0.0, 1.0, 5.0)
	paddle._previous_position = paddle.position
	paddle.velocity = Vector3.ZERO
	ball.position = Vector3(5.0, 1.05, 5.0)
	ball.velocity = Vector3(0.0, -4.0, 0.0)
	var vy_before: float = ball.velocity.y
	await physics_frame
	print("[miss] velocity.y=%.3f (expect < %.3f, gravity only)" % [ball.velocity.y, vy_before])
	_ok = _ok and ball.velocity.y < vy_before
	_ok = _ok and not is_equal_approx(ball.velocity.y, ball.ball_launch_vy)


func _check_no_repeated_hit(paddle: Area3D, ball: Area3D) -> void:
	print("--- no repeated hit while paddle keeps moving under the ball ---")

	paddle.position = Vector3(0.0, 1.0, 5.0)
	paddle._previous_position = Vector3(-0.1, 1.0, 5.0)
	ball.position = Vector3(0.0, 1.05, 5.0)
	ball.velocity = Vector3(0.0, -4.0, 0.0)

	var hit_count := 0
	var last_vy: float = ball.velocity.y
	for i in range(10):
		Input.action_press("move_right")
		await physics_frame
		if last_vy <= 0.0 and ball.velocity.y > 6.0:
			hit_count += 1
		last_vy = ball.velocity.y
	Input.action_release("move_right")

	print("hit_count over 10 frames: ", hit_count, " (expect exactly 1)")
	_ok = _ok and hit_count == 1


func _check_always_forward(paddle: Area3D, ball: Area3D) -> void:
	print("--- bounce always toward the opponent ---")

	# Попадание у "своего" (дальнего от сетки) края весла.
	paddle.position = Vector3(0.0, 1.0, 5.0)
	paddle._previous_position = paddle.position
	paddle.velocity = Vector3.ZERO
	ball.position = Vector3(0.0, 1.05, 5.5)
	ball.velocity = Vector3(0.0, -4.0, 0.0)
	await physics_frame
	print("[own-side edge hit] velocity.z=%.3f (expect < 0)" % ball.velocity.z)
	_ok = _ok and ball.velocity.z < 0.0

	# Сильное движение весла назад в момент удара не должно развернуть отскок.
	var backward_velocity := Vector3(0.0, 0.0, 20.0)
	paddle.position = Vector3(0.0, 1.0, 5.0)
	paddle._previous_position = paddle.position - backward_velocity * (1.0 / 60.0)
	ball.position = Vector3(0.0, 1.05, 5.0)
	ball.velocity = Vector3(0.0, -4.0, 0.0)
	await physics_frame
	print("[paddle moving backward hard] velocity.z=%.3f (expect < 0)" % ball.velocity.z)
	_ok = _ok and ball.velocity.z < 0.0


func _check_ai_hit_bounces_toward_player(ai: Area3D, ball: Area3D) -> void:
	print("--- hit against AI paddle bounces toward the player ---")

	var home_z: float = (ai._bounds.z_min + ai._bounds.z_max) / 2.0
	ai.position = Vector3(0.0, 1.0, home_z)
	ai._previous_position = ai.position
	ball.position = Vector3(0.0, 1.05, home_z)
	ball.velocity = Vector3(0.0, -4.0, 0.0) # vz=0.0 -- держит AI неподвижным (idle) на этом тике
	await physics_frame
	print("[AI hit, center] velocity=%s (expect z > 0, toward player)" % ball.velocity)
	_ok = _ok and is_equal_approx(ball.velocity.y, ball.ball_launch_vy)
	_ok = _ok and is_equal_approx(ball.velocity.z, ball.ball_hit_forward_speed)

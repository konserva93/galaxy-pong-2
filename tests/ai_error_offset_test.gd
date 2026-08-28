extends SceneTree

## Регрессия для ai_error_offset / броска d21 (задача 3.1, paddle_ai.gd):
## - при каждом новом заходе AI "бросает" d21 (равномерно 1..21, не
##   нормальное распределение);
## - при броске < AIM_MISS_THRESHOLD (5) -- ГАРАНТИРОВАННЫЙ промах: цель
##   весла смещена от точной прогнозируемой точки настолько, чтобы мяч
##   оказался вне площади весла (по X или по Z), но оффсет ограничен сверху
##   ai_error_offset -- весло остаётся рядом с местом приземления, не мажет
##   в сторону;
## - при броске >= AIM_MISS_THRESHOLD -- точное попадание, оффсет нулевой;
## - бросок/оффсет фиксируются один раз за заход, пока мяч непрерывно летит
##   к AI (не дёргается каждый кадр);
## - новый заход (после того как мяч улетел от AI и снова полетел к нему)
##   бросает кубик заново.
##
## _predict_ball_landing()/_compute_target() вызываются напрямую (без
## await physics_frame между ними) специально: мяч сам двигается в
## _physics_process, и если дать кадру пройти между вычислением "точной"
## точки и вызовом _compute_target, у них разъедутся входные данные --
## разница будет отражать движение мяча, а не оффсет погрешности.
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

	_check_offset_bounded_and_stable(ai, ball)
	_check_die_roll_distribution(ai, ball)
	_check_miss_is_always_a_real_miss(ai, ball)
	_check_reroll_after_goal_pause(ai, ball)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_offset_bounded_and_stable(ai: Area3D, ball: Area3D) -> void:
	print("--- whatever this approach's roll was, offset stays within ai_error_offset and constant ---")

	ball.position = Vector3(3.0, 10.0, -2.0)
	ball.velocity = Vector3(0.0, 0.0, -5.0)

	var exact: Vector2 = ai._predict_ball_landing()
	var target1: Vector2 = ai._compute_target()
	var offset1: Vector2 = target1 - exact
	print("offset1=%s (limit=%.2f)" % [offset1, ai.ai_error_offset])
	_ok = _ok and absf(offset1.x) <= ai.ai_error_offset + 0.0001
	_ok = _ok and absf(offset1.y) <= ai.ai_error_offset + 0.0001

	# Мяч продолжает лететь к AI, но из другой позиции (как если бы прошёл
	# кадр) -- оффсет должен остаться тем же самым значением, кубик не
	# бросается заново на каждый прогноз.
	ball.position = Vector3(2.7, 9.5, -2.3)
	ball.velocity = Vector3(0.0, -0.2, -5.0)
	var exact2: Vector2 = ai._predict_ball_landing()
	var target2: Vector2 = ai._compute_target()
	var offset2: Vector2 = target2 - exact2
	print("offset2=%s (expect == offset1)" % [offset2])
	_ok = _ok and offset1.is_equal_approx(offset2)


func _check_die_roll_distribution(ai: Area3D, ball: Area3D) -> void:
	print("--- d21 roll: uniform 1..21, miss (<5) gives bounded offset, hit gives exact aim ---")

	var attempts := 400
	var miss_count := 0
	var hit_count := 0
	var offsets_seen: Array[float] = [] # для грубой проверки, что оффсет не всегда одно и то же значение

	for i in range(attempts):
		ball.velocity = Vector3(0.0, 0.0, 5.0) # мяч летит от AI -- сброс состояния реакции
		ai._compute_target()

		ball.position = Vector3(3.0, 10.0, -2.0)
		ball.velocity = Vector3(0.0, 0.0, -5.0) # новый заход -- новый бросок
		var exact: Vector2 = ai._predict_ball_landing()
		var target: Vector2 = ai._compute_target()
		var offset: Vector2 = target - exact

		if offset.is_equal_approx(Vector2.ZERO):
			hit_count += 1
		else:
			miss_count += 1
			_ok = _ok and absf(offset.x) <= ai.ai_error_offset + 0.0001
			_ok = _ok and absf(offset.y) <= ai.ai_error_offset + 0.0001
			offsets_seen.append(offset.x)

	var miss_ratio := float(miss_count) / float(attempts)
	var expected_ratio := float(ai.AIM_MISS_THRESHOLD - 1) / float(ai.AIM_DIE_SIDES)
	print("attempts=%d hit=%d miss=%d miss_ratio=%.3f (expect ~%.3f, d21 roll<%d)" % [attempts, hit_count, miss_count, miss_ratio, expected_ratio, ai.AIM_MISS_THRESHOLD])
	# Широкий допуск -- это случайность на 400 бросках, не точная пропорция.
	_ok = _ok and absf(miss_ratio - expected_ratio) < 0.08

	var distinct_offsets := {}
	for o in offsets_seen:
		distinct_offsets[snappedf(o, 0.01)] = true
	print("distinct miss-offset values seen: %d (expect > 1, i.e. not a single fixed value -- confirms non-degenerate spread)" % distinct_offsets.size())
	_ok = _ok and distinct_offsets.size() > 1


## Регрессия: изначально ai_error_offset (0.5) был меньше половины
## paddle_size (1.0 x 0.9), так что даже наихудший промах всё равно попадал
## в площадь весла -- мяч отбивался всегда, промах не имел видимого эффекта
## ("ИИ не промахивается, когда выпадает меньше 5"). Затем оффсет увеличили
## (1.2), но это давало лишь вероятностный промах -- пользователь явно
## потребовал, чтобы бросок < 5 был ГАРАНТИРОВАННЫМ промахом каждый раз, без
## исключений. Проверяем это и точечно (через _is_within_paddle), и
## статистически на реальном распределении бросков: буквально каждый
## промашный бросок должен давать мяч вне площади весла.
func _check_miss_is_always_a_real_miss(ai: Area3D, ball: Area3D) -> void:
	print("--- roll < 5 must ALWAYS place the ball outside the paddle's hit area, no exceptions ---")

	var half_size: Vector2 = ai.paddle_size / 2.0
	print("paddle half-size: %s, ai_error_offset=%.2f" % [half_size, ai.ai_error_offset])
	_ok = _ok and ai.ai_error_offset > minf(half_size.x, half_size.y)

	var landing := Vector3(0.0, ai.paddle_hit_height, -3.0)

	# Оффсет за пределами половины весла по X -- фактический промах.
	ai.position = landing + Vector3(half_size.x + 0.2, 0.0, 0.0)
	ball.position = landing
	_ok = _ok and not ball._is_within_paddle(ai)

	# То же самое, но по Z.
	ai.position = landing + Vector3(0.0, 0.0, half_size.y + 0.2)
	ball.position = landing
	_ok = _ok and not ball._is_within_paddle(ai)

	# Статистика на реальном распределении бросков/оффсетов: КАЖДЫЙ промашный
	# бросок (roll < 5) обязан давать мяч вне площади весла -- ни одного
	# исключения на большой выборке.
	var attempts := 400
	var real_miss_count := 0
	var miss_roll_count := 0
	for i in range(attempts):
		ball.velocity = Vector3(0.0, 0.0, 5.0)
		ai._compute_target()

		ball.position = Vector3(0.0, 10.0, -3.0)
		ball.velocity = Vector3(0.0, 0.0, -5.0)
		var exact: Vector2 = ai._predict_ball_landing()
		var target: Vector2 = ai._compute_target()
		if target.is_equal_approx(exact):
			continue # это попадание (roll >= 5), а не промах
		miss_roll_count += 1

		var ball_landing := Vector3(exact.x, ai.paddle_hit_height, exact.y)
		var paddle_at_target := Vector3(target.x, ai.paddle_hit_height, target.y)
		ai.position = paddle_at_target
		ball.position = ball_landing
		if not ball._is_within_paddle(ai):
			real_miss_count += 1

	print("miss rolls=%d, of which actually missed the paddle=%d (expect == miss rolls, every miss is real)" % [miss_roll_count, real_miss_count])
	_ok = _ok and miss_roll_count > 0
	_ok = _ok and real_miss_count == miss_roll_count


## Регрессия: после гола мяч замирает и прячется (ball._score_point --
## visible=false), но его velocity.z остаётся таким же, каким был ДО гола
## (физика не обнуляется, просто перестаёт считаться). Если AI промахнулся
## прямо перед голом (velocity.z уже было < 0 в момент паузы), в версии ДО
## фикса "заход" никогда не завершался -- velocity.z ни разу не становился
## >= 0, чтобы сбросить _was_reacting, и следующая подача в сторону AI
## наследовала СТАРЫЙ бросок d21 (в т.ч. промах) вместо нового. Фикс:
## _compute_target сбрасывает _was_reacting, пока мяч не visible (пауза).
func _check_reroll_after_goal_pause(ai: Area3D, ball: Area3D) -> void:
	print("--- a fresh d21 roll happens for the serve after a goal, even if the ball froze mid-approach ---")

	# Симулируем состояние "AI только что промахнулся, мяч замер на паузе,
	# скрыт -- как ball._score_point() оставляет его": velocity.z ещё < 0
	# (заморожено с момента до гола), но visible=false.
	ai._was_reacting = true
	ai._current_error = Vector2(99.0, 99.0) # заведомо невозможное значение (> ai_error_offset)
	ball.visible = false
	ball.velocity = Vector3(0.0, 0.0, -5.0)
	ai._compute_target()
	print("mid-pause: _was_reacting=%s (expect false -- reset while ball frozen/hidden)" % ai._was_reacting)
	_ok = _ok and not ai._was_reacting

	# Пауза кончилась, GameManager подал мяч обратно в сторону AI (та же
	# ситуация, в которой был баг: подача идёт именно к промахнувшемуся AI).
	ball.visible = true
	ball.position = Vector3(0.0, 10.0, -3.0)
	ball.velocity = Vector3(0.0, 0.0, -5.0)
	ai._compute_target()
	print("new serve toward AI: _current_error=%s (expect within +-%.2f, i.e. freshly rolled, not the stale sentinel)" % [ai._current_error, ai.ai_error_offset])
	_ok = _ok and absf(ai._current_error.x) <= ai.ai_error_offset + 0.0001
	_ok = _ok and absf(ai._current_error.y) <= ai.ai_error_offset + 0.0001

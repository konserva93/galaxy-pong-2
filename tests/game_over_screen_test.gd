extends SceneTree

## Регрессия для game_over_screen.gd/GameManager.restart_game() (задача 4.3):
## - GameManager.game_over(winner) показывает экран с правильным текстом
##   победителя и ставит get_tree().paused=true (вёсла реально
##   останавливаются, не просто мяч);
## - restart_game(): счёт обнуляется, is_game_over снимается, экран
##   скрывается, пауза снимается, вёсла возвращаются на стартовые позиции
##   (через restart_requested -> main.gd), мяч снова летит (новая подача);
## - действие "restart" (Space/Enter) на экране работает так же, как кнопка
##   «Рестарт».
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

	var game_manager: Node = root.get_node("GameManager")
	var ball: Area3D = main.get_node("Ball")
	var player: Area3D = main.get_node("PlayerPaddle")
	var ai: Area3D = main.get_node("AIPaddle")
	var screen: Control = main.get_node("UI/GameOverScreen")
	var winner_label: Label = screen.get_node("CenterContainer/VBoxContainer/WinnerLabel")

	await _check_game_over_shows_screen_and_freezes(game_manager, player, ai, screen, winner_label)
	await _check_restart_resets_everything(game_manager, ball, player, ai, screen)
	await _check_restart_action_hotkey(game_manager, screen)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_game_over_shows_screen_and_freezes(game_manager: Node, player: Area3D, ai: Area3D, screen: Control, winner_label: Label) -> void:
	print("--- game_over shows the screen with the winner's text and freezes gameplay ---")

	game_manager.player_score = game_manager.SCORE_TO_WIN - 1
	game_manager.ai_score = 0
	var player_pos_at_start: Vector3 = player.position
	Input.action_press("move_left")
	await physics_frame
	Input.action_release("move_left")

	game_manager.register_point("player")
	await physics_frame

	print("game_over: is_game_over=%s tree.paused=%s screen.visible=%s text=%s" % [game_manager.is_game_over, root.get_tree().paused, screen.visible, winner_label.text])
	_ok = _ok and game_manager.is_game_over
	_ok = _ok and root.get_tree().paused
	_ok = _ok and screen.visible
	_ok = _ok and winner_label.text == "Ты выиграл!"

	# Задача 6.5: текст победителя подсвечивается его собственным неоновым
	# цветом (тот же циан, что у весла игрока -- см. PlayerPaddle.tscn).
	var font_color: Color = winner_label.get_theme_color("font_color")
	print("winner_label font_color=%s (expect player cyan)" % font_color)
	_ok = _ok and font_color.is_equal_approx(Color(0, 0.9, 1, 1))

	# Вёсла тоже должны стоять на месте, не только мяч.
	var player_pos_before: Vector3 = player.position
	var ai_pos_before: Vector3 = ai.position
	Input.action_press("move_left")
	for i in range(10):
		await physics_frame
	Input.action_release("move_left")
	print("paddles frozen during game over: player.position=%s (expect unchanged %s)" % [player.position, player_pos_before])
	_ok = _ok and player.position.is_equal_approx(player_pos_before)
	_ok = _ok and ai.position.is_equal_approx(ai_pos_before)
	_ok = _ok and not player_pos_before.is_equal_approx(player_pos_at_start) # подтверждает, что весло вообще двигалось ДО game over


func _check_restart_resets_everything(game_manager: Node, ball: Area3D, player: Area3D, ai: Area3D, screen: Control) -> void:
	print("--- restart_game() resets score, positions, pause, and serves again ---")

	var player_start: Vector3 = player._start_position

	game_manager.restart_game()
	await physics_frame

	print("after restart: score=%d:%d is_game_over=%s tree.paused=%s screen.visible=%s" % [game_manager.player_score, game_manager.ai_score, game_manager.is_game_over, root.get_tree().paused, screen.visible])
	_ok = _ok and game_manager.player_score == 0
	_ok = _ok and game_manager.ai_score == 0
	_ok = _ok and not game_manager.is_game_over
	_ok = _ok and not root.get_tree().paused
	_ok = _ok and not screen.visible

	# Игрок: raw стартовая позиция (0,1,6) и так внутри клампа -- сверяем точно.
	print("player back at start: position=%s (expect %s)" % [player.position, player_start])
	_ok = _ok and player.position.is_equal_approx(player_start)

	# AI: raw стартовая позиция сцены (0,1,-6) на самом деле ЗА пределами
	# визуально скорректированного Z-диапазона (parallax-клампа) -- это не
	# специфика рестарта, так было бы и на самом первом кадре игры, если бы
	# кто-то проверил его настолько же рано. reset_position() ставит X/Z весла
	# в raw-координаты сцены; следующий же _physics_process зажимает их в
	# допустимый диапазон -- проверяем именно это, а не точное (0,1,-6).
	print("ai back in valid range: position=%s x_range=[%.3f,%.3f] z_range=[%.3f,%.3f]" % [ai.position, ai._bounds.x_min, ai._bounds.x_max, ai._bounds.z_min, ai._bounds.z_max])
	_ok = _ok and absf(ai.position.x) < 0.01
	_ok = _ok and ai.position.z >= ai._bounds.z_min - 0.01 and ai.position.z <= ai._bounds.z_max + 0.01

	print("ball serving again: velocity=%s (expect nonzero)" % ball.velocity)
	_ok = _ok and ball.velocity.length() > 0.0


func _check_restart_action_hotkey(game_manager: Node, screen: Control) -> void:
	print("--- 'restart' input action (Space/Enter) works like clicking Restart, only while the screen is visible ---")

	game_manager.player_score = game_manager.SCORE_TO_WIN - 1
	game_manager.register_point("player")
	await physics_frame
	print("game over again before hotkey test: is_game_over=%s screen.visible=%s" % [game_manager.is_game_over, screen.visible])
	_ok = _ok and screen.visible

	var event := InputEventAction.new()
	event.action = "restart"
	event.pressed = true
	root.push_input(event)
	await physics_frame

	print("after 'restart' action: is_game_over=%s screen.visible=%s (expect both false/hidden -- restarted)" % [game_manager.is_game_over, screen.visible])
	_ok = _ok and not game_manager.is_game_over
	_ok = _ok and not screen.visible

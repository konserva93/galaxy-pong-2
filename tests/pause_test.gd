extends SceneTree

## Регрессия для паузы (задача 4.2, game_manager.gd/pause_menu.gd):
## - GameManager.toggle_pause() переключает get_tree().paused и эмитит
##   state_changed("Paused"/"Playing");
## - PauseMenu становится видимым/скрытым синхронно с этим состоянием;
## - пока пауза активна, игровая физика (мяч, вёсла) реально останавливается
##   (get_tree().paused тормозит их дефолтный process_mode), а GameManager и
##   PauseMenu (process_mode=Always) продолжают реагировать;
## - нажатие action "pause" переключает паузу через _unhandled_input;
## - после game_over пауза заблокирована (нечего ставить на паузу).
##
## Запуск: см. reference-godot-cli в памяти проекта.

var _ok := true
var _states_seen: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _on_state_changed(new_state: String) -> void:
	_states_seen.append(new_state)


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var game_manager: Node = root.get_node("GameManager")
	var ball: Area3D = main.get_node("Ball")
	var pause_menu: Control = main.get_node("UI/PauseMenu")
	game_manager.state_changed.connect(_on_state_changed)

	await _check_toggle_pauses_physics_and_menu(game_manager, ball, pause_menu)
	await _check_pause_input_action(game_manager, ball)
	await _check_blocked_after_game_over(game_manager)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_toggle_pauses_physics_and_menu(game_manager: Node, ball: Area3D, pause_menu: Control) -> void:
	print("--- toggle_pause() stops ball physics and shows/hides PauseMenu ---")

	print("initial: is_paused=%s tree.paused=%s pause_menu.visible=%s" % [game_manager.is_paused, root.get_tree().paused, pause_menu.visible])
	_ok = _ok and not game_manager.is_paused
	_ok = _ok and not root.get_tree().paused
	_ok = _ok and not pause_menu.visible

	_states_seen.clear()
	game_manager.toggle_pause()
	print("after toggle_pause(): is_paused=%s tree.paused=%s pause_menu.visible=%s states_seen=%s" % [game_manager.is_paused, root.get_tree().paused, pause_menu.visible, _states_seen])
	_ok = _ok and game_manager.is_paused
	_ok = _ok and root.get_tree().paused
	_ok = _ok and pause_menu.visible
	_ok = _ok and _states_seen == ["Paused"]

	var frozen_pos: Vector3 = ball.position
	var frozen_vel: Vector3 = ball.velocity
	for i in range(20):
		await process_frame # физика стоит, а SceneTree.process_frame всё ещё тикает
	print("20 idle frames while paused: ball.position=%s (expect unchanged %s)" % [ball.position, frozen_pos])
	_ok = _ok and ball.position.is_equal_approx(frozen_pos)
	_ok = _ok and ball.velocity.is_equal_approx(frozen_vel)

	_states_seen.clear()
	game_manager.toggle_pause() # снимаем паузу (эмулирует нажатие "Продолжить")
	print("after resuming: is_paused=%s tree.paused=%s pause_menu.visible=%s states_seen=%s" % [game_manager.is_paused, root.get_tree().paused, pause_menu.visible, _states_seen])
	_ok = _ok and not game_manager.is_paused
	_ok = _ok and not root.get_tree().paused
	_ok = _ok and not pause_menu.visible
	_ok = _ok and _states_seen == ["Playing"]

	await physics_frame
	await physics_frame
	print("ball moved again after resuming: %s (expect != %s)" % [ball.position, frozen_pos])
	_ok = _ok and not ball.position.is_equal_approx(frozen_pos)


func _check_pause_input_action(game_manager: Node, ball: Area3D) -> void:
	print("--- the 'pause' input action toggles pause via _unhandled_input ---")
	# Input.action_press() only sets polling state (Input.is_action_pressed/
	# get_axis) -- it does NOT dispatch a real InputEvent through
	# _input/_unhandled_input. _unhandled_input needs an actual event, so we
	# synthesize one via Input.parse_input_event(), matching how a real key
	# press reaches the tree.

	_ok = _ok and not game_manager.is_paused
	_send_pause_action_press()
	await process_frame
	print("after pressing 'pause' action: is_paused=%s (expect true)" % game_manager.is_paused)
	_ok = _ok and game_manager.is_paused

	_send_pause_action_press()
	await process_frame
	print("after pressing 'pause' action again: is_paused=%s (expect false)" % game_manager.is_paused)
	_ok = _ok and not game_manager.is_paused


func _send_pause_action_press() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	# root.push_input(), не Input.parse_input_event(): последний обновляет
	# только состояние опроса (is_action_pressed/get_axis), а не проходит
	# через _input/_unhandled_input -- push_input() явно прогоняет событие
	# через тот же путь, что и реальный ввод от ОС.
	root.push_input(event)


func _check_blocked_after_game_over(game_manager: Node) -> void:
	print("--- pause is a no-op once the game is over ---")

	game_manager.is_game_over = true
	game_manager.toggle_pause()
	print("toggle_pause() after game_over: is_paused=%s tree.paused=%s (expect both false -- blocked)" % [game_manager.is_paused, root.get_tree().paused])
	_ok = _ok and not game_manager.is_paused
	_ok = _ok and not root.get_tree().paused

	game_manager.is_game_over = false # чтобы не мешать возможным следующим тестам/выходу процесса

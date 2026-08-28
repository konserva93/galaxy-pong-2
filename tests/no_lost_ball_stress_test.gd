extends SceneTree

## Долгий стресс-тест со случайным вводом игрока (клавиатура): гоняет полную
## сцену много секунд подряд и проверяет, что мяч не "теряется" — либо
## розыгрыш регулярно завершается голом/аутом, либо позиция/скорость не
## портятся в NaN/Inf. Остановка из-за game_over (кто-то реально набрал
## SCORE_TO_WIN) — ожидаемый, не аварийный исход: именно так нашлось, что
## реальная жалоба "иногда теряю мяч" была не багом детекции гола/аута
## (см. commit "fix: ball never returning..."), а достижением game_over без
## какой-либо видимой обратной связи (экрана победы ещё нет — задача 4.3).
##
## Запуск: см. reference-godot-cli в памяти проекта. Детерминирован (фиксный
## seed), поэтому воспроизводим при повторных запусках.

var _rng := RandomNumberGenerator.new()
var _last_score_frame := 0
var _total_score_events := 0
var _game_over_seen := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_rng.seed = 12345
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)

	var game_manager: Node = root.get_node("GameManager")
	var ball: Area3D = main.get_node("Ball")
	var player: Area3D = main.get_node("PlayerPaddle")

	game_manager.score_changed.connect(func(_p, _a): _on_score())
	game_manager.game_over.connect(func(_w): _game_over_seen = true)

	var max_frames := 60 * 90 # 90 секунд
	var stall_limit_frames := 60 * 12 # 12 секунд без единого очка — подозрительно
	var actions := ["move_left", "move_right", "move_forward", "move_back"]
	var current_action := ""
	var action_change_counter := 0
	var ok := true

	for i in range(max_frames):
		action_change_counter -= 1
		if action_change_counter <= 0:
			if current_action != "":
				Input.action_release(current_action)
			if _rng.randf() < 0.15:
				current_action = ""
			else:
				current_action = actions[_rng.randi_range(0, actions.size() - 1)]
				Input.action_press(current_action)
			action_change_counter = _rng.randi_range(3, 25)

		await physics_frame

		if not _is_finite(ball.position) or not _is_finite(ball.velocity):
			print("FAIL frame=%d: ball position/velocity non-finite: pos=%s vel=%s" % [i, ball.position, ball.velocity])
			ok = false
			break
		if not _is_finite(player.position):
			print("FAIL frame=%d: player paddle position non-finite: %s" % [i, player.position])
			ok = false
			break

		if _game_over_seen:
			print("game_over reached at frame %d -- expected stop, not a stall. Ending test early." % i)
			break

		if i - _last_score_frame > stall_limit_frames:
			print("FAIL frame=%d: no score for %ds -- ball likely stuck/lost. ball.pos=%s ball.vel=%s ball.visible=%s" % [i, stall_limit_frames / 60, ball.position, ball.velocity, ball.visible])
			ok = false
			break

	if current_action != "":
		Input.action_release(current_action)

	print("total score events: %d, game_over reached: %s" % [_total_score_events, _game_over_seen])
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _on_score() -> void:
	_total_score_events += 1
	_last_score_frame = Engine.get_physics_frames()


func _is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

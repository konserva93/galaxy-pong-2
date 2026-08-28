extends SceneTree

## Быстрая regression-проверка: поднимает Main.tscn и прогоняет 10 секунд
## игрового времени (оба весла + мяч в реальном взаимодействии), проверяя,
## что ничего не падает и не улетает в NaN/бесконечность. Не проверяет
## конкретные игровые правила (для этого — отдельные точечные тесты),
## только общую стабильность сцены.
##
## Запуск (см. reference-godot-cli в памяти проекта):
##   "<путь до Godot>" --headless --path "<путь до проекта>" -s "res://tests/smoke_test.gd"

const DURATION_SECONDS: float = 10.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)

	var ai: Area3D = main.get_node("AIPaddle")
	var player: Area3D = main.get_node("PlayerPaddle")
	var ball: Area3D = main.get_node("Ball")

	var ok := true
	var frame_count: int = int(DURATION_SECONDS * 60.0)

	for i in range(frame_count):
		await physics_frame

		for node in [ai, player, ball]:
			if not is_instance_valid(node):
				print("FAIL: node freed unexpectedly at frame ", i, ": ", node)
				ok = false
				continue
			if not _is_finite(node.position):
				print("FAIL: non-finite position at frame ", i, ": ", node.name, " = ", node.position)
				ok = false

		if i % 100 == 0:
			print("t=%.1fs ball=%s ai=%s player=%s" % [i / 60.0, ball.position, ai.position, player.position])

	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

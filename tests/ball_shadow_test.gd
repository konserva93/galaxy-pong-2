extends SceneTree

## Регрессия для тени мяча (ShadowMesh, см. ball.gd _update_shadow):
## - тень держится на уровне поля (Y=0.02) точно под мячом по X/Z при любой
##   высоте мяча, и её масштаб уменьшается с высотой в допустимых пределах;
## - тень ложится на поверхность весла (а не остаётся под ним, где была бы
##   не видна), когда мяч находится над его площадью.
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

	var ball: Area3D = main.get_node("Ball")
	var shadow: MeshInstance3D = ball.get_node("ShadowMesh")
	var paddle: Area3D = main.get_node("PlayerPaddle")

	# Независимо от того, что задал GameManager при первой подаче -- берём
	# известную скорость, чтобы траектория (и момент возможного гола) была
	# предсказуемой.
	ball.launch(Vector3(0.0, 8.0, 0.0))
	await _check_ground_tracking(ball, shadow)
	await _check_paddle_surface(ball, shadow, paddle)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_ground_tracking(ball: Area3D, shadow: MeshInstance3D) -> void:
	print("--- shadow follows ball X/Z at ground level, shrinks with height ---")

	for i in range(60):
		await physics_frame
		var world_shadow_y: float = ball.position.y + shadow.position.y
		if absf(world_shadow_y - 0.02) > 0.001:
			print("FAIL at frame ", i, ": world shadow y=", world_shadow_y, " ball.y=", ball.position.y)
			_ok = false
		if shadow.scale.x < 0.35 - 0.001 or shadow.scale.x > 1.0 + 0.001:
			print("FAIL: shadow scale out of bounds: ", shadow.scale.x)
			_ok = false


func _check_paddle_surface(ball: Area3D, shadow: MeshInstance3D, paddle: Area3D) -> void:
	print("--- shadow lands on paddle surface when ball is over it ---")

	paddle.position = Vector3(0.0, 1.0, 5.0)
	paddle._previous_position = paddle.position
	# launch() снимает "мяч замер после гола" (см. ball.gd _physics_process) --
	# без этого, если мяч успел набрать очко за 60 кадров предыдущей проверки,
	# физика (и вместе с ней _update_shadow) вообще не выполняется, и тень
	# просто не сдвинется на следующий кадр.
	ball.launch(Vector3.ZERO)
	ball.position = Vector3(0.0, 3.0, 5.0) # прямо над веслом
	await physics_frame
	var world_shadow_y: float = ball.position.y + shadow.position.y
	var expected_on_paddle: float = paddle.paddle_hit_height + 0.1
	print("over paddle: world_shadow_y=%.4f expected=%.4f" % [world_shadow_y, expected_on_paddle])
	_ok = _ok and absf(world_shadow_y - expected_on_paddle) < 0.001

	# Огромное смещение по X гарантирует отсутствие пересечения с ЛЮБЫМ
	# веслом независимо от его текущего Z (AI-весло тоже в группе "paddles"
	# и могло само куда-то уехать за предыдущие проверки).
	ball.launch(Vector3.ZERO)
	ball.position = Vector3(-999.0, 3.0, 5.0)
	await physics_frame
	world_shadow_y = ball.position.y + shadow.position.y
	print("away from paddle: world_shadow_y=%.4f expected=0.02" % world_shadow_y)
	_ok = _ok and absf(world_shadow_y - 0.02) < 0.001

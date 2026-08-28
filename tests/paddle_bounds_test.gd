extends SceneTree

## Регрессия для PaddleBounds (paddle_bounds.gd) и движения PlayerPaddle:
## - клавиатура доезжает ровно до вычисленных границ (не до "наивных" плоских);
## - визуально скорректированные границы X/Z действительно совпадают с
##   проекцией истинных границ поля на экран на разных Z (фикс параллакса,
##   см. project memory "Camera-parallax clamp bug").
##
## Запуск: см. tests/README.md или reference-godot-cli в памяти проекта.

var _ok := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var paddle: Area3D = main.get_node("PlayerPaddle")
	var camera: Camera3D = main.get_node("Camera3D")

	await _check_keyboard_reaches_bounds(paddle)
	await physics_frame
	await _check_visual_alignment(paddle, camera)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_keyboard_reaches_bounds(paddle: Area3D) -> void:
	print("--- keyboard reachability ---")

	Input.action_press("move_left")
	for i in range(150):
		await physics_frame
	Input.action_release("move_left")
	print("move_left -> x=%.4f (bound x_min=%.4f)" % [paddle.position.x, paddle._bounds.x_min])
	_ok = _ok and is_equal_approx(paddle.position.x, paddle._bounds.x_min)

	Input.action_press("move_right")
	for i in range(150):
		await physics_frame
	Input.action_release("move_right")
	print("move_right -> x=%.4f (bound x_max=%.4f)" % [paddle.position.x, paddle._bounds.x_max])
	_ok = _ok and is_equal_approx(paddle.position.x, paddle._bounds.x_max)

	Input.action_press("move_forward")
	for i in range(250):
		await physics_frame
	Input.action_release("move_forward")
	print("move_forward -> z=%.4f (bound z_min=%.4f)" % [paddle.position.z, paddle._bounds.z_min])
	_ok = _ok and is_equal_approx(paddle.position.z, paddle._bounds.z_min)

	Input.action_press("move_back")
	for i in range(250):
		await physics_frame
	Input.action_release("move_back")
	print("move_back -> z=%.4f (bound z_max=%.4f)" % [paddle.position.z, paddle._bounds.z_max])
	_ok = _ok and is_equal_approx(paddle.position.z, paddle._bounds.z_max)


func _check_visual_alignment(paddle: Area3D, camera: Camera3D) -> void:
	print("--- visual alignment (clamped edge vs. true field boundary, same screen row) ---")

	for z in [paddle._bounds.z_min, 2.0, 4.0, 6.0, paddle._bounds.z_max]:
		paddle._bounds.update_x_bounds(camera, z)
		var edge_world: float = paddle._bounds.x_min - paddle._bounds.half_width
		var edge_screen := camera.unproject_position(Vector3(edge_world, paddle.paddle_hit_height, z))

		var near_end := camera.unproject_position(Vector3(-paddle._bounds.field_width / 2.0, 0.0, -paddle._bounds.field_length / 2.0))
		var far_end := camera.unproject_position(Vector3(-paddle._bounds.field_width / 2.0, 0.0, paddle._bounds.field_length / 2.0))
		var boundary_screen_x: float = remap(edge_screen.y, near_end.y, far_end.y, near_end.x, far_end.x)

		var diff: float = absf(boundary_screen_x - edge_screen.x)
		print("z=%.2f x_min=%.3f edge_screen=(%.2f,%.2f) boundary_at_same_y=%.2f diff=%.4f" % [
			z, paddle._bounds.x_min, edge_screen.x, edge_screen.y, boundary_screen_x, diff
		])
		_ok = _ok and diff < 0.05

	# Симметрия X, и обе стороны обязаны оставаться в пределах своей половины по Z.
	paddle._bounds.update_x_bounds(camera, 4.0)
	print("symmetry: x_min=%.4f x_max=%.4f sum=%.4f (expect ~0)" % [paddle._bounds.x_min, paddle._bounds.x_max, paddle._bounds.x_min + paddle._bounds.x_max])
	_ok = _ok and absf(paddle._bounds.x_min + paddle._bounds.x_max) < 0.01
	_ok = _ok and paddle._bounds.z_min > 0.0 and paddle._bounds.z_max > 0.0

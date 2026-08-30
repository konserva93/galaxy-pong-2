extends SceneTree

## Регрессия для задачи 6.3 (мяч и след): проверяет только то, что можно
## проверить программно — материал мяча эмиссивен, свет и след-частицы
## присутствуют и настроены (мировые координаты у следа, чтобы он оставался
## позади движущегося мяча), и их интенсивность реально растёт со скоростью
## мяча (а не постоянна). Насколько это красиво выглядит с bloom (этап 6.4) —
## решает пользователь при живом просмотре.
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

	_check_ball_material(ball)
	_check_light_and_trail_setup(ball)
	await _check_intensity_scales_with_speed(ball)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_ball_material(ball: Area3D) -> void:
	print("--- ball mesh material is emissive, not the old flat color ---")

	var mesh_instance: MeshInstance3D = ball.get_node("MeshInstance3D")
	var mat: StandardMaterial3D = mesh_instance.mesh.material
	print("mat=%s emission_enabled=%s" % [mat, mat.emission_enabled if mat else null])
	_ok = _ok and mat != null and mat.emission_enabled


func _check_light_and_trail_setup(ball: Area3D) -> void:
	print("--- ball has a small omni light and a world-space particle trail ---")

	var light: OmniLight3D = ball.get_node_or_null("BallLight")
	print("light=%s omni_range=%s" % [light, light.omni_range if light else null])
	_ok = _ok and light != null
	_ok = _ok and light != null and light.omni_range <= 5.0

	var trail: GPUParticles3D = ball.get_node_or_null("Trail")
	print("trail=%s local_coords=%s process_material=%s" % [
		trail, trail.local_coords if trail else null, trail.process_material if trail else null
	])
	_ok = _ok and trail != null
	if trail == null:
		return
	# Мировые координаты обязательны -- иначе испущенные частицы будут
	# двигаться вместе с мячом вместо того, чтобы оставаться позади него,
	# и никакого "следа" визуально не получится.
	_ok = _ok and trail.local_coords == false
	_ok = _ok and trail.process_material != null

	# Регрессия: изначально частицы были голыми квадратами QuadMesh без текстуры
	# -- визуально читалось как "квадратики" вместо плавного следа (замечено
	# пользователем при живом просмотре). Радиальный градиент на albedo_texture
	# даёт мягкий круглый спад альфы вместо жёсткого края квадрата.
	var trail_mat: StandardMaterial3D = trail.draw_pass_1.material
	print("trail_mat.albedo_texture=%s" % trail_mat.albedo_texture if trail_mat else null)
	_ok = _ok and trail_mat != null
	_ok = _ok and trail_mat != null and trail_mat.albedo_texture is GradientTexture2D
	if trail_mat != null and trail_mat.albedo_texture is GradientTexture2D:
		_ok = _ok and trail_mat.albedo_texture.fill == GradientTexture2D.FILL_RADIAL


func _check_intensity_scales_with_speed(ball: Area3D) -> void:
	print("--- light energy and trail amount_ratio grow with ball speed, not constant ---")

	var light: OmniLight3D = ball.get_node("BallLight")
	var trail: GPUParticles3D = ball.get_node("Trail")

	ball.launch(Vector3(0.0, 0.5, 0.5)) # почти неподвижен -- минимальная интенсивность
	await physics_frame
	var slow_energy: float = light.light_energy
	var slow_ratio: float = trail.amount_ratio

	ball.launch(Vector3(6.0, 6.0, 6.0)) # быстро -- высокая интенсивность
	await physics_frame
	var fast_energy: float = light.light_energy
	var fast_ratio: float = trail.amount_ratio

	print("slow: energy=%.3f ratio=%.3f | fast: energy=%.3f ratio=%.3f" % [
		slow_energy, slow_ratio, fast_energy, fast_ratio
	])
	_ok = _ok and fast_energy > slow_energy
	_ok = _ok and fast_ratio > slow_ratio
	_ok = _ok and slow_ratio > 0.0 # даже у апекса след не гаснет совсем

extends SceneTree

## Регрессия для задачи 6.1 (фон и skybox): проверяет только то, что можно
## проверить программно — сцена собрана правильно (Sky назначен, звёздное
## поле сконфигурировано). Как это выглядит на глаз — решает пользователь
## при живом просмотре в редакторе, сюда не входит.
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

	_check_sky(main)
	_check_stars(main)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_sky(main: Node3D) -> void:
	print("--- WorldEnvironment uses a procedural sky, not a flat background color ---")

	var world_env: WorldEnvironment = main.get_node("WorldEnvironment")
	var env: Environment = world_env.environment
	print("background_mode=%d (expect %d, BG_SKY), sky=%s" % [env.background_mode, Environment.BG_SKY, env.sky])
	_ok = _ok and env.background_mode == Environment.BG_SKY
	_ok = _ok and env.sky != null
	_ok = _ok and env.sky.sky_material is ProceduralSkyMaterial


func _check_stars(main: Node3D) -> void:
	print("--- a star field particle system exists and is configured ---")

	var stars: GPUParticles3D = main.get_node_or_null("Stars")
	print("stars=%s" % stars)
	_ok = _ok and stars != null
	if stars == null:
		return

	print("amount=%d draw_pass_1=%s process_material=%s" % [stars.amount, stars.draw_pass_1, stars.process_material])
	_ok = _ok and stars.amount > 0
	_ok = _ok and stars.draw_pass_1 != null
	_ok = _ok and stars.process_material != null

	# Регрессия конкретного бага: звёзды рождались внутри ЗАПОЛНЕННОГО шара
	# (EMISSION_SHAPE_SPHERE), из-за чего часть попадала прямо в игровую зону
	# (и даже между камерой и вёслами) и по глубине законно рисовалась поверх
	# объектов. Должны рождаться только на ПОВЕРХНОСТИ (SPHERE_SURFACE), и
	# радиус должен быть заведомо больше игровой зоны (поле максимум ~10x16,
	# камера на расстоянии ~17 от центра).
	var process_mat: ParticleProcessMaterial = stars.process_material
	print("emission_shape=%d (expect %d, SPHERE_SURFACE) radius=%.1f (expect > 30)" % [process_mat.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE, process_mat.emission_sphere_radius])
	_ok = _ok and process_mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	_ok = _ok and process_mat.emission_sphere_radius > 30.0

extends SceneTree

## Регрессия для задачи 6.3 (мяч и след) и её последующих правок:
## - материал мяча эмиссивен, свет присутствует и настроен;
## - след — процедурная меш-лента (не GPUParticles3D, см. правку 2026-08-30 --
##   отдельные "квадратики"/частицы не читались как непрерывный след), реально
##   строится по последним позициям мяча и её ширина/альфа растут со скоростью;
## - после гола лента следа не "вспыхивает" на месте приземления, пока мяч
##   ждёт следующей подачи (баг, найденный пользователем при живом просмотре:
##   GPUParticles3D продолжал испускать частицы на замершем мяче).
##
## Насколько это красиво выглядит с bloom (этап 6.4) — решает пользователь при
## живом просмотре.
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
	_check_light_and_ribbon_setup(ball)
	await _check_light_scales_with_speed(ball)
	_check_ribbon_alpha_scales_with_speed(ball)
	await _check_trail_clears_on_goal_and_relaunch(ball)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_ball_material(ball: Area3D) -> void:
	print("--- ball mesh material is emissive, not the old flat color ---")

	var mesh_instance: MeshInstance3D = ball.get_node("MeshInstance3D")
	var mat: StandardMaterial3D = mesh_instance.mesh.material
	print("mat=%s emission_enabled=%s" % [mat, mat.emission_enabled if mat else null])
	_ok = _ok and mat != null and mat.emission_enabled


func _check_light_and_ribbon_setup(ball: Area3D) -> void:
	print("--- ball has a small omni light and a top-level trail ribbon ---")

	var light: OmniLight3D = ball.get_node_or_null("BallLight")
	print("light=%s omni_range=%s" % [light, light.omni_range if light else null])
	_ok = _ok and light != null
	_ok = _ok and light != null and light.omni_range <= 5.0

	var ribbon: MeshInstance3D = ball.get_node_or_null("TrailRibbon")
	print("ribbon=%s top_level=%s" % [ribbon, ribbon.top_level if ribbon else null])
	_ok = _ok and ribbon != null
	# top_level обязателен -- иначе лента унаследовала бы трансформ мяча и
	# глобальные координаты её вершин задвоили бы смещение позиции мяча.
	_ok = _ok and ribbon != null and ribbon.top_level == true


func _check_light_scales_with_speed(ball: Area3D) -> void:
	print("--- light energy grows with ball speed, not constant ---")

	var light: OmniLight3D = ball.get_node("BallLight")

	# Один кадр после каждого launch -- намеренно, чтобы гравитация не успела
	# заметно исказить скорость за время замера (на большом числе кадров она
	# меняет модуль velocity достаточно, чтобы смазать сравнение "медленно"/
	# "быстро", как выяснилось на первой версии этого теста).
	ball.launch(Vector3(0.0, 0.5, 0.5)) # почти неподвижен -- минимальная интенсивность
	await physics_frame
	var slow_energy: float = light.light_energy

	ball.launch(Vector3(6.0, 6.0, 6.0)) # быстро -- высокая интенсивность
	await physics_frame
	var fast_energy: float = light.light_energy

	print("slow: energy=%.3f | fast: energy=%.3f" % [slow_energy, fast_energy])
	_ok = _ok and fast_energy > slow_energy


func _check_ribbon_alpha_scales_with_speed(ball: Area3D) -> void:
	print("--- trail ribbon alpha/width scale with the speed_ratio passed in, deterministically ---")

	# Прямой вызов внутренней сборки ленты с фиксированными точками и
	# speed_ratio -- без прогона через физику/гравитацию, чтобы проверить
	# именно формулу (col.a == t * speed_ratio, t=1 у головы), а не таймингом
	# зависимую траекторию (см. _check_light_scales_with_speed выше).
	var points: Array[Vector3] = [Vector3(0, 1, 0), Vector3(0, 1, 1)]
	ball._trail_points = points
	var ribbon: MeshInstance3D = ball.get_node("TrailRibbon")

	ball._rebuild_trail_mesh(0.2)
	var low_alpha: float = _head_alpha(ribbon)

	ball._rebuild_trail_mesh(0.9)
	var high_alpha: float = _head_alpha(ribbon)

	print("speed_ratio=0.2 head_alpha=%.3f | speed_ratio=0.9 head_alpha=%.3f" % [low_alpha, high_alpha])
	_ok = _ok and absf(low_alpha - 0.2) < 0.01
	_ok = _ok and absf(high_alpha - 0.9) < 0.01
	_ok = _ok and high_alpha > low_alpha


func _head_alpha(ribbon: MeshInstance3D) -> float:
	var mesh: ArrayMesh = ribbon.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0.0
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	return colors[0].a if colors.size() > 0 else 0.0


func _check_trail_clears_on_goal_and_relaunch(ball: Area3D) -> void:
	print("--- trail ribbon doesn't keep flashing at the goal spot while the ball waits to respawn ---")

	ball.launch(Vector3(6.0, 6.0, 6.0))
	for i in range(20):
		await physics_frame
	print("before goal: trail points=%d" % ball._trail_points.size())
	_ok = _ok and ball._trail_points.size() > 0 # подтверждает, что след вообще накопился

	# Через ball._score_point(), а не прямой point_scored.emit() -- та же
	# причина, что и в goal_out_test.gd: эмит сигнала напрямую не меняет
	# состояние самого мяча (см. feedback-galaxy-pong-2-workflow).
	ball._score_point("player")
	for i in range(10):
		await physics_frame # мяч "ждёт" следующей подачи -- лента не должна расти
	print("during goal pause: trail points=%d mesh surfaces=%d" % [
		ball._trail_points.size(), ball.get_node("TrailRibbon").mesh.get_surface_count()
	])
	_ok = _ok and ball._trail_points.is_empty()
	_ok = _ok and ball.get_node("TrailRibbon").mesh.get_surface_count() == 0

	ball.position = Vector3.ZERO
	ball.launch(Vector3(0.0, 8.0, 5.0))
	await physics_frame
	print("right after relaunch: trail points=%d" % ball._trail_points.size())
	_ok = _ok and ball._trail_points.size() <= 1 # начинается заново от новой позиции, не тянется со старой

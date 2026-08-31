extends SceneTree

## Регрессия для задачи 6.4 (постобработка): проверяет только то, что можно
## проверить программно — glow/fog/tonemap реально включены в Environment, а
## не просто есть значения "по умолчанию" (которые выглядели бы так же, как
## без этой задачи). Итоговый баланс intensity/threshold/density -- по
## ощущениям, решает пользователь при живом просмотре.
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

	var world_env: WorldEnvironment = main.get_node("WorldEnvironment")
	var env: Environment = world_env.environment

	_check_glow(env)
	_check_fog(env)
	_check_tonemap(env)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_glow(env: Environment) -> void:
	print("--- glow/bloom is enabled with non-zero intensity ---")
	print("glow_enabled=%s glow_intensity=%.2f" % [env.glow_enabled, env.glow_intensity])
	_ok = _ok and env.glow_enabled
	_ok = _ok and env.glow_intensity > 0.0


func _check_fog(env: Environment) -> void:
	print("--- a light fog is enabled, not the default off state ---")
	print("fog_enabled=%s fog_density=%.4f" % [env.fog_enabled, env.fog_density])
	_ok = _ok and env.fog_enabled
	_ok = _ok and env.fog_density > 0.0


func _check_tonemap(env: Environment) -> void:
	print("--- tonemap is set explicitly, not left at the flat default LINEAR ---")
	print("tonemap_mode=%d (expect != %d, LINEAR)" % [env.tonemap_mode, Environment.TONE_MAPPER_LINEAR])
	_ok = _ok and env.tonemap_mode != Environment.TONE_MAPPER_LINEAR

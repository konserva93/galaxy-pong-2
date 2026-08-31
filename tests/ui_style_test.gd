extends SceneTree

## Регрессия для задачи 6.5 (стиль UI): проверяет только то, что можно
## проверить программно — HUD-подписи получили эмуляцию неонового свечения
## (обводка + "тень" с нулевым смещением как ореол), PauseMenu/GameOverScreen
## используют общую неоновую Theme для кнопок и больше не используют плоский
## чёрный фон-затемнение. Как это реально выглядит (читаемость, баланс
## яркости) — решает пользователь при живом просмотре, как и с 4.1/2.1.
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

	_check_hud_glow(main)
	_check_menu_theme_and_background(main, "UI/PauseMenu", Color(0.02, 0.01, 0.05, 0.65))
	_check_menu_theme_and_background(main, "UI/GameOverScreen", Color(0.02, 0.01, 0.05, 0.75))

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_hud_glow(main: Node3D) -> void:
	print("--- HUD score labels emulate a neon glow (outline + zero-offset shadow halo) ---")

	var hud: Control = main.get_node("UI/HUD")
	for label_path in ["TopBar/ScoreRow/PlayerScoreLabel", "TopBar/ScoreRow/AIScoreLabel"]:
		var label: Label = hud.get_node(label_path)
		var outline_size: int = label.get_theme_constant("outline_size")
		var shadow_size: int = label.get_theme_constant("shadow_outline_size")
		var shadow_off_x: int = label.get_theme_constant("shadow_offset_x")
		print("%s outline_size=%d shadow_outline_size=%d shadow_offset_x=%d" % [
			label_path, outline_size, shadow_size, shadow_off_x
		])
		_ok = _ok and outline_size > 0
		_ok = _ok and shadow_size > 0
		_ok = _ok and shadow_off_x == 0 # смещение 0 -- это именно ореол/glow, а не отбрасываемая тень


func _check_menu_theme_and_background(main: Node3D, node_path: String, expected_bg: Color) -> void:
	print("--- %s uses the shared neon button theme and a tinted (not flat black) dim background ---" % node_path)

	var screen: Control = main.get_node(node_path)
	print("theme=%s" % screen.theme)
	_ok = _ok and screen.theme != null
	_ok = _ok and screen.theme.get_stylebox("normal", "Button") != null

	var dim_bg: ColorRect = screen.get_node("DimBackground")
	print("dim_bg.color=%s (expect %s)" % [dim_bg.color, expected_bg])
	_ok = _ok and dim_bg.color.is_equal_approx(expected_bg)
	_ok = _ok and dim_bg.color != Color(0, 0, 0, dim_bg.color.a) # не голый чёрный, как было раньше

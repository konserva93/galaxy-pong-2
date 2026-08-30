extends SceneTree

## Регрессия для подменю "Настройки" внутри PauseMenu (pause_menu.gd):
## - кнопка "Настройки" переключает MainPanel/SettingsPanel, "Назад" -- обратно;
## - контролы синхронизированы с текущими значениями Settings при открытии;
## - изменение контрола реально доходит до Settings (не только меняет вид);
## - закрытие паузы (не через "Назад") сбрасывает меню на MainPanel к
##   следующему открытию, а не оставляет его на подменю настроек.
##
## Чистит settings.cfg (см. settings.gd -- рядом с игрой, в редакторе/тестах
## это корень проекта) в начале/конце -- та же причина, что и в
## settings_test.gd (Settings._ready() грузит с диска при каждом запуске).
##
## Запуск: см. reference-godot-cli в памяти проекта.

var _ok := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	_delete_settings_file(settings)

	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)
	await physics_frame

	var game_manager: Node = root.get_node("GameManager")
	var pause_menu: Control = main.get_node("UI/PauseMenu")

	_check_settings_toggle(game_manager, pause_menu)
	await _check_controls_reflect_and_apply(pause_menu, settings)
	_check_closing_pause_resets_to_main_panel(game_manager, pause_menu)

	_delete_settings_file(settings)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _delete_settings_file(settings: Node) -> void:
	var path: String = settings.settings_file_path()
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _check_settings_toggle(game_manager: Node, pause_menu: Control) -> void:
	print("--- Settings button swaps MainPanel for SettingsPanel, Back swaps it back ---")

	game_manager.toggle_pause()
	var main_panel: Control = pause_menu.get_node("MainPanel")
	var settings_panel: Control = pause_menu.get_node("SettingsPanel")
	print("on open: main=%s settings=%s" % [main_panel.visible, settings_panel.visible])
	_ok = _ok and main_panel.visible and not settings_panel.visible

	pause_menu.get_node("MainPanel/VBoxContainer/SettingsButton").pressed.emit()
	print("after Settings pressed: main=%s settings=%s" % [main_panel.visible, settings_panel.visible])
	_ok = _ok and not main_panel.visible and settings_panel.visible

	pause_menu.get_node("SettingsPanel/VBoxContainer/BackButton").pressed.emit()
	print("after Back pressed: main=%s settings=%s" % [main_panel.visible, settings_panel.visible])
	_ok = _ok and main_panel.visible and not settings_panel.visible

	game_manager.toggle_pause() # обратно в игру, чтобы не мешать следующим проверкам


func _check_controls_reflect_and_apply(pause_menu: Control, settings: Node) -> void:
	print("--- settings controls start synced to Settings, and changing them calls through to Settings ---")

	settings.set_music_volume(0.6)
	settings.set_resolution_index(3)

	pause_menu._sync_settings_controls() # то же самое, что и _ready() -- на реальном открытии паузы уже вызвано один раз

	var resolution_option: OptionButton = pause_menu.get_node("SettingsPanel/VBoxContainer/ResolutionRow/ResolutionOption")
	var music_slider: HSlider = pause_menu.get_node("SettingsPanel/VBoxContainer/MusicRow/MusicSlider")
	print("synced: resolution.selected=%d (expect 3) music_slider.value=%.2f (expect 0.6)" % [
		resolution_option.selected, music_slider.value
	])
	_ok = _ok and resolution_option.selected == 3
	_ok = _ok and is_equal_approx(music_slider.value, 0.6)

	var sfx_slider: HSlider = pause_menu.get_node("SettingsPanel/VBoxContainer/SfxRow/SfxSlider")
	sfx_slider.value = 0.25
	await physics_frame # value_changed -> Settings.set_sfx_volume, дать сигналу дойти
	print("after moving SFX slider to 0.25: Settings.sfx_volume=%.2f" % settings.sfx_volume)
	_ok = _ok and is_equal_approx(settings.sfx_volume, 0.25)


func _check_closing_pause_resets_to_main_panel(game_manager: Node, pause_menu: Control) -> void:
	print("--- closing pause (not via Back) resets the menu to MainPanel for next time ---")

	var main_panel: Control = pause_menu.get_node("MainPanel")
	var settings_panel: Control = pause_menu.get_node("SettingsPanel")

	game_manager.toggle_pause() # открыть
	pause_menu.get_node("MainPanel/VBoxContainer/SettingsButton").pressed.emit()
	_ok = _ok and settings_panel.visible

	game_manager.toggle_pause() # закрыть -- не через "Назад"
	print("after closing pause while on settings: main.visible=%s settings.visible=%s" % [
		main_panel.visible, settings_panel.visible
	])
	_ok = _ok and main_panel.visible and not settings_panel.visible

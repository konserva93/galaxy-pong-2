extends SceneTree

## Регрессия для autoload Settings (подменю "Настройки" в паузе):
## - значения по умолчанию (когда settings.cfg ещё нет);
## - set_* сразу применяет (аудио-шины Music/SFX) и сохраняет на диск;
## - сохранённые значения переживают "перезапуск" (свежая загрузка ConfigFile
##   с диска даёт то же самое, что было сохранено).
##
## Файл (см. settings.gd -- рядом с игрой, в редакторе/тестах это корень
## проекта) чистится за собой в начале и в конце -- иначе прогон этого теста
## оставлял бы его, искажая значения по умолчанию, которые подхватит
## следующий запуск headless-тестов (Settings._ready() грузит с диска при
## старте КАЖДОГО процесса godot, включая другие тесты).
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

	_check_defaults(settings)
	_check_resolution_and_fullscreen(settings)
	_check_volume_applies_to_bus(settings)
	_check_persists_to_disk(settings)

	_delete_settings_file(settings)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _delete_settings_file(settings: Node) -> void:
	var path: String = settings.settings_file_path()
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _check_defaults(settings: Node) -> void:
	print("--- defaults when no settings.cfg exists yet: full volume, windowed, first resolution ---")
	print("resolution_index=%d fullscreen=%s music=%.2f sfx=%.2f" % [
		settings.resolution_index, settings.fullscreen, settings.music_volume, settings.sfx_volume
	])
	_ok = _ok and settings.resolution_index == 0
	_ok = _ok and settings.fullscreen == false
	_ok = _ok and is_equal_approx(settings.music_volume, 1.0)
	_ok = _ok and is_equal_approx(settings.sfx_volume, 1.0)


func _check_resolution_and_fullscreen(settings: Node) -> void:
	print("--- set_resolution_index/set_fullscreen update state and clamp out-of-range indices ---")

	settings.set_resolution_index(2)
	_ok = _ok and settings.resolution_index == 2

	settings.set_resolution_index(999) # за пределами RESOLUTIONS -- должно clamp'иться, не упасть
	print("out-of-range index clamped to %d (expect last valid, %d)" % [
		settings.resolution_index, settings.RESOLUTIONS.size() - 1
	])
	_ok = _ok and settings.resolution_index == settings.RESOLUTIONS.size() - 1

	settings.set_fullscreen(true)
	_ok = _ok and settings.fullscreen == true
	settings.set_fullscreen(false)
	_ok = _ok and settings.fullscreen == false


func _check_volume_applies_to_bus(settings: Node) -> void:
	print("--- set_music_volume/set_sfx_volume actually change the AudioServer bus, not just the stored value ---")

	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	_ok = _ok and music_bus != -1
	_ok = _ok and sfx_bus != -1
	if music_bus == -1 or sfx_bus == -1:
		return

	settings.set_music_volume(0.5)
	var half_db := AudioServer.get_bus_volume_db(music_bus)
	print("music_volume=0.5 -> bus volume_db=%.2f mute=%s" % [half_db, AudioServer.is_bus_mute(music_bus)])
	_ok = _ok and half_db < 0.0 # тише, чем 0дБ по умолчанию
	_ok = _ok and not AudioServer.is_bus_mute(music_bus)

	settings.set_music_volume(0.0)
	print("music_volume=0.0 -> mute=%s (expect true)" % AudioServer.is_bus_mute(music_bus))
	_ok = _ok and AudioServer.is_bus_mute(music_bus)

	settings.set_sfx_volume(1.0)
	print("sfx_volume=1.0 -> bus volume_db=%.2f mute=%s" % [
		AudioServer.get_bus_volume_db(sfx_bus), AudioServer.is_bus_mute(sfx_bus)
	])
	_ok = _ok and is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), 0.0)
	_ok = _ok and not AudioServer.is_bus_mute(sfx_bus)


func _check_persists_to_disk(settings: Node) -> void:
	print("--- settings written by set_* survive a fresh ConfigFile load from disk ---")

	settings.set_resolution_index(1)
	settings.set_fullscreen(true)
	settings.set_music_volume(0.4)
	settings.set_sfx_volume(0.8)

	var config := ConfigFile.new()
	var load_result := config.load(settings.settings_file_path())
	print("reload from disk: load_result=%d" % load_result)
	_ok = _ok and load_result == OK
	if load_result != OK:
		return

	var loaded_resolution: int = config.get_value("display", "resolution_index", -1)
	var loaded_fullscreen: bool = config.get_value("display", "fullscreen", false)
	var loaded_music: float = config.get_value("audio", "music_volume", -1.0)
	var loaded_sfx: float = config.get_value("audio", "sfx_volume", -1.0)
	print("loaded: resolution_index=%d fullscreen=%s music=%.2f sfx=%.2f" % [
		loaded_resolution, loaded_fullscreen, loaded_music, loaded_sfx
	])
	_ok = _ok and loaded_resolution == 1
	_ok = _ok and loaded_fullscreen == true
	_ok = _ok and is_equal_approx(loaded_music, 0.4)
	_ok = _ok and is_equal_approx(loaded_sfx, 0.8)

extends Node

## Настройки экрана/звука (подменю "Настройки" в паузе). Autoload -- применяет
## сохранённые значения при старте игры (до того, как AmbientMusic заиграет
## в main.gd), и сразу же и сохраняет, и применяет любое новое значение, без
## отдельной кнопки "Применить".
##
## Разрешение -- это размер ОКНА, не внутреннее разрешение рендера: сцена и
## так масштабируется через window/stretch (canvas_items/expand, см.
## project.godot, задача 0.2), так что смена размера окна ничего не искажает.
## В fullscreen ОС всё равно берёт нативное разрешение монитора -- пункт
## разрешения в этом случае значения не имеет, но остаётся доступным (просто
## возьмётся при следующем переключении в оконный режим).

const SETTINGS_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var resolution_index: int = 0
var fullscreen: bool = false
var music_volume: float = 1.0 # линейно, 0..1
var sfx_volume: float = 1.0 # линейно, 0..1


func _ready() -> void:
	_load()
	_apply_window()
	_apply_bus_volume(MUSIC_BUS, music_volume)
	_apply_bus_volume(SFX_BUS, sfx_volume)


func set_resolution_index(index: int) -> void:
	resolution_index = clampi(index, 0, RESOLUTIONS.size() - 1)
	_apply_window()
	_save()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_window()
	_save()


func set_music_volume(linear: float) -> void:
	music_volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(MUSIC_BUS, music_volume)
	_save()


func set_sfx_volume(linear: float) -> void:
	sfx_volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(SFX_BUS, sfx_volume)
	_save()


func _apply_window() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if not fullscreen:
		DisplayServer.window_set_size(RESOLUTIONS[resolution_index])
		var screen_size := DisplayServer.screen_get_size()
		var window_size := DisplayServer.window_get_size()
		DisplayServer.window_set_position((screen_size - window_size) / 2)


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		push_warning("Settings: аудио-шина '%s' не найдена в default_bus_layout" % bus_name)
		return
	# 0 -> явный mute, а не -inf дБ -- надёжнее полной тишины на глаз/на слух
	# и не зависит от того, как AudioServer обрабатывает -inf на разных бэкендах.
	AudioServer.set_bus_mute(bus_index, linear <= 0.0001)
	if linear > 0.0001:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "resolution_index", resolution_index)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.save(SETTINGS_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return # первый запуск / файла ещё нет -- остаёмся на значениях по умолчанию

	resolution_index = clampi(
		config.get_value("display", "resolution_index", resolution_index), 0, RESOLUTIONS.size() - 1
	)
	fullscreen = config.get_value("display", "fullscreen", fullscreen)
	music_volume = clampf(config.get_value("audio", "music_volume", music_volume), 0.0, 1.0)
	sfx_volume = clampf(config.get_value("audio", "sfx_volume", sfx_volume), 0.0, 1.0)

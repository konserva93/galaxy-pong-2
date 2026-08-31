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
##
## Файл настроек — рядом с самой игрой (папка с .exe), не в системном профиле
## пользователя (%APPDATA%/... на Windows) — так попросил пользователь.
## OS.has_feature("editor") истинно при любом запуске через сам редактор
## (обычный Play, headless-скрипты/тесты — вообще всё, кроме реально
## экспортированной игры), для этих случаев "рядом с игрой" — корень проекта.

## Кандидаты на список разрешений -- не обязательно то, что реально
## показывается: см. _compute_available_resolutions() -- убирает варианты
## крупнее нативного разрешения монитора и добавляет само нативное, если его
## нет среди кандидатов.
const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

## main.gd слушает это, чтобы проиграть звук удара весла как живое превью
## новой громкости эффектов -- отдельного превью для музыки не нужно: она,
## в отличие от SFX, играет непрерывно и так (см. process_mode на "Audio" в
## Main.tscn), новую громкость слышно сразу без специального сигнала.
signal sfx_previewed

## Реальный список для выпадающего меню -- вычисляется один раз в _ready()
## (до _load(), т.к. resolution_index клампится по его размеру). pause_menu.gd
## строит пункты OptionButton по этому массиву, не по RESOLUTION_PRESETS
## напрямую.
var available_resolutions: Array[Vector2i] = []

var resolution_index: int = 0
var fullscreen: bool = false
var music_volume: float = 1.0 # линейно, 0..1
var sfx_volume: float = 1.0 # линейно, 0..1

var _settings_path: String = ""


func _ready() -> void:
	_settings_path = _resolve_settings_path()
	available_resolutions = _compute_available_resolutions()
	_load()
	_apply_window()
	_apply_bus_volume(MUSIC_BUS, music_volume)
	_apply_bus_volume(SFX_BUS, sfx_volume)


func _compute_available_resolutions() -> Array[Vector2i]:
	return _filter_resolutions_for_native(DisplayServer.screen_get_size())


## Отбрасывает пресеты крупнее нативного разрешения монитора (по любой оси --
## показывать вариант, для которого окно не влезет на экран, бессмысленно) и
## добавляет само нативное, если оно не совпадает ни с одним из оставшихся --
## по прямому запросу. Принимает native параметром (не читает DisplayServer
## сама), чтобы регрессионный тест мог проверить саму логику фильтрации с
## разными "мониторами" без реального экрана.
##
## native <= 0 по любой оси (DisplayServer.screen_get_size() в headless-
## контексте — тесты, --headless без реального экрана — возвращает (0, 0)) --
## нет достоверных данных о мониторе, фильтрация ничего не даёт, кроме потери
## всего списка, так что отдаём пресеты как есть.
func _filter_resolutions_for_native(native: Vector2i) -> Array[Vector2i]:
	if native.x <= 0 or native.y <= 0:
		return RESOLUTION_PRESETS.duplicate()

	var result: Array[Vector2i] = []
	var native_included := false
	for preset in RESOLUTION_PRESETS:
		if preset.x > native.x or preset.y > native.y:
			continue
		result.append(preset)
		if preset == native:
			native_included = true

	if not native_included:
		result.append(native)
		result.sort_custom(_by_area_ascending)

	return result


func _by_area_ascending(a: Vector2i, b: Vector2i) -> bool:
	return a.x * a.y < b.x * b.y


## Путь к settings.cfg -- открыт (не приватный), чтобы регрессионные тесты
## могли явно чистить файл за собой без хардкода пути в двух местах.
func settings_file_path() -> String:
	return _settings_path


func _resolve_settings_path() -> String:
	var dir: String
	if OS.has_feature("editor"):
		dir = ProjectSettings.globalize_path("res://")
	else:
		dir = OS.get_executable_path().get_base_dir()
	return dir.path_join("settings.cfg")


func set_resolution_index(index: int) -> void:
	resolution_index = clampi(index, 0, available_resolutions.size() - 1)
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
	sfx_previewed.emit()


func _apply_window() -> void:
	# В редакторе игра часто запускается во встроенном окне (Debug > Embed
	# Game Window, включено по умолчанию в новых версиях Godot) -- им нельзя
	# управлять из самой игры, DisplayServer тут же и без пользы шлёт в лог
	# "Embedded window can't be resized/moved". В реальном билде (и в обычном
	# отдельном окне редактора) get_window() не embedded, и ветка ниже
	# отрабатывает как обычно.
	var window := get_window()
	if window != null and window.is_embedded():
		return

	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if not fullscreen:
		DisplayServer.window_set_size(available_resolutions[resolution_index])
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
	config.save(_settings_path)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(_settings_path) != OK:
		return # первый запуск / файла ещё нет -- остаёмся на значениях по умолчанию

	resolution_index = clampi(
		config.get_value("display", "resolution_index", resolution_index), 0, available_resolutions.size() - 1
	)
	fullscreen = config.get_value("display", "fullscreen", fullscreen)
	music_volume = clampf(config.get_value("audio", "music_volume", music_volume), 0.0, 1.0)
	sfx_volume = clampf(config.get_value("audio", "sfx_volume", sfx_volume), 0.0, 1.0)

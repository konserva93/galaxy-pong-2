extends SceneTree

## Регрессия для задачи 5.1 (подготовка звуковых файлов): проверяет, что все
## три звуковых файла импортированы и загружаются как AudioStreamWAV с
## разумной длительностью и частотой дискретизации. paddle_hit/goal —
## сгенерированные плейсхолдеры (Python, см. историю); ambient_sound_of_galaxy
## — реальный файл, добавленный пользователем взамен сгенерированного лупа
## (был `ambient_loop.wav`, 8с/44100Hz моно — заменён по прямому запросу).
##
## Зацикливание эмбиента сюда НЕ входит: ручная правка `loop_mode` в
## `.wav.import` через headless CLI (без реального открытия импорт-дока в
## редакторе) не долетала до итогового ресурса при загрузке -- надёжно
## воспроизводимо оказалось только выставление `AudioStreamWAV.loop_mode` в
## коде при настройке плеера, поэтому это отложено на задачу 5.2 (там и тест
## на зацикливание).
##
## Запуск: см. reference-godot-cli в памяти проекта.

var _ok := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sfx("res://audio/paddle_hit.wav", 0.08, 0.20, 44100)
	_check_sfx("res://audio/goal.wav", 0.35, 0.65, 44100)
	_check_sfx("res://audio/ambient_sound_of_galaxy.wav", 5.0, 60.0, 48000)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_sfx(path: String, min_len: float, max_len: float, expected_mix_rate: int) -> void:
	var stream: AudioStreamWAV = load(path)
	var loaded := stream != null
	print("%s: loaded=%s" % [path, loaded])
	_ok = _ok and loaded
	if not loaded:
		return

	var length: float = stream.get_length()
	print("  length=%.3fs mix_rate=%d (expect %.2f..%.2fs, %dHz)" % [length, stream.mix_rate, min_len, max_len, expected_mix_rate])
	_ok = _ok and length >= min_len and length <= max_len
	_ok = _ok and stream.mix_rate == expected_mix_rate

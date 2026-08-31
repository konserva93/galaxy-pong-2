extends SceneTree

## Регрессия для задачи 5.2 (подключение звука, main.gd):
## - удар веслом (ball.paddle_hit) запускает PaddleHitSound;
## - очко (ball.point_scored) запускает GoalSound, независимо от победителя;
## - фоновая музыка (AmbientMusic) запускается и РЕАЛЬНО зацикливается ПОСЛЕ
##   естественного конца клипа (длина берётся из самого файла, сейчас это
##   `ambient_sound_of_galaxy.wav`), а не просто молчит после первого прохода;
## - относительная громкость: фоновая музыка тише SFX (GameDesign 7 —
##   "негромкая" эмбиент-музыка).
##
## Регрессия конкретного бага ("не слышу эмбиент в процессе игры", остальные
## звуки работают): AudioStreamPlayer.autoplay=true в сцене запускал
## AmbientMusic ДО того, как main.gd._ready() успевал выставить
## AudioStreamWAV.loop_mode -- дочерние узлы получают _ready() раньше
## родителя, так что autoplay стартовал с loop_mode ресурса ещё "как
## импортировано" (Disabled), и смена loop_mode на уже идущее проигрывание не
## влияла -- луп доигрывал первые 8 секунд и замолкал на всю оставшуюся
## партию. Дополнительно: одного loop_mode=Forward было недостаточно --
## loop_end по умолчанию 0 (пустой диапазон), нужно было явно выставить его в
## сэмплах. Фикс: play() вызывается из main.gd ПОСЛЕ настройки loop_mode/
## loop_begin/loop_end, autoplay сцены убран.
##
## Запуск: см. reference-godot-cli в памяти проекта. Этот тест реально ждёт
## чуть больше длины эмбиент-клипа по настоящему времени (аудио
## синхронизировано с реальным временем, не с физическими тиками) — дольше
## остальных тестов, но это
## единственный надёжный способ поймать регресс именно этого бага.

var _ok := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var ball: Area3D = main.get_node("Ball")
	var game_manager: Node = root.get_node("GameManager")
	var paddle_hit_sound: AudioStreamPlayer = main.get_node("Audio/PaddleHitSound")
	var goal_sound: AudioStreamPlayer = main.get_node("Audio/GoalSound")
	var ambient_music: AudioStreamPlayer = main.get_node("Audio/AmbientMusic")
	# Тест сам вызывает ball._score_point() напрямую -- отключаем реальный
	# GameManager, чтобы пауза/подача после гола не мешали (тот же приём, что
	# и в других тестах, работающих с ball напрямую).
	if ball.point_scored.is_connected(game_manager.register_point):
		ball.point_scored.disconnect(game_manager.register_point)

	_check_ambient_playing_and_loop_configured(ambient_music)
	await _check_paddle_hit_plays_sound(ball, paddle_hit_sound)
	await _check_point_scored_plays_sound(ball, goal_sound)
	_check_relative_volume(paddle_hit_sound, goal_sound, ambient_music)
	await _check_ambient_actually_loops_past_clip_end(ambient_music)
	await _check_music_keeps_playing_while_paused(game_manager, ambient_music)

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_ambient_playing_and_loop_configured(ambient_music: AudioStreamPlayer) -> void:
	print("--- ambient music is playing and its stream is configured to loop ---")

	print("ambient_music: playing=%s stream=%s" % [ambient_music.playing, ambient_music.stream])
	_ok = _ok and ambient_music.playing
	_ok = _ok and ambient_music.stream is AudioStreamWAV
	if ambient_music.stream is AudioStreamWAV:
		var stream: AudioStreamWAV = ambient_music.stream
		print("loop_mode=%d (expect %d) loop_begin=%d loop_end=%d (expect > 0)" % [stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, stream.loop_begin, stream.loop_end])
		_ok = _ok and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
		_ok = _ok and stream.loop_end > 0


func _check_paddle_hit_plays_sound(ball: Area3D, paddle_hit_sound: AudioStreamPlayer) -> void:
	print("--- ball.paddle_hit -> PaddleHitSound.play() ---")

	_ok = _ok and not paddle_hit_sound.playing
	ball.paddle_hit.emit()
	await process_frame
	print("after paddle_hit emit: playing=%s" % paddle_hit_sound.playing)
	_ok = _ok and paddle_hit_sound.playing


func _check_point_scored_plays_sound(ball: Area3D, goal_sound: AudioStreamPlayer) -> void:
	print("--- ball.point_scored -> GoalSound.play(), for either winner ---")

	_ok = _ok and not goal_sound.playing
	ball.launch(Vector3(0.0, 8.0, -5.0))
	ball._score_point("player")
	await process_frame
	print("after point_scored('player'): playing=%s" % goal_sound.playing)
	_ok = _ok and goal_sound.playing

	goal_sound.stop()
	ball.launch(Vector3(0.0, 8.0, 5.0))
	ball._score_point("ai")
	await process_frame
	print("after point_scored('ai'): playing=%s" % goal_sound.playing)
	_ok = _ok and goal_sound.playing


func _check_relative_volume(paddle_hit_sound: AudioStreamPlayer, goal_sound: AudioStreamPlayer, ambient_music: AudioStreamPlayer) -> void:
	print("--- ambient music is quieter than the SFX (GameDesign 7: 'негромкая') ---")

	print("volume_db: hit=%.1f goal=%.1f ambient=%.1f" % [paddle_hit_sound.volume_db, goal_sound.volume_db, ambient_music.volume_db])
	_ok = _ok and ambient_music.volume_db < paddle_hit_sound.volume_db
	_ok = _ok and ambient_music.volume_db < goal_sound.volume_db


func _check_ambient_actually_loops_past_clip_end(ambient_music: AudioStreamPlayer) -> void:
	print("--- ambient music is still playing (looped) past its own clip length ---")

	var clip_length: float = ambient_music.stream.get_length()
	var start_ms := Time.get_ticks_msec()
	var wait_seconds: float = clip_length + 0.5
	while (Time.get_ticks_msec() - start_ms) / 1000.0 < wait_seconds:
		await process_frame

	print("after %.1fs (clip is %.1fs): playing=%s playback_position=%.2f (expect true, wrapped near 0, not stuck at end)" % [wait_seconds, clip_length, ambient_music.playing, ambient_music.get_playback_position()])
	_ok = _ok and ambient_music.playing
	_ok = _ok and ambient_music.get_playback_position() < clip_length * 0.5


func _check_music_keeps_playing_while_paused(game_manager: Node, ambient_music: AudioStreamPlayer) -> void:
	print("--- ambient music keeps playing while paused (menu should stay audible), not frozen by get_tree().paused ---")

	game_manager.toggle_pause()
	var position_at_pause: float = ambient_music.get_playback_position()

	var start_ms := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start_ms) / 1000.0 < 0.3:
		await process_frame

	print("while paused: playing=%s position_before=%.3f position_after=%.3f" % [
		ambient_music.playing, position_at_pause, ambient_music.get_playback_position()
	])
	_ok = _ok and ambient_music.playing
	_ok = _ok and ambient_music.get_playback_position() > position_at_pause

	game_manager.toggle_pause() # снять паузу, не оставлять дерево замороженным на выходе

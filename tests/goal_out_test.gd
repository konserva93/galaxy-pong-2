extends SceneTree

## Регрессия для детекции гола/аута в ball.gd (задача 1.6, см. GameDesign 3.4):
## - касание пола на своей/чужой половине начисляет очко правильной стороне;
## - аут по X и по Z штрафует последнего отбившего, а не привязан к тому,
##   на чьей половине мяч вышел за границы;
## - аут БЕЗ единого удара за розыгрыш (например, не приняли подачу) всё
##   равно начисляет очко (по правилу "чья половина" — как при касании пола),
##   а не оставляет мяч без начисления — раньше это был баг: розыгрыш мог
##   никогда не завершиться, мяч просто улетал навсегда;
## - сигнал point_scored не срабатывает повторно в рамках одного розыгрыша;
## - сигнал доходит до GameManager.register_point;
## - когда мяч ОДНОВРЕМЕННО (в один и тот же физический тик) уже вне границ
##   поля и пересекает пол -- побеждает правило аута (штраф отбившему), а не
##   правило "чья половина" (которое в этом случае наградило бы именно того,
##   кто выбил мяч за пределы). Регрессия конкретного бага: пол проверялся
##   раньше аута и не знал о границах поля ("бесконечный пол"), так что мяч,
##   уже улетевший за пределы, но всё ещё падающий под гравитацией, рано или
##   поздно пересекал Y=0 и засчитывался по правилу половины.
##
## Запуск: см. reference-godot-cli в памяти проекта.

var _ok := true
var _received: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _on_point(winner: String) -> void:
	_received.append(winner)


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var ball: Area3D = main.get_node("Ball")
	var game_manager: Node = root.get_node("GameManager")
	ball.point_scored.connect(_on_point)

	# Мяч у самого пола, чтобы пересечь Y=0 за один физический тик.
	ball.position = Vector3(0.0, 0.05, 3.0) # своя половина игрока
	ball.velocity = Vector3(0.0, -4.0, 0.0)
	_received.clear()
	await physics_frame
	print("[floor, player half] received=%s GameManager.ai_score=%d" % [_received, game_manager.ai_score])
	_ok = _ok and _received == ["ai"]
	_ok = _ok and game_manager.ai_score == 1

	ball.launch(Vector3(0.0, -4.0, 0.0)) # launch() сбрасывает состояние розыгрыша
	ball.position = Vector3(0.0, 0.05, -3.0) # половина AI
	_received.clear()
	await physics_frame
	print("[floor, ai half] received=%s" % [_received])
	_ok = _ok and _received == ["player"]

	ball.launch(Vector3(10.0, 0.0, 0.0))
	ball.position = Vector3(0.0, 3.0, 5.0)
	ball._last_hitter_side = "player"
	_received.clear()
	ball.position.x = 6.0 # за пределы field_width/2=5
	await physics_frame
	print("[out via X, last hitter player] received=%s" % [_received])
	_ok = _ok and _received == ["ai"]

	ball.launch(Vector3(0.0, 0.0, -10.0))
	ball.position = Vector3(0.0, 3.0, 0.0)
	ball._last_hitter_side = "ai"
	_received.clear()
	ball.position.z = -9.0 # за пределы field_length/2=8
	await physics_frame
	print("[out via Z, last hitter ai] received=%s" % [_received])
	_ok = _ok and _received == ["player"]

	# Аут без единого удара -- не должен зависать без результата: очко по
	# правилу "чья половина" (мяч на положительной Z, половине игрока -> AI).
	ball.launch(Vector3(0.0, 0.0, 0.0))
	ball.position = Vector3(0.0, 3.0, 5.0)
	_received.clear()
	ball.position.x = 6.0
	await physics_frame
	print("[out, no hitter yet -> falls back to half-based rule] received=%s (expect ['ai'])" % [_received])
	_ok = _ok and _received == ["ai"]

	ball.launch(Vector3(0.0, -4.0, 0.0))
	ball.position = Vector3(0.0, 0.05, 3.0)
	_received.clear()
	for i in range(10):
		await physics_frame
	print("[no double-score over 10 frames] received=%s (expect exactly 1 entry)" % [_received])
	_ok = _ok and _received.size() == 1

	# Мяч уже за пределами поля по Z (AI-половина, z<0) И одновременно
	# пересекает пол в этом же тике. Правило половины наградило бы "player"
	# (мяч упал на половине AI) -- но выбивший его за пределы (player) должен
	# получить ШТРАФ, очко сопернику ("ai"). Это и есть тот самый баг.
	ball.launch(Vector3(0.0, -4.0, 0.0))
	ball.position = Vector3(0.0, 0.05, -8.5) # уже вне |z|<=field_length/2=8, и y пересечёт 0 в этот же тик
	ball._last_hitter_side = "player"
	_received.clear()
	await physics_frame
	print("[out+floor same tick, last hitter player] received=%s (expect ['ai'] -- out-of-bounds penalty, not the half-based rule)" % [_received])
	_ok = _ok and _received == ["ai"]

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)

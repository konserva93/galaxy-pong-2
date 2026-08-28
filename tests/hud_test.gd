extends SceneTree

## Регрессия для hud.gd/HUD.tscn (задача 4.1):
## - при старте показывает текущий счёт GameManager (обычно 0:0);
## - подписан на GameManager.score_changed и обновляет оба лейбла при любом
##   изменении счёта, независимо от того, чьё это очко.
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
	await physics_frame

	var game_manager: Node = root.get_node("GameManager")
	var hud: Control = main.get_node("UI/HUD")
	var player_label: Label = hud.get_node("TopBar/ScoreRow/PlayerScoreLabel")
	var ai_label: Label = hud.get_node("TopBar/ScoreRow/AIScoreLabel")

	print("--- initial HUD reflects starting score ---")
	print("player_label=%s ai_label=%s (expect %d:%d)" % [player_label.text, ai_label.text, game_manager.player_score, game_manager.ai_score])
	_ok = _ok and player_label.text == str(game_manager.player_score)
	_ok = _ok and ai_label.text == str(game_manager.ai_score)

	print("--- HUD updates when AI scores ---")
	game_manager.register_point("ai")
	await physics_frame
	print("player_label=%s ai_label=%s (expect 0:1)" % [player_label.text, ai_label.text])
	_ok = _ok and player_label.text == "0"
	_ok = _ok and ai_label.text == "1"

	print("--- HUD updates when player scores ---")
	game_manager.register_point("player")
	await physics_frame
	print("player_label=%s ai_label=%s (expect 1:1)" % [player_label.text, ai_label.text])
	_ok = _ok and player_label.text == "1"
	_ok = _ok and ai_label.text == "1"

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)

extends Control

## Экран окончания игры: текст победителя, кнопки «Рестарт»/«Выход» (задача
## 4.3). Появляется по GameManager.game_over(winner). process_mode = Always
## (см. .tscn) — как и PauseMenu, должен реагировать на ввод, пока
## GameManager держит get_tree().paused=true на время game over.

@onready var _winner_label: Label = $CenterContainer/VBoxContainer/WinnerLabel
@onready var _restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var _exit_button: Button = $CenterContainer/VBoxContainer/ExitButton


func _ready() -> void:
	visible = false
	GameManager.game_over.connect(_on_game_over)
	# Скрываемся по restart_requested, а не напрямую в _on_restart_pressed() —
	# так экран остаётся синхронизирован с реальным состоянием GameManager,
	# даже если рестарт когда-нибудь будет запущен не только через эту кнопку/
	# хоткей (restart_requested — часть restart_game(), см. game_manager.gd).
	GameManager.restart_requested.connect(_on_restart_requested)
	_restart_button.pressed.connect(_on_restart_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	# Дублирование рестарта горячей клавишей Space/Enter ("restart" в Input Map).
	if visible and event.is_action_pressed("restart"):
		_on_restart_pressed()


func _on_game_over(winner: String) -> void:
	_winner_label.text = "Ты выиграл!" if winner == "player" else "AI выиграл"
	visible = true


func _on_restart_requested() -> void:
	visible = false


func _on_restart_pressed() -> void:
	GameManager.restart_game()


func _on_exit_pressed() -> void:
	get_tree().quit()

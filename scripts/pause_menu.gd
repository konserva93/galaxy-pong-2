extends Control

## Меню паузы: видимость привязана к GameManager.state_changed ("Paused"/
## "Playing" — GameManager.toggle_pause() открывает/закрывает по Esc).
## process_mode = Always (см. .tscn) — этот узел и его кнопки должны получать
## ввод, пока get_tree().paused=true останавливает остальную игру.

@onready var _continue_button: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var _exit_button: Button = $CenterContainer/VBoxContainer/ExitButton


func _ready() -> void:
	visible = false
	GameManager.state_changed.connect(_on_state_changed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)


func _on_state_changed(new_state: String) -> void:
	visible = new_state == "Paused"


func _on_continue_pressed() -> void:
	GameManager.toggle_pause()


func _on_exit_pressed() -> void:
	get_tree().quit()

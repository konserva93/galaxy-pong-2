extends Control

## Меню паузы: видимость привязана к GameManager.state_changed ("Paused"/
## "Playing" — GameManager.toggle_pause() открывает/закрывает по Esc).
## process_mode = Always (см. .tscn) — этот узел и его кнопки должны получать
## ввод, пока get_tree().paused=true останавливает остальную игру.
##
## Подменю "Настройки" (SettingsPanel) — не отдельный экран, а второй набор
## контролов внутри этой же сцены: MainPanel/SettingsPanel показываются по
## очереди, само меню паузы (visible) при этом не трогается. Значения читает/
## пишет через autoload Settings (см. scripts/settings.gd) — он же применяет
## их немедленно и сохраняет на диск, здесь только синхронизация контролов.

@onready var _main_panel: Control = $MainPanel
@onready var _continue_button: Button = $MainPanel/VBoxContainer/ContinueButton
@onready var _settings_button: Button = $MainPanel/VBoxContainer/SettingsButton
@onready var _exit_button: Button = $MainPanel/VBoxContainer/ExitButton

@onready var _settings_panel: Control = $SettingsPanel
@onready var _resolution_option: OptionButton = $SettingsPanel/VBoxContainer/ResolutionRow/ResolutionOption
@onready var _fullscreen_check: Button = $SettingsPanel/VBoxContainer/FullscreenRow/FullscreenCheck
@onready var _music_slider: HSlider = $SettingsPanel/VBoxContainer/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $SettingsPanel/VBoxContainer/SfxRow/SfxSlider
@onready var _back_button: Button = $SettingsPanel/VBoxContainer/BackButton


func _ready() -> void:
	visible = false
	GameManager.state_changed.connect(_on_state_changed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_back_button.pressed.connect(_on_back_pressed)

	_populate_resolution_options()
	_sync_settings_controls()
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)


func _on_state_changed(new_state: String) -> void:
	visible = new_state == "Paused"
	if not visible:
		# Закрыли паузу целиком (не кнопкой "Назад" из настроек) -- в
		# следующий раз меню должно открыться с главного экрана, а не
		# оставаться на подменю настроек.
		_show_main_panel()


func _on_continue_pressed() -> void:
	GameManager.toggle_pause()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_settings_pressed() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true


func _on_back_pressed() -> void:
	_show_main_panel()


func _show_main_panel() -> void:
	_settings_panel.visible = false
	_main_panel.visible = true


func _populate_resolution_options() -> void:
	_resolution_option.clear()
	for resolution in Settings.available_resolutions:
		_resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])


func _sync_settings_controls() -> void:
	_resolution_option.selected = Settings.resolution_index
	_fullscreen_check.button_pressed = Settings.fullscreen
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume


func _on_resolution_selected(index: int) -> void:
	Settings.set_resolution_index(index)


func _on_fullscreen_toggled(enabled: bool) -> void:
	Settings.set_fullscreen(enabled)


func _on_music_volume_changed(value: float) -> void:
	Settings.set_music_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	Settings.set_sfx_volume(value)

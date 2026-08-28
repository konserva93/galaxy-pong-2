extends Control

## HUD: счёт игрока/AI сверху по центру (см. GameDesign 4.1/6). Подписывается
## напрямую на GameManager.score_changed — не требует проводки через main.gd.
## Цвета цифр — те же временные placeholder-цвета, что и у вёсел (циан у
## игрока, розово-оранжевый у AI), для согласованности до финального неонового
## визуала (этап 6).

@onready var _player_score_label: Label = $TopBar/ScoreRow/PlayerScoreLabel
@onready var _ai_score_label: Label = $TopBar/ScoreRow/AIScoreLabel


func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	_on_score_changed(GameManager.player_score, GameManager.ai_score)


func _on_score_changed(player_score: int, ai_score: int) -> void:
	_player_score_label.text = str(player_score)
	_ai_score_label.text = str(ai_score)

extends Node

## Autoload: игровое состояние, счёт, сигналы игрового цикла.
## Наполняется в этапе 1 (Greybox-прототип).

signal score_changed(player_score: int, ai_score: int)
signal game_over(winner: String)
signal state_changed(new_state: String)

const SCORE_TO_WIN: int = 7


## Принимает сигнал ball.point_scored (задача 1.6: детекция гола/аута).
## Настоящее хранение счёта, score_changed и проверка SCORE_TO_WIN —
## задача 1.7; пока только фиксируем последнего получившего очко.
var last_point_winner: String = ""


func register_point(winner: String) -> void:
	last_point_winner = winner

extends Node

## Autoload: игровое состояние, счёт, сигналы игрового цикла.
## Наполняется в этапе 1 (Greybox-прототип).

signal score_changed(player_score: int, ai_score: int)
signal game_over(winner: String)
signal state_changed(new_state: String)

const SCORE_TO_WIN: int = 7

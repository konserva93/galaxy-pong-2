extends Area3D

## Мяч: баллистическое движение (парабола) — гравитация действует на vy,
## позиция обновляется по velocity * delta. Отбивание веслом, гол/аут — ниже.
##
## Отбитие засчитывается, когда Y мяча пересекает paddle_hit_height весла и
## его XZ-позиция в этот момент попадает в площадь весла (см. GameDesign 3.3).
## Вёсла ищутся по группе "paddles", чтобы работать одинаково и с игроком, и
## с AI без изменений в этом скрипте.
##
## Гол засчитывается (см. GameDesign 3.4), когда:
## - мяч коснулся пола (Y=0) — вне зависимости от того, был он до этого отбит
##   или нет, очко получает сторона, ПРОТИВОПОЛОЖНАЯ той половине, где мяч
##   упал (упал на своей половине без отбития — очко сопернику; упал на
##   половине соперника после отбития — очко бьющему; правило одно и то же
##   для обоих случаев, отдельно их различать не нужно);
## - мяч улетел за пределы поля по X или Z, не задев ни пол, ни весло — очко
##   получает соперник последнего, кто отбивал мяч (аут = штраф бьющему,
##   поэтому здесь важно именно кто бил последним, а не где мяч вышел).
##
## Реальные хранение счёта/подача после гола — в GameManager, задача 1.7;
## здесь только детекция и сигнал point_scored.

@export var ball_gravity: float = -20.0
@export var ball_launch_vy: float = 8.0
@export var ball_hit_forward_speed: float = 8.0
@export var ball_hit_horizontal_factor: float = 3.0
@export var paddle_velocity_influence: float = 0.5
@export_node_path("Node3D") var field_path: NodePath

const SHADOW_GROUND_Y: float = 0.02
const SHADOW_MIN_SCALE: float = 0.35
const SHADOW_HEIGHT_SHRINK_FACTOR: float = 0.15
# Половина толщины меша весла (0.15, см. PlayerPaddle.tscn/AIPaddle.tscn) плюс
# небольшой зазор, чтобы тень лежала поверх весла, а не внутри его коробки.
# Подогнать, если толщина меша весла изменится.
const SHADOW_PADDLE_SURFACE_OFFSET: float = 0.1

# Скорость мяча (длина вектора velocity), при которой след/свечение достигают
# полной интенсивности — ориентировочно (сумма ball_launch_vy/ball_hit_forward_speed
# по умолчанию), подобрать точнее на живом плейтесте, как и остальные константы
# баланса (см. GameDesign 3.1 про ai_paddle_speed/ai_error_offset).
const GLOW_SPEED_REFERENCE: float = 14.0
const GLOW_MIN_RATIO: float = 0.15 # след/свет не гаснут полностью даже у апекса параболы
const LIGHT_BASE_ENERGY: float = 0.8
const LIGHT_SPEED_ENERGY: float = 0.06
const LIGHT_PULSE_AMPLITUDE: float = 0.15
const LIGHT_PULSE_SPEED: float = 6.0 # рад/сек

signal point_scored(winner: String) # "player" или "ai"
signal paddle_hit # для звука удара (задача 5.2) — без параметров, самого факта отбития достаточно

var velocity: Vector3 = Vector3.ZERO

var _paddles: Array[Node] = []
@onready var _field: Node3D = get_node_or_null(field_path)
var _field_width: float = 10.0
var _field_length: float = 16.0

var _last_hitter_side: String = "" # "player"/"ai", пусто — ещё никто не отбивал в этом розыгрыше
var _point_scored_this_rally: bool = false

@onready var _shadow: MeshInstance3D = $ShadowMesh
@onready var _light: OmniLight3D = $BallLight
@onready var _trail: GPUParticles3D = $Trail

var _pulse_time: float = 0.0


func _ready() -> void:
	_paddles = get_tree().get_nodes_in_group("paddles")

	if _field != null:
		_field_width = _field.field_width
		_field_length = _field.field_length
	else:
		push_warning("Ball: field_path не назначен, используются размеры поля по умолчанию")


func _physics_process(delta: float) -> void:
	if _point_scored_this_rally:
		return # очко уже начислено — мяч замирает, ждёт следующей подачи от GameManager

	var y_before := position.y

	velocity.y += ball_gravity * delta
	position += velocity * delta

	_check_paddle_hits(y_before, position.y)
	# Аут — ДО касания пола: _check_floor_touch реагирует на пересечение Y=0
	# где угодно (это "бесконечный пол", не ограниченный площадью поля), так
	# что мяч, уже улетевший за X/Z-границы, всё равно рано или поздно падает
	# до Y=0 под гравитацией и, если бы пол проверялся первым, засчитывался бы
	# по правилу "чья половина" (которое может наградить именно того, кто
	# выбил мяч за пределы) вместо штрафа бьющему за аут. Раз аут проверяется
	# первым, он забирает очко, если мяч уже вне границ поля, независимо от
	# того, успел ли он в этот же кадр или чуть позже дойти до пола.
	_check_out_of_bounds()
	_check_floor_touch(y_before, position.y)
	_update_shadow()
	_update_glow(delta)


func _update_shadow() -> void:
	# Тень-«блин» держится строго под мячом по X/Z — в отличие от настоящей
	# тени от направленного света (которая легла бы под углом), это
	# однозначно показывает, куда мяч сейчас упадёт. Ложится на поверхность
	# весла, если мяч сейчас над его площадью (иначе тень рисовалась бы под
	# непрозрачным веслом и была бы не видна), иначе — на уровень поля.
	# Слегка уменьшается с высотой, чтобы дополнительно читалась глубина.
	var surface_y := SHADOW_GROUND_Y
	for paddle in _paddles:
		if is_instance_valid(paddle) and _is_within_paddle(paddle):
			surface_y = paddle.paddle_hit_height + SHADOW_PADDLE_SURFACE_OFFSET
			break

	_shadow.position.y = surface_y - position.y
	var shadow_scale: float = clamp(1.0 - position.y * SHADOW_HEIGHT_SHRINK_FACTOR, SHADOW_MIN_SCALE, 1.0)
	_shadow.scale = Vector3(shadow_scale, 1.0, shadow_scale)


func _update_glow(delta: float) -> void:
	# След и свет ярче на быстрых участках параболы (взлёт/приземление) и
	# тусклее у апекса, где скорость минимальна — этого добиваемся просто
	# завязкой на полную длину velocity, без отдельной проверки оси Y: по
	# траектории параболы горизонтальная составляющая скорости примерно
	# постоянна между ударами, так что общая скорость и так проседает у
	# апекса и растёт к краям дуги (см. GameDesign 5).
	_pulse_time += delta
	var speed := velocity.length()
	var speed_ratio: float = clamp(speed / GLOW_SPEED_REFERENCE, GLOW_MIN_RATIO, 1.0)

	_trail.amount_ratio = speed_ratio

	var pulse := sin(_pulse_time * LIGHT_PULSE_SPEED) * LIGHT_PULSE_AMPLITUDE
	_light.light_energy = LIGHT_BASE_ENERGY + LIGHT_SPEED_ENERGY * speed + pulse


func launch(new_velocity: Vector3) -> void:
	velocity = new_velocity
	# Новый запуск = новый розыгрыш: никто ещё не отбивал, очко ещё не начислено.
	_last_hitter_side = ""
	_point_scored_this_rally = false
	visible = true


func _check_paddle_hits(y_before: float, y_after: float) -> void:
	for paddle in _paddles:
		if not is_instance_valid(paddle):
			continue

		# Только пересечение СВЕРХУ ВНИЗ — мяч подлетает и попадает в весло
		# "с лёта". Строгое неравенство для y_before принципиально: сразу
		# после удара мяч снапается ровно на hit_height и улетает вверх, и
		# нестрогая проверка в обе стороны считала бы это новым пересечением
		# на каждом следующем кадре, пока мяч не покинет площадь весла по
		# XZ — отсюда и было "вязнет" при повторных срабатываниях удара.
		var hit_height: float = paddle.paddle_hit_height
		var crossed_downward := y_before > hit_height and y_after <= hit_height
		if not crossed_downward:
			continue

		if _is_within_paddle(paddle):
			_apply_hit(paddle, hit_height)
			return # за один кадр возможен только один удар


func _is_within_paddle(paddle: Node) -> bool:
	var half_size: Vector2 = paddle.paddle_size / 2.0
	var local_offset := Vector2(position.x - paddle.position.x, position.z - paddle.position.z)
	return abs(local_offset.x) <= half_size.x and abs(local_offset.y) <= half_size.y


func _apply_hit(paddle: Node, hit_height: float) -> void:
	position.y = hit_height

	var half_size: Vector2 = paddle.paddle_size / 2.0
	var offset := Vector2(
		(position.x - paddle.position.x) / half_size.x,
		(position.z - paddle.position.z) / half_size.y
	)

	# Отскок всегда летит в сторону соперника: весло на половине игрока
	# (Z>0) бьёт в сторону AI (-Z), и наоборот. ball_hit_forward_speed —
	# гарантированная базовая сила по Z независимо от точки попадания;
	# смещение по глубине весла (offset.y) добавляет к ней небольшую
	# переменную часть (ball_hit_horizontal_factor), а не задаёт всю силу
	# целиком — иначе удар в центр весла давал бы нулевой Z, а попадание в
	# "свой" край отправляло бы мяч назад, на свою же половину.
	var forward_sign := -1.0 if paddle.position.z > 0.0 else 1.0

	var base_dir := Vector3(
		offset.x * ball_hit_horizontal_factor,
		ball_launch_vy,
		(ball_hit_forward_speed + absf(offset.y) * ball_hit_horizontal_factor) * forward_sign
	)

	var paddle_velocity: Vector3 = paddle.velocity
	velocity = base_dir + paddle_velocity * paddle_velocity_influence
	# Финальная гарантия "только вперёд" даже если вклад скорости весла
	# (paddle_velocity_influence) тянул бы мяч назад.
	velocity.z = absf(velocity.z) * forward_sign

	_last_hitter_side = "player" if paddle.position.z > 0.0 else "ai"
	paddle_hit.emit()


func _check_floor_touch(y_before: float, y_after: float) -> void:
	if _point_scored_this_rally:
		return

	# Строгое неравенство по той же причине, что и в _check_paddle_hits —
	# не пересчитывать повторно после того, как мяч уже провалился под пол.
	var crossed_downward := y_before > 0.0 and y_after <= 0.0
	if not crossed_downward:
		return

	# Мяч упал на своей половине (Z>0 — половина игрока) — очко сопернику
	# (AI), и наоборот. Одно и то же правило верно и для "не отбил свой
	# мяч", и для "отбил мяч на половину соперника" — см. заголовок файла.
	var winner := "ai" if position.z > 0.0 else "player"
	_score_point(winner)


func _check_out_of_bounds() -> void:
	if _point_scored_this_rally:
		return

	var within_bounds := absf(position.x) <= _field_width / 2.0 and absf(position.z) <= _field_length / 2.0
	if within_bounds:
		return

	var winner: String
	if _last_hitter_side == "":
		# Никто ещё не отбивал (например, не приняли подачу, и мяч улетел за
		# границы раньше, чем успел коснуться пола) — некого штрафовать по
		# правилу аута, поэтому считаем это как обычное "не принял подачу":
		# очко сопернику половины, где сейчас мяч (та же логика, что и при
		# касании пола). Раньше в этом случае функция просто выходила без
		# счёта — мяч продолжал лететь и мог не вернуться никогда, это баг.
		winner = "ai" if position.z > 0.0 else "player"
	else:
		winner = "ai" if _last_hitter_side == "player" else "player"

	_score_point(winner)


func _score_point(winner: String) -> void:
	_point_scored_this_rally = true
	visible = false # не висеть в воздухе/за краем поля до следующей подачи
	point_scored.emit(winner)

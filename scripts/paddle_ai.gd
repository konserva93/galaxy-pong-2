extends Area3D

## Весло AI: та же механика удержания на paddle_hit_height и того же clamp
## (через общий PaddleBounds, см. paddle_bounds.gd), что и у игрока, но
## управляется не игроком, а прогнозом полёта мяча.
##
## Реагирует только когда мяч летит в сторону AI (velocity.z < 0 — половина
## AI на Z<0); в остальное время медленно возвращается к центру своей
## половины (idle). При реакции — едет к точке, где парабола мяча пересечёт
## paddle_hit_height, с ограниченной скоростью ai_paddle_speed. Отбивание —
## общей логикой в ball.gd (весло состоит в группе "paddles"), той же
## формулой, что и у игрока.
##
## Погрешность прицеливания (ai_error_offset): каждый раз, когда AI заново
## начинает целиться в мяч (см. AIM_DIE_SIDES/AIM_MISS_THRESHOLD ниже),
## "бросается" d21 — равномерно распределённое целое 1..21 (без нормального
## распределения, как и положено кубику); при результате меньше
## AIM_MISS_THRESHOLD — гарантированный промах: цель весла отклоняется от
## точной прогнозируемой точки ровно настолько, чтобы мяч оказался вне
## площади весла (по X ИЛИ по Z, выбирается случайно), но не сильнее, чем
## нужно для этого — весло всё равно остаётся рядом с местом приземления, а
## не мажет вслепую в сторону. Бросок и оффсет фиксируются один раз за
## "заход" (пока мяч непрерывно летит к AI), а не каждый кадр — иначе весло
## дёргалось бы каждый тик.
##
## ai_error_offset — верхняя граница оффсета по "гарантирующей промах" оси;
## должен быть больше соответствующей половины paddle_size, иначе гарантия
## промаха невозможна (в этом случае оффсет расширяется автоматически, см.
## _generate_guaranteed_miss_offset).

const AIM_DIE_SIDES := 21
const AIM_MISS_THRESHOLD := 5 ## бросок < 5 (т.е. 1..4) -> гарантированный промах
const AIM_MISS_MARGIN := 0.05 ## запас сверх половины весла, чтобы промах не был "впритык"

@export var ai_paddle_speed: float = 10.0
@export var paddle_hit_height: float = 1.0
@export var paddle_size: Vector2 = Vector2(2.0, 1.8) # X ширина, Z глубина
@export var ai_error_offset: float = 1.2
@export_node_path("Node3D") var field_path: NodePath
@export_node_path("Area3D") var ball_path: NodePath

@onready var _field: Node3D = get_node_or_null(field_path)
@onready var _ball: Area3D = get_node_or_null(ball_path)

var _bounds: PaddleBounds
var _rng := RandomNumberGenerator.new()
var _was_reacting := false
var _current_error := Vector2.ZERO
var _prev_ball_y := 0.0
var _missed_return_count := 0 ## для тестов -- считает срабатывания _check_missed_return

## Скорость весла в текущем кадре (для вклада в удар мяча, см. ball.gd).
var velocity: Vector3 = Vector3.ZERO
var _previous_position: Vector3
var _start_position: Vector3


func _ready() -> void:
	position.y = paddle_hit_height
	_previous_position = position
	_start_position = position

	var field_width := 10.0
	var field_length := 16.0
	if _field != null:
		field_width = _field.field_width
		field_length = _field.field_length
	else:
		push_warning("AIPaddle: field_path не назначен, используются размеры поля по умолчанию")

	if _ball == null:
		push_warning("AIPaddle: ball_path не назначен, AI не сможет реагировать на мяч")
	else:
		_prev_ball_y = _ball.position.y

	_bounds = PaddleBounds.new(
		field_width, field_length,
		paddle_size.x / 2.0, paddle_size.y / 2.0,
		paddle_hit_height, false # половина AI — Z<0
	)


## Возвращает весло на стартовую позицию (задача 4.3 — рестарт партии).
## Сбрасывает и _was_reacting/_prev_ball_y — иначе после телепорта мяча в
## центр при рестарте следующий тик мог бы ложно засчитать "промах"
## (см. _check_missed_return) на устаревших данных.
func reset_position() -> void:
	position = _start_position
	velocity = Vector3.ZERO
	_previous_position = position
	_was_reacting = false
	if _ball != null:
		_prev_ball_y = _ball.position.y


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and not _bounds.z_calibrated:
		_bounds.calibrate_z(camera)

	_check_missed_return()

	var target := _compute_target()
	position.x = move_toward(position.x, target.x, ai_paddle_speed * delta)
	position.z = move_toward(position.z, target.y, ai_paddle_speed * delta)

	if camera != null:
		_bounds.update_x_bounds(camera, position.z)
	position = _bounds.clamp_position(position)

	velocity = (position - _previous_position) / delta
	_previous_position = position


## Отладочный вывод: мяч пересёк paddle_hit_height сверху вниз, ЛЕТЯ К AI
## (velocity.z < 0, т.е. это не последствие уже состоявшегося отбития — сразу
## после удара velocity.z становится >= 0), пока AI активно реагировал на
## него (_was_reacting) -- значит удара не произошло, AI не поймал мяч,
## который был "его". Строгое "< paddle_hit_height" (а не "<=") принципиально
## отличает это от кадра самого удара, где ball.gd снапает Y ровно на
## paddle_hit_height, а не ниже.
func _check_missed_return() -> void:
	if _ball == null:
		return

	var ball_y: float = _ball.position.y
	var crossed_downward := _prev_ball_y > paddle_hit_height and ball_y < paddle_hit_height
	if _was_reacting and crossed_downward and _ball.velocity.z < 0.0:
		_missed_return_count += 1
		print("AI missed a return: ball crossed paddle_hit_height at x=%.2f z=%.2f (AI was at x=%.2f z=%.2f)" % [_ball.position.x, _ball.position.z, position.x, position.z]) # TODO: временный отладочный вывод, убрать после проверки

	_prev_ball_y = ball_y


func _compute_target() -> Vector2:
	var home_center := Vector2(0.0, (_bounds.z_min + _bounds.z_max) / 2.0)

	if _ball == null:
		return home_center

	if not _ball.visible:
		# Мяч замер и скрыт на паузе после гола (см. ball.gd/_score_point) —
		# его velocity.z в этот момент "застыл" таким же, каким был перед
		# голом, и не сигнализирует, куда полетит следующая подача. Без этого
		# сброса заход, начавшийся ДО гола, не завершался (velocity.z не
		# успевал стать >=0), и следующая подача в сторону AI наследовала
		# старый бросок d21 (в том числе промах) вместо нового.
		_was_reacting = false
		return home_center

	if _ball.velocity.z < 0.0:
		if not _was_reacting:
			_was_reacting = true
			var roll := _rng.randi_range(1, AIM_DIE_SIDES)
			print("AI d21 roll: %d (%s)" % [roll, "miss" if roll < AIM_MISS_THRESHOLD else "hit"]) # TODO: временный отладочный вывод, убрать после проверки
			if roll < AIM_MISS_THRESHOLD:
				_current_error = _generate_guaranteed_miss_offset()
			else:
				_current_error = Vector2.ZERO
		return _predict_ball_landing() + _current_error

	_was_reacting = false
	return home_center


## Оффсет по одной случайно выбранной оси (X или Z), гарантированно
## превышающий соответствующую половину paddle_size — мяч на точной
## прогнозируемой точке окажется вне площади весла (см. ball._is_within_paddle),
## значит удара не будет. Величина по этой оси — от границы весла с небольшим
## запасом (AIM_MISS_MARGIN) до ai_error_offset (расширяется, если тот
## меньше границы). Вторая ось получает небольшой оффсет в пределах своей
## половины весла — не влияет на гарантию промаха, просто разнообразит цель.
func _generate_guaranteed_miss_offset() -> Vector2:
	var half_size: Vector2 = paddle_size / 2.0
	var sign: float = 1.0 if _rng.randf() < 0.5 else -1.0

	if _rng.randf() < 0.5:
		var lower: float = half_size.x + AIM_MISS_MARGIN
		var upper: float = maxf(ai_error_offset, lower + AIM_MISS_MARGIN)
		return Vector2(sign * _rng.randf_range(lower, upper), _rng.randf_range(-half_size.y, half_size.y))

	var lower_z: float = half_size.y + AIM_MISS_MARGIN
	var upper_z: float = maxf(ai_error_offset, lower_z + AIM_MISS_MARGIN)
	return Vector2(_rng.randf_range(-half_size.x, half_size.x), sign * _rng.randf_range(lower_z, upper_z))


func _predict_ball_landing() -> Vector2:
	var t := _time_to_reach_height(_ball.position.y, _ball.velocity.y, _ball.ball_gravity, paddle_hit_height)
	if t < 0.0:
		return Vector2(_ball.position.x, _ball.position.z)

	return Vector2(
		_ball.position.x + _ball.velocity.x * t,
		_ball.position.z + _ball.velocity.z * t
	)


## Время до пересечения мячом высоты target_height по параболе:
## 0.5*g*t^2 + vy*t + (y0-target_height) = 0. Возвращает -1.0, если решения
## нет (мяч эту высоту не пересечёт) или оно только в прошлом.
func _time_to_reach_height(y0: float, vy: float, g: float, target_height: float) -> float:
	var a := 0.5 * g
	var b := vy
	var c := y0 - target_height

	if is_zero_approx(a):
		if is_zero_approx(b):
			return -1.0
		var t: float = -c / b
		return t if t >= 0.0 else -1.0

	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0

	var sqrt_d := sqrt(discriminant)
	var t1 := (-b + sqrt_d) / (2.0 * a)
	var t2 := (-b - sqrt_d) / (2.0 * a)

	var best := -1.0
	for t in [t1, t2]:
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best

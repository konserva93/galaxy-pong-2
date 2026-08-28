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
## Погрешность прицеливания (ai_error_offset) — тюнинг сложности, задача 3.1,
## сюда пока не входит.

@export var ai_paddle_speed: float = 10.0
@export var paddle_hit_height: float = 1.0
@export var paddle_size: Vector2 = Vector2(2.0, 1.8) # X ширина, Z глубина
@export_node_path("Node3D") var field_path: NodePath
@export_node_path("Area3D") var ball_path: NodePath

@onready var _field: Node3D = get_node_or_null(field_path)
@onready var _ball: Area3D = get_node_or_null(ball_path)

var _bounds: PaddleBounds

## Скорость весла в текущем кадре (для вклада в удар мяча, см. ball.gd).
var velocity: Vector3 = Vector3.ZERO
var _previous_position: Vector3


func _ready() -> void:
	position.y = paddle_hit_height
	_previous_position = position

	var field_width := 10.0
	var field_length := 16.0
	if _field != null:
		field_width = _field.field_width
		field_length = _field.field_length
	else:
		push_warning("AIPaddle: field_path не назначен, используются размеры поля по умолчанию")

	if _ball == null:
		push_warning("AIPaddle: ball_path не назначен, AI не сможет реагировать на мяч")

	_bounds = PaddleBounds.new(
		field_width, field_length,
		paddle_size.x / 2.0, paddle_size.y / 2.0,
		paddle_hit_height, false # половина AI — Z<0
	)


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and not _bounds.z_calibrated:
		_bounds.calibrate_z(camera)

	var target := _compute_target()
	position.x = move_toward(position.x, target.x, ai_paddle_speed * delta)
	position.z = move_toward(position.z, target.y, ai_paddle_speed * delta)

	if camera != null:
		_bounds.update_x_bounds(camera, position.z)
	position = _bounds.clamp_position(position)

	velocity = (position - _previous_position) / delta
	_previous_position = position


func _compute_target() -> Vector2:
	var home_center := Vector2(0.0, (_bounds.z_min + _bounds.z_max) / 2.0)

	if _ball == null:
		return home_center

	if _ball.velocity.z < 0.0:
		return _predict_ball_landing()

	return home_center


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

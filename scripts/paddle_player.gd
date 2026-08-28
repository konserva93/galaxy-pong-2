extends Area3D

## Весло игрока: движение по X/Z на фиксированной высоте paddle_hit_height,
## одновременно и клавиатурой (WASD/стрелки), и мышью, с clamp в пределах
## своей половины поля.
##
## Весло висит над полем на высоте paddle_hit_height, а границы поля — на
## уровне земли (Y=0). Под наклонной камерой это создаёт параллакс: поднятый
## объект проецируется на экран не туда же, куда линия на земле с теми же
## X/Z, из-за чего весло визуально не дотягивалось до своего дальнего края и
## вылезало за боковую границу у центра, хотя её мировые координаты были
## верны. Поэтому границы clamp (и калибровка мыши) считаются не по плоским
## координатам поля, а перепроецируются через камеру на плоскость
## paddle_hit_height — так весло визуально совпадает с полем.
##
## Граница по Z (центральная линия / свой край) считается один раз при X=0 —
## камера стоит на X=0, так что зависимостью Z-границы от X можно пренебречь.
## Граница по X, наоборот, ощутимо зависит от текущего Z (перспективное
## схождение боковых линий поля), поэтому пересчитывается каждый кадр от
## актуальной позиции весла по Z.

@export var paddle_speed: float = 12.0
@export var paddle_hit_height: float = 1.0
@export var paddle_size: Vector2 = Vector2(2.0, 1.8) # X ширина, Z глубина
@export var mouse_follow_speed: float = 15.0
@export_node_path("Node3D") var field_path: NodePath

@onready var _field: Node3D = get_node_or_null(field_path)

var _field_width: float = 10.0
var _field_length: float = 16.0
var _last_mouse_pos: Vector2

var _half_width: float
var _half_depth: float
var _x_min: float
var _x_max: float
var _z_min: float
var _z_max: float

var _z_bounds_calibrated: bool = false
var _mouse_calibrated: bool = false
var _mouse_x_screen_range: Vector2
var _mouse_z_screen_range: Vector2

## Скорость весла в текущем кадре (для вклада в удар мяча, см. ball.gd).
var velocity: Vector3 = Vector3.ZERO
var _previous_position: Vector3


func _ready() -> void:
	position.y = paddle_hit_height
	_last_mouse_pos = get_viewport().get_mouse_position()
	_previous_position = position

	if _field != null:
		_field_width = _field.field_width
		_field_length = _field.field_length
	else:
		push_warning("PlayerPaddle: field_path не назначен, используются размеры поля по умолчанию")

	_half_width = paddle_size.x / 2.0
	_half_depth = paddle_size.y / 2.0
	# Плоские границы поля — запасной вариант, пока камера ещё не найдена;
	# _x_min/_x_max каждый кадр и _z_min/_z_max один раз заменяются визуально
	# скорректированными значениями (см. _update_x_bounds/_calibrate_z_bounds).
	_x_min = -_field_width / 2.0 + _half_width
	_x_max = _field_width / 2.0 - _half_width
	_z_min = _half_depth
	_z_max = _field_length / 2.0 - _half_depth


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and not _z_bounds_calibrated:
		_calibrate_z_bounds(camera)
	if camera != null and not _mouse_calibrated:
		_calibrate_mouse_mapping(camera)

	_apply_keyboard_movement(delta)
	_apply_mouse_movement(delta, camera)
	_clamp_to_bounds(camera)

	velocity = (position - _previous_position) / delta
	_previous_position = position


func _apply_keyboard_movement(delta: float) -> void:
	var move_x := Input.get_axis("move_left", "move_right")
	var move_z := Input.get_axis("move_forward", "move_back")
	if move_x != 0.0 or move_z != 0.0:
		position.x += move_x * paddle_speed * delta
		position.z += move_z * paddle_speed * delta


func _apply_mouse_movement(delta: float, camera: Camera3D) -> void:
	if camera == null or not _mouse_calibrated:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	if mouse_pos == _last_mouse_pos:
		return
	_last_mouse_pos = mouse_pos

	var target_x := remap(mouse_pos.x, _mouse_x_screen_range.x, _mouse_x_screen_range.y, _x_min, _x_max)
	var target_z := remap(mouse_pos.y, _mouse_z_screen_range.x, _mouse_z_screen_range.y, _z_min, _z_max)

	position.x = move_toward(position.x, target_x, mouse_follow_speed * delta)
	position.z = move_toward(position.z, target_z, mouse_follow_speed * delta)


func _calibrate_z_bounds(camera: Camera3D) -> void:
	var reproj_near := _reproject_to_height(camera, Vector3(0.0, 0.0, 0.0))
	var reproj_far := _reproject_to_height(camera, Vector3(0.0, 0.0, _field_length / 2.0))
	_z_min = reproj_near.z + _half_depth
	_z_max = reproj_far.z - _half_depth
	_z_bounds_calibrated = true


func _calibrate_mouse_mapping(camera: Camera3D) -> void:
	var mid_z := (_z_min + _z_max) / 2.0
	_update_x_bounds(camera, mid_z)
	_mouse_x_screen_range = Vector2(
		camera.unproject_position(Vector3(_x_min, paddle_hit_height, mid_z)).x,
		camera.unproject_position(Vector3(_x_max, paddle_hit_height, mid_z)).x
	)
	_mouse_z_screen_range = Vector2(
		camera.unproject_position(Vector3(0.0, paddle_hit_height, _z_min)).y,
		camera.unproject_position(Vector3(0.0, paddle_hit_height, _z_max)).y
	)
	_mouse_calibrated = true


func _update_x_bounds(camera: Camera3D, z: float) -> void:
	# Боковая граница поля (прямая в 3D при y=0) проецируется на экран тоже
	# прямой линией — находим её экранный X на той же экранной высоте, на
	# которой сейчас реально отрисовывается весло (на высоте paddle_hit_height,
	# в текущем z), и обратно проецируем эту экранную точку на высоту весла.
	# (Наивная перепроекция "луч камеры сквозь граничную точку до высоты
	# весла" не подходит: получившаяся точка оказывается на другом Z, чем
	# реальная позиция весла, — визуально совпадение не гарантируется.)
	var paddle_screen_y := camera.unproject_position(Vector3(0.0, paddle_hit_height, z)).y

	_x_min = _boundary_world_x(camera, -_field_width / 2.0, paddle_screen_y) + _half_width
	_x_max = _boundary_world_x(camera, _field_width / 2.0, paddle_screen_y) - _half_width


func _boundary_world_x(camera: Camera3D, edge_x: float, at_screen_y: float) -> float:
	var near_end := camera.unproject_position(Vector3(edge_x, 0.0, -_field_length / 2.0))
	var far_end := camera.unproject_position(Vector3(edge_x, 0.0, _field_length / 2.0))
	var screen_x := remap(at_screen_y, near_end.y, far_end.y, near_end.x, far_end.x)

	var ray_origin := camera.project_ray_origin(Vector2(screen_x, at_screen_y))
	var ray_dir := camera.project_ray_normal(Vector2(screen_x, at_screen_y))
	var t := (paddle_hit_height - ray_origin.y) / ray_dir.y
	return (ray_origin + ray_dir * t).x


func _reproject_to_height(camera: Camera3D, ground_point: Vector3) -> Vector3:
	var cam_pos := camera.global_position
	var dir := (ground_point - cam_pos).normalized()
	if is_zero_approx(dir.y):
		return ground_point
	var t := (paddle_hit_height - cam_pos.y) / dir.y
	return cam_pos + dir * t


func _clamp_to_bounds(camera: Camera3D) -> void:
	if camera != null:
		_update_x_bounds(camera, position.z)
	position.x = clamp(position.x, _x_min, _x_max)
	position.z = clamp(position.z, _z_min, _z_max)

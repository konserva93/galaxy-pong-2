extends Area3D

## Весло игрока: движение по X/Z на фиксированной высоте paddle_hit_height,
## одновременно и клавиатурой (WASD/стрелки), и мышью, с clamp в пределах
## своей половины поля. Визуально скорректированные (под параллакс камеры)
## границы движения считает общий PaddleBounds (см. paddle_bounds.gd) —
## используется и AIPaddle.

@export var paddle_speed: float = 12.0
@export var paddle_hit_height: float = 1.0
@export var paddle_size: Vector2 = Vector2(2.0, 1.8) # X ширина, Z глубина
@export var mouse_follow_speed: float = 15.0
@export_node_path("Node3D") var field_path: NodePath

@onready var _field: Node3D = get_node_or_null(field_path)

var _bounds: PaddleBounds
var _last_mouse_pos: Vector2

var _mouse_calibrated: bool = false
var _mouse_x_screen_range: Vector2
var _mouse_z_screen_range: Vector2

## Скорость весла в текущем кадре (для вклада в удар мяча, см. ball.gd).
var velocity: Vector3 = Vector3.ZERO
var _previous_position: Vector3
var _start_position: Vector3


func _ready() -> void:
	position.y = paddle_hit_height
	_last_mouse_pos = get_viewport().get_mouse_position()
	_previous_position = position
	_start_position = position

	var field_width := 10.0
	var field_length := 16.0
	if _field != null:
		field_width = _field.field_width
		field_length = _field.field_length
	else:
		push_warning("PlayerPaddle: field_path не назначен, используются размеры поля по умолчанию")

	_bounds = PaddleBounds.new(
		field_width, field_length,
		paddle_size.x / 2.0, paddle_size.y / 2.0,
		paddle_hit_height, true # половина игрока — Z>0
	)


## Возвращает весло на стартовую позицию (задача 4.3 — рестарт партии).
func reset_position() -> void:
	position = _start_position
	velocity = Vector3.ZERO
	_previous_position = position


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and not _bounds.z_calibrated:
		_bounds.calibrate_z(camera)
	if camera != null and not _mouse_calibrated:
		_calibrate_mouse_mapping(camera)

	_apply_keyboard_movement(delta)
	_apply_mouse_movement(delta, camera)

	if camera != null:
		_bounds.update_x_bounds(camera, position.z)
	position = _bounds.clamp_position(position)

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

	var target_x := remap(mouse_pos.x, _mouse_x_screen_range.x, _mouse_x_screen_range.y, _bounds.x_min, _bounds.x_max)
	var target_z := remap(mouse_pos.y, _mouse_z_screen_range.x, _mouse_z_screen_range.y, _bounds.z_min, _bounds.z_max)

	position.x = move_toward(position.x, target_x, mouse_follow_speed * delta)
	position.z = move_toward(position.z, target_z, mouse_follow_speed * delta)


func _calibrate_mouse_mapping(camera: Camera3D) -> void:
	var mid_z := (_bounds.z_min + _bounds.z_max) / 2.0
	_bounds.update_x_bounds(camera, mid_z)
	_mouse_x_screen_range = Vector2(
		camera.unproject_position(Vector3(_bounds.x_min, paddle_hit_height, mid_z)).x,
		camera.unproject_position(Vector3(_bounds.x_max, paddle_hit_height, mid_z)).x
	)
	_mouse_z_screen_range = Vector2(
		camera.unproject_position(Vector3(0.0, paddle_hit_height, _bounds.z_min)).y,
		camera.unproject_position(Vector3(0.0, paddle_hit_height, _bounds.z_max)).y
	)
	_mouse_calibrated = true

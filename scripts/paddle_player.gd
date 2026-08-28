extends Area3D

## Весло игрока: движение по X/Z на фиксированной высоте paddle_hit_height,
## одновременно и клавиатурой (WASD/стрелки), и мышью (проекция курсора на
## плоскость поля), с clamp в пределах своей половины поля.

@export var paddle_speed: float = 12.0
@export var paddle_hit_height: float = 1.0
@export var paddle_size: Vector2 = Vector2(2.0, 1.2) # X ширина, Z глубина
@export var mouse_follow_speed: float = 15.0
@export_node_path("Node3D") var field_path: NodePath

@onready var _field: Node3D = get_node_or_null(field_path)

var _field_width: float = 10.0
var _field_length: float = 16.0
var _last_mouse_pos: Vector2


func _ready() -> void:
	position.y = paddle_hit_height
	_last_mouse_pos = get_viewport().get_mouse_position()
	if _field != null:
		_field_width = _field.field_width
		_field_length = _field.field_length
	else:
		push_warning("PlayerPaddle: field_path не назначен, используются размеры поля по умолчанию")


func _physics_process(delta: float) -> void:
	_apply_keyboard_movement(delta)
	_apply_mouse_movement(delta)
	_clamp_to_bounds()


func _apply_keyboard_movement(delta: float) -> void:
	var move_x := Input.get_axis("move_left", "move_right")
	var move_z := Input.get_axis("move_forward", "move_back")
	if move_x != 0.0 or move_z != 0.0:
		position.x += move_x * paddle_speed * delta
		position.z += move_z * paddle_speed * delta


func _apply_mouse_movement(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	if mouse_pos == _last_mouse_pos:
		return
	_last_mouse_pos = mouse_pos

	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if is_zero_approx(ray_dir.y):
		return

	var t := (paddle_hit_height - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return
	var target := ray_origin + ray_dir * t

	position.x = move_toward(position.x, target.x, mouse_follow_speed * delta)
	position.z = move_toward(position.z, target.z, mouse_follow_speed * delta)


func _clamp_to_bounds() -> void:
	var half_width := paddle_size.x / 2.0
	var half_depth := paddle_size.y / 2.0

	position.x = clamp(position.x, -_field_width / 2.0 + half_width, _field_width / 2.0 - half_width)
	position.z = clamp(position.z, half_depth, _field_length / 2.0 - half_depth)

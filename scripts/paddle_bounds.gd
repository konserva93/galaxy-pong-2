class_name PaddleBounds
extends RefCounted

## Общая логика вычисления границ движения весла в пределах его половины
## поля по X/Z, визуально скорректированных под параллакс: весло висит на
## высоте paddle_hit_height, а поле — на уровне земли (Y=0), из-за чего под
## наклонной камерой плоский clamp по геометрии поля выглядит неверно (весло
## вылезает за боковые границы у центра, не дотягивается до своего края).
## См. paddle_player.gd — там разбор проблемы подробно. Используется и
## PlayerPaddle, и AIPaddle, чтобы не дублировать эту математику.
##
## Граница по Z (центральная линия / свой край) считается один раз при X=0 —
## камера стоит на X=0, так что зависимостью Z-границы от X можно пренебречь.
## Граница по X, наоборот, ощутимо зависит от текущего Z (перспективное
## схождение боковых линий поля), поэтому пересчитывается при каждом вызове
## update_x_bounds() от актуальной позиции весла по Z.

var field_width: float
var field_length: float
var half_width: float
var half_depth: float
var paddle_hit_height: float
var positive_half: bool # true — половина игрока (Z>0), false — половина AI (Z<0)

var z_min: float
var z_max: float
var x_min: float
var x_max: float

var z_calibrated: bool = false


func _init(
	p_field_width: float,
	p_field_length: float,
	p_half_width: float,
	p_half_depth: float,
	p_paddle_hit_height: float,
	p_positive_half: bool
) -> void:
	field_width = p_field_width
	field_length = p_field_length
	half_width = p_half_width
	half_depth = p_half_depth
	paddle_hit_height = p_paddle_hit_height
	positive_half = p_positive_half

	# Плоские границы поля — запасной вариант, пока камера ещё не найдена.
	x_min = -field_width / 2.0 + half_width
	x_max = field_width / 2.0 - half_width
	if positive_half:
		z_min = half_depth
		z_max = field_length / 2.0 - half_depth
	else:
		z_min = -field_length / 2.0 + half_depth
		z_max = -half_depth


func calibrate_z(camera: Camera3D) -> void:
	var center_line_z := 0.0
	var back_edge_z := field_length / 2.0 if positive_half else -field_length / 2.0

	var reproj_center := _reproject_to_height(camera, Vector3(0.0, 0.0, center_line_z))
	var reproj_back := _reproject_to_height(camera, Vector3(0.0, 0.0, back_edge_z))

	if positive_half:
		z_min = reproj_center.z + half_depth
		z_max = reproj_back.z - half_depth
		# Защита: истинная (не визуальная) позиция весла никогда не должна
		# пересекать центральную линию. Камера асимметрична (стоит только на
		# положительной стороне Z), поэтому перепроекция "точки визуального
		# совпадения с центральной линией" для дальней половины поля может
		# оказаться на чужой стороне (см. ветку else) — здесь этого не
		# происходит, но симметричная защита не помешает.
		z_min = max(z_min, half_depth)
	else:
		z_min = reproj_back.z + half_depth
		z_max = reproj_center.z - half_depth
		# См. комментарий выше: для дальней от камеры половины поля
		# перепроецированная "точка совпадения с центральной линией" лежит
		# на положительной стороне Z (камера ведь всегда на положительной
		# стороне) — без этой защиты весло могло бы визуально "правильно"
		# заехать на чужую половину.
		z_max = min(z_max, -half_depth)

	z_calibrated = true


func update_x_bounds(camera: Camera3D, z: float) -> void:
	# Боковая граница поля (прямая в 3D при y=0) проецируется на экран тоже
	# прямой линией — находим её экранный X на той же экранной высоте, на
	# которой сейчас реально отрисовывается весло (на высоте paddle_hit_height,
	# в текущем z), и обратно проецируем эту экранную точку на высоту весла.
	# (Наивная перепроекция "луч камеры сквозь граничную точку до высоты
	# весла" не подходит: получившаяся точка оказывается на другом Z, чем
	# реальная позиция весла, — визуально совпадение не гарантируется.)
	var paddle_screen_y := camera.unproject_position(Vector3(0.0, paddle_hit_height, z)).y

	x_min = _boundary_world_x(camera, -field_width / 2.0, paddle_screen_y) + half_width
	x_max = _boundary_world_x(camera, field_width / 2.0, paddle_screen_y) - half_width


func clamp_position(pos: Vector3) -> Vector3:
	pos.x = clamp(pos.x, x_min, x_max)
	pos.z = clamp(pos.z, z_min, z_max)
	return pos


func _boundary_world_x(camera: Camera3D, edge_x: float, at_screen_y: float) -> float:
	var near_end := camera.unproject_position(Vector3(edge_x, 0.0, -field_length / 2.0))
	var far_end := camera.unproject_position(Vector3(edge_x, 0.0, field_length / 2.0))
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

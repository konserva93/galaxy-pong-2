extends Node3D

## Игровое поле: плоскость поля, боковые границы (для аута) и центральная линия.
## field_width/field_length — единственный источник правды для размеров поля;
## остальные скрипты (весла, мяч, AI) будут читать их отсюда.

@export var field_width: float = 10.0:
	set(value):
		field_width = value
		_apply_dimensions()
@export var field_length: float = 16.0:
	set(value):
		field_length = value
		_apply_dimensions()

const WALL_THICKNESS: float = 0.2
const WALL_HEIGHT: float = 20.0
const CENTER_LINE_THICKNESS: float = 0.1
const CENTER_LINE_HEIGHT: float = 0.05

@onready var _field_mesh: MeshInstance3D = $FieldMesh
@onready var _left_wall: Area3D = $LeftWall
@onready var _right_wall: Area3D = $RightWall
@onready var _left_wall_shape: CollisionShape3D = $LeftWall/CollisionShape3D
@onready var _right_wall_shape: CollisionShape3D = $RightWall/CollisionShape3D
@onready var _center_line: MeshInstance3D = $CenterLine


func _ready() -> void:
	_apply_dimensions()


func _apply_dimensions() -> void:
	if not is_node_ready():
		return

	(_field_mesh.mesh as PlaneMesh).size = Vector2(field_width, field_length)

	var wall_size := Vector3(WALL_THICKNESS, WALL_HEIGHT, field_length)
	(_left_wall_shape.shape as BoxShape3D).size = wall_size
	(_right_wall_shape.shape as BoxShape3D).size = wall_size
	_left_wall.position = Vector3(-field_width / 2.0, WALL_HEIGHT / 2.0, 0.0)
	_right_wall.position = Vector3(field_width / 2.0, WALL_HEIGHT / 2.0, 0.0)

	(_center_line.mesh as BoxMesh).size = Vector3(field_width, CENTER_LINE_HEIGHT, CENTER_LINE_THICKNESS)

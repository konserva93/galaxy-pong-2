extends SceneTree

## Регрессия для задачи 6.2 (материалы поля и весла): проверяет только то, что
## можно проверить программно — поле тёмное/полупрозрачное, разметка (центр +
## границы) эмиссивна и подстраивается под размер поля, вёсла эмиссивны с
## правильными неоновыми цветами и используют новый плоский меш-«площадку»
## вместо старого сплошного бокса. Насколько это красиво светится в реальном
## bloom (этап 6.4) — решает пользователь при живом просмотре.
##
## Запуск: см. reference-godot-cli в памяти проекта.

var _ok := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = main_scene.instantiate()
	root.add_child(main)
	await physics_frame

	_check_field_surface(main)
	_check_field_grid(main)
	_check_paddle_material(main, "PlayerPaddle", Color(0, 0.9, 1, 1))
	_check_paddle_material(main, "AIPaddle", Color(1, 0.2, 0.55, 1))

	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_field_surface(main: Node3D) -> void:
	print("--- field surface is dark and translucent, not the flat default ---")

	var field_mesh: MeshInstance3D = main.get_node("Field/FieldMesh")
	var mat: StandardMaterial3D = field_mesh.mesh.material
	print("mat=%s transparency=%s albedo=%s" % [mat, mat.transparency if mat else null, mat.albedo_color if mat else null])
	_ok = _ok and mat != null
	if mat == null:
		return
	_ok = _ok and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	_ok = _ok and mat.albedo_color.a < 1.0
	_ok = _ok and mat.albedo_color.v < 0.3 # тёмная, не яркая


func _check_field_grid(main: Node3D) -> void:
	print("--- center line and border lines are emissive and track field size ---")

	var field: Node3D = main.get_node("Field")
	var field_width: float = field.field_width
	var field_length: float = field.field_length

	for line_name in ["CenterLine", "BorderLeft", "BorderRight", "BorderFront", "BorderBack"]:
		var line: MeshInstance3D = field.get_node(line_name)
		var mat: StandardMaterial3D = line.mesh.material
		print("%s mat=%s emission_enabled=%s" % [line_name, mat, mat.emission_enabled if mat else null])
		_ok = _ok and mat != null and mat.emission_enabled

	var border_left: MeshInstance3D = field.get_node("BorderLeft")
	var border_front: MeshInstance3D = field.get_node("BorderFront")
	print("border_left.x=%.2f (expect %.2f) border_front.z=%.2f (expect %.2f)" % [
		border_left.position.x, -field_width / 2.0, border_front.position.z, field_length / 2.0
	])
	_ok = _ok and absf(border_left.position.x - (-field_width / 2.0)) < 0.001
	_ok = _ok and absf(border_front.position.z - field_length / 2.0) < 0.001


func _check_paddle_material(main: Node3D, node_name: String, expected_emission: Color) -> void:
	print("--- %s uses an emissive neon disc, not the old solid box ---" % node_name)

	var paddle: Area3D = main.get_node(node_name)
	var mesh_instance: MeshInstance3D = paddle.get_node("MeshInstance3D")
	var mesh := mesh_instance.mesh
	print("mesh=%s" % mesh)
	_ok = _ok and mesh is CylinderMesh
	if mesh is CylinderMesh:
		_ok = _ok and mesh.height < 0.3 # тоньше старого бокса (0.3) -- реально "площадка"

	var mat: StandardMaterial3D = mesh.material
	print("mat=%s emission_enabled=%s emission=%s" % [mat, mat.emission_enabled if mat else null, mat.emission if mat else null])
	_ok = _ok and mat != null
	if mat == null:
		return
	_ok = _ok and mat.emission_enabled
	_ok = _ok and mat.emission.is_equal_approx(expected_emission)

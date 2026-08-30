extends Button

## Кастомный чекбокс для подменю настроек (переключатель полноэкранного
## режима): квадрат с неоновой обводкой, галочка внутри — текстовый символ,
## не иконка темы -- рисуется сам в _draw(), не стандартный движковый
## CheckBox/CheckButton (по прямому запросу). Клик/тоггл всё равно берём
## готовый у Button (toggle_mode) -- переопределяем только визуал: flat=true
## убирает штатную заливку/рамку кнопки, весь вид ниже свой.

const BOX_SIZE := 28.0
const BORDER_WIDTH := 2.0
# Тот же радиус, что у обводки выпадающего списка/кнопок (theme/neon_theme.tres,
# StyleBoxFlat_button_*/StyleBoxFlat_option_*corner_radius) -- визуально одна
# и та же скруглённость по всему UI паузы/настроек, не своя произвольная.
const CORNER_RADIUS := 6
const BOX_FILL := Color(0.05, 0.03, 0.12, 0.85)
const BORDER_COLOR := Color(0, 0.9, 1, 1)
const BORDER_COLOR_HOVER := Color(0.4, 1, 1, 1)
const CHECK_COLOR := Color(0, 0.9, 1, 1)

var _hovering := false
var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat


func _ready() -> void:
	toggle_mode = true
	flat = true
	text = ""
	custom_minimum_size = Vector2(BOX_SIZE, BOX_SIZE)
	toggled.connect(_on_toggled)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_style_normal = _make_box_style(BORDER_COLOR)
	_style_hover = _make_box_style(BORDER_COLOR_HOVER)


func _make_box_style(border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BOX_FILL
	style.border_color = border_color
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(CORNER_RADIUS)
	return style


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(BOX_SIZE, BOX_SIZE))
	draw_style_box(_style_hover if _hovering else _style_normal, rect)

	if button_pressed:
		var font := get_theme_default_font()
		var font_size := int(BOX_SIZE * 0.75)
		draw_string(font, Vector2(BOX_SIZE * 0.18, BOX_SIZE * 0.78), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CHECK_COLOR)


func _on_toggled(_value: bool) -> void:
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovering = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovering = false
	queue_redraw()

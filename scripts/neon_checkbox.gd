extends Button

## Кастомный чекбокс для подменю настроек (переключатель полноэкранного
## режима): квадрат с неоновой обводкой, галочка внутри — текстовый символ,
## не иконка темы -- рисуется сам в _draw(), не стандартный движковый
## CheckBox/CheckButton (по прямому запросу). Клик/тоггл всё равно берём
## готовый у Button (toggle_mode) -- переопределяем только визуал: flat=true
## убирает штатную заливку/рамку кнопки, весь вид ниже свой.

const BOX_SIZE := 28.0
const BORDER_WIDTH := 2.0
const BOX_FILL := Color(0.05, 0.03, 0.12, 0.85)
const BORDER_COLOR := Color(0, 0.9, 1, 1)
const BORDER_COLOR_HOVER := Color(0.4, 1, 1, 1)
const CHECK_COLOR := Color(0, 0.9, 1, 1)

var _hovering := false


func _ready() -> void:
	toggle_mode = true
	flat = true
	text = ""
	custom_minimum_size = Vector2(BOX_SIZE, BOX_SIZE)
	toggled.connect(_on_toggled)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(BOX_SIZE, BOX_SIZE))
	draw_rect(rect, BOX_FILL, true)
	draw_rect(rect, BORDER_COLOR_HOVER if _hovering else BORDER_COLOR, false, BORDER_WIDTH)

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

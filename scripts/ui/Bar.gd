extends Control
# Flat HUD bar (health / shield) drawn with a few rects.

var value := 100.0 setget set_value
var max_value := 100.0
var fill_color := Color(0.35, 0.90, 0.40)


func set_value(v: float) -> void:
	if v != value:
		value = v
		update()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0, 0, 0, 0.55))
	var w := rect_size.x * clamp(value / max_value, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, rect_size.y)), fill_color)
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(1, 1, 1, 0.35), false, 2.0)
	var font := get_font("font", "Label")
	var text := str(int(ceil(value)))
	var tw := font.get_string_size(text).x
	draw_string(font, Vector2((rect_size.x - tw) / 2.0, rect_size.y / 2.0 + font.get_height() * 0.3), text, Color.white)

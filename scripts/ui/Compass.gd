extends Control
# Heading strip at the top of the screen: ticks every 5 degrees, letters at the
# eight compass points, and the current bearing in the middle.

const SPAN := 140.0    # degrees visible across the strip
const LABELS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}

var heading := 0.0     # degrees, 0 = north (-Z), clockwise


func _process(_delta: float) -> void:
	update()


func _draw() -> void:
	var font := get_font("font", "Label")
	var w := rect_size.x
	var px_per_deg := w / SPAN
	draw_rect(Rect2(Vector2(0, 0), rect_size), Color(0, 0, 0, 0.28))
	var first := int(floor((heading - SPAN / 2.0) / 5.0)) * 5
	for d in range(first, first + int(SPAN) + 10, 5):
		var x := w / 2.0 + (d - heading) * px_per_deg
		if x < 0.0 or x > w:
			continue
		var deg := int(posmod(d, 360))
		var fade: float = clamp(1.0 - abs(x - w / 2.0) / (w / 2.0), 0.0, 1.0)
		if LABELS.has(deg):
			var t: String = LABELS[deg]
			var tw := font.get_string_size(t).x
			draw_string(font, Vector2(x - tw / 2.0, 24.0), t, Color(1, 1, 1, 0.35 + fade * 0.65))
		elif deg % 15 == 0:
			draw_line(Vector2(x, 10), Vector2(x, 24), Color(1, 1, 1, 0.3 + fade * 0.6), 2.0)
		else:
			draw_line(Vector2(x, 14), Vector2(x, 22), Color(1, 1, 1, 0.2 + fade * 0.4), 1.0)
	draw_colored_polygon(PoolVector2Array([Vector2(w / 2.0 - 6, 0), Vector2(w / 2.0 + 6, 0), Vector2(w / 2.0, 8)]), Color(1.0, 0.85, 0.3))
	var bearing := "%d" % int(posmod(round(heading), 360))
	var bw := font.get_string_size(bearing).x
	draw_string(font, Vector2(w / 2.0 - bw / 2.0, rect_size.y + 18.0), bearing, Color(1, 1, 1, 0.9))

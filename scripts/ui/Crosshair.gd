extends Control
# Centre crosshair plus a hit marker that flashes when a shot lands.

var hit := 0.0
var killed := false


func flash(is_kill: bool) -> void:
	hit = 1.0
	killed = is_kill


func _process(delta: float) -> void:
	if hit > 0.0:
		hit = max(0.0, hit - delta * 5.0)
	update()


func _draw() -> void:
	var c := rect_size / 2.0
	var col := Color(1, 1, 1, 0.9)
	var gap := 5.0
	var ln := 9.0
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + ln, 0), col, 2.0)
	draw_line(c - Vector2(gap, 0), c - Vector2(gap + ln, 0), col, 2.0)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + ln), col, 2.0)
	draw_line(c - Vector2(0, gap), c - Vector2(0, gap + ln), col, 2.0)
	draw_circle(c, 1.5, col)
	if hit > 0.0:
		var hc := Color(1.0, 0.25, 0.2, hit) if killed else Color(1, 1, 1, hit)
		var d := 12.0
		draw_line(c + Vector2(d, d), c + Vector2(d * 2, d * 2), hc, 3.0)
		draw_line(c + Vector2(-d, d), c + Vector2(-d * 2, d * 2), hc, 3.0)
		draw_line(c + Vector2(d, -d), c + Vector2(d * 2, -d * 2), hc, 3.0)
		draw_line(c + Vector2(-d, -d), c + Vector2(-d * 2, -d * 2), hc, 3.0)

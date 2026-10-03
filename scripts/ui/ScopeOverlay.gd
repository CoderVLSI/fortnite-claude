extends Control
# Full-screen sniper scope: black surround with a round view, a duplex reticle (thick outer posts, thin
# inner lines) with milliradian dots and a red centre dot. Shown only while the player is scoped in.

var player


func _process(_delta: float) -> void:
	var on: bool = player != null and player.is_scoped()
	if on != visible:
		visible = on
	if on:
		update()


func _draw() -> void:
	var size := rect_size
	var c := size / 2.0
	var r: float = min(size.x, size.y) * 0.47
	var black := Color(0, 0, 0, 1)
	# everything outside the circle: bars around its bounding square, then the four corners cut by the arc
	draw_rect(Rect2(Vector2(0, 0), Vector2(c.x - r, size.y)), black)
	draw_rect(Rect2(Vector2(c.x + r, 0), Vector2(size.x - c.x - r, size.y)), black)
	draw_rect(Rect2(Vector2(c.x - r, 0), Vector2(2.0 * r, c.y - r)), black)
	draw_rect(Rect2(Vector2(c.x - r, c.y + r), Vector2(2.0 * r, size.y - c.y - r)), black)
	var signs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for q in range(4):
		var a0: float = PI + q * PI / 2.0
		var pts := PoolVector2Array()
		pts.append(c + signs[q] * r)
		for i in range(25):
			var a := a0 + (PI / 2.0) * float(i) / 24.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, black)
	draw_arc(c, r, 0, TAU, 96, Color(0.05, 0.05, 0.06, 1), 8.0)
	draw_arc(c, r - 6.0, 0, TAU, 96, Color(1, 1, 1, 0.10), 2.0)
	draw_circle(c, r - 8.0, Color(0.55, 0.75, 1.0, 0.05))                 # faint glass tint
	var line := Color(0, 0, 0, 0.92)
	var gap := 7.0
	var thick_from: float = r * 0.42
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + dir * gap, c + dir * thick_from, line, 1.6)               # thin inner section
		draw_line(c + dir * thick_from, c + dir * (r - 8.0), line, 5.0)         # thick outer post
		for k in range(1, 5):                                                    # mil dots
			draw_circle(c + dir * (gap + 26.0 * k), 2.0, line)
	draw_circle(c, 2.4, Color(1.0, 0.2, 0.12, 0.95))

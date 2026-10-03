extends Control
# Pings on the screen: a diamond with the distance where it is, or pinned to the edge pointing the way when it is off screen.

const COLORS := {"go": Color(0.35, 0.85, 1.0), "enemy": Color(1.0, 0.3, 0.25), "loot": Color(1.0, 0.85, 0.25)}

var world
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)


func _process(_delta: float) -> void:
	var want: bool = world != null and world.pings.size() > 0
	if visible != want:
		visible = want
	if want:
		update()


func _draw() -> void:
	var cam := get_viewport().get_camera()
	if cam == null or world == null or font == null or world.player == null:
		return
	var me: Vector3 = world.player.global_transform.origin
	var size := rect_size
	for pg in world.pings:
		var col: Color = COLORS.get(pg.kind, Color.white)
		var a: float = clamp(pg.t / 2.0, 0.0, 1.0)
		var pos: Vector3 = pg.pos
		var behind := cam.is_position_behind(pos)
		var sp: Vector2 = cam.unproject_position(pos)
		var margin := 38.0
		var inside: bool = not behind and sp.x > margin and sp.x < size.x - margin and sp.y > margin and sp.y < size.y - margin
		var dir := Vector2.ZERO
		if not inside:
			var c := size / 2.0
			dir = (sp - c) if not behind else (c - sp)
			if dir.length() < 1.0:
				dir = Vector2(0, 1)
			dir = dir.normalized()
			var k: float = min((size.x / 2.0 - margin) / max(abs(dir.x), 0.001), (size.y / 2.0 - margin) / max(abs(dir.y), 0.001))
			sp = c + dir * k
		var pulse: float = 1.0 + sin(OS.get_ticks_msec() * 0.008) * 0.12
		var r: float = 13.0 * pulse
		var pts := PoolVector2Array([sp + Vector2(0, -r), sp + Vector2(r * 0.8, 0), sp + Vector2(0, r), sp + Vector2(-r * 0.8, 0)])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85 * a))
		draw_polyline(PoolVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.8 * a), 2.0)
		if not inside:
			var tip := sp + dir * (r + 6.0)
			var side := Vector2(-dir.y, dir.x) * 6.0
			draw_colored_polygon(PoolVector2Array([tip + dir * 8.0, tip + side, tip - side]), Color(col.r, col.g, col.b, a))
		var label := "%d m" % int(me.distance_to(pos))
		var w := font.get_string_size(label).x
		draw_string(font, sp + Vector2(-w / 2.0 + 1, r + 19), label, Color(0, 0, 0, a))
		draw_string(font, sp + Vector2(-w / 2.0, r + 18), label, Color(1, 1, 1, a))
		if pg.owner != "" and not pg.mine:
			var ow := font.get_string_size(pg.owner).x
			draw_string(font, sp + Vector2(-ow / 2.0, -r - 6), pg.owner, Color(col.r, col.g, col.b, a))

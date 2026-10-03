extends Control

const MapColors = preload("res://scripts/ui/MapColors.gd")
# Full map overlay (M key / tap the minimap): terrain heat-map, roads, named POIs, storm
# circles, supply drops, the bus route, the boss and the player.

const N := 160

var world
var _tex: ImageTexture
var _icons := {}                # keeps the generated vehicle icons alive between draws
var _small: DynamicFont         # POI names: smaller than the HUD font so thirteen of them fit
var _pending := []              # [text, centre, colour, is_town] collected while drawing, then laid out and drawn on top


func _build_texture() -> void:
	_tex = MapColors.make_texture(world.terrain, N)


func _label_font(fallback: Font) -> Font:
	if _small == null:
		var data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
		if data != null:
			_small = DynamicFont.new()
			_small.font_data = data
			_small.size = 17
			_small.use_filter = true
	return _small if _small != null else fallback


func _icon(name: String):
	if not _icons.has(name):
		var path := "res://assets/icons/%s.png" % name
		_icons[name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[name]


func _process(_delta: float) -> void:
	if visible:
		update()


func _draw() -> void:
	if world == null or world.player == null:
		return
	if _tex == null:
		_build_texture()
	var font := get_font("font", "Label")
	var half: float = world.terrain.half
	var s := rect_size.x / (half * 2.0)
	var mid := rect_size / 2.0
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0, 0, 0, 0.6))
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, rect_size), false)
	for r in world.poi_roads:
		draw_line(mid + r[0] * s, mid + r[1] * s, Color(0.62, 0.52, 0.36, 0.9), 2.0)

	var storm = world.storm
	draw_arc(mid + storm.center * s, storm.radius * s, 0, TAU, 96, Color(0.72, 0.42, 1.0), 3.0)
	if storm.waiting and not storm.finished and storm.active:
		draw_arc(mid + storm.next_center * s, storm.next_radius * s, 0, TAU, 64, Color(1, 1, 1, 0.95), 2.0)

	_pending.clear()
	_label(font, mid, s, Vector2.ZERO, "MAPLE SQUARE", Color(1, 1, 1))
	for poi in world.pois:
		var tint := Color(1.0, 0.85, 0.3) if poi.def.has("boss") else Color.white
		_label(font, mid, s, poi.center, poi.name, tint)

	for sup in get_tree().get_nodes_in_group("supply"):
		if is_instance_valid(sup) and not sup.opened:
			var sp := Vector2(sup.global_transform.origin.x, sup.global_transform.origin.z)
			draw_rect(Rect2(mid + sp * s - Vector2(6, 6), Vector2(12, 12)), Color(1.0, 0.3, 0.25))
			draw_rect(Rect2(mid + sp * s - Vector2(6, 6), Vector2(12, 12)), Color.white, false, 2.0)
	if world.boss != null and is_instance_valid(world.boss) and not world.boss.is_dead:
		var bp := Vector2(world.boss.global_transform.origin.x, world.boss.global_transform.origin.z)
		draw_circle(mid + bp * s, 6.0, Color(1.0, 0.3, 0.1))
		draw_circle(mid + bp * s, 3.0, Color(1.0, 0.9, 0.3))
	for v in get_tree().get_nodes_in_group("vehicles"):
		if is_instance_valid(v):
			var vp := Vector2(v.global_transform.origin.x, v.global_transform.origin.z)
			var vt = _icon("vehicle_" + str(v.kind))
			if vt != null:
				draw_texture_rect(vt, Rect2(mid + vp * s - Vector2(15, 15), Vector2(30, 30)), false)
			else:
				draw_rect(Rect2(mid + vp * s - Vector2(3, 3), Vector2(6, 6)), Color(0.4, 0.9, 1.0))
	if world.bus != null and is_instance_valid(world.bus):
		var bus_p := Vector2(world.bus.global_transform.origin.x, world.bus.global_transform.origin.z)
		var bd := Vector2(world.bus.direction.x, world.bus.direction.z)
		draw_line(mid + (bus_p - bd * world.BUS_LENGTH) * s, mid + (bus_p + bd * world.BUS_LENGTH) * s, Color(1.0, 0.7, 0.2, 0.5), 2.0)
		var bt = _icon("vehicle_bus")
		if bt != null:
			draw_texture_rect(bt, Rect2(mid + bus_p * s - Vector2(20, 20), Vector2(40, 40)), false)
		else:
			draw_circle(mid + bus_p * s, 6.0, Color(1.0, 0.8, 0.3))

	_draw_labels(font)                      # names go on top of the icons, nudged apart so none overlap

	var p = world.player
	var pp := Vector2(p.global_transform.origin.x, p.global_transform.origin.z)
	var fwd := Vector2(-sin(p.rotation.y), -cos(p.rotation.y))
	var perp := Vector2(-fwd.y, fwd.x)
	var c := mid + pp * s
	draw_colored_polygon(PoolVector2Array([c + fwd * 12.0, c - fwd * 7.0 + perp * 7.5, c - fwd * 7.0 - perp * 7.5]), Color(1, 1, 1))
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(1, 1, 1, 0.7), false, 3.0)
	var title := "ISLAND MAP   [M] close"
	draw_string(font, Vector2(12, 26), title, Color(1, 1, 1, 0.9))


func _label(_font: Font, mid: Vector2, s: float, pos: Vector2, text: String, color: Color) -> void:
	_pending.append([text, mid + pos * s, color])


func _draw_labels(font: Font) -> void:
	var f := _label_font(font)
	var taken := []
	for entry in _pending:
		var c: Vector2 = entry[1]
		draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), entry[2])                     # the marker
		var w := f.get_string_size(entry[0]).x
		var best := Rect2()
		for off in [Vector2(0, 14), Vector2(0, -34), Vector2(0, 40), Vector2(0, -60), Vector2(0, 66), Vector2(0, -86)]:
			var r := Rect2(c + off + Vector2(-w / 2.0 - 4, 0), Vector2(w + 8, 22))
			var clash := false
			for t in taken:
				if r.intersects(t):
					clash = true
					break
			best = r
			if not clash:
				break
		taken.append(best)
		draw_rect(best, Color(0, 0, 0, 0.62))
		draw_string(f, best.position + Vector2(4, 17), entry[0], entry[2])

extends Control

const MapColors = preload("res://scripts/ui/MapColors.gd")
# North-up island map: storm circles, buildings, the player and nearby enemies.

const RADAR_RANGE := 45.0   # enemies are only shown when this close

var world
var _tex: ImageTexture
var _small: DynamicFont         # place-name banner font: small enough for the longest POI name


func _process(_delta: float) -> void:
	update()


func _draw() -> void:
	if world == null or world.player == null:
		return
	var half: float = world.terrain.half
	var s := rect_size.x / (half * 2.0)
	var mid := rect_size / 2.0

	if _tex == null:
		_tex = MapColors.make_texture(world.terrain, 96)
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, rect_size), false)                          # sea, beaches, biomes, mountains
	for b in world.building_positions:
		draw_rect(Rect2(mid + b * s - Vector2(2, 2), Vector2(4, 4)), Color(0.93, 0.90, 0.80))

	var storm = world.storm
	draw_arc(mid + storm.center * s, storm.radius * s, 0, TAU, 64, Color(0.70, 0.40, 1.0), 2.5)
	if storm.waiting and not storm.finished:
		draw_arc(mid + storm.next_center * s, storm.next_radius * s, 0, TAU, 48, Color(1, 1, 1, 0.9), 1.5)

	for sup in get_tree().get_nodes_in_group("supply"):
		if is_instance_valid(sup) and not sup.opened:
			var sp := Vector2(sup.global_transform.origin.x, sup.global_transform.origin.z)
			draw_rect(Rect2(mid + sp * s - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.3, 0.25))
			draw_rect(Rect2(mid + sp * s - Vector2(4, 4), Vector2(8, 8)), Color.white, false, 1.5)
	if world.bus != null and is_instance_valid(world.bus):
		var bp := Vector2(world.bus.global_transform.origin.x, world.bus.global_transform.origin.z)
		var bd := Vector2(world.bus.direction.x, world.bus.direction.z)
		draw_line(mid + bp * s - bd * 8.0, mid + bp * s + bd * 8.0, Color(1.0, 0.7, 0.2), 4.0)
		draw_circle(mid + bp * s + bd * 8.0, 3.5, Color(1.0, 0.95, 0.6))

	var p = world.player
	var pp := Vector2(p.global_transform.origin.x, p.global_transform.origin.z)
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == p or f.is_dead:
			continue
		var fp := Vector2(f.global_transform.origin.x, f.global_transform.origin.z)
		if fp.distance_to(pp) < RADAR_RANGE:
			draw_circle(mid + fp * s, 2.8, Color(1.0, 0.25, 0.2))

	var fwd := Vector2(-sin(p.rotation.y), -cos(p.rotation.y))
	var perp := Vector2(-fwd.y, fwd.x)
	var c := mid + pp * s
	draw_colored_polygon(PoolVector2Array([c + fwd * 9.0, c - fwd * 5.0 + perp * 5.5, c - fwd * 5.0 - perp * 5.5]), Color(1, 1, 1))
	var font := get_font("font", "Label")
	if _small == null:
		var data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
		if data != null:
			_small = DynamicFont.new()
			_small.font_data = data
			_small.size = 15
			_small.use_filter = true
	if _small != null:
		font = _small
	var loc: String = world.location_name(p.global_transform.origin)
	draw_rect(Rect2(Vector2(0, rect_size.y - 24), Vector2(rect_size.x, 24)), Color(0, 0, 0, 0.55))
	var nw := font.get_string_size(loc).x
	draw_string(font, Vector2(max((rect_size.x - nw) / 2.0, 2.0), rect_size.y - 7), loc, Color.white)
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(1, 1, 1, 0.6), false, 2.0)

extends Control
# North-up island map: storm circles, buildings, the player and nearby enemies.

const RADAR_RANGE := 45.0   # enemies are only shown when this close

var world


func _process(_delta: float) -> void:
	update()


func _draw() -> void:
	if world == null or world.player == null:
		return
	var half: float = world.terrain.half
	var s := rect_size.x / (half * 2.0)
	var mid := rect_size / 2.0

	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.10, 0.34, 0.52, 0.85))                # sea
	draw_circle(mid, half * 0.80 * s, Color(0.52, 0.70, 0.38, 0.95))                       # island
	for b in world.building_positions:
		draw_rect(Rect2(mid + b * s - Vector2(2, 2), Vector2(4, 4)), Color(0.93, 0.90, 0.80))

	var storm = world.storm
	draw_arc(mid + storm.center * s, storm.radius * s, 0, TAU, 64, Color(0.70, 0.40, 1.0), 2.5)
	if storm.waiting and not storm.finished:
		draw_arc(mid + storm.next_center * s, storm.next_radius * s, 0, TAU, 48, Color(1, 1, 1, 0.9), 1.5)

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
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(1, 1, 1, 0.6), false, 2.0)

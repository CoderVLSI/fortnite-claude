extends Control
# Names (and a thin health bar) floating over the other human players in an online match.

var player
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)


func _process(_delta: float) -> void:
	var want: bool = get_tree().get_nodes_in_group("remote_players").size() > 0
	if visible != want:
		visible = want
	if want:
		update()


func _draw() -> void:
	var cam := get_viewport().get_camera()
	if cam == null or font == null:
		return
	for f in get_tree().get_nodes_in_group("remote_players"):
		if f.is_dead:
			continue
		var pos: Vector3 = f.global_transform.origin + Vector3(0, 2.35, 0)
		if cam.is_position_behind(pos):
			continue
		var dist: float = cam.global_transform.origin.distance_to(pos)
		if dist > 140.0:
			continue
		var sp: Vector2 = cam.unproject_position(pos)
		var nm: String = str(f.player_name)
		var w: float = font.get_string_size(nm).x
		var a: float = clamp(1.4 - dist / 120.0, 0.35, 1.0)
		draw_string(font, sp + Vector2(-w * 0.5 + 1, 1), nm, Color(0, 0, 0, a))
		draw_string(font, sp + Vector2(-w * 0.5, 0), nm, Color(f.color.r, f.color.g, f.color.b, a).linear_interpolate(Color(1, 1, 1, a), 0.45))
		var frac: float = clamp(f.health / max(f.max_health, 1.0), 0.0, 1.0)
		draw_rect(Rect2(sp + Vector2(-24, 5), Vector2(48, 4)), Color(0, 0, 0, 0.6 * a))
		draw_rect(Rect2(sp + Vector2(-24, 5), Vector2(48.0 * frac, 4)), Color(0.35, 0.9, 0.4, a))

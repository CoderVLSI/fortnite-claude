extends Reference
# World markers shared by the big map and the minimap, drawn with the UI icons:
#   Keepers (quest givers)  ui_quest      Supply Llamas  ui_llama      Reboot Vans  ui_reboot_card      Fuel pumps  ui_fuel
# `cache` is the caller's own dictionary of loaded textures (so nothing outlives the map when the game closes).

static func tex(cache: Dictionary, name: String):
	if not cache.has(name):
		var path := "res://assets/ui/%s.png" % name
		cache[name] = load(path) if ResourceLoader.exists(path) else null
	return cache[name]


static func _icon(ci: CanvasItem, cache: Dictionary, name: String, at: Vector2, size: float, fallback: Color) -> void:
	var t = tex(cache, name)
	if t != null:
		ci.draw_texture_rect(t, Rect2(at - Vector2(size, size) / 2.0, Vector2(size, size)), false)
	else:
		ci.draw_circle(at, size * 0.3, fallback)


# big = the full-screen map (bigger icons, everything shown); small = the corner minimap (llamas and vans only, Keepers as dots).
static func draw(ci: CanvasItem, cache: Dictionary, tree: SceneTree, mid: Vector2, s: float, big: bool) -> void:
	for n in tree.get_nodes_in_group("llamas"):
		if is_instance_valid(n) and not n.is_dead:
			_icon(ci, cache, "ui_llama", mid + Vector2(n.global_transform.origin.x, n.global_transform.origin.z) * s, 30.0 if big else 15.0, Color(1.0, 0.4, 0.8))
	for n in tree.get_nodes_in_group("reboot_vans"):
		if is_instance_valid(n):
			_icon(ci, cache, "ui_reboot_card", mid + Vector2(n.global_transform.origin.x, n.global_transform.origin.z) * s, 26.0 if big else 13.0, Color(0.4, 0.9, 1.0))
	for n in tree.get_nodes_in_group("npcs"):
		if not is_instance_valid(n):
			continue
		var at: Vector2 = mid + Vector2(n.global_transform.origin.x, n.global_transform.origin.z) * s
		if big:
			_icon(ci, cache, "ui_quest", at, 24.0, Color(1.0, 0.85, 0.3))
		else:
			ci.draw_circle(at, 3.0, Color(1.0, 0.85, 0.25))
			ci.draw_arc(at, 3.0, 0, TAU, 10, Color(0.2, 0.1, 0.0), 1.0)
	if big:
		for n in tree.get_nodes_in_group("gas_pumps"):
			if is_instance_valid(n):
				_icon(ci, cache, "ui_fuel", mid + Vector2(n.global_transform.origin.x, n.global_transform.origin.z) * s, 20.0, Color(1.0, 0.5, 0.3))

extends SceneTree
# Which control would receive a mouse click at a point? (walks the UI the way Godot does)

func _init() -> void:
	call_deferred("_run")


func _hits(n: Node, pos: Vector2, out: Array) -> void:
	for c in n.get_children():
		_hits(c, pos, out)
	if n is Control and n.is_visible_in_tree() and n.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		var r: Rect2 = n.get_global_rect()
		if r.has_point(pos):
			out.append(n)


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var hud = world.hud
	hud.root.visible = true
	hud.open_inventory()
	yield(self, "idle_frame")
	var L = hud.inventory._layout()
	var pos: Vector2 = L.slots[2].position + Vector2(40, 40)
	var out := []
	_hits(world, pos, out)
	print("PROBE inventory visible=", hud.inventory.visible, " player.input_enabled=", world.player.input_enabled, " hovered controls at ", pos, ":")
	for n in out:
		print("PROBE   ", n.get_path(), "  filter=", n.mouse_filter)
	quit(0)

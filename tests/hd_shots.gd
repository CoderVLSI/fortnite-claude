extends SceneTree
# Screenshots of HD Mode in a real match: tests/out/hdgame_*.png (pixel = same scene with --pixel)
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	yield(self, "idle_frame")
	var S = root.get_node("Settings")
	S.prefs["graphics_mode"] = 0 if "--pixel" in OS.get_cmdline_args() else 1
	for a in OS.get_cmdline_args():
		if a.begins_with("skin="):
			S.loadout["skin"] = a.substr(5)
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	for f in get_nodes_in_group("fighters"):
		if f != world.player:
			f.set_physics_process(false)
	var p = world.player
	var t = world.terrain
	var base := Vector3(60, 0, 40)
	var y: float = t.height_at(base.x, base.z)
	p.global_transform.origin = Vector3(base.x, y + 1.0, base.z)
	p.mode = p.Mode.GROUND
	p.give_weapon("assault", 3, 120)
	p.select_slot(1)
	p.rotation.y = PI
	var tag := "pixel" if "--pixel" in OS.get_cmdline_args() else "hd"
	world.spawn_vehicle("buggy", Vector3(base.x - 5, y + 1.5, base.z - 6), 0.5)
	world.spawn_vehicle("quad", Vector3(base.x + 4, y + 1.5, base.z - 7), -0.4)
	world.add_vending("healing", Vector2(base.x + 8, base.z - 3), Vector2(base.x, base.z))
	world._add_chest("chest", Vector3(base.x - 3, y, base.z - 3), 0.3)
	world.spawn_item(load("res://scripts/Items.gd").make_weapon("sniper", 3), Vector3(base.x + 2, y + 0.5, base.z - 2))
	var d := Directory.new()
	d.make_dir_recursive("res://tests/out")
	for i in range(60):
		yield(self, "physics_frame")
	for shot in range(3):
		p.rotation.y = PI + [0.0, 0.55, -0.6][shot]
		for i in range(20):
			yield(self, "idle_frame")
		var img := root.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png("res://tests/out/hdgame_%s_%d.png" % [tag, shot])
	quit()

extends SceneTree
# POI test: every named location exists, resolves its name, has loot, and the boss is in place.
# Screenshots each POI from above/behind.
#
#   xvfb-run -a godot3 --path . -s res://tests/poi_test.gd -- --no-bus --skip-menu --no-capture --shots=tests/out/poi

var failures := []
var shots_dir := ""


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss:
			f.queue_free()
	p.set_physics_process(false)
	var cam := Camera.new()
	cam.far = 600.0
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()

	check(world.pois.size() == 6, "six POIs were placed (%d)" % world.pois.size())
	var names := []
	for poi in world.pois:
		names.append(poi.name)
		var c: Vector2 = poi.center
		var h: float = world.terrain.height_at(c.x, c.y)
		check(h > 0.5, "%s is on land (height %.1f, at %.0f,%.0f)" % [poi.name, h, c.x, c.y])
		check(world.location_name(Vector3(c.x, h, c.y)) == poi.name, "%s resolves its own name" % poi.name)
		var built := 0
		for n in poi.nodes:
			if n != null:
				built += 1
		check(built == poi.def.props.size(), "%s built all %d props" % [poi.name, built])
	var chests := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("open"):
			chests += 1
	check(chests >= 30, "chests are spread around (%d)" % chests)
	var vaults := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("open") and n.kind == "vault":
			vaults += 1
	check(vaults == 1, "the bunker holds one vault")
	check(world.boss != null and is_instance_valid(world.boss) and not world.boss.is_dead, "the Warden stands guard")
	if world.boss:
		var w = world.boss.selected_item()
		check(w != null and w.kind == "weapon" and w.rarity == 5, "the Warden carries a mythic (%s)" % (w.id if w != null else "none"))
		check(world.boss.max_health == 300.0 and world.boss.shield >= 99.0, "boss is tough (hp %.0f, shield %.0f)" % [world.boss.max_health, world.boss.shield])

	# killing the boss drops the mythic
	if world.boss:
		var before := 0
		for n in get_nodes_in_group("interactable"):
			if n.has_method("setup") and n.item.kind == "weapon" and n.item.rarity == 5:
				before += 1
		world.boss.take_damage(5000.0, p)
		yield(self, "physics_frame")
		yield(self, "physics_frame")
		var after := 0
		for n in get_nodes_in_group("interactable"):
			if n.has_method("setup") and n.item.kind == "weapon" and n.item.rarity == 5:
				after += 1
		check(after == before + 1, "the Warden drops his mythic weapon on death")

	if shots_dir != "":
		for poi in world.pois:
			var c: Vector2 = poi.center
			var h: float = world.terrain.height_at(c.x, c.y)
			var out := Vector3(cos(-poi.frame_yaw), 0, sin(-poi.frame_yaw))
			cam.look_at_from_position(Vector3(c.x, h + 38.0, c.y) + out * -42.0 + Vector3(0, 0, 0), Vector3(c.x, h + 2.0, c.y), Vector3.UP)
			yield(self, "idle_frame")
			yield(self, "idle_frame")
			var img := root.get_texture().get_data()
			img.flip_y()
			img.save_png("%s/%s.png" % [shots_dir, poi.id])
			print("SHOT  ", poi.id)
		# whole-island overview
		cam.look_at_from_position(Vector3(0, 300, 120), Vector3(0, 0, 0), Vector3.UP)
		world.hud.root.visible = false
		yield(self, "idle_frame")
		yield(self, "idle_frame")
		var ov := root.get_texture().get_data()
		ov.flip_y()
		ov.save_png("%s/overview.png" % shots_dir)
		print("SHOT  overview")
		world.hud.root.visible = true
		world.hud.map_screen.visible = true
		cam.look_at_from_position(Vector3(0, 90, 0), Vector3(0, 0, 0), Vector3.UP)
		yield(self, "idle_frame")
		yield(self, "idle_frame")
		var mp := root.get_texture().get_data()
		mp.flip_y()
		mp.save_png("%s/map_screen.png" % shots_dir)
		print("SHOT  map_screen")

	print("POI_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# Buildings: doors open by themselves, buildings show their health and come down, nothing opens through a wall,
# the minimap shows the biomes, and there are real mountains.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "idle_frame")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(_frames(4), "completed")
	var p = world.player
	p.max_health = 1000000.0
	p.health = p.max_health
	var terrain = world.terrain

	# mountains and biomes
	var peak := 0.0
	var x := -200.0
	while x < 200.0:
		var z := -200.0
		while z < 200.0:
			peak = max(peak, terrain.raw_height(x, z))
			z += 6.0
		x += 6.0
	check(peak > 30.0, "the island has tall mountains (peak %.0f m)" % peak)
	var MapColors = load("res://scripts/ui/MapColors.gd")
	var snow: Color = MapColors.color_at(terrain, 200.0 * cos(deg2rad(315.0)), 200.0 * sin(deg2rad(315.0)))
	var lava: Color = MapColors.color_at(terrain, 200.0 * cos(deg2rad(232.0)), 200.0 * sin(deg2rad(232.0)))
	var desert: Color = MapColors.color_at(terrain, 200.0 * cos(deg2rad(62.0)), 200.0 * sin(deg2rad(62.0)))
	check(snow.v > 0.8 and lava.v < 0.6 and desert.r > desert.b + 0.2, "map colours: snow bright, lava dark, desert tan (%s %s %s)" % [snow, lava, desert])
	check(world.hud.minimap._tex != null, "the minimap draws the biome texture")

	# doors
	var doors := get_nodes_in_group("doors")
	check(doors.size() >= 10, "buildings have doors (%d)" % doors.size())
	var d = doors[0]
	var dpos: Vector3 = d.global_transform.origin
	p.global_transform.origin = dpos + d.global_transform.basis.z * 1.5 + Vector3(0, 0.5, 0)
	p.velocity = Vector3.ZERO
	yield(_frames(25), "completed")
	check(d._open and d._pivot.rotation.y < -1.2, "a door opens by itself when you walk up (%.2f rad)" % d._pivot.rotation.y)
	p.global_transform.origin = dpos + Vector3(0, 0.5, 40)
	yield(_frames(40), "completed")
	check(not d._open and d._pivot.rotation.y > -0.3, "and closes when you leave (%.2f rad)" % d._pivot.rotation.y)

	# chests do not open through walls
	var spot := Vector3(24, 0, 46)
	spot.y = terrain.height_at(spot.x, spot.z)
	p.global_transform.origin = spot + Vector3(0, 1.0, 0)
	p.velocity = Vector3.ZERO
	yield(_frames(6), "completed")
	var chest = world._add_chest("chest", spot + Vector3(2.4, 0, 0), 0.0)
	yield(_frames(2), "completed")
	check(p._can_reach(chest), "a chest in the open can be reached")
	var wall := StaticBody.new()
	wall.collision_layer = 1
	var cs := CollisionShape.new()
	var bx := BoxShape.new()
	bx.extents = Vector3(0.2, 2.0, 3.0)
	cs.shape = bx
	wall.add_child(cs)
	world.add_child(wall)
	wall.global_transform.origin = spot + Vector3(1.2, 2.0, 0)
	yield(_frames(3), "completed")
	check(not p._can_reach(chest), "the same chest behind a wall cannot be opened")
	wall.queue_free()

	# destructible buildings
	var bld = null
	for c in world.get_children():
		if c.has_meta("hits_max") and c.get_meta("hits_max") <= 16:
			bld = c
			break
	check(bld != null, "buildings are destructible")
	var body = null
	for k in bld.get_children():
		if k is StaticBody and k.has_meta("structure"):
			body = k
			break
	if body == null:
		for k in bld.get_children():
			for kk in k.get_children():
				if kk is StaticBody and kk.has_meta("structure"):
					body = kk
	check(body != null, "a building has pickaxe-able walls")
	var fractions := []
	p.connect("harvested", self, "_on_harvest", [fractions])
	var max_hits: int = int(bld.get_meta("hits_max"))
	for i in range(max_hits):
		world.harvest_hit(body, 0, "wood", p, bld.global_transform.origin)
	check(fractions.size() == max_hits and fractions[0] > fractions[fractions.size() - 1] and fractions[fractions.size() - 1] == 0.0, "the building's health bar drains to zero (%d reports)" % fractions.size())
	check(bld.has_meta("fallen"), "the building comes down")
	yield(_frames(10), "completed")
	var solid := false
	for k in bld.get_children():
		if k is StaticBody and k.collision_layer != 0:
			solid = true
	check(not solid, "its walls stop blocking")
	for i in range(220):
		yield(self, "idle_frame")
		if not is_instance_valid(bld):
			break
	check(not is_instance_valid(bld) or bld.is_queued_for_deletion(), "the ruins are cleared away")

	print("STRUCTURE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)


func _on_harvest(_pos, fraction, _kind, _label, _id, store) -> void:
	store.append(fraction)

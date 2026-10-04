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
	var snow := Color(0, 0, 0)
	var lava := Color(1, 1, 1)
	var desert := Color(0, 0, 0)
	for k in [0.5, 0.56, 0.62, 0.68]:               # sample a few distances: a spot can land on a rocky ridge
		var r: float = terrain.half * k
		var sc: Color = MapColors.color_at(terrain, r * cos(deg2rad(315.0)), r * sin(deg2rad(315.0)))
		var lc: Color = MapColors.color_at(terrain, r * cos(deg2rad(232.0)), r * sin(deg2rad(232.0)))
		var dc: Color = MapColors.color_at(terrain, r * cos(deg2rad(62.0)), r * sin(deg2rad(62.0)))
		if sc.v > snow.v:
			snow = sc
		if lc.v < lava.v:
			lava = lc
		if dc.r - dc.b > desert.r - desert.b:
			desert = dc
	check(snow.v > 0.65 and snow.v > lava.v + 0.12 and lava.v < 0.6 and desert.r > desert.b + 0.2, "map colours: snow bright, lava dark, desert tan (%s %s %s)" % [snow, lava, desert])
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

	# buildings break a piece at a time
	var bld = null
	for c in get_nodes_in_group("structures"):
		if c.has_meta("res") and str(c.get_meta("res")).begins_with("house") and c.global_transform.origin.distance_to(p.global_transform.origin) < 400.0:
			bld = c
			break
	check(bld != null, "buildings are destructible")
	var body = null
	var stack := [bld]
	while stack.size() > 0 and body == null:
		var n = stack.pop_back()
		if n is StaticBody and n.has_meta("structure"):
			body = n
		for k in n.get_children():
			stack.append(k)
	check(body != null, "a building has pickaxe-able walls")
	check(not bld.has_meta("pieces"), "an untouched building is still one cheap mesh")
	var fractions := []
	p.connect("harvested", self, "_on_harvest", [fractions])
	var at: Vector3 = bld.global_transform.origin + Vector3(0, 1.4, 0)
	world.harvest_hit(body, 0, "wood", p, at)
	check(bld.has_meta("pieces") and bld.get_meta("pieces").size() >= 6, "the first hit cuts it into pieces (%d)" % (bld.get_meta("pieces").size() if bld.has_meta("pieces") else 0))
	var pieces: Array = bld.get_meta("pieces")
	var idx: int = world._piece_near(pieces, at)
	var target = pieces[idx]
	var guard := 0
	while pieces[idx] != null and guard < 12:
		var pb = null
		for k in target.get_children():
			if k is StaticBody:
				pb = k
		if pb == null:
			break
		world.harvest_hit(pb, 0, "wood", p, at)
		guard += 1
	check(pieces[idx] == null, "five or so hits break that piece (%d hits)" % (guard + 1))
	check(fractions.size() >= 2 and fractions[0] > fractions[fractions.size() - 1] and fractions[fractions.size() - 1] == 0.0, "its health bar drains to zero (%d reports)" % fractions.size())
	var alive := 0
	for q in pieces:
		if q != null:
			alive += 1
	check(alive == pieces.size() - 1 and not bld.has_meta("fallen"), "only that piece is gone, the rest of the house stands (%d of %d left)" % [alive, pieces.size()])
	yield(_frames(10), "completed")
	# an explosion takes down everything around it, still piece by piece
	world.break_pieces_near(bld.global_transform.origin + Vector3(0, 1.5, 0), 2.5)
	alive = 0
	for q in pieces:
		if q != null:
			alive += 1
	check(alive < pieces.size() - 1 and alive > 0, "a blast removes the pieces around it but not the whole house (%d left)" % alive)
	for i in range(240):
		yield(self, "idle_frame")
	var freed := 0
	for q in pieces:
		if q == null:
			freed += 1
	check(freed >= pieces.size() - alive, "broken pieces are cleared away")

	print("STRUCTURE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)


func _on_harvest(_pos, fraction, _kind, _label, _id, store) -> void:
	store.append(fraction)

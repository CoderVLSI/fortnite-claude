extends SceneTree
# A bot that starts on one side of the biggest mountain with the safe circle on the other side must get over / around it.
var failures := []


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func _initialize() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	var keep = null
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss and not f.guard:
			if keep == null:
				keep = f
			else:
				f.queue_free()
	p.global_transform.origin = Vector3(0, -300, 0)
	p.set_physics_process(false)
	var t = world.terrain
	var peak := Vector2.ZERO
	var best := -1e9
	var x := -250.0
	while x < 250.0:
		var z := -250.0
		while z < 250.0:
			var h: float = t.raw_height(x, z)
			if h > best and Vector2(x, z).length() > 120.0:
				best = h
				peak = Vector2(x, z)
			z += 8.0
		x += 8.0
	var dir := peak.normalized()
	var start: Vector2 = peak - dir * 90.0
	var goal: Vector2 = peak + dir * 90.0
	print("NAV peak ", peak, " h=", best, " start ", start, " goal ", goal)
	world.storm.active = true
	world.storm.center = goal
	world.storm.radius = 25.0
	world.storm.waiting = true
	world.storm.time_left = 9999.0
	world.storm.damage_per_second = 0.0
	keep.mode = keep.Mode.GROUND
	keep.collision_layer = 2
	keep.collision_mask = keep.BODY_MASK
	keep.global_transform.origin = Vector3(start.x, t.height_at(start.x, start.y) + 1.5, start.y)
	keep.velocity = Vector3.ZERO
	keep.health = 100000.0
	keep.max_health = 100000.0
	var d0: float = Vector2(keep.global_transform.origin.x, keep.global_transform.origin.z).distance_to(goal)
	var t_s := 0.0
	var reached := false
	while t_s < 70.0:
		for i in range(60):
			yield(self, "physics_frame")
		t_s += 1.0
		var pos := Vector2(keep.global_transform.origin.x, keep.global_transform.origin.z)
		if pos.distance_to(goal) < 30.0:
			reached = true
			break
	var d1: float = Vector2(keep.global_transform.origin.x, keep.global_transform.origin.z).distance_to(goal)
	check(reached, "the bot reached the circle on the far side of the mountain (%.0f m -> %.0f m in %.0f s)" % [d0, d1, t_s])
	print("BOTNAV_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

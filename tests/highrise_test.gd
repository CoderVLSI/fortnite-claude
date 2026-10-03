extends SceneTree
# Skyline Heights: the high-rise POI is placed, towers have doors, loot on the upper floors, and the stairs can be climbed.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	p.max_health = 1000000.0
	p.health = p.max_health
	var poi = null
	for q in world.pois:
		if q.id == "skyline":
			poi = q
	check(poi != null, "Skyline Heights is on the map")
	if poi == null:
		quit(1)
		return
	var towers := 0
	for n in poi.nodes:
		if n != null and n.res.begins_with("highrise"):
			towers += 1
	check(towers == 7, "seven towers stand in the city (%d)" % towers)
	var tall := 0.0
	var high_chests := 0
	for c in get_nodes_in_group("interactable"):
		if c.has_method("can_interact") and c.get("kind") != null and c.global_transform.origin.distance_to(Vector3(poi.center.x, c.global_transform.origin.y, poi.center.y)) < 60.0:
			var rel: float = c.global_transform.origin.y - world.terrain.height_at(c.global_transform.origin.x, c.global_transform.origin.z)
			tall = max(tall, rel)
			if rel > 5.0:
				high_chests += 1
	check(high_chests >= 8 and tall > 30.0, "chests wait on the upper floors (%d above the ground, highest %.0f m)" % [high_chests, tall])

	# climb the first flight of the tallest tower: the stairs start at the back wall and climb towards the front
	var node: Dictionary = poi.nodes[0]
	var inst: Spatial = node.node
	var hw := 6.5
	var hd := 6.5
	var xs: float = -(hw - 0.35 - 0.95)
	var start: Vector3 = inst.global_transform.xform(Vector3(xs, 0.45, -(hd - 0.55)))
	p.global_transform.origin = start
	p.rotation.y = inst.rotation.y + PI
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	p.velocity = Vector3.ZERO
	yield(_frames(40), "completed")
	var y0: float = p.global_transform.origin.y
	Input.action_press("move_forward")
	yield(_frames(260), "completed")
	Input.action_release("move_forward")
	print("DBG start ", start, " end ", p.global_transform.origin, " inst ", inst.global_transform.origin, " yaw ", inst.rotation.y, " mode ", p.mode)
	var hit = p.get_world().direct_space_state.intersect_ray(start + Vector3(0, 3, 0), start + Vector3(0, -3, 0), [p], 1)
	print("DBG floor below start: ", hit.position if hit else "none")
	print("DBG start ", start, " end ", p.global_transform.origin, " inst ", inst.global_transform.origin, " yaw ", inst.rotation.y, " mode ", p.mode)
	var hit = p.get_world().direct_space_state.intersect_ray(start + Vector3(0, 3, 0), start + Vector3(0, -3, 0), [p], 1)
	print("DBG floor below start: ", hit.position if hit else "none")
	var rose: float = p.global_transform.origin.y - y0
	check(rose > 2.8, "the stairs climb to the first upper floor (+%.1f m)" % rose)

	# the tallest tower is destructible
	check(inst.has_meta("hits_max") and int(inst.get_meta("hits_max")) >= 100, "towers can be brought down with many pickaxe hits (%s)" % str(inst.get_meta("hits_max")))
	print("HIGHRISE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

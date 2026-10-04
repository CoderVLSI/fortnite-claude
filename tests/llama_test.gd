extends SceneTree
# Supply Llamas: they stand around the island, take shots, burst into loot, and a burst heard from the network pops the copy.

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
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	p.max_health = 100000.0
	p.health = p.max_health
	var llamas := get_nodes_in_group("llamas")
	check(llamas.size() >= 4, "Supply Llamas stand around the island (%d)" % llamas.size())
	var ids := {}
	for l in llamas:
		ids[l.net_id] = true
	check(ids.size() == llamas.size() and world.net_nodes.has(llamas[0].net_id), "each has its own network id")
	var l = llamas[0]
	var items_before := get_nodes_in_group("interactable").size()
	var hits := 0
	while not l.is_dead and hits < 100:
		l.take_damage(30.0, p)
		hits += 1
	check(l.is_dead and hits >= 5, "it takes several hits to burst (%d)" % hits)
	yield(_frames(10), "completed")
	var loot := get_nodes_in_group("interactable").size() - items_before
	check(loot >= 7, "and drops a pile of loot (%d things)" % loot)
	check(p.match_stats.get("llamas", 0) == 1, "the burst counts for the quest")
	# the pop event from another machine removes our copy without a second pile of loot
	var l2 = llamas[1]
	var before := get_nodes_in_group("interactable").size()
	world.net_event(2, "llama_pop", l2.net_id)
	yield(_frames(5), "completed")
	check(not is_instance_valid(l2) or l2.is_queued_for_deletion(), "a network pop removes the copy")
	check(get_nodes_in_group("interactable").size() <= before, "without duplicating the loot")
	# a bullet from a real gun counts
	var l3 = llamas[2]
	var y: float = world.terrain.height_at(l3.translation.x + 6.0, l3.translation.z)
	p.global_transform.origin = Vector3(l3.translation.x + 6.0, y + 1.0, l3.translation.z)
	p.mode = p.Mode.GROUND
	p.give_weapon("assault", 3)
	yield(_frames(20), "completed")
	var from: Vector3 = p.global_transform.origin + Vector3(0, 1.6, 0)
	var dir: Vector3 = ((l3.global_transform.origin + Vector3(0, 1.4, 0)) - from).normalized()
	var h0: float = l3.health
	p._fire_cd = 0.0
	p.try_fire(from, dir)
	check(l3.health < h0, "a gun hits it (%.0f -> %.0f)" % [h0, l3.health])
	print("LLAMA_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# Farming: trees break after a few hits, a glowing weak point appears, hitting it doubles materials and hits and moves it.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


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
	var data: Dictionary = world._props["TreeColliders"]
	var body = data.body
	var idx := 0
	var tpos: Vector3 = data.transforms[idx].origin
	p.global_transform.origin = tpos + Vector3(2.5, 1.0, 0)
	var at := tpos + Vector3(0.5, 1.2, 0)
	var wood0: int = p.materials.get("wood", 0) if "materials" in p else 0
	world._wp_key = ""
	world.harvest_hit(body, idx, "wood", p, at)
	check(world._wp_node != null and world._wp_node.visible, "a weak point shows up on the tree you hit")
	var wp: Vector3 = world._wp_pos
	check(wp.distance_to(tpos + Vector3(0, 1.2, 0)) < 3.0, "close to the trunk (%.1f m)" % wp.distance_to(tpos))
	var hits_before: int = data.hits.get(idx, 0)
	world.harvest_hit(body, idx, "wood", p, wp)
	check(data.hits.get(idx, 0) == hits_before + 2, "hitting the weak point counts as two hits (%d -> %d)" % [hits_before, data.hits.get(idx, 0)])
	check(world._wp_pos.distance_to(wp) > 0.01, "and the weak point moves")
	var far: Vector3 = world._wp_pos + Vector3(3, 0, 0)
	var h2: int = data.hits.get(idx, 0)
	world.harvest_hit(body, idx, "wood", p, far)
	check(data.hits.get(idx, 0) == h2 + 1, "missing it is a normal hit")
	for i in range(6):
		world.harvest_hit(body, idx, "wood", p, world._wp_pos)
	check(data.hits.get(idx, 0) >= world.HARVEST_HITS, "the tree is used up")
	print("FARM_RESULT failures=%d" % failures.size())
	quit(1 if failures.size() > 0 else 0)

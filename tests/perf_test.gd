extends SceneTree
# Frame-rate protection: distance culling hides far things and keeps near ones, the governor steps the graphics down.

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
	var settings = root.get_node("Settings")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(5):
		yield(self, "idle_frame")
	var p = world.player
	var perf = world.perf
	check(perf != null, "the world has the performance helper")
	var near_item = null
	var far_item = null
	for n in get_nodes_in_group("interactable"):
		var d: float = n.global_transform.origin.distance_to(p.global_transform.origin)
		if d < 60.0 and near_item == null:
			near_item = n
		if d > 300.0 and far_item == null:
			far_item = n
	perf.cull()
	check(far_item != null and not far_item.visible, "something far away is not drawn")
	check(near_item == null or near_item.visible, "something close still is")
	var bots_hidden := 0
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.visible:
			bots_hidden += 1
	check(bots_hidden > 5, "far-away fighters are skipped (%d)" % bots_hidden)
	var trees_hidden := 0
	for c in get_nodes_in_group("scenery"):
		if not c.visible:
			trees_hidden += 1
	check(trees_hidden > 0 and trees_hidden < get_nodes_in_group("scenery").size(), "distant tree squares are skipped, near ones kept (%d of %d)" % [trees_hidden, get_nodes_in_group("scenery").size()])
	# teleport across the island: the culling follows
	var before_far_visible: bool = far_item.visible
	p.global_transform.origin = far_item.global_transform.origin + Vector3(0, 3, 0)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	perf.cull()
	check(far_item.visible and not before_far_visible, "walking up to it draws it")

	var q: int = settings.quality
	var far0: float = p.camera.far
	for i in range(4):
		perf.step_down(12.0)
	check(world.profile.get("force_no_shadows", false) and settings.quality == 0, "the governor turns shadows and antialiasing off")
	check(p.camera.far < far0 and perf.scale < 1.0, "and shortens the view and the culling radius")
	settings.quality = q

	print("PERF_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

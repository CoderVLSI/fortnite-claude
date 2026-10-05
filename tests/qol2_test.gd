extends SceneTree
# Auto sprint setting, healing while walking.
var failures := []


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _initialize() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var Items = load("res://scripts/Items.gd")
	var settings = root.get_node("Settings")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.queue_free()
	p.max_health = 100.0
	p.mode = p.Mode.GROUND
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	yield(_frames(30), "completed")
	# auto sprint
	settings.prefs["auto_sprint"] = false
	check(not p._sprint_wanted(Vector2(0, -1)), "without the setting walking does not sprint")
	settings.prefs["auto_sprint"] = true
	check(p._sprint_wanted(Vector2(0, -1)), "with Auto sprint on, moving sprints")
	check(not p._sprint_wanted(Vector2(0, 0)), "and standing still does not")
	settings.prefs["auto_sprint"] = false
	# heal while walking: quick heal keeps going when you hold forward
	p.health = 40.0
	p.slots = [Items.pickaxe(), Items.make_consumable("bandage", 3), null, null, null, null]
	p.quick_heal()
	Input.action_press("move_forward")
	var started: bool = p._quick_slot >= 0
	for i in range(60 * 5):
		p._fire_input(1.0 / 60.0)
		yield(self, "physics_frame")
	Input.action_release("move_forward")
	check(started, "quick heal starts")
	check(p.health > 40.0, "and keeps healing while you walk (%.0f)" % p.health)
	print("QOL2_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

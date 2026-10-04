extends SceneTree
# Aim assist (phones / controllers): the view eases onto an enemy that is already near the crosshair, and ignores far-off or hidden ones.
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


func _angle_to(p, f) -> float:
	var to: Vector3 = (f.global_transform.origin + Vector3(0, 1.1, 0) - p.camera.global_transform.origin).normalized()
	return rad2deg(acos(clamp((-p.camera.global_transform.basis.z).dot(to), -1.0, 1.0)))


func _run() -> void:
	yield(self, "idle_frame")
	var Items = load("res://scripts/Items.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	var enemy = null
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
			if enemy == null and not f.is_boss:
				enemy = f
	p.max_health = 100000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.rotation.y = 0.0
	p.pitch = -0.05
	p.mode = p.Mode.GROUND
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.give_weapon("assault", 2, 90)
	p.select_slot(1)
	enemy.team = 99
	enemy.global_transform.origin = Vector3(26.0, world.terrain.height_at(26.0, 24.0), 24.0)      # 22 m ahead, a little to the right
	yield(_frames(6), "completed")
	var before: float = _angle_to(p, enemy)
	check(before > 2.0 and before < 7.0, "the enemy starts a few degrees off the crosshair (%.1f)" % before)
	for i in range(90):
		p._aim_assist(1.0 / 60.0)
		yield(self, "physics_frame")
	var after: float = _angle_to(p, enemy)
	check(after < before * 0.4, "the view eased onto them (%.1f -> %.1f degrees)" % [before, after])
	# an enemy far off to the side is left alone
	enemy.global_transform.origin = Vector3(49.0, world.terrain.height_at(49.0, 24.0), 24.0)
	yield(_frames(6), "completed")
	var yaw0: float = p.rotation.y
	p._assist_t = 0.0
	for i in range(40):
		p._aim_assist(1.0 / 60.0)
	check(abs(p.rotation.y - yaw0) < 0.001, "an enemy 45 degrees off does not steal the aim")
	# a dead one too
	enemy.global_transform.origin = Vector3(25.0, world.terrain.height_at(25.0, 24.0), 24.0)
	enemy.is_dead = true
	yield(_frames(6), "completed")
	p._assist_t = 0.0
	var yaw1: float = p.rotation.y
	for i in range(40):
		p._aim_assist(1.0 / 60.0)
	check(abs(p.rotation.y - yaw1) < 0.001, "a dead fighter is ignored")
	check(root.get_node("Settings").pref("aim_assist") == true, "aim assist is on by default")
	print("ASSIST_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# Movement test: sprint speed + FOV kick, swimming (enter, float, swim to shore, exit),
# mantling a low ledge and refusing a high wall.
#
#   xvfb-run -a godot3 --path . -s res://tests/movement_test.gd -- --no-capture --no-bus --skip-menu [--shots=DIR]

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


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _shot(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	if shots_dir == "":
		return
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("SHOT  ", name)


func _box(world, pos: Vector3, size: Vector3) -> StaticBody:
	var body := StaticBody.new()
	body.collision_layer = 1
	var cs := CollisionShape.new()
	var sh := BoxShape.new()
	sh.extents = size / 2.0
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	mi.mesh = cm
	body.add_child(mi)
	body.translation = pos + Vector3(0, size.y / 2.0, 0)
	world.add_child(body)
	return body


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.queue_free()
	p.max_health = 1000000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(0.0, y + 1.0, 30.0)
	p.rotation.y = PI / 2.0
	p.velocity = Vector3.ZERO
	yield(_frames(60), "completed")

	# --- sprint
	Input.action_press("move_forward")
	yield(_frames(60), "completed")
	var walk_speed := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_press("sprint")
	yield(_frames(90), "completed")
	var sprint_speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(sprint_speed > walk_speed + 2.0, "sprinting is faster than walking (%.1f vs %.1f m/s)" % [sprint_speed, walk_speed])
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(p.camera.fov > 75.0, "sprinting widens the field of view (%.1f)" % p.camera.fov)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	yield(_frames(30), "completed")

	# --- mantling a 1.3 m ledge
	p.global_transform.origin = Vector3(0.0, y + 1.0, 30.0)
	p.rotation.y = PI / 2.0
	p.velocity = Vector3.ZERO
	var low = _box(world, Vector3(-3.0, y, 30.0), Vector3(2.0, 1.3, 4.0))
	yield(_frames(40), "completed")
	Input.action_press("move_forward")
	var started := false
	for i in range(120):
		yield(self, "physics_frame")
		if p.mode == 5:
			started = true
			break
		if p.global_transform.origin.x < -1.6 and not started:
			Input.action_press("jump")
	Input.action_release("jump")
	check(started, "walking + jumping into a 1.3 m ledge starts a mantle")
	yield(_frames(5), "completed")
	yield(_shot("mantle_mid"), "completed")
	var n := 0
	while p.mode == 5 and n < 120:
		yield(self, "physics_frame")
		n += 1
	Input.action_release("move_forward")
	yield(_frames(20), "completed")
	var top_y: float = y + 1.3
	check(p.mode == 0 and p.global_transform.origin.y > top_y - 0.2 and p.global_transform.origin.y < top_y + 0.8, "mantle ends standing on the ledge (y=%.2f top=%.2f)" % [p.global_transform.origin.y, top_y])
	check(get_nodes_in_group("fighters").size() > 0 and root.get_node("Audio").count_of("mantle") > 0, "mantle sound played")

	# --- a 3.2 m wall can't be climbed
	p.global_transform.origin = Vector3(0.0, y + 1.0, 36.0)
	p.velocity = Vector3.ZERO
	var tall = _box(world, Vector3(-3.0, y, 36.0), Vector3(2.0, 3.2, 4.0))
	yield(_frames(40), "completed")
	Input.action_press("move_forward")
	var climbed := false
	for i in range(100):
		yield(self, "physics_frame")
		if p.mode == 5:
			climbed = true
		if p.global_transform.origin.x < -1.6:
			Input.action_press("jump")
	Input.action_release("jump")
	Input.action_release("move_forward")
	check(not climbed, "a 3.2 m wall is too high to mantle")

	# --- swimming: find open water and drop in
	var sea := Vector3.ZERO
	var found := false
	for r in range(205, 100, -1):          # the island is 480 m wide now: deep water starts further out
		var h: float = world.terrain.height_at(float(r), 0.0)
		if h < -4.0:
			sea = Vector3(float(r), -0.3, 0.0)
			found = true
			break
	check(found, "found deep water on the east side of the island")
	p.global_transform.origin = sea
	p.velocity = Vector3.ZERO
	p.rotation.y = -PI / 2.0              # facing +X (out to sea)
	yield(_frames(90), "completed")
	check(p.mode == 4, "player enters swimming mode in deep water")
	check(abs(p.global_transform.origin.y - p.SWIM_FEET_Y) < 0.45, "swimmer floats at the surface (feet y=%.2f)" % p.global_transform.origin.y)
	check(root.get_node("Audio").count_of("splash") > 0, "splash sound on entering the water")
	yield(_shot("swim_idle"), "completed")
	Input.action_press("move_forward")
	yield(_frames(60), "completed")
	var swim_speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(swim_speed > 1.5 and swim_speed < 4.5, "swimming moves at swim speed (%.1f m/s)" % swim_speed)
	check(root.get_node("Audio").count_of("swim_stroke") > 0, "swim strokes make sound")
	yield(_shot("swim_move"), "completed")
	Input.action_release("move_forward")
	# swim back to the beach: face the island (-X) and hold forward
	p.rotation.y = PI / 2.0
	Input.action_press("move_forward")
	var landed := false
	for i in range(60 * 30):
		yield(self, "physics_frame")
		if p.mode == 0:
			landed = true
			break
	Input.action_release("move_forward")
	var po: Vector3 = p.global_transform.origin
	print("DEBUG swim-back end: pos=", po, " mode=", p.mode, " vel=", p.velocity, " grounded=", p.grounded, " floor_h=", world.terrain.height_at(po.x, po.z), " yaw=", p.rotation.y, " on_floor=", p.is_on_floor(), " on_wall=", p.is_on_wall())
	check(landed, "swimming toward the island returns to walking in the shallows (x=%.0f)" % p.global_transform.origin.x)

	print("MOVE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

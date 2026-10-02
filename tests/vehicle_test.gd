extends SceneTree
# Vehicle test: enter / drive / steer / handbrake / exit a buggy, ride as passenger, run over a
# bot, shoot a vehicle until it explodes, quad bike, and a motor boat on the sea.
#
#   xvfb-run -a godot3 --path . -s res://tests/vehicle_test.gd -- --no-capture --no-bus --skip-menu [--shots=DIR]

const Items = preload("res://scripts/Items.gd")
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


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss:
			f.queue_free()
	p.max_health = 1000000.0
	p.health = p.max_health
	var audio = root.get_node("Audio")
	check(get_nodes_in_group("vehicles").size() >= 6, "vehicles are spawned around the island (%d)" % get_nodes_in_group("vehicles").size())

	# --- a buggy on the flat town street
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(8.0, y + 1.0, 30.0)
	p.rotation.y = PI / 2.0
	p.velocity = Vector3.ZERO
	var buggy = world.spawn_vehicle("buggy", Vector3(0.0, y + 1.0, 30.0), PI / 2.0)    # nose toward -X
	yield(_frames(120), "completed")
	var rest_y: float = buggy.global_transform.origin.y
	check(abs(rest_y - y) < 0.9, "buggy settles on its suspension (y %.2f ground %.2f)" % [rest_y, y])
	p.global_transform.origin = buggy.global_transform.origin + Vector3(0.0, 0.2, 2.6)
	yield(_frames(14), "completed")
	check(p.interact_target == buggy, "the buggy is the interact target (got %s)" % str(p.interact_target))
	Input.action_press("interact")
	yield(_frames(3), "completed")
	Input.action_release("interact")
	yield(_frames(3), "completed")
	check(p.mode == 6 and p.vehicle == buggy and buggy.occupants[0] == p, "pressing interact puts the player in the driver seat")
	check(audio.count_of("door") > 0, "door sound plays")

	# drive forward
	var start: Vector3 = buggy.global_transform.origin
	Input.action_press("move_forward")
	yield(_frames(120), "completed")
	var fwd_speed: float = buggy.forward_speed()
	var moved: float = _flat(buggy.global_transform.origin - start).length()
	var dir: Vector3 = (buggy.global_transform.origin - start).normalized()
	var nose: Vector3 = -buggy.global_transform.basis.z
	check(fwd_speed > 8.0, "holding forward accelerates the buggy (%.1f m/s)" % fwd_speed)
	check(moved > 12.0, "the buggy covers ground (%.0f m)" % moved)
	check(dir.dot(nose) > 0.6, "it drives where its nose points (dot %.2f)" % dir.dot(nose))
	check(audio.count_of("engine_car_loop") > 0, "engine loop is playing")
	var yaw_before: float = buggy.global_transform.basis.get_euler().y
	Input.action_press("move_left")
	yield(_frames(50), "completed")
	Input.action_release("move_left")
	var yaw_after: float = buggy.global_transform.basis.get_euler().y
	check(wrapf(yaw_after - yaw_before, -PI, PI) > 0.2, "pressing left turns the buggy left (%.2f rad)" % wrapf(yaw_after - yaw_before, -PI, PI))
	yield(_shot("buggy_drive"), "completed")
	Input.action_release("move_forward")
	Input.action_press("jump")
	yield(_frames(150), "completed")
	Input.action_release("jump")
	check(buggy.linear_velocity.length() < 2.5, "handbrake stops the buggy (%.1f m/s)" % buggy.linear_velocity.length())
	Input.action_press("move_back")
	yield(_frames(80), "completed")
	var reverse: float = buggy.forward_speed()
	Input.action_release("move_back")
	check(reverse < -1.0, "holding back reverses (%.1f m/s)" % reverse)
	Input.action_press("jump")
	yield(_frames(60), "completed")
	Input.action_release("jump")

	# exit
	Input.action_press("interact")
	yield(_frames(3), "completed")
	Input.action_release("interact")
	yield(_frames(10), "completed")
	check(p.mode == 0 and buggy.occupants[0] == null, "interact again leaves the vehicle")
	check(p.global_transform.origin.distance_to(buggy.global_transform.origin) < 4.5, "the player steps out beside it")

	# --- run over a bot
	var victim = world.get_node("Bot0") if world.has_node("Bot0") else null
	if victim == null or not is_instance_valid(victim) or victim.is_dead:
		victim = null
		for f in get_nodes_in_group("fighters"):
			if f != p and not f.is_dead and not f.is_boss:
				victim = f
	if victim != null:
		victim.set_physics_process(false)
		victim.health = 100.0
		victim.shield = 0.0
		p.global_transform.origin = buggy.global_transform.origin + Vector3(0.0, 0.2, 2.6)
		yield(_frames(10), "completed")
		Input.action_press("interact")
		yield(_frames(3), "completed")
		Input.action_release("interact")
		yield(_frames(3), "completed")
		var b: Transform = buggy.global_transform
		victim.global_transform.origin = b.origin + (-b.basis.z) * 14.0 + Vector3(0, 0.5, 0)
		Input.action_press("move_forward")
		var n := 0
		while victim.health >= 100.0 and not victim.is_dead and n < 400:
			yield(self, "physics_frame")
			n += 1
		Input.action_release("move_forward")
		check(victim.health < 100.0 or victim.is_dead, "running into a fighter hurts him (health %.0f)" % victim.health)
		Input.action_press("jump")
		yield(_frames(120), "completed")
		Input.action_release("jump")
		Input.action_press("interact")
		yield(_frames(3), "completed")
		Input.action_release("interact")
		yield(_frames(5), "completed")

	# --- passenger seat
	var buggy2 = world.spawn_vehicle("buggy", Vector3(-10.0, y + 1.0, 30.0), 0.0)
	yield(_frames(60), "completed")
	var other = null
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_dead and not f.is_boss:
			other = f
	if other != null:
		other.set_physics_process(false)
		other.global_transform.origin = buggy2.global_transform.origin + Vector3(0.0, 0.3, 2.6)
		other.enter_vehicle(buggy2, 0)
		buggy2.occupants[0] = other
		p.global_transform.origin = buggy2.global_transform.origin + Vector3(0.0, 0.2, -2.6)
		yield(_frames(14), "completed")
		check(buggy2.can_interact(), "a half-full buggy can still be boarded")
		Input.action_press("interact")
		yield(_frames(3), "completed")
		Input.action_release("interact")
		yield(_frames(3), "completed")
		check(p.mode == 6 and p.vehicle_seat == 1, "second player takes the passenger seat")
		yield(_shot("buggy_two_seats"), "completed")
		Input.action_press("interact")
		yield(_frames(3), "completed")
		Input.action_release("interact")
		yield(_frames(4), "completed")
		other.exit_vehicle()

	# --- shoot a vehicle until it explodes
	p.give_weapon("assault", 3, 300)
	var target_v = world.spawn_vehicle("buggy", Vector3(20.0, y + 1.0, 30.0), 0.0)
	yield(_frames(80), "completed")
	p.global_transform.origin = Vector3(0.0, y + 1.0, 30.0)
	p.rotation.y = 3.0 * PI / 2.0       # face +X toward the target
	p.pitch = -0.045                     # aim at the body, not over the roof
	p.head.rotation.x = -0.045
	p.velocity = Vector3.ZERO
	yield(_frames(10), "completed")
	var shots := 0
	var hp0: float = target_v.health
	while not target_v.exploded and shots < 120:
		p._fire_cd = 0.0
		p.fire_at_crosshair()
		shots += 1
		yield(self, "physics_frame")
		if p.get_ammo() == 0:
			p.start_reload()
			yield(_frames(130), "completed")
	check(target_v.health < hp0, "bullets damage a vehicle (%.0f -> %.0f)" % [hp0, target_v.health])
	check(target_v.exploded, "enough damage blows the vehicle up (%d shots)" % shots)
	check(audio.count_of("explosion") > 0, "explosion sound plays")
	check(not target_v.can_interact(), "a wreck cannot be driven")
	yield(_shot("explosion"), "completed")

	# --- quad bike
	var quad = world.spawn_vehicle("quad", Vector3(-4.0, y + 1.0, 42.0), PI / 2.0)    # a clear lane
	yield(_frames(90), "completed")
	p.global_transform.origin = quad.global_transform.origin + Vector3(0.0, 0.3, 1.9)
	yield(_frames(14), "completed")
	Input.action_press("interact")
	yield(_frames(3), "completed")
	Input.action_release("interact")
	yield(_frames(3), "completed")
	check(p.mode == 6 and p.vehicle == quad, "the quad bike can be ridden")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	yield(_frames(110), "completed")
	check(quad.forward_speed() > 9.0, "the quad accelerates (%.1f m/s, speed along nose)" % quad.forward_speed())
	Input.action_release("sprint")
	Input.action_release("move_forward")
	yield(_shot("quad_drive"), "completed")
	Input.action_press("jump")
	yield(_frames(100), "completed")
	Input.action_release("jump")
	Input.action_press("interact")
	yield(_frames(3), "completed")
	Input.action_release("interact")
	yield(_frames(5), "completed")

	# --- boat on the sea
	var sea := Vector3.ZERO
	for r in range(150, 100, -1):
		if world.terrain.height_at(float(r), -40.0) < -5.0:
			sea = Vector3(float(r), 0.4, -40.0)
			break
	var boat = world.spawn_vehicle("boat", sea, 0.0)
	yield(_frames(120), "completed")
	var boat_y: float = boat.global_transform.origin.y
	check(abs(boat_y - 0.0) < 0.9, "the boat floats at the surface (y %.2f)" % boat_y)
	p.global_transform.origin = boat.global_transform.origin + Vector3(1.9, 0.6, 0.0)
	p.velocity = Vector3.ZERO
	yield(_frames(3), "completed")
	boat.interact(p)
	yield(_frames(3), "completed")
	check(p.mode == 6 and p.vehicle == boat, "the player boards the boat")
	var bstart: Vector3 = boat.global_transform.origin
	Input.action_press("move_forward")
	yield(_frames(200), "completed")
	var bspeed: float = boat.linear_velocity.length()
	check(bspeed > 5.0, "the boat speeds across the water (%.1f m/s)" % bspeed)
	check(abs(boat.global_transform.origin.y) < 1.2, "and keeps floating while moving (y %.2f)" % boat.global_transform.origin.y)
	check(audio.count_of("engine_boat_loop") > 0, "boat engine loop plays")
	yield(_shot("boat_drive"), "completed")
	Input.action_release("move_forward")

	print("VEHICLE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

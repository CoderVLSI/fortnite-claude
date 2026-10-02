extends SceneTree
# Headless smoke test: boots the real game, then checks movement, shooting,
# storm damage, loot, bot AI, touch controls and takes screenshots.
#
#   xvfb-run -a godot3 --path . -s res://tests/smoke_test.gd -- --no-capture --shots=/tmp/shots
#
# Extra args after "--": --touch (show on-screen controls), --mobile (mobile quality profile)

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


# Synthetic touches must be in window pixels (like a real device); the engine then
# maps them through the stretch transform into the UI's virtual coordinates.
func _win(v: Vector2) -> Vector2:
	return root.get_final_transform().xform(v)


func _win_rel(v: Vector2) -> Vector2:
	return root.get_final_transform().basis_xform(v)


func _wait_idle(n: int) -> void:
	for i in range(n):
		yield(self, "idle_frame")


func _shot(name: String) -> void:
	if shots_dir == "":
		return
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var img := root.get_texture().get_data()
	img.flip_y()
	var path := "%s/%s.png" % [shots_dir, name]
	img.save_png(path)
	print("SHOT  ", path, "  ", img.get_width(), "x", img.get_height())


func _run() -> void:
	yield(self, "idle_frame")
	var packed = load("res://scenes/Main.tscn")
	check(packed != null, "Main.tscn loads")
	var world = packed.instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")

	var controls = root.get_node("Controls")
	var p = world.player
	check(world.terrain != null and p != null, "world built with terrain and player")
	check(get_nodes_in_group("fighters").size() == world.profile.bots + 1, "all %d fighters spawned" % (world.profile.bots + 1))
	check(world.building_positions.size() >= 10, "buildings placed (%d)" % world.building_positions.size())
	p.max_health = 1000000.0   # keep bots from killing the test player
	p.health = p.max_health

	yield(_frames(150), "completed")
	var o: Vector3 = p.global_transform.origin
	var ground: float = world.terrain.height_at(o.x, o.z)
	check(abs(o.y - ground) < 1.0, "player stands on the terrain (y=%.2f ground=%.2f)" % [o.y, ground])

	# --- movement
	var start: Vector3 = p.global_transform.origin
	Input.action_press("move_forward")
	yield(_frames(60), "completed")
	Input.action_release("move_forward")
	check(start.distance_to(p.global_transform.origin) > 2.0, "player walks forward (%.1f m)" % start.distance_to(p.global_transform.origin))

	# --- shooting: freeze a bot right in the crosshair line
	var target = world.get_node("Bot0")
	target.set_physics_process(false)
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	# turn until the 14 m line in front of the crosshair is not blocked by a tree or wall
	var tpos := Vector3.ZERO
	for turn in range(16):
		var b: Basis = p.global_transform.basis
		tpos = p.global_transform.origin + (-b.z) * 14.0 + b.x * p.SHOULDER_OFFSET.x
		tpos.y = world.terrain.height_at(tpos.x, tpos.z) + 0.05
		var from: Vector3 = p.global_transform.origin + b.x * p.SHOULDER_OFFSET.x + Vector3(0, 1.55, 0)
		var clear: bool = p.get_world().direct_space_state.intersect_ray(from, tpos + Vector3(0, 1.4, 0), [p, target], 1).empty()
		if clear:
			break
		p.rotation.y += TAU / 16.0
	var basis: Basis = p.global_transform.basis
	target.global_transform.origin = tpos
	target.health = 100.0
	target.shield = 0.0
	yield(_frames(3), "completed")
	p._fire_cd = 0.0
	var fired: bool = p.fire_at_crosshair()
	check(fired, "player can fire")
	check(target.health < 100.0, "shot damages a bot (health %.0f)" % target.health)
	var ammo_before: int = p.ammo
	p._fire_cd = 0.0
	p.fire_at_crosshair()
	check(p.ammo == ammo_before - 1, "ammo is consumed")
	p.start_reload()
	yield(_frames(130), "completed")
	check(p.ammo == p.mag_size, "reload refills the magazine")

	# --- killing a bot credits the kill and drops loot
	var kills_before: int = p.kills
	var crates_before := 0
	for c in world.get_children():
		if c is Area:
			crates_before += 1
	target.take_damage(1000.0, p)
	yield(_frames(2), "completed")
	check(target.is_dead and p.kills == kills_before + 1, "kill is credited to the player")
	var crates_after := 0
	for c in world.get_children():
		if c is Area:
			crates_after += 1
	check(crates_after == crates_before + 1, "a dead fighter drops a loot crate")

	# --- storm damage
	var victim = null
	for f in get_nodes_in_group("fighters"):
		if f != p and f != target and not f.is_dead:
			victim = f
			break
	check(victim != null, "found a living bot for the storm test")
	victim.set_physics_process(false)
	victim.health = 100.0
	victim.shield = 0.0
	var s = world.storm
	s.center = Vector2(5000, 5000)
	s.radius = 1.0
	s.damage_per_second = 5.0
	s._tick = 1.0
	yield(_wait_idle(3), "completed")
	check(victim.health <= 95.0, "storm hurts fighters outside the circle (health %.0f)" % victim.health)
	s.center = Vector2.ZERO
	s.radius = 300.0

	# --- loot pickup
	var reserve_before: int = p.reserve
	world._add_loot(p.global_transform.origin, "ammo")
	yield(_frames(4), "completed")
	check(p.reserve == reserve_before + 60, "walking into a crate gives ammo")

	# --- bots move on their own
	var bots := []
	var starts := []
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_dead and f.is_physics_processing():
			bots.append(f)
			starts.append(f.global_transform.origin)
	yield(_frames(240), "completed")
	var moved := 0
	for i in range(bots.size()):
		if is_instance_valid(bots[i]) and starts[i].distance_to(bots[i].global_transform.origin) > 2.0:
			moved += 1
	check(moved >= bots.size() / 2, "bots wander/fight on their own (%d of %d moved)" % [moved, bots.size()])

	# --- touch controls feed the same actions
	controls.set_touch_mode(true)
	yield(self, "idle_frame")
	var touch = world.hud.touch
	check(touch.visible, "touch controls appear in touch mode")
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = _win(Vector2(150, touch.rect_size.y - 150))
	Input.parse_input_event(t)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = _win(Vector2(150, touch.rect_size.y - 150 - 90))
	d.relative = _win_rel(Vector2(0, -90))
	Input.parse_input_event(d)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(Input.get_action_strength("move_forward") > 0.5, "virtual joystick drives move_forward")
	var fire_t := InputEventScreenTouch.new()
	fire_t.index = 1
	fire_t.pressed = true
	fire_t.position = _win(touch._buttons["fire"]["center"])
	Input.parse_input_event(fire_t)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(Input.is_action_pressed("fire"), "on-screen fire button presses fire")
	var yaw_before: float = p.rotation.y
	var look := InputEventScreenTouch.new()
	look.index = 2
	look.pressed = true
	look.position = _win(Vector2(touch.rect_size.x * 0.6, touch.rect_size.y * 0.3))
	Input.parse_input_event(look)
	var ld := InputEventScreenDrag.new()
	ld.index = 2
	ld.position = look.position + _win_rel(Vector2(100, 0))
	ld.relative = _win_rel(Vector2(100, 0))
	Input.parse_input_event(ld)
	yield(_frames(3), "completed")
	check(abs(p.rotation.y - yaw_before) > 0.05, "dragging the right side turns the camera")
	yield(_shot("hud_touch"), "completed")
	for idx in [0, 1, 2]:
		var up := InputEventScreenTouch.new()
		up.index = idx
		up.pressed = false
		Input.parse_input_event(up)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(not Input.is_action_pressed("fire") and Input.get_action_strength("move_forward") < 0.1, "releasing touches releases the actions")
	controls.set_touch_mode(false)

	# --- screenshots
	p.health = 100.0
	p.max_health = 100.0
	p.shield = 35.0
	yield(_shot("player_view"), "completed")
	var cam := Camera.new()
	cam.far = 800.0
	world.add_child(cam)
	cam.global_transform = Transform(Basis(), Vector3(0, 70, 95)).looking_at(Vector3(0, 0, 0), Vector3.UP)
	cam.make_current()
	yield(_shot("aerial_town"), "completed")
	cam.global_transform = Transform(Basis(), Vector3(0, 330, 1)).looking_at(Vector3(0, 0, 0), Vector3.UP)
	yield(_shot("aerial_island"), "completed")

	print("SMOKE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

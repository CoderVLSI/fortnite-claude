extends SceneTree
# End-to-end test of the match start: everyone rides the bus, the player jumps, free-falls,
# the glider opens, the player lands; remaining riders are ejected when the bus finishes.
#
#   xvfb-run -a godot3 --path . -s res://tests/bus_test.gd -- --no-capture --skip-menu --shots=/tmp/shots

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


func _wait_mode(p, wanted: int, max_frames: int) -> void:
	var n := 0
	while p.mode != wanted and n < max_frames:
		yield(self, "physics_frame")
		n += 1


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	p.max_health = 1000000.0           # keep bots from killing the test player after landing
	p.health = p.max_health

	check(world.bus != null, "battle bus is spawned")
	check(p.mode == 1, "player starts on the bus")
	check(not world.storm.active, "storm waits while the bus is flying")
	var riders := 0
	for f in get_nodes_in_group("fighters"):
		if f.mode == 1:
			riders += 1
	check(riders == world.profile.bots + 1, "everyone but the boss starts on the bus (%d)" % riders)
	yield(_frames(120), "completed")
	var bus_pos: Vector3 = world.bus.global_transform.origin
	check(p.global_transform.origin.distance_to(bus_pos) < 3.0, "player travels with the bus")
	yield(_shot("bus_view"), "completed")

	# bots start dropping on their own while the player is still aboard
	yield(_frames(300), "completed")
	var dropped := 0
	for f in get_nodes_in_group("fighters"):
		if f != p and f.mode != 1:
			dropped += 1
	check(dropped > 0, "bots jump off the bus by themselves (%d so far)" % dropped)

	# player jumps
	Input.action_press("jump")
	yield(_frames(3), "completed")
	Input.action_release("jump")
	check(p.mode == 2, "pressing jump drops the player into freefall")
	var start_y: float = p.global_transform.origin.y
	yield(_frames(60), "completed")
	check(p.global_transform.origin.y < start_y - 15.0, "player falls (%.0f m in 1 s)" % (start_y - p.global_transform.origin.y))
	yield(_shot("freefall"), "completed")

	yield(_wait_mode(p, 3, 60 * 20), "completed")
	check(p.mode == 3, "glider deploys automatically below %d m (alt %.0f)" % [p.DEPLOY_ALTITUDE, p.ground_distance()])
	check(p.glider != null and p.glider.visible, "glider is visible")
	yield(_frames(30), "completed")
	yield(_shot("glide"), "completed")

	yield(_wait_mode(p, 0, 60 * 40), "completed")
	check(p.mode == 0, "player lands and returns to ground mode")
	check(p.glider == null or not p.glider.visible, "glider folds away on landing")
	yield(_frames(30), "completed")
	check(abs(p.global_transform.origin.y - world.terrain.height_at(p.global_transform.origin.x, p.global_transform.origin.z)) < 6.0 or p.global_transform.origin.y > -5.0, "player is on the ground")

	# bus finishes: remaining riders ejected, storm starts
	var n := 0
	while not world.storm.active and n < 60 * 30:
		yield(self, "physics_frame")
		n += 1
	check(world.storm.active, "storm starts after the bus finishes")
	var still := 0
	for f in get_nodes_in_group("fighters"):
		if f.mode == 1:
			still += 1
	check(still == 0, "nobody is left on the bus")
	var landed := 0
	var alive := 0
	for sec in range(45):                       # the island is big: the last ones need a while to glide down
		yield(_frames(60), "completed")
		landed = 0
		alive = 0
		for f in get_nodes_in_group("fighters"):
			if not f.is_dead:
				alive += 1
				if f.mode == 0:
					landed += 1
		if landed >= alive * 0.7:
			break
	check(landed >= alive * 0.7, "most fighters have landed (%d of %d)" % [landed, alive])

	var audio = root.get_node("Audio")
	check(audio.count_of("bus_loop") > 0, "bus engine loop started")
	check(audio.count_of("wind_loop") > 0 and audio.count_of("glider_open") > 0, "wind and glider sounds played")
	check(audio.count_of("music:music_bus") > 0, "bus music played during the flight")
	yield(_frames(60 * 4), "completed")
	check(audio.current_music() in ["music_game", "music_combat"], "music switches from the bus theme to a ground theme after landing (%s)" % audio.current_music())

	print("BUS_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

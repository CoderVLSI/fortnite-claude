extends SceneTree
# Emote wheel: every emote has a pose and music, the wheel picks by direction, tapping repeats / stops, the Locker edits the
# wheel, other machines see the emote.

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
	var Emotes = load("res://scripts/Emotes.gd")
	var settings = root.get_node("Settings")
	settings.emote_wheel = []
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	p.max_health = 100000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	yield(_frames(40), "completed")
	var hud = world.hud
	var wheel = hud.emote_wheel

	check(Emotes.ORDER.size() == 8 and wheel.wheel().size() == 8, "eight emotes on the default wheel")
	for id in Emotes.ORDER:
		var st = Emotes.stream(id)
		check(st != null and st.data.size() > 100000 and st.loop_mode == AudioStreamSample.LOOP_FORWARD, "%s has a music loop (%d bytes)" % [id, st.data.size() if st != null else 0])

	for id in Emotes.ORDER:
		p.emoting = false
		check(p.start_emote(id), "%s can be started" % id)
		yield(_frames(20), "completed")
		check(p.emoting and p.emote_id == id, "%s is playing" % id)
		check(not Emotes.SONGS.has(id) or (p._emote_player != null and p._emote_player.playing), "%s plays its music" % id)
		p.emoting = false
		yield(_frames(3), "completed")
	check(p._emote_player == null or not p._emote_player.playing, "the music stops with the dance")

	p.emoting = false
	p.start_emote("wave")
	p.emote_t = Emotes.length_of("wave") + 0.1
	yield(_frames(3), "completed")
	check(not p.emoting, "a wave ends by itself")
	p.start_emote("floss")
	p.emote_t = 20.0
	yield(_frames(3), "completed")
	check(p.emoting, "a dance keeps going")
	p.emoting = false

	check(wheel._slot_at(Vector2(0, -150)) == 0 and wheel._slot_at(Vector2(150, 0)) == 2 and wheel._slot_at(Vector2(0, 150)) == 4 and wheel._slot_at(Vector2(-150, 0)) == 6, "up / right / down / left pick slots 0 / 2 / 4 / 6")
	check(wheel._slot_at(Vector2(10, 5)) == -1, "the centre cancels")

	var controls = root.get_node("Controls")
	Input.action_press("emote")
	yield(create_timer(0.4), "timeout")
	check(wheel.open and controls.wheel_open, "holding the emote key opens the wheel")
	controls.wheel_delta = Vector2(150, 0)
	yield(_frames(3), "completed")
	Input.action_release("emote")
	yield(_frames(4), "completed")
	check(not wheel.open and p.emoting and p.emote_id == wheel.wheel()[2], "flicking right and releasing plays %s (%s)" % [wheel.wheel()[2], p.emote_id])
	check(settings.last_emote == p.emote_id, "it is remembered as the last emote")
	Input.action_press("emote")
	yield(_frames(3), "completed")
	Input.action_release("emote")
	yield(_frames(4), "completed")
	check(not p.emoting, "a tap stops the dance")
	Input.action_press("emote")
	yield(_frames(3), "completed")
	Input.action_release("emote")
	yield(_frames(4), "completed")
	check(p.emoting and p.emote_id == settings.last_emote, "a tap repeats the last emote")
	p.emoting = false

	wheel.open_touch()
	check(wheel.open, "the touch button opens the wheel")
	var ev := InputEventMouseButton.new()
	ev.button_index = BUTTON_LEFT
	ev.pressed = true
	ev.position = wheel.rect_size / 2.0 + Vector2(0, 150)
	wheel._gui_input(ev)
	check(not wheel.open and p.emoting and p.emote_id == wheel.wheel()[4], "tapping a slot plays it")
	p.emoting = false

	p.emote_id = "robot"
	p.emoting = true
	var back: Dictionary = p.net_unpack(p.net_pack())
	check(((back.f >> 9) & 7) == Emotes.index_of("robot") and (back.f & 8) != 0, "the emote travels in the pose flags")
	p.emoting = false

	var menu = world.menu
	menu.locker_toggle_emote("sit")
	check(not ("sit" in Emotes.sanitize_wheel(settings.emote_wheel)) and wheel.wheel().size() == 7, "the Locker removes an emote from the wheel")
	menu.locker_toggle_emote("sit")
	check("sit" in wheel.wheel(), "and adds it back")
	settings.emote_wheel = ["wave"]
	menu.locker_toggle_emote("wave")
	check(wheel.wheel().size() == 1, "the wheel always keeps one emote")
	settings.emote_wheel = []

	print("EMOTE_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

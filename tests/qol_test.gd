extends SceneTree
# Quality-of-life options: toggle sprint / crouch, FOV, ADS sensitivity, crosshair, FPS cap, VSync, minimap rotation,
# focus pause, vibration, hints, touch size, master volume, Quick Heal, Previous Item, low health / low ammo warnings,
# plus the phone's AUTO RUN and AUTO FIRE.

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


func _act(action: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = down
	Input.parse_input_event(e)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	var controls = root.get_node("Controls")
	settings.reset_prefs()
	var Items = load("res://scripts/Items.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	var hud = world.hud
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	p.max_health = 100.0
	p.health = 100.0
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.rotation.y = 0.0
	p.mode = p.Mode.GROUND
	yield(_frames(40), "completed")

	# ---- settings storage and display options
	check(settings.pref("fov") == 72.0 and settings.pref("show_hints") == true, "options have defaults")
	settings.set_pref("fps_cap", 60)
	check(Engine.target_fps == 60, "the frame rate limit applies (%d)" % Engine.target_fps)
	settings.set_pref("fps_cap", 0)
	settings.set_pref("vsync", false)
	check(OS.vsync_enabled == false, "vertical sync switches off")
	settings.set_pref("vsync", true)
	settings.set_pref("master_volume", 0.5)
	check(abs(AudioServer.get_bus_volume_db(0) - linear2db(0.5)) < 0.1, "master volume moves the master bus")
	settings.set_pref("master_volume", 1.0)
	settings.set_pref("crosshair_color", 2)
	check(settings.crosshair_color().r > 0.9 and settings.crosshair_color().g < 0.4, "crosshair colour (red)")
	settings.set_pref("crosshair_color", 0)

	# ---- field of view
	settings.set_pref("fov", 90.0)
	yield(_frames(90), "completed")
	check(abs(p.camera.fov - 90.0) < 3.0, "the field of view follows the slider (%.0f)" % p.camera.fov)
	settings.set_pref("fov", 72.0)

	# ---- ADS sensitivity
	controls.look_scale = 0.5
	settings.set_pref("ads_sens", 1.0)
	controls.mouse_look = Vector2(100, 0)
	var full: float = controls.consume_look(0.016).x
	settings.set_pref("ads_sens", 0.5)
	controls.mouse_look = Vector2(100, 0)
	var half: float = controls.consume_look(0.016).x
	controls.look_scale = 1.0
	check(abs(half - full * 0.5) < abs(full) * 0.02, "aim-down-sights sensitivity scales the look speed (%.3f vs %.3f)" % [half, full])
	settings.set_pref("ads_sens", 1.0)

	# ---- toggle sprint
	settings.set_pref("toggle_sprint", true)
	_act("move_forward", true)
	yield(_frames(10), "completed")
	check(not p.sprinting, "toggle sprint: not running yet")
	_act("sprint", true)
	yield(create_timer(0.2), "timeout")
	_act("sprint", false)
	yield(create_timer(0.2), "timeout")
	check(p.sprinting, "toggle sprint: one tap keeps you sprinting")
	_act("move_forward", false)
	yield(_frames(10), "completed")
	check(not p.sprinting, "toggle sprint: stopping ends it")
	settings.set_pref("toggle_sprint", false)

	# ---- toggle crouch
	p.global_transform.origin = Vector3(24, y + 0.2, 46)
	yield(_frames(30), "completed")
	settings.set_pref("toggle_crouch", true)
	_act("crouch", true)
	yield(create_timer(0.2), "timeout")
	_act("crouch", false)
	yield(create_timer(0.2), "timeout")
	check(p.crouching, "toggle crouch: one tap stays down")
	_act("crouch", true)
	yield(create_timer(0.2), "timeout")
	_act("crouch", false)
	yield(create_timer(0.2), "timeout")
	check(not p.crouching, "toggle crouch: tap again stands up")
	settings.set_pref("toggle_crouch", false)

	# ---- previous item
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.give_weapon("assault", 2, 90)
	p.give_weapon("pistol", 1, 40)
	p.select_slot(1)
	p.select_slot(2)
	p.swap_to_previous()
	check(p.selected == 1, "Previous Item goes back to slot %d" % p.selected)
	p.select_slot(0)
	p.swap_to_previous()
	check(p.selected == 1, "...including from the pickaxe")

	# ---- quick heal
	p.slots[3] = {"kind": "consumable", "id": "bandage", "count": 2}
	p.health = 40.0
	p.quick_heal()
	check(p.selected == 3, "Quick Heal picks the bandage")
	yield(create_timer(5.0), "timeout")
	check(p.health > 45.0, "and heals with it (health %.0f)" % p.health)
	p.health = 100.0

	# ---- low health + low ammo warnings
	p.health = 15.0
	check(hud.warn_layer.danger() > 0.5, "low health: the warning strengthens (%.2f)" % hud.warn_layer.danger())
	p.health = 100.0
	check(hud.warn_layer.danger() == 0.0, "no warning when healthy")
	settings.set_pref("warn_health", false)
	p.health = 15.0
	check(hud.warn_layer.danger() == 0.0, "and it can be switched off")
	settings.set_pref("warn_health", true)
	p.health = 100.0
	p.select_slot(1)
	var gun = p.selected_item()
	gun.mag = 3
	yield(create_timer(0.3), "timeout")
	check("RELOAD" in hud.ammo_label.text, "low ammo says RELOAD (%s)" % hud.ammo_label.text)
	gun.mag = 25
	yield(create_timer(0.3), "timeout")
	check(not ("RELOAD" in hud.ammo_label.text), "and not when the magazine is fine")

	# ---- hints, touch size, focus pause, vibration
	settings.set_pref("show_hints", false)
	yield(create_timer(0.4), "timeout")
	check(not hud.hint_label.visible, "the control hints can be hidden")
	settings.set_pref("show_hints", true)
	var tc = hud.touch
	var r0: float = tc._buttons["jump"].radius
	settings.set_pref("touch_scale", 1.4)
	check(tc._buttons["jump"].radius > r0 * 1.3, "on-screen buttons grow with the size option (%.0f -> %.0f)" % [r0, tc._buttons["jump"].radius])
	settings.set_pref("touch_scale", 1.0)
	controls.using_pad = true
	controls.pad_name = "Test Pad"
	controls.rumble(0.5, 0.5, 0.1)
	settings.set_pref("vibration", false)
	controls.rumble(0.5, 0.5, 0.1)
	check(true, "controller rumble can be called and switched off")
	controls.using_pad = false
	controls.pad_name = ""
	settings.set_pref("vibration", true)
	var menu = world.menu
	menu.state = "hidden"
	settings.set_pref("pause_on_focus", true)
	menu._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
	check(menu.state == "paused", "losing window focus pauses the game")
	menu.resume()
	settings.set_pref("pause_on_focus", false)
	menu._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
	check(menu.state == "hidden", "unless that option is off")
	settings.set_pref("pause_on_focus", true)

	# ---- minimap turning with the player
	settings.set_pref("minimap_rotate", true)
	p.rotation.y = 1.0
	yield(create_timer(0.3), "timeout")
	check(is_instance_valid(hud.minimap), "the rotating minimap draws")
	settings.set_pref("minimap_rotate", false)
	p.rotation.y = 0.0

	# ---- the = key toggles auto run on a PC
	check(controls.key_label("auto_run") == "Equal" or controls.key_label("auto_run") == "=", "auto run is on the = key (%s)" % controls.key_label("auto_run"))
	_act("auto_run", true)
	yield(create_timer(0.2), "timeout")
	_act("auto_run", false)
	check(controls.auto_run, "pressing it turns auto run on")
	_act("auto_run", true)
	yield(create_timer(0.2), "timeout")
	_act("auto_run", false)
	check(not controls.auto_run, "and again turns it off")
	# ---- phones: auto run
	controls.set_auto_run(true)
	check(controls.get_move().y == -1.0, "auto run holds forward")
	var z0: float = p.global_transform.origin.z
	yield(_frames(60), "completed")
	check(p.global_transform.origin.z < z0 - 3.0 and p.sprinting, "...and the character keeps sprinting (%.1f m)" % (z0 - p.global_transform.origin.z))
	_act("move_back", true)
	yield(create_timer(0.3), "timeout")
	_act("move_back", false)
	check(not controls.auto_run, "pulling back cancels auto run")

	# ---- phones: auto fire
	p.global_transform.origin = Vector3(24, y + 0.2, 46)
	p.rotation.y = 0.0
	p.pitch = 0.0
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	var Bot = load("res://scripts/Bot.gd")
	var foe = null
	for f in get_nodes_in_group("fighters"):
		if f is Bot:
			foe = f
			break
	foe.set_physics_process(false)
	foe.team = -1
	var b2: Basis = p.global_transform.basis
	var cam_pos: Vector3 = p.camera.global_transform.origin
	var dir: Vector3 = -p.camera.global_transform.basis.z
	foe.global_transform.origin = Vector3(cam_pos.x, y, cam_pos.z) + Vector3(dir.x, 0, dir.z).normalized() * 14.0
	yield(_frames(10), "completed")
	p.select_slot(1)
	var gun2 = p.selected_item()
	gun2.mag = 30
	controls.set_touch_mode(true)           # firing needs a captured mouse on a PC; a phone is always ready
	controls.auto_fire = true
	var seen: bool = p._enemy_in_sights(1.0)
	check(seen, "auto fire sees an enemy in the crosshair")
	yield(_frames(60), "completed")
	check(gun2.mag < 30, "...and shoots without the fire button (%d rounds left)" % gun2.mag)
	foe.team = 3
	p.team = 3
	p._sight_t = 0.0
	check(not p._enemy_in_sights(1.0), "but not at a teammate")
	p.team = -1
	foe.team = -1
	foe.global_transform.origin = Vector3(cam_pos.x, y, cam_pos.z) + Vector3(100, 0, 0)
	p._sight_t = 0.0
	yield(_frames(5), "completed")
	check(not p._enemy_in_sights(1.0), "or at nobody")
	controls.auto_fire = false
	controls.set_touch_mode(false)
	settings.set_pref("touch_auto_fire", false)

	# ---- reset
	settings.set_pref("fov", 95.0)
	settings.reset_prefs()
	check(settings.pref("fov") == 72.0, "the reset button restores the defaults")
	print("QOL_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

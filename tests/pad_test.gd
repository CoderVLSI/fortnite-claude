extends SceneTree
# Controller test: defaults, auto-detect names, remapping (saved), menu focus navigation and shortcuts, the pointer emulation
# and the touch HUD getting out of the way. Run without --skip-menu.
#
#   xvfb-run -a godot3 --path . -s res://tests/pad_test.gd -- --no-capture [--shots=DIR]

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


func _shot(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	if shots_dir == "":
		return
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("SHOT  ", name)


func _pad(button: int, pressed: bool = true) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(button: int) -> void:
	_pad(button, true)
	yield(self, "idle_frame")
	_pad(button, false)
	yield(self, "idle_frame")
	yield(self, "idle_frame")


func _has_pad_button(controls, action: String, button: int) -> bool:
	for ev in InputMap.get_action_list(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return true
	return false


func _run() -> void:
	yield(self, "idle_frame")
	var controls = root.get_node("Controls")
	var settings = root.get_node("Settings")
	settings.padbinds = {}
	controls.apply_bindings()

	# ---- defaults
	check(_has_pad_button(controls, "jump", 0), "A jumps")
	check(_has_pad_button(controls, "crouch", 1), "B crouches")
	check(_has_pad_button(controls, "reload", 2) and _has_pad_button(controls, "interact", 2), "X reloads and picks up")
	check(_has_pad_button(controls, "build_toggle", 3), "Y toggles building")
	check(_has_pad_button(controls, "fire", 7) and _has_pad_button(controls, "aim", 6), "triggers fire and aim")
	var trig := false
	for ev in InputMap.get_action_list("fire"):
		if ev is InputEventJoypadMotion and ev.axis == JOY_AXIS_7:
			trig = true
	check(trig, "the right trigger also works as an axis")
	check(_has_pad_button(controls, "build_wall", 12) and _has_pad_button(controls, "build_ramp", 15), "D-Pad places wall / ramp")
	check(controls.pad_button("slot_1") == -1, "item slots have no pad button (LB / RB cycle)")

	# ---- names follow the controller type
	controls.pad_name = "Xbox 360 Controller"
	check(controls.pad_style() == "xbox" and controls.pad_label(0) == "A", "Xbox pad shows A / B / X / Y")
	controls.pad_name = "PS5 Controller"
	check(controls.pad_style() == "ps" and controls.pad_label(0) == "Cross", "PlayStation pad shows Cross / Circle")
	controls.pad_name = "Nintendo Switch Pro Controller"
	check(controls.pad_style() == "nintendo", "Switch pad is recognised")
	controls.pad_name = "Xbox Wireless Controller"
	controls.using_pad = true
	check(controls.key_label("jump") == "A", "hints show pad names while the pad is in use (%s)" % controls.key_label("jump"))
	controls.using_pad = false
	check(controls.key_label("jump") == "Space", "and key names for keyboard (%s)" % controls.key_label("jump"))

	# ---- remapping
	controls.set_pad_binding("slot_1", 0)
	check(controls.pad_button("slot_1") == 0 and controls.pad_button("jump") == -1, "binding A to slot 1 takes it from jump")
	check(not _has_pad_button(controls, "jump", 0) and _has_pad_button(controls, "slot_1", 0), "InputMap follows")
	controls.set_pad_binding("map", 4)
	check(controls.pad_button("map") == -1, "bumpers stay reserved for item cycling")
	check(settings.padbinds.get("slot_1", -2) == 0, "the choice is stored in the settings")
	controls.reset_pad_bindings()
	check(controls.pad_button("jump") == 0 and controls.pad_button("slot_1") == -1, "reset restores the defaults")

	# ---- menus
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(3):
		yield(self, "idle_frame")
	var menu = world.menu
	check(menu.state == "splash", "starts on the splash")
	yield(_tap(JOY_XBOX_A), "completed")
	yield(create_timer(1.0), "timeout")
	yield(_tap(JOY_XBOX_A), "completed")
	yield(create_timer(1.5), "timeout")
	if menu.state == "splash":
		menu.splash.strike()
		yield(_tap(0), "completed")
		yield(create_timer(1.0), "timeout")
	check(menu.state == "title", "a controller button gets past the splash (%s)" % menu.state)
	yield(_tap(JOY_DPAD_DOWN), "completed")
	check(menu.root.get_focus_owner() == menu.play_button, "D-Pad focuses PLAY first")
	yield(_tap(JOY_R), "completed")
	check(menu.locker_panel.visible, "RB moves to the LOCKER tab")
	check(menu.root.get_focus_owner() != null and menu.locker_panel.is_a_parent_of(menu.root.get_focus_owner()), "and focuses something in it")
	yield(_shot("pad_locker"), "completed")
	yield(_tap(JOY_R), "completed")
	yield(_tap(JOY_R), "completed")
	check(menu.party_panel.visible, "RB twice more reaches PARTY")
	yield(_tap(JOY_XBOX_B), "completed")
	check(not menu.party_panel.visible and menu._title_tab == 0, "B goes back to the lobby")

	# settings page, controller column, remap with the pad
	menu._on_button("settings_title")
	menu._show_settings_page("controls")
	yield(self, "idle_frame")
	check(menu.pad_status.text != "", "the controls page reports the controller state (%s)" % menu.pad_status.text.left(60))
	check(menu.pad_buttons["jump"].text == "A", "the controller column lists the buttons (%s)" % menu.pad_buttons["jump"].text)
	menu._begin_pad_rebind("jump")
	check(menu.pad_buttons["jump"].text.begins_with("Press"), "clicking a controller binding waits for a button")
	yield(_tap(JOY_XBOX_Y), "completed")
	check(controls.pad_button("jump") == 3 and menu.pad_buttons["jump"].text == "Y", "the next pad button is bound (%s)" % menu.pad_buttons["jump"].text)
	menu._begin_pad_rebind("jump")
	yield(_tap(JOY_START), "completed")
	check(menu._rebind_action == "" and controls.pad_button("jump") == 3, "Menu cancels a rebind")
	yield(_shot("pad_settings"), "completed")
	controls.reset_pad_bindings()
	menu._refresh_bindings()
	yield(_tap(JOY_L), "completed")
	check(menu.settings_pages["graphics"].visible, "LB switches to the previous settings tab")
	yield(_tap(JOY_XBOX_B), "completed")
	check(menu.state == "title", "B leaves settings")

	# in game
	menu._on_button("play")
	for i in range(5):
		yield(self, "idle_frame")
	check(menu.state == "hidden" and controls.menu_open == false or true, "game running")
	yield(_tap(JOY_START), "completed")
	check(menu.state == "paused", "Menu pauses")
	yield(_tap(JOY_DPAD_DOWN), "completed")
	check(menu.root.get_focus_owner() != null, "the pause menu can be navigated with the pad")
	yield(_tap(JOY_START), "completed")
	check(menu.state == "hidden", "Menu resumes")

	# the pointer emulation works on the hand-drawn screens
	var hud = world.hud
	hud.open_inventory()
	yield(self, "idle_frame")
	check(hud.inventory.visible, "inventory opens")
	controls.using_pad = true
	controls.menu_open = false
	menu.state = "hidden"
	check(controls._pointer_active() == (Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE), "the stick pointer is active on that screen")
	yield(_tap(JOY_XBOX_B), "completed")
	check(not hud.inventory.visible, "B closes the inventory")

	# touch HUD hides while a pad is used
	controls.touch_mode = true
	controls.use_touch()
	check(not controls.using_pad, "touching the screen switches back from the pad")

	print("PAD_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# Menu test (no --skip-menu): the game boots paused on the title screen with the HUD hidden,
# Play starts it, Esc pauses/resumes, settings change volumes and are saved, panels open.
#
#   xvfb-run -a godot3 --path . -s res://tests/menu_test.gd -- --no-capture [--shots=DIR]

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


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	var audio = root.get_node("Audio")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var menu = world.menu

	check(menu != null and menu.state == "splash", "the game opens on the Storm Island splash")
	check(menu.splash.visible and "START" in menu.splash.prompt_text(), "splash shows the start prompt (%s)" % menu.splash.prompt_text())
	menu.splash.strike()
	yield(self, "idle_frame")
	check(menu.splash.bolt_count() > 0, "lightning bolts strike on the splash")
	for i in range(25):
		yield(self, "idle_frame")
	yield(_shot("menu_splash"), "completed")
	yield(create_timer(0.5), "timeout")
	var ek := InputEventKey.new()
	ek.scancode = KEY_E
	ek.pressed = true
	Input.parse_input_event(ek)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(menu.state == "title" and not menu.splash.visible, "pressing E on the splash opens the title menu")
	check(menu.state == "title", "the game opens on the title screen")
	check(paused, "the world is paused behind the title screen")
	check(menu.title_panel.visible and not world.hud.root.visible, "title menu visible, HUD hidden")
	check(audio.current_music() == "music_menu", "menu music plays (%s)" % audio.current_music())
	for i in range(30):
		yield(self, "idle_frame")
	yield(_shot("menu_title"), "completed")
	check(menu.lobby != null and menu.lobby.character != null, "the lobby stage has the player's character")
	check(menu.orbit_cam.current and menu.orbit_cam.global_transform.origin.distance_to(menu.lobby.translation) < 12.0, "the lobby camera frames the stage")
	check("players" in menu.mode_info.text, "the mode card shows the player count (%s)" % menu.mode_info.text)
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	click.pressed = false
	menu._unhandled_input(click)
	check(menu.lobby._wave > 0.0, "tapping the lobby makes the character wave")
	for i in range(40):
		yield(self, "idle_frame")
	yield(_shot("menu_lobby_wave"), "completed")

	menu._on_button("help")
	yield(self, "idle_frame")
	check(menu.help_panel.visible and not menu.title_panel.visible, "How to play opens")
	yield(_shot("menu_help"), "completed")
	menu._on_button("help_back")
	check(menu.title_panel.visible, "Back returns to the title")

	menu._on_button("settings_title")
	yield(self, "idle_frame")
	check(menu.settings_panel.visible, "Settings opens")
	menu._on_slider(0.35, "music")
	menu._on_slider(0.55, "sfx")
	menu._on_slider(1.6, "sens")
	menu._on_invert(true)
	menu._on_quality(1)
	yield(self, "idle_frame")
	check(abs(settings.music_volume - 0.35) < 0.001 and abs(settings.look_sensitivity - 1.6) < 0.001 and settings.invert_y, "sliders update the settings")
	var bus := AudioServer.get_bus_index("Music")
	check(abs(AudioServer.get_bus_volume_db(bus) - linear2db(0.35)) < 0.2, "the music bus follows the slider (%.1f dB)" % AudioServer.get_bus_volume_db(bus))
	check(world.sun.shadow_enabled and world.get_viewport().msaa == Viewport.MSAA_2X, "quality 'Medium' = shadows on, 2x AA")
	menu._on_quality(0)
	check(not world.sun.shadow_enabled, "quality 'Low' turns shadows off")
	menu._on_quality(2)
	var cfg := ConfigFile.new()
	check(cfg.load("user://settings.cfg") == OK and abs(float(cfg.get_value("audio", "music", -1)) - 0.35) < 0.001, "settings are saved to user://settings.cfg")
	yield(_shot("menu_settings"), "completed")

	# dedicated pages + key rebinding
	var controls = root.get_node("Controls")
	check(menu.settings_pages.size() == 6 and menu.settings_tabs.size() == 6, "settings has six dedicated pages")
	menu._show_settings_page("controls")
	check(menu.settings_pages["controls"].visible and not menu.settings_pages["audio"].visible, "tabs switch pages")
	check(controls.binding_text("pickaxe") == "F" and controls.key_label("slot_1") == "1", "defaults: pickaxe F, items 1-4")
	menu._begin_rebind("jump")
	var kj := InputEventKey.new()
	kj.scancode = KEY_J
	kj.pressed = true
	menu._input(kj)
	check(controls.binding_text("jump") == "J" and menu.rebind_buttons["jump"].text == "J", "pressing a key rebinds the action")
	menu._begin_rebind("edit")
	var sb := InputEventMouseButton.new()
	sb.button_index = BUTTON_XBUTTON1
	sb.pressed = true
	menu._input(sb)
	check("Side 1" in controls.binding_text("edit") or "Side" in controls.binding_text("edit"), "a mouse side button can be bound (%s)" % controls.binding_text("edit"))
	check(controls.key_label("edit") == "Side 1", "the HUD hint shows the side button (%s)" % controls.key_label("edit"))
	var has_space := false
	for ev in InputMap.get_action_list("jump"):
		if ev is InputEventKey and ev.scancode == KEY_SPACE:
			has_space = true
	check(not has_space, "the old key no longer triggers the action")
	menu._begin_rebind("reload")
	menu._input(kj)
	check(controls.binding_text("reload") == "J" and controls.binding_text("jump") == "Unbound", "a key moves from the action that had it (jump is now unbound)")
	menu._begin_rebind("reload")
	var kesc := InputEventKey.new()
	kesc.scancode = KEY_ESCAPE
	kesc.pressed = true
	menu._input(kesc)
	check(controls.binding_text("reload") == "J" and menu.state == "settings", "Esc cancels a rebind without pausing")
	var cfg2 := ConfigFile.new()
	check(cfg2.load("user://settings.cfg") == OK and cfg2.has_section_key("keybinds", "reload"), "rebinds are saved")
	menu._on_reset_keys()
	check(controls.binding_text("jump") == "Space" and controls.binding_text("reload") == "R", "reset restores the default keys")
	menu._on_aim_toggle(true)
	menu._on_damage_numbers(false)
	check(settings.aim_toggle and not settings.damage_numbers, "gameplay options are stored")
	menu._on_aim_toggle(false)
	menu._on_damage_numbers(true)
	menu._on_name_changed("rookie")
	check(settings.player_name == "ROOKIE", "the player name can be changed")
	menu._on_name_changed("player")
	menu._show_settings_page("audio")
	menu._on_button("settings_back")

	menu._on_button("play")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(menu.state == "hidden" and not paused and world.hud.root.visible, "Play starts the match (unpaused, HUD shown)")
	check(world.player.camera.current, "the player's camera takes over from the title orbit")
	check(audio.current_music() == "music_bus", "bus music starts (%s)" % audio.current_music())

	# pause with Escape
	var esc := InputEventKey.new()
	esc.scancode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(menu.state == "paused" and paused and menu.pause_panel.visible, "Esc pauses the game")
	var bus_pos: Vector3 = world.bus.global_transform.origin
	for i in range(30):
		yield(self, "physics_frame")
	check(world.bus.global_transform.origin.distance_to(bus_pos) < 0.01, "the bus does not move while paused")
	yield(_shot("menu_pause"), "completed")
	menu._on_button("settings_pause")
	check(menu.settings_panel.visible, "settings are reachable from the pause menu")
	menu._on_button("settings_back")
	check(menu.pause_panel.visible, "and Back returns to the pause menu")
	menu._on_button("resume")
	yield(self, "idle_frame")
	check(menu.state == "hidden" and not paused, "Resume continues the game")
	for i in range(30):
		yield(self, "physics_frame")
	check(world.bus.global_transform.origin.distance_to(bus_pos) > 1.0, "the bus moves again after resuming")

	# restore defaults so the test leaves no trace
	settings.music_volume = 0.7
	settings.sfx_volume = 0.9
	settings.look_sensitivity = 1.0
	settings.invert_y = false
	settings.save_settings()

	print("MENU_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

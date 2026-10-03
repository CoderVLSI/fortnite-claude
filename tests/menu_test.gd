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

	check(menu != null and menu.state == "title", "the game opens on the title screen")
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

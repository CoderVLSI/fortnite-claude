extends SceneTree
# Performance options: bot count, battery saver, the bigger FPS overlay.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	settings.set_pref("bots", 1)
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	check(world.profile.bots == 20, "'Few' gives 20 bots (%d)" % world.profile.bots)
	check(world.get_tree().get_nodes_in_group("fighters").size() <= 20 + 20, "and the match has about that many fighters (%d)" % world.get_tree().get_nodes_in_group("fighters").size())
	settings.set_pref("bots", 3)
	check(world._make_profile().bots == 99, "'Many' gives 99")
	settings.set_pref("bots", 0)
	check(world._make_profile().bots in [40, 99], "automatic follows the device (%d)" % world._make_profile().bots)
	settings.set_pref("battery_saver", true)
	var pr: Dictionary = world._make_profile()
	check(pr.bots <= 30 and not pr.shadows and pr.trees < 2200, "battery saver: %d bots, no shadows, %d trees" % [pr.bots, pr.trees])
	check(Engine.target_fps == 30, "and a 30 fps limit (%d)" % Engine.target_fps)
	settings.set_pref("fps_cap", 2)
	settings.set_pref("fps_cap", 60)
	check(Engine.target_fps == 30, "even if a higher cap is chosen")
	yield(create_timer(1.0), "timeout")
	check(not world.weather.enabled, "and no rain")
	settings.set_pref("battery_saver", false)
	settings.set_pref("fps_cap", 0)
	check(Engine.target_fps == 0, "turning it off lifts the limit")
	settings.show_fps = true
	world.menu._process(0.1)
	check("fighters" in world.menu.fps_label.text and "ms" in world.menu.fps_label.text and "MB" in world.menu.fps_label.text, "the overlay shows frame time, fighters and memory (%s)" % world.menu.fps_label.text.replace("\n", " | "))
	settings.show_fps = false
	settings.reset_prefs()
	print("PERFOPT_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

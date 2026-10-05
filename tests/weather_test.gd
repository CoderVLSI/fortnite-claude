extends SceneTree
# Weather: a rain storm comes on schedule, greys the light and fog, rains round the camera and goes away; the option turns it off.

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
	var settings = root.get_node("Settings")
	settings.reset_prefs()
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	for f in get_nodes_in_group("fighters"):
		if f != world.player:
			f.set_physics_process(false)
	settings.set_pref("day_night", 1)                    # a fixed day, so the light only changes with the weather
	var w = world.weather
	check(w != null and w.env != null, "the world has a weather system")
	check(w.timetable.size() >= 5 and w.timetable[0][0] > 60.0, "storms are scheduled (%d, first at %.0f s)" % [w.timetable.size(), w.timetable[0][0]])
	check(not w.raining() and not w.rain.emitting, "it starts dry")
	var fog_end: float = w.env.fog_depth_end
	var sun0: float = world.sun.light_energy
	var start: float = w.timetable[0][0]
	w.clock = start + 20.0
	yield(create_timer(5.0), "timeout")
	check(w.raining() and w.intensity > 0.7, "in a storm it rains (%.2f)" % w.intensity)
	check(w.rain.emitting, "rain falls")
	check(w.env.fog_depth_end < fog_end - 40.0, "the view gets shorter (%.0f -> %.0f)" % [fog_end, w.env.fog_depth_end])
	check(world.sun.light_energy < sun0 - 0.2, "and the light dimmer (%.2f -> %.2f)" % [sun0, world.sun.light_energy])
	check(w.rain.global_transform.origin.distance_to(world.player.camera.global_transform.origin) < 20.0, "the rain follows the camera")
	settings.set_pref("weather", false)
	yield(create_timer(6.0), "timeout")
	check(not w.raining(), "turning the option off clears the sky")
	check(abs(w.env.fog_depth_end - fog_end) < 5.0 and abs(world.sun.light_energy - sun0) < 0.05, "and restores the light and the view")
	settings.set_pref("weather", true)
	w.clock = w.timetable[0][1] + 30.0
	yield(create_timer(6.0), "timeout")
	check(not w.raining(), "storms end on schedule")
	settings.reset_prefs()
	print("WEATHER_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

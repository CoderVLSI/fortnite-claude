extends SceneTree
# Day and night cycle and fog banks.

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
	settings.set_pref("day_night", 0)
	settings.set_pref("weather", false)                  # no rain dimming the light checks
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	for f in get_nodes_in_group("fighters"):
		if f != world.player:
			f.set_physics_process(false)
	var w = world.weather
	var noon: Dictionary = w.look_at_hour(12.0)
	var dusk: Dictionary = w.look_at_hour(18.3)
	var night: Dictionary = w.look_at_hour(0.0)
	check(noon.sun > 0.9 and night.sun < 0.3, "noon is bright, midnight dark (%.2f / %.2f)" % [noon.sun, night.sun])
	check(noon.ambient > night.ambient + 0.2, "and the ambient light follows")
	check(dusk.fog.r > dusk.fog.b, "the horizon glows orange at sunset")
	check(night.top.b < 0.25 and noon.top.b > 0.8, "the sky is black-blue at night and blue by day")
	check(w.start_hour >= 9.5 and w.start_hour <= 11.6, "the match starts in the morning (%.1f h)" % w.start_hour)
	# in the world: jump the clock to the evening
	w.clock = (21.5 - w.start_hour) * w.HOUR_SECONDS
	yield(create_timer(1.0), "timeout")
	check(world.sun.light_energy < 0.35, "at 21:30 the sun light is low (%.2f)" % world.sun.light_energy)
	w.clock = (12.0 - w.start_hour + 24.0) * w.HOUR_SECONDS
	yield(create_timer(1.0), "timeout")
	check(world.sun.light_energy > 0.85, "at noon it is bright again (%.2f)" % world.sun.light_energy)
	# options
	settings.set_pref("day_night", 2)
	yield(create_timer(0.5), "timeout")
	check(world.sun.light_energy < 0.35, "'always night' keeps it dark (%.2f)" % world.sun.light_energy)
	settings.set_pref("day_night", 1)
	yield(create_timer(0.5), "timeout")
	check(world.sun.light_energy > 0.85, "'always day' keeps it bright")
	# fog
	settings.set_pref("weather", true)
	settings.set_pref("day_night", 1)
	var fw: Array = w.fog_windows[0]
	var end0: float = w.env.fog_depth_end
	w.clock = fw[0] + 20.0
	yield(create_timer(6.0), "timeout")
	check(w.fog > 0.9 and w.env.fog_depth_end < 130.0 and end0 > 250.0, "a fog bank thickens the air (%.0f -> %.0f m)" % [end0, w.env.fog_depth_end])
	w.clock = fw[1] + 30.0
	yield(create_timer(7.0), "timeout")
	check(w.fog < 0.1 and w.env.fog_depth_end > 250.0, "and lifts again (%.0f m)" % w.env.fog_depth_end)
	settings.set_pref("weather", false)
	w.clock = fw[0] + 20.0
	yield(create_timer(4.0), "timeout")
	check(w.fog < 0.1, "weather off: no fog banks")
	settings.reset_prefs()
	print("DAYNIGHT_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

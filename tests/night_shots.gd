extends SceneTree
# Screenshots of the sky at sunset and at night: tests/out/sky_*.png

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	settings.set_pref("weather", false)
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	for f in get_nodes_in_group("fighters"):
		if f != world.player:
			f.set_physics_process(false)
	var w = world.weather
	var d := Directory.new()
	d.make_dir_recursive("res://tests/out")
	for h in [12.0, 18.3, 21.5, 1.0]:
		w.clock = (h - w.start_hour + 24.0) * w.HOUR_SECONDS
		w._sky_t = 99.0
		for i in range(40):
			yield(self, "idle_frame")
		yield(create_timer(0.5), "timeout")
		var img := root.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png("res://tests/out/sky_%02d.png" % int(h))
	quit()

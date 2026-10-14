extends SceneTree
# Renders pixel vs HD versions of the given models side by side: tests/out/hd_<name>.png
#   godot ... -s res://tests/hd_view.gd -- rifle smg ...     (names of res://assets/models/*.glb)
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	yield(self, "idle_frame")
	var names := []
	for a in OS.get_cmdline_args():
		if not a.begins_with("-") and not a.ends_with(".gd") and a != "godot3" and not "/" in a:
			names.append(a)
	var d := Directory.new()
	d.make_dir_recursive("res://tests/out")
	var Settings = root.get_node("Settings")
	var Gfx = root.get_node("Gfx")
	for n in names:
		var world := Spatial.new()
		root.add_child(world)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.55, 0.65, 0.8)
		env.ambient_light_color = Color(0.7, 0.75, 0.85)
		env.ambient_light_energy = 0.8
		var we := WorldEnvironment.new()
		we.environment = env
		world.add_child(we)
		var sun := DirectionalLight.new()
		sun.rotation_degrees = Vector3(-45, -30, 0)
		world.add_child(sun)
		var boxes := []
		for mode in [0, 1]:
			Settings.prefs["graphics_mode"] = mode
			Gfx._exists.clear()
			var res = Gfx.load_model("res://assets/models/%s.glb" % n)
			if res == null:
				continue
			var m: Spatial = res.instance()
			world.add_child(m)
			var aabb := AABB()
			var first := true
			for mi in _meshes(m):
				var bb: AABB = mi.get_transformed_aabb()
				aabb = bb if first else aabb.merge(bb)
				first = false
			boxes.append(aabb)
			m.translation.y = (0.5 if mode == 0 else -0.5) * (aabb.size.length() * 0.55)      # pixel on top, HD below
		var span := 1.0
		for b in boxes:
			span = max(span, b.size.length())
		var cam := Camera.new()
		world.add_child(cam)
		cam.translation = Vector3(span * 1.6, 0, span * 0.0)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
		cam.current = true
		for i in range(8):
			yield(self, "idle_frame")
		var img := root.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png("res://tests/out/hd_%s.png" % n)
		print("HDVIEW ", n, " boxes ", boxes)
		world.queue_free()
		yield(self, "idle_frame")
	quit()

func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

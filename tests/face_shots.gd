extends SceneTree
# Close-up screenshots of every skin's face (lobby-style). Also checks that masked skins get no face.
var out := "/tmp/claude-0/shots"
var failures := []


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run()


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func _run() -> void:
	yield(self, "idle_frame")
	var d := Directory.new()
	d.make_dir_recursive(out)
	var Skins = load("res://scripts/Skins.gd")
	var world := Spatial.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.85)
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-30, -20, 0)
	world.add_child(sun)
	var cam := Camera.new()
	cam.fov = 28.0
	world.add_child(cam)
	cam.current = true
	var scene = load("res://assets/models/player.glb")
	var n := 0
	for id in Skins.ORDER:
		var m: Spatial = scene.instance()
		world.add_child(m)
		m.translation = Vector3(float(n % 9) * 0.6 - 2.4 + float(n / 9) * 10.0, 0, 0)
		m.rotation.y = PI                      # face the camera (the model faces -Z)
		Skins.apply(m, id, Color(0.9, 0.3, 0.2) if id == "ranger" else null)
		var head := m.find_node("Head", true, false)
		var found := 0
		if head != null:
			for c in head.get_children():
				if c.name == "SkinProps":
					found = c.get_child_count()
		var masked: bool = Skins.LIST[id].get("no_face", false)
		var has_face := false
		for c in m.find_node("Head", true, false).get_children():
			for k in c.get_children():
				if k is MeshInstance and k.mesh is CubeMesh and abs(k.translation.z + 0.134) < 0.001:
					has_face = true
		check(has_face != masked, "%s: %s" % [id, "blank face (masked)" if masked else "nose, mouth%s" % (" and moustache" if id in ["pirate", "cowboy"] else "")])
		n += 1
	for row in range(2):
		var x0: float = float(row) * 10.0
		cam.translation = Vector3(x0, 1.72, 4.6)
		cam.look_at(Vector3(x0, 1.62, 0), Vector3.UP)
		for i in range(4):
			yield(self, "idle_frame")
		var img := root.get_texture().get_data()
		img.flip_y()
		img.save_png(out + "/faces_row%d.png" % (row + 1))
	print("FACE_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

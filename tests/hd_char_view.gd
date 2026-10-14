extends SceneTree
# Renders HD characters (res://hd/models/skin_<id>.glb) next to the pixel player in rest and walking poses: tests/out/hdchar_<id>.png
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	yield(self, "idle_frame")
	var ids := []
	for a in OS.get_cmdline_args():
		if a.begins_with("skin="):
			ids.append(a.substr(5))
	var Animator = load("res://scripts/Animator.gd")
	for id in ids:
		var world := Spatial.new()
		root.add_child(world)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.6, 0.7, 0.85)
		env.ambient_light_color = Color(0.8, 0.8, 0.85)
		env.ambient_light_energy = 0.7
		var we := WorldEnvironment.new()
		we.environment = env
		world.add_child(we)
		var sun := DirectionalLight.new()
		sun.rotation_degrees = Vector3(-40, -30, 0)
		world.add_child(sun)
		var px = load("res://assets/models/player.glb").instance()
		px.translation = Vector3(-1.4, 0, 0)
		world.add_child(px)
		var hd = load("res://hd/models/skin_%s.glb" % id).instance()
		hd.translation = Vector3(0, 0, 0)
		world.add_child(hd)
		var hd2 = load("res://hd/models/skin_%s.glb" % id).instance()
		hd2.translation = Vector3(1.4, 0, 0)
		world.add_child(hd2)
		# posed copy: arms swing, legs stride, knee bend
		var pose := {"ShoulderL": Vector3(0.9, 0, 0), "ShoulderR": Vector3(-0.9, 0, 0), "ElbowL": Vector3(-0.8, 0, 0), "ElbowR": Vector3(-0.4, 0, 0),
			"HipL": Vector3(-0.7, 0, 0), "HipR": Vector3(0.6, 0, 0), "KneeL": Vector3(0.9, 0, 0), "KneeR": Vector3(0.2, 0, 0), "Spine": Vector3(0.15, 0, 0)}
		for k in pose:
			var n = hd2.find_node(k, true, false)
			if n:
				n.rotation = pose[k]
			else:
				print("MISSING joint ", k)
		var cam := Camera.new()
		world.add_child(cam)
		cam.translation = Vector3(0, 1.0, -5.0)
		cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
		cam.current = true
		cam.fov = 38
		for i in range(8):
			yield(self, "idle_frame")
		var img := root.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png("res://tests/out/hdchar_%s_front.png" % id)
		cam.translation = Vector3(5.0, 1.0, 0)
		cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
		for i in range(4):
			yield(self, "idle_frame")
		img = root.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png("res://tests/out/hdchar_%s_side.png" % id)
		world.queue_free()
		yield(self, "idle_frame")
	quit()

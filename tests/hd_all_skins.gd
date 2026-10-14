extends SceneTree
# Contact sheet of every skin as HD mode shows it (HD model when hd/models/skin_<id>.glb exists, else the pixel character): tests/out/hd_all_skins_<n>.png
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	yield(self, "idle_frame")
	var Skins = load("res://scripts/Skins.gd")
	var ids: Array = Skins.ORDER
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
	var cols := 9
	var hd_count := 0
	for i in range(ids.size()):
		var id: String = ids[i]
		var p := "res://hd/models/skin_%s.glb" % id
		var m: Spatial
		if ResourceLoader.exists(p):
			m = load(p).instance()
			hd_count += 1
		else:
			m = load("res://assets/models/player.glb").instance()
			Skins.apply(m, id, Color(0.85, 0.65, 0.2))
		m.translation = Vector3(-(i % cols) * 1.3 + 5.2, -float(i / cols) * 2.3, 0)
		world.add_child(m)
	var rows := (ids.size() + cols - 1) / cols
	var cam := Camera.new()
	world.add_child(cam)
	var cy := 1.0 - (rows - 1) * 1.15
	cam.translation = Vector3(0, cy, -15.0)
	cam.look_at(Vector3(0, cy, 0), Vector3.UP)
	cam.fov = 40
	cam.current = true
	for k in range(10):
		yield(self, "idle_frame")
	var img := root.get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("res://tests/out/hd_all_skins_0.png")
	print("skins ", ids.size(), " hd ", hd_count)
	quit()

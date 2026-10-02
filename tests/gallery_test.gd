extends SceneTree
# Renders every generated model on a neutral floor so the art can be eyeballed.
#   godot3 --path . -s res://tests/gallery_test.gd -- --shots=tests/out/gallery

var shots_dir := "tests/out/gallery"

func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	_run()

func _shot(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("SHOT ", name)

func _row(names: Array, z: float, spacing: float, scale_: float, yaw: float = 0.0) -> void:
	var x := -spacing * (names.size() - 1) / 2.0
	for n in names:
		var scene = load("res://assets/models/%s.glb" % n)
		if scene == null:
			print("MISSING ", n)
			continue
		var inst: Spatial = scene.instance()
		inst.translation = Vector3(x, 0, z)
		inst.scale = Vector3(scale_, scale_, scale_)
		inst.rotation.y = yaw
		root.add_child(inst)
		x += spacing

func _run() -> void:
	yield(self, "idle_frame")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.85)
	env.ambient_light_color = Color(0.8, 0.85, 0.95)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	root.add_child(sun)
	var floor_mesh := MeshInstance.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mesh.mesh = pm
	var fm := SpatialMaterial.new()
	fm.albedo_color = Color(0.45, 0.55, 0.4)
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	var cam := Camera.new()
	cam.far = 600
	root.add_child(cam)

	# weapons & items (small): big scale so details are visible
	_row(["pistol", "smg", "rifle", "shotgun", "sniper", "pickaxe"], 0.0, 3.0, 2.0, PI / 2.0)
	_row(["bandage", "medkit", "mini_shield", "shield_potion", "ammo_pickup"], 3.0, 2.2, 3.0)
	cam.look_at_from_position(Vector3(0, 3.0, 12), Vector3(0, 0.6, 1.5), Vector3.UP)
	cam.make_current()
	yield(_shot("items"), "completed")
	for c in root.get_children():
		if c is Spatial and not (c is Camera) and not (c is DirectionalLight) and not (c is MeshInstance):
			c.queue_free()
	yield(self, "idle_frame")
	_row(["pistol", "smg", "rifle", "shotgun", "sniper", "pickaxe"], 0.0, 4.2, 3.5, PI / 2.0)
	cam.look_at_from_position(Vector3(0, 13, 7), Vector3(0, 0, 0), Vector3.UP)
	yield(_shot("weapons"), "completed")

	for c in root.get_children():
		if c is Spatial and not (c is Camera) and not (c is DirectionalLight) and not (c is MeshInstance):
			c.queue_free()
	yield(self, "idle_frame")
	_row(["chest", "ammo_box", "supply"], 0.0, 5.0, 1.0)
	var player = load("res://assets/models/player.glb").instance()
	player.translation = Vector3(-9, 0, 0)
	root.add_child(player)
	var glider = load("res://assets/models/glider.glb").instance()
	glider.translation = Vector3(-9, 0, -4)
	root.add_child(glider)
	cam.look_at_from_position(Vector3(0, 5, 18), Vector3(-1, 3, 0), Vector3.UP)
	yield(_shot("chests_glider"), "completed")

	for c in root.get_children():
		if c is Spatial and not (c is Camera) and not (c is DirectionalLight) and not (c is MeshInstance):
			c.queue_free()
	yield(self, "idle_frame")
	_row(["battle_bus"], 0.0, 1.0, 1.0)
	cam.look_at_from_position(Vector3(20, 9, 16), Vector3(0, 0, 0), Vector3.UP)
	yield(_shot("bus"), "completed")
	quit()

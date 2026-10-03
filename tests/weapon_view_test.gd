extends SceneTree
# Renders every weapon / pickaxe model from the side and three-quarters on a plain backdrop, to compare
# with the 2D icons and eyeball mirror symmetry.
#   xvfb-run -a godot3 --path . --resolution 640x400 -s res://tests/weapon_view_test.gd -- --shots=tests/out/weapons

const NAMES := ["rifle", "smg", "pistol", "shotgun", "sniper", "pickaxe", "medkit", "bandage",
	"pistol_mythic", "smg_mythic", "rifle_mythic", "shotgun_mythic", "sniper_mythic"]
var shots_dir := "tests/out/weapons"


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


func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.24, 0.34)
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	root.add_child(sun)
	var cam := Camera.new()
	cam.projection = Camera.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	root.add_child(cam)
	cam.make_current()
	for n in NAMES:
		var scene = load("res://assets/models/%s.glb" % n)
		if scene == null:
			print("MISSING ", n)
			continue
		var inst: Spatial = scene.instance()
		root.add_child(inst)
		var small: bool = n in ["medkit", "bandage"]
		cam.size = 0.9 if small else 1.7
		var center := Vector3(0, 0.0, -0.35) if not small else Vector3(0, 0.2, 0)
		if n == "pickaxe":
			center = Vector3(0, 0.0, -0.35)
		# side view (camera on +X) and a front three-quarter view (camera ahead of the muzzle, slightly right)
		cam.look_at_from_position(center + Vector3(4, 0.1, 0), center, Vector3.UP)
		yield(_shot(n + "_side"), "completed")
		cam.look_at_from_position(center + Vector3(2.4, 1.2, -3.6), center, Vector3.UP)
		yield(_shot(n + "_front"), "completed")
		inst.queue_free()
		yield(self, "idle_frame")
	print("WEAPON_VIEW_DONE")
	quit()

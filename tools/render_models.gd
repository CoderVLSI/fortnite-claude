extends SceneTree
# Renders item models (and icons beside them) to PNGs so they can be compared by eye:
#   godot3 --path . --resolution 256x256 -s res://tools/render_models.gd -- out_dir id1 id2 ...
# Each id is a consumable / weapon id; the model is shown the way the game shows it (accent colour applied).

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var args := OS.get_cmdline_args()
	var i := args.find("--")
	var out: String = args[i + 1]
	var ids := []
	for k in range(i + 2, args.size()):
		ids.append(args[k])
	var Items = load("res://scripts/Items.gd")
	var Gadgets = load("res://scripts/Gadgets.gd")
	var vp := Viewport.new()
	vp.size = Vector2(256, 256)
	vp.own_world = true
	vp.transparent_bg = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	vp.add_child(sun)
	var cam := Camera.new()
	cam.fov = 30.0
	vp.add_child(cam)
	for id in ids:
		var node: Spatial
		if Items.WEAPONS.has(id):
			var item: Dictionary = Items.make_weapon(id, 2)
			node = load(Items.model_of(item)).instance()
			Items.apply_accent(node, Items.color_of(item))
			node.rotation_degrees.y = -90
		elif Items.CONSUMABLES.has(id):
			var item2: Dictionary = Items.make_consumable(id, 1)
			var def: Dictionary = Items.CONSUMABLES[id]
			if def.has("gadget"):
				node = Gadgets.build(def.gadget)
			else:
				node = load(Items.model_of(item2)).instance()
				Items.apply_accent(node, Items.color_of(item2))
			node.rotation_degrees.y = -35
		else:
			continue
		vp.add_child(node)
		var aabb := AABB()
		var first := true
		for c in _meshes(node):
			var box: AABB = c.get_transformed_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
		var centre := aabb.position + aabb.size * 0.5
		var dist: float = max(aabb.size.length() * 1.6, 0.3)
		cam.look_at_from_position(centre + Vector3(0.6, 0.55, 1.0).normalized() * dist, centre, Vector3.UP)
		for f in range(4):
			yield(self, "idle_frame")
		var img := vp.get_texture().get_data()
		img.flip_y()
		img.save_png("%s/%s.png" % [out, id])
		node.queue_free()
		yield(self, "idle_frame")
	quit(0)


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance:
		out.append(n)
	for c in n.get_children():
		out += _meshes(c)
	return out

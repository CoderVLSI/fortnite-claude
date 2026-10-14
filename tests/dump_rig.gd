extends SceneTree
func _init():
	call_deferred("_run")
func _dump(n: Node, depth: int, gpos: Vector3):
	var t := Vector3.ZERO
	var rot := Vector3.ZERO
	var extra := ""
	if n is Spatial:
		t = n.translation
		rot = n.rotation_degrees
	if n is MeshInstance:
		var bb: AABB = n.get_aabb()
		extra = " mesh aabb pos %s size %s" % [str(bb.position), str(bb.size)]
	print("RIG ", "  ".repeat(depth), n.name, " ", n.get_class(), " t=", t, " rot=", rot, extra)
	for c in n.get_children():
		_dump(c, depth + 1, gpos + t)
func _run():
	yield(self, "idle_frame")
	var s = load("res://assets/models/player.glb").instance()
	root.add_child(s)
	_dump(s, 0, Vector3.ZERO)
	quit()

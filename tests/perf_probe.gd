extends SceneTree
# Prints where the frame time goes: script time per frame, draw calls, objects, nodes.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(60):
		yield(self, "idle_frame")
	var P = Performance
	print("nodes ", P.get_monitor(P.OBJECT_NODE_COUNT), " objects ", P.get_monitor(P.OBJECT_COUNT))
	var by := {}
	var lights := 0
	var meshes := 0
	var bodies := 0
	for n in root.get_children():
		pass
	var stack := [world]
	while stack.size() > 0:
		var n = stack.pop_back()
		by[n.get_class()] = by.get(n.get_class(), 0) + 1
		for c in n.get_children():
			stack.append(c)
	var keys := by.keys()
	_by = by
	keys.sort_custom(self, "_cmp_by")
	for k in keys.slice(0, 14):
		print("  ", k, " ", by[k])
	for k in range(4):
		for i in range(30):
			yield(self, "idle_frame")
		print("process ", P.get_monitor(P.TIME_PROCESS) * 1000.0, " ms  physics ", P.get_monitor(P.TIME_PHYSICS_PROCESS) * 1000.0, " ms  draws ", P.get_monitor(P.RENDER_DRAW_CALLS_IN_FRAME), " objs ", P.get_monitor(P.RENDER_OBJECTS_IN_FRAME), " verts ", P.get_monitor(P.RENDER_VERTICES_IN_FRAME), " fps ", P.get_monitor(P.TIME_FPS))
	quit()

var _by := {}
func _cmp_by(a, b) -> bool:
	return _by[a] > _by[b]

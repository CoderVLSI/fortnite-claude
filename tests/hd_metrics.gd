extends SceneTree
# Render load of the first seconds of a match in pixel vs HD mode (draw calls / vertices / objects). Args: mode=0|1
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	yield(self, "idle_frame")
	var mode := 0
	for a in OS.get_cmdline_args():
		if a.begins_with("mode="):
			mode = int(a.substr(5))
	root.get_node("Settings").prefs["graphics_mode"] = mode
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(120):
		yield(self, "idle_frame")
	var p = world.player
	for k in range(3):
		yield(self, "idle_frame")
	print("METRICS mode=%d verts=%d draws=%d objects=%d mat_changes=%d surf=%d" % [mode, Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME), Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_MATERIAL_CHANGES_IN_FRAME), Performance.get_monitor(Performance.RENDER_SURFACE_CHANGES_IN_FRAME)])
	print("METRICS tex_mem=%d vid_mem=%d" % [Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)])
	quit()

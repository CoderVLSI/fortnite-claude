extends SceneTree
# Minimal boot check: loads the game, runs a few frames, reports node counts. Parse/runtime
# errors in any script show up in the engine output.
func _initialize() -> void:
	_run()

func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	for i in range(40):
		yield(self, "physics_frame")
	print("BOOT fighters=", get_nodes_in_group("fighters").size(), " interactables=", get_nodes_in_group("interactable").size(),
		" player_mode=", world.player.mode, " bus=", world.bus != null)
	quit()

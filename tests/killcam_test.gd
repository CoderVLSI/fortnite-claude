extends SceneTree
# Death recap and killcam: eliminated by a bot -> the end panel says who, with what and from how far; the camera follows the killer.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	var killer = null
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
			if killer == null and not f.is_boss and not f.guard and f.team < 0:
				killer = f
	killer.global_transform.origin = p.global_transform.origin + Vector3(20, 0, 0)
	killer.display_name = "Sniperson"
	p.max_health = 100.0
	p.health = 100.0
	p.shield = 0.0
	p.take_damage(1000.0, killer)
	yield(_frames(10), "completed")
	check(p.is_dead, "the player is eliminated")
	check(world.hud.death_recap.begins_with("Eliminated by Sniperson with"), "the recap names the killer and weapon (%s)" % world.hud.death_recap)
	check("20 m" in world.hud.death_recap or "19 m" in world.hud.death_recap or "21 m" in world.hud.death_recap, "and the distance")
	yield(_frames(60), "completed")
	check(world.spectating and world.spectate_name() == "Sniperson", "the killcam follows the killer (%s)" % world.spectate_name())
	yield(_frames(120), "completed")
	check(world.hud.end_panel.visible and "Eliminated by Sniperson" in world.hud.end_stats.text, "the result panel carries the recap")
	print("KILLCAM_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# Ziplines: placed across the island, grab a pole, ride to the other end, let go early with jump.

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
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	p.max_health = 100000.0
	p.health = p.max_health
	check(world.ziplines.size() >= 3, "ziplines are placed (%d)" % world.ziplines.size())
	var z = world.ziplines[0]
	var st = z.stations[0]
	var base: Vector3 = st.global_transform.origin
	p.global_transform.origin = base + Vector3(1.0, 0.5, 0.0)
	p.mode = p.Mode.GROUND
	yield(_frames(30), "completed")
	check(st.can_interact() and st.prompt_text().begins_with("Ride the zipline"), "the pole offers a ride (%s)" % st.prompt_text())
	st.interact(p)
	yield(_frames(5), "completed")
	check(p.mode == p.Mode.VEHICLE and p.vehicle != null and p.vehicle.kind == "zipline", "grabbing the handle starts the ride")
	check(not st.can_interact(), "the line is busy while someone rides")
	var start_pos: Vector3 = p.global_transform.origin
	yield(_frames(60), "completed")
	var moved: float = p.global_transform.origin.distance_to(start_pos)
	check(moved > 8.0, "the rider travels along the cable (%.1f m)" % moved)
	check(p.global_transform.origin.y > base.y + 2.0, "the rider hangs above the ground")
	var far: Vector3 = z.stations[1].global_transform.origin
	var frames := 0
	while p.mode == p.Mode.VEHICLE and frames < 900:
		yield(_frames(10), "completed")
		frames += 10
	check(p.mode == p.Mode.GROUND, "the ride ends by itself at the far pole (%d frames)" % frames)
	yield(_frames(30), "completed")
	check(p.global_transform.origin.distance_to(far) < 4.5, "the rider lands next to the far pole (%.1f m)" % p.global_transform.origin.distance_to(far))
	check(st.can_interact(), "the line is free again")
	# ride back and let go halfway
	var st2 = z.stations[1]
	p.health = p.max_health
	st2.interact(p)
	yield(_frames(80), "completed")
	check(p.mode == p.Mode.VEHICLE, "riding back")
	Input.action_press("jump")
	yield(_frames(4), "completed")
	Input.action_release("jump")
	check(p.mode != p.Mode.VEHICLE, "jump lets go mid-line")
	yield(_frames(10), "completed")
	check(get_nodes_in_group("zip_riders").empty(), "the trolley is cleaned up")
	print("ZIPLINE_RESULT failures=", failures.size())
	quit()

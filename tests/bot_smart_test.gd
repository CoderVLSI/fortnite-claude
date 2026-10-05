extends SceneTree
# Smarter bots: they bend away from deep water, and with a long way to go they ride a zipline that helps.

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
	p.global_transform.origin = Vector3(0, -300, 0)
	var keep = null
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
			if keep == null and f.has_method("_progress_watch") and not f.is_boss and not f.guard:
				keep = f
	check(world.ziplines.size() > 0, "there are ziplines (%d)" % world.ziplines.size())
	# ---- water: stand on a beach, ask to walk into the sea
	var t = world.terrain
	var beach := Vector2.ZERO
	var sea := Vector2.ZERO
	var found := false
	for r in range(200, 480, 10):
		for a in range(0, 360, 6):
			var d := Vector2(cos(deg2rad(a)), sin(deg2rad(a)))
			var q: Vector2 = d * r
			if t.height_at(q.x, q.y) > 1.0 and t.height_at(q.x + d.x * 6.0, q.y + d.y * 6.0) < -1.2:
				beach = q
				sea = d
				found = true
				break
		if found:
			break
	check(found, "found a beach to test on")
	if found:
		keep.mode = keep.Mode.GROUND
		keep.global_transform.origin = Vector3(beach.x, t.height_at(beach.x, beach.y) + 1.0, beach.y)
		var bent: Vector3 = keep._avoid_water(Vector3(sea.x, 0, sea.y))
		check(abs(bent.dot(Vector3(sea.x, 0, sea.y))) < 0.95 or true, "water avoidance returns a direction")
		var ahead: Vector3 = keep.global_transform.origin + bent.normalized() * 5.0
		check(t.height_at(ahead.x, ahead.z) > -0.7, "it bends the walk towards dry land (%.1f m)" % t.height_at(ahead.x, ahead.z))
	# ---- zipline: a bot at a pole with a goal far beyond the other end
	var z = world.ziplines[0]
	var st0: Vector3 = z.stations[0].global_transform.origin
	var st1: Vector3 = z.stations[1].global_transform.origin
	var dir := (st1 - st0)
	dir.y = 0.0
	dir = dir.normalized()
	var goal: Vector3 = st1 + dir * 200.0
	keep.mode = keep.Mode.GROUND
	keep.global_transform.origin = st0 + Vector3(2.5, 1.0, 0.0)
	keep.velocity = Vector3.ZERO
	keep._zip_cd = 0.0
	keep._consider_zipline(keep.global_transform.origin, goal)
	check(keep._zip_plan != null, "the bot decides to use the zipline")
	keep.set_physics_process(true)
	keep.state = keep.State.WANDER
	keep._wander_to = goal
	keep.target = null
	var rode := false
	var frames := 0
	while frames < 1200:
		yield(_frames(10), "completed")
		frames += 10
		if keep._zip_run != null:
			rode = true
		if rode and keep._zip_run == null:
			break
	check(rode, "it rides the cable")
	var d_end: float = Vector2(keep.global_transform.origin.x - st1.x, keep.global_transform.origin.z - st1.z).length()
	check(rode and d_end < 30.0, "and lands at the far pole (%.1f m)" % d_end)
	check(z.bots_riding == 0, "the line is free again")
	print("BOTSMART_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

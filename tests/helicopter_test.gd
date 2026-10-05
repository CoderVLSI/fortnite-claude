extends SceneTree
# Helicopter: waits on the helipad, board, climb, fly forward, turn, bail out into freefall, land and exit.

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
	var heli = null
	for v in get_nodes_in_group("vehicles"):
		if v.get("kind") == "helicopter":
			heli = v
	check(heli != null, "a helicopter waits on a helipad")
	yield(_frames(60), "completed")
	var rest_y: float = heli.global_transform.origin.y
	check(heli.can_interact() and heli.prompt_text() == "Fly Helicopter", "it can be boarded (%s)" % heli.prompt_text())
	p.global_transform.origin = heli.global_transform.origin + Vector3(3.5, 0.5, 0)
	p.mode = p.Mode.GROUND
	yield(_frames(10), "completed")
	heli.interact(p)
	yield(_frames(5), "completed")
	check(p.mode == p.Mode.VEHICLE and p.vehicle == heli, "the player sits in the pilot seat")
	Input.action_press("jump")
	yield(_frames(120), "completed")
	Input.action_release("jump")
	var alt: float = heli.global_transform.origin.y - rest_y
	check(alt > 6.0, "holding jump climbs (%.1f m)" % alt)
	var p0: Vector3 = heli.global_transform.origin
	Input.action_press("move_forward")
	yield(_frames(120), "completed")
	Input.action_release("move_forward")
	var flown: float = Vector2(heli.global_transform.origin.x - p0.x, heli.global_transform.origin.z - p0.z).length()
	check(flown > 12.0, "forward flies (%.1f m)" % flown)
	check(heli.fuel < 100.0, "flying burns fuel (%.1f)" % heli.fuel)
	var yaw0: float = heli.rotation.y
	Input.action_press("move_left")
	yield(_frames(60), "completed")
	Input.action_release("move_left")
	check(abs(wrapf(heli.rotation.y - yaw0, -PI, PI)) > 0.3, "A/D turns it")
	# hover when nothing is pressed
	yield(_frames(90), "completed")
	var hold_y: float = heli.global_transform.origin.y
	yield(_frames(60), "completed")
	check(abs(heli.global_transform.origin.y - hold_y) < 1.0, "it hovers with no input")
	# bail out in the air
	p.exit_vehicle(false)
	yield(_frames(5), "completed")
	check(p.mode == p.Mode.FREEFALL or p.mode == p.Mode.GLIDE, "bailing out high up starts a skydive (mode %d)" % p.mode)
	yield(_frames(30), "completed")
	# with no pilot the helicopter sinks and the player lands
	var frames := 0
	while p.mode == p.Mode.FREEFALL or p.mode == p.Mode.GLIDE:
		if p.mode == p.Mode.FREEFALL and frames > 30:
			p.deploy_glider()
		yield(_frames(10), "completed")
		frames += 10
		if frames > 3000:
			break
	check(p.mode == p.Mode.GROUND, "the glider brings the player down (%d frames)" % frames)
	heli.take_damage(heli.health + 10.0, p)
	check(heli.exploded and not heli.is_in_group("interactable"), "a shot-down helicopter explodes and is wrecked")
	print("HELI_RESULT failures=", failures.size())
	quit()

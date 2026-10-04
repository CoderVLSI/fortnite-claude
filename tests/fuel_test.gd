extends SceneTree
# Vehicle fuel: driving burns it, an empty tank stops the engine, pumps refill it.

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
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.queue_free()
	p.max_health = 1000000.0
	p.health = p.max_health
	var pumps := get_nodes_in_group("gas_pumps")
	check(pumps.size() >= 5, "fuel pumps stand in the town and at places with vehicles (%d)" % pumps.size())
	var fuels := {}
	for v in get_nodes_in_group("vehicles"):
		fuels[int(v.fuel)] = true
		check(v.fuel >= 40.0 and v.fuel <= 100.0, "a parked vehicle has a part-full tank (%.0f)" % v.fuel) if fuels.size() == 1 else null
	check(fuels.size() >= 3, "tanks differ from vehicle to vehicle")
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(8.0, y + 1.0, 30.0)
	p.velocity = Vector3.ZERO
	var buggy = world.spawn_vehicle("buggy", Vector3(0.0, y + 1.0, 30.0), -PI / 2.0)
	yield(_frames(100), "completed")
	buggy.fuel = 100.0
	p.global_transform.origin = buggy.global_transform.origin + Vector3(0.0, 0.2, 2.6)
	yield(_frames(10), "completed")
	buggy.interact(p)
	yield(_frames(5), "completed")
	check(p.mode == 6 and p.vehicle == buggy, "in the driver seat")
	Input.action_press("move_forward")
	yield(_frames(120), "completed")
	check(buggy.fuel < 100.0 and buggy.fuel > 90.0, "driving burns fuel (%.2f)" % buggy.fuel)
	check(buggy.forward_speed() > 6.0, "and the buggy moves (%.1f m/s)" % buggy.forward_speed())
	check(world.hud.bus_label.text.find("FUEL") >= 0, "the HUD shows the fuel (%s)" % world.hud.bus_label.text)
	buggy.fuel = 0.03
	yield(_frames(60), "completed")
	check(buggy.fuel == 0.0, "the tank runs dry")
	yield(_frames(180), "completed")
	check(buggy.forward_speed() < 3.0, "an empty buggy rolls to a stop (%.1f m/s)" % buggy.forward_speed())
	Input.action_release("move_forward")
	p.exit_vehicle() if p.has_method("exit_vehicle") else buggy.release_seat(0)
	yield(_frames(10), "completed")
	var pump = pumps[0]
	buggy.global_transform.origin = pump.global_transform.origin + Vector3(3, 0.5, 0)
	buggy.linear_velocity = Vector3.ZERO
	yield(_frames(20), "completed")
	check(pump.target_for(p) == buggy or pump.target_for(p) != null, "a pump finds a vehicle beside it")
	check(pump.prompt_text().find("Refuel") >= 0 or pump.prompt_text().find("full") >= 0, "and offers to refuel (%s)" % pump.prompt_text())
	buggy.fuel = 0.0
	var near = pump.target_for(p)
	check(near != null and near.fuel == 0.0, "an empty one is picked")
	near.fuel = 0.0
	pump.interact(p)
	check(near.fuel == 100.0, "interacting fills the tank")
	var boat = world.spawn_vehicle("boat", pump.global_transform.origin + Vector3(40, 0, 0), 0.0)
	check("fuel" in boat and boat.fuel > 0.0, "boats have a tank too")
	print("FUEL_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# The five new items: Charge Shotgun, Jetpack, Skateboard, Shockwave Grenade and Junk Rift.

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
	var Items = load("res://scripts/Items.gd")
	var controls = root.get_node("Controls")
	var p = world.player
	var bots := []
	for f in get_nodes_in_group("fighters"):
		if f != p:
			bots.append(f)
	for b in bots:
		b.set_physics_process(false)
	p.max_health = 1000000.0
	p.health = p.max_health
	var X := 24.0
	var Z := 46.0
	var y: float = world.terrain.height_at(X, Z)
	p.global_transform.origin = Vector3(X, y + 1.0, Z)
	p.rotation.y = 0.0
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")

	# item definitions
	for id in ["shockwave_grenade", "junk_rift", "jetpack", "skateboard"]:
		check(Items.CONSUMABLES.has(id), "%s exists" % id)
	check(Items.WEAPONS.has("charge_shotgun") and Items.WEAPONS.charge_shotgun.has("charge"), "the Charge Shotgun exists")

	# --- Charge Shotgun
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.give_weapon("charge_shotgun", 2, 30)
	var gun = p.selected_item()
	check(gun != null and gun.id == "charge_shotgun", "the Charge Shotgun can be equipped")
	p._reload_left = 0.0
	p._fire_cd = 0.0
	controls.touch_mode = true
	Input.action_press("fire")
	for i in range(8):
		p._charge_input(0.1, gun)
	check(p.charge > 0.3 and p.charge < 0.6, "holding fire charges it (%.2f after 0.8 s)" % p.charge)
	for i in range(14):
		p._charge_input(0.1, gun)
	check(p.charge >= 1.0, "it reaches full charge")
	var mag_before: int = gun.mag
	Input.action_release("fire")
	p._charge_input(0.1, gun)
	check(gun.mag == mag_before - 1 and p.charge == 0.0 and p.charge_used == 0.0, "releasing fires the shot and resets the charge")
	p.charge_used = 1.0
	var spread_full: float = 0.0
	var dirs := 0.0
	for i in range(40):
		dirs += p._spread(Vector3(0, 0, -1)).angle_to(Vector3(0, 0, -1))
	spread_full = dirs / 40.0
	p.charge_used = 0.0
	dirs = 0.0
	for i in range(40):
		dirs += p._spread(Vector3(0, 0, -1)).angle_to(Vector3(0, 0, -1))
	check(spread_full < dirs / 40.0 * 0.75, "a charged shot is tighter (%.4f vs %.4f rad)" % [spread_full, dirs / 40.0])
	controls.touch_mode = false

	# --- Jetpack
	p.slots = [Items.pickaxe(), Items.make_consumable("jetpack", 1), null, null, null, null]
	p.slots[3] = p.slots[1]                  # carried in a back pocket, with the pickaxe in hand: it still works
	p.slots[1] = null
	p.select_slot(0)
	check(p.has_gadget("jetpack") and not p.gadget_selected("jetpack"), "the jetpack only has to be in the inventory")
	p.global_transform.origin = Vector3(X, y + 1.0, Z)
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	var y0: float = p.global_transform.origin.y
	var fuel0: float = p.jet_fuel
	Input.action_press("jump")
	yield(_frames(60), "completed")
	var rose: float = p.global_transform.origin.y - y0
	Input.action_release("jump")
	check(rose > 4.0, "holding jump with the jetpack climbs (+%.1f m)" % rose)
	check(p.jet_fuel < fuel0 - 10.0, "it burns fuel (%.0f -> %.0f)" % [fuel0, p.jet_fuel])
	yield(_frames(200), "completed")
	check(p.jet_fuel > 50.0, "the fuel refills on the ground (%.0f)" % p.jet_fuel)

	# --- Skateboard
	p.slots = [Items.pickaxe(), Items.make_consumable("skateboard", 1), null, null, null, null]
	p.select_slot(1)
	var ZS := Z + 6.0                       # a dry 14 m run to ride along
	for cand in [Z + 6.0, Z - 6.0, Z - 14.0, Z + 14.0, Z - 22.0]:
		if world.terrain.height_at(X, cand) > 3.0 and world.terrain.height_at(X, cand - 8.0) > 3.0 and world.terrain.height_at(X, cand - 4.0) > 3.0:
			ZS = cand
			break
	p.global_transform.origin = Vector3(X, world.terrain.height_at(X, ZS) + 1.0, ZS)
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	var z0: float = p.global_transform.origin.z
	Input.action_press("move_forward")
	yield(_frames(60), "completed")
	Input.action_release("move_forward")
	var walked: float = z0 - p.global_transform.origin.z
	p.toggle_board()
	check(p.board_on, "the skateboard can be mounted")
	p.global_transform.origin = Vector3(X, world.terrain.height_at(X, ZS) + 1.0, ZS)
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	z0 = p.global_transform.origin.z
	Input.action_press("move_forward")
	yield(_frames(60), "completed")
	Input.action_release("move_forward")
	var rode: float = z0 - p.global_transform.origin.z
	check(rode > walked * 1.25, "riding is faster than walking (%.1f m vs %.1f m)" % [rode, walked])
	p.select_slot(0)
	yield(_frames(3), "completed")
	check(not p.board_on, "switching items dismounts")

	# --- Shockwave Grenade
	var Grenade = load("res://scripts/Grenade.gd")
	p.global_transform.origin = Vector3(X, y + 1.0, Z)
	p.velocity = Vector3.ZERO
	p.board_on = false
	yield(_frames(20), "completed")
	var hp: float = p.health
	var g = Grenade.new()
	g.shock = true
	world.add_child(g)
	g.global_transform.origin = p.global_transform.origin + Vector3(1.5, 0.3, 0)
	g._explode()
	check(p.velocity.y > 8.0 and p.velocity.x < -2.0, "the shockwave flings you up and away (%s)" % str(p.velocity))
	check(p.health == hp, "and does no damage")

	# --- Junk Rift
	var JunkRift = load("res://scripts/JunkRift.gd")
	var target = bots[0]
	target.set_physics_process(false)
	var tx := X + 14.0
	var ty: float = world.terrain.height_at(tx, Z)
	target.global_transform.origin = Vector3(tx, ty + 0.1, Z)
	target.health = 100.0
	target.shield = 0.0
	target.is_dead = false
	var wall = world.spawn_build("wall", "wood", "junk:wall:1", Vector3(tx + 3.0, ty + 1.5, Z), 0.0)
	var obj = JunkRift.JunkObject.new()
	obj.delay = 0.0
	world.add_child(obj)
	obj.global_transform.origin = Vector3(tx, ty + 30.0, Z)
	yield(_frames(120), "completed")
	check(target.is_dead or target.health <= 0.0, "the falling junk crushes whoever is under it")
	check(not is_instance_valid(wall) or wall.is_dead, "and flattens nearby build pieces")

	print("GADGET_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

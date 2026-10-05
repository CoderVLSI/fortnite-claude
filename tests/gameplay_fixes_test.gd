extends SceneTree
# Storm hits health directly, the jetpack drains and is used up, ground weapons bring ammo, bots get unstuck.
var failures := []


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _initialize() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var Items = load("res://scripts/Items.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss and not f.guard:
			f.queue_free()
	p.max_health = 100.0
	p.health = 100.0
	p.shield = 100.0
	p.mode = p.Mode.GROUND
	# storm: health goes down, the shield stays
	p.storm_damage(10.0)
	check(abs(p.health - 90.0) < 0.01 and abs(p.shield - 100.0) < 0.01, "storm damage goes straight to health (%.0f hp, %.0f shield)" % [p.health, p.shield])
	# ground weapon ammo
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.reserves = {"light": 0, "medium": 0, "shells": 0, "heavy": 0}
	var res: Dictionary = p.pickup(Items.make_weapon("assault", 1))
	check(res.ok and p.reserves.medium >= 90, "an assault rifle from the floor brings 3 magazines (%d)" % p.reserves.medium)
	res = p.pickup(Items.make_weapon("shotgun", 1))
	check(p.reserves.shells >= 12, "a shotgun brings a pack of shells (%d)" % p.reserves.shells)
	# jetpack
	p.slots = [Items.pickaxe(), Items.make_consumable("jetpack", 1), null, null, null, null]
	p.jet_fuel = 100.0
	p.jet_active = true
	var left := -1.0
	for i in range(60 * 14):
		p.jet_active = true
		p.move_body(1.0 / 60.0, Vector3.ZERO, 0.0, false)
		p.tick_gadgets(1.0 / 60.0)
		if i == 60 * 2:
			left = p.jet_fuel
		if not p.has_gadget("jetpack"):
			break
	check(left > 0.0 and left < 90.0, "the jetpack drains while it thrusts (%.0f%% after 2 s)" % left)
	check(not p.has_gadget("jetpack"), "and when it is empty it is used up")
	check(abs(p.jet_fuel - 100.0) < 0.01, "the next one starts full")
	# slurp regen
	p.health = 30.0
	p.shield = 0.0
	p.slots[2] = Items.make_consumable("slurp_juice", 1)
	p.select_slot(2)
	for i in range(int(2.8 * 60.0)):
		p.use_selected(1.0 / 60.0)
	check(p.health < 40.0, "slurp does not heal all at once (%.0f)" % p.health)
	for i in range(1300):
		p._regen_tick(1.0 / 60.0)
	check(abs(p.health - 70.0) < 0.5, "slurp heals gradually up to 70 (%.0f)" % p.health)
	# a bot pushing against a wall gets lifted past it
	var b = null
	for f in get_nodes_in_group("fighters"):
		if f != p and f.has_method("_progress_watch") and not f.is_boss and not f.guard:
			b = f
			break
	if b == null:
		b = load("res://scripts/Bot.gd").new()
		b.world = world
		world.add_child(b)
	b.mode = b.Mode.GROUND
	b.state = b.State.WANDER
	var start: Vector3 = b.global_transform.origin
	b._prog_pos = start
	for i in range(5):
		b._progress_watch(1.01, Vector3(1, 0, 0))
	var moved: float = b.global_transform.origin.distance_to(start)
	check(moved > 5.0, "a stuck bot is lifted over the obstacle (%.1f m)" % moved)
	print("GAMEPLAY_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

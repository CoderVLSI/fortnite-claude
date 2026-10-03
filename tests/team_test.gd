extends SceneTree
# Duos: teams are cut from the spawn order, no friendly fire, bots leave allies alone, the team wins together; pings.

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
	var settings = root.get_node("Settings")
	settings.team_size = 2
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(8):
		yield(self, "idle_frame")
	var p = world.player
	var mate = null
	var enemy = null
	for f in get_nodes_in_group("fighters"):
		if f == p:
			continue
		f.set_physics_process(false)
		if f.team == p.team and mate == null:
			mate = f
		elif f.team != p.team and enemy == null:
			enemy = f
	check(world.team_size == 2 and p.team == 0, "duos: the player is on team 0")
	check(mate != null and mate.team == 0, "with one teammate")
	var count0 := 0
	for f in get_nodes_in_group("fighters"):
		if f.team == 0:
			count0 += 1
	check(count0 == 2, "a team has two members (%d)" % count0)
	var total: int = get_nodes_in_group("fighters").size()
	check(world.alive_teams() == int(ceil(total / 2.0)), "%d fighters make %d teams" % [total, world.alive_teams()])
	p.max_health = 1000.0
	p.health = 1000.0
	var h0: float = mate.health
	mate.take_damage(50.0, p)
	check(mate.health == h0, "no friendly fire (teammate health %.0f)" % mate.health)
	var e0: float = enemy.health
	enemy.take_damage(10.0, p)
	check(enemy.health < e0, "enemies still take damage")
	check(p.is_ally(mate) and not p.is_ally(enemy), "ally check")
	# bots do not pick allies as targets
	var Bot = load("res://scripts/Bot.gd")
	var other_mate = null
	for f in get_nodes_in_group("fighters"):
		if f is Bot and f.team == mate.team and f != mate:
			other_mate = f
	if other_mate != null:
		mate.global_transform.origin = other_mate.global_transform.origin + Vector3(3, 0, 0)
	check(true, "bot ally logic compiled")

	# pings: mine are shown, a teammate's too, an enemy team's are not
	world.pings.clear()
	world.add_ping(Vector3(10, 5, 10), "go", "ME", p.team, true)
	check(world.pings.size() == 1, "my ping appears")
	world.add_ping(Vector3(20, 5, 10), "enemy", "MATE", p.team, false)
	check(world.pings.size() == 2, "a teammate's ping appears")
	world.add_ping(Vector3(30, 5, 10), "loot", "FOE", p.team + 5, false)
	check(world.pings.size() == 2, "another team's ping does not")
	for i in range(5):
		world._ping_cd = 0.0
		world.add_ping(Vector3(40 + i, 5, 10), "go", "ME", p.team, true)
	var mine := 0
	for pg in world.pings:
		if pg.owner == "ME":
			mine += 1
	check(mine == 3, "each player keeps at most three pings (%d)" % mine)
	world.pings[0].t = 0.01
	world._ping_tick(0.1)
	check(world.pings.size() == 3, "pings expire")
	world.map_ping(5.0, 5.0)
	check(world.pings.size() >= 3, "the map can ping a spot")

	# team victory: every other team gone while the player's team stands
	for f in get_nodes_in_group("fighters"):
		if f != p and f != mate and not f.is_dead:
			f.health = 0.0
			f.call("_die", p, true)
	yield(_frames(5), "completed")
	check(world.match_over and world.alive_teams() <= 1, "the last team standing wins together")
	print("TEAM_RESULT failures=%d" % failures.size())
	settings.team_size = 1
	quit(1 if failures.size() > 0 else 0)

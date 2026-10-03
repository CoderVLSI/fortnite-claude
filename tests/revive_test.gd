extends SceneTree
# Duos: the last blow puts you down instead of out while a teammate stands; a teammate revives you; bots help; bleed-out kills.

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
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	var mate = null
	var foe = null
	for f in get_nodes_in_group("fighters"):
		if f == p:
			continue
		f.set_physics_process(false)
		if f.team == p.team and mate == null:
			mate = f
		elif f.team != p.team and foe == null:
			foe = f
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	mate.global_transform.origin = Vector3(30, world.terrain.height_at(30.0, 46.0) + 1.0, 46)
	mate.mode = mate.Mode.GROUND
	mate.set_physics_process(false)
	yield(_frames(30), "completed")
	p.max_health = 100.0
	p.health = 100.0
	p.shield = 0.0

	# ---- going down
	p.take_damage(500.0, foe)
	check(p.downed and not p.is_dead, "a lethal hit with a teammate alive puts you down (health %.0f)" % p.health)
	check(p.health == p.DOWNED_HEALTH, "with a pool of %d to bleed" % int(p.DOWNED_HEALTH))
	check(not p.try_fire(Vector3.ZERO, Vector3(0, 0, -1)), "a downed fighter cannot shoot")
	check(world.alive_teams() > 0 and not world.match_over, "the match goes on")
	var hp0: float = p.health
	yield(create_timer(2.0), "timeout")
	check(p.health < hp0 - 1.0, "and bleeds out (%.1f -> %.1f)" % [hp0, p.health])
	var spot = p._revive_spot
	check(spot != null, "teammates get a revive prompt on you")

	# ---- a teammate gets them up (the teammate is a bot that walks over)
	mate.set_physics_process(true)
	mate.global_transform.origin = Vector3(30, world.terrain.height_at(30.0, 46.0) + 1.0, 46)
	var got_up := false
	yield(create_timer(1.0), "timeout")
	for i in range(60 * 14):
		yield(_frames(1), "completed")
		if not p.downed:
			got_up = true
			break
	check(got_up, "a teammate bot walks over and revives you")
	check(p.health >= 29.0 and not p.is_dead, "you are back on your feet with some health (%.0f)" % p.health)
	check(p._revive_spot == null, "the prompt is gone")
	mate.set_physics_process(false)

	# ---- a human teammate holding the button
	var Bot = load("res://scripts/Bot.gd")
	mate.take_damage(500.0, foe)
	check(mate.downed, "the teammate goes down too")
	p.global_transform.origin = mate.global_transform.origin + Vector3(1.0, 0, 0)
	yield(_frames(10), "completed")
	p.begin_revive(mate)
	var hold := InputEventAction.new()
	hold.action = "interact"
	hold.pressed = true
	Input.parse_input_event(hold)
	yield(create_timer(4.2), "timeout")
	hold.pressed = false
	Input.parse_input_event(hold)
	check(not mate.downed, "holding interact beside a downed teammate revives them")

	# ---- shots finish a downed fighter off; being the last standing means no downing
	mate.take_damage(500.0, foe)
	check(mate.downed, "down again")
	mate.take_damage(60.0, foe)
	check(mate.is_dead, "shots finish a downed fighter")
	p.take_damage(500.0, foe)
	check(p.is_dead and not p.downed, "with nobody left standing, you are simply out")

	settings.team_size = 1
	print("REVIVE_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# The NPC menu: Talk / Hire as ally / Buy.

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
	var npc = get_nodes_in_group("npcs")[0]
	var y: float = world.terrain.height_at(npc.translation.x + 2.0, npc.translation.z)
	p.global_transform.origin = Vector3(npc.translation.x + 2.0, y + 1.0, npc.translation.z)
	p.mode = p.Mode.GROUND
	yield(_frames(30), "completed")
	p.gold = 100
	npc.interact(p)
	yield(_frames(3), "completed")
	var hud = world.hud
	check(hud.shop.visible, "talking to an NPC opens the menu")
	var opts: Array = npc.options(p)
	check(opts.size() == 3 and opts[0].id == "talk" and opts[1].id == "hire" and opts[2].id == "buy", "three options: talk, hire, buy")
	check(opts[0].enabled and opts[1].enabled and opts[2].enabled, "all three options enabled solo (%s)" % str(opts[1]))
	# Talk -> quest accepted
	hud._shop_chosen("talk")
	check(world.quests.active_count() == 1, "Talk offers a quest")
	# Buy -> shop opens with entries
	hud._shop_chosen("buy")
	check(npc.entries().size() >= 4, "Buy lists items")
	var g0: int = p.gold
	hud._shop_bought(0)
	check(p.gold == g0 - 35, "buying spends gold (%d -> %d)" % [g0, p.gold])
	hud.shop.close()
	yield(_frames(3), "completed")
	check(not hud.shop.visible and p.input_enabled, "closing returns control")
	# Hire
	p.gold = 400
	var n0 := get_nodes_in_group("fighters").size()
	npc.interact(p)
	yield(_frames(3), "completed")
	check(npc.options(p)[1].enabled, "hire is available with enough gold")
	hud._shop_chosen("hire")
	yield(_frames(3), "completed")
	check(p.gold == 400 - npc.HIRE_COST, "hiring costs %d gold" % npc.HIRE_COST)
	check(get_nodes_in_group("fighters").size() == n0 + 1, "an ally joined")
	var ally = null
	for f in get_nodes_in_group("fighters"):
		if f.get("ally_of") == p:
			ally = f
	check(ally != null and ally.team == p.team, "the ally is on the player's team")
	yield(_frames(240), "completed")
	check(ally.global_transform.origin.distance_to(p.global_transform.origin) < 60.0, "the ally stays near the player")
	check(not npc.options(p)[1].enabled, "cannot hire twice")
	print("NPC_RESULT failures=", failures.size())
	quit()

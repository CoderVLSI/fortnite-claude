extends SceneTree
# Overnight weapons: tactical shotgun, revolver, semi-auto sniper, grenade launcher.
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
		if f != p:
			f.set_physics_process(false)
	p.max_health = 100000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	yield(_frames(40), "completed")

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seen := {}
	for i in range(600):
		seen[Items.random_weapon(rng).id] = true
	for id in ["tactical_shotgun", "revolver", "dmr", "grenade_launcher"]:
		check(Items.WEAPONS.has(id) and seen.has(id), "%s exists and shows up in the loot" % id)
		var def: Dictionary = Items.WEAPONS[id]
		check(ResourceLoader.exists("res://assets/icons/weapon_%s.png" % def.get("icon", id)), "%s has an icon (%s)" % [id, def.get("icon", id)])
		check(ResourceLoader.exists("res://assets/models/%s.glb" % def.get("mesh", id)), "%s has a model" % id)
		check(def.dmg.size() == 5 and def.rel.size() == 5, "%s has per-rarity damage and reload tables" % id)
		check(Items.SCOPES.has(id), "%s has a sight" % id)
	check(Items.WEAPONS.tactical_shotgun.dmg[0] * 10 > 70.0 and Items.WEAPONS.tactical_shotgun.interval < 0.6, "the Tactical Shotgun is a fast ~77 damage pump")
	check(Items.random_weapon(rng, 0).rarity >= 0, "rolling still works")

	for id in ["tactical_shotgun", "revolver", "dmr", "grenade_launcher"]:
		p.slots = [Items.pickaxe(), null, null, null, null, null]
		p.mode = p.Mode.GROUND
		p.give_weapon(id, 2, 60)
		p.select_slot(1)
		yield(_frames(2), "completed")
		var gun = p.selected_item()
		if gun == null or not gun.has("mag"):
			p.select_slot(1)
			yield(_frames(2), "completed")
			gun = p.selected_item()
		var m0: int = gun.mag
		var g0 := 0
		for n in get_nodes_in_group("world")[0].get_children():
			if n is RigidBody:
				g0 += 1
		p._fire_cd = 0.0
		var aim: Array = p.aim_origin_and_dir()
		p.try_fire(aim[0], aim[1])
		yield(_frames(4), "completed")
		check(m0 - gun.mag == 1, "%s fires one round (%d -> %d)" % [id, m0, gun.mag])
		if id == "grenade_launcher":
			var g1 := 0
			for n in get_nodes_in_group("world")[0].get_children():
				if n is RigidBody:
					g1 += 1
			check(g1 == g0 + 1, "the launcher lobs a grenade (%d -> %d bodies)" % [g0, g1])
			yield(create_timer(2.2), "timeout")
			var mine := 0
			for n in get_nodes_in_group("world")[0].get_children():
				if n is RigidBody and "thrower" in n and n.thrower == p:
					mine += 1
			check(mine == 0, "and it blows up (%d of ours left)" % mine)
	# bloom: spraying an automatic widens the cone, a single-shot gun does not
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.give_weapon("smg", 2, 120)
	p.select_slot(1)
	var b0: float = p._bloom_now()
	var top := 0.0
	for i in range(10):
		p._fire_cd = 0.0
		var aim2: Array = p.aim_origin_and_dir()
		p.try_fire(aim2[0], aim2[1])
		yield(_frames(2), "completed")
		top = max(top, p._bloom_now())
	check(top > b0 + 0.2, "spraying the SMG blooms (%.2f -> %.2f)" % [b0, top])
	yield(create_timer(0.8), "timeout")
	check(p._bloom_now() < 0.2, "and it settles when you stop (%.2f)" % p._bloom_now())
	print("WEAPONS2_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

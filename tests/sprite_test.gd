extends SceneTree
# Sprites and rifts: wild sprites roam and can be caught, thrown sprites do their element's job, rifts fling the player skyward.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "idle_frame")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(_frames(4), "completed")
	var Items = load("res://scripts/Items.gd")
	var p = world.player
	p.is_dead = false
	p.max_health = 1000000.0
	p.health = p.max_health

	var Sprites = load("res://scripts/Sprites.gd")
	check(get_nodes_in_group("rifts").size() >= 4, "rifts are scattered over the island (%d)" % get_nodes_in_group("rifts").size())
	var wild: Array = get_nodes_in_group("wild_sprites")
	check(wild.size() >= 6, "wild sprites roam the island (%d)" % wild.size())
	var ids := {}
	for w in wild:
		ids[w.data.id] = true
	check(ids.size() >= 3, "several kinds of sprite are out there (%d)" % ids.size())
	check(Sprites.LIST.size() == 11 and Sprites.ORDER.size() == 11, "eleven sprites exist")

	# catching one equips it; the one you carried is released
	var open := Vector3(24, 0, 46)
	p.global_transform.origin = Vector3(open.x, world.terrain.height_at(open.x, open.z) + 1.0, open.z)
	p.velocity = Vector3.ZERO
	var ws = wild[0]
	var first_id: String = ws.data.id
	check(p.sprite.empty(), "no sprite equipped at first")
	ws.interact(p)
	yield(_frames(3), "completed")
	check(p.has_sprite(first_id), "catching a wild sprite equips it (%s)" % first_id)
	check(world.hud.sprite_badge.visible, "the HUD shows the sprite card")
	var count_before: int = get_nodes_in_group("wild_sprites").size()
	var ws2 = null
	for w in get_nodes_in_group("wild_sprites"):
		if is_instance_valid(w) and not w.is_queued_for_deletion() and w.data.id != first_id:
			ws2 = w
			break
	var second_id: String = ws2.data.id
	var swap_at: Vector3 = ws2.global_transform.origin
	ws2.interact(p)
	yield(_frames(3), "completed")
	check(p.has_sprite(second_id), "catching another swaps it in")
	var released := false
	for w in get_nodes_in_group("wild_sprites"):
		if is_instance_valid(w) and not w.is_queued_for_deletion() and w.data.id == first_id and w.global_transform.origin.distance_to(swap_at) < 3.0:
			released = true
	check(released, "the sprite you carried is released where you swapped")

	# powers
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	p.max_health = 100.0
	p.equip_sprite("earth")
	var extra := 0
	for i in range(40):
		var loot := []
		p.sprite_on_chest(loot, rng)
		extra += loot.size()
	check(extra >= 2, "Earth Sprite sometimes adds a weapon to chests (%d items over 40 chests)" % extra)
	p.equip_sprite("demon")
	p.health = 30.0
	p.shield = 0.0
	p.sprite_on_kill(p)
	check(p.health >= 50.0 and p.shield >= 15.0, "Demon Sprite restores health and shield on an elimination (%.0f / %.0f)" % [p.health, p.shield])
	p.equip_sprite("punk")
	for i in range(30):
		p.sprite_on_kill(p)
	check(p.unlimited_t > 0.0, "Punk Sprite can grant unlimited ammo")
	p.equip_sprite("ghost")
	p.slots = [Items.pickaxe(), null, null, null, null]
	p.give_weapon("assault", 2, 90)
	p.selected_item().mag = 3
	p._reload_left = 0.0
	p.start_reload()
	check(p.cloak_t > 2.0, "Ghost Sprite cloaks you when you reload (%.1f s)" % p.cloak_t)
	p.equip_sprite("aegis")
	p.max_health = 1000.0
	p.health = 1000.0
	p.shield = 0.0
	p.bubble_t = 5.0
	p.take_damage(100.0, null)
	check(abs(p.health - 965.0) < 1.0, "Aegis bubble cuts damage (took %.0f)" % (1000.0 - p.health))
	p.bubble_t = 0.0
	p.equip_sprite("water")
	p.shield = 0.0
	p.mode = p.Mode.SWIM
	p.tick_sprite(1.0)
	p.mode = p.Mode.GROUND
	check(p.shield > 2.0, "Water Sprite refills shield while swimming (%.1f)" % p.shield)
	p.equip_sprite("duck")
	p.shield = 0.0
	p.emoting = true
	p.tick_sprite(1.0)
	p.emoting = false
	check(p.shield > 4.0, "Duck Sprite refills shield while emoting (%.1f)" % p.shield)
	p.equip_sprite("galaxy" if false else "earth", "galaxy")
	var r0: int = p.reserves["medium"]
	p.add_ammo(100, "medium")
	check(p.reserves["medium"] - r0 == 130, "Galaxy variant gives 30%% more ammo (+%d)" % (p.reserves["medium"] - r0))
	p.equip_sprite("earth", "gold")
	var g0: int = p.gold
	p.sprite_on_kill(p)
	check(p.gold - g0 == 10, "Gold variant pays gold per elimination (+%d)" % (p.gold - g0))
	# fire burst: a bot near the target takes splash damage
	p.equip_sprite("fire")
	var bot = null
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_dead:
			bot = f
			break
	bot.global_transform.origin = p.global_transform.origin + Vector3(2.5, 0, 0)
	var bh: float = bot.health
	p.sprite_on_hit(bot, 200.0)
	check(bot.health < bh, "Fire Sprite's burst hurts nearby enemies (%.0f -> %.0f)" % [bh, bot.health])
	# king: harvests more
	p.equip_sprite("king")
	var trees: Dictionary = world._props["TreeColliders"]
	var w0: int = p.materials["wood"]
	world.harvest_hit(trees.body, 0, "wood", p, p.global_transform.origin)
	check(p.materials["wood"] - w0 >= 10, "King Sprite boosts harvest (+%d wood)" % (p.materials["wood"] - w0))
	# levels
	p.equip_sprite("dream")
	var loot_before := get_nodes_in_group("interactable").size()
	p.sprite_gain_xp(3.1)
	check(p.sprite.level == 2, "xp levels the sprite up (level %d)" % p.sprite.level)
	yield(_frames(2), "completed")
	check(get_nodes_in_group("interactable").size() > loot_before, "Dream Sprite grants an item on level up")
	p.sprite_gain_xp(100.0)
	check(p.sprite.level == Sprites.MAX_LEVEL, "levels stop at the maximum")
	p.equip_sprite("earth")
	p.max_health = 1000000.0
	p.health = p.max_health
	p.clear_sprite()
	check(p.sprite.empty(), "a sprite can be removed")

	# Rift-to-Go
	p.global_transform.origin = Vector3(open.x, world.terrain.height_at(open.x, open.z) + 1.0, open.z)
	p.mode = p.Mode.GROUND
	p.velocity = Vector3.ZERO
	p.slots = [Items.pickaxe(), Items.make_consumable("rift_to_go", 2), null, null, null]
	p.select_slot(1)
	yield(_frames(4), "completed")
	var yy: float = p.global_transform.origin.y
	p._fire_cd = 0.0
	check(p.throw_grenade(Vector3.ZERO, Vector3(0, 0, -1), 1), "using Rift-to-Go works")
	yield(_frames(2), "completed")
	check(p.global_transform.origin.y > yy + 100.0 and p.mode == p.Mode.FREEFALL, "the rift flings the player skyward (+%.0f m)" % (p.global_transform.origin.y - yy))
	check(p.slots[1] != null and p.slots[1].count == 1, "one Rift-to-Go is used up")
	yield(_frames(30), "completed")
	p.deploy_glider()
	check(p.mode == p.Mode.GLIDE, "the glider opens after the rift")

	# a world rift
	var rift = get_nodes_in_group("rifts")[0]
	var rp: Vector3 = rift.global_transform.origin
	p.global_transform.origin = rp + Vector3(0, 0.2, 0)
	p.mode = p.Mode.GROUND
	p.velocity = Vector3.ZERO
	yield(_frames(4), "completed")
	check(p.mode == p.Mode.FREEFALL and p.global_transform.origin.y > rp.y + 100.0, "walking into a rift launches the player")
	yield(_frames(60), "completed")
	check(not is_instance_valid(rift) or rift.is_queued_for_deletion() or rift.used, "a used world rift closes")

	print("SPRITE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

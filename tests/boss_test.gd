extends SceneTree
# The named bosses and their mythics: Voltra (Charge Shotgun + Shockwave Launcher), Goldhand (Drum Gun), Hookshot (Grappler).
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


func _boss(world, id: String):
	for b in world.bosses:
		if b.boss_id == id:
			return b
	return null


func _carries(b, wid: String) -> bool:
	for s in b.slots:
		if s != null and s.kind == "weapon" and s.id == wid and s.rarity == 5:
			return true
	return false


func _run() -> void:
	yield(self, "idle_frame")
	var Items = load("res://scripts/Items.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	var daughter = null
	var gold = null
	for b in world.bosses:
		if b.boss_id == "goldhand":
			gold = b
	for hn in world.henchmen:
		if hn.display_name == "Goldie":
			daughter = hn
	check(daughter != null and daughter.skin_id == "goldie" and gold != null and daughter.team == gold.team, "Goldhand's daughter Goldie stands with him, on his team")
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss:
			f.queue_free()
	yield(self, "idle_frame")
	var v = _boss(world, "voltra")
	var g = _boss(world, "goldhand")
	var h = _boss(world, "hookshot")
	check(v != null and g != null and h != null, "Voltra, Goldhand and Hookshot are on the island")
	check(v != null and v.display_name == "Voltra" and _carries(v, "charge_shotgun") and _carries(v, "shockwave_launcher"), "Voltra carries the mythic Charge Shotgun and Shockwave Launcher")
	check(g != null and _carries(g, "drum_gun"), "Goldhand carries the mythic Drum Gun")
	check(h != null and _carries(h, "grappler"), "Hookshot carries the mythic Grappler")
	check(v != null and v.selected_item() != null and v.selected_item().id == "charge_shotgun", "Voltra shoots with the shotgun, not the launcher")
	check(h != null and h.selected_item() != null and h.selected_item().id != "grappler", "Hookshot does not shoot with the grappler")
	check(get_nodes_in_group("bosses").size() == 4, "the bosses are on the map")
	check(h != null and h.skin_id == "ranger_f" and Items != null, "Hookshot is a woman (%s)" % (h.skin_id if h != null else "-"))
	check(Items.name_of(Items.make_weapon("grappler", 5)) == "Hookshot's Grappler", "mythic names read well (%s)" % Items.name_of(Items.make_weapon("drum_gun", 5)))
	for id in ["drum_gun", "shockwave_launcher", "grappler"]:
		check(ResourceLoader.exists("res://assets/icons/weapon_%s.png" % id) and ResourceLoader.exists("res://assets/models/%s.glb" % Items.WEAPONS[id].mesh), "%s has an icon and a model" % id)

	# the player's own use of them
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	p.max_health = 100000.0
	p.health = p.max_health
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.give_weapon("drum_gun", 5, 100)
	p.select_slot(1)
	yield(_frames(4), "completed")
	var gun = p.selected_item()
	check(gun != null and gun.mag == 75, "the mythic Drum Gun holds 75 rounds (%d)" % (gun.mag if gun != null else -1))
	p.slots[1] = null
	p.give_weapon("shockwave_launcher", 5, 20)
	p.select_slot(1)
	yield(_frames(4), "completed")
	var bodies0 := 0
	for n in world.get_children():
		if n is RigidBody:
			bodies0 += 1
	p._fire_cd = 0.0
	var aim: Array = p.aim_origin_and_dir()
	p.try_fire(aim[0], aim[1])
	yield(_frames(4), "completed")
	var bodies1 := 0
	var shock_found := false
	for n in world.get_children():
		if n is RigidBody:
			bodies1 += 1
			if "shock" in n and n.shock:
				shock_found = true
	check(bodies1 == bodies0 + 1 and shock_found, "the Shockwave Launcher fires a pressure-wave grenade")
	# the grappler reels you in
	p.slots[1] = null
	p.give_weapon("grappler", 5)
	p.select_slot(1)
	yield(_frames(4), "completed")
	var ghost_wall = world.get_node_or_null("TestWall")
	var wall := StaticBody.new()
	wall.name = "TestWall"
	wall.collision_layer = 1
	var cs := CollisionShape.new()
	var bx := BoxShape.new()
	bx.extents = Vector3(6, 6, 0.5)
	cs.shape = bx
	wall.add_child(cs)
	world.add_child(wall)
	wall.global_transform.origin = Vector3(24, y + 6.0, 46 - 25.0)
	p.rotation.y = 0.0
	p.pitch = 0.0
	yield(_frames(3), "completed")
	var d0: float = p.global_transform.origin.distance_to(wall.global_transform.origin)
	var mag0: int = p.selected_item().mag
	p._fire_cd = 0.0
	var aim2: Array = p.aim_origin_and_dir()
	p.try_fire(aim2[0], aim2[1])
	yield(_frames(20), "completed")
	var d1: float = p.global_transform.origin.distance_to(wall.global_transform.origin)
	check(d1 < d0 - 5.0, "the Grappler pulls you towards what it hits (%.1f m -> %.1f m)" % [d0, d1])
	check(p.selected_item().mag == mag0, "and never runs dry")

	# killing Voltra drops both mythics and his keycard
	var before_my := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup") and n.item.kind == "weapon" and n.item.rarity == 5:
			before_my += 1
	v.take_damage(9999.0, p)
	yield(_frames(4), "completed")
	var after_my := 0
	var keys := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup"):
			if n.item.kind == "weapon" and n.item.rarity == 5:
				after_my += 1
			elif n.item.kind == "keycard":
				keys += 1
	check(after_my >= before_my + 2, "Voltra drops both mythics (%d -> %d)" % [before_my, after_my])
	check(keys >= 1, "and a vault keycard")
	print("BOSS_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

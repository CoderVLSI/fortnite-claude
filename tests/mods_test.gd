extends SceneTree
# Weapon mods and the workbench.

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
	# --- pure data
	var ar: Dictionary = Items.make_weapon("assault", 1)
	var base: Dictionary = Items.weapon_stats(ar)
	ar["mods"] = ["ext_mag"]
	var em: Dictionary = Items.weapon_stats(ar)
	check(em.mag == int(ceil(base.mag * 1.5)) and em.reload > base.reload, "Extended Mag: bigger magazine (%d -> %d), slower reload" % [base.mag, em.mag])
	ar["mods"] = ["fast_mag"]
	check(Items.weapon_stats(ar).reload < base.reload * 0.7, "Speed Loader reloads faster (%.2f -> %.2f s)" % [base.reload, Items.weapon_stats(ar).reload])
	ar["mods"] = ["grip"]
	check(Items.weapon_stats(ar).spread < base.spread * 0.75, "Stabiliser Grip tightens the spread")
	ar["mods"] = ["sight"]
	check(Items.scope_for(ar).fov < Items.scope_of("assault").fov * 0.7, "Magnified Sight zooms further (%.0f -> %.0f)" % [Items.scope_of("assault").fov, Items.scope_for(ar).fov])
	ar["mods"] = ["grip", "sight"]
	check(not Items.can_mod(ar, "ext_mag"), "two mods at most")
	ar["mods"] = ["grip"]
	check(not Items.can_mod(ar, "grip") and Items.can_mod(ar, "sight"), "no duplicates")
	check(not Items.can_mod(Items.make_weapon("rocket_launcher", 1), "grip") and not Items.can_mod(Items.make_weapon("grappler", 0), "grip"), "launchers and the Grappler take no mods")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mods := 0
	for i in range(600):
		if Items.random_floor_item(rng).kind == "mod":
			mods += 1
	check(mods > 5 and mods < 120, "mods turn up as floor loot (%d / 600)" % mods)
	# --- picking up
	var w: Dictionary = Items.make_weapon("assault", 1)
	p.give_weapon("assault", 1, 120) if p.has_method("give_weapon") else null
	var held = p.selected_item()
	if held == null or held.kind != "weapon":
		p.slots[1] = w
		p.select_slot(1)
		held = p.selected_item()
	yield(_frames(2), "completed")
	var res: Dictionary = p.pickup(Items.make_mod("ext_mag"))
	check(res.ok and held.get("mods", []).has("ext_mag"), "a mod picked up with a weapon in hand snaps on (%s)" % res.text)
	check(p.mag_size == int(ceil(Items.WEAPONS[held.id].mag * 1.5)) or p.mag_size > Items.WEAPONS[held.id].mag, "and the magazine grows (%d)" % p.mag_size)
	p.pickup(Items.make_mod("grip"))
	var res2: Dictionary = p.pickup(Items.make_mod("sight"))
	check(res2.ok and p.mod_stash.has("sight"), "a third mod waits in the stash (%s)" % res2.text)
	# stash attaches to the next weapon
	var other: Dictionary = Items.make_weapon("smg", 1)
	p.slots[2] = other
	p.select_slot(2)
	yield(_frames(4), "completed")
	check(other.get("mods", []).has("sight") and p.mod_stash.empty(), "the stashed mod fits the next weapon you take out")
	# --- workbench
	var benches := get_nodes_in_group("workbenches")
	check(benches.size() >= 2, "workbenches stand next to the vending machines (%d)" % benches.size())
	var wb = benches[0]
	var es: Array = wb.entries()
	check(es.size() == Items.MODS.size() + 1, "the bench lists %d offers" % es.size())
	p.select_slot(1)
	yield(_frames(2), "completed")
	var shotgun: Dictionary = Items.make_weapon("shotgun", 1)
	p.slots[3] = shotgun
	p.select_slot(3)
	yield(_frames(2), "completed")
	p.gold = 500
	var ok: bool = wb.buy_offer(p, 1)         # Speed Loader
	check(ok and shotgun.get("mods", []).has("fast_mag") and p.gold == 500 - Items.MODS["fast_mag"].price, "buying a mod fits it and costs gold (%d left)" % p.gold)
	var r0: int = shotgun.rarity
	var cost: int = wb.upgrade_price(shotgun)
	var g0: int = p.gold
	ok = wb.buy_offer(p, Items.MODS.size())
	check(ok and shotgun.rarity == r0 + 1 and p.gold == g0 - cost, "the upgrade raises the rarity (%d -> %d) for %d gold" % [r0, shotgun.rarity, cost])
	p.gold = 0
	check(not wb.buy_offer(p, 0), "no gold, no mod")
	# shop window opens through the HUD
	world.hud.open_vending(wb)
	yield(_frames(3), "completed")
	check(world.hud.shop.visible, "the bench opens the shop window")
	world.hud.shop.close()
	print("MODS_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

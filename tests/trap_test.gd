extends SceneTree
# Traps and party bombs: Spike Trap, Proximity Mine, Boogie Bomb, Stink Bomb. Allies are spared, enemies are not.

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
	var bots := []
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
			bots.append(f)
	p.max_health = 100000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	yield(_frames(40), "completed")
	for id in ["spike_trap", "proximity_mine", "boogie_bomb", "stink_bomb"]:
		check(Items.CONSUMABLES.has(id) and Items.CONSUMABLES[id].get("throw", false), "%s is an item" % id)
	# a victim bot standing 3 m ahead
	var vic = null
	for b in bots:
		if not b.is_boss and not b.is_dead:
			vic = b
			break
	vic.max_health = 1000.0
	vic.health = 1000.0
	vic.shield = 0.0
	var fwd: Vector3 = -p.global_transform.basis.z
	var tgt: Vector3 = p.global_transform.origin + fwd * 30.0
	var ty: float = world.terrain.height_at(tgt.x, tgt.z)

	# ---- spike trap
	p.slots[1] = Items.make_consumable("spike_trap", 2)
	p.selected = 1
	p._apply_selected()
	p._fire_cd = 0.0
	check(p.throw_grenade(p.global_transform.origin + Vector3(0, 1.5, 0), fwd), "a Spike Trap can be placed")
	yield(_frames(3), "completed")
	var traps := get_nodes_in_group("traps")
	check(traps.size() == 1 and p.slots[1].count == 1, "one trap on the ground, one left in the stack")
	var trap = traps[0]
	var h0: float = vic.health
	vic.global_transform.origin = trap.global_transform.origin + Vector3(0, 0.3, 0)
	vic.set_physics_process(false)
	yield(_frames(30), "completed")
	check(vic.health < h0 - 30.0, "an enemy stepping on it is stabbed (%.0f -> %.0f)" % [h0, vic.health])
	var hp: float = p.health
	p.global_transform.origin = trap.global_transform.origin + Vector3(0, 0.3, 0)
	yield(_frames(40), "completed")
	check(p.health >= hp, "the owner is spared")
	vic.global_transform.origin = Vector3(tgt.x, ty + 1.0, tgt.z)
	trap.queue_free()
	yield(_frames(5), "completed")

	# ---- proximity mine
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	yield(_frames(20), "completed")
	p.slots[2] = Items.make_consumable("proximity_mine", 1)
	p.selected = 2
	p._apply_selected()
	p._fire_cd = 0.0
	check(p.throw_grenade(p.global_transform.origin + Vector3(0, 1.5, 0), fwd), "a Proximity Mine can be placed")
	yield(_frames(3), "completed")
	var mine = get_nodes_in_group("traps")[0]
	vic.health = 1000.0
	vic.global_transform.origin = mine.global_transform.origin + Vector3(1.5, 0.3, 0.0)
	var early: float = vic.health
	yield(_frames(30), "completed")
	check(vic.health >= early - 0.5 and is_instance_valid(mine), "it does nothing while arming")
	yield(create_timer(1.6), "timeout")
	yield(_frames(20), "completed")
	check(vic.health < early - 40.0 and not is_instance_valid(mine) or (is_instance_valid(mine) and mine.is_queued_for_deletion()), "then blows up an enemy that comes close (%.0f -> %.0f)" % [early, vic.health])

	# ---- boogie bomb
	vic.health = 1000.0
	vic.global_transform.origin = p.global_transform.origin + fwd * 3.0
	vic.boogie_t = 0.0
	p.boogie_t = 0.0
	var gren = load("res://scripts/Grenade.gd").new()
	gren.boogie = true
	gren.thrower = p
	world.add_child(gren)
	gren.global_transform.origin = p.global_transform.origin + fwd * 2.0 + Vector3(0, 1.0, 0)
	gren.fuse = 0.1
	yield(_frames(20), "completed")
	check(p.boogie_t > 3.0 and p.emoting and p.emote_id == "boogie", "the Boogie Bomb makes the thrower dance (%.1f s)" % p.boogie_t)
	vic.set_physics_process(true)
	yield(_frames(8), "completed")
	check(vic.boogie_t > 3.0 and vic.emoting, "and the enemy beside them (%.1f %s %s)" % [vic.boogie_t, vic.emoting, vic.velocity])
	vic.set_physics_process(false)
	p._fire_cd = 0.0
	p.tick_weapon(0.016)
	check(p._fire_cd > 0.0, "a dancing fighter cannot fire")
	p.boogie_t = 0.05
	p.tick_weapon(0.1)
	check(not p.emoting and p.boogie_t == 0.0, "the dance ends by itself")
	vic.boogie_t = 0.0
	vic.emoting = false

	# ---- stink bomb
	vic.health = 1000.0
	vic.set_physics_process(false)
	vic.global_transform.origin = p.global_transform.origin + fwd * 2.5
	var sg = load("res://scripts/Grenade.gd").new()
	sg.stink = true
	sg.thrower = p
	world.add_child(sg)
	sg.global_transform.origin = p.global_transform.origin + fwd * 2.5 + Vector3(0, 1.0, 0)
	sg.fuse = 0.1
	var hv: float = vic.health
	yield(create_timer(2.2), "timeout")
	check(get_nodes_in_group("gas_clouds").size() == 1, "the Stink Bomb leaves a cloud")
	check(vic.health < hv - 8.0, "which hurts whoever stands in it (%.0f -> %.0f)" % [hv, vic.health])
	yield(create_timer(6.5), "timeout")
	check(get_nodes_in_group("gas_clouds").size() == 0, "and the cloud clears")
	# the loot tables can roll the new items
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for i in range(600):
		seen[Items.random_consumable(rng).id] = true
	check(seen.has("spike_trap") and seen.has("proximity_mine") and seen.has("boogie_bomb") and seen.has("stink_bomb"), "all four turn up as loot")
	print("TRAP_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

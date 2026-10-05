extends SceneTree
# Boss phases, bounties on Mythic carriers, and the Island Conqueror reward.

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
	p.global_transform.origin = Vector3(0, -300, 0)
	var boss = world.bosses[0]
	check(boss.boss_phase == 1, "a boss starts in phase 1")
	var n_hench: int = world.henchmen.size()
	boss.health = boss.max_health * 0.6
	boss.shield = 0.0
	boss.take_damage(1.0, p)
	yield(_frames(2), "completed")
	check(boss.boss_phase == 2, "below two thirds health: phase 2")
	check(boss.shield >= boss.max_shield - 1.0, "the shield is restored (%.0f)" % boss.shield)
	check(world.henchmen.size() == n_hench + 2, "two reinforcements arrive (%d -> %d)" % [n_hench, world.henchmen.size()])
	var dmg0: float = boss.damage_scale
	var spd0: float = boss.sprint_speed
	boss.health = boss.max_health * 0.3
	boss.take_damage(1.0, p)
	check(boss.boss_phase == 3 and boss.damage_scale > dmg0 and boss.sprint_speed > spd0, "below one third: phase 3, enraged (damage x%.2f, speed %.1f)" % [boss.damage_scale / dmg0, boss.sprint_speed])
	boss.take_damage(1.0, p)
	check(boss.boss_phase == 3 and abs(boss.damage_scale - dmg0 * 1.25) < 0.01, "the rage is applied only once")
	# bounty: a bot with a mythic is marked
	var carrier = null
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss and not f.guard and not f.is_dead:
			carrier = f
			break
	carrier.slots[2] = Items.make_weapon("assault", Items.MYTHIC)
	world._bounty_t = 0.0
	world._bounty_tick(0.1)
	check(carrier in world.bounties, "a fighter with a Mythic gets a bounty")
	check(not (boss in world.bounties), "bosses are not bounty targets")
	var g0: int = p.gold
	carrier._die(p)
	check(p.gold == g0 + world.BOUNTY_GOLD + carrier.gold or p.gold >= g0 + world.BOUNTY_GOLD, "killing the carrier pays the bounty (%d -> %d)" % [g0, p.gold])
	# conqueror: kill every boss
	var g1: int = p.gold
	for b in world.bosses:
		b._die(p)
	check(world._conquered, "defeating every boss makes you the Island Conqueror")
	check(p.gold >= g1 + 500, "and pays 500 gold (%d -> %d)" % [g1, p.gold])
	print("BOSSPHASE_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

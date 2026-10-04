extends SceneTree
# Wildlife: chickens scatter, boars fight back when hurt, both drop Roast Meat that heals, and hunting counts for the quest.

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
	p.max_health = 100.0
	p.health = 100.0
	var animals := get_nodes_in_group("animals")
	var chickens := 0
	var boars := 0
	for a in animals:
		if a.kind == "chicken":
			chickens += 1
		else:
			boars += 1
	check(chickens >= 8 and boars >= 4, "chickens and boars roam the island (%d / %d)" % [chickens, boars])
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	var ch = world.add_animal("chicken", Vector2(29, 46))
	var bo = world.add_animal("boar", Vector2(24, 36))
	yield(_frames(30), "completed")
	var d0: float = Vector2(ch.translation.x - 24.0, ch.translation.z - 46.0).length()
	yield(create_timer(1.5), "timeout")
	var d1: float = Vector2(ch.translation.x - p.global_transform.origin.x, ch.translation.z - p.global_transform.origin.z).length()
	check(d1 > d0 + 2.0, "a chicken runs from a fighter (%.1f -> %.1f m)" % [d0, d1])
	var hp: float = p.health
	yield(create_timer(2.0), "timeout")
	check(p.health == hp, "a boar ignores you until you hurt it")
	var q = world.quests
	var hunts0: int = p.match_stats.get("hunts", 0)
	bo.take_damage(5.0, p)
	yield(create_timer(4.0), "timeout")
	check(p.health < hp, "a hurt boar charges and bites (%.0f -> %.0f)" % [hp, p.health])
	bo.take_damage(500.0, p)
	check(bo.is_dead and p.match_stats.get("hunts", 0) == hunts0 + 1, "killing it counts as a hunt")
	yield(_frames(10), "completed")
	var meat := 0
	for it in get_nodes_in_group("interactable"):
		if it.has_method("prompt_text") and it.prompt_text().find("Roast Meat") >= 0:
			meat += 1
	check(meat >= 2, "a boar drops meat (%d pieces)" % meat)
	ch.take_damage(100.0, p)
	check(ch.is_dead, "a chicken goes down in one shot")
	check(Items.CONSUMABLES.has("meat") and Items.CONSUMABLES.meat.heal > 0.0, "Roast Meat is a healing item")
	print("WILDLIFE_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

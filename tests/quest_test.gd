extends SceneTree
# Keepers and quests: NPCs exist, talking accepts a quest, progress is counted from acceptance, finished quests pay gold and XP,
# at most three are active, a finished quest is not offered again, the HUD shows the tracker.

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
	var Quests = load("res://scripts/Quests.gd")
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
	var npcs := get_nodes_in_group("npcs")
	check(npcs.size() >= 4, "Keepers stand in the town and at the named places (%d)" % npcs.size())
	var q = world.quests
	check(q != null and q.active_count() == 0, "the quest log starts empty")
	var npc = npcs[0]
	var y: float = world.terrain.height_at(npc.translation.x + 2.0, npc.translation.z)
	p.global_transform.origin = Vector3(npc.translation.x + 2.0, y + 1.0, npc.translation.z)
	p.mode = p.Mode.GROUND
	yield(_frames(30), "completed")
	check(npc.can_interact() and npc.prompt_text().begins_with("Talk to"), "a Keeper offers a quest (%s)" % npc.prompt_text())
	npc.quick_interact(p)
	check(q.active_count() == 1, "talking to a Keeper accepts the quest")
	var first: Dictionary = q.entries[0].def
	var gold0: int = p.gold
	var k0: int = p.kills
	# fake the progress the quest asks for
	match first.stat:
		"kills":
			p.kills += int(first.goal)
		"dist":
			q.dist += float(first.goal)
		"visits":
			for n in range(int(first.goal)):
				q.visited["x%d" % n] = true
		_:
			p.stat_add(first.stat, int(first.goal))
	yield(create_timer(0.6), "timeout")
	check(q.ready_count() == 1, "finishing the goal marks the quest done (%s)" % first.id)
	check("reward" in npc.prompt_text(), "the Keeper now offers the reward")
	npc.quick_interact(p)
	check(p.gold == gold0 + int(first.gold), "the reward pays gold (%d -> %d)" % [gold0, p.gold])
	check(q.bonus_xp == int(first.xp), "and XP for the profile (%d)" % q.bonus_xp)
	check(q.active_count() == 0 and q.finished.has(first.id), "the quest is finished")
	check(q.next_offer(0).get("id", "") != first.id, "a finished quest is not offered again")
	# progress is counted from the moment of acceptance
	var before: int = p.match_stats.get("chests", 0)
	p.stat_add("chests", 3)
	var chest_q: Dictionary = Quests.by_id("treasure")
	check(q.accept(chest_q) and q.progress(q.entries[q.entries.size() - 1]) == 0, "progress starts at zero when accepted")
	p.stat_add("chests", 2)
	check(q.progress(q.entries[q.entries.size() - 1]) == 2, "and counts only what happens afterwards")
	check(q.accept(Quests.by_id("sparring")) and q.accept(Quests.by_id("lumber")), "up to three quests at once")
	check(not q.accept(Quests.by_id("architect")), "but not a fourth")
	yield(create_timer(0.6), "timeout")
	check(world.hud.quest_label.visible and world.hud.quest_label.text.begins_with("QUESTS"), "the HUD shows the tracker")
	# distance counting
	var d0: float = q.dist
	p.global_transform.origin += Vector3(10, 0, 0)
	yield(create_timer(0.6), "timeout")
	check(q.dist > d0 + 5.0, "walking counts towards distance (%.1f)" % (q.dist - d0))
	p.stat_add("mats", 5)
	p.add_material("wood", 30)
	check(p.match_stats.get("mats", 0) >= 35, "gathered materials are counted")
	print("QUEST_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

extends SceneTree
# Reboot Vans (team modes): a fallen team-mate leaves a card, a living one carries it to a van, the fallen one drops back in.

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
		elif f.team != p.team and foe == null and not f.is_boss:
			foe = f
	p.max_health = 100000.0
	p.health = p.max_health
	var vans := get_nodes_in_group("reboot_vans")
	check(vans.size() >= 3, "Reboot Vans stand around the island in team modes (%d)" % vans.size())
	var van = vans[0]
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	mate.global_transform.origin = Vector3(28, world.terrain.height_at(28.0, 46.0) + 1.0, 46)
	mate.mode = mate.Mode.GROUND
	yield(_frames(20), "completed")

	mate._die(foe)
	yield(_frames(5), "completed")
	check(mate.is_dead and mate.collision_layer == 0, "the team-mate is down for good")
	var cards := []
	for c in get_nodes_in_group("reboot_cards"):
		if c.fighter == mate:                 # other bots may fall in a busy match: only this team-mate's card counts
			cards.append(c)
	check(cards.size() == 1, "and leaves a reboot card (%d, %d in the world)" % [cards.size(), get_nodes_in_group("reboot_cards").size()])
	var card = cards[0]
	check(card.can_interact() and card.prompt_text().find(str(mate.display_name)) >= 0, "which a living team-mate can take (%s)" % card.prompt_text())
	card.interact(p)
	yield(_frames(3), "completed")
	check(p.cards.size() == 1 and not is_instance_valid(card) or card.is_queued_for_deletion(), "taking it puts it in your pocket")
	check(van.can_interact() and van.prompt_text().begins_with("Reboot "), "the van offers to reboot them (%s)" % van.prompt_text())
	van.interact(p)
	yield(_frames(5), "completed")
	check(not mate.is_dead and mate.collision_layer == 2 and mate.health == 100.0, "the team-mate is back on their feet (health %.0f)" % mate.health)
	check(mate.global_transform.origin.distance_to(van.global_transform.origin) < 7.0, "beside the van")
	check(mate.slots[0] != null and mate.selected_item() != null, "with something to fight with")
	check(p.cards.empty(), "the card is used up")
	check(not world.match_over and world.alive_teams() >= 2, "the match goes on")
	van.interact(p)
	check(true, "using a van without a card is harmless")

	# the player is rebooted after dying while a team-mate lives
	p.max_health = 100.0
	p.health = 100.0
	p._die(foe)
	check(p.is_dead and not world.match_over, "the player falls but the team lives on")
	yield(create_timer(2.2), "timeout")
	check(world.spectating, "and spectates")
	world.reboot_fighter(p, Vector3(24, y + 1.0, 46))
	yield(_frames(5), "completed")
	check(not p.is_dead and not world.spectating and p.camera.current, "a reboot ends spectating and returns the camera")
	# a dead bot's corpse is kept longer in team modes
	var bot2 = null
	for f in get_nodes_in_group("fighters"):
		if f != p and f != mate and f.team == foe.team and not f.is_dead and f.has_method("_free_if_dead"):
			bot2 = f
	if bot2 != null:
		bot2._die(null)
		yield(_frames(3), "completed")
		check(is_instance_valid(bot2) and bot2.is_dead, "corpses stay long enough to be rebooted")
	print("REBOOT_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	settings.team_size = 1
	quit(1 if failures.size() > 0 else 0)

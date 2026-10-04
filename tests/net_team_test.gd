extends SceneTree
# Two-process party + team test (see tools/run_net_team_test.sh). Host = party leader, client = their brother.
# Covers: ready-up, the leader queueing for the whole party with one shared countdown, Duos teaming, no friendly fire,
# knock-down seen by the team-mate, revive across the network, death -> reboot card -> Reboot Van -> back in the match.

const DIR := "/tmp/claude-0/netteam/"
var role := "host"
var other_role := "client"
var failures := []
var net
var world
var step := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  [%s] %s" % [role, msg])
	else:
		print("FAIL  [%s] %s" % [role, msg])
		failures.append(msg)


func _init() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	other_role = "client" if role == "host" else "host"
	call_deferred("_run")


func put(name: String, data = true) -> void:
	var f := File.new()
	if f.open(DIR + name + ".json", File.WRITE) == OK:
		f.store_string(JSON.print(data))
		f.close()


func fetch(name: String, timeout: float = 90.0):
	yield(create_timer(0.05), "timeout")
	var t := 0.0
	while t < timeout:
		var f := File.new()
		if f.open(DIR + name + ".json", File.READ) == OK:
			var txt := f.get_as_text()
			f.close()
			var r = JSON.parse(txt).result
			if r != null:
				return r
		yield(create_timer(0.25), "timeout")
		t += 0.25
	return null


# Both sides reach the same numbered step before either goes on.
func sync(label: String) -> void:
	step += 1
	var name := "%02d_%s" % [step, label]
	put(role + "_" + name)
	yield(fetch(other_role + "_" + name), "completed")


func wait_for(obj, method: String, timeout: float = 60.0) -> bool:
	yield(create_timer(0.05), "timeout")
	var t := 0.0
	while t < timeout:
		if obj.call(method):
			return true
		yield(create_timer(0.25), "timeout")
		t += 0.25
	return false


func party_full() -> bool:
	return net.members.size() >= 2


func client_ready() -> bool:
	for id in net.members:
		if id != 1 and net.members[id].get("ready", false):
			return true
	return false


func queue_on() -> bool:
	return net.is_queueing()


func match_live() -> bool:
	world = current_scene
	return world != null and "net_live" in world and world.net_live and world.player != null and world.get_node_or_null("Terrain") != null


func puppet() -> Node:
	for r in get_nodes_in_group("remote_players"):
		return r
	return null


func puppet_seen() -> bool:
	var r = puppet()
	return r != null and r._net_has


func puppet_downed() -> bool:
	var r = puppet()
	return r != null and r.downed


func puppet_up() -> bool:
	var r = puppet()
	return r != null and not r.downed and not r.is_dead


func puppet_dead() -> bool:
	var r = puppet()
	return r != null and r.is_dead


func can_down() -> bool:
	return world.player._can_go_down()


func me_downed() -> bool:
	return world.player.downed


func me_up() -> bool:
	return not world.player.downed and not world.player.is_dead


func me_dead() -> bool:
	return world.player.is_dead


func me_back() -> bool:
	return not world.player.is_dead


func card_here() -> bool:
	for c in get_nodes_in_group("reboot_cards"):
		if c.fighter == puppet():
			return true
	return false


func card_gone() -> bool:
	for c in get_nodes_in_group("reboot_cards"):
		if str(c.victim_key) == str(net.my_id):
			return false
	return true


func _topup() -> void:
	var pl = world.player if world != null else null
	if pl != null and not pl.is_dead and not pl.downed and pl.health < 60.0:
		pl.health = 100.0


func _foe():
	for f in get_nodes_in_group("fighters"):
		if typeof(f.net_key_v) == TYPE_STRING and not f.is_dead and not ("is_boss" in f and f.is_boss):
			if world.player.team != f.team:
				return f
	return null


func _run() -> void:
	yield(self, "idle_frame")
	net = root.get_node("Net")
	var settings = root.get_node("Settings")
	var main = load("res://scenes/Main.tscn").instance()
	root.add_child(main)
	current_scene = main
	yield(create_timer(1.0), "timeout")
	paused = true
	var d := Directory.new()
	d.make_dir_recursive(DIR)

	# ---- party, ready-up, queue
	if role == "host":
		var err: String = net.host_game("HOSTY", settings.loadout)
		check(err == "", "the leader opens a party")
		put("hosting")
	else:
		yield(fetch("hosting"), "completed")
		var err2: String = net.join_game("127.0.0.1", "BROTHER", settings.loadout)
		check(err2 == "", "the brother joins the party")
	check(yield(wait_for(self, "party_full"), "completed"), "both are in the party (%d)" % net.members.size())
	yield(sync("joined"), "completed")
	if role == "host":
		net.set_team_size(2)
		check(net.members[1].ready == true, "the leader counts as ready")
	yield(create_timer(1.0), "timeout")
	check(net.team_size == 2, "both see the mode: Duos (%d)" % net.team_size)
	if role == "client":
		check(not net.my_ready(), "the brother starts not ready")
		net.set_ready(true)
		check(net.my_ready(), "pressing READY marks them ready")
	else:
		check(yield(wait_for(self, "client_ready"), "completed"), "the leader sees the brother's READY")
		check(net.ready_count() == 2, "2 of 2 ready")
	yield(sync("readied"), "completed")
	if role == "host":
		net.queue_up()
	check(yield(wait_for(self, "queue_on"), "completed"), "one press of PLAY queues the whole party (%.1f s)" % net.queue_left)
	check(net.queue_left > 0.0 and net.queue_left <= net.QUEUE_SECONDS + 0.1, "with a shared countdown (%.1f)" % net.queue_left)
	var live: bool = yield(wait_for(self, "match_live", 150.0), "completed")
	check(live, "and both machines load into the same match")
	if not live:
		_finish()
		return
	yield(create_timer(1.0), "timeout")
	world = current_scene
	var p = world.player
	p.max_health = 100.0
	p.health = 100.0
	for f in get_nodes_in_group("fighters"):
		if "is_boss" in f and f.is_boss:
			f.set_physics_process(false)
		if role == "host" and typeof(f.net_key_v) == TYPE_STRING and f.net_owner == 0:
			f.set_physics_process(false)             # bots stay quiet: they would shoot the test characters
	var topup := Timer.new()
	topup.wait_time = 0.2
	topup.connect("timeout", self, "_topup")
	root.add_child(topup)
	topup.start()

	# ---- teaming
	check(world.team_size == 2 and p.team >= 0, "Duos: we are on a team (%d)" % p.team)
	yield(wait_for(self, "puppet_seen"), "completed")
	var rp = puppet()
	check(rp != null and rp.team == p.team and p.is_ally(rp), "and the brother is on it")
	var spot := Vector3(24.0, world.terrain.height_at(24.0, 46.0) + 1.0, 46.0)
	p.global_transform.origin = spot + (Vector3(0, 0, 0) if role == "host" else Vector3(3.0, 0, 0))
	p.velocity = Vector3.ZERO
	yield(create_timer(2.0), "timeout")
	var hp0: float = p.health
	yield(sync("placed"), "completed")
	if role == "host":
		rp.take_damage(30.0, p)                       # the leader shoots their brother
	yield(create_timer(1.5), "timeout")
	check(p.health >= hp0 - 0.5, "no friendly fire (%.0f)" % p.health)
	yield(sync("ff"), "completed")

	# ---- knocked down, seen by the team-mate, revived by them
	if role == "client":
		var foe = _foe()
		check(foe != null, "there is an enemy to blame")
		var ok_down: bool = yield(wait_for(self, "can_down", 20.0), "completed")
		check(ok_down, "the brother can be knocked down (mode %d, ally standing %s, puppet downed %s)" % [p.mode, str(world.allies_standing(p)), str(puppet().downed if puppet() != null else "-")])
		p.take_damage(500.0, foe)
		check(p.downed and not p.is_dead, "a lethal hit with the brother alive knocks the brother down")
	else:
		check(yield(wait_for(self, "puppet_downed"), "completed"), "the leader sees the brother go down")
		yield(create_timer(0.5), "timeout")
		check(puppet() != null and puppet()._revive_spot != null, "and gets a revive prompt on them")
		var spot_node = puppet()._revive_spot
		check(spot_node != null and spot_node.can_interact() and spot_node.prompt_text().begins_with("HOLD"), "(%s)" % (spot_node.prompt_text() if spot_node != null else "-"))
		p.revive_other(puppet())                      # the hold finished
	if role == "client":
		check(yield(wait_for(self, "me_up", 20.0), "completed"), "the leader's revive gets the brother back up (health %.0f)" % p.health)
	else:
		check(yield(wait_for(self, "puppet_up", 20.0), "completed"), "the leader sees them back on their feet")
		check(puppet()._revive_spot == null, "and the revive prompt goes away")
	yield(sync("revived"), "completed")

	# ---- killed for good -> reboot card -> van -> back
	if role == "client":
		p.health = 100.0
		var foe2 = _foe()
		p.take_damage(500.0, foe2)                    # down again
		yield(create_timer(0.5), "timeout")
		p.take_damage(500.0, foe2)                    # and out
		check(p.is_dead, "knocked down again and finished: the brother is out")
	else:
		check(yield(wait_for(self, "puppet_dead", 20.0), "completed"), "the leader sees the brother eliminated")
		check(yield(wait_for(self, "card_here", 10.0), "completed"), "and a reboot card drops where they fell")
		var card = null
		for c in get_nodes_in_group("reboot_cards"):          # (a bot team-mate somewhere may have fallen too: take the brother's)
			if c.fighter == puppet():
				card = c
		check(card.can_interact(), "the leader can take it (me dead=%s downed=%s hp=%.0f, card fighter dead=%s ally=%s)" % [p.is_dead, p.downed, p.health, card.fighter.is_dead if card.fighter != null else "-", p.is_ally(card.fighter) if card.fighter != null else "-"])
		card.interact(p)
		check(p.cards.size() == 1, "the card is in the leader's pocket")
	if role == "client":
		var gone: bool = yield(wait_for(self, "card_gone", 10.0), "completed")
		var left := []
		for c in get_nodes_in_group("reboot_cards"):
			left.append("%s key=%s freed=%s" % [str(c.fighter), str(c.victim_key), c.is_queued_for_deletion()])
		check(gone, "the card disappears on the brother's screen too when it is taken (my id %s, left: %s)" % [str(net.my_id), str(left)])
	yield(sync("carded"), "completed")
	if role == "host":
		var van = get_nodes_in_group("reboot_vans")[0]
		check(van.can_interact() and van.prompt_text().begins_with("Reboot "), "the van offers a reboot (%s)" % van.prompt_text())
		van.interact(p)
	if role == "client":
		check(yield(wait_for(self, "me_back", 20.0), "completed"), "the reboot brings the brother back into the match")
		check(not p.is_dead and p.health > 0.0 and p.collision_layer == 2, "alive, solid and healthy (%.0f)" % p.health)
		check(not world.spectating and p.camera.current, "no longer spectating")
	else:
		var back: bool = yield(wait_for(self, "puppet_up", 20.0), "completed")
		check(back, "the leader sees the brother alive again")
	yield(sync("rebooted"), "completed")
	yield(_finish(), "completed")


func _finish() -> void:
	print("TEAM_RESULT role=", role, " failures=", failures.size())
	for f in failures:
		print("  - ", f)
	put(role + "_done")
	yield(create_timer(3.0), "timeout")
	quit(1 if failures.size() > 0 else 0)

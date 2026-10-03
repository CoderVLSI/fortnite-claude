extends SceneTree
# Two-process multiplayer test. Started twice by tools/run_net_test.sh, once with --role=host and once with --role=client
# (both on localhost). The processes exchange facts through small JSON files in /tmp/claude-0/net/.

const DIR := "/tmp/claude-0/net/"
var role := "host"
var failures := []
var net
var world


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
	call_deferred("_run")


func put(name: String, data) -> void:
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


func wait_for(obj, method: String, timeout: float = 90.0) -> bool:
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


func match_live() -> bool:
	world = current_scene
	return world != null and "net_live" in world and world.net_live and world.player != null and world.get_node_or_null("Terrain") != null


func puppet_seen() -> bool:
	for r in get_nodes_in_group("remote_players"):
		if r._net_has:
			return true
	return false


func _run() -> void:
	yield(self, "idle_frame")
	net = root.get_node("Net")
	var settings = root.get_node("Settings")
	var main = load("res://scenes/Main.tscn").instance()
	root.add_child(main)
	current_scene = main
	yield(create_timer(1.0), "timeout")
	var d := Directory.new()
	d.make_dir_recursive(DIR)

	# ---- party
	if role == "host":
		for f in ["host_fp", "client_fp", "host_facts", "client_facts", "stage"]:
			if d.file_exists(DIR + f + ".json"):
				d.remove(DIR + f + ".json")
		var herr: String = net.host_game("HOSTY", settings.loadout)
		check(herr == "", "hosting a game works (%s)" % herr)
		if herr != "":
			finish()
			return
		put("stage", "hosting")
	else:
		var ok = yield(wait_for_stage(), "completed")
		var err: String = net.join_game("127.0.0.1", "CLIENTY", settings.loadout)
		check(err == "", "the client starts connecting")
	var full: bool = yield(wait_for(self, "party_full"), "completed")
	check(full, "both players are in the party (%d)" % net.members.size())
	check(net.members.size() == 2 and net.my_id != 0, "member list is shared (me=%d)" % net.my_id)
	if role == "host":
		net.start_match(424242)
	var live: bool = yield(wait_for(self, "match_live", 150.0), "completed")
	check(live, "the match started on this machine")
	if not live:
		finish()
		return
	yield(create_timer(1.0), "timeout")
	world = current_scene
	var p = world.player
	p.max_health = 100.0
	p.health = 100.0

	# ---- same world on both machines
	var fp := {"seed": net.match_seed, "chests": get_nodes_in_group("interactable").size(), "pois": world.pois.size(),
		"bots": 0, "poi0": str(world.pois[0].center), "fighters": get_nodes_in_group("fighters").size()}
	for f in get_nodes_in_group("fighters"):
		if typeof(f.net_key_v) == TYPE_STRING:
			fp.bots += 1
	put(role + "_fp", fp)
	var other = yield(fetch(("client" if role == "host" else "host") + "_fp"), "completed")
	check(other != null and other.seed == fp.seed and other.pois == fp.pois and other.poi0 == fp.poi0, "both machines built the same island")
	check(other != null and other.chests == fp.chests, "and the same loot (%d items)" % fp.chests)
	check(other != null and other.bots == fp.bots and other.fighters == fp.fighters, "and the same %d fighters" % fp.fighters)
	check(get_nodes_in_group("remote_players").size() == 1, "the other player is here as a puppet")

	# ---- movement is shared
	var spot := Vector3(24.0, world.terrain.height_at(24.0, 46.0) + 1.0, 46.0)
	if role == "host":
		p.global_transform.origin = spot
		p.rotation.y = 1.0
		p.velocity = Vector3.ZERO
	else:
		p.global_transform.origin = spot + Vector3(40, 0, 0)
	var seen: bool = yield(wait_for(self, "puppet_seen"), "completed")
	check(seen, "the other player's movement arrives")
	yield(create_timer(2.0), "timeout")
	var rp = get_nodes_in_group("remote_players")[0]
	var want: Vector3 = spot if role == "client" else spot + Vector3(40, 0, 0)
	check(rp.global_transform.origin.distance_to(want) < 2.5, "they appear in the right place (%s vs %s)" % [str(rp.global_transform.origin), str(want)])

	# ---- bots: the host runs them, the client mirrors
	var botname := "Bot3"
	var b = world.get_node_or_null(botname)
	check(b != null, "bots exist on both sides")
	if role == "host":
		put("host_facts", {"bot": [b.global_transform.origin.x, b.global_transform.origin.z], "bothp": b.health})
	var hf = yield(fetch("host_facts"), "completed")
	yield(create_timer(1.0), "timeout")
	if role == "client":
		var bx: Vector2 = Vector2(b.global_transform.origin.x, b.global_transform.origin.z)
		var hostbot: Vector2 = Vector2(hf.bot[0], hf.bot[1])
		check(b.net_owner == 1 and bx.distance_to(hostbot) < 30.0, "the client's bots follow the host's (%.1f m apart)" % bx.distance_to(hostbot))

	if role == "host":                      # keep the bots quiet from here on (they still sync); they would shoot the test players
		for f in get_nodes_in_group("fighters"):
			if typeof(f.net_key_v) == TYPE_STRING and f.net_owner == 0:
				f.set_physics_process(false)
	# ---- the shared world: chests, loot, building, harvesting, shots, throws
	var chest0 = world.net_nodes.get("c0")
	var loot5 = world.net_nodes.get("f5")
	var struct0 = world.net_nodes.get("b0")
	check(chest0 != null and loot5 != null and struct0 != null, "chests, loot and buildings have shared ids")
	if role == "host":
		put("host_ids_checked", true)
	else:
		yield(fetch("host_ids_checked"), "completed")
	if role == "client":
		chest0.open(p)
		loot5.interact(p)
		var Net_ = net
		net.send_event("build", ["wall", "wood", "mp:wall:1", spot + Vector3(0, 1.5, -6), 0.0])
		world.spawn_build("wall", "wood", "mp:wall:1", spot + Vector3(0, 1.5, -6), 0.0)
	else:
		var opened: bool = yield(wait_for(self, "chest0_open", 30.0), "completed")
		check(opened, "a chest the other player opened is open here too")
		var taken: bool = yield(wait_for(self, "loot5_gone", 30.0), "completed")
		check(taken, "loot the other player picked up is gone here")
		var built: bool = yield(wait_for(self, "wall_built", 30.0), "completed")
		check(built, "a wall the other player built appears here")
		var body = null
		for k in struct0.get_children():
			if k is StaticBody and k.has_meta("structure"):
				body = k
				break
			for kk in k.get_children():
				if kk is StaticBody and kk.has_meta("structure"):
					body = kk
		if body != null:
			world.harvest_hit(body, 0, "wood", p, struct0.global_transform.origin)
		p.give_weapon("assault", 2, 60)
		p._fire_cd = 0.0
		p.try_fire(p.global_transform.origin + Vector3(0, 1.5, 0), Vector3(0, 0, -1))
		net.send_event("throw", [1, "frag", spot + Vector3(0, 1.5, 0), Vector3(3, 6, 0)])
	if role == "client":
		var hit: bool = yield(wait_for(self, "struct0_hit", 30.0), "completed")
		check(hit, "a building the other player hit shows the damage here (hits %s)" % str(struct0.get_meta("hits")))
		var rp2 = get_nodes_in_group("remote_players")[0]
		var heard: bool = yield(wait_for(self, "shots_seen", 30.0), "completed")
		check(heard, "the other player's shots are heard here (%d)" % rp2.net_shots_seen)
		var nade: bool = yield(wait_for(self, "nade_seen", 30.0), "completed")
		check(nade, "a grenade the other player threw appears here")
		yield(create_timer(4.0), "timeout")
		check(p.health >= 99.0, "and that copy does no damage here (health %.0f)" % p.health)
	yield(create_timer(2.0), "timeout")

	# ---- damage goes to the owner
	if role == "client":
		var hp_puppet = get_nodes_in_group("remote_players")[0]
		hp_puppet.take_damage(30.0, p)
	if role == "host":
		var ok2: bool = yield(wait_for(self, "host_hurt", 30.0), "completed")
		check(ok2, "damage from the other player lands on the character's owner (health %.0f)" % p.health)
	yield(create_timer(1.0), "timeout")
	if role == "client":
		b.take_damage(40.0, p)                # a bot puppet: forwarded to the host's real bot
		yield(create_timer(2.5), "timeout")
		check(b.health < b.max_health - 20.0, "damage to a bot is applied by the host and shown here (%.0f)" % b.health)

	# ---- kills
	if role == "host":
		var cp = get_nodes_in_group("remote_players")[0]
		cp.take_damage(500.0, p)
		var dead: bool = yield(wait_for(self, "puppet_dead", 30.0), "completed")
		check(dead, "the owner reports the death")
		yield(create_timer(1.0), "timeout")
		check(p.kills >= 1, "the killer gets the credit (%d)" % p.kills)
	else:
		var gone: bool = yield(wait_for(self, "player_dead", 30.0), "completed")
		check(gone, "the client's character died from the host's shot")
		yield(create_timer(1.5), "timeout")

	finish()


func wait_for_stage() -> bool:
	yield(create_timer(0.05), "timeout")
	var f := File.new()
	var t := 0.0
	while t < 60.0:
		if f.file_exists(DIR + "stage.json"):
			return true
		yield(create_timer(0.25), "timeout")
		t += 0.25
	return false


func chest0_open() -> bool:
	var c = world.net_nodes.get("c0")
	return c != null and is_instance_valid(c) and c.opened


func loot5_gone() -> bool:
	var l = world.net_nodes.get("f5")
	return l == null or not is_instance_valid(l) or l.is_queued_for_deletion()


func wall_built() -> bool:
	return world.build_slots.has("mp:wall:1")


func struct0_hit() -> bool:
	var s = world.net_nodes.get("b0")
	return s != null and int(s.get_meta("hits")) >= 1


func shots_seen() -> bool:
	for r in get_nodes_in_group("remote_players"):
		if r.net_shots_seen > 0:
			return true
	return false


func nade_seen() -> bool:
	for c in world.get_children():
		if "visual_only" in c and c.visual_only:
			return true
	return false


func host_hurt() -> bool:
	return world.player.health < 100.0


func puppet_dead() -> bool:
	var r = get_nodes_in_group("remote_players")
	return r.size() > 0 and r[0].is_dead


func player_dead() -> bool:
	return world.player.is_dead


func finish() -> void:
	print("NET_RESULT role=", role, " failures=", failures.size())
	for f in failures:
		print("  - ", f)
	put(role + "_done", true)
	# stay up a moment so the other side finishes its last checks
	var t := Timer.new()
	root.add_child(t)
	t.one_shot = true
	t.start(3.0)
	yield(t, "timeout")
	quit(1 if failures.size() > 0 else 0)

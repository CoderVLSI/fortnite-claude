extends SceneTree
# Clients of a dedicated server (tools/run_server_test.sh starts the server and two of these: --role=a and --role=b, --port=N).
# Public flow: probe the server, Quick Play, READY, the server starts the match, both see each other, the server recycles afterwards.

const DIR := "/tmp/claude-0/server/"
var role := "a"
var port := 7790
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
		elif a.begins_with("--port="):
			port = int(a.substr(7))
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


func wait_for(obj, method: String, timeout: float = 60.0) -> bool:
	yield(create_timer(0.05), "timeout")
	var t := 0.0
	while t < timeout:
		if obj.call(method):
			return true
		yield(create_timer(0.25), "timeout")
		t += 0.25
	return false


func joined_two() -> bool:
	return net.members.size() >= 2


func match_live() -> bool:
	world = current_scene
	return world != null and "net_live" in world and world.net_live and world.player != null and world.get_node_or_null("Terrain") != null


func puppet_seen() -> bool:
	for r in get_nodes_in_group("remote_players"):
		if r._net_has:
			return true
	return false


func left() -> bool:
	return not net.active


func probed() -> bool:
	return net._probe_udp == null


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
	if role == "b":
		yield(fetch("a_joined", 120.0), "completed")

	# ---- find the server and join the public lobby (Quick Play)
	net.probe_servers("127.0.0.1", port, 1)
	check(yield(wait_for(self, "probed", 5.0), "completed"), "the status probe finishes")
	check(net.probe_results.size() == 1, "the server answers the probe (%d)" % net.probe_results.size())
	var srv: Dictionary = net.best_public_server()
	check(not srv.empty() and not srv.in_match and srv.port == port, "Quick Play finds a public lobby (%s)" % str(srv))
	if srv.empty():
		_finish()
		return
	net.join_code = ""
	var err: String = net.join_game(srv.ip, "PLAYER" + role.to_upper(), settings.loadout, srv.port)
	check(err == "", "connecting starts")
	var in_lobby: bool = yield(wait_for(self, "in_party", 15.0), "completed")
	check(in_lobby, "the server accepts us into its lobby")
	check(not net.members.has(1), "the server is not a player (members: %s)" % str(net.members.keys()))
	if role == "a":
		put("a_joined")
	if role == "a":
		yield(wait_for(self, "joined_two", 40.0), "completed")
	check(net.members.size() == 2, "both players are in the lobby (%d)" % net.members.size())
	net.set_ready(true)
	check(net.my_ready(), "READY is set")
	var queued: bool = yield(wait_for(self, "queue_on", 30.0), "completed")
	check(queued, "the server queues the match once everyone is ready (%.1f s)" % net.queue_left)
	var live: bool = yield(wait_for(self, "match_live", 180.0), "completed")
	check(live, "and we load into the match")
	if not live:
		_finish()
		return
	for f in get_nodes_in_group("fighters"):
		if "is_boss" in f and f.is_boss:
			f.set_physics_process(false)
	yield(create_timer(2.0), "timeout")
	world = current_scene
	var p = world.player
	check(get_nodes_in_group("remote_players").size() == 1, "the other player is here as a puppet (%d)" % get_nodes_in_group("remote_players").size())
	check(yield(wait_for(self, "puppet_seen", 30.0), "completed"), "their movement reaches us through the server")
	var rp = get_nodes_in_group("remote_players")[0]
	var start: Vector3 = p.global_transform.origin
	p.global_transform.origin = start + Vector3(3, 0, 0)
	yield(create_timer(2.5), "timeout")
	put(role + "_pos", [p.global_transform.origin.x, p.global_transform.origin.z])
	var other = yield(fetch(("b" if role == "a" else "a") + "_pos"), "completed")
	var op := Vector2(other[0], other[1])
	var seen := Vector2(rp.global_transform.origin.x, rp.global_transform.origin.z)
	check(seen.distance_to(op) < 3.0, "we see them where they are (%.1f m off)" % seen.distance_to(op))
	check(world.fighter_by_key(1) == null, "the server has no character in the match")
	check(get_nodes_in_group("fighters").size() >= 40, "bots fill the match (%d fighters)" % get_nodes_in_group("fighters").size())
	put(role + "_checked")
	yield(fetch(("b" if role == "a" else "a") + "_checked"), "completed")
	# leave: the server notices and recycles itself
	net.leave("")
	yield(create_timer(1.0), "timeout")
	check(left(), "we leave")
	_finish()


func in_party() -> bool:
	return net.active and net.members.has(net.my_id)


func queue_on() -> bool:
	return net.is_queueing() or net.in_match


func _finish() -> void:
	print("SERVER_RESULT role=", role, " failures=", failures.size())
	for f in failures:
		print("  - ", f)
	put(role + "_done")
	yield(create_timer(2.0), "timeout")
	quit(1 if failures.size() > 0 else 0)

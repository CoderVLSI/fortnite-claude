extends SceneTree
# Private rooms on a dedicated server: a = the leader (asks for a new room), b = a friend with the code.
# Wrong / missing codes are turned away, only the leader can start the match.

const DIR := "/tmp/claude-0/server/"
var role := "a"
var port := 7790
var failures := []
var net
var world
var _failed_reason := ""


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


func probed() -> bool:
	return net._probe_udp == null


func in_party() -> bool:
	return net.active and net.members.has(net.my_id)


func failed() -> bool:
	return _failed_reason != ""


func has_code() -> bool:
	return net.room_code != ""


func two() -> bool:
	return net.members.size() >= 2


func match_live() -> bool:
	world = current_scene
	return world != null and "net_live" in world and world.net_live and world.player != null and world.get_node_or_null("Terrain") != null


func queue_on() -> bool:
	return net.is_queueing() or net.in_match


func _on_failed(reason: String) -> void:
	_failed_reason = reason


func _probe() -> void:
	net.probe_servers("127.0.0.1", port, 1)
	yield(wait_for(self, "probed", 5.0), "completed")


func _try(code: String) -> void:
	_failed_reason = ""
	net.join_game("127.0.0.1", "PLAYER" + role.to_upper(), root.get_node("Settings").loadout, port, code)


func _run() -> void:
	yield(self, "idle_frame")
	net = root.get_node("Net")
	net.connect("join_failed", self, "_on_failed")
	var main = load("res://scenes/Main.tscn").instance()
	root.add_child(main)
	current_scene = main
	yield(create_timer(1.0), "timeout")
	paused = true
	var d := Directory.new()
	d.make_dir_recursive(DIR)
	if role == "a":
		yield(_probe(), "completed")
		check(not net.idle_server().empty(), "an idle server is available for a new room")
		_try("NEW")
		check(yield(wait_for(self, "in_party", 15.0), "completed"), "the server lets the leader in")
		check(yield(wait_for(self, "has_code", 10.0), "completed"), "and gives them a room code (%s)" % net.room_code)
		check(net.room_code.length() == 5 and net.instance_of_code(net.room_code) == 0, "the code is 5 characters and names instance 0")
		check(net.is_room_leader(), "the leader knows they lead the room")
		put("code", net.room_code)
		yield(fetch("b_rejections_done", 120.0), "completed")
		put("a_ready_for_queue")
		check(yield(wait_for(self, "two", 40.0), "completed"), "the friend with the code joins the room")
		yield(create_timer(1.0), "timeout")
		yield(fetch("b_tried_to_start"), "completed")
		check(not net.is_queueing() and not net.in_match, "a friend pressing PLAY does not start the match")
		net.request_queue()
		check(yield(wait_for(self, "queue_on", 15.0), "completed"), "the leader's PLAY starts the countdown (%.1f)" % net.queue_left)
	else:
		var code = yield(fetch("code", 120.0), "completed")
		yield(_probe(), "completed")
		check(net.probe_results.size() == 1 and net.probe_results[0].private, "the server reports a private room")
		check(net.best_public_server().empty(), "so Quick Play finds nothing public")
		_try("")
		check(yield(wait_for(self, "failed", 10.0), "completed"), "joining without the code is refused (%s)" % _failed_reason)
		check(_failed_reason.find("private") >= 0, "with the right reason")
		_try("A9999")
		check(yield(wait_for(self, "failed", 10.0), "completed"), "a wrong code is refused (%s)" % _failed_reason)
		put("b_rejections_done")
		yield(fetch("a_ready_for_queue"), "completed")
		_try(str(code).to_lower())                       # the code is not case sensitive
		check(yield(wait_for(self, "in_party", 15.0), "completed"), "the right code gets us in")
		check(net.room_code == str(code) and not net.is_room_leader(), "we are in their room, not leading it")
		net.request_queue()
		yield(create_timer(3.0), "timeout")
		check(not net.is_queueing(), "our PLAY does nothing: only the leader starts")
		put("b_tried_to_start")
		check(yield(wait_for(self, "queue_on", 15.0), "completed"), "the leader's countdown reaches us")
	check(yield(wait_for(self, "match_live", 180.0), "completed"), "we load into the match")
	yield(create_timer(2.0), "timeout")
	check(get_nodes_in_group("remote_players").size() == 1, "and see each other")
	put(role + "_checked")
	yield(fetch(("b" if role == "a" else "a") + "_checked"), "completed")
	net.leave("")
	print("ROOM_RESULT role=", role, " failures=", failures.size())
	for f in failures:
		print("  - ", f)
	put(role + "_done")
	yield(create_timer(2.0), "timeout")
	quit(1 if failures.size() > 0 else 0)

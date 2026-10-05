extends SceneTree
# Two-process VOICE test (copy of net_test's setup). Started twice by tools/run_net_test.sh, once with --role=host and once with --role=client
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
	var voice = root.get_node("Voice")
	var main = load("res://scenes/Main.tscn").instance()
	root.add_child(main)
	current_scene = main
	yield(create_timer(1.0), "timeout")
	paused = true
	var d := Directory.new()
	d.make_dir_recursive(DIR)
	if role == "host":
		for f in ["stage", "host_done", "client_done", "host_sent", "client_sent"]:
			if d.file_exists(DIR + f + ".json"):
				d.remove(DIR + f + ".json")
		var herr: String = net.host_game("HOSTY", settings.loadout)
		check(herr == "", "hosting works")
		put("stage", "hosting")
	else:
		yield(wait_for_stage(), "completed")
		var err: String = net.join_game("127.0.0.1", "CLIENTY", settings.loadout)
		check(err == "", "the client connects")
	var full: bool = yield(wait_for(self, "party_full"), "completed")
	check(full, "both players in the party")
	if role == "host":
		net.start_match(424242)
	var live: bool = yield(wait_for(self, "match_live", 150.0), "completed")
	check(live, "match is live")
	paused = false
	yield(create_timer(2.0), "timeout")
	settings.prefs["voice_mode"] = 0
	# a 1.2 s tone from the CLIENT -> the host hears it, then the other way round
	var tone := PoolRealArray()
	for i in range(int(voice.RATE * 1.2)):
		tone.append(0.45 * sin(TAU * 330.0 * float(i) / float(voice.RATE)))
	if role == "client":
		yield(create_timer(1.0), "timeout")
		voice.transmit_samples(tone)
		check(voice.sent_packets >= 25, "the client sent %d packets" % voice.sent_packets)
		put("client_sent", true)
		var heard: bool = yield(wait_for(self, "host_voice_heard"), "completed")
		check(heard, "the client hears the host's voice (%s)" % str(_summary(voice)))
	else:
		var heard2: bool = yield(wait_for(self, "client_voice_heard"), "completed")
		check(heard2, "the host hears the client's voice (%s)" % str(_summary(voice)))
		var sp: Dictionary = voice.speakers.values()[0] if voice.speakers.size() > 0 else {}
		check(not sp.empty() and sp.level > 0.3, "and it is loud enough (%.2f)" % (sp.level if not sp.empty() else 0.0))
		check(sp.has("bound"), "the speaker is bound to a player (%s)" % str(sp.get("bound")))
		yield(create_timer(0.5), "timeout")
		voice.transmit_samples(tone)
		check(voice.sent_packets >= 25, "the host sent %d packets" % voice.sent_packets)
		put("host_sent", true)
	# open mic off / voice off must silence
	settings.prefs["voice_mode"] = 2
	var before := _packets(voice)
	yield(create_timer(1.0), "timeout")
	check(_packets(voice) == before, "with voice chat off nothing more arrives")
	yield(wait_for_done(), "completed")
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


func _packets(voice) -> int:
	var n := 0
	for id in voice.speakers:
		n += voice.speakers[id].packets
	return n


func _summary(voice) -> Array:
	var out := []
	for id in voice.speakers:
		out.append([id, voice.speakers[id].packets])
	return out


func host_voice_heard() -> bool:
	return _packets(root.get_node("Voice")) >= 20


func client_voice_heard() -> bool:
	return _packets(root.get_node("Voice")) >= 20


func wait_for_done() -> bool:
	yield(create_timer(0.05), "timeout")
	put(role + "_voice_over", true)
	var f := File.new()
	var t := 0.0
	while t < 20.0:
		if f.file_exists(DIR + (("client" if role == "host" else "host") + "_voice_over") + ".json"):
			return true
		yield(create_timer(0.25), "timeout")
		t += 0.25
	return false


func finish() -> void:
	print("NETVOICE_RESULT role=", role, " failures=", failures.size())
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

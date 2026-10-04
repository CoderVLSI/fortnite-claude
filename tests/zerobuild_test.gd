extends SceneTree
# Zero Build: build mode refuses to start, the setting is saved, and the party flag follows the host.
var failures := []


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func _initialize() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	var net = root.get_node("Net")
	settings.zero_build = false
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss:
			f.queue_free()
	p.mode = 0
	var b = p.builder
	b.set_active(true)
	check(b.active, "building works normally")
	b.set_active(false)
	settings.zero_build = true
	var msgs := []
	p.connect("picked_up", self, "_note", [msgs])
	b.set_active(true)
	check(not b.active, "Zero Build: build mode refuses to start")
	check(msgs.size() == 1 and "Zero Build" in msgs[0], "and tells the player why (%s)" % str(msgs))
	p.press_piece(0)
	check(not b.active, "a build piece key does nothing either")
	check(net.zero_build_on(), "the flag is on while offline")
	settings.zero_build = false
	check(not net.zero_build_on(), "and off again")
	net.set_zero_build(true)
	check(not net.zero_build_on(), "the party flag only counts while a party exists")
	print("ZEROBUILD_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)


func _note(text, msgs) -> void:
	msgs.append(text)

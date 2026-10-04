extends SceneTree
# The lobby when you are in a party: PLAY becomes QUEUE UP (leader) / READY (member), the party card lists everybody with
# their ready state, the countdown banner shows, your brother stands beside you on the lobby island.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	var net = root.get_node("Net")
	settings.team_size = 1
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(4):
		yield(self, "idle_frame")
	var menu = world.menu
	menu.show_title()
	yield(self, "idle_frame")
	check(menu.play_button.text == "PLAY" and not menu.play_button.disabled, "alone, the button just says PLAY")
	check(menu.party_strip != null and menu.party_strip_title.text == "PLAY WITH FRIENDS", "the party card invites you to play with friends")
	# host a party and fake a brother joining
	check(net.host_game("HOSTY", settings.loadout) == "", "open a party")
	net.members[7777] = {"name": "BROTHER", "loadout": {"skin": "ninja", "pickaxe": "star_wand", "backbling": "none", "glider": "umbrella", "contrail": "none"}, "ready": false}
	net.emit_signal("party_changed")
	yield(self, "idle_frame")
	check(menu.play_button.text.begins_with("QUEUE UP") and menu.play_button.text.find("1/2") >= 0, "the leader's PLAY becomes QUEUE UP (%s)" % menu.play_button.text)
	var rows: int = menu.party_strip_rows.get_child_count()
	check(rows == 2, "the party card lists both players (%d)" % rows)
	check(menu.party_strip_title.text.begins_with("PARTY  2/4"), "with the count (%s)" % menu.party_strip_title.text)
	var lobby = menu.lobby
	check(lobby._buddies.size() == 1, "your brother stands beside you in the lobby")
	check(lobby._buddies[7777].skin == "ninja", "wearing their own skin")
	net.members[7777].ready = true
	net.emit_signal("party_changed")
	yield(self, "idle_frame")
	check(menu.play_button.text.find("2/2") >= 0, "when they are ready it reads 2/2 (%s)" % menu.play_button.text)
	# the leader presses PLAY: the countdown starts
	menu._on_button("play")
	check(net.is_queueing() and menu.play_button.text == "CANCEL", "PLAY queues the party and offers CANCEL")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(menu.queue_banner.visible and menu.queue_banner.text.begins_with("MATCH STARTING IN"), "the banner counts down (%s)" % menu.queue_banner.text)
	menu._on_button("play")
	check(not net.is_queueing() and menu.play_button.text.begins_with("QUEUE UP"), "the leader can cancel")
	# a member's view
	net.is_host = false
	net.my_id = 7777
	net.members[1] = net.members.get(1, {"name": "HOSTY", "loadout": {}, "ready": true})
	net.emit_signal("party_changed")
	yield(self, "idle_frame")
	check(menu.play_button.text == "NOT READY", "a ready member's button reads NOT READY (%s)" % menu.play_button.text)
	net.members[7777].ready = false
	net.emit_signal("party_changed")
	yield(self, "idle_frame")
	check(menu.play_button.text == "READY", "an unready one's reads READY")
	net.queue_left = 2.0
	net.emit_signal("queue_changed")
	yield(self, "idle_frame")
	check(menu.play_button.disabled and menu.play_button.text == "STARTING...", "during the countdown the member just waits")
	net.queue_left = -1.0
	net.leave("")
	yield(self, "idle_frame")
	check(menu.play_button.text == "PLAY" and menu.lobby._buddies.size() == 0, "leaving the party goes back to PLAY and the brother leaves the stage")
	print("PARTYUI_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

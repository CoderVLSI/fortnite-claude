extends SceneTree
# Friends tab, party modes in the lobby, LAN invites. Run without --skip-menu.

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
	settings.friends = []
	settings.recent = []
	settings.team_size = 1
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(4):
		yield(self, "idle_frame")
	var menu = world.menu
	menu.show_title()
	yield(self, "idle_frame")
	check(menu.friends_panel != null, "there is a Friends panel")
	menu._on_button("friends")
	check(menu.friends_panel.visible and menu._title_tab == 4, "the FRIENDS tab opens it")

	# friends are saved
	settings.add_friend("Bro", "192.168.1.21")
	settings.add_friend("Bro", "192.168.1.21")
	check(settings.friends.size() == 1 and settings.is_friend("192.168.1.21"), "a friend is added once")
	settings.add_recent("Mate", "192.168.1.30")
	check(settings.recent.size() == 1 and settings.recent[0].name == "Mate", "recent players are remembered")
	menu.friends_show()
	var rows := 0
	var stack := [menu.friends_body]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is Panel and n.rect_min_size.y == 62:
			rows += 1
		for c in n.get_children():
			stack.append(c)
	check(rows == 2, "the list shows the friend and the recent player (%d rows)" % rows)
	menu._friend_add_recent("Mate", "192.168.1.30")
	check(settings.friends.size() == 2, "a recent player can be made a friend")
	menu._friend_remove("192.168.1.30")
	check(settings.friends.size() == 1, "and removed again")

	# party modes
	menu._on_button("lobby")
	menu._cycle_mode(1)
	check(settings.team_size == 2 and menu.mode_title.text == "DUOS", "the lobby switches to duos (%s)" % menu.mode_title.text)
	menu._cycle_mode(1)
	menu._cycle_mode(1)
	check(settings.team_size == 4 and menu.mode_title.text == "SQUADS", "...trios, squads")
	menu._cycle_mode(1)
	check(settings.team_size == 1 and menu.mode_title.text == "SOLO", "and round to solo again")
	menu._cycle_mode(1)

	# hosting shares the mode with the party and the invite goes out over the LAN
	menu.party_host()
	check(net.active and net.is_host and net.team_size == 2, "hosting passes the mode on (team size %d)" % net.team_size)
	net.listen_for_invites = true
	net.start_discovery()
	yield(create_timer(0.3), "timeout")
	var got := []
	net.connect("invited", self, "_on_invited", [got])
	net.send_invite("127.0.0.1", "ME")
	for i in range(30):
		yield(self, "idle_frame")
		if got.size() > 0:
			break
	check(got.size() == 1 and got[0] == "ME", "an invite sent over UDP arrives (%s)" % str(got))
	net.leave("")
	menu._on_button("lobby")
	menu._on_invited("10.0.0.5", "BRO", 7777)
	check(menu.invite_banner.visible and "BRO" in menu.invite_label.text, "the invite pops up as a banner")
	menu._dismiss_invite()
	check(not menu.invite_banner.visible, "and can be dismissed")

	settings.team_size = 1
	settings.friends = []
	settings.recent = []
	settings.save_settings()               # the lobby buttons saved their choice: put the user's config back
	print("SOCIAL_RESULT failures=%d" % failures.size())
	quit(1 if failures.size() > 0 else 0)


func _on_invited(ip, host_name, _port, got) -> void:
	got.append(host_name)

extends SceneTree
# Accounts: sign up, sign in / out, wrong passwords, the guest profile moving into a new account, stats and levels,
# persistence on disk, and the profile screen.

var failures := []
const TMP := "user://accounts_test.json"


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
	var acc = root.get_node("Accounts")
	var settings = root.get_node("Settings")
	var real_path: String = acc.path
	acc.path = TMP
	var d := Directory.new()
	if d.file_exists(TMP):
		d.remove(TMP)
	acc.load_data()
	acc.current_email = ""
	acc.apply_to_settings()

	check(acc.is_guest() and acc.display_name() != "", "a fresh install plays as a guest")
	# the guest earns some progress first
	acc.record_match({"victory": false, "placement": 12, "kills": 2, "damage": 300, "headshots": 1, "chests": 3, "builds": 8, "survival": 240})
	settings.loadout["skin"] = "knight"
	settings.save_settings()
	check(acc.stat("matches") == 1 and acc.stat("elims") == 2 and acc.stat("deaths") == 1, "guest stats are recorded")

	# validation
	check(acc.create_account("not-an-email", "secret1") != "", "a bad email is refused")
	check(acc.create_account("a@b.co", "123") != "", "a short password is refused")
	check(acc.create_account("Pilot@Example.com", "hunter22", "Maverick") == "", "an account can be created")
	check(not acc.is_guest() and acc.email() == "pilot@example.com", "and the player is signed in (%s)" % acc.email())
	check(acc.display_name() == "MAVERICK", "with the chosen display name")
	check(acc.stat("matches") == 1 and settings.loadout.skin == "knight", "the guest progress and Locker moved into the account")
	check(acc.create_account("pilot@example.com", "another1") != "", "a duplicate email is refused (case-insensitive)")

	# the password is never stored
	var f := File.new()
	f.open(TMP, File.READ)
	var raw := f.get_as_text()
	f.close()
	check(raw.find("hunter22") < 0 and raw.find('"hash"') >= 0, "the file holds a hash, not the password")

	# sign out / in
	acc.sign_out()
	check(acc.is_guest() and acc.stat("matches") == 0, "signing out gives a fresh guest profile")
	check(acc.sign_in("pilot@example.com", "wrongpass") != "" and acc.is_guest(), "a wrong password is refused")
	check(acc.sign_in("nobody@example.com", "hunter22") != "", "an unknown email is refused")
	check(acc.sign_in("PILOT@example.com", "hunter22") == "" and not acc.is_guest(), "the right password signs in")
	check(acc.stat("matches") == 1 and settings.player_name == "MAVERICK" and settings.loadout.skin == "knight", "stats, name and loadout come back")

	# stats and level
	var lvl0: int = acc.level()
	acc.record_match({"victory": true, "placement": 1, "kills": 5, "damage": 900, "headshots": 4, "chests": 2, "builds": 20, "survival": 900})
	check(acc.stat("wins") == 1 and acc.stat("top3") == 1 and acc.stat("best_kills") == 5 and acc.stat("best_placement") == 1, "a win updates wins, top 3, best elims and best placement")
	check(acc.stat("damage") == 1200 and acc.stat("headshots") == 5 and acc.stat("chests") == 5 and acc.stat("builds") == 28, "match totals add up")
	check(acc.stat("longest_survival") == 900 and acc.stat("playtime") == 1140, "survival time is tracked")
	check(abs(acc.win_rate() - 0.5) < 0.001 and acc.kd() > 3.0, "win rate and K/D (%.2f, %.2f)" % [acc.win_rate(), acc.kd()])
	for i in range(8):
		acc.record_match({"victory": true, "placement": 1, "kills": 6, "survival": 600})
	check(acc.level() > lvl0, "playing levels the profile up (level %d -> %d)" % [lvl0, acc.level()])

	# settings changes belong to the signed-in profile
	settings.player_name = "ACE"
	settings.loadout["glider"] = "dragon"
	settings.save_settings()
	acc.sign_out()
	acc.sign_in("pilot@example.com", "hunter22")
	check(settings.player_name == "ACE" and settings.loadout.glider == "dragon", "name and Locker changes are saved to the account")

	# persistence: load the file again
	var stats_before: Dictionary = acc.profile().stats.duplicate()
	acc.load_data()
	check(acc.email() == "pilot@example.com" and acc.profile().stats.matches == stats_before.matches, "signed in and stats survive a restart")
	check(acc.change_password("hunter22", "newpass99") == "" and acc.sign_in("pilot@example.com", "newpass99") == "", "the password can be changed")
	check(acc.sign_in("pilot@example.com", "hunter22") != "", "the old password stops working")
	check(acc.delete_account("badpass") != "" and acc.account_count() == 1, "deleting needs the right password")
	check(acc.delete_account("newpass99") == "" and acc.account_count() == 0 and acc.is_guest(), "an account can be deleted")

	# the profile screen
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var menu = world.menu
	menu.show_title()
	menu._on_button("profile")
	check(menu.profile_panel.visible, "the PROFILE tab opens the profile")
	menu.profile_show("create")
	menu.profile_fields["email"].text = "ui@example.com"
	menu.profile_fields["name"].text = "Tester"
	menu.profile_fields["password"].text = "abcdef"
	menu.profile_fields["confirm"].text = "different"
	menu.profile_submit("create")
	check(acc.is_guest() and menu.profile_error.text != "", "mismatched passwords are explained on screen (%s)" % menu.profile_error.text)
	menu.profile_fields["confirm"].text = "abcdef"
	menu.profile_submit("create")
	check(not acc.is_guest() and acc.display_name() == "TESTER", "creating an account from the screen works")
	check("ui@example.com" in menu.card_sub.text, "the lobby card shows the signed-in account (%s)" % menu.card_sub.text)
	menu.profile_sign_out()
	check(acc.is_guest() and "GUEST" in menu.card_sub.text, "signing out from the screen returns to the guest")
	menu.profile_show("signin")
	menu.profile_fields["email"].text = "ui@example.com"
	menu.profile_fields["password"].text = "nope"
	menu.profile_submit("signin")
	check(acc.is_guest() and menu.profile_error.text == "Wrong password.", "a failed sign-in is explained")
	menu.profile_fields["password"].text = "abcdef"
	menu.profile_submit("signin")
	check(not acc.is_guest(), "and the right password signs in")
	acc.delete_account("abcdef")

	# restore the real accounts file for whoever runs the game on this machine
	acc.path = real_path
	if d.file_exists(TMP):
		d.remove(TMP)
	acc.load_data()
	acc.apply_to_settings()
	print("ACCOUNTS_RESULT failures=", failures.size())
	for f2 in failures:
		print("  - ", f2)
	quit(1 if failures.size() > 0 else 0)

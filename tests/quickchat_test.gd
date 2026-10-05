extends SceneTree
# Quick chat: the list opens, a line shows on the feed and closes the list, a team-mate's line shows, an enemy team's does not.

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


func _last(hud) -> String:
	var n: int = hud.feed_box.get_child_count()
	return str(hud.feed_box.get_child(n - 1).text) if n > 0 else ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	var hud = world.hud
	yield(_frames(10), "completed")
	hud.open_quickchat()
	yield(_frames(3), "completed")
	check(hud.shop.visible, "the quick chat list opens")
	hud._shop_chosen("ammo")
	yield(_frames(3), "completed")
	check(not hud.shop.visible and p.input_enabled, "choosing a line closes the list")
	check(_last(hud).find("I need ammo") >= 0, "the line appears on the feed (%s)" % _last(hud))
	world._on_chat("Follow me!", "Buddy", -1)
	check(_last(hud).find("Buddy: Follow me") >= 0, "a line from a player with no team shows")
	p.team = 3
	world._on_chat("secret", "Enemy", 5)
	check(_last(hud).find("secret") < 0, "another team's radio is not shown")
	world._on_chat("hi team", "Mate", 3)
	check(_last(hud).find("Mate: hi team") >= 0, "a team-mate's line is shown")
	check(InputMap.has_action("quick_chat"), "the quick chat key (J) is bound")
	print("QUICKCHAT_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

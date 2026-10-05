extends SceneTree
# The vending machine shop screen: cards with pictures and prices, buying, closing.
var failures := []


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _initialize() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var Items = load("res://scripts/Items.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.queue_free()
	p.max_health = 100000.0
	p.health = p.max_health
	var hud = world.hud
	var y: float = world.terrain.height_at(40.0, 60.0)
	p.global_transform.origin = Vector3(40.0, y + 1.0, 62.0)
	p.mode = p.Mode.GROUND
	var h = world.add_vending("healing", Vector2(44.0, 60.0), Vector2(44.0, 70.0))
	var w = world.add_vending("weapons", Vector2(36.0, 60.0), Vector2(36.0, 70.0))
	yield(_frames(20), "completed")
	for m in [h, w, world.add_vending("utility", Vector2(40.0, 50.0), Vector2(40.0, 70.0))]:
		for e in m.entries():
			check(ResourceLoader.exists("res://assets/icons/%s.png" % e.icon), "%s: %s has a picture" % [m.kind, e.name])
		check(m.entries().size() == 6, "%s machine shows six items" % m.kind)
	p.gold = 300
	h.interact(p)
	yield(_frames(3), "completed")
	check(hud.shop.visible and hud.shop.mode == "shop", "pressing interact opens the shop window")
	check(not p.input_enabled, "the character stands still while it is open")
	check(world._screen_open(), "the game knows a screen is open")
	check(hud.shop._buttons.size() == 6, "six cards are shown (%d)" % hud.shop._buttons.size())
	# click the third card (Medkit) as a player would
	var floor0 := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup"):
			floor0 += 1
	hud.shop._buttons[2].emit_signal("pressed")
	yield(_frames(3), "completed")
	var floor1 := 0
	var medkit := false
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup"):
			floor1 += 1
			if n.item.kind == "consumable" and n.item.id == "medkit":
				medkit = true
	check(p.gold == 220 and floor1 == floor0 + 1 and medkit, "clicking a card buys it for its price (gold %d)" % p.gold)
	check(hud.shop.visible and h.entries()[2].price == 90, "the window stays open and prices rise (%d)" % h.entries()[2].price)
	# too poor
	p.gold = 5
	hud.shop._buttons[5].emit_signal("pressed")
	yield(_frames(2), "completed")
	check(p.gold == 5, "not enough gold: nothing happens")
	# close with Escape
	var ev := InputEventKey.new()
	ev.scancode = KEY_ESCAPE
	ev.pressed = true
	hud.shop._input(ev)
	yield(_frames(2), "completed")
	check(not hud.shop.visible and p.input_enabled, "Escape closes it and gives control back")
	# a real Escape key event (through the whole input chain): closes the shop and does NOT open the pause menu
	w.interact(p)
	yield(_frames(3), "completed")
	var ev2 := InputEventKey.new()
	ev2.scancode = KEY_ESCAPE
	ev2.pressed = true
	Input.parse_input_event(ev2)
	for i in range(4):
		yield(self, "idle_frame")
	check(not hud.shop.visible and world.menu.state == "hidden" and not paused, "Escape closes the shop without opening the pause menu (shop %s, menu %s, paused %s)" % [hud.shop.visible, world.menu.state, paused])
	# weapons machine
	p.gold = 500
	w.interact(p)
	yield(_frames(3), "completed")
	hud.shop._buttons[2].emit_signal("pressed")
	yield(_frames(3), "completed")
	var got_ar := false
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup") and n.item.kind == "weapon" and n.item.id == "assault":
			got_ar = true
	check(got_ar, "the weapon machine sells an assault rifle from its window")
	hud.shop.close()
	print("SHOPUI_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

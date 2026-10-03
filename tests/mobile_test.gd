extends SceneTree
# Phone layout check: run at a phone-sized window (--resolution 844x390 --touch) with --shots to eyeball the HUD and menus.
#
#   xvfb-run -a godot3 --path . --resolution 844x390 -s res://tests/mobile_test.gd -- --no-capture --touch --shots=tests/out/phone

var failures := []
var shots_dir := "tests/out/phone"


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	call_deferred("_run")


func _shot(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("SHOT  ", name)


func _run() -> void:
	yield(self, "idle_frame")
	var controls = root.get_node("Controls")
	var Items = load("res://scripts/Items.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(4):
		yield(self, "idle_frame")
	var menu = world.menu
	check(controls.touch_mode, "touch mode is on")
	menu.show_title()
	yield(_shot("menu_lobby"), "completed")
	for t in ["locker", "profile", "party", "help", "settings_title"]:
		menu._on_button(t)
		yield(create_timer(0.3), "timeout")
		yield(_shot("menu_" + t), "completed")
		if t in ["help", "settings_title"]:
			menu._back_from_sub()
	menu._on_button("settings_title")
	menu._show_settings_page("controls")
	yield(_shot("menu_settings_controls"), "completed")
	menu._show_settings_page("display")
	yield(_shot("menu_settings_display"), "completed")
	menu._show_settings_page("comfort")
	yield(_shot("menu_settings_comfort"), "completed")
	menu._back_from_sub()
	menu._on_button("lobby")
	menu._on_button("play")
	for i in range(5):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	p.max_health = 100000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.mode = p.Mode.GROUND
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.give_weapon("charge_shotgun", 2, 30)
	p.pickup({"kind": "consumable", "id": "jetpack", "count": 1})
	p.pickup({"kind": "consumable", "id": "skateboard", "count": 1})
	p.pickup({"kind": "consumable", "id": "junk_rift", "count": 2})
	p.pickup({"kind": "consumable", "id": "shockwave_grenade", "count": 2})
	p.equip_sprite("fire")
	p.select_slot(1)
	for i in range(30):
		yield(self, "physics_frame")
	p.charge = 0.7
	yield(_shot("hud_items"), "completed")
	p.select_slot(2)
	yield(_shot("hud_slot2"), "completed")
	var hud = world.hud
	hud.open_inventory()
	yield(_shot("hud_inventory"), "completed")
	hud.close_inventory()
	p.select_slot(1)
	p.builder.set_active(true)
	yield(_shot("hud_build"), "completed")
	print("MOBILE_RESULT failures=%d" % failures.size())
	quit(1 if failures.size() > 0 else 0)

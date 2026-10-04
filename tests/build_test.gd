extends SceneTree
# Build mode test: toggle, ghost, place wall/floor/ramp/roof, material cost and tiers,
# duplicate / unaffordable refusal, climbing a ramp, and destroying a piece with bullets.
#
#   xvfb-run -a godot3 --path . -s res://tests/build_test.gd -- --no-capture --no-bus --skip-menu [--shots=DIR]

var failures := []
var shots_dir := ""


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
	_run()


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _shot(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	if shots_dir == "":
		return
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("SHOT  ", name)


var toasts := []


func _on_toast(text: String) -> void:
	toasts.append(text)


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss:
			f.queue_free()
	p.max_health = 1000000.0
	p.health = p.max_health
	var audio = root.get_node("Audio")
	var b = p.builder
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(0.0, y + 1.0, 30.0)
	p.rotation.y = PI / 2.0
	p.pitch = -0.35
	p.head.rotation.x = -0.35
	p.velocity = Vector3.ZERO
	p.materials = {"wood": 100, "stone": 100, "metal": 0}
	yield(_frames(60), "completed")
	var wait_n := 0
	while p.mode != 0 and wait_n < 600:          # a heavy frame (100 fighters) can delay the landing
		yield(_frames(1), "completed")
		wait_n += 1

	check(not b.active, "build mode starts off")
	Input.action_press("build_toggle")
	yield(_frames(3), "completed")
	Input.action_release("build_toggle")
	yield(_frames(3), "completed")
	check(b.active, "pressing Q enters build mode")
	check(b._ghost.visible, "a placement ghost is shown")
	check(audio.count_of("build_toggle") > 0, "toggle sound plays")

	# Z X C V pick a piece (and enter build mode), the same key again leaves it, number keys go back to items
	Input.action_press("build_toggle")
	yield(_frames(3), "completed")
	Input.action_release("build_toggle")
	yield(_frames(3), "completed")
	check(not b.active, "Q again leaves build mode")
	Input.action_press("build_ramp")
	yield(_frames(3), "completed")
	Input.action_release("build_ramp")
	yield(_frames(3), "completed")
	check(b.active and b.piece == 2, "C enters build mode with the ramp")
	Input.action_press("build_roof")
	yield(_frames(3), "completed")
	Input.action_release("build_roof")
	yield(_frames(3), "completed")
	check(b.active and b.piece == 3, "V switches to the roof")
	Input.action_press("build_roof")
	yield(_frames(3), "completed")
	Input.action_release("build_roof")
	yield(_frames(3), "completed")
	check(not b.active, "pressing the chosen piece key again leaves build mode")
	Input.action_press("build_toggle")
	yield(_frames(3), "completed")
	Input.action_release("build_toggle")
	yield(_frames(3), "completed")
	check(b.active, "Q enters build mode again")
	Input.action_press("pickaxe")
	yield(_frames(3), "completed")
	Input.action_release("pickaxe")
	yield(_frames(3), "completed")
	check(not b.active and p.selected == 0, "F leaves build mode and equips the pickaxe")
	Input.action_press("build_toggle")
	yield(_frames(3), "completed")
	Input.action_release("build_toggle")
	yield(_frames(3), "completed")

	# with no materials a click is refused and the HUD says why
	p.connect("picked_up", self, "_on_toast")
	var had: Dictionary = p.materials.duplicate()
	p.materials = {"wood": 0, "stone": 0, "metal": 0}
	b.set_piece(1)
	yield(self, "idle_frame")
	check(not b.place(), "placing without materials is refused")
	check(toasts.size() > 0 and "WOOD" in toasts[toasts.size() - 1], "the refusal explains what is missing (%s)" % (toasts[toasts.size() - 1] if toasts.size() > 0 else "no message"))
	p.materials = had

	# floor
	b.set_piece(1)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	check(b._target.valid and b._target.kind == "floor", "the ghost is valid for a floor (%s)" % str(b._target.get("kind")))
	yield(_shot("build_ghost"), "completed")
	check(b.place(), "placing a floor works")
	check(world.build_slots.size() == 1 and p.materials["wood"] == 90, "a floor costs 10 wood (wood %d)" % p.materials["wood"])
	check(audio.count_of("build_place") > 0, "placement sound plays")
	yield(_frames(4), "completed")
	check(not b._target.valid, "the same slot is now blocked")
	check(not b.place() and world.build_slots.size() == 1 and p.materials["wood"] == 90, "placing twice in one slot is refused")

	# wall in stone
	b.set_piece(0)
	b.cycle_material(1)
	check(b.material == "stone", "scrolling selects the next material")
	yield(_frames(4), "completed")
	check(b.place(), "placing a stone wall works")
	var wall = null
	for k in world.build_slots.keys():
		if k.begins_with("wall"):
			wall = world.build_slots[k]
	check(wall != null and wall.health == 300.0 and p.materials["stone"] == 90, "stone walls are tougher (hp %.0f)" % (wall.health if wall else -1.0))

	# running out of a material routes straight to the next one that has enough
	var saved: Dictionary = p.materials.duplicate()
	b.material = "wood"
	p.materials = {"wood": 0, "stone": 30, "metal": 50}
	b.auto_route()
	check(b.material == "stone", "out of wood -> stone (%s)" % b.material)
	p.materials = {"wood": 0, "stone": 5, "metal": 50}
	b.auto_route()
	check(b.material == "metal", "too little stone -> metal (%s)" % b.material)
	p.materials = {"wood": 0, "stone": 0, "metal": 0}
	b.auto_route()
	check(b.material == "metal", "with nothing at all the selection stays put")
	b.material = "wood"
	p.materials = {"wood": 10, "stone": 100, "metal": 100}
	yield(_frames(4), "completed")
	b.set_piece(1)
	b.place()
	check(b.material == "stone" and p.materials.wood == 0 or not b._target.valid, "spending the last wood moves the selection on (%s)" % b.material)
	p.materials = saved

	# roof
	b.material = "wood"
	b.set_piece(3)
	yield(_frames(4), "completed")
	check(b.place(), "placing a roof works")

	# ramp you can climb
	b.set_active(false)
	var cx := 12.0
	var cz := 30.0
	var ramp = world.spawn_build("ramp", "wood", "test_ramp", Vector3(cx, y + 1.5, cz), 0.0)
	yield(_frames(10), "completed")
	p.global_transform.origin = Vector3(cx, y + 0.5, cz + 3.4)
	p.rotation.y = 0.0                        # facing -Z, up the ramp
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	Input.action_press("move_forward")
	var top_y: float = p.global_transform.origin.y
	for i in range(150):
		yield(self, "physics_frame")
		top_y = max(top_y, p.global_transform.origin.y)
	Input.action_release("move_forward")
	check(top_y > y + 2.0, "walking up a ramp gains height (%.1f m above the street)" % (top_y - y))
	yield(_shot("build_ramp"), "completed")

	# shoot a wall apart
	p.materials["wood"] = 50
	p.global_transform.origin = Vector3(-30.0, y + 1.0, 36.0)
	p.rotation.y = 3.0 * PI / 2.0                          # facing +X
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	var tgt = world.spawn_build("wall", "wood", "test_wall", Vector3(-24.0, y + 1.5, 36.65), PI / 2.0)
	yield(_frames(10), "completed")
	p.give_weapon("assault", 2, 300)
	var slots_before: int = world.build_slots.size()
	var shots := 0
	while is_instance_valid(tgt) and not tgt.is_dead and shots < 80:
		p._fire_cd = 0.0
		p.fire_at_crosshair()
		shots += 1
		yield(self, "physics_frame")
		if p.get_ammo() == 0:
			p.start_reload()
			yield(_frames(130), "completed")
	check(not is_instance_valid(tgt) or tgt.is_dead, "bullets destroy a wooden wall (%d shots)" % shots)
	check(world.build_slots.size() == slots_before - 1, "a destroyed piece frees its slot")
	check(audio.count_of("build_break") > 0, "breaking sound plays")

	# the real input path: the fire action (left click) places the chosen piece
	var controls = root.get_node("Controls")
	controls.touch_mode = true          # lets the player act without a captured mouse
	p.materials = {"wood": 100, "stone": 0, "metal": 0}
	p.pitch = -0.35
	p.head.rotation.x = -0.35
	p.rotation.y += 1.0                 # face fresh ground
	p.select_slot(0)
	b.set_active(true)
	b.set_piece(1)
	b.material = "wood"
	yield(_frames(10), "completed")
	var before: int = world.build_slots.size()
	Input.action_press("fire")
	yield(_frames(4), "completed")
	Input.action_release("fire")
	yield(_frames(4), "completed")
	check(world.build_slots.size() == before + 1 and p.materials.wood == 90, "a left click places the piece and spends 10 wood (%d pieces, %d wood)" % [world.build_slots.size() - before, p.materials.wood])
	controls.touch_mode = false

	print("BUILD_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

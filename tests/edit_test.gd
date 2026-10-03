extends SceneTree
# Build editing: look at a wall, open the editor, cut a door, walk through it; floors get holes; bad masks are refused;
# cancel leaves the piece alone; ramps and roofs are not editable.
#
#   xvfb-run -a godot3 --path . -s res://tests/edit_test.gd -- --no-capture --no-bus --skip-menu [--shots=DIR]

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


func _shape_count(piece) -> int:
	var n := 0
	for c in piece.get_children():
		if c is CollisionShape and not c.disabled:
			n += 1
	return n


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.queue_free()
	p.max_health = 1000000.0
	p.health = p.max_health
	var X := 24.0                       # open ground east of the town (houses block the lane at x = 0)
	var ZW := 44.0
	var ZP := 50.0
	var y: float = world.terrain.height_at(X, ZP)
	p.global_transform.origin = Vector3(X, y + 1.0, ZP)
	p.rotation.y = 0.0
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	p.velocity = Vector3.ZERO
	var hud = world.hud
	var yw: float = world.terrain.height_at(X, ZW)                # the ground under the wall (it slopes a little)
	var aim_pitch: float = atan2((yw + 1.5) - (y + 1.6), ZP - ZW)
	var wall = world.spawn_build("wall", "wood", "edit:wall:1", Vector3(X, yw + 1.5, ZW), 0.0)
	yield(_frames(40), "completed")

	# a solid wall blocks the way
	Input.action_press("move_forward")
	yield(_frames(100), "completed")
	Input.action_release("move_forward")
	check(p.global_transform.origin.z > ZW + 0.2, "an unedited wall blocks you (z=%.1f)" % p.global_transform.origin.z)

	# looking at it and opening the editor
	p.global_transform.origin = Vector3(X, y + 1.0, ZP)
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	p.pitch = aim_pitch
	p.head.rotation.x = aim_pitch
	yield(_frames(5), "completed")
	check(p.builder.looked_at_piece() == wall, "the builder finds the wall under the crosshair")
	hud.try_edit()
	check(hud.editor.visible and hud.editor.aim_mode and p.input_enabled and root.get_node("Controls").edit_aim, "G opens the in-world editor and you can still look around")
	yield(_frames(4), "completed")
	var aimed: int = hud.editor.aim_cell()
	check(aimed == 4, "the crosshair is on the middle tile of the wall (tile %d)" % aimed)
	yield(_shot("edit_grid"), "completed")
	# click the tile under the crosshair, then drag down onto the tile below it
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	Input.action_press("fire")
	hud.editor._input(click)
	check(not hud.editor.mask[aimed], "clicking a tile cuts it away")
	Input.action_release("fire")
	hud.editor._painting = false
	hud.editor.mask[4] = false
	hud.editor.mask[1] = false
	hud.editor.mask[7] = true
	var rs := InputEventMouseButton.new()
	rs.button_index = BUTTON_RIGHT
	rs.pressed = true
	hud.editor._input(rs)
	check(hud.editor.mask == [true, true, true, true, true, true, true, true, true], "Reset Edit restores every tile")
	hud.editor._preset("DOOR")
	check(not hud.editor.mask[1] and not hud.editor.mask[4] and hud.editor.mask[7], "(door shape: the two middle-column cells)")
	hud.editor.confirm()
	check(not hud.editor.visible and p.input_enabled and not root.get_node("Controls").edit_aim, "confirming closes the editor")
	check(not wall.is_full() and _shape_count(wall) == 7 and not wall.get_mask()[1], "the wall now has a door-shaped hole (7 cells left)")
	yield(_shot("edit_door"), "completed")

	# the opening is walkable
	Input.action_press("move_forward")
	yield(_frames(150), "completed")
	Input.action_release("move_forward")
	check(p.global_transform.origin.z < ZW - 3.0, "you can walk through the door (z=%.1f)" % p.global_transform.origin.z)

	# damaged pieces still flash / break normally
	wall.take_damage(10.0, null)
	check(wall.health < 150.0 and not wall.is_dead, "an edited wall takes damage")

	# cancel leaves it alone
	p.global_transform.origin = Vector3(X, y + 1.0, ZP)
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	wall.apply_mask([true, true, true, true, true, true, true, true, true])
	p.head.rotation.x = aim_pitch
	yield(_frames(4), "completed")
	var before: Array = wall.get_mask()
	hud.try_edit()
	check(hud.editor.visible, "G opens the editor again")
	hud.editor.mask[0] = false
	hud.editor.mask[2] = false
	hud.editor.cancel()
	check(wall.get_mask() == before and p.input_enabled, "cancel leaves the wall unchanged")

	# reset and bad masks
	check(not wall.apply_mask([false, false, false, false, false, false, false, false, false]), "a mask with every cell removed is refused")
	check(wall.apply_mask([true, true, true, true, true, true, true, true, true]) and wall.is_full() and _shape_count(wall) == 1, "an all-true mask restores the whole wall")

	# floors get holes
	var floor_piece = world.spawn_build("floor", "stone", "edit:floor:1", Vector3(X + 12.0, y + 0.9, ZW), 0.0)
	yield(_frames(10), "completed")
	check(floor_piece.editable() and floor_piece.apply_mask([true, true, true, true, false, true, true, true, true]) and _shape_count(floor_piece) == 8, "a floor can have a hole (8 cells)")

	# ramps and roofs cannot be edited
	var ramp = world.spawn_build("ramp", "wood", "edit:ramp:1", Vector3(X - 12.0, y + 1.5, ZW), 0.0)
	var roof = world.spawn_build("roof", "wood", "edit:roof:1", Vector3(X - 20.0, y + 1.5, ZW), 0.0)
	check(not ramp.editable() and not ramp.apply_mask([true, true, true, true, false, true, true, true, true]), "ramps are not editable")
	check(not roof.editable(), "roofs are not editable")

	print("EDIT_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

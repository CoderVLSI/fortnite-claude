extends SceneTree
# Inventory: a full inventory swaps the picked-up item for the one in hand (or the last one held when the pickaxe is
# out), stacks still merge, X / Drop puts an item on the ground, and the Tab inventory screen opens, equips on click,
# drops, and closes.
#
#   xvfb-run -a godot3 --path . -s res://tests/inventory_test.gd -- --no-capture --no-bus --skip-menu [--shots=DIR]

const Items = preload("res://scripts/Items.gd")

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


func _floor_items(world) -> Array:
	var out := []
	for n in get_nodes_in_group("interactable"):
		if is_instance_valid(n) and n.has_method("setup") and n.get("item") != null and not n.item.empty():
			out.append(n.item)
	return out


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
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(0.0, y + 1.0, 30.0)
	p.velocity = Vector3.ZERO
	yield(_frames(40), "completed")
	var hud = world.hud

	# a full inventory: four different guns
	p.slots[1] = Items.make_weapon("assault", 1)
	p.slots[2] = Items.make_weapon("smg", 0)
	p.slots[3] = Items.make_weapon("shotgun", 2)
	p.slots[4] = Items.make_consumable("bandage", 3)
	p.select_slot(2)
	var spot: Vector3 = p.global_transform.origin + Vector3(0, 0.3, -2.0)

	# 1. holding the SMG: picking up a rare pistol replaces it and drops the SMG
	var pistol := Items.make_weapon("pistol", 2)
	var res: Dictionary = p.pickup(pistol)
	check(res.ok and p.slots[2].id == "pistol" and p.selected == 2, "full inventory: the new weapon replaces the one in hand (%s)" % res.text)
	check(res.dropped != null and res.dropped.id == "smg", "the replaced weapon is returned to be dropped")
	check(p.slots[1].id == "assault" and p.slots[3].id == "shotgun", "the other slots are untouched")

	# 2. through the real LootItem path: the old item appears on the floor
	var loot = world.spawn_item(Items.make_weapon("sniper", 3), spot)
	yield(_frames(3), "completed")
	var before := _floor_items(world).size()
	loot.interact(p)
	yield(_frames(3), "completed")
	check(p.slots[2].id == "sniper" and p.selected == 2, "pressing E on a floor weapon swaps it into the equipped slot")
	var dropped := false
	for it in _floor_items(world):
		if it.kind == "weapon" and it.id == "pistol":
			dropped = true
	check(dropped, "the swapped-out pistol lies on the ground")

	# 3. pickaxe out: the swap goes to the last item slot and equips the new gun
	p.select_slot(0)
	yield(_frames(3), "completed")
	res = p.pickup(Items.make_weapon("assault", 4))
	check(res.ok and p.slots[2].id == "assault" and p.selected == 2, "pickaxe out: the last-held slot is replaced and equipped (slot %d)" % p.selected)

	# 4. consumables swap too, but a matching stack merges instead
	p.select_slot(3)
	res = p.pickup(Items.make_consumable("medkit", 1))
	check(res.ok and p.slots[3].kind == "consumable" and p.slots[3].id == "medkit", "a full inventory swaps in a medkit for the item in hand")
	check(res.dropped != null and res.dropped.id == "shotgun", "the shotgun it replaced is dropped")
	res = p.pickup(Items.make_consumable("bandage", 2))
	check(res.ok and p.slots[4].count == 5 and res.dropped == null, "bandages stack onto the existing stack (%d)" % p.slots[4].count)

	# 5. drop with X: the pickaxe stays, anything else goes to the floor and the pickaxe comes out
	p.select_slot(1)
	var floor_before := _floor_items(world).size()
	check(not p.drop_slot(0), "the pickaxe cannot be dropped")
	check(p.drop_slot(1), "drop_slot drops the equipped item")
	yield(_frames(3), "completed")
	check(p.slots[1] == null and p.selected == 0, "the slot empties and the pickaxe is equipped")
	check(_floor_items(world).size() == floor_before + 1, "the dropped item is on the ground")

	# 6. the Tab inventory screen
	p.slots[1] = Items.make_weapon("smg", 3)
	yield(self, "idle_frame")
	Input.action_press("inventory")
	yield(self, "idle_frame")
	Input.action_release("inventory")
	yield(_frames(4), "completed")
	check(hud.inventory.visible and not p.input_enabled, "Tab opens the inventory and freezes player input")
	yield(_shot("inventory_screen"), "completed")
	var L: Dictionary = hud.inventory._layout()
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	click.position = L.slots[3].position + Vector2(40, 40)
	hud.inventory._gui_input(click)
	check(p.selected == 3, "clicking an equipment slot equips it")
	var key := InputEventKey.new()
	key.scancode = KEY_X
	key.pressed = true
	hud.inventory._input(key)
	yield(_frames(3), "completed")
	check(p.slots[3] == null, "X in the inventory drops the highlighted item")
	hud.inventory._gui_input(_back_click(L))
	yield(_frames(3), "completed")
	check(not hud.inventory.visible and p.input_enabled, "Back closes it and gives control back")
	yield(self, "idle_frame")
	Input.action_press("inventory")
	yield(self, "idle_frame")
	Input.action_release("inventory")
	yield(_frames(4), "completed")
	check(hud.inventory.visible, "Tab reopens it")
	yield(self, "idle_frame")
	Input.action_press("inventory")
	yield(self, "idle_frame")
	Input.action_release("inventory")
	yield(_frames(4), "completed")
	check(not hud.inventory.visible, "Tab again closes it")

	print("INVENTORY_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)


func _back_click(L: Dictionary) -> InputEventMouseButton:
	var c := InputEventMouseButton.new()
	c.button_index = BUTTON_LEFT
	c.pressed = true
	c.position = L.back.position + Vector2(20, 20)
	return c

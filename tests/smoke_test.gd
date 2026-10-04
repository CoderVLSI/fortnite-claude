extends SceneTree
# Headless gameplay test: boots the real game (ground start, no bus) and checks movement,
# weapons, inventory, pickups, consumables, harvesting, chests, supply drop, bots, storm and
# touch input, then takes screenshots.
#
#   xvfb-run -a godot3 --path . -s res://tests/smoke_test.gd -- --no-capture --no-bus --skip-menu --shots=/tmp/shots
#
# Extra args after "--": --mobile (mobile quality profile). See tests/bus_test.gd for the bus flow.

const Items = preload("res://scripts/Items.gd")

var failures := []
var shots_dir := ""
var controls
var hits := []


var harvest_log := []


func _on_harvested(_pos, fraction, _kind, _label, _id) -> void:
	harvest_log.append(fraction)


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


func _wait_idle(n: int) -> void:
	for i in range(n):
		yield(self, "idle_frame")


# Synthetic touches must be in window pixels (like a real device); the engine then
# maps them through the stretch transform into the UI's virtual coordinates.
func _win(v: Vector2) -> Vector2:
	return root.get_final_transform().xform(v)


func _win_rel(v: Vector2) -> Vector2:
	return root.get_final_transform().basis_xform(v)


func _shot(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	if shots_dir == "":
		return
	var img := root.get_texture().get_data()
	img.flip_y()
	var path := "%s/%s.png" % [shots_dir, name]
	img.save_png(path)
	print("SHOT  ", path, "  ", img.get_width(), "x", img.get_height())


func _on_player_hit(hit_target, _killed, _headshot) -> void:
	hits.append(hit_target)


func _loot_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for i in get_nodes_in_group("interactable"):
		if i.has_method("setup") and i.global_transform.origin.distance_to(pos) < radius:
			n += 1
	return n


func _count_loot() -> int:
	var n := 0
	for i in get_nodes_in_group("interactable"):
		if i.has_method("setup"):      # LootItem
			n += 1
	return n


func _run() -> void:
	yield(self, "idle_frame")
	controls = root.get_node("Controls")
	var packed = load("res://scenes/Main.tscn")
	check(packed != null, "Main.tscn loads")
	var world = packed.instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")

	var p = world.player
	check(world.terrain != null and p != null, "world built with terrain and player")
	check(get_nodes_in_group("fighters").size() == world.profile.bots + 1 + world.bosses.size(), "all %d fighters spawned (bots + player + boss)" % (world.profile.bots + 1 + world.bosses.size()))
	check(world.building_positions.size() >= 10, "buildings placed (%d)" % world.building_positions.size())
	check(get_nodes_in_group("interactable").size() > 40, "chests and floor loot placed (%d)" % get_nodes_in_group("interactable").size())
	p.max_health = 1000000.0   # keep bots from killing the test player
	p.health = p.max_health

	# start every run from the same flat spot in town (random spawns can land on a slope)
	var town_y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(0.0, town_y + 1.0, 30.0)
	p.rotation.y = PI / 2.0        # facing -X, a clear 40 m street
	p.velocity = Vector3.ZERO
	yield(_frames(150), "completed")
	var o: Vector3 = p.global_transform.origin
	var ground: float = world.terrain.height_at(o.x, o.z)
	check(abs(o.y - ground) < 1.0, "player stands on the terrain (y=%.2f ground=%.2f)" % [o.y, ground])

	# --- starting inventory: pickaxe only
	var filled := 0
	for i in range(p.slots.size()):
		if p.slots[i] != null:
			filled += 1
	check(p.slots.size() == 6 and filled == 1 and p.slots[0].kind == "pickaxe" and p.selected == 0, "player starts with only a pickaxe (pickaxe + 5 slots)")
	check(p.get_ammo() == 0 and p.get_reserve() == 0, "pickaxe has no ammo")

	# --- movement
	var start: Vector3 = p.global_transform.origin
	Input.action_press("move_forward")
	yield(_frames(60), "completed")
	Input.action_release("move_forward")
	check(start.distance_to(p.global_transform.origin) > 2.0, "player walks forward (%.1f m)" % start.distance_to(p.global_transform.origin))

	# --- weapons: equip a rare assault rifle and shoot a bot in the crosshair
	p.give_weapon("assault", 2, 120)
	check(p.selected_item() != null and p.selected_item().id == "assault" and p.selected == 1, "weapon goes to slot 2 and is auto-selected")
	check(p.get_ammo() == 30 and p.get_reserve() == 120, "rifle has a full magazine and reserve ammo")
	var target = null
	for f in get_nodes_in_group("fighters"):            # any bot that is still alive
		if f != p and not f.is_dead and not f.is_boss:
			target = f
			break
	target.set_physics_process(false)
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	var tpos := Vector3.ZERO
	for turn in range(16):   # turn until the 14 m line in front of the crosshair is clear
		var b: Basis = p.global_transform.basis
		tpos = p.global_transform.origin + (-b.z) * 14.0 + b.x * p.SHOULDER_OFFSET.x
		tpos.y = world.terrain.height_at(tpos.x, tpos.z) + 0.05
		var from: Vector3 = p.global_transform.origin + b.x * p.SHOULDER_OFFSET.x + Vector3(0, 1.55, 0)
		if p.get_world().direct_space_state.intersect_ray(from, tpos + Vector3(0, 1.4, 0), [p, target], 1).empty():
			break
		p.rotation.y += TAU / 16.0
	target.global_transform.origin = tpos
	target.health = 100.0
	target.shield = 0.0
	yield(_frames(3), "completed")
	p._fire_cd = 0.0
	p.connect("hit_landed", self, "_on_player_hit")
	check(p.fire_at_crosshair(), "player can fire")
	var aim: Array = p.aim_origin_and_dir()
	var dbg: Dictionary = p.get_world().direct_space_state.intersect_ray(aim[0], aim[0] + aim[1] * 40.0, [p], 3)
	print("DEBUG aim_from=", aim[0], " dir=", aim[1], " target=", target.global_transform.origin, " mode=", target.mode, " layer=", target.collision_layer,
		" ray_hit=", dbg.collider.name if dbg.has("collider") else "none", " at ", dbg.position if dbg.has("position") else "-", " weapon=", p.selected_item(), " range=", p.weapon_range)
	check(hits.size() > 0, "shot damages a fighter (hit %s, target health %.0f)" % [hits[0].display_name if hits.size() > 0 else "nobody", target.health])
	var mag_before: int = p.get_ammo()
	p._fire_cd = 0.0
	p.fire_at_crosshair()
	check(p.get_ammo() == mag_before - 1, "magazine ammo is consumed")
	p.start_reload()
	yield(_frames(160), "completed")
	check(p.get_ammo() == 30, "reload refills the magazine from reserve")

	# --- kill: credited, and the bot's weapon + ammo drop as floor loot
	var kill_target = null
	for f in get_nodes_in_group("fighters"):          # a bot that is still alive (others may have killed Bot0)
		if f != p and not f.is_dead and not f.is_boss:
			kill_target = f
			break
	check(kill_target != null, "a living bot is available for the kill test")
	kill_target.set_physics_process(false)
	kill_target.health = 100.0
	kill_target.shield = 0.0
	var kills_before: int = p.kills
	var loot_before := _count_loot()
	kill_target.take_damage(1000.0, p)
	yield(_frames(2), "completed")
	target = kill_target
	check(target.is_dead and p.kills == kills_before + 1, "kill is credited to the player")
	check(_count_loot() >= loot_before + 2, "a dead bot drops its weapon and ammo")

	# --- floor loot: weapon pickup with interact, and weapon swap when full
	var here: Vector3 = p.global_transform.origin
	world.spawn_item(Items.make_weapon("shotgun", 3), here + Vector3(1.2, 0.5, 0))
	yield(_frames(12), "completed")
	check(p.interact_target != null, "nearby floor loot becomes the interact target")
	Input.action_press("interact")
	yield(_frames(4), "completed")
	Input.action_release("interact")
	var has_shotgun := false
	for it in p.slots:
		if it != null and it.kind == "weapon" and it.id == "shotgun":
			has_shotgun = true
	check(has_shotgun, "pressing interact picks up the weapon")
	# fill the remaining slots, then pick up another weapon -> swaps with the selected weapon
	p.pickup(Items.make_weapon("smg", 1))
	p.pickup(Items.make_weapon("pistol", 0))
	p.pickup(Items.make_weapon("assault", 0))
	var full := true
	for i in range(1, p.slots.size()):
		if p.slots[i] == null:
			full = false
	check(full, "all five item slots can be filled")
	p.select_slot(1)
	var res: Dictionary = p.pickup(Items.make_consumable("bandage", 3))
	check(res.ok and p.slots[1].kind == "consumable" and res.dropped != null, "full inventory swaps a new consumable stack for the item in hand")
	p.select_slot(3)
	var swapped: Dictionary = p.pickup(Items.make_weapon("sniper", 4))
	check(swapped.ok and swapped.dropped != null and p.slots[3].id == "sniper", "picking up a weapon with full slots swaps the selected one")

	# --- ammo auto pickup
	var light_before: int = p.reserves["light"]
	world.spawn_item(Items.make_ammo("light", 24), p.global_transform.origin + Vector3(0.5, 0.2, 0.5))
	yield(_frames(20), "completed")
	check(p.reserves["light"] == light_before + 24, "ammo is collected by walking over it")

	# --- consumables: free a slot, then use shield potion / bandage
	p.slots[4] = Items.make_consumable("shield_potion", 2)
	p.select_slot(4)
	p.shield = 0.0
	check(p.can_use_selected(), "shield potion is usable when shield is low")
	for i in range(280):
		p.use_selected(1.0 / 60.0)
	check(abs(p.shield - 50.0) < 0.1 and p.slots[4].count == 1, "shield potion adds 50 shield and uses up one (shield %.0f)" % p.shield)
	p.shield = 100.0
	check(not p.can_use_selected(), "shield potion is refused at full shield")
	p.slots[4] = Items.make_consumable("bandage", 2)
	p._apply_selected()
	p.health = 50.0
	p.max_health = 100.0
	for i in range(190):
		p.use_selected(1.0 / 60.0)
	check(abs(p.health - 65.0) < 0.1, "bandage heals 15 (health %.0f)" % p.health)
	p.health = 70.0
	for i in range(190):
		p.use_selected(1.0 / 60.0)
	check(abs(p.health - 75.0) < 0.1, "bandage stops at 75 health (health %.0f)" % p.health)
	check(p.slots[4] == null and p.selected == 0, "empty stack frees the slot and falls back to the pickaxe")
	p.max_health = 1000000.0
	p.health = p.max_health

	# --- pickaxe harvesting: trees give wood and get felled after 5 hits
	var trees: Dictionary = world._props["TreeColliders"]
	var tree_idx := 0
	for ti in range(trees.body.get_child_count()):       # a tree on gentle ground with no neighbour in the way
		var tp: Vector3 = trees.body.get_child(ti).translation
		var flat: bool = abs(world.terrain.height_at(tp.x + 2.0, tp.z) - world.terrain.height_at(tp.x - 2.0, tp.z)) < 0.8 and abs(world.terrain.height_at(tp.x, tp.z + 3.0) - world.terrain.height_at(tp.x, tp.z - 3.0)) < 1.2
		var clear := true
		for tj in range(trees.body.get_child_count()):
			if tj != ti and tj < ti + 40 and tj > ti - 40 and Vector2(trees.body.get_child(tj).translation.x - tp.x, trees.body.get_child(tj).translation.z - tp.z).length() < 4.5:
				clear = false
		if flat and clear:
			tree_idx = ti
			break
	var tree_pos: Vector3 = trees.body.get_child(tree_idx).translation
	var wood_before: int = p.materials["wood"]
	p.select_slot(0)
	p.global_transform.origin = Vector3(tree_pos.x, world.terrain.height_at(tree_pos.x, tree_pos.z) + 1.0, tree_pos.z + 2.4)
	p.rotation.y = 0.0     # looking toward -Z, at the tree
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	p.velocity = Vector3.ZERO
	var b2: Basis = p.global_transform.basis
	p.global_transform.origin += b2.x * -p.SHOULDER_OFFSET.x    # camera ray is offset to the right: shift so it lines up
	yield(_frames(6), "completed")
	p.connect("harvested", self, "_on_harvested")
	harvest_log.clear()
	for i in range(5):
		p._fire_cd = 0.0
		p.fire_at_crosshair()
		yield(_frames(2), "completed")
	check(harvest_log.size() >= 3 and harvest_log.size() <= 5, "each pickaxe hit on a tree reports its health (%d reports)" % harvest_log.size())
	if harvest_log.size() == 5:
		check(abs(harvest_log[0] - 0.8) < 0.01 and harvest_log[4] == 0.0, "the tree's bar drains 80%% -> 0%% (first %.2f, last %.2f)" % [harvest_log[0], harvest_log[4]])
	check(world.hud.hv_root.visible or world.hud._hv_t > 0.0, "the HUD shows the harvest health bar")
	check(p.materials["wood"] > wood_before, "pickaxe harvests wood from a tree (+%d)" % (p.materials["wood"] - wood_before))
	check(trees.hits.get(tree_idx, 0) >= 5, "tree is felled after repeated hits")

	# --- chests: each variety opens and drops its contents
	var spots := [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 5)]
	var kinds := ["chest", "ammo_box", "supply"]
	var expected := [5, 3, 11]       # weapon+ammo+consumable+materials+gold; 2 ammo+materials; 2 guns+3 heals/grenades+2 ammo+3 materials
	for i in range(3):
		var pos: Vector3 = p.global_transform.origin + spots[i]
		var chest = world._add_chest(kinds[i], Vector3(pos.x, world.terrain.height_at(pos.x, pos.z), pos.z), 0.0)
		yield(_frames(2), "completed")
		var cpos: Vector3 = chest.global_transform.origin
		var before := _loot_near(cpos, 6.0)
		check(chest.can_interact(), "%s can be opened" % kinds[i])
		chest.interact(p)
		yield(_frames(2), "completed")
		var dropped := _loot_near(cpos, 6.0) - before
		check(chest.opened and dropped == expected[i], "%s drops %d items (%d)" % [kinds[i], expected[i], dropped])

	# --- supply drop falls then becomes openable
	var drop = world._add_chest("supply", p.global_transform.origin + Vector3(10, 0, 10), 0.0)
	yield(_frames(2), "completed")
	drop.start_fall(6.0, drop.translation.y)
	check(drop.falling and not drop.can_interact(), "supply drop floats down and can't be opened mid-air")
	yield(_wait_idle(2), "completed")
	for i in range(160):
		drop._process(1.0 / 60.0)
	check(not drop.falling and drop.can_interact(), "supply drop lands and becomes openable")

	# --- storm damage
	var victim = null
	for f in get_nodes_in_group("fighters"):
		if f != p and f != target and not f.is_dead:
			victim = f
			break
	check(victim != null, "found a living bot for the storm test")
	victim.set_physics_process(false)
	victim.health = 100.0
	victim.shield = 0.0
	var s = world.storm
	s.center = Vector2(5000, 5000)
	s.radius = 1.0
	s.damage_per_second = 5.0
	s._tick = 1.0
	yield(_wait_idle(3), "completed")
	check(victim.health <= 95.0, "storm hurts fighters outside the circle (health %.0f)" % victim.health)
	s.center = Vector2.ZERO
	s.radius = 300.0

	# --- bots move on their own and are armed
	var bots := []
	var starts := []
	var armed := 0
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_dead and f.is_physics_processing():
			bots.append(f)
			starts.append(f.global_transform.origin)
			for it in f.slots:            # carries a gun (a bot mid-heal may have something else in hand)
				if it != null and it.kind == "weapon":
					armed += 1
					break
	check(armed == bots.size(), "every bot carries a weapon (%d)" % armed)
	yield(_frames(240), "completed")
	var moved := 0
	for i in range(bots.size()):
		if is_instance_valid(bots[i]) and starts[i].distance_to(bots[i].global_transform.origin) > 2.0:
			moved += 1
	check(moved >= bots.size() / 2, "bots wander/fight on their own (%d of %d moved)" % [moved, bots.size()])

	# --- touch controls feed the same actions, hotbar taps select slots, interact button appears
	controls.set_touch_mode(true)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var touch = world.hud.touch
	check(touch.visible, "touch controls appear in touch mode")
	var hb = world.hud.hotbar
	p.select_slot(0)
	var slot_center: Vector2 = hb.rect_global_position + hb.slot_rect(2).position + Vector2(30, 30)
	var tap := InputEventScreenTouch.new()
	tap.index = 5
	tap.pressed = true
	tap.position = _win(slot_center)
	Input.parse_input_event(tap)
	yield(_wait_idle(2), "completed")
	var tap_up := InputEventScreenTouch.new()
	tap_up.index = 5
	tap_up.pressed = false
	tap_up.position = tap.position
	Input.parse_input_event(tap_up)
	check(p.selected == 2, "tapping a hotbar slot selects it")

	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = _win(Vector2(150, touch.rect_size.y - 150))
	Input.parse_input_event(t)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = _win(Vector2(150, touch.rect_size.y - 150 - 90))
	d.relative = _win_rel(Vector2(0, -90))
	Input.parse_input_event(d)
	yield(_wait_idle(2), "completed")
	check(Input.get_action_strength("move_forward") > 0.5, "virtual joystick drives move_forward")
	var fire_t := InputEventScreenTouch.new()
	fire_t.index = 1
	fire_t.pressed = true
	fire_t.position = _win(touch._buttons["fire"]["center"])
	Input.parse_input_event(fire_t)
	yield(_wait_idle(2), "completed")
	check(Input.is_action_pressed("fire"), "on-screen fire button presses fire")
	var yaw_before: float = p.rotation.y
	var look := InputEventScreenTouch.new()
	look.index = 2
	look.pressed = true
	look.position = _win(Vector2(touch.rect_size.x * 0.6, touch.rect_size.y * 0.3))
	Input.parse_input_event(look)
	var ld := InputEventScreenDrag.new()
	ld.index = 2
	ld.position = look.position + _win_rel(Vector2(100, 0))
	ld.relative = _win_rel(Vector2(100, 0))
	Input.parse_input_event(ld)
	yield(_frames(3), "completed")
	check(abs(p.rotation.y - yaw_before) > 0.05, "dragging the right side turns the camera")
	for idx in [0, 1, 2]:
		var up := InputEventScreenTouch.new()
		up.index = idx
		up.pressed = false
		Input.parse_input_event(up)
	yield(_wait_idle(2), "completed")
	check(not Input.is_action_pressed("fire") and Input.get_action_strength("move_forward") < 0.1, "releasing touches releases the actions")

	# the PICK UP button shows when loot is in reach
	p.velocity = Vector3.ZERO
	world.spawn_item(Items.make_consumable("medkit", 1), p.global_transform.origin + Vector3(1.0, 0.4, 0))
	yield(_frames(14), "completed")
	yield(_wait_idle(2), "completed")
	check(not touch._buttons["interact"]["hidden"], "touch PICK UP button appears near loot")
	yield(_shot("hud_touch"), "completed")

	# build-piece buttons enter / leave build mode, material boxes pick the material
	var pc: Vector2 = touch._buttons["piece1"]["center"]
	var pt := InputEventScreenTouch.new()
	pt.index = 6
	pt.pressed = true
	pt.position = _win(pc)
	Input.parse_input_event(pt)
	yield(_wait_idle(2), "completed")
	pt.pressed = false
	Input.parse_input_event(pt)
	yield(_wait_idle(2), "completed")
	check(p.builder.active and p.builder.piece == 1, "touch piece button enters build mode with that piece")
	p.materials = {"wood": 50, "stone": 50, "metal": 50}     # an empty material would auto-route away
	var mat_pos: Vector2 = world.hud.materials.rect_global_position + Vector2(76 * 2 + 12 + 30, 20)
	var mt := InputEventScreenTouch.new()
	mt.index = 7
	mt.pressed = true
	mt.position = _win(mat_pos)
	Input.parse_input_event(mt)
	yield(_wait_idle(2), "completed")
	mt.pressed = false
	Input.parse_input_event(mt)
	yield(_wait_idle(2), "completed")
	check(p.builder.material == "metal", "tapping a materials box chooses it")
	yield(_shot("hud_touch_build"), "completed")
	pt.pressed = true
	Input.parse_input_event(pt)
	yield(_wait_idle(2), "completed")
	pt.pressed = false
	Input.parse_input_event(pt)
	yield(_wait_idle(2), "completed")
	check(not p.builder.active, "tapping the chosen piece again leaves build mode")
	controls.set_touch_mode(false)

	# --- screenshots: loadout on the desktop HUD
	p.select_slot(1)
	p.slots[4] = Items.make_consumable("shield_potion", 2)
	p.materials = {"wood": 120, "stone": 36, "metal": 8}
	p.health = 100.0
	p.max_health = 100.0
	p.shield = 35.0
	p.emit_signal("slot_changed")
	yield(_wait_idle(2), "completed")
	yield(_shot("hud_loadout"), "completed")
	p.select_slot(0)
	var cam := Camera.new()
	cam.far = 800.0
	world.add_child(cam)
	cam.global_transform = Transform(Basis(), Vector3(0, 70, 95)).looking_at(Vector3(0, 0, 0), Vector3.UP)
	cam.make_current()
	yield(_shot("aerial_town"), "completed")

	# --- audio events fired during all of the above
	var audio = root.get_node("Audio")
	for snd in ["shot_rifle", "reload", "hitmarker", "chest_open", "ammo_box_open", "loot_pickup", "hit_wood", "consume_potion", "shield_up", "heal_up", "swing"]:
		check(audio.count_of(snd) > 0, "sound played: " + snd)
	var steps := 0
	for k in audio.stats.keys():
		if k.begins_with("step_"):
			steps += audio.stats[k]
	check(steps > 0, "footsteps play while walking (%d)" % steps)
	check(audio.current_music() in ["music_game", "music_combat"], "in-game music is playing (%s)" % audio.current_music())
	check(audio.count_of("ambient_loop") > 0 and audio.count_of("waves_loop") > 0, "ambient loops started")
	for loop_name in ["bus_loop", "music_game", "storm_loop"]:
		var st = audio._stream(loop_name)
		check(st != null and abs(float(st.loop_end) / st.mix_rate - st.get_length()) < 0.05, "%s loops over its whole length (%.2fs of %.2fs)" % [loop_name, float(st.loop_end) / st.mix_rate, st.get_length()])

	print("SMOKE_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

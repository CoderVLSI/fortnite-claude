extends SceneTree
# New mechanics: grenades (throw, fuse, blast damage, build pieces, thrower feedback), Slurp Juice / Chug Jug, floating
# damage numbers, item slot keys (F pickaxe, 1-4 items).
#
#   xvfb-run -a godot3 --path . -s res://tests/mechanics_test.gd -- --no-capture --no-bus --skip-menu [--shots=DIR]

const Items = preload("res://scripts/Items.gd")
var Grenade        # loaded at run time: the script talks to autoloads that do not exist yet when this file is parsed

var failures := []
var shots_dir := ""
var hit_log := []
var dmg_log := []


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


func _on_hit(target, killed, _head) -> void:
	hit_log.append([target, killed])


func _on_dmg(_pos, amount, _head, _killed) -> void:
	dmg_log.append(amount)


func _run() -> void:
	yield(self, "idle_frame")
	Grenade = load("res://scripts/Grenade.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	var target = null
	for f in get_nodes_in_group("fighters"):
		if f != p:
			if target == null:
				target = f
			else:
				f.queue_free()
	p.max_health = 1000000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(0.0, y + 1.0, 30.0)
	p.rotation.y = 0.0
	p.velocity = Vector3.ZERO
	target.set_physics_process(false)        # a stationary dummy
	target.global_transform.origin = Vector3(0.0, y + 0.2, 20.0)
	target.health = 100.0
	target.shield = 0.0
	yield(_frames(30), "completed")
	p.connect("hit_landed", self, "_on_hit")
	p.connect("damage_dealt", self, "_on_dmg")

	# --- item slot keys: F = pickaxe, 1-4 = item slots
	p.slots[1] = Items.make_weapon("smg", 0)
	p.slots[2] = Items.make_weapon("pistol", 0)
	p.select_slot(2)
	Input.action_press("pickaxe")
	yield(_frames(3), "completed")
	Input.action_release("pickaxe")
	yield(_frames(3), "completed")
	check(p.selected == 0, "F equips the pickaxe")
	Input.action_press("slot_1")
	yield(_frames(3), "completed")
	Input.action_release("slot_1")
	yield(_frames(3), "completed")
	check(p.selected == 1 and p.selected_item().id == "smg", "1 equips the first item slot")

	# --- throwing a grenade
	p.slots[3] = Items.make_consumable("grenade", 3)
	p.select_slot(3)
	yield(_frames(5), "completed")
	check(p.is_throwable_selected(), "a grenade in hand is a throwable")
	var before_nodes := 0
	for n in world.get_children():
		if n is RigidBody:
			before_nodes += 1
	p.rotation.y = 0.0
	p.pitch = -0.1
	p.head.rotation.x = -0.1
	var a: Array = p.aim_origin_and_dir()
	p._fire_cd = 0.0
	check(p.throw_grenade(a[0], a[1]), "throw_grenade throws")
	var after_nodes := 0
	for n in world.get_children():
		if n is RigidBody:
			after_nodes += 1
	check(after_nodes == before_nodes + 1, "a grenade body is in the world")
	check(p.slots[3].count == 2, "the stack drops by one (%d left)" % p.slots[3].count)
	check(not p.throw_grenade(a[0], a[1]), "there is a cooldown between throws")

	# --- the blast: a dummy close to the grenade takes damage, the thrower gets hit-marker feedback
	var g = Grenade.new()
	g.thrower = p
	g.fuse = 0.15
	world.add_child(g)
	g.global_transform.origin = target.global_transform.origin + Vector3(1.5, 0.8, 0)
	hit_log.clear()
	dmg_log.clear()
	var hp_before: float = target.health
	yield(_frames(30), "completed")
	check(target.health < hp_before - 20.0 or target.is_dead, "the explosion damages a nearby fighter (%.0f -> %.0f)" % [hp_before, target.health])
	check(hit_log.size() > 0 and dmg_log.size() > 0, "the thrower gets a hit marker and a damage number")
	check(is_instance_valid(g) == false or g.is_queued_for_deletion(), "the grenade is gone after exploding")

	# --- build pieces take blast damage
	p.materials = {"wood": 100, "stone": 0, "metal": 0}
	var node = world.spawn_build("wall", "wood", "test:wall:1", p.global_transform.origin + Vector3(0, 1.5, -6.0), 0.0)
	yield(_frames(5), "completed")
	var piece_hp: float = node.health
	var g2 = Grenade.new()
	g2.thrower = p
	g2.fuse = 0.1
	world.add_child(g2)
	g2.global_transform.origin = node.global_transform.origin + Vector3(1.0, 0.5, 0)
	yield(_frames(25), "completed")
	check(not is_instance_valid(node) or node.is_dead or node.health < piece_hp, "a grenade damages build pieces")

	# --- Slurp Juice (heals and shields) and Chug Jug (full, slowly)
	p.max_health = 100.0
	p.health = 30.0
	p.shield = 10.0
	p.slots[4] = Items.make_consumable("slurp_juice", 2)
	p.select_slot(4)
	yield(_frames(3), "completed")
	for i in range(int(2.8 * 60.0)):
		p.use_selected(1.0 / 60.0)
	check(abs(p.health - 55.0) < 0.5 and abs(p.shield - 35.0) < 0.5, "Slurp Juice gives +25 health and +25 shield (%.0f / %.0f)" % [p.health, p.shield])
	check(p.slots[4] != null and p.slots[4].count == 1, "one Slurp is used up")
	p.slots[4] = Items.make_consumable("chug_jug", 1)
	p.select_slot(4)
	yield(_frames(3), "completed")
	var used := 0.0
	while p.slots[4] != null and used < 12.0:
		p.use_selected(1.0 / 60.0)
		used += 1.0 / 60.0
	check(p.health >= 99.9 and p.shield >= 99.9 and used > 9.0, "Chug Jug takes ~10 s and restores everything (%.1f s)" % used)
	check(p.slots[4] == null, "the Chug Jug is consumed")

	# --- floating damage numbers
	var hud = world.hud
	hud._dmg.clear()
	p.emit_signal("damage_dealt", p.global_transform.origin + p.global_transform.basis.z * -5.0, 42.0, true, false)
	yield(self, "idle_frame")
	check(hud._dmg.size() == 1, "a hit spawns a floating damage number")
	for i in range(80):
		yield(self, "idle_frame")
	check(hud._dmg.size() == 0, "the number fades away")

	# --- crouch: slower, lower camera, steadier aim
	p.select_slot(0)
	p.max_health = 1000000.0
	p.health = p.max_health
	p.global_transform.origin = Vector3(0.0, world.terrain.height_at(0.0, 35.0) + 1.0, 35.0)
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	yield(_frames(60), "completed")
	Input.action_press("move_forward")
	yield(_frames(60), "completed")
	var walk_speed := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_press("crouch")
	yield(_frames(60), "completed")
	var crouch_speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(p.crouching and crouch_speed < walk_speed * 0.7, "crouching slows you (%.1f vs %.1f m/s)" % [crouch_speed, walk_speed])
	check(p.head.translation.y < 1.2, "the camera sinks while crouched (%.2f)" % p.head.translation.y)
	Input.action_release("crouch")
	Input.action_release("move_forward")
	yield(_frames(60), "completed")
	check(not p.crouching and p.head.translation.y > 1.4, "standing up restores the camera")

	# --- slide: crouch while sprinting
	p.rotation.y = 0.0
	p.global_transform.origin = Vector3(24.0, world.terrain.height_at(24.0, 50.0) + 1.0, 50.0)       # clear of the test wall
	p.velocity = Vector3.ZERO
	yield(_frames(40), "completed")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	yield(_frames(90), "completed")
	var run_speed := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_press("crouch")
	yield(_frames(4), "completed")
	Input.action_release("crouch")
	check(p.sliding, "crouch while sprinting starts a slide (running at %.1f m/s)" % run_speed)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	yield(_frames(12), "completed")
	var slide_speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(slide_speed > walk_speed, "the slide keeps momentum without input (%.1f m/s)" % slide_speed)
	yield(_frames(80), "completed")
	check(not p.sliding, "the slide ends by itself")

	# --- emote: tap to dance, moving cancels it
	p.velocity = Vector3.ZERO
	yield(_frames(30), "completed")
	Input.action_press("emote")
	yield(_frames(3), "completed")
	Input.action_release("emote")
	yield(_frames(10), "completed")
	check(p.emoting, "the emote key starts the dance")
	Input.action_press("move_forward")
	yield(_frames(6), "completed")
	Input.action_release("move_forward")
	check(not p.emoting, "moving cancels the emote")

	# --- fall damage: a small drop is free, a big one hurts
	p.max_health = 100.0
	p.health = 100.0
	p.shield = 0.0
	p.global_transform.origin = Vector3(0.0, world.terrain.height_at(0.0, 40.0) + 3.0, 40.0)
	p.velocity = Vector3.ZERO
	yield(_frames(80), "completed")
	check(p.health >= 99.9, "a 2 m drop does no damage (%.0f)" % p.health)
	p.global_transform.origin = Vector3(0.0, world.terrain.height_at(0.0, 40.0) + 32.0, 40.0)
	p.velocity = Vector3.ZERO
	yield(_frames(180), "completed")
	check(p.health < 80.0 and p.health > 0.0, "a 30 m fall hurts (%.0f / 100)" % p.health)

	# --- spectating after elimination (a fresh bot to watch; the earlier dummy died in the grenade test)
	var Bot = load("res://scripts/Bot.gd")
	var watched = Bot.new()
	watched.name = "SpectateBot"
	watched.world = world
	watched.display_name = "Watchme"
	watched.map_half = 236.0
	watched.translation = Vector3(40.0, world.terrain.height_at(40.0, 60.0) + 1.0, 60.0)
	world.add_child(watched)
	watched.set_physics_process(false)
	yield(_frames(10), "completed")
	world.match_over = false            # the grenade test already "won" the match when the dummy died; start fresh
	hud.end_panel.visible = false
	hud.end_bg.visible = false
	p.max_health = 100.0
	p.health = 100.0
	p.shield = 0.0
	p.take_damage(1000.0, watched)
	yield(_frames(150), "completed")
	check(p.is_dead and hud.end_panel.visible, "being eliminated shows the result panel")
	check(hud.spec_button.visible, "the eliminated panel offers SPECTATE")
	hud._on_spectate()
	yield(_frames(10), "completed")
	check(world.spectating and world._spec_cam.current, "spectating switches to a free camera")
	check(world.spectate_name() == "Watchme" and hud.spec_root.visible, "it follows a living fighter (%s)" % world.spectate_name())
	var cam_before: Vector3 = world._spec_cam.global_transform.origin
	watched.global_transform.origin += Vector3(8, 0, 0)
	yield(_frames(60), "completed")
	check(world._spec_cam.global_transform.origin.distance_to(cam_before) > 3.0, "the camera follows the fighter around")
	watched.take_damage(1000000.0, null)
	yield(_frames(30), "completed")
	check(not world.spectating and hud.end_panel.visible, "when nobody is left to watch, the result panel comes back")
	check(p.camera.current, "the player camera is restored")

	print("MECHANICS_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

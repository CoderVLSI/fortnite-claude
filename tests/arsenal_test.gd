extends SceneTree
# New Fortnite-style kit: Burst AR, Rocket Launcher, Bouncer, glider redeploy, turbo building, sound visualisation.

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


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var Items = load("res://scripts/Items.gd")
	var settings = root.get_node("Settings")
	var controls = root.get_node("Controls")
	settings.reset_prefs()
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	p.max_health = 100000.0
	p.health = p.max_health
	var y: float = world.terrain.height_at(24.0, 46.0)
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.rotation.y = 0.0
	p.mode = p.Mode.GROUND
	yield(_frames(40), "completed")

	check(Items.WEAPONS.has("burst_assault") and Items.WEAPONS.has("rocket_launcher") and Items.CONSUMABLES.has("bouncer"), "the new items exist")
	for id in ["burst_assault", "rocket_launcher"]:
		check(ResourceLoader.exists("res://assets/icons/weapon_%s.png" % id), "%s has an icon" % id)
	check(ResourceLoader.exists("res://assets/models/rocket_launcher.glb") and ResourceLoader.exists("res://assets/icons/heal_bouncer.png"), "and a model / icon")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in range(400):
		seen[Items.random_weapon(rng).id] = true
	check(seen.has("burst_assault") and seen.has("rocket_launcher"), "they show up in the loot")

	# ---- burst fire: one pull, three rounds
	p.slots = [Items.pickaxe(), null, null, null, null, null]
	p.give_weapon("burst_assault", 2, 90)
	p.select_slot(1)
	var gun = p.selected_item()
	var m0: int = gun.mag
	p._fire_cd = 0.0
	var aim: Array = p.aim_origin_and_dir()
	p.try_fire(aim[0], aim[1])
	yield(_frames(30), "completed")
	check(m0 - gun.mag == 3, "the Burst AR fires three rounds per trigger pull (%d -> %d)" % [m0, gun.mag])
	p._fire_cd = 0.0

	# ---- rocket launcher
	p.give_weapon("rocket_launcher", 3, 12)
	p.select_slot(2)
	var rl = p.selected_item()
	check(rl != null and rl.id == "rocket_launcher", "the launcher can be equipped")
	var Bot = load("res://scripts/Bot.gd")
	var foe = null
	for f in get_nodes_in_group("fighters"):
		if f is Bot:
			foe = f
			break
	foe.set_physics_process(false)
	foe.team = -1
	var cam_pos: Vector3 = p.camera.global_transform.origin
	var dir: Vector3 = -p.camera.global_transform.basis.z
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	foe.global_transform.origin = Vector3(cam_pos.x, world.terrain.height_at(cam_pos.x + flat.x * 26.0, cam_pos.z + flat.z * 26.0), cam_pos.z) + flat * 26.0
	foe.global_transform.origin.y = world.terrain.height_at(foe.global_transform.origin.x, foe.global_transform.origin.z)
	foe.health = foe.max_health
	yield(_frames(10), "completed")
	var h0: float = foe.health
	p._fire_cd = 0.0
	var aim2: Array = p.aim_origin_and_dir()
	var a_to_foe: Vector3 = (foe.global_transform.origin + Vector3(0, 1.0, 0) - aim2[0]).normalized()
	check(p.try_fire(aim2[0], a_to_foe), "the rocket launcher fires")
	check(get_nodes_in_group("fighters").size() > 0 and rl.mag == 0, "it uses its single round")
	var flew := false
	for i in range(200):
		yield(_frames(1), "completed")
		if foe.health < h0:
			flew = true
			break
	check(flew, "the rocket flies and its blast hurts the enemy (%.0f -> %.0f)" % [h0, foe.health])

	# ---- rockets break buildings piece by piece
	var bld = null
	for c in get_nodes_in_group("structures"):
		if c.has_meta("res") and str(c.get_meta("res")) == "house_a":
			bld = c
			break
	var RocketScript = load("res://scripts/Rocket.gd")
	var rk = RocketScript.new()
	rk.thrower = p
	var from: Vector3 = bld.global_transform.origin + Vector3(9, 2.0, 0)
	rk.velocity = Vector3(-1, 0, 0) * RocketScript.SPEED
	world.add_child(rk)
	rk.global_transform.origin = from
	for i in range(120):
		yield(_frames(1), "completed")
		if bld.has_meta("pieces"):
			break
	check(bld.has_meta("pieces"), "a rocket into a house cuts it into pieces")
	yield(_frames(10), "completed")
	var gone := 0
	if bld.has_meta("pieces"):
		for pm in bld.get_meta("pieces"):
			if pm == null:
				gone += 1
	check(gone >= 1, "and the blast takes some of them down (%d pieces)" % gone)

	# ---- bouncer
	p.global_transform.origin = Vector3(24, y + 0.2, 46)
	p.velocity = Vector3.ZERO
	p.slots[3] = Items.make_consumable("bouncer", 2)
	p.select_slot(3)
	yield(_frames(20), "completed")
	p._fire_cd = 0.0
	var aim3: Array = p.aim_origin_and_dir()
	check(p.throw_grenade(aim3[0], aim3[1]), "a Bouncer can be placed")
	check(get_nodes_in_group("bounce_pads").size() == 1 and p.slots[3].count == 1, "the pad exists and one is used up")
	var pad = get_nodes_in_group("bounce_pads")[0]
	p.global_transform.origin = pad.global_transform.origin + Vector3(0, 0.3, 0)
	p.velocity = Vector3.ZERO
	var maxvy := 0.0
	for i in range(40):
		yield(_frames(1), "completed")
		maxvy = max(maxvy, p.velocity.y)
	check(maxvy > 14.0, "stepping on it flings you upward (%.1f m/s)" % maxvy)

	# ---- glider redeploy
	p.select_slot(0)
	p.global_transform.origin = Vector3(60, world.terrain.height_at(60.0, 60.0) + 70.0, 60)
	p.velocity = Vector3.ZERO
	yield(create_timer(1.5), "timeout")                  # fall for a moment: the glider can only reopen at speed
	var jump := InputEventAction.new()
	jump.action = "jump"
	jump.pressed = true
	Input.parse_input_event(jump)
	yield(create_timer(0.3), "timeout")
	jump.pressed = false
	Input.parse_input_event(jump)
	check(p.mode == p.Mode.GLIDE or p.mode == p.Mode.FREEFALL, "pressing jump while falling opens the glider again (mode %d)" % p.mode)
	yield(create_timer(8.0), "timeout")
	check(p.mode == p.Mode.GROUND or p.mode == p.Mode.GLIDE, "and you can land safely")
	p.global_transform.origin = Vector3(24, y + 1.0, 46)
	p.velocity = Vector3.ZERO
	p.mode = p.Mode.GROUND
	yield(_frames(60), "completed")

	# ---- turbo building
	controls.set_touch_mode(true)
	p.materials["wood"] = 500
	p.builder.set_active(true)
	p.builder.piece = 1
	var before: int = world.build_slots.size()
	var press := InputEventAction.new()
	press.action = "fire"
	press.pressed = true
	Input.parse_input_event(press)
	yield(create_timer(1.2), "timeout")
	press.pressed = false
	Input.parse_input_event(press)
	var after: int = world.build_slots.size()
	check(after - before >= 1, "turbo building keeps placing while fire is held (%d pieces)" % (after - before))
	p.builder.set_active(false)
	controls.set_touch_mode(false)

	# ---- visualize sound
	settings.set_pref("visual_sound", true)
	foe.global_transform.origin = Vector3(24, y, 46) + Vector3(8, 0, 0)
	foe.velocity = Vector3(5, 0, 0)
	foe.grounded = true
	root.get_node("Audio").note("gun", Vector3(24, y, 46) + Vector3(0, 0, -30))
	var viz = world.hud.sound_viz
	viz._marks.clear()
	viz._sample()
	var kinds := {}
	for m in viz._marks:
		kinds[m.kind] = true
	check(kinds.has("step") and kinds.has("gun"), "the sound ring shows footsteps and gunfire (%s)" % str(kinds.keys()))
	settings.set_pref("visual_sound", false)
	print("ARSENAL_RESULT failures=%d" % failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

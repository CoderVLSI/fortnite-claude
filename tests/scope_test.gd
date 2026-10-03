extends SceneTree
# Aim-down-sights test: right mouse / L2 / the scope button zoom the camera per weapon, pick the weapon's own sight
# (iron posts, red dot, holo ring, bead ring, full sniper scope), tighten spread, slow walking, and cancel sprinting.
#
#   xvfb-run -a godot3 --path . -s res://tests/scope_test.gd -- --no-capture --no-bus --skip-menu [--shots=DIR]

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


func _spread_rms(p, n: int) -> float:
	var sum := 0.0
	for i in range(n):
		var d: Vector3 = p._spread(Vector3(0, 0, -1))
		sum += d.angle_to(Vector3(0, 0, -1)) * d.angle_to(Vector3(0, 0, -1))
	return sqrt(sum / n)


func _run() -> void:
	yield(self, "idle_frame")
	var controls = root.get_node("Controls")
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
	controls.touch_mode = true          # lets the player aim without a captured mouse (HUD layout stays desktop)
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(0.0, y + 1.0, 30.0)
	p.rotation.y = PI / 2.0
	p.velocity = Vector3.ZERO
	yield(_frames(60), "completed")
	var hud = world.hud

	for id in ["pistol", "smg", "assault", "shotgun", "sniper"]:
		var sc: Dictionary = Items.scope_of(id)
		p.slots[1] = Items.make_weapon(id, 0)
		p.slots[1].mag = 99
		p.select_slot(1)
		yield(_frames(40), "completed")
		check(not p.aiming and abs(p.camera.fov - 72.0) < 1.5, "%s: hip-fire has the normal field of view (%.1f)" % [id, p.camera.fov])
		var hip_rms := _spread_rms(p, 400)
		yield(_shot("scope_%s_hip" % id), "completed")

		Input.action_press("aim")
		yield(_frames(50), "completed")
		yield(self, "idle_frame")
		check(p.aiming, "%s: holding aim sets aiming" % id)
		check(abs(p.camera.fov - sc.fov) < 1.5, "%s: aiming zooms to %.0f degrees (%.1f)" % [id, sc.fov, p.camera.fov])
		check(p.is_scoped() == (id == "sniper"), "%s: full scope only on the sniper" % id)
		check(hud.scope_overlay.visible == (id == "sniper"), "%s: scope overlay visible = %s" % [id, str(id == "sniper")])
		check(p.model.visible == (id != "sniper"), "%s: the body hides only behind the sniper scope" % id)
		var aim_rms := _spread_rms(p, 400)
		if hip_rms > 0.0001:
			check(aim_rms < hip_rms * 0.8, "%s: aiming tightens the spread (%.4f -> %.4f rad)" % [id, hip_rms, aim_rms])
		else:
			check(aim_rms <= hip_rms, "%s: aiming keeps the spread at 0" % id)
		if id == "sniper":
			check(_spread_rms(p, 10) < 0.0001, "sniper: scoped shots are perfectly accurate")
		yield(_shot("scope_%s_ads" % id), "completed")

		Input.action_release("aim")
		yield(_frames(60), "completed")
		check(not p.aiming and abs(p.camera.fov - 72.0) < 2.0, "%s: releasing aim returns to the normal view (%.1f)" % [id, p.camera.fov])
		if id == "sniper":
			check(_spread_rms(p, 400) > 0.01, "sniper: hip-fire is inaccurate on purpose")

	# slower walking while aiming, and aiming cancels sprinting
	p.slots[1] = Items.make_weapon("assault", 0)
	p.slots[1].mag = 99
	p.select_slot(1)
	Input.action_press("move_forward")
	yield(_frames(70), "completed")
	var walk := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_press("aim")
	yield(_frames(70), "completed")
	var aimed := Vector2(p.velocity.x, p.velocity.z).length()
	check(aimed < walk * 0.85, "walking while aiming is slower (%.1f vs %.1f m/s)" % [aimed, walk])
	Input.action_press("sprint")
	yield(_frames(40), "completed")
	check(p.aiming and not p.sprinting, "aiming overrides sprinting")
	Input.action_release("sprint")
	Input.action_release("aim")
	Input.action_release("move_forward")
	yield(_frames(20), "completed")

	# only guns can aim
	p.select_slot(0)
	yield(_frames(10), "completed")
	Input.action_press("aim")
	yield(_frames(20), "completed")
	check(not p.aiming, "the pickaxe cannot aim")
	Input.action_release("aim")

	# the touch scope button toggles aiming
	p.select_slot(1)
	yield(_frames(10), "completed")
	controls.touch_aim = true
	yield(_frames(30), "completed")
	check(p.aiming, "the touch scope toggle aims")
	controls.touch_aim = false
	yield(_frames(30), "completed")
	check(not p.aiming, "toggling the scope off stops aiming")

	# every mythic gun has its own shot sound
	var audio = root.get_node("Audio")
	for id in ["pistol", "smg", "assault", "shotgun", "sniper"]:
		p.slots[1] = Items.make_weapon(id, Items.MYTHIC)
		p.select_slot(1)
		yield(_frames(5), "completed")
		p._fire_cd = 0.0
		p.fire_at_crosshair()
		var snd := "shot_mythic" if id == "sniper" else "shot_mythic_" + id
		check(audio.count_of(snd) > 0, "mythic %s fires '%s'" % [id, snd])

	print("SCOPE_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

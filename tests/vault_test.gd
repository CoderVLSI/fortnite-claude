extends SceneTree
# Vaulting through a low window: from outside to inside and back again.

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
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	var wins := get_nodes_in_group("windows")
	check(wins.size() >= 10, "buildings have window markers (%d)" % wins.size())
	var w = null
	for c in wins:
		if str(c.get_parent().name).begins_with("house") or str(c.get_parent().get_parent().name).begins_with("house"):
			w = c
			break
	if w == null:
		w = wins[0]
	var nrm: Vector3 = w.global_transform.basis.xform(w.get_meta("dir")).normalized()
	var wp: Vector3 = w.global_transform.origin
	var ground_y: float = wp.y - 1.0
	check(abs(nrm.length() - 1.0) < 0.01 and abs(nrm.y) < 0.01, "a window knows which way it faces")
	# stand outside, face the window, jump
	p.mode = p.Mode.GROUND
	p.global_transform.origin = Vector3(wp.x, ground_y + 0.05, wp.z) + nrm * 1.1
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(nrm.x, nrm.z)             # the player's forward is -Z: look against the outward normal
	yield(_frames(10), "completed")
	Input.action_press("move_forward")
	var jump := InputEventAction.new()
	jump.action = "jump"
	jump.pressed = true
	Input.parse_input_event(jump)
	yield(_frames(8), "completed")
	var started: bool = p.mode == p.Mode.MANTLE and p._vault
	check(started, "jumping at the window starts a vault (mode %d)" % p.mode)
	var Clips = load("res://scripts/AnimClips.gd")
	for c in ["slide", "vault", "mantle", "harvest"]:
		check(Clips.has_clip(c) and Clips.length_of(c) > 0.3, "the Blender clip '%s' is loaded (%.2f s)" % [c, Clips.length_of(c)])
	check(Clips.joints_of("harvest").size() == 6 and not ("HipL" in Clips.joints_of("harvest")), "the pickaxe swing only drives the upper body")
	var smp: Dictionary = Clips.sample("vault", 0.35, 0.93)
	check(smp.has("HipL") and smp.HipL.x > 1.2, "the vault clip tucks the legs (%.2f rad)" % smp.HipL.x)
	yield(_frames(8), "completed")
	check(p.animator.tgt["HipL"].x > 0.75, "the character plays it (thigh target %.2f)" % p.animator.tgt["HipL"].x)
	jump.pressed = false
	Input.parse_input_event(jump)
	yield(_frames(70), "completed")
	Input.action_release("move_forward")
	var d_in: float = (p.global_transform.origin - wp).dot(nrm)
	check(p.mode == p.Mode.GROUND and d_in < -0.5, "you land inside the building (%.1f m past the wall)" % -d_in)
	check(abs(p.global_transform.origin.y - (ground_y + 0.05)) < 0.6, "on the floor, not on the roof (y %.1f)" % (p.global_transform.origin.y - ground_y))
	# and back out again
	p._mantle_cd = 0.0
	p.rotation.y = atan2(-nrm.x, -nrm.z)
	p.global_transform.origin = Vector3(wp.x, ground_y + 0.05, wp.z) - nrm * 1.1
	yield(_frames(10), "completed")
	Input.action_press("move_forward")
	jump.pressed = true
	Input.parse_input_event(jump)
	yield(_frames(8), "completed")
	check(p.mode == p.Mode.MANTLE, "and out again")
	jump.pressed = false
	Input.parse_input_event(jump)
	yield(_frames(70), "completed")
	Input.action_release("move_forward")
	check((p.global_transform.origin - wp).dot(nrm) > 0.5, "you end up outside")
	# far from any window nothing happens
	p.global_transform.origin = world.player.global_transform.origin + Vector3(40, 0, 40)
	yield(_frames(5), "completed")
	check(not p.try_vault(Vector3(0, 0, -1)), "no vault away from windows")
	print("VAULT_RESULT failures=%d" % failures.size())
	quit(1 if failures.size() > 0 else 0)

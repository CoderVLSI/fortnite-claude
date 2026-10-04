extends "res://scripts/Fighter.gd"
# Player: over-the-shoulder third-person camera, strafe movement relative to the
# camera yaw, inventory/hotbar, interact (loot, chests), and the bus -> freefall ->
# glider -> ground flow. Weapons fire a hitscan along the crosshair.

const Builder = preload("res://scripts/Builder.gd")

const SHOULDER_OFFSET := Vector3(0.65, 1.55, 0.0)
const CAMERA_DISTANCE := 3.6
const INTERACT_RANGE := 3.2
const SLIDE_TIME := 0.85
const SLIDE_SPEED := 11.5
var _slide_buffer := 0.0
var _sprint_latch := false         # Settings: toggle sprint
var _crouch_latch := false         # Settings: toggle crouch
var _sprint_was_down := false
var _crouch_was_down := false
var _jump_was_down := false
var _turbo_t := 0.0                # turbo building repeat timer
var _quick_slot := -1              # Quick Heal: the healing slot being used
var _sight_t := 0.0
var _sight_enemy := false
const BUILD_ACTIONS := ["build_wall", "build_floor", "build_ramp", "build_roof"]

var input_enabled := true
var pitch := -0.12
var head: Spatial
var spring: SpringArm
var camera: Camera
var interact_target = null
var builder
var _interact_t := 0.0
var _audio_ready := false
var _last_look_time := 0.0
var _aim_latch := false     # toggle-aim mode (Settings > Gameplay)
var combat_until := 0.0     # seconds (ticks) until which the music stays in "combat"


func _ready() -> void:
	add_to_group("player")
	setup_fighter("You", Color(0.22, 0.42, 0.85))
	_build_camera()
	builder = Builder.new()
	builder.name = "Builder"
	add_child(builder)
	builder.setup(self, get_parent())
	Controls.connect("slot_scroll", self, "_on_scroll")
	connect("hit_landed", self, "_on_hit_landed")
	connect("slot_changed", self, "_on_slot_changed")
	_audio_ready = true


func _build_camera() -> void:
	head = Spatial.new()
	head.name = "CameraPivot"
	head.translation = SHOULDER_OFFSET
	add_child(head)
	spring = SpringArm.new()
	spring.spring_length = CAMERA_DISTANCE
	spring.margin = 0.3
	spring.collision_mask = 1
	head.add_child(spring)
	spring.add_excluded_object(get_rid())
	camera = Camera.new()
	camera.fov = 72.0
	camera.far = 420.0
	camera.near = 0.15
	spring.add_child(camera)
	camera.make_current()
	head.rotation.x = pitch


func _physics_process(delta: float) -> void:
	tick_weapon(delta)
	_update_air_audio()
	if mode != Mode.GROUND or is_dead:
		aiming = false
		crouching = false
		sliding = false
		emoting = false
	if is_dead:
		velocity = Vector3(0, velocity.y, 0)
		move_body(delta, Vector3.ZERO, 0.0, false)
		animate(delta)
		return
	if input_enabled:
		_look(delta)
	match mode:
		Mode.BUS:
			follow_bus()
			if input_enabled and Input.is_action_just_pressed("jump"):
				leave_bus()
			interact_target = null
		Mode.VEHICLE:
			_vehicle_process(delta)
		Mode.SWIM:
			_swim_process(delta)
		Mode.MANTLE:
			mantle_physics(delta)
			aim_pitch = 0.0
			animate(delta)
			interact_target = null
		Mode.FREEFALL, Mode.GLIDE:
			air_input = Controls.get_move() if input_enabled else Vector2.ZERO
			if mode == Mode.FREEFALL and input_enabled and Input.is_action_just_pressed("jump"):
				deploy_glider()
			air_physics(delta)
			aim_pitch = 0.0
			animate(delta)
			interact_target = null
		_:
			_ground_process(delta)


func _vehicle_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.exploded:
		exit_vehicle(true)
		return
	follow_vehicle()
	var v = vehicle
	var yaw: float = v.global_transform.basis.get_euler().y
	air_pivot.rotation.y = wrapf(yaw - rotation.y, -PI, PI)
	if vehicle_seat == 0 and input_enabled:
		v.input_move = Controls.get_move()
		v.handbrake = Input.is_action_pressed("jump")
		v.boost = Input.is_action_pressed("sprint")
		if Input.is_action_just_pressed("reload"):
			Audio.play3d("car_horn", v.global_transform.origin, 2.0)
		vehicle_steer = clamp(v.steer_visual * 2.0 if "steer_visual" in v else v.input_move.x * -0.5, -1.0, 1.0)
	else:
		vehicle_steer = 0.0
		if vehicle_seat == 0:
			v.input_move = Vector2.ZERO
	vehicle_hands_on_wheel = vehicle_seat == 0
	if input_enabled and OS.get_ticks_msec() / 1000.0 - _last_look_time > 1.3:
		rotation.y = lerp_angle(rotation.y, yaw, clamp(1.8 * delta, 0.0, 1.0))
	aim_pitch = 0.0
	animate(delta)
	if input_enabled and Input.is_action_just_pressed("interact"):
		exit_vehicle(false)


# Sprint is held, or toggled on by one tap when that option is on, or kept going by the phone's AUTO RUN.
func _sprint_wanted(move: Vector2) -> bool:
	if Controls.auto_run:
		return move.length() > 0.2
	if Settings.pref("toggle_sprint"):
		var down := Input.is_action_pressed("sprint")
		if down and not _sprint_was_down:
			_sprint_latch = not _sprint_latch
		_sprint_was_down = down
		if move.length() < 0.2:
			_sprint_latch = false
		return _sprint_latch and move.length() > 0.2
	_sprint_latch = false
	return Input.is_action_pressed("sprint") and move.length() > 0.2


func _crouch_wanted() -> bool:
	if Settings.pref("toggle_crouch"):
		var down := Input.is_action_pressed("crouch")
		if down and not _crouch_was_down and grounded and not sliding:
			_crouch_latch = not _crouch_latch
		_crouch_was_down = down
		if Input.is_action_just_pressed("jump") or not grounded:
			_crouch_latch = false
		return _crouch_latch
	_crouch_latch = false
	return Input.is_action_pressed("crouch")


func _swim_process(delta: float) -> void:
	var move := Controls.get_move() if input_enabled else Vector2.ZERO
	sprinting = input_enabled and _sprint_wanted(move)
	var b := global_transform.basis
	var wish := b.x * move.x + b.z * move.y
	if input_enabled and Input.is_action_just_pressed("jump"):
		swim_jump()
		return
	swim_physics(delta, wish, 5.4 if sprinting else 3.4)
	aim_pitch = 0.0
	animate(delta)
	interact_target = null


func _ground_process(delta: float) -> void:
	var move := Vector2.ZERO
	var want_jump := false
	if input_enabled:
		move = Controls.get_move()
		want_jump = Input.is_action_pressed("jump") and not downed and boogie_t <= 0.0
		sprinting = _sprint_wanted(move) and not downed
		_update_aim()
		if Input.is_action_just_pressed("reload"):
			start_reload()
		if Input.is_action_just_pressed("quick_heal"):
			quick_heal()
		if Input.is_action_just_pressed("last_item"):
			swap_to_previous()
		if Input.is_action_just_pressed("build_toggle") and not downed:
			builder.toggle()
		for i in range(BUILD_ACTIONS.size()):
			if Input.is_action_just_pressed(BUILD_ACTIONS[i]):
				press_piece(i)
		if Input.is_action_just_pressed("pickaxe"):          # F: the pickaxe
			if builder.active:
				builder.set_active(false)
			select_slot(0)
		for i in range(1, Items.SLOT_COUNT):                 # 1-5: the item slots, in order
			if Input.is_action_just_pressed("slot_%d" % i):
				if builder.active:
					builder.set_active(false)          # picking an item leaves build mode
				select_slot(i)
		_fire_input(delta)
		_interact_input(delta)
	var b := global_transform.basis
	if not input_enabled:
		sprinting = false
		aiming = false
	var jump_down := Input.is_action_pressed("jump")
	var jump_edge: bool = jump_down and not _jump_was_down
	_jump_was_down = jump_down
	if input_enabled and jump_edge and not grounded and redeploy_glider():
		return
	if input_enabled and Input.is_action_just_pressed("jump") and try_vault(-b.z * -move.y + b.x * move.x if move.length() > 0.3 else -b.z):
		return
	if input_enabled and want_jump and move.y < -0.3 and try_mantle(-b.z * -move.y + b.x * move.x):
		return
	if input_enabled and not grounded and move.y < -0.3 and try_mantle(-b.z):
		return                             # jumped / fell against a ledge: grab it
	_update_stance(delta, move, want_jump)
	if emoting:
		move = Vector2.ZERO
	if has_gadget("jetpack") and input_enabled and mode == Mode.GROUND and Input.is_action_pressed("jump"):
		_jet_hold += delta
	else:
		_jet_hold = 0.0
	jet_active = _jet_hold > 0.15                  # a tap is a normal jump; holding Space lights the jetpack (it only has to be in your inventory)
	var wish := b.x * move.x + b.z * move.y    # move.y > 0 is backwards, and basis.z points backwards
	var speed := sprint_speed if sprinting else walk_speed
	if sliding:                                # momentum: a fixed direction, losing speed as the slide ends
		wish = _slide_dir
		speed = lerp(3.0, SLIDE_SPEED, clamp(_slide_t / SLIDE_TIME, 0.0, 1.0))
	elif crouching:
		speed *= 0.5
	if is_using():
		speed *= 0.5
	if charge > 0.0:
		speed *= 0.75                              # bracing the charge slows you
	if aiming:
		speed *= Items.scope_of(selected_item().id).move
	move_body(delta, wish, speed, want_jump)
	aim_pitch = pitch
	animate(delta)


# Right mouse / L2 (hold) or the touch scope button (toggle) aims the equipped gun. Aiming cancels sprinting and
# pauses while reloading or using an item.
# Crouch (hold), slide (crouch while sprinting) and emote (tap) state for this frame.
func _update_stance(delta: float, move: Vector2, want_jump: bool) -> void:
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	_slide_buffer = max(0.0, _slide_buffer - delta)
	if input_enabled and not grounded and Input.is_action_just_pressed("crouch") and flat_speed > 4.8:
		_slide_buffer = 0.45                      # crouch pressed just before landing: slide as soon as you touch down
	if sliding:
		_slide_t -= delta
		if _slide_t <= 0.0 or want_jump or not grounded:
			sliding = false
	elif input_enabled and not downed and grounded and flat_speed > 4.8 and (Input.is_action_just_pressed("crouch") or _slide_buffer > 0.0) \
			and (sprinting or flat_speed > 5.5 or _slide_buffer > 0.0):
		_slide_buffer = 0.0
		sliding = true
		_slide_t = SLIDE_TIME
		_slide_dir = Vector3(velocity.x, 0.0, velocity.z).normalized()
		Audio.play3d("skid", global_transform.origin, -6.0, 1.4)
	crouching = input_enabled and _crouch_wanted() and grounded and not sliding and not downed
	if sliding or crouching:
		sprinting = false
	if emoting:
		emote_t += delta
		if boogie_t <= 0.0 and (move.length() > 0.2 or want_jump or Input.is_action_pressed("fire") or sliding or emote_t > Emotes.length_of(emote_id)):
			emoting = false


# Start an emote from the wheel (or the quick tap). Returns false when the player is busy.
func start_emote(id: String) -> bool:
	if not Emotes.is_emote(id) or not input_enabled or is_dead or mode != Mode.GROUND or emoting:
		if emoting and Emotes.is_emote(id) and not is_dead and mode == Mode.GROUND:
			emote_id = id                      # picking another one while dancing switches straight to it
			emote_t = 0.0
			Settings.last_emote = id
			return true
		return false
	var move := Controls.get_move()
	if not grounded or sliding or crouching or aiming or move.length() >= 0.2 or builder.active:
		return false
	emote_id = id
	emoting = true
	emote_t = 0.0
	Settings.last_emote = id
	cancel_use()
	return true


# A build piece key / button: enter build mode with that piece; pressing the chosen piece again leaves build mode.
func press_piece(index: int) -> void:
	if is_dead or mode != Mode.GROUND:
		return
	if builder.active and builder.piece == index:
		builder.set_active(false)
		return
	builder.set_active(true)
	if builder.active:
		builder.set_piece(index)


func _update_aim() -> void:
	var item = selected_item()
	var gun: bool = item != null and item.kind == "weapon" and not builder.active
	if not gun:
		Controls.touch_aim = false
		_aim_latch = false
	if Settings.aim_toggle:
		if Input.is_action_just_pressed("aim"):
			_aim_latch = not _aim_latch
	else:
		_aim_latch = false
	var pressed: bool = _aim_latch if Settings.aim_toggle else Input.is_action_pressed("aim")
	var wants: bool = gun and (pressed or Controls.touch_aim) and _can_aim()
	if wants:
		sprinting = false
	aiming = wants and not is_reloading() and not is_using()


func is_scoped() -> bool:
	return aiming and Items.scope_of(selected_item().id).kind == "scope"


var _jet_hold := 0.0


func _fire_input(delta: float) -> void:
	if downed:
		cancel_use()
		return
	if Controls.edit_aim:             # the build editor owns the fire button (it selects tiles)
		cancel_use()
		return
	if builder.active:
		_turbo_t -= delta
		if Input.is_action_just_pressed("fire") and _can_aim():
			builder.place()
			_turbo_t = 0.28
		elif Settings.pref("turbo_build") and Input.is_action_pressed("fire") and _can_aim() and _turbo_t <= 0.0:
			builder.place()                           # Turbo building: hold fire to keep placing
			_turbo_t = 0.14
		cancel_use()
		return
	var item = selected_item()
	if item != null and item.kind == "weapon" and Items.WEAPONS[item.id].has("charge"):
		_charge_input(delta, item)
		return
	if _quick_slot >= 0:                        # Quick Heal keeps using the item until it is done or you do something else
		if selected == _quick_slot and slots[selected] != null and slots[selected].kind == "consumable" and not Input.is_action_pressed("fire") \
				and Controls.get_move().length() < 0.1 and not Input.is_action_pressed("jump"):
			use_selected(delta)
			return
		_quick_slot = -1
		cancel_use()
	var auto_shot: bool = Controls.auto_fire and item != null and item.kind == "weapon" and _enemy_in_sights(delta)
	var firing := (Input.is_action_pressed("fire") or auto_shot) and _can_aim()
	if item == null or not firing:
		cancel_use()
		return
	if item.kind == "consumable":
		if Items.CONSUMABLES[item.id].has("gadget"):          # jetpack: hold jump; skateboard: fire hops on / off
			if Input.is_action_just_pressed("fire") and Items.CONSUMABLES[item.id].gadget == "skateboard":
				toggle_board()
			return
		if is_throwable_selected():
			if Input.is_action_just_pressed("fire"):
				var a := aim_origin_and_dir()
				throw_grenade(a[0], a[1])
			return
		use_selected(delta)
		return
	if automatic or auto_shot or Input.is_action_just_pressed("fire"):
		if fire_at_crosshair() and item.kind == "weapon":
			Controls.rumble(0.1, 0.3, 0.07)
			pitch += rand_range(0.0, 0.006) * (3.0 if pellets > 1 or item.id == "sniper" else 1.0)
			rotation.y += rand_range(-0.003, 0.003)


# Phones' AUTO FIRE: is somebody who is not on our team in the crosshair (and in range)?
func _enemy_in_sights(delta: float) -> bool:
	_sight_t -= delta
	if _sight_t > 0.0:
		return _sight_enemy
	_sight_t = 0.08
	_sight_enemy = false
	if camera == null:
		return false
	var centre: Vector2 = get_viewport().get_visible_rect().size / 2.0
	var from: Vector3 = camera.project_ray_origin(centre)
	var to: Vector3 = from + camera.project_ray_normal(centre) * max(weapon_range, 20.0)
	var hit := get_world().direct_space_state.intersect_ray(from, to, [self], 3)
	if hit and hit.collider != null and hit.collider.is_in_group("fighters"):
		var f = hit.collider
		_sight_enemy = not f.is_dead and not is_ally(f) and f != self
	return _sight_enemy


# Quick Heal key: pick the best healing item for what is missing and start using it.
func quick_heal() -> void:
	if is_dead or mode != Mode.GROUND or not input_enabled:
		return
	var want_health: bool = health < max_health - 1.0
	var want_shield: bool = shield < max_shield - 1.0
	var best := -1
	var best_score := -1.0
	for i in range(1, slots.size()):
		var it = slots[i]
		if it == null or it.kind != "consumable":
			continue
		var c: Dictionary = Items.CONSUMABLES[it.id]
		if c.get("gadget", "") != "" or c.get("rift", false):
			continue
		var score := 0.0
		if want_health and c.heal > 0.0 and health < c.heal_cap:
			score += c.heal
		if want_shield and c.shield > 0.0 and shield < c.shield_cap:
			score += c.shield
		if score > best_score:
			best_score = score
			best = i
	if best < 0 or best_score <= 0.0:
		emit_signal("picked_up", "Nothing to heal with" if want_health or want_shield else "Already at full health")
		return
	if builder.active:
		builder.set_active(false)
	select_slot(best)
	_quick_slot = best


# Charge Shotgun: hold fire to charge (up to 50% more damage, tighter spread), release to shoot.
func _charge_input(delta: float, item) -> void:
	var def: Dictionary = Items.WEAPONS[item.id]
	var holding := Input.is_action_pressed("fire") and _can_aim()
	var ready: bool = mode == Mode.GROUND and _fire_cd <= 0.0 and _reload_left <= 0.0 and _use_left <= 0.0 and item.mag > 0
	if holding and ready:
		var before := charge
		charge = min(1.0, charge + delta / float(def.charge))
		if before == 0.0:
			Audio.play2d("charge_start", -1.0)
		if before < 1.0 and charge >= 1.0:
			Audio.play2d("charge_full", -5.0)
	elif charge > 0.0:
		if ready and not holding:
			charge_used = charge
			fire_at_crosshair()
			charge_used = 0.0
		charge = 0.0
	elif Input.is_action_just_pressed("fire") and item.mag <= 0:
		fire_at_crosshair()                         # empty: clicks, then reloads


func _on_downed() -> void:
	if builder.active:
		builder.set_active(false)
	_quick_slot = -1
	_revive_target = null


func _on_reboot() -> void:
	for w in get_tree().get_nodes_in_group("world"):
		w.stop_spectating()
		if w.hud != null:
			w.hud.show_toast("REBOOTED")
	if camera != null:
		camera.make_current()
	_revive_target = null


var _revive_target = null
var _revive_t := 0.0


func begin_revive(target) -> void:
	if downed or target == null or not target.downed:
		return
	_revive_target = target
	_revive_t = 0.0


func _revive_hold(delta: float) -> bool:
	if _revive_target == null:
		return false
	if not is_instance_valid(_revive_target) or not _revive_target.downed or downed or is_dead \
			or not Input.is_action_pressed("interact") or global_transform.origin.distance_to(_revive_target.global_transform.origin) > INTERACT_RANGE + 0.6:
		_revive_target = null
		_revive_t = 0.0
		cancel_use()
		return false
	_revive_t += delta
	_use_total = REVIVE_TIME
	_use_left = max(0.01, REVIVE_TIME - _revive_t)              # the HUD's progress bar shows it
	if _revive_t >= REVIVE_TIME:
		var t = _revive_target
		_revive_target = null
		_revive_t = 0.0
		cancel_use()
		revive_other(t)
		emit_signal("picked_up", "Revived %s" % str(t.display_name))
	return true


func _interact_input(delta: float) -> void:
	if _revive_hold(delta):
		return
	_interact_t -= delta
	if _interact_t <= 0.0:
		_interact_t = 0.1
		interact_target = _find_interactable()
	if interact_target != null and Input.is_action_just_pressed("interact"):
		if is_instance_valid(interact_target) and interact_target.can_interact():
			interact_target.interact(self)
		interact_target = null
		_interact_t = 0.0


func _find_interactable():
	var best = null
	var best_d := INTERACT_RANGE
	var here := global_transform.origin
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n) or not n.can_interact():
			continue
		var d := here.distance_to(n.global_transform.origin + Vector3(0, 0.5, 0))
		if d < best_d and _can_reach(n):
			best_d = d
			best = n
	return best


# Nothing opens through a wall: the line from the player's chest to the thing must be clear of buildings and props.
func _can_reach(n) -> bool:
	var from := global_transform.origin + Vector3(0, 1.1, 0)
	var to: Vector3 = n.global_transform.origin + Vector3(0, 0.5, 0)
	var hit := get_world().direct_space_state.intersect_ray(from, to, [self], 1)
	if not hit:
		return true
	return from.distance_to(hit.position) > from.distance_to(to) - 0.7


func _on_hit_landed(_target, killed: bool, _headshot: bool) -> void:
	Audio.play2d("hitmarker", -4.0)
	if killed:
		Audio.play2d("kill_ding", -2.0)
	combat_until = OS.get_ticks_msec() / 1000.0 + 8.0


func _on_slot_changed() -> void:
	if _audio_ready:
		Audio.play2d("ui_slot", -8.0)


func _update_air_audio() -> void:
	var wind := Audio.SILENT_DB
	var glide := Audio.SILENT_DB
	if not is_dead:
		match mode:
			Mode.FREEFALL:
				wind = clamp(-16.0 + abs(velocity.y) * 0.25, -16.0, -3.0)
			Mode.GLIDE:
				glide = -10.0
				wind = -22.0
	Audio.ambient("wind_loop", wind)
	Audio.ambient("glider_loop", glide)


func _on_scroll(direction: int) -> void:
	if mode == Mode.GROUND and not is_dead and input_enabled:
		if builder.active:
			builder.cycle_material(direction)
		else:
			cycle_slot(direction)


func _process(delta: float) -> void:
	if head == null:
		return
	head.rotation.x = pitch
	# Camera rig per movement state: pulled back and up on the bus / in the air.
	var dist := CAMERA_DISTANCE
	var offset := SHOULDER_OFFSET
	match mode:
		Mode.BUS:
			dist = 17.0
			offset = Vector3(0.0, 5.5, 0.0)
		Mode.FREEFALL:
			dist = 6.5
			offset = Vector3(0.0, 1.6, 0.0)
		Mode.GLIDE:
			dist = 5.2
			offset = Vector3(0.0, 1.9, 0.0)
		Mode.VEHICLE:
			dist = 8.5
			offset = Vector3(0.0, 2.5, 0.0)
	var run_fov: float = 80.0 if (sprinting and mode == Mode.GROUND and speed_ratio() > 0.8) else (74.0 if mode == Mode.SWIM else 72.0)
	run_fov += float(Settings.pref("fov")) - 72.0
	var fov_rate := 5.0
	if aiming and selected_item() != null:      # zoom in over the shoulder, or right up to the eye behind a scope
		var sc: Dictionary = Items.scope_of(selected_item().id)
		run_fov = sc.fov
		dist = sc.dist
		offset = Vector3(0.0, 1.62, 0.0) if sc.kind == "scope" else Vector3(0.72, 1.5, 0.0)
	if mode == Mode.GROUND:
		fov_rate = 12.0
	if mode == Mode.GROUND:
		if sliding:
			offset.y -= 0.85
		elif crouching:
			offset.y -= 0.55
		if emoting:
			dist = 5.2
			offset = Vector3(0.0, 1.45, 0.0)
	var k: float = clamp((9.0 if mode == Mode.GROUND else 3.0) * delta, 0.0, 1.0)
	camera.fov = lerp(camera.fov, run_fov, clamp(fov_rate * delta, 0.0, 1.0))
	if model != null:
		model.visible = is_dead or not is_scoped()        # no body in the way of the scope view
	spring.spring_length = lerp(spring.spring_length, dist, k)
	head.translation = head.translation.linear_interpolate(offset, k)


func _look(delta: float) -> void:
	Controls.look_scale = Items.scope_of(selected_item().id).sens if (aiming and selected_item() != null) else 1.0
	var l := Controls.consume_look(delta)
	if l.length() > 0.002:
		_last_look_time = OS.get_ticks_msec() / 1000.0
	rotation.y -= l.x
	pitch = clamp(pitch - l.y, -1.15, 1.15)


func _can_aim() -> bool:
	return Controls.touch_mode or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func speed_ratio() -> float:
	return Vector2(velocity.x, velocity.z).length() / sprint_speed


func aim_origin_and_dir() -> Array:
	# Ray starts level with the character (not at the camera) so cover behind us
	# can't block shots, and runs along the camera's forward axis.
	var cam := camera.global_transform
	var fwd := -cam.basis.z
	var along: float = max(0.0, (head.global_transform.origin - cam.origin).dot(fwd))
	return [cam.origin + fwd * along, fwd]


func fire_at_crosshair() -> bool:
	var a := aim_origin_and_dir()
	return try_fire(a[0], a[1])

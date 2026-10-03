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
const EMOTE_LENGTH := 4.5
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
	camera.far = 520.0
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


func _swim_process(delta: float) -> void:
	var move := Controls.get_move() if input_enabled else Vector2.ZERO
	sprinting = input_enabled and Input.is_action_pressed("sprint") and move.length() > 0.2
	var b := global_transform.basis
	var wish := b.x * move.x + b.z * move.y
	swim_physics(delta, wish, 5.4 if sprinting else 3.4)
	aim_pitch = 0.0
	animate(delta)
	interact_target = null


func _ground_process(delta: float) -> void:
	var move := Vector2.ZERO
	var want_jump := false
	if input_enabled:
		move = Controls.get_move()
		want_jump = Input.is_action_pressed("jump")
		sprinting = Input.is_action_pressed("sprint") and move.length() > 0.2
		_update_aim()
		if Input.is_action_just_pressed("reload"):
			start_reload()
		if Input.is_action_just_pressed("build_toggle"):
			builder.toggle()
		for i in range(BUILD_ACTIONS.size()):
			if Input.is_action_just_pressed(BUILD_ACTIONS[i]):
				press_piece(i)
		if Input.is_action_just_pressed("pickaxe"):          # F: the pickaxe
			if builder.active:
				builder.set_active(false)
			select_slot(0)
		for i in range(1, Items.SLOT_COUNT):                 # 1-4: the item slots, in order
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
	if input_enabled and want_jump and move.y < -0.3 and try_mantle(-b.z * -move.y + b.x * move.x):
		return
	if input_enabled and not grounded and move.y < -0.3 and try_mantle(-b.z):
		return                             # jumped / fell against a ledge: grab it
	_update_stance(delta, move, want_jump)
	if emoting:
		move = Vector2.ZERO
	if gadget_selected("jetpack") and input_enabled and mode == Mode.GROUND and Input.is_action_pressed("jump"):
		_jet_hold += delta
	else:
		_jet_hold = 0.0
	jet_active = _jet_hold > 0.2                   # a tap is a normal jump; holding lights the jetpack
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
	if sliding:
		_slide_t -= delta
		if _slide_t <= 0.0 or want_jump or not grounded:
			sliding = false
	elif input_enabled and Input.is_action_just_pressed("crouch") and sprinting and grounded and flat_speed > 5.5:
		sliding = true
		_slide_t = SLIDE_TIME
		_slide_dir = Vector3(velocity.x, 0.0, velocity.z).normalized()
		Audio.play3d("skid", global_transform.origin, -6.0, 1.4)
	crouching = input_enabled and Input.is_action_pressed("crouch") and grounded and not sliding
	if sliding or crouching:
		sprinting = false
	if emoting:
		emote_t += delta
		if move.length() > 0.2 or want_jump or Input.is_action_pressed("fire") or sliding or emote_t > EMOTE_LENGTH:
			emoting = false
	elif input_enabled and Input.is_action_just_pressed("emote") and grounded and not sliding and not crouching and not aiming \
			and move.length() < 0.2 and not builder.active:
		emoting = true
		emote_t = 0.0
		cancel_use()


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
	if Controls.edit_aim:             # the build editor owns the fire button (it selects tiles)
		cancel_use()
		return
	if builder.active:
		if Input.is_action_just_pressed("fire") and _can_aim():
			builder.place()
		cancel_use()
		return
	var item = selected_item()
	if item != null and item.kind == "weapon" and Items.WEAPONS[item.id].has("charge"):
		_charge_input(delta, item)
		return
	var firing := Input.is_action_pressed("fire") and _can_aim()
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
	if automatic or Input.is_action_just_pressed("fire"):
		if fire_at_crosshair() and item.kind == "weapon":
			pitch += rand_range(0.0, 0.006) * (3.0 if pellets > 1 or item.id == "sniper" else 1.0)
			rotation.y += rand_range(-0.003, 0.003)


# Charge Shotgun: hold fire to charge (up to 50% more damage, tighter spread), release to shoot.
func _charge_input(delta: float, item) -> void:
	var def: Dictionary = Items.WEAPONS[item.id]
	var holding := Input.is_action_pressed("fire") and _can_aim()
	var ready: bool = mode == Mode.GROUND and _fire_cd <= 0.0 and _reload_left <= 0.0 and _use_left <= 0.0 and item.mag > 0
	if holding and ready:
		var before := charge
		charge = min(1.0, charge + delta / float(def.charge))
		if before == 0.0:
			Audio.play2d("charge_start", -8.0)
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


func _interact_input(delta: float) -> void:
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

extends VehicleBody
# Wheeled vehicle (buggy / quad bike) built on VehicleBody. The model's Wheel* objects are
# reparented under VehicleWheel nodes so they steer, spin and ride the suspension.

const Common = preload("res://scripts/VehicleCommon.gd")

# Godot's VehicleBody pushes toward -Z / +Z depending on the build; the vehicle test checks this.
const ENGINE_SIGN := -1.0

export var kind := "buggy"

var title := "Buggy"
var health := 320.0
var max_health := 320.0
var exploded := false
var is_dead := false
var last_attacker = null
var occupants := [null, null]
var seat_offsets := [Vector3(-0.4, 0.5, 0.2), Vector3(0.4, 0.5, 0.2)]
var input_move := Vector2.ZERO        # set by the driver each frame (x right, y back)
var handbrake := false
var boost := false
var top_speed := 28.0
var max_engine := 2600.0
var max_steer := 0.5
var model: Spatial
var net_id := ""
var net_owner := 0                 # another machine is driving: we only follow it
var _net_xf := Transform()
var _net_has := false
var steer_visual := 0.0
var fuel := 100.0                   # see VehicleCommon.burn_fuel
var low_warned := false

var _engine_snd: AudioStreamPlayer3D
var _prev_speed := 0.0
var _run_over_t := 0.0
var _skid_t := 0.0
var _wheels := []


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("interactable")
	collision_layer = 8
	collision_mask = 1 | 8
	title = Common.TITLES[kind]
	var wheel_radius := 0.45
	var half := Vector3(0.85, 0.42, 1.75)
	var com_y := 0.55
	if kind == "quad":
		mass = 260.0
		health = 180.0
		max_health = 180.0
		top_speed = 24.0
		max_engine = 1500.0
		max_steer = 0.55
		wheel_radius = 0.38
		half = Vector3(0.6, 0.4, 0.95)
		seat_offsets = [Vector3(0, 0.5, 0.45)]
		occupants = [null]
	else:
		mass = 650.0
		health = 320.0
		max_health = 320.0
	var shape := BoxShape.new()
	shape.extents = half
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 0.85, 0.0)
	add_child(cs)
	var scene = load("res://assets/models/%s.glb" % kind)
	model = scene.instance() if scene != null else Spatial.new()
	add_child(model)
	var wheel_nodes := []
	for c in model.get_children():
		if c.name.begins_with("Wheel"):
			wheel_nodes.append(c)
	for wn in wheel_nodes:
		var pos: Vector3 = wn.translation
		model.remove_child(wn)
		var w := VehicleWheel.new()
		w.name = wn.name
		w.translation = Vector3(pos.x, wheel_radius + 0.2, pos.z)
		w.wheel_radius = wheel_radius
		w.wheel_rest_length = 0.2
		w.suspension_travel = 0.35
		w.suspension_stiffness = 42.0
		w.suspension_max_force = 9000.0
		w.damping_compression = 1.6
		w.damping_relaxation = 1.9
		w.wheel_friction_slip = 4.5
		w.wheel_roll_influence = 0.25
		var front: bool = pos.z < 0.0                     # forward is -Z
		w.use_as_steering = front
		w.use_as_traction = true
		wn.translation = Vector3.ZERO
		w.add_child(wn)
		add_child(w)
		_wheels.append(w)
	_engine_snd = Audio.make_loop3d("engine_quad_loop" if kind == "quad" else "engine_car_loop", self, -60.0, 140.0)
	Items_tint()


func Items_tint() -> void:
	# paint variety: tint the accent surfaces
	var Items = load("res://scripts/Items.gd")
	var palette := [Color(0.9, 0.35, 0.1), Color(0.15, 0.55, 0.85), Color(0.85, 0.15, 0.2), Color(0.2, 0.7, 0.35), Color(0.9, 0.75, 0.1)]
	Items.apply_accent(model, palette[get_instance_id() % palette.size()])


# --- interaction ---------------------------------------------------------------

func can_interact() -> bool:
	return Common.can_interact(self)


func prompt_text() -> String:
	return Common.prompt(self)


func prompt_color() -> Color:
	return Color(0.45, 0.9, 1.0)


func interact(by) -> void:
	Common.interact(self, by)


func seat_position(seat: int) -> Vector3:
	return Common.seat_position(self, seat)


func exit_position(seat: int) -> Vector3:
	return Common.exit_position(self, seat)


func release_seat(seat: int) -> void:
	Common.release(self, seat)


func take_damage(amount: float, source = null) -> void:
	Common.take_damage(self, amount, source)


func forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z)


# --- driving -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if net_owner != 0:
		Common.net_follow(self, delta)
		return
	var speed := linear_velocity.length()
	var driver = occupants[0]
	var driven: bool = driver != null and is_instance_valid(driver) and not exploded
	if exploded or global_transform.origin.y < -3.0:
		engine_force = 0.0
		brake = 3.0
		_set_engine_sound(false, 0.0, 0.0)
		if not exploded and global_transform.origin.y < -3.0:
			Common.explode(self)
		return
	var thr := 0.0
	var st := 0.0
	var hb := false
	if driven:
		thr = -input_move.y
		st = input_move.x
		hb = handbrake
		if not Common.burn_fuel(self, thr, boost, delta):
			thr = 0.0                                    # the tank is empty: coast
	var fwd := forward_speed()
	var boost_mult := 1.5 if (boost and driven) else 1.0
	var br := 0.0
	var eng := 0.0
	if thr > 0.05:
		if fwd < -1.0:
			br = 40.0 * thr                              # braking while rolling backwards
		else:
			eng = thr * max_engine * boost_mult * clamp(1.0 - fwd / (top_speed * boost_mult), 0.0, 1.0)
	elif thr < -0.05:
		if fwd > 1.5:
			br = 40.0 * -thr                             # braking
		else:
			eng = thr * max_engine * 0.55                # reverse
	else:
		br = 2.5 if driven else 6.0                      # engine braking / parked
	if hb:
		br = 70.0
	engine_force = ENGINE_SIGN * eng
	brake = br
	var limit: float = lerp(max_steer, 0.16, clamp(speed / 26.0, 0.0, 1.0))
	steering = lerp(steering, -st * limit, clamp(7.0 * delta, 0.0, 1.0))
	steer_visual = steering

	# crash damage from sudden deceleration
	var drop := _prev_speed - speed
	if drop > 9.0 and _prev_speed > 11.0:
		Audio.play3d("vehicle_crash", global_transform.origin, 2.0, rand_range(0.9, 1.1))
		Common.take_damage(self, drop * 5.0, null)
		for o in occupants:
			if o != null and is_instance_valid(o):
				o.take_damage(drop * 1.2, null)
	_prev_speed = speed

	# skid sound when sliding hard
	_skid_t -= delta
	if hb and speed > 8.0 and _skid_t <= 0.0:
		_skid_t = 0.6
		Audio.play3d("skid", global_transform.origin, -4.0)

	_run_over_t -= delta
	if _run_over_t <= 0.0 and speed > 5.0:
		_run_over_t = 0.1
		_run_over(speed, driver)

	_set_engine_sound(driven, abs(thr), speed)


func _set_engine_sound(driven: bool, thr: float, speed: float) -> void:
	if _engine_snd == null:
		return
	if driven:
		_engine_snd.unit_db = lerp(-9.0, -1.0, clamp(thr, 0.0, 1.0))
		_engine_snd.pitch_scale = lerp(0.65, 2.0, clamp(speed / top_speed, 0.0, 1.0))
	else:
		_engine_snd.unit_db = -60.0


func _run_over(speed: float, driver) -> void:
	var b := global_transform
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.is_dead or f.mode == 6 or f == driver:
			continue
		var local: Vector3 = b.xform_inv(f.global_transform.origin)
		if local.z < 0.4 and local.z > -2.6 and abs(local.x) < 1.35 and abs(local.y) < 2.0 and forward_speed() > 4.0:
			f.take_damage(speed * 3.2, driver)
			Audio.play3d("hit_flesh", f.global_transform.origin + Vector3(0, 1, 0), 2.0)

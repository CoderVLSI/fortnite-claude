extends RigidBody
# Motor boat: a rigid body with buoyancy, thrust, steering torque and water drag. It only
# accelerates while its hull is in the water.

const Common = preload("res://scripts/VehicleCommon.gd")
const WATER_LEVEL := 0.0

export var kind := "boat"

var title := "Motor Boat"
var health := 260.0
var max_health := 260.0
var exploded := false
var is_dead := false
var last_attacker = null
var occupants := [null, null]
var seat_offsets := [Vector3(-0.4, 0.55, 0.55), Vector3(0.4, 0.55, 0.55)]
var input_move := Vector2.ZERO
var handbrake := false
var boost := false
var top_speed := 20.0
var steering := 0.0
var model: Spatial
var net_id := ""
var net_owner := 0                 # another machine is driving: we only follow it
var _net_xf := Transform()
var _net_has := false

var _engine_snd: AudioStreamPlayer3D
var _prev_speed := 0.0


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("interactable")
	collision_layer = 8
	collision_mask = 1 | 8
	mass = 420.0
	linear_damp = 0.4
	angular_damp = 2.5
	title = Common.TITLES["boat"]
	var shape := BoxShape.new()
	shape.extents = Vector3(0.85, 0.5, 2.3)
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 0.55, 0)
	add_child(cs)
	var scene = load("res://assets/models/boat.glb")
	model = scene.instance() if scene != null else Spatial.new()
	add_child(model)
	_engine_snd = Audio.make_loop3d("engine_boat_loop", self, -60.0, 140.0)


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
	var p := Common.exit_position(self, seat)
	p.y = max(p.y, WATER_LEVEL + 0.2)
	return p


func release_seat(seat: int) -> void:
	Common.release(self, seat)


func take_damage(amount: float, source = null) -> void:
	Common.take_damage(self, amount, source)


func forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z)


func _physics_process(delta: float) -> void:
	if net_owner != 0:
		Common.net_follow(self, delta)
		return
	var driver = occupants[0]
	var driven: bool = driver != null and is_instance_valid(driver) and not exploded
	var t := global_transform
	var depth: float = WATER_LEVEL - t.origin.y + 0.05          # how deep the hull sits
	var in_water := depth > -0.25
	if exploded:
		_engine_snd.unit_db = -60.0
		return
	var thr := -input_move.y if driven else 0.0
	var st := input_move.x if driven else 0.0
	if in_water:
		# buoyancy with vertical damping
		var lift: float = mass * 9.8 * clamp(depth * 1.9, 0.0, 2.0)
		add_central_force(Vector3(0, lift, 0))
		add_central_force(Vector3(0, -linear_velocity.y * mass * 3.0, 0))
		# thrust and rudder
		var boost_mult := 1.45 if (boost and driven) else 1.0
		var fwd := forward_speed()
		var push: float = clamp(1.0 - fwd / (top_speed * boost_mult), 0.0, 1.0)
		if abs(thr) > 0.05:
			add_central_force(-t.basis.z * thr * 3900.0 * boost_mult * (push if thr > 0.0 else 0.6))
		var speed_factor: float = clamp(abs(fwd) / 8.0, 0.15, 1.0)
		add_torque(Vector3(0, -st * 1700.0 * speed_factor * sign(fwd if abs(fwd) > 0.5 else 1.0), 0))
		# sideways drag so the boat tracks, plus a little roll while turning
		var lateral := t.basis.x.dot(linear_velocity)
		add_central_force(-t.basis.x * lateral * mass * 2.4)
		if handbrake:
			add_central_force(-linear_velocity * mass * 1.2)
		# self-righting
		var up_err := t.basis.y.cross(Vector3.UP)
		add_torque(up_err * mass * 14.0 - angular_velocity * mass * 0.9 * Vector3(1, 0, 1))
	var speed := linear_velocity.length()
	var drop := _prev_speed - speed
	if drop > 8.0 and _prev_speed > 10.0:
		Audio.play3d("vehicle_crash", t.origin, 0.0)
		Common.take_damage(self, drop * 4.0, null)
	_prev_speed = speed
	if _engine_snd:
		if driven:
			_engine_snd.unit_db = lerp(-9.0, -1.0, clamp(abs(thr), 0.0, 1.0))
			_engine_snd.pitch_scale = lerp(0.7, 1.9, clamp(speed / top_speed, 0.0, 1.0))
		else:
			_engine_snd.unit_db = -60.0

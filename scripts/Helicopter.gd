extends RigidBody
# Helicopter: parked on helipads. Interact to board (pilot first, then two passengers). The pilot flies with
# W/S (forward / back), A/D (turn), Space (climb), Ctrl (descend), Shift (boost). Gravity is cancelled while someone is at
# the controls; with no pilot, or an empty tank, it sinks (an empty tank gives a slow emergency descent).

const Common = preload("res://scripts/VehicleCommon.gd")

export var kind := "helicopter"

const CEILING := 230.0
const CRUISE := 24.0
const CLIMB := 9.0

var title := "Helicopter"
var health := 500.0
var max_health := 500.0
var exploded := false
var is_dead := false
var last_attacker = null
var occupants := [null, null, null]
var seat_offsets := [Vector3(-0.45, 0.2, -0.55), Vector3(0.45, 0.2, -0.55), Vector3(0.0, 0.2, 0.7)]
var input_move := Vector2.ZERO        # x right, y back (set by the pilot each frame)
var handbrake := false                # Space: climb
var descend := false                  # Ctrl
var boost := false
var fuel := 100.0
var low_warned := false
var steer_visual := 0.0
var model: Spatial
var net_id := ""
var net_owner := 0
var _net_xf := Transform()
var _net_has := false
var _rotor: Spatial
var _tail: Spatial
var _spin := 0.0
var _prev_speed := 0.0
var _tilt: Spatial
var _engine_snd: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("interactable")
	collision_layer = 8
	collision_mask = 1 | 8
	mass = 900.0
	linear_damp = 0.05
	angular_damp = 6.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	title = Common.TITLES["helicopter"]
	var shape := BoxShape.new()
	shape.extents = Vector3(1.1, 0.95, 2.3)
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 1.0, 0.2)
	add_child(cs)
	_build_model()
	_engine_snd = Audio.make_loop3d("engine_car_loop", self, -60.0, 200.0)


func _box(parent: Node, size: Vector3, pos: Vector3, color: Color, metal := 0.4) -> MeshInstance:
	var m := MeshInstance.new()
	var c := CubeMesh.new()
	c.size = size
	m.mesh = c
	var mat := SpatialMaterial.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.5
	m.material_override = mat
	m.translation = pos
	parent.add_child(m)
	return m


func _build_model() -> void:
	model = Spatial.new()
	add_child(model)
	_tilt = Spatial.new()
	model.add_child(_tilt)
	var palette := [Color(0.85, 0.2, 0.15), Color(0.15, 0.45, 0.8), Color(0.9, 0.7, 0.1), Color(0.2, 0.6, 0.35)]
	var body_col: Color = palette[get_instance_id() % palette.size()]
	var dark := Color(0.16, 0.17, 0.2)
	_box(_tilt, Vector3(1.9, 1.35, 3.0), Vector3(0, 1.25, 0.2), body_col)                  # cabin
	var nose := _box(_tilt, Vector3(1.7, 1.0, 1.0), Vector3(0, 1.1, -1.7), body_col)      # nose
	nose.rotation.x = deg2rad(-12.0)
	var glass := _box(_tilt, Vector3(1.75, 0.8, 1.1), Vector3(0, 1.55, -1.55), Color(0.35, 0.6, 0.8, 0.8), 0.9)
	glass.rotation.x = deg2rad(-18.0)
	(glass.material_override as SpatialMaterial).flags_transparent = true
	_box(_tilt, Vector3(0.45, 0.45, 3.2), Vector3(0, 1.55, 3.0), body_col)                  # tail boom
	_box(_tilt, Vector3(0.18, 1.3, 0.7), Vector3(0, 2.1, 4.5), body_col)                    # fin
	_box(_tilt, Vector3(0.7, 0.14, 0.45), Vector3(0, 1.6, 4.3), dark)                      # tailplane
	_box(_tilt, Vector3(0.5, 0.35, 0.8), Vector3(0, 2.1, 0.0), dark)                       # engine hump / mast base
	_box(_tilt, Vector3(0.12, 0.6, 0.12), Vector3(0, 2.4, 0.0), dark)                      # mast
	for sx in [-0.9, 0.9]:                                                                # skids
		_box(_tilt, Vector3(0.12, 0.12, 3.4), Vector3(sx, 0.18, 0.1), dark)
		_box(_tilt, Vector3(0.1, 0.55, 0.1), Vector3(sx, 0.45, -0.8), dark)
		_box(_tilt, Vector3(0.1, 0.55, 0.1), Vector3(sx, 0.45, 1.0), dark)
	_rotor = Spatial.new()
	_rotor.translation = Vector3(0, 2.75, 0)
	_tilt.add_child(_rotor)
	_box(_rotor, Vector3(8.4, 0.05, 0.28), Vector3.ZERO, dark, 0.2)                       # two crossed blades
	_box(_rotor, Vector3(0.28, 0.05, 8.4), Vector3.ZERO, dark, 0.2)
	_tail = Spatial.new()
	_tail.translation = Vector3(0.25, 2.2, 4.5)
	_tilt.add_child(_tail)
	_box(_tail, Vector3(0.05, 1.3, 0.12), Vector3.ZERO, dark, 0.2)


func can_interact() -> bool:
	return not exploded and net_owner == 0 and Common.free_seat(self) >= 0 and linear_velocity.length() < 4.0 and global_transform.origin.y < CEILING


func prompt_text() -> String:
	return ("Fly " if Common.free_seat(self) == 0 else "Ride ") + title


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


func altitude() -> float:
	return global_transform.origin.y


func _physics_process(delta: float) -> void:
	if net_owner != 0:
		Common.net_follow(self, delta)
		_animate(delta, true, 0.5)
		return
	if exploded:
		_set_sound(false, 0.0)
		return
	var pilot = occupants[0]
	var driven: bool = pilot != null and is_instance_valid(pilot)
	var powered := false
	var thr := 0.0
	if driven:
		thr = -input_move.y
		powered = Common.burn_fuel(self, max(abs(thr), 1.0 if (handbrake or descend) else 0.0) * 0.8, boost, delta)
	if powered:
		gravity_scale = 0.0
		var speed_cap: float = CRUISE * (1.5 if boost else 1.0)
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var target := fwd * thr * speed_cap
		var vy := 0.0
		if handbrake and global_transform.origin.y < CEILING:
			vy = CLIMB
		elif descend:
			vy = -CLIMB
		target.y = vy
		var k: float = 1.0 - exp(-1.6 * delta)
		linear_velocity = linear_velocity.linear_interpolate(target, k)
		angular_velocity = Vector3(0, -input_move.x * 1.1, 0)
		steer_visual = lerp(steer_visual, input_move.x, clamp(4.0 * delta, 0.0, 1.0))
	else:
		gravity_scale = 1.0 if not driven else 0.35
		if driven:                                                  # out of fuel: a slow glide down
			linear_velocity.y = max(linear_velocity.y, -6.0)
		angular_velocity = Vector3(0, angular_velocity.y * 0.9, 0)
		steer_visual = lerp(steer_visual, 0.0, clamp(3.0 * delta, 0.0, 1.0))
	# crash damage from a sudden stop
	var speed := linear_velocity.length()
	var drop := _prev_speed - speed
	if drop > 8.0 and _prev_speed > 11.0:
		Audio.play3d("vehicle_crash", global_transform.origin, 2.0)
		Common.take_damage(self, drop * 9.0, null)
		for o in occupants:
			if o != null and is_instance_valid(o):
				o.take_damage(drop * 1.5, null)
	_prev_speed = speed
	if global_transform.origin.y < -3.0:
		Common.explode(self)
		return
	_animate(delta, powered, abs(thr))
	_set_sound(powered, speed)


func _animate(delta: float, running: bool, _thr: float) -> void:
	var rate: float = 40.0 if running else 0.0
	_spin = lerp(_spin, rate, clamp(1.5 * delta, 0.0, 1.0))
	if _rotor != null:
		_rotor.rotation.y += _spin * delta
	if _tail != null:
		_tail.rotation.x += _spin * 1.4 * delta
	if _tilt != null:                                              # lean into the flight
		var f := forward_speed()
		_tilt.rotation.x = lerp(_tilt.rotation.x, clamp(-f / 70.0, -0.3, 0.3), clamp(3.0 * delta, 0.0, 1.0))
		_tilt.rotation.z = lerp(_tilt.rotation.z, clamp(-steer_visual * 0.2, -0.25, 0.25), clamp(3.0 * delta, 0.0, 1.0))


func _set_sound(on: bool, speed: float) -> void:
	if _engine_snd == null:
		return
	if on:
		_engine_snd.unit_db = -2.0
		_engine_snd.pitch_scale = lerp(0.55, 0.9, clamp(speed / CRUISE, 0.0, 1.0))
	else:
		_engine_snd.unit_db = -60.0

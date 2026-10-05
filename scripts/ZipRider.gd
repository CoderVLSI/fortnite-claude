extends Spatial
# The trolley that carries one person along a zipline. It borrows the vehicle interface (occupants, seat_position, exit_position,
# release_seat, linear_velocity, exploded) so Player's vehicle mode drives everything else.

const ACCEL := 14.0
const TOP_SPEED := 19.0
const HANG := 2.0                 # how far below the cable the rider's feet hang

var line
var from_end := 0
var kind := "zipline"
var title := "Zipline"
var occupants := [null]
var seat_offsets := [Vector3(0, -HANG, 0)]
var input_move := Vector2.ZERO
var handbrake := false
var boost := false
var exploded := false
var is_dead := false
var net_id := ""
var net_owner := 0
var linear_velocity := Vector3.ZERO
var finished := false
var progress := 0.0              # metres travelled
var speed := 0.0
var _src := Vector3.ZERO
var _dst := Vector3.ZERO
var _len := 1.0


func _ready() -> void:
	add_to_group("zip_riders")
	_src = line.a if from_end == 0 else line.b
	_dst = line.b if from_end == 0 else line.a
	_len = max(0.1, _src.distance_to(_dst))
	var d := (_dst - _src).normalized()
	global_transform = Transform(Basis.IDENTITY, _src).looking_at(_src + d, Vector3.UP)
	var m := MeshInstance.new()                              # the little wheel block on the cable
	var cm := CubeMesh.new()
	cm.size = Vector3(0.25, 0.2, 0.5)
	m.mesh = cm
	add_child(m)
	var handle := MeshInstance.new()
	var hm := CubeMesh.new()
	hm.size = Vector3(0.7, 0.07, 0.07)
	handle.mesh = hm
	handle.translation = Vector3(0, -0.45, 0)
	add_child(handle)
	Audio.play3d("door", _src, 0.0, 1.4)


func can_interact() -> bool:
	return false


func forward_speed() -> float:
	return speed


func _physics_process(delta: float) -> void:
	if finished:
		return
	var rider = occupants[0]
	if rider == null or not is_instance_valid(rider) or rider.is_dead or rider.mode != rider.Mode.VEHICLE or rider.vehicle != self:
		_end(false)
		return
	speed = min(TOP_SPEED, speed + ACCEL * delta)
	progress += speed * delta
	var dir := (_dst - _src) / _len
	linear_velocity = dir * speed
	if progress >= _len:
		global_transform.origin = _dst
		_end(true)
		return
	global_transform.origin = _src + dir * progress
	if handbrake:                                  # jump: let go
		rider.exit_vehicle(true)
		return


func seat_position(_seat: int) -> Vector3:
	return global_transform.origin + Vector3(0, -HANG, 0)


# Mid-cable you simply drop from where you hang; at the pole you step down to the ground.
func exit_position(_seat: int) -> Vector3:
	var p := global_transform.origin + Vector3(0, -HANG, 0)
	if progress >= _len - 0.01:
		var space := get_world().direct_space_state
		var hit = space.intersect_ray(_dst + Vector3(0, 0.5, 0), _dst + Vector3(0, -12.0, 0), [], 1)
		if hit:
			p = hit.position + Vector3(0, 0.1, 0) + (_dst - _src).normalized() * 1.2
	return p


func release_seat(seat: int) -> void:
	if seat == 0:
		occupants[0] = null
	_finish()


func _end(arrived: bool) -> void:
	var rider = occupants[0]
	if rider != null and is_instance_valid(rider) and rider.mode == rider.Mode.VEHICLE and rider.vehicle == self:
		if arrived:
			linear_velocity = Vector3.ZERO
		rider.exit_vehicle(false)
	_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	remove_from_group("zip_riders")
	call_deferred("queue_free")

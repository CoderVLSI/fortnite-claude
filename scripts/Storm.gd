extends Spatial
# Shrinking safe zone. Phases alternate "waiting" (circle fixed, next circle
# shown on the minimap) and "shrinking" (circle moves/contracts). Anyone
# outside the circle takes damage every second.

const PHASES := [
	{"wait": 35.0, "shrink": 30.0, "radius": 100.0, "dps": 1.0},
	{"wait": 28.0, "shrink": 25.0, "radius": 62.0, "dps": 2.0},
	{"wait": 22.0, "shrink": 22.0, "radius": 34.0, "dps": 4.0},
	{"wait": 18.0, "shrink": 18.0, "radius": 15.0, "dps": 7.0},
	{"wait": 12.0, "shrink": 14.0, "radius": 4.0, "dps": 10.0},
]
const WALL_HEIGHT := 140.0

var center := Vector2.ZERO
var radius := 150.0
var phase := 0
var waiting := true
var time_left := 0.0
var damage_per_second := 0.0
var next_center := Vector2.ZERO
var next_radius := 100.0
var finished := false
var active := true          # false while the battle bus is still flying

var _from_center := Vector2.ZERO
var _from_radius := 0.0
var _rng: RandomNumberGenerator
var _tick := 0.0
var _wall: MeshInstance


func setup(start_radius: float, rng: RandomNumberGenerator) -> void:
	radius = start_radius
	_rng = rng
	add_to_group("storm")
	_build_wall()
	_begin_wait()


func _begin_wait() -> void:
	waiting = true
	time_left = PHASES[phase].wait
	next_radius = PHASES[phase].radius
	var spread: float = max(0.0, radius - next_radius)
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * spread
	next_center = center + Vector2(cos(a), sin(a)) * r
	damage_per_second = PHASES[phase].dps


func _begin_shrink() -> void:
	waiting = false
	time_left = PHASES[phase].shrink
	_from_center = center
	_from_radius = radius


func _process(delta: float) -> void:
	if finished or not active:
		return
	time_left -= delta
	if not waiting:
		var t: float = clamp(1.0 - time_left / PHASES[phase].shrink, 0.0, 1.0)
		center = _from_center.linear_interpolate(next_center, t)
		radius = lerp(_from_radius, next_radius, t)
	if time_left <= 0.0:
		if waiting:
			_begin_shrink()
		else:
			center = next_center
			radius = next_radius
			phase += 1
			if phase >= PHASES.size():
				finished = true
				time_left = 0.0
			else:
				_begin_wait()
	_update_wall()

	_tick += delta
	if _tick >= 1.0:
		_tick -= 1.0
		for f in get_tree().get_nodes_in_group("fighters"):
			if not f.is_dead and not is_inside(f.global_transform.origin):
				f.take_damage(damage_per_second, null)
				if f.is_in_group("player"):
					Audio.play2d("storm_hit", -4.0)


func is_inside(p: Vector3) -> bool:
	return Vector2(p.x - center.x, p.z - center.y).length() <= radius


func center_3d(y: float) -> Vector3:
	return Vector3(center.x, y, center.y)


func skip_to(target_phase: int) -> void:
	# Debug / test helper: jump straight to the start of a phase's waiting period.
	phase = int(clamp(target_phase, 0, PHASES.size() - 1))
	if phase > 0:
		radius = PHASES[phase - 1].radius
	finished = false
	_begin_wait()
	_update_wall()


func status_text() -> String:
	if not active:
		return "Battle bus in flight"
	if finished:
		return "Final circle"
	var secs := int(ceil(max(time_left, 0.0)))
	var clock := "%d:%02d" % [secs / 60, secs % 60]
	if waiting:
		return "Storm closing in " + clock
	return "Storm shrinking! " + clock


func _build_wall() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 72
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var top := Vector3(0, WALL_HEIGHT, 0)
		var low := Color(0.62, 0.28, 1.0, 0.50)
		var high := Color(0.62, 0.28, 1.0, 0.04)
		for v in [[p0, low], [p1, low], [p1 + top, high], [p0, low], [p1 + top, high], [p0 + top, high]]:
			st.add_color(v[1])
			st.add_vertex(v[0])
	var mat := SpatialMaterial.new()
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.vertex_color_use_as_albedo = true
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mat.flags_do_not_receive_shadows = true
	_wall = MeshInstance.new()
	_wall.name = "StormWall"
	_wall.mesh = st.commit()
	_wall.material_override = mat
	_wall.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_wall.translation.y = -20.0
	add_child(_wall)
	_update_wall()


func _update_wall() -> void:
	if _wall:
		_wall.translation = Vector3(center.x, -20.0, center.y)
		_wall.scale = Vector3(radius, 1.0, radius)

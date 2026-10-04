extends Node
# Weather: now and then a rain storm rolls over the island. The grey light, fog and falling rain are cosmetic (the storm circle is
# the real danger). The timetable comes from the match seed, so every machine in a game gets the same sky.

const Perf = preload("res://scripts/Perf.gd")

var world
var env: Environment
var rain: CPUParticles
var intensity := 0.0            # 0 clear .. 1 downpour
var timetable := []             # [[start, end], ...] in seconds since the match began
var clock := 0.0
var enabled := true
var _base_sun := 0.95
var _base_ambient := 0.7
var _base_fog_color := Color(0.74, 0.85, 0.96)
var _last_end := -1.0
var _perf_end := 380.0
var _flash := 0.0
var _next_thunder := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("weather")
	var rr := RandomNumberGenerator.new()
	rr.seed = world.SEED + 31
	var t := rr.randf_range(100.0, 200.0)
	for i in range(8):
		var dur := rr.randf_range(60.0, 130.0)
		timetable.append([t, t + dur])
		t += dur + rr.randf_range(150.0, 330.0)
	_rng.randomize()
	for c in world.get_children():
		if c is WorldEnvironment:
			env = c.environment
	if world.sun != null:
		_base_sun = world.sun.light_energy
	if env != null:
		_base_ambient = env.ambient_light_energy
		_base_fog_color = env.fog_color
		_perf_end = env.fog_depth_end
	_build_rain()


func _build_rain() -> void:
	rain = CPUParticles.new()
	rain.emitting = false
	rain.amount = 160 if world.profile.mobile else 420
	rain.lifetime = 0.9
	rain.preprocess = 0.5
	rain.local_coords = false
	rain.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(16, 0.5, 16)
	rain.direction = Vector3(0.12, -1, 0.05)
	rain.spread = 3.0
	rain.initial_velocity = 28.0
	rain.gravity = Vector3(0, -10, 0)
	var mesh := CubeMesh.new()
	mesh.size = Vector3(0.012, 0.55, 0.012)
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
	mesh.material = mat
	rain.mesh = mesh
	rain.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


func raining() -> bool:
	return intensity > 0.05


# 0..1 target for the clock: ramps in over six seconds at the start of a storm and out over six at the end.
func target_at(t: float) -> float:
	for w in timetable:
		if t >= w[0] and t <= w[1]:
			return clamp(min(t - w[0], w[1] - t) / 6.0, 0.0, 1.0)
	return 0.0


func _process(delta: float) -> void:
	if world == null or env == null:
		return
	enabled = bool(Settings.pref("weather"))
	clock += delta
	var want: float = target_at(clock) if enabled else 0.0
	intensity = move_toward(intensity, want, delta * 0.25)
	var k := intensity
	# rain follows the camera
	var cam: Camera = get_viewport().get_camera()
	rain.emitting = k > 0.05
	if cam != null and rain.emitting:
		rain.global_transform.origin = cam.global_transform.origin + Vector3(0, 12, 0)
	rain.amount = int(clamp(float(rain.amount), 10.0, 600.0))
	# the sky goes grey (the Perf governor may have shortened the view: build on whatever it set)
	if abs(env.fog_depth_end - _last_end) > 0.01:
		_perf_end = env.fog_depth_end
	var grey := Color(0.5, 0.54, 0.6)
	env.fog_color = _base_fog_color.linear_interpolate(grey, k * 0.8)
	env.fog_depth_end = _perf_end * (1.0 - 0.35 * k)
	_last_end = env.fog_depth_end
	var flash: float = max(0.0, _flash)
	_flash -= delta * 3.0
	env.ambient_light_energy = _base_ambient * (1.0 - 0.3 * k) + flash * 1.5
	if world.sun != null:
		world.sun.light_energy = _base_sun * (1.0 - 0.45 * k) + flash * 0.8
	var rain_db: float = lerp(Audio.SILENT_DB, -9.0, k) if k > 0.05 else Audio.SILENT_DB
	Audio.ambient("rain_loop", rain_db)
	if k > 0.7 and clock > _next_thunder:
		_next_thunder = clock + _rng.randf_range(14.0, 40.0)
		_flash = 1.0
		get_tree().create_timer(_rng.randf_range(0.4, 2.0)).connect("timeout", self, "_thunder")


func _thunder() -> void:
	Audio.play2d("thunder", -4.0)

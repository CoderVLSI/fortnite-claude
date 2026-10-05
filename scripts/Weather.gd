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
# Day and night: the match starts mid-morning and a game hour lasts HOUR_SECONDS, so a normal match runs into the evening and the night.
const HOUR_SECONDS := 75.0
var start_hour := 10.0
var sky: ProceduralSky
var fog_windows := []           # [[start, end]] thick fog banks
var fog := 0.0                  # 0 clear .. 1 thick fog
var _sky_t := 99.0
var _fog_told := false
var _fog_perf_begin := 150.0


func _ready() -> void:
	add_to_group("weather")
	var rr := RandomNumberGenerator.new()
	rr.seed = world.SEED + 31
	var t := rr.randf_range(100.0, 200.0)
	for i in range(8):
		var dur := rr.randf_range(60.0, 130.0)
		timetable.append([t, t + dur])
		t += dur + rr.randf_range(150.0, 330.0)
	start_hour = 9.5 + rr.randf() * 2.0
	var tf := rr.randf_range(240.0, 420.0)
	for i in range(3):
		var dur2 := rr.randf_range(70.0, 130.0)
		fog_windows.append([tf, tf + dur2])
		tf += dur2 + rr.randf_range(260.0, 480.0)
	_rng.randomize()
	for c in world.get_children():
		if c is WorldEnvironment:
			env = c.environment
			if env.background_sky is ProceduralSky:
				sky = env.background_sky
	if world.sun != null:
		_base_sun = world.sun.light_energy
	if env != null:
		_fog_perf_begin = env.fog_depth_begin
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


# ---- time of day
# Game hour 0..24 (6 = sunrise, 12 = noon, 18 = sunset).
func hour() -> float:
	var mode := int(Settings.pref("day_night"))
	if mode == 1:
		return 11.0
	if mode == 2:
		return 0.5
	return fmod(start_hour + clock / HOUR_SECONDS, 24.0)


func sun_height(h: float) -> float:
	return sin((h - 6.0) / 12.0 * PI)           # 1 at noon, 0 at sunrise / sunset, negative at night


# Everything the sky needs at hour h: sun / moon energy and colour, ambient, fog and sky colours.
func look_at_hour(h: float) -> Dictionary:
	var el := sun_height(h)
	var day: float = clamp((el + 0.12) / 0.5, 0.0, 1.0)                    # 0 night .. 1 full day
	var warm: float = clamp(1.0 - abs(el) / 0.45, 0.0, 1.0) * (1.0 if el > -0.25 else 0.0)   # sunrise / sunset glow
	var top_day := Color(0.22, 0.48, 0.92)
	var hor_day := Color(0.72, 0.84, 0.96)
	var top := Color(0.03, 0.05, 0.14).linear_interpolate(top_day, day).linear_interpolate(Color(0.38, 0.3, 0.62), warm * 0.8)
	var hor := Color(0.09, 0.11, 0.22).linear_interpolate(hor_day, day).linear_interpolate(Color(1.0, 0.56, 0.3), warm * 0.85)
	var sun_col := Color(0.55, 0.65, 1.0).linear_interpolate(Color(1.0, 0.97, 0.9), day).linear_interpolate(Color(1.0, 0.62, 0.36), warm * 0.8)
	return {
		"sun": lerp(0.22, 0.95, day),
		"ambient": lerp(0.34, 0.7, day),
		"ambient_col": Color(0.3, 0.38, 0.6).linear_interpolate(Color(0.62, 0.70, 0.82), day),
		"fog": hor,
		"top": top,
		"sun_col": sun_col,
		"pitch": -lerp(38.0, 62.0, clamp(el, 0.0, 1.0)) if el > 0.0 else -38.0,
		"yaw": -35.0 + (h - 12.0) * 11.0,
		"day": day,
	}


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
	enabled = bool(Settings.pref("weather")) and not bool(Settings.pref("battery_saver"))
	clock += delta
	var want: float = target_at(clock) if enabled else 0.0
	intensity = move_toward(intensity, want, delta * 0.25)
	var k := intensity
	# time of day
	var look := look_at_hour(hour())
	_base_sun = look.sun
	_base_ambient = look.ambient
	_base_fog_color = look.fog
	env.ambient_light_color = look.ambient_col
	if world.sun != null:
		world.sun.light_color = look.sun_col
		world.sun.rotation_degrees = Vector3(look.pitch, look.yaw, 0.0)
	_sky_t += delta
	if sky != null and _sky_t > 3.0:                        # the sky texture is rebuilt on every change: only now and then
		_sky_t = 0.0
		sky.sky_top_color = look.top
		sky.sky_horizon_color = look.fog
		sky.ground_horizon_color = look.fog
		sky.ground_bottom_color = look.top.linear_interpolate(Color(0.25, 0.38, 0.5), look.day * 0.6)
	# fog banks
	var fog_want := 0.0
	if enabled:
		for fw in fog_windows:
			if clock >= fw[0] and clock <= fw[1]:
				fog_want = clamp(min(clock - fw[0], fw[1] - clock) / 10.0, 0.0, 1.0)
	fog = move_toward(fog, fog_want, delta * 0.2)
	if fog > 0.5 and not _fog_told:
		_fog_told = true
		if world.hud != null:
			world.hud.show_toast("Thick fog rolls in")
	elif fog < 0.1:
		_fog_told = false
	# rain follows the camera
	var cam: Camera = get_viewport().get_camera()
	rain.emitting = k > 0.05
	if cam != null and rain.emitting:
		rain.global_transform.origin = cam.global_transform.origin + Vector3(0, 12, 0)
	# the sky goes grey (the Perf governor may have shortened the view: build on whatever it set)
	if abs(env.fog_depth_end - _last_end) > 0.01:
		_perf_end = env.fog_depth_end
	var grey := Color(0.5, 0.54, 0.6)
	env.fog_color = _base_fog_color.linear_interpolate(grey, k * 0.8).linear_interpolate(Color(0.78, 0.8, 0.84) * (0.35 + 0.65 * look.day), fog * 0.85)
	env.fog_depth_end = lerp(_perf_end * (1.0 - 0.35 * k), 95.0, fog)
	env.fog_depth_begin = lerp(_fog_perf_begin, 12.0, fog)
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

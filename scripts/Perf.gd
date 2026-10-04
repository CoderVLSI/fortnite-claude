extends Node
# Keeps the frame rate up on modest GPUs:
#  * distance culling: loot, chests, vehicles, sprites, rifts and far-away fighters are not drawn (or lit) beyond a radius,
#  * an automatic governor that lowers the graphics (shadows -> antialiasing -> view distance -> culling radius)
#    when the game runs slowly for a few seconds, and says so in a toast. Settings > Graphics > Auto-adjust turns it off.

const CULL_INTERVAL := 0.35
const GOVERN_WINDOW := 4.0
const SLOW_FPS := 30.0

var world
var level := 0                    # 0 = as chosen, 1 = shadows off, 2 = + no antialiasing, 3 = + short view, 4 = + tight culling
var scale := 1.0                  # multiplies every culling radius
# The view distance as chosen (and shortened by the governor); the higher you are, the further you can see (_apply_altitude).
var base_far := 460.0
var base_begin := 150.0
var base_end := 380.0
var _alt_a := -1.0
var _cull_t := 0.0
var _gov_t := 0.0
var _gov_frames := 0
var _grace := 6.0                 # ignore the first seconds (loading hitches)
var radius := {"interactable": 130.0, "fighters": 170.0, "rifts": 220.0, "structures": 330.0, "scenery": 260.0, "wildlife": 110.0}


func setup(w) -> void:
	world = w
	name = "Perf"
	pause_mode = Node.PAUSE_MODE_STOP


# One toast when the game is clearly not on a real graphics card (a laptop's built-in chip, or software rendering).
func _check_adapter() -> void:
	var a := VisualServer.get_video_adapter_name().to_lower()
	var weak: bool = ("intel" in a and not "arc" in a) or "llvmpipe" in a or "basic render" in a or "software" in a or "uhd" in a
	if weak and world.hud != null and OS.get_name() == "Windows":
		world.hud.show_toast("Running on %s - see Settings > Graphics > High-performance GPU" % VisualServer.get_video_adapter_name())


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	_apply_altitude()
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = CULL_INTERVAL
		cull()
	if Settings.auto_graphics:
		_govern(delta)


func cull() -> void:
	var cam := get_viewport().get_camera()
	if cam == null:
		return
	var cp: Vector3 = cam.global_transform.origin
	for group in radius:
		var r: float = radius[group] * scale
		var r_in: float = r * 0.9
		for n in get_tree().get_nodes_in_group(group):
			if n.is_in_group("player") or n.is_in_group("remote_players") or not (n is Spatial):
				continue
			var d: float = n.global_transform.origin.distance_to(cp)
			if n is GeometryInstance:        # a chunk of trees / rocks: measure to its box, not to the origin
				var box: AABB = n.get_transformed_aabb()
				d = max(0.0, box.get_center().distance_to(cp) - box.size.length() * 0.5)
			var show: bool = d < r_in if not n.visible else d < r      # a little hysteresis so things at the edge do not flicker
			if n.visible != show:
				n.visible = show


func _govern(delta: float) -> void:
	if _grace > 0.0:
		_grace -= delta
		if _grace <= 0.0:
			_check_adapter()
		return
	_gov_t += delta
	_gov_frames += 1
	if _gov_t < GOVERN_WINDOW:
		return
	var fps := float(_gov_frames) / _gov_t
	_gov_t = 0.0
	_gov_frames = 0
	if fps < SLOW_FPS and level < 4:
		step_down(fps)


func step_down(fps: float = 0.0) -> void:
	level += 1
	var what := ""
	match level:
		1:
			world.profile["force_no_shadows"] = true
			what = "shadows off"
		2:
			Settings.quality = 0
			what = "antialiasing off"
		3:
			what = "shorter view distance"
			_set_view(300.0)
		4:
			what = "far objects hidden sooner"
			scale = 0.6
			_set_view(220.0)
	world.apply_quality()
	Settings.save_settings()
	if world.hud != null:
		world.hud.show_toast("Running slowly (%d FPS): %s" % [int(fps), what])


func _set_view(far: float) -> void:
	base_far = far + 40.0
	base_begin = far * 0.35
	base_end = far
	_alt_a = -1.0                      # re-apply with the new base
	_apply_altitude()


# From the battle bus, or gliding, the whole island has to be visible: fog and the far plane grow with height above the ground.
func _apply_altitude() -> void:
	var p = world.player
	if p == null or p.camera == null or world.terrain == null:
		return
	var o: Vector3 = p.global_transform.origin
	var alt: float = o.y - world.terrain.height_at(o.x, o.z)
	var a: float = clamp((alt - 20.0) / 120.0, 0.0, 1.0)
	if is_equal_approx(a, _alt_a):
		return
	_alt_a = a
	p.camera.far = base_far + a * 1400.0
	for c in world.get_children():
		if c is WorldEnvironment and c.environment != null:
			c.environment.fog_depth_begin = base_begin + a * 900.0
			c.environment.fog_depth_end = base_end + a * 1700.0

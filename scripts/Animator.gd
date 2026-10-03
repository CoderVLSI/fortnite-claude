extends Reference
# Procedural full-body animation for the jointed character rig (see tools/blender).
# Every frame the pose function for the fighter's state fills target rotations for the
# joints; the targets are then smoothed so transitions blend instead of snapping.
#
# Rotation conventions (Godot, character faces -Z):
#   shoulder.x  + raises the arm forward (1.57 = horizontal, PI = overhead)
#   shoulder.z  + swings the right arm outward (left arm uses the opposite sign)
#   shoulder.y  + swings an arm toward -X  (so it crosses the body for the right arm)
#   elbow.x     + bends the forearm up / forward
#   hip.x       + swings the leg forward;   knee.x - bends the shin backwards
#   spine.x     - leans the torso forward;  head.x + looks up

const GROUND := 0
const BUS := 1
const FREEFALL := 2
const GLIDE := 3
const SWIM := 4
const MANTLE := 5
const VEHICLE := 6

const JOINTS := ["Hips", "Spine", "Head", "ShoulderL", "ElbowL", "HandL", "ShoulderR", "ElbowR", "HandR",
	"HipL", "KneeL", "HipR", "KneeR"]

var nodes := {}
var cur := {}
var tgt := {}
var hips_rest := Vector3.ZERO
var hips_target_y := 0.0
var held_rot := Vector3.ZERO
var held_pos := Vector3.ZERO

var t := 0.0
var phase := 0.0
var swim_phase := 0.0
var speed_smooth := 0.0
var aim_blend := 0.0
var recoil := 0.0
var land_squash := 0.0
var was_grounded := true
var last_fall_speed := 0.0
var rate := 16.0


func setup(model: Spatial) -> void:
	for n in JOINTS:
		var node := model.find_node(n, true, false)
		if node:
			nodes[n] = node
			cur[n] = Vector3.ZERO
			tgt[n] = Vector3.ZERO
	if nodes.has("Hips"):
		hips_rest = nodes["Hips"].translation


func kick(amount: float = 1.0) -> void:
	recoil = min(1.5, recoil + amount)


func _to(joint: String, rot: Vector3) -> void:
	tgt[joint] = rot


func _out(side: String) -> float:
	return 1.0 if side == "R" else -1.0


func update(f, delta: float) -> void:
	if nodes.empty():
		return
	t += delta
	for n in JOINTS:
		tgt[n] = Vector3.ZERO
	hips_target_y = 0.0
	held_rot = Vector3.ZERO
	held_pos = Vector3.ZERO
	recoil = max(0.0, recoil - delta * 6.0)
	land_squash = max(0.0, land_squash - delta * 4.0)

	var flat_speed := Vector2(f.velocity.x, f.velocity.z).length()
	speed_smooth = lerp(speed_smooth, flat_speed, clamp(10.0 * delta, 0.0, 1.0))
	if f.grounded and not was_grounded and last_fall_speed < -6.0:
		land_squash = clamp(-last_fall_speed / 16.0, 0.2, 1.0)
	was_grounded = f.grounded
	last_fall_speed = f.velocity.y

	if f.is_dead:
		_pose_dead(f)
	else:
		match f.mode:
			FREEFALL:
				_pose_freefall(f)
			GLIDE:
				_pose_glide(f)
			SWIM:
				_pose_swim(f, delta)
			MANTLE:
				_pose_mantle(f)
			VEHICLE:
				_pose_vehicle(f)
			_:
				_pose_ground(f, delta)

	if f.held != null:       # items are only visible when the character is on foot (and not mid-dance)
		f.held.visible = (f.is_dead or f.mode == GROUND or f.mode == MANTLE) and not f.emoting
	var k := 1.0 - exp(-rate * delta)
	for n in JOINTS:
		cur[n] = cur[n].linear_interpolate(tgt[n], k)
		nodes[n].rotation = cur[n]
	nodes["Hips"].translation = hips_rest + Vector3(0, hips_target_y, 0)
	if f.held != null:
		f.held.rotation = f.held.rotation.linear_interpolate(held_rot, 1.0 - exp(-24.0 * delta))
		f.held.translation = f.held.translation.linear_interpolate(held_pos, 1.0 - exp(-24.0 * delta))


# ------------------------------------------------------------------ ground

func _pose_ground(f, delta: float) -> void:
	var item = f.selected_item()
	var spd: float = speed_smooth
	var run: float = clamp((spd - 3.2) / 5.0, 0.0, 1.0)
	var moving := spd > 0.5
	var sprinting: bool = f.sprinting and moving

	if not f.grounded:
		_pose_airborne(f, item)
		return
	if f.emoting:
		_pose_emote(f)
		return
	if f.sliding:
		_pose_slide(f)
		return

	# locomotion cycle (negative speed along facing = backpedal)
	var dir := 1.0
	if abs(f.forward_speed) > 0.4:
		dir = sign(f.forward_speed)
	if moving:
		var before := sin(phase)
		phase += delta * spd * 2.0 * dir
		if sign(before) != sign(sin(phase)) and spd > 1.2:
			f.footstep(spd)
	var amp: float = lerp(0.30, 0.95, clamp(spd / 8.0, 0.0, 1.0))
	var s := sin(phase)
	var c := cos(phase)
	var w: float = clamp(spd / 2.0, 0.0, 1.0)         # walk weight (0 when standing still)

	_to("HipL", Vector3(s * amp * w, 0, 0))
	_to("HipR", Vector3(-s * amp * w, 0, 0))
	_to("KneeL", Vector3(-(0.10 + w * (0.15 + 0.9 * run) * max(0.0, c) + 0.05 * w), 0, 0))
	_to("KneeR", Vector3(-(0.10 + w * (0.15 + 0.9 * run) * max(0.0, -c) + 0.05 * w), 0, 0))
	hips_target_y = -0.03 * w - abs(s) * 0.035 * w * (0.5 + run) - land_squash * 0.22
	var lean := 0.04 + 0.16 * run
	var spine_x := -lean - 0.02 * sin(t * 1.6) * (1.0 - w)
	var hips_yaw := s * 0.12 * w * (0.4 + run)
	var hip_rot := Vector3(-land_squash * 0.25, hips_yaw, sin(t * 0.7) * 0.02 * (1.0 - w))
	_to("Hips", hip_rot)
	_to("Spine", Vector3(spine_x - land_squash * 0.3, -hips_yaw * 1.4, 0))
	_to("Head", Vector3(clamp(f.aim_pitch * 0.55, -0.7, 0.7) - spine_x * 0.8, -hips_yaw * 0.4, 0))
	if land_squash > 0.0:
		_to("HipL", Vector3(0.9 * land_squash, 0, 0))
		_to("HipR", Vector3(0.9 * land_squash, 0, 0))
		_to("KneeL", Vector3(-1.5 * land_squash, 0, 0))
		_to("KneeR", Vector3(-1.5 * land_squash, 0, 0))

	var armed: bool = item != null and item.kind == "weapon"
	var target_aim := 0.0
	if armed and not sprinting:
		target_aim = 1.0
	aim_blend = lerp(aim_blend, target_aim, clamp(8.0 * delta, 0.0, 1.0))

	# --- arms ------------------------------------------------------------------
	var swing := s * 0.55 * w * (0.5 + run)
	var free_l := Vector3(-swing, 0, -0.06)
	var free_r := Vector3(swing, 0, 0.06)
	var elbow_free := 0.25 + 0.75 * run * w
	_to("ShoulderL", free_l)
	_to("ShoulderR", free_r)
	_to("ElbowL", Vector3(elbow_free, 0, 0))
	_to("ElbowR", Vector3(elbow_free, 0, 0))
	if item != null:
		match item.kind:
			"weapon":
				_pose_weapon(f, item, sprinting, run, w, s)
			"pickaxe":
				_pose_pickaxe(f, swing, elbow_free)
			"consumable":
				_pose_consume(f, item)
	if f.crouching:                                  # squat: hips down, thighs forward, knees folded
		hips_target_y = -0.42 - land_squash * 0.1
		_to("HipL", Vector3(1.0 + s * 0.15 * w, 0, 0))
		_to("HipR", Vector3(1.0 - s * 0.15 * w, 0, 0))
		_to("KneeL", Vector3(-1.85, 0, 0))
		_to("KneeR", Vector3(-1.85, 0, 0))


# The emote on the wheel that is playing (f.emote_id): each is a looping or one-shot pose driven by the clock `t`.
func _pose_emote(f) -> void:
	match f.emote_id:
		"wave":
			_pose_wave(f)
		"floss":
			_pose_floss()
		"robot":
			_pose_robot()
		"twirl":
			_pose_twirl()
		"flex":
			_pose_flex(f)
		"cheer":
			_pose_cheer()
		"sit":
			_pose_sit()
		_:
			_pose_boogie()


# Knees pumping, arms alternating overhead, hips swaying.
func _pose_boogie() -> void:
	var beat := t * 7.0
	var s := sin(beat)
	hips_target_y = -0.10 - abs(sin(beat)) * 0.16
	_to("Hips", Vector3(0, sin(beat * 0.5) * 0.35, sin(beat) * 0.10))
	_to("Spine", Vector3(-0.05, -sin(beat * 0.5) * 0.30, -sin(beat) * 0.08))
	_to("Head", Vector3(sin(beat) * 0.12, sin(beat * 0.5) * 0.4, 0))
	_to("HipL", Vector3(0.45 + s * 0.45, 0, 0))
	_to("HipR", Vector3(0.45 - s * 0.45, 0, 0))
	_to("KneeL", Vector3(-0.9 - s * 0.5, 0, 0))
	_to("KneeR", Vector3(-0.9 + s * 0.5, 0, 0))
	_to("ShoulderL", Vector3(2.5 + s * 0.35, 0, 0.35))
	_to("ShoulderR", Vector3(2.5 - s * 0.35, 0, -0.35))
	_to("ElbowL", Vector3(0.7 - s * 0.4, 0, 0))
	_to("ElbowR", Vector3(0.7 + s * 0.4, 0, 0))


# One arm up, waving from the elbow; the other relaxed.
func _pose_wave(f) -> void:
	var w := sin(t * 11.0)
	hips_target_y = 0.0
	_to("Hips", Vector3(0, 0.12, 0))
	_to("Spine", Vector3(0, 0.08, 0))
	_to("Head", Vector3(0, 0.25, 0.12))
	_to("ShoulderR", Vector3(2.7, 0, -0.55))
	_to("ElbowR", Vector3(0.5 + w * 0.55, 0, 0))
	_to("ShoulderL", Vector3(0.05, 0, 0.1))
	_to("ElbowL", Vector3(0.15, 0, 0))
	for j in ["HipL", "HipR", "KneeL", "KneeR"]:
		_to(j, Vector3.ZERO)


# Hips swinging side to side while the arms swing the opposite way.
func _pose_floss() -> void:
	var b := t * 9.0
	var s := sin(b)
	hips_target_y = -0.16
	_to("Hips", Vector3(0, 0, s * 0.30))
	_to("Spine", Vector3(0.12, 0, -s * 0.20))
	_to("Head", Vector3(0.05, 0, 0))
	_to("HipL", Vector3(0.35, 0, 0.1 * s))
	_to("HipR", Vector3(0.35, 0, 0.1 * s))
	_to("KneeL", Vector3(-0.7, 0, 0))
	_to("KneeR", Vector3(-0.7, 0, 0))
	_to("ShoulderL", Vector3(-0.2, 0, 0.35 - s * 0.9))
	_to("ShoulderR", Vector3(-0.2, 0, -0.35 - s * 0.9))
	_to("ElbowL", Vector3(0.1, 0, 0))
	_to("ElbowR", Vector3(0.1, 0, 0))


# Jerky, stepped robot moves: the pose snaps every half beat.
func _pose_robot() -> void:
	var k := int(floor(t * 4.0)) % 4
	hips_target_y = -0.05 - (0.05 if k % 2 == 0 else 0.0)
	_to("Hips", Vector3(0, [0.0, 0.5, 0.0, -0.5][k], 0))
	_to("Spine", Vector3(0, [0.0, -0.4, 0.0, 0.4][k], 0))
	_to("Head", Vector3(0, [0.5, 0.0, -0.5, 0.0][k], 0))
	_to("ShoulderL", Vector3([1.57, 2.4, 1.57, 0.2][k], 0, 0.2))
	_to("ElbowL", Vector3([1.57, 0.0, 1.57, 1.57][k], 0, 0))
	_to("ShoulderR", Vector3([0.2, 1.57, 2.4, 1.57][k], 0, -0.2))
	_to("ElbowR", Vector3([1.57, 1.57, 0.0, 1.57][k], 0, 0))
	_to("HipL", Vector3([0.3, 0.0, 0.3, 0.0][k], 0, 0))
	_to("HipR", Vector3([0.0, 0.3, 0.0, 0.3][k], 0, 0))
	_to("KneeL", Vector3([-0.5, 0.0, -0.5, 0.0][k], 0, 0))
	_to("KneeR", Vector3([0.0, -0.5, 0.0, -0.5][k], 0, 0))


# Arms out, spinning round and round.
func _pose_twirl() -> void:
	hips_target_y = -0.04 - abs(sin(t * 3.0)) * 0.05
	_to("Hips", Vector3(0, t * 5.5, 0))
	_to("Spine", Vector3(0, 0, sin(t * 3.0) * 0.08))
	_to("Head", Vector3(-0.1, 0, 0))
	_to("ShoulderL", Vector3(0, 0, 1.45))
	_to("ShoulderR", Vector3(0, 0, -1.45))
	_to("ElbowL", Vector3(0.1, 0, 0))
	_to("ElbowR", Vector3(0.1, 0, 0))
	_to("HipL", Vector3(0.1, 0, 0.1))
	_to("HipR", Vector3(0.1, 0, -0.1))
	_to("KneeL", Vector3(-0.2, 0, 0))
	_to("KneeR", Vector3(-0.2, 0, 0))


# Both arms up with bent elbows; a slow pump of the chest.
func _pose_flex(f) -> void:
	var p := sin(t * 5.0) * 0.08
	hips_target_y = -0.06
	_to("Hips", Vector3(0, 0, 0))
	_to("Spine", Vector3(-0.1 + p, 0, 0))
	_to("Head", Vector3(-0.12, 0, 0))
	_to("ShoulderL", Vector3(0.3, 0, 1.55 + p))
	_to("ShoulderR", Vector3(0.3, 0, -1.55 - p))
	_to("ElbowL", Vector3(2.3, 0, 0))
	_to("ElbowR", Vector3(2.3, 0, 0))
	_to("HipL", Vector3(0.0, 0, 0.18))
	_to("HipR", Vector3(0.0, 0, -0.18))
	_to("KneeL", Vector3(-0.15, 0, 0))
	_to("KneeR", Vector3(-0.15, 0, 0))


# Hopping on the spot with both arms in the air.
func _pose_cheer() -> void:
	var h := abs(sin(t * 6.0))
	hips_target_y = 0.05 + h * 0.22
	_to("Hips", Vector3(0, 0, 0))
	_to("Spine", Vector3(-0.1, 0, sin(t * 6.0) * 0.06))
	_to("Head", Vector3(-0.2, 0, 0))
	_to("ShoulderL", Vector3(2.9, 0, 0.3 + h * 0.3))
	_to("ShoulderR", Vector3(2.9, 0, -0.3 - h * 0.3))
	_to("ElbowL", Vector3(0.2, 0, 0))
	_to("ElbowR", Vector3(0.2, 0, 0))
	_to("HipL", Vector3(0.3 - h * 0.3, 0, 0.1))
	_to("HipR", Vector3(0.3 - h * 0.3, 0, -0.1))
	_to("KneeL", Vector3(-0.6 + h * 0.5, 0, 0))
	_to("KneeR", Vector3(-0.6 + h * 0.5, 0, 0))


# Sitting on an invisible chair, one foot tapping.
func _pose_sit() -> void:
	hips_target_y = -0.62
	_to("Hips", Vector3(0, 0, 0))
	_to("Spine", Vector3(-0.1, 0, 0))
	_to("Head", Vector3(0.05, sin(t * 1.4) * 0.25, 0))
	_to("HipL", Vector3(1.5, 0, 0.12))
	_to("HipR", Vector3(1.5, 0, -0.12))
	_to("KneeL", Vector3(-1.5 + max(0.0, sin(t * 7.0)) * 0.25, 0, 0))
	_to("KneeR", Vector3(-1.5, 0, 0))
	_to("ShoulderL", Vector3(0.7, 0, 0.25))
	_to("ShoulderR", Vector3(0.7, 0, -0.25))
	_to("ElbowL", Vector3(1.2, 0, 0))
	_to("ElbowR", Vector3(1.2, 0, 0))


# Sliding: leaning back with one leg out in front.
func _pose_slide(f) -> void:
	hips_target_y = -0.62
	_to("Hips", Vector3(0.25, 0, 0))
	_to("Spine", Vector3(0.55, 0, 0))
	_to("Head", Vector3(-0.35, 0, 0))
	_to("HipL", Vector3(1.45, 0, 0))
	_to("KneeL", Vector3(-0.1, 0, 0))
	_to("HipR", Vector3(0.65, 0, 0))
	_to("KneeR", Vector3(-1.5, 0, 0))
	_to("ShoulderL", Vector3(0.9, 0, 0.5))
	_to("ShoulderR", Vector3(0.9, 0, -0.5))
	_to("ElbowL", Vector3(0.5, 0, 0))
	_to("ElbowR", Vector3(0.5, 0, 0))


func _pose_weapon(f, item, sprinting: bool, run: float, w: float, s: float) -> void:
	var pitch: float = f.aim_pitch
	var kick := recoil
	# ready pose (blend with the lowered sprint pose)
	var ready_r := Vector3(1.28 + pitch * 0.9 + kick * 0.16, 0.10, 0.0)
	var ready_er := Vector3(0.38 - kick * 0.1, 0, 0)
	var ready_l := Vector3(1.20 + pitch * 0.9 + kick * 0.14, -0.58, 0.0)
	var ready_el := Vector3(0.95, 0, 0)
	var low_r := Vector3(0.55 + s * 0.12 * w, 0.0, 0.08)
	var low_er := Vector3(1.05, 0, 0)
	var low_l := Vector3(0.45 + s * 0.12 * w, -0.35, -0.05)
	var low_el := Vector3(1.15, 0, 0)
	var a := aim_blend
	_to("ShoulderR", low_r.linear_interpolate(ready_r, a))
	_to("ElbowR", low_er.linear_interpolate(ready_er, a))
	_to("ShoulderL", low_l.linear_interpolate(ready_l, a))
	_to("ElbowL", low_el.linear_interpolate(ready_el, a))
	var is_long: bool = item.id == "assault" or item.id == "sniper" or item.id == "shotgun" or item.id == "charge_shotgun"
	if not is_long:                       # pistols / SMGs are held a bit higher, with one hand relaxed
		if item.id == "pistol":
			_to("ShoulderL", Vector3(0.12 - s * 0.45 * w, 0, -0.06).linear_interpolate(Vector3(1.0, -0.4, 0), a * 0.0))
			_to("ElbowL", Vector3(0.3, 0, 0))
	# reload: left hand drops to the magazine and back, gun tilts
	if f.is_reloading():
		var r: float = 1.0 - f.reload_fraction_left()
		var bump := sin(clamp(r, 0.0, 1.0) * PI)
		_to("ShoulderL", Vector3(1.20 - 0.95 * bump + pitch * 0.5, -0.30 * bump - 0.2, 0))
		_to("ElbowL", Vector3(0.95 + 0.6 * bump, 0, 0))
		_to("Head", Vector3(-0.35 * bump, 0, 0))
		held_rot.z = 0.45 * bump
		held_rot.x = -0.25 * bump
	# the weapon is parented to the right hand: undo the arm's rotation so it stays level and
	# follows the aim pitch
	var arm_x: float = cur["ShoulderR"].x + cur["ElbowR"].x
	held_rot.x += -arm_x + pitch + (0.0 if a > 0.5 else -0.5 * (1.0 - a))
	held_pos = Vector3(0.0, -0.02, -0.04 + kick * 0.05)
	held_rot.y = -cur["ShoulderR"].y * 0.8
	_to("Spine", Vector3(tgt["Spine"].x - kick * 0.04, tgt["Spine"].y - 0.18 * a, 0))


func _pose_pickaxe(f, swing: float, elbow_free: float) -> void:
	# carried on the shoulder-ish; swing is a wind-up then a strike
	_to("ShoulderR", Vector3(0.65 + swing * 0.3, 0.0, 0.1))
	_to("ElbowR", Vector3(0.95, 0, 0))
	var sw: float = f.swing_fraction()
	var arm_x: float = cur["ShoulderR"].x + cur["ElbowR"].x
	held_rot.x = -arm_x + 0.9
	held_pos = Vector3(0, -0.02, -0.04)
	if sw > 0.0:
		var p := 1.0 - sw                     # 0 -> 1 over the swing
		var wind: float = clamp(p / 0.35, 0.0, 1.0)
		var strike: float = clamp((p - 0.35) / 0.4, 0.0, 1.0)
		var ang: float = lerp(-2.2, 1.7, strike) * (1.0 if p > 0.35 else 1.0)
		if p <= 0.35:
			ang = lerp(0.65, -2.2, wind)
		_to("ShoulderR", Vector3(ang, 0.0, 0.1))
		_to("ElbowR", Vector3(lerp(0.9, 0.2, strike), 0, 0))
		_to("Spine", Vector3(tgt["Spine"].x - 0.25 * strike, 0.4 * (1.0 - strike) - 0.5 * strike, 0))
		held_rot.x = -(ang + tgt["ElbowR"].x) + 1.3


func _pose_consume(f, item) -> void:
	var prog: float = f.use_progress()
	var using: bool = f.is_using()
	var up := 1.0 if using else 0.5
	_to("ShoulderR", Vector3(0.95 + 0.3 * up, 0.30, 0.05))
	_to("ElbowR", Vector3(1.35 + 0.55 * up, 0, 0))
	_to("ShoulderL", Vector3(0.5, -0.3, -0.05))
	_to("ElbowL", Vector3(1.0, 0, 0))
	if using:
		_to("Head", Vector3(0.3 * sin(t * 6.0) * 0.1 + 0.12, 0, 0))
		_to("Spine", Vector3(-0.06 + 0.02 * sin(t * 9.0), 0, 0))
	var arm_x: float = tgt["ShoulderR"].x + tgt["ElbowR"].x
	held_rot.x = -arm_x + 1.5
	held_pos = Vector3(0, -0.03, -0.04)


func _pose_airborne(f, item) -> void:
	var up: float = clamp(f.velocity.y / 8.0, -1.0, 1.0)
	_to("HipL", Vector3(0.55 + 0.2 * up, 0, 0))
	_to("HipR", Vector3(-0.1, 0, 0))
	_to("KneeL", Vector3(-1.0 + 0.3 * up, 0, 0))
	_to("KneeR", Vector3(-0.35, 0, 0))
	_to("Spine", Vector3(-0.06, 0, 0))
	if item != null and item.kind == "weapon":
		_to("ShoulderR", Vector3(1.2 + f.aim_pitch * 0.8, 0.1, 0.1))
		_to("ElbowR", Vector3(0.4, 0, 0))
		_to("ShoulderL", Vector3(1.1 + f.aim_pitch * 0.8, -0.55, 0))
		_to("ElbowL", Vector3(0.95, 0, 0))
		var arm_x: float = tgt["ShoulderR"].x + tgt["ElbowR"].x
		held_rot.x = -arm_x + f.aim_pitch
	else:
		_to("ShoulderL", Vector3(0.4 + 0.5 * up, 0, -0.55))
		_to("ShoulderR", Vector3(0.4 + 0.5 * up, 0, 0.55))
		_to("ElbowL", Vector3(0.5, 0, 0))
		_to("ElbowR", Vector3(0.5, 0, 0))


# ------------------------------------------------------------------ special states

func _pose_freefall(f) -> void:
	var dive: bool = f.air_input.y < -0.5
	_to("ShoulderL", Vector3(-0.6 if dive else 0.3, 0, -1.25))
	_to("ShoulderR", Vector3(-0.6 if dive else 0.3, 0, 1.25))
	_to("ElbowL", Vector3(0.35, 0, 0))
	_to("ElbowR", Vector3(0.35, 0, 0))
	_to("HipL", Vector3(-0.2 - 0.1 * sin(t * 14.0), 0, -0.12))
	_to("HipR", Vector3(-0.2 + 0.1 * sin(t * 14.0), 0, 0.12))
	_to("KneeL", Vector3(-0.3, 0, 0))
	_to("KneeR", Vector3(-0.3, 0, 0))
	_to("Head", Vector3(0.55, 0, 0))
	_to("Spine", Vector3(0.12, 0, 0))


func _pose_glide(f) -> void:
	_to("ShoulderL", Vector3(2.75, 0, -0.30))
	_to("ShoulderR", Vector3(2.75, 0, 0.30))
	_to("ElbowL", Vector3(0.1, 0, 0))
	_to("ElbowR", Vector3(0.1, 0, 0))
	_to("HipL", Vector3(0.15 + 0.05 * sin(t * 2.0), 0, 0))
	_to("HipR", Vector3(0.05 - 0.05 * sin(t * 2.0), 0, 0))
	_to("KneeL", Vector3(-0.25, 0, 0))
	_to("KneeR", Vector3(-0.15, 0, 0))
	_to("Head", Vector3(0.25, 0, 0))
	hips_target_y = 0.0


func _pose_swim(f, delta: float) -> void:
	var spd: float = speed_smooth
	var moving: bool = spd > 0.8
	swim_phase += delta * (3.0 + spd * 1.2)
	var s := sin(swim_phase)
	if moving and sign(s) != f._stroke_sign:
		f._stroke_sign = sign(s)
		f.swim_stroke()
	if moving:       # freestyle: arms alternate over the head, legs flutter-kick
		var a: float = swim_phase
		_to("ShoulderL", Vector3(-2.6 + 2.8 * sin(a), 0, -0.2))
		_to("ShoulderR", Vector3(-2.6 + 2.8 * sin(a + PI), 0, 0.2))
		_to("ElbowL", Vector3(0.2 + 0.7 * max(0.0, cos(a)), 0, 0))
		_to("ElbowR", Vector3(0.2 + 0.7 * max(0.0, -cos(a)), 0, 0))
		_to("HipL", Vector3(0.25 * sin(a * 2.0), 0, 0))
		_to("HipR", Vector3(-0.25 * sin(a * 2.0), 0, 0))
		_to("KneeL", Vector3(-0.3 - 0.2 * max(0.0, sin(a * 2.0)), 0, 0))
		_to("KneeR", Vector3(-0.3 - 0.2 * max(0.0, -sin(a * 2.0)), 0, 0))
		_to("Head", Vector3(0.9, 0, 0))
		_to("Spine", Vector3(0.05, sin(a) * 0.15, 0))
	else:            # treading water: scull with the arms
		_to("ShoulderL", Vector3(0.5 + 0.3 * s, 0, -0.9))
		_to("ShoulderR", Vector3(0.5 - 0.3 * s, 0, 0.9))
		_to("ElbowL", Vector3(0.7, 0, 0))
		_to("ElbowR", Vector3(0.7, 0, 0))
		_to("HipL", Vector3(0.3 * s, 0, -0.1))
		_to("HipR", Vector3(-0.3 * s, 0, 0.1))
		_to("KneeL", Vector3(-0.5 - 0.3 * max(0.0, s), 0, 0))
		_to("KneeR", Vector3(-0.5 - 0.3 * max(0.0, -s), 0, 0))
		hips_target_y = 0.04 * sin(t * 2.2)
	if f.held != null:
		held_rot = Vector3(0, 0, 0)


func _pose_mantle(f) -> void:
	var m: float = f.mantle_fraction()          # 0 = reaching, 1 = up and over
	var reach: float = clamp(1.0 - m * 1.6, 0.0, 1.0)
	var push: float = clamp((m - 0.35) / 0.4, 0.0, 1.0)
	_to("ShoulderL", Vector3(2.7 * reach + 1.2 * (1.0 - reach) * (1.0 - push), 0, -0.25))
	_to("ShoulderR", Vector3(2.7 * reach + 1.2 * (1.0 - reach) * (1.0 - push), 0, 0.25))
	_to("ElbowL", Vector3(0.2 + 1.1 * (1.0 - reach), 0, 0))
	_to("ElbowR", Vector3(0.2 + 1.1 * (1.0 - reach), 0, 0))
	_to("Spine", Vector3(-0.45 * (1.0 - push) - 0.1, 0, 0))
	var scramble: float = sin(t * 18.0)
	_to("HipL", Vector3(0.9 + 0.3 * scramble, 0, 0))
	_to("HipR", Vector3(0.5 - 0.3 * scramble, 0, 0))
	_to("KneeL", Vector3(-1.4, 0, 0))
	_to("KneeR", Vector3(-1.0, 0, 0))
	hips_target_y = -0.05


func _pose_vehicle(f) -> void:
	var steer: float = f.vehicle_steer
	_to("HipL", Vector3(1.45, 0, -0.06))
	_to("HipR", Vector3(1.45, 0, 0.06))
	_to("KneeL", Vector3(-1.45, 0, 0))
	_to("KneeR", Vector3(-1.45, 0, 0))
	_to("Spine", Vector3(0.12, -steer * 0.15, 0))
	_to("Head", Vector3(0.0, steer * 0.2, 0))
	if f.vehicle_hands_on_wheel:
		_to("ShoulderL", Vector3(1.15, -0.2 + steer * 0.35, -0.08))
		_to("ShoulderR", Vector3(1.15, 0.2 + steer * 0.35, 0.08))
		_to("ElbowL", Vector3(0.65, 0, 0))
		_to("ElbowR", Vector3(0.65, 0, 0))
	else:
		_to("ShoulderL", Vector3(0.7, 0, -0.25))
		_to("ShoulderR", Vector3(0.7, 0, 0.25))
		_to("ElbowL", Vector3(0.8, 0, 0))
		_to("ElbowR", Vector3(0.8, 0, 0))
	hips_target_y = -0.25


func _pose_dead(f) -> void:
	_to("ShoulderL", Vector3(0.2, 0, -0.9))
	_to("ShoulderR", Vector3(-0.1, 0, 0.9))
	_to("ElbowL", Vector3(0.3, 0, 0))
	_to("ElbowR", Vector3(0.4, 0, 0))
	_to("HipL", Vector3(0.25, 0, -0.15))
	_to("HipR", Vector3(-0.1, 0, 0.2))
	_to("KneeL", Vector3(-0.35, 0, 0))
	_to("KneeR", Vector3(-0.15, 0, 0))
	_to("Head", Vector3(0.0, 0.35, 0.25))

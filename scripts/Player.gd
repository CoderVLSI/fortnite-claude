extends "res://scripts/Fighter.gd"
# Player: over-the-shoulder third-person camera, strafe movement relative to the
# camera yaw, auto-fire rifle with a hitscan along the crosshair.

const SHOULDER_OFFSET := Vector3(0.65, 1.55, 0.0)
const CAMERA_DISTANCE := 3.6

var input_enabled := true
var pitch := -0.12
var head: Spatial
var spring: SpringArm
var camera: Camera


func _ready() -> void:
	add_to_group("player")
	setup_fighter("You", Color(0.22, 0.42, 0.85))
	gun_damage = 22.0
	reserve = 120
	_build_camera()


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
	camera.far = 420.0
	camera.near = 0.15
	spring.add_child(camera)
	camera.make_current()
	head.rotation.x = pitch


func _physics_process(delta: float) -> void:
	tick_weapon(delta)
	if is_dead:
		velocity = Vector3(0, velocity.y, 0)
		move_body(delta, Vector3.ZERO, 0.0, false)
		return
	var move := Vector2.ZERO
	var want_jump := false
	var sprinting := false
	if input_enabled:
		_look(delta)
		move = Controls.get_move()
		want_jump = Input.is_action_pressed("jump")
		sprinting = Input.is_action_pressed("sprint") and move.length() > 0.2
		if Input.is_action_just_pressed("reload"):
			start_reload()
		if Input.is_action_pressed("fire") and _can_aim():
			if fire_at_crosshair():
				pitch += rand_range(0.0, 0.006)
				rotation.y += rand_range(-0.003, 0.003)
	var b := global_transform.basis
	var wish := b.x * move.x + b.z * move.y    # move.y > 0 is backwards, and basis.z points backwards
	move_body(delta, wish, sprint_speed if sprinting else walk_speed, want_jump)
	aim_pitch = pitch
	animate(delta)


func _process(_delta: float) -> void:
	if head:
		head.rotation.x = pitch


func _look(delta: float) -> void:
	var l := Controls.consume_look(delta)
	rotation.y -= l.x
	pitch = clamp(pitch - l.y, -1.15, 1.15)


func _can_aim() -> bool:
	return Controls.touch_mode or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


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

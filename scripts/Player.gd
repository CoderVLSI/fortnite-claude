extends "res://scripts/Fighter.gd"
# Player: over-the-shoulder third-person camera, strafe movement relative to the
# camera yaw, inventory/hotbar, interact (loot, chests), and the bus -> freefall ->
# glider -> ground flow. Weapons fire a hitscan along the crosshair.

const SHOULDER_OFFSET := Vector3(0.65, 1.55, 0.0)
const CAMERA_DISTANCE := 3.6
const INTERACT_RANGE := 3.2

var input_enabled := true
var pitch := -0.12
var head: Spatial
var spring: SpringArm
var camera: Camera
var interact_target = null
var _interact_t := 0.0


func _ready() -> void:
	add_to_group("player")
	setup_fighter("You", Color(0.22, 0.42, 0.85))
	_build_camera()
	Controls.connect("slot_scroll", self, "_on_scroll")


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
	camera.far = 520.0
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
	if input_enabled:
		_look(delta)
	match mode:
		Mode.BUS:
			follow_bus()
			if input_enabled and Input.is_action_just_pressed("jump"):
				leave_bus()
			interact_target = null
		Mode.FREEFALL, Mode.GLIDE:
			air_input = Controls.get_move() if input_enabled else Vector2.ZERO
			if mode == Mode.FREEFALL and input_enabled and Input.is_action_just_pressed("jump"):
				deploy_glider()
			air_physics(delta)
			aim_pitch = 0.0
			animate(delta)
			interact_target = null
		_:
			_ground_process(delta)


func _ground_process(delta: float) -> void:
	var move := Vector2.ZERO
	var want_jump := false
	var sprinting := false
	if input_enabled:
		move = Controls.get_move()
		want_jump = Input.is_action_pressed("jump")
		sprinting = Input.is_action_pressed("sprint") and move.length() > 0.2
		if Input.is_action_just_pressed("reload"):
			start_reload()
		for i in range(Items.SLOT_COUNT):
			if Input.is_action_just_pressed("slot_%d" % (i + 1)):
				select_slot(i)
		_fire_input(delta)
		_interact_input(delta)
	var b := global_transform.basis
	var wish := b.x * move.x + b.z * move.y    # move.y > 0 is backwards, and basis.z points backwards
	var speed := sprint_speed if sprinting else walk_speed
	if is_using():
		speed *= 0.5
	move_body(delta, wish, speed, want_jump)
	aim_pitch = pitch
	animate(delta)


func _fire_input(delta: float) -> void:
	var item = selected_item()
	var firing := Input.is_action_pressed("fire") and _can_aim()
	if item == null or not firing:
		cancel_use()
		return
	if item.kind == "consumable":
		use_selected(delta)
		return
	if automatic or Input.is_action_just_pressed("fire"):
		if fire_at_crosshair() and item.kind == "weapon":
			pitch += rand_range(0.0, 0.006) * (3.0 if pellets > 1 or item.id == "sniper" else 1.0)
			rotation.y += rand_range(-0.003, 0.003)


func _interact_input(delta: float) -> void:
	_interact_t -= delta
	if _interact_t <= 0.0:
		_interact_t = 0.1
		interact_target = _find_interactable()
	if interact_target != null and Input.is_action_just_pressed("interact"):
		if is_instance_valid(interact_target) and interact_target.can_interact():
			interact_target.interact(self)
		interact_target = null
		_interact_t = 0.0


func _find_interactable():
	var best = null
	var best_d := INTERACT_RANGE
	var here := global_transform.origin
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n) or not n.can_interact():
			continue
		var d := here.distance_to(n.global_transform.origin + Vector3(0, 0.5, 0))
		if d < best_d:
			best_d = d
			best = n
	return best


func _on_scroll(direction: int) -> void:
	if mode == Mode.GROUND and not is_dead and input_enabled:
		cycle_slot(direction)


func _process(delta: float) -> void:
	if head == null:
		return
	head.rotation.x = pitch
	# Camera rig per movement state: pulled back and up on the bus / in the air.
	var dist := CAMERA_DISTANCE
	var offset := SHOULDER_OFFSET
	match mode:
		Mode.BUS:
			dist = 17.0
			offset = Vector3(0.0, 5.5, 0.0)
		Mode.FREEFALL:
			dist = 6.5
			offset = Vector3(0.0, 1.6, 0.0)
		Mode.GLIDE:
			dist = 5.2
			offset = Vector3(0.0, 1.9, 0.0)
	var k: float = clamp(3.0 * delta, 0.0, 1.0)
	spring.spring_length = lerp(spring.spring_length, dist, k)
	head.translation = head.translation.linear_interpolate(offset, k)


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

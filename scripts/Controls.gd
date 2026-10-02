extends Node
# Unified input layer (autoload). Keyboard/mouse, gamepad and the on-screen
# touch controls all end up as the same InputMap actions, so gameplay code only
# ever asks `Input.is_action_pressed("fire")` and friends.

signal touch_mode_changed(enabled)
signal slot_scroll(direction)   # +1 next item, -1 previous (mouse wheel / gamepad bumpers)

const MOVE_ACTIONS = ["move_forward", "move_back", "move_left", "move_right"]

var touch_mode := false
var mouse_look := Vector2.ZERO   # accumulated mouse pixels since last consume
var touch_look := Vector2.ZERO   # accumulated touch-drag pixels since last consume

const MOUSE_SENSITIVITY := 0.0022
const TOUCH_SENSITIVITY := 0.0042
const STICK_LOOK_SPEED := 2.6    # radians per second at full deflection


func _ready() -> void:
	_register_actions()
	var args := OS.get_cmdline_args()
	touch_mode = OS.has_touchscreen_ui_hint() or OS.has_feature("mobile") or ("--touch" in args)


func _register_actions() -> void:
	_key("move_forward", KEY_W)
	_key("move_forward", KEY_UP)
	_key("move_back", KEY_S)
	_key("move_back", KEY_DOWN)
	_key("move_left", KEY_A)
	_key("move_left", KEY_LEFT)
	_key("move_right", KEY_D)
	_key("move_right", KEY_RIGHT)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("reload", KEY_R)
	_key("interact", KEY_E)
	for i in range(5):
		_key("slot_%d" % (i + 1), KEY_1 + i)
	_mouse("fire", BUTTON_LEFT)
	# Gamepad: left stick = move, right stick = look, R2/RB = fire, A = jump.
	_axis("move_left", JOY_AXIS_0, -1.0)
	_axis("move_right", JOY_AXIS_0, 1.0)
	_axis("move_forward", JOY_AXIS_1, -1.0)
	_axis("move_back", JOY_AXIS_1, 1.0)
	_axis("look_left", JOY_AXIS_2, -1.0)
	_axis("look_right", JOY_AXIS_2, 1.0)
	_axis("look_up", JOY_AXIS_3, -1.0)
	_axis("look_down", JOY_AXIS_3, 1.0)
	_pad("jump", JOY_XBOX_A)
	_pad("reload", JOY_XBOX_X)
	_pad("sprint", JOY_BUTTON_8)  # left stick click
	_pad("fire", JOY_R2)
	_axis("fire", JOY_AXIS_7, 1.0)  # right trigger
	_pad("interact", JOY_XBOX_Y)


func _add(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	InputMap.action_add_event(action, event)


func _key(action: String, scancode: int) -> void:
	var e := InputEventKey.new()
	e.scancode = scancode
	_add(action, e)


func _mouse(action: String, button: int) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	_add(action, e)


func _axis(action: String, axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	_add(action, e)


func _pad(action: String, button: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	_add(action, e)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_look += event.relative
	elif event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_WHEEL_UP:
		emit_signal("slot_scroll", -1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_WHEEL_DOWN:
		emit_signal("slot_scroll", 1)
	elif event is InputEventJoypadButton and event.pressed and (event.button_index == JOY_L or event.button_index == JOY_R):
		emit_signal("slot_scroll", 1 if event.button_index == JOY_R else -1)
	elif event is InputEventScreenTouch and not touch_mode:
		set_touch_mode(true)  # a real touchscreen appeared (e.g. touch laptop)
	elif event is InputEventJoypadButton or event is InputEventKey:
		if touch_mode and not OS.has_feature("mobile") and not ("--touch" in OS.get_cmdline_args()):
			set_touch_mode(false)


func set_touch_mode(enabled: bool) -> void:
	if touch_mode == enabled:
		return
	touch_mode = enabled
	emit_signal("touch_mode_changed", enabled)


# Movement as a Vector2: x = right, y = back (so forward is y = -1).
func get_move() -> Vector2:
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	return v.limit_length(1.0)


# Look delta in radians (x = yaw, y = pitch), consuming accumulated pointer motion.
func consume_look(delta: float) -> Vector2:
	var l := (mouse_look * MOUSE_SENSITIVITY + touch_look * TOUCH_SENSITIVITY) * Settings.look_sensitivity
	mouse_look = Vector2.ZERO
	touch_look = Vector2.ZERO
	l.x += (Input.get_action_strength("look_right") - Input.get_action_strength("look_left")) * STICK_LOOK_SPEED * delta
	l.y += (Input.get_action_strength("look_down") - Input.get_action_strength("look_up")) * STICK_LOOK_SPEED * delta
	if Settings.invert_y:
		l.y = -l.y
	return l


func capture_mouse(capture: bool) -> void:
	if touch_mode:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)

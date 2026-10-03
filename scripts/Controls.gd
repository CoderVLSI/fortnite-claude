extends Node
# Unified input layer (autoload). Keyboard/mouse, gamepad and the on-screen
# touch controls all end up as the same InputMap actions, so gameplay code only
# ever asks `Input.is_action_pressed("fire")` and friends.

signal touch_mode_changed(enabled)
signal slot_scroll(direction)   # +1 next item, -1 previous (mouse wheel / gamepad bumpers)

const MOVE_ACTIONS = ["move_forward", "move_back", "move_left", "move_right"]

var touch_mode := false
var touch_aim := false            # the on-screen scope button is a toggle
var look_scale := 1.0             # < 1 while zoomed in, so aiming stays controllable
var mouse_look := Vector2.ZERO   # accumulated mouse pixels since last consume
var touch_look := Vector2.ZERO   # accumulated touch-drag pixels since last consume

const MOUSE_SENSITIVITY := 0.0022
const TOUCH_SENSITIVITY := 0.0042
const STICK_LOOK_SPEED := 2.6    # radians per second at full deflection


func _ready() -> void:
	_register_actions()
	var args := OS.get_cmdline_args()
	touch_mode = OS.has_touchscreen_ui_hint() or OS.has_feature("mobile") or ("--touch" in args)


# Every keyboard / mouse action the player can rebind (Settings > Controls): [action, label].
const BINDABLE := [
	["move_forward", "Move Forward"], ["move_back", "Move Backward"], ["move_left", "Move Left"], ["move_right", "Move Right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["crouch", "Crouch / Slide"], ["fire", "Fire"], ["aim", "Aim / Scope"],
	["reload", "Reload"], ["interact", "Pick Up / Interact"], ["pickaxe", "Pickaxe"],
	["slot_1", "Item Slot 1"], ["slot_2", "Item Slot 2"], ["slot_3", "Item Slot 3"], ["slot_4", "Item Slot 4"],
	["build_toggle", "Build Mode"], ["build_wall", "Build: Wall"], ["build_floor", "Build: Floor"],
	["build_ramp", "Build: Ramp"], ["build_roof", "Build: Roof"],
	["inventory", "Inventory"], ["map", "Map"], ["emote", "Emote"],
]

# Default keyboard / mouse bindings: action -> [[type, code], ...] with type "key" or "mouse".
const DEFAULTS := {
	"move_forward": [["key", KEY_W], ["key", KEY_UP]], "move_back": [["key", KEY_S], ["key", KEY_DOWN]],
	"move_left": [["key", KEY_A], ["key", KEY_LEFT]], "move_right": [["key", KEY_D], ["key", KEY_RIGHT]],
	"jump": [["key", KEY_SPACE]], "sprint": [["key", KEY_SHIFT]], "crouch": [["key", KEY_CONTROL]],
	"fire": [["mouse", BUTTON_LEFT]], "aim": [["mouse", BUTTON_RIGHT]], "reload": [["key", KEY_R]],
	"interact": [["key", KEY_E]], "pickaxe": [["key", KEY_F]],
	"slot_1": [["key", KEY_1]], "slot_2": [["key", KEY_2]], "slot_3": [["key", KEY_3]], "slot_4": [["key", KEY_4]],
	"build_toggle": [["key", KEY_Q]], "build_wall": [["key", KEY_Z]], "build_floor": [["key", KEY_X]],
	"build_ramp": [["key", KEY_C]], "build_roof": [["key", KEY_V]],
	"inventory": [["key", KEY_TAB]], "map": [["key", KEY_M]], "emote": [["key", KEY_B]],
}


func _register_actions() -> void:
	for a in DEFAULTS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
	apply_bindings()
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
	_pad("crouch", JOY_BUTTON_9)  # right stick click
	_pad("fire", JOY_R2)
	_pad("aim", JOY_L2)
	_axis("aim", JOY_AXIS_6, 1.0)  # left trigger
	_axis("fire", JOY_AXIS_7, 1.0)  # right trigger
	_pad("interact", JOY_XBOX_Y)
	_pad("inventory", JOY_SELECT)
	_pad("emote", JOY_DPAD_UP)


# (Re)build every action's keyboard / mouse events from the saved overrides, else the defaults. Gamepad events stay.
func apply_bindings() -> void:
	for action in DEFAULTS:
		for ev in InputMap.get_action_list(action):
			if ev is InputEventKey or ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)
		var list: Array = Settings.keybinds.get(action, DEFAULTS[action])
		for entry in list:
			if entry[0] == "key":
				_key(action, int(entry[1]))
			else:
				_mouse(action, int(entry[1]))


# Bind one key / mouse button to an action, taking it away from any other action that used it. Saved immediately.
func set_binding(action: String, type: String, code: int) -> void:
	for other in DEFAULTS:
		if other == action:
			continue
		var list: Array = Settings.keybinds.get(other, DEFAULTS[other]).duplicate(true)
		var kept := []
		for entry in list:
			if not (entry[0] == type and int(entry[1]) == code):
				kept.append(entry)
		if kept.size() != list.size():
			Settings.keybinds[other] = kept
	Settings.keybinds[action] = [[type, code]]
	apply_bindings()
	Settings.save_settings()


func reset_bindings() -> void:
	Settings.keybinds = {}
	apply_bindings()
	Settings.save_settings()


# One short label for the HUD hints ("Z", "LMB", "Ctrl"); follows the player's rebinding.
func key_label(action: String) -> String:
	for ev in InputMap.get_action_list(action):
		if ev is InputEventKey:
			var t := OS.get_scancode_string(ev.scancode)
			var short := {"Control": "Ctrl", "Escape": "Esc", "Space": "Space", "Shift": "Shift"}
			return short.get(t, t)
		elif ev is InputEventMouseButton:
			return ["", "LMB", "RMB", "MMB", "Wheel+", "Wheel-"][clamp(ev.button_index, 0, 5)]
	return "-"


# Short text for what is bound to an action ("W / Up", "Mouse Left", "Unbound").
func binding_text(action: String) -> String:
	var parts := []
	for ev in InputMap.get_action_list(action):
		if ev is InputEventKey:
			parts.append(OS.get_scancode_string(ev.scancode))
		elif ev is InputEventMouseButton:
			parts.append(["", "Mouse Left", "Mouse Right", "Mouse Middle", "Wheel Up", "Wheel Down"][clamp(ev.button_index, 0, 5)])
	return " / ".join(parts) if parts.size() > 0 else "Unbound"


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
	var l := (mouse_look * MOUSE_SENSITIVITY + touch_look * TOUCH_SENSITIVITY) * Settings.look_sensitivity * look_scale
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

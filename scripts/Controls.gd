extends Node
# Unified input layer (autoload). Keyboard/mouse, gamepad and the on-screen
# touch controls all end up as the same InputMap actions, so gameplay code only
# ever asks `Input.is_action_pressed("fire")` and friends.

signal touch_mode_changed(enabled)
var edit_aim := false              # the in-world build editor is open (fire / wheel belong to it)
signal slot_scroll(direction)   # +1 next item, -1 previous (mouse wheel / gamepad bumpers)
signal pad_changed(connected, pad_name)     # a controller was plugged in / removed
signal device_changed(using_pad)            # the last thing the player touched switched between pad and keyboard / mouse

const MOVE_ACTIONS = ["move_forward", "move_back", "move_left", "move_right"]

var touch_mode := false
var wheel_open := false           # the emote wheel is up: the mouse / right stick pick an emote instead of turning the camera
var wheel_delta := Vector2.ZERO   # mouse movement collected for the wheel
var using_pad := false            # the last input came from a controller (HUD hints switch to its button names)
var menu_open := false            # a menu is up: it is navigated with focus (D-pad / stick + A), not the pointer emulation
var pad_name := ""                # "" while no controller is connected
var touch_aim := false            # the on-screen scope button is a toggle
var look_scale := 1.0             # < 1 while zoomed in, so aiming stays controllable
var mouse_look := Vector2.ZERO   # accumulated mouse pixels since last consume
var touch_look := Vector2.ZERO   # accumulated touch-drag pixels since last consume

const MOUSE_SENSITIVITY := 0.0022
const TOUCH_SENSITIVITY := 0.0042
const STICK_LOOK_SPEED := 2.6    # radians per second at full deflection


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS          # the pad pointer has to work while a screen has the game paused
	_register_actions()
	Input.connect("joy_connection_changed", self, "_on_joy_changed")
	_refresh_pad()
	var args := OS.get_cmdline_args()
	touch_mode = OS.has_touchscreen_ui_hint() or OS.has_feature("mobile") or ("--touch" in args)


# Every keyboard / mouse action the player can rebind (Settings > Controls): [action, label].
const BINDABLE := [
	["move_forward", "Move Forward"], ["move_back", "Move Backward"], ["move_left", "Move Left"], ["move_right", "Move Right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["crouch", "Crouch / Slide"], ["fire", "Fire"], ["aim", "Aim / Scope"],
	["reload", "Reload"], ["interact", "Pick Up / Interact"], ["pickaxe", "Pickaxe"],
	["slot_1", "Item Slot 1"], ["slot_2", "Item Slot 2"], ["slot_3", "Item Slot 3"], ["slot_4", "Item Slot 4"], ["slot_5", "Item Slot 5"],
	["build_toggle", "Build Mode"], ["build_wall", "Build: Wall"], ["build_floor", "Build: Floor"],
	["build_ramp", "Build: Ramp"], ["build_roof", "Build: Roof"],
	["edit", "Edit Build Piece"], ["edit_reset", "Reset Edit"], ["inventory", "Inventory"], ["map", "Map"], ["emote", "Emote"],
]

# Default keyboard / mouse bindings: action -> [[type, code], ...] with type "key" or "mouse".
const DEFAULTS := {
	"move_forward": [["key", KEY_W], ["key", KEY_UP]], "move_back": [["key", KEY_S], ["key", KEY_DOWN]],
	"move_left": [["key", KEY_A], ["key", KEY_LEFT]], "move_right": [["key", KEY_D], ["key", KEY_RIGHT]],
	"jump": [["key", KEY_SPACE]], "sprint": [["key", KEY_SHIFT]], "crouch": [["key", KEY_CONTROL]],
	"fire": [["mouse", BUTTON_LEFT]], "aim": [["mouse", BUTTON_RIGHT]], "reload": [["key", KEY_R]],
	"interact": [["key", KEY_E]], "pickaxe": [["key", KEY_F]],
	"slot_1": [["key", KEY_1]], "slot_2": [["key", KEY_2]], "slot_3": [["key", KEY_3]], "slot_4": [["key", KEY_4]], "slot_5": [["key", KEY_5]],
	"build_toggle": [["key", KEY_Q]], "build_wall": [["key", KEY_Z]], "build_floor": [["key", KEY_X]],
	"build_ramp": [["key", KEY_C]], "build_roof": [["key", KEY_V]],
	"edit": [["key", KEY_G]], "edit_reset": [["mouse", BUTTON_RIGHT]], "inventory": [["key", KEY_TAB]], "map": [["key", KEY_M]], "emote": [["key", KEY_B]],
}


func _register_actions() -> void:
	for a in DEFAULTS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
	apply_bindings()
	# Gamepad sticks are fixed (left = move, right = look); the buttons come from PAD_DEFAULTS / the player's own choices.
	_axis("move_left", JOY_AXIS_0, -1.0)
	_axis("move_right", JOY_AXIS_0, 1.0)
	_axis("move_forward", JOY_AXIS_1, -1.0)
	_axis("move_back", JOY_AXIS_1, 1.0)
	_axis("look_left", JOY_AXIS_2, -1.0)
	_axis("look_right", JOY_AXIS_2, 1.0)
	_axis("look_up", JOY_AXIS_3, -1.0)
	_axis("look_down", JOY_AXIS_3, 1.0)


# Default controller buttons (Xbox naming; the same positions on PlayStation / Switch pads): action -> JOY_ index.
# LB / RB cycle the item slots (or the build material) and Menu / Start pauses: those three are fixed.
const PAD_DEFAULTS := {
	"jump": 0, "crouch": 1, "reload": 2, "interact": 2, "build_toggle": 3,
	"fire": 7, "aim": 6, "edit_reset": 6, "sprint": 8, "edit": 9, "inventory": 10,
	"build_wall": 12, "build_roof": 13, "build_floor": 14, "build_ramp": 15,
}
const PAD_RESERVED := [4, 5, 11]          # LB, RB, Start
const PAD_NAMES := {
	"xbox": {0: "A", 1: "B", 2: "X", 3: "Y", 4: "LB", 5: "RB", 6: "LT", 7: "RT", 8: "L3", 9: "R3", 10: "View", 11: "Menu",
		12: "D-Pad Up", 13: "D-Pad Down", 14: "D-Pad Left", 15: "D-Pad Right"},
	"ps": {0: "Cross", 1: "Circle", 2: "Square", 3: "Triangle", 4: "L1", 5: "R1", 6: "L2", 7: "R2", 8: "L3", 9: "R3", 10: "Share", 11: "Options",
		12: "D-Pad Up", 13: "D-Pad Down", 14: "D-Pad Left", 15: "D-Pad Right"},
	"nintendo": {0: "B", 1: "A", 2: "Y", 3: "X", 4: "L", 5: "R", 6: "ZL", 7: "ZR", 8: "L-Stick", 9: "R-Stick", 10: "-", 11: "+",
		12: "D-Pad Up", 13: "D-Pad Down", 14: "D-Pad Left", 15: "D-Pad Right"},
}


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
	apply_pad_bindings()


# Controller buttons for the bindable actions (stick axes stay as they are).
func apply_pad_bindings() -> void:
	for action in DEFAULTS:
		for ev in InputMap.get_action_list(action):
			if ev is InputEventJoypadButton or (ev is InputEventJoypadMotion and ev.axis >= JOY_AXIS_6):
				InputMap.action_erase_event(action, ev)
		var b: int = pad_button(action)
		if b < 0:
			continue
		_pad(action, b)
		if b == JOY_L2 or b == JOY_R2:                 # the triggers arrive as axes on some systems and as buttons on others
			_axis(action, JOY_AXIS_6 if b == JOY_L2 else JOY_AXIS_7, 1.0)


# The controller button bound to an action (-1 = none).
func pad_button(action: String) -> int:
	return int(Settings.padbinds.get(action, PAD_DEFAULTS.get(action, -1)))


# Give a controller button to an action; any other action that had it loses it (except the intended pairs on one button).
func set_pad_binding(action: String, button: int) -> void:
	if button in PAD_RESERVED:
		return
	for other in DEFAULTS:
		if other != action and pad_button(other) == button:
			Settings.padbinds[other] = -1
	Settings.padbinds[action] = button
	apply_pad_bindings()
	Settings.save_settings()


func reset_pad_bindings() -> void:
	Settings.padbinds = {}
	apply_pad_bindings()
	Settings.save_settings()


# "xbox", "ps" or "nintendo" - decides the button names shown. Unknown pads are treated as Xbox-layout.
func pad_style() -> String:
	var n := pad_name.to_lower()
	for k in ["playstation", "dualshock", "dualsense", "sony", "ps3", "ps4", "ps5"]:
		if k in n:
			return "ps"
	for k in ["nintendo", "switch", "joy-con", "pro controller"]:
		if k in n:
			return "nintendo"
	return "xbox"


func pad_label(button: int) -> String:
	if button < 0:
		return "Unbound"
	return PAD_NAMES[pad_style()].get(button, "Button %d" % button)


# Text for the controller column in Settings.
func pad_binding_text(action: String) -> String:
	if action in MOVE_ACTIONS:
		return "Left Stick"
	return pad_label(pad_button(action))


func _refresh_pad() -> void:
	var pads: Array = Input.get_connected_joypads()
	pad_name = Input.get_joy_name(int(pads[0])) if pads.size() > 0 else ""


func _on_joy_changed(_device: int, connected: bool) -> void:
	_refresh_pad()
	if not connected and pad_name == "":
		_set_using_pad(false)
	emit_signal("pad_changed", pad_name != "", pad_name)


func use_touch() -> void:
	_set_using_pad(false)


func _set_using_pad(on: bool) -> void:
	if using_pad != on:
		using_pad = on
		emit_signal("device_changed", on)


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
	if using_pad and pad_name != "":
		var b: int = pad_button(action)
		if b >= 0:
			return pad_label(b)
	for ev in InputMap.get_action_list(action):
		if ev is InputEventKey:
			var t := OS.get_scancode_string(ev.scancode)
			var short := {"Control": "Ctrl", "Escape": "Esc", "Space": "Space", "Shift": "Shift"}
			return short.get(t, t)
		elif ev is InputEventMouseButton:
			return mouse_name(ev.button_index, true)
	return "-"


static func mouse_name(b: int, short: bool) -> String:
	var names := {1: ["LMB", "Mouse Left"], 2: ["RMB", "Mouse Right"], 3: ["MMB", "Mouse Middle"], 4: ["Wheel+", "Wheel Up"],
		5: ["Wheel-", "Wheel Down"], 8: ["Side 1", "Mouse Side 1 (Back)"], 9: ["Side 2", "Mouse Side 2 (Forward)"]}
	return names[b][0 if short else 1] if names.has(b) else "Mouse %d" % b


# Short text for what is bound to an action ("W / Up", "Mouse Left", "Unbound").
func binding_text(action: String) -> String:
	var parts := []
	for ev in InputMap.get_action_list(action):
		if ev is InputEventKey:
			parts.append(OS.get_scancode_string(ev.scancode))
		elif ev is InputEventMouseButton:
			parts.append(mouse_name(ev.button_index, false))
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
	# Remember which kind of device was used last: the HUD hints and the pointer emulation follow it.
	if event is InputEventJoypadButton:
		if event.pressed:
			_set_using_pad(true)
	elif event is InputEventJoypadMotion:
		if abs(event.axis_value) > 0.55:
			_set_using_pad(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		if using_pad and event.pressed and not event.has_meta("pad_click"):
			_set_using_pad(false)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if wheel_open:
			wheel_delta += event.relative
		else:
			mouse_look += event.relative
	elif edit_aim and event is InputEventMouseButton:
		pass               # while editing, the wheel may be bound to Reset Edit: it must not also scroll the hotbar
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
	if event is InputEventJoypadButton and _pointer_active():
		_pad_click(event)


# Screens drawn by hand (inventory, map, end-of-match buttons) are pointer based: while one is open and a controller is in
# use, the left stick moves the pointer, A clicks and X right-clicks. Menus use focus navigation instead.
func _pointer_active() -> bool:
	return using_pad and not touch_mode and not menu_open and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if not _pointer_active():
		return
	var v := Vector2(Input.get_joy_axis(_pad_device(), JOY_AXIS_0), Input.get_joy_axis(_pad_device(), JOY_AXIS_1))
	if v.length() < 0.22:
		return
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size
	var pos: Vector2 = vp.get_mouse_position() + v.normalized() * pow(v.length(), 1.6) * 900.0 * delta
	pos.x = clamp(pos.x, 0.0, size.x - 1.0)
	pos.y = clamp(pos.y, 0.0, size.y - 1.0)
	vp.warp_mouse(pos)
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.relative = v * 4.0
	m.set_meta("pad_click", true)
	Input.parse_input_event(m)


func _pad_device() -> int:
	var pads: Array = Input.get_connected_joypads()
	return int(pads[0]) if pads.size() > 0 else 0


func _pad_click(event: InputEventJoypadButton) -> void:
	var btn := 0
	if event.button_index == JOY_XBOX_A:
		btn = BUTTON_LEFT
	elif event.button_index == JOY_XBOX_X:
		btn = BUTTON_RIGHT
	if btn == 0:
		return
	var pos: Vector2 = get_viewport().get_mouse_position()
	var c := InputEventMouseButton.new()
	c.button_index = btn
	c.pressed = event.pressed
	c.position = pos
	c.global_position = pos
	c.button_mask = (1 << (btn - 1)) if event.pressed else 0
	c.set_meta("pad_click", true)
	Input.parse_input_event(c)


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
	if wheel_open:
		mouse_look = Vector2.ZERO
		touch_look = Vector2.ZERO
		return Vector2.ZERO
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

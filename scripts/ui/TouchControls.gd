extends Control
# On-screen controls for phones/tablets: floating left-thumb joystick, drag
# anywhere on the right to look, and Fire / Jump / Reload / Sprint buttons.
# Everything is translated into InputMap actions (see Controls.gd), so the
# gameplay code is identical on PC and Android. Multi-touch aware.

const STICK_RADIUS := 105.0
const DEAD_ZONE := 0.12

signal map_pressed

var hotbar                  # set by the HUD: taps on it select slots
var minimap                 # set by the HUD: tapping it opens the full map
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_id := -1
var _buttons := {}
var _sprint_toggle := false
var _stick_sprint := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	connect("resized", self, "_layout")
	connect("visibility_changed", self, "_on_visibility_changed")
	_layout()


func _layout() -> void:
	var w := rect_size.x
	var h := rect_size.y
	_buttons = {
		"fire": {"center": Vector2(w - 150, h - 150), "radius": 82.0, "label": "FIRE", "action": "fire", "look_drag": true},
		"jump": {"center": Vector2(w - 335, h - 110), "radius": 60.0, "label": "JUMP", "action": "jump"},
		"reload": {"center": Vector2(w - 305, h - 268), "radius": 54.0, "label": "RELOAD", "action": "reload"},
		"interact": {"center": Vector2(w - 140, h - 322), "radius": 60.0, "label": "PICK UP", "action": "interact", "hidden": true},
		"sprint": {"center": Vector2(255, h - 340), "radius": 58.0, "label": "SPRINT", "action": "sprint", "toggle": true},
	}
	for b in _buttons.values():
		b["id"] = -1


func set_interact(show: bool) -> void:
	if _buttons.has("interact") and _buttons["interact"].get("hidden", false) == show:
		_buttons["interact"]["hidden"] = not show
		update()


func _stick_home() -> Vector2:
	return Vector2(170, rect_size.y - 170)


func _on_visibility_changed() -> void:
	if not visible:
		_release_all()


func _release_all() -> void:
	_stick_id = -1
	_look_id = -1
	_set_move(Vector2.ZERO)
	for b in _buttons.values():
		b["id"] = -1
		Input.action_release(b["action"])
	_sprint_toggle = false
	_stick_sprint = false
	update()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_down(event.index, event.position)
		else:
			_up(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)


func _down(index: int, pos: Vector2) -> void:
	if minimap != null and minimap.visible and Rect2(minimap.rect_global_position, minimap.rect_size).has_point(pos):
		emit_signal("map_pressed")
		return
	if hotbar != null and hotbar.visible:
		var slot: int = hotbar.slot_at(pos)
		if slot >= 0:
			hotbar.emit_signal("slot_pressed", slot)
			return
	for b in _buttons.values():
		if b.get("hidden", false):
			continue
		if pos.distance_to(b["center"]) <= b["radius"] * 1.2 and b["id"] == -1:
			b["id"] = index
			if b.get("toggle", false):
				_sprint_toggle = not _sprint_toggle
				_apply_sprint()
			else:
				Input.action_press(b["action"])
			update()
			return
	if pos.x < rect_size.x * 0.42 and _stick_id == -1:
		_stick_id = index
		_stick_origin = Vector2(clamp(pos.x, STICK_RADIUS, rect_size.x * 0.42), clamp(pos.y, rect_size.y * 0.35, rect_size.y - STICK_RADIUS))
		_stick_pos = pos
		_drag(index, pos, Vector2.ZERO)
	elif _look_id == -1:
		_look_id = index
	update()


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _stick_id:
		var d := pos - _stick_origin
		if d.length() > STICK_RADIUS:
			d = d.normalized() * STICK_RADIUS
		_stick_pos = _stick_origin + d
		var v := d / STICK_RADIUS
		_stick_sprint = v.length() > 0.96
		_apply_sprint()
		_set_move(v)
	elif index == _look_id:
		Controls.touch_look += relative
	else:
		for b in _buttons.values():
			if b["id"] == index and b.get("look_drag", false):
				Controls.touch_look += relative
	update()


func _up(index: int) -> void:
	if index == _stick_id:
		_stick_id = -1
		_stick_sprint = false
		_apply_sprint()
		_set_move(Vector2.ZERO)
	elif index == _look_id:
		_look_id = -1
	for b in _buttons.values():
		if b["id"] == index:
			b["id"] = -1
			if not b.get("toggle", false):
				Input.action_release(b["action"])
	update()


func _set_move(v: Vector2) -> void:
	if v.length() < DEAD_ZONE:
		v = Vector2.ZERO
	_press("move_right", max(v.x, 0.0))
	_press("move_left", max(-v.x, 0.0))
	_press("move_back", max(v.y, 0.0))
	_press("move_forward", max(-v.y, 0.0))


func _press(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _apply_sprint() -> void:
	if _sprint_toggle or _stick_sprint:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func _draw() -> void:
	var font := get_font("font", "Label")
	var home := _stick_origin if _stick_id != -1 else _stick_home()
	var knob := _stick_pos if _stick_id != -1 else home
	draw_circle(home, STICK_RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(home, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
	draw_circle(knob, 44.0, Color(1, 1, 1, 0.30 if _stick_id == -1 else 0.55))

	for b in _buttons.values():
		if b.get("hidden", false):
			continue
		var active: bool = b["id"] != -1 or (b.get("toggle", false) and _sprint_toggle)
		var tint := Color(1.0, 0.35, 0.3) if b["action"] == "fire" else Color(1, 1, 1)
		if b["action"] == "interact":
			tint = Color(1.0, 0.85, 0.3)
		draw_circle(b["center"], b["radius"], Color(tint.r, tint.g, tint.b, 0.40 if active else 0.16))
		draw_arc(b["center"], b["radius"], 0, TAU, 40, Color(tint.r, tint.g, tint.b, 0.65), 3.0)
		var tw := font.get_string_size(b["label"]).x
		draw_string(font, b["center"] + Vector2(-tw / 2.0, font.get_height() * 0.3), b["label"], Color(1, 1, 1, 0.9))

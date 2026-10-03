extends Control
# On-screen controls for phones/tablets, laid out like a mobile battle-royale HUD: floating
# left-thumb joystick with a second FIRE button above it, a big FIRE + JUMP cluster and SPRINT
# on the right, the four build-piece buttons down the right edge, RELOAD beside the ammo
# readout and a context PICK UP / EXIT ring beside the hotbar. Drag anywhere on the right to
# look. Everything is translated into InputMap actions (see Controls.gd), so the gameplay code
# is identical on PC and Android. Multi-touch aware.

const STICK_RADIUS := 105.0
const DEAD_ZONE := 0.12
const HOTBAR_HALF := 167.0       # half the hotbar width: the pickup ring and reload button sit beside it

signal map_pressed
signal piece_pressed(index)
signal material_pressed(name)

var hotbar                  # set by the HUD: taps on it select slots
var minimap                 # set by the HUD: tapping it opens the full map
var materials               # set by the HUD: tapping a box chooses the build material
var builder                 # set by the HUD: highlights the active build piece
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
		"fire": {"center": Vector2(w - 190, h - 215), "radius": 80.0, "icon": "fire", "action": "fire", "look_drag": true},
		"fire2": {"center": Vector2(86, h - 345), "radius": 54.0, "icon": "fire", "action": "fire", "look_drag": true},
		"jump": {"center": Vector2(w - 84, h - 98), "radius": 58.0, "icon": "jump", "action": "jump"},
		"sprint": {"center": Vector2(w - 300, h - 480), "radius": 56.0, "icon": "sprint", "action": "sprint", "toggle": true},
		"scope": {"center": Vector2(w - 348, h - 338), "radius": 50.0, "icon": "scope", "aim": true},
		"reload": {"center": Vector2(w / 2.0 + HOTBAR_HALF + 235.0, h - 64), "radius": 40.0, "icon": "reload", "action": "reload"},
		"interact": {"center": Vector2(w / 2.0 - HOTBAR_HALF - 72.0, h - 78), "radius": 58.0, "label": "PICK UP", "action": "interact", "hidden": true},
	}
	for i in range(4):
		_buttons["piece%d" % i] = {"center": Vector2(w - 46, 150.0 + i * 84.0), "radius": 36.0, "icon": "piece%d" % i, "piece": i}
	for b in _buttons.values():
		b["id"] = -1


func set_interact(show: bool, label: String = "PICK UP") -> void:
	if not _buttons.has("interact"):
		return
	var b: Dictionary = _buttons["interact"]
	if b.get("hidden", false) == show or b["label"] != label:
		b["hidden"] = not show
		b["label"] = label
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
		if b.has("action"):
			Input.action_release(b["action"])
	_sprint_toggle = false
	_stick_sprint = false
	Controls.touch_aim = false
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
	if materials != null and materials.visible:
		var m: String = materials.material_at(pos)
		if m != "":
			emit_signal("material_pressed", m)
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
			if b.has("piece"):
				emit_signal("piece_pressed", b["piece"])
			elif b.get("aim", false):
				Controls.touch_aim = not Controls.touch_aim       # tap to scope in, tap again to scope out
			elif b.get("toggle", false):
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
			if b.has("action") and not b.get("toggle", false):
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


func _process(_delta: float) -> void:
	if visible:
		update()   # piece buttons follow the builder state


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var font := get_font("font", "Label")
	var home := _stick_origin if _stick_id != -1 else _stick_home()
	var knob := _stick_pos if _stick_id != -1 else home
	draw_circle(home, STICK_RADIUS, Color(0.05, 0.07, 0.12, 0.22))
	draw_arc(home, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.5)
	draw_circle(knob, 44.0, Color(1, 1, 1, 0.26 if _stick_id == -1 else 0.5))

	for key in _buttons:
		var b: Dictionary = _buttons[key]
		if b.get("hidden", false):
			continue
		var c: Vector2 = b["center"]
		var r: float = b["radius"]
		var active: bool = b["id"] != -1 or (b.get("toggle", false) and _sprint_toggle) or (b.get("aim", false) and Controls.touch_aim)
		var chosen: bool = b.has("piece") and builder != null and builder.active and builder.piece == b["piece"]
		var ring := Color(1, 1, 1, 0.6)
		var fill := Color(0.05, 0.07, 0.12, 0.30)
		if b.get("action", "") == "interact":
			ring = Color(0.45, 0.75, 1.0, 0.95)
			fill = Color(0.12, 0.25, 0.5, 0.45)
		if chosen:
			ring = Color(0.45, 0.78, 1.0, 1.0)
			fill = Color(0.12, 0.3, 0.6, 0.55)
		if active:
			fill = Color(1, 1, 1, 0.34)
		draw_circle(c, r, fill)
		draw_arc(c, r, 0, TAU, 40, ring, 2.5 if not chosen else 4.0)
		if b.has("icon"):
			_draw_icon(b["icon"], c, r, Color(1, 1, 1, 0.95), chosen)
		elif b.has("label"):
			var tw := font.get_string_size(b["label"]).x
			draw_string(font, c + Vector2(-tw / 2.0, font.get_height() * 0.3), b["label"], Color(1, 1, 1, 0.95))


func _draw_icon(icon: String, c: Vector2, r: float, col: Color, chosen: bool) -> void:
	var k := r / 60.0
	match icon:
		"fire":      # bullet pointing up-left, like a shoot button
			var pts := PoolVector2Array([c + Vector2(-26, 22) * k, c + Vector2(-8, 28) * k, c + Vector2(26, -20) * k, c + Vector2(0, -26) * k])
			draw_colored_polygon(pts, Color(1, 1, 1, 0.9))
			draw_line(c + Vector2(-30, 8) * k, c + Vector2(-12, 0) * k, Color(1, 1, 1, 0.6), 3.0)
			draw_line(c + Vector2(-34, 20) * k, c + Vector2(-18, 14) * k, Color(1, 1, 1, 0.45), 3.0)
		"jump":      # two stacked chevrons
			for off in [0.0, 18.0]:
				draw_polyline(PoolVector2Array([c + Vector2(-24, 6 + off) * k, c + Vector2(0, -14 + off) * k, c + Vector2(24, 6 + off) * k]), col, 5.0 * max(k, 0.8))
		"sprint":    # three chevrons pointing right with speed lines
			for off in [-16.0, 2.0, 20.0]:
				draw_polyline(PoolVector2Array([c + Vector2(off - 6, -18) * k, c + Vector2(off + 12, 0) * k, c + Vector2(off - 6, 18) * k]), col, 5.0 * max(k, 0.8))
		"scope":     # sight ring with a crosshair
			draw_arc(c, 19.0 * max(k * 1.3, 1.0), 0, TAU, 28, col, 3.0)
			for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + dir * 8.0, c + dir * 27.0 * max(k * 1.2, 1.0), col, 3.0)
			draw_circle(c, 2.5, col)
		"reload":    # circular arrow
			draw_arc(c, 17.0 * max(k * 1.4, 1.0), -0.6, TAU - 1.4, 24, col, 4.0)
			var tip := c + Vector2(cos(-0.6), sin(-0.6)) * 17.0 * max(k * 1.4, 1.0)
			draw_colored_polygon(PoolVector2Array([tip + Vector2(-9, -2), tip + Vector2(9, -4), tip + Vector2(2, 10)]), col)
		"piece0":    # wall
			draw_rect(Rect2(c + Vector2(-20, -24), Vector2(40, 48)), Color(0.55, 0.78, 1.0, 0.9) if chosen else Color(0.7, 0.85, 1.0, 0.85))
			draw_rect(Rect2(c + Vector2(-20, -24), Vector2(40, 48)), Color(1, 1, 1, 0.9), false, 2.0)
		"piece1":    # floor
			draw_colored_polygon(PoolVector2Array([c + Vector2(-26, 8), c + Vector2(-14, -10), c + Vector2(26, -10), c + Vector2(14, 8)]), Color(0.7, 0.85, 1.0, 0.85))
			draw_rect(Rect2(c + Vector2(-26, 8), Vector2(40, 7)), Color(0.45, 0.62, 0.85, 0.95))
		"piece2":    # stairs / ramp
			draw_colored_polygon(PoolVector2Array([c + Vector2(-24, 20), c + Vector2(24, 20), c + Vector2(24, -20)]), Color(0.7, 0.85, 1.0, 0.85))
			draw_line(c + Vector2(-24, 20), c + Vector2(24, -20), Color(1, 1, 1, 0.9), 2.0)
		"piece3":    # roof / cone
			draw_colored_polygon(PoolVector2Array([c + Vector2(-26, 20), c + Vector2(26, 20), c + Vector2(0, -24)]), Color(0.7, 0.85, 1.0, 0.85))
			draw_line(c + Vector2(0, -24), c + Vector2(0, 20), Color(1, 1, 1, 0.5), 2.0)

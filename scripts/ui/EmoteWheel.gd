extends Control
# The emote wheel. Hold the emote key / button (B on PC, nothing by default on a pad - bind it in Settings) to open it,
# flick the mouse / right stick toward an emote and let go to play it. A quick tap repeats your last emote (or stops the
# dance). On a phone the dance button opens it and you tap an emote. Which emotes sit on it is chosen in Locker > Emotes.

const Emotes = preload("res://scripts/Emotes.gd")
const HOLD_TIME := 0.18
const RADIUS_IN := 62.0
const RADIUS_OUT := 235.0

var player
var font: Font
var open := false
var _touch := false
var _down := false
var _hold := 0.0
var _cursor := Vector2.ZERO
var _sel := -1
var _latch_down := false         # key events seen between frames, so a very quick tap on a slow frame rate is not missed
var _latch_up := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	visible = false


func _input(event: InputEvent) -> void:
	if event.is_action("emote") and not event.is_echo() and not (event is InputEventMouseMotion):
		if event.is_pressed():
			_latch_down = true
		else:
			_latch_up = true


func wheel() -> Array:
	return Emotes.sanitize_wheel(Settings.emote_wheel)


func _can_emote() -> bool:
	return player != null and not player.is_dead and player.input_enabled and player.mode == player.Mode.GROUND


func _process(delta: float) -> void:
	if player == null:
		return
	if open and (not _can_emote() or player.is_dead):
		_close()
		return
	if _touch:
		return
	var pressed_now: bool = Input.is_action_just_pressed("emote") or _latch_down
	var released_now: bool = _latch_up
	_latch_down = false
	_latch_up = false
	if _can_emote() and pressed_now and not Controls.menu_open:
		_down = true
		_hold = 0.0
	if _down:
		if Input.is_action_pressed("emote") and not released_now:
			_hold += delta
			if _hold > HOLD_TIME and not open:
				_open(false)
		else:
			_down = false
			var id := _selected_id() if open else ""
			var slow_tap: bool = open and id == "" and _hold < 0.5      # a tap on a slow frame rate looks like a short hold
			if open:
				_close()
			if id != "":
				player.start_emote(id)
			elif open and not slow_tap:
				pass                                       # held, nothing picked: cancel
			elif player.emoting:
				player.emoting = false                     # a tap while dancing stops the dance
			else:
				player.start_emote(Settings.last_emote if Emotes.is_emote(Settings.last_emote) else "boogie")
	if open:
		_cursor += Controls.wheel_delta
		Controls.wheel_delta = Vector2.ZERO
		var stick := Vector2(Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
			Input.get_action_strength("look_down") - Input.get_action_strength("look_up"))
		if stick.length() > 0.35:
			_cursor = stick.normalized() * RADIUS_IN * 1.8
		if _cursor.length() > RADIUS_IN * 2.4:
			_cursor = _cursor.normalized() * RADIUS_IN * 2.4
		_update_sel()
		update()


func _open(touch: bool) -> void:
	open = true
	_touch = touch
	_cursor = Vector2.ZERO
	_sel = -1
	visible = true
	Controls.wheel_open = true
	Controls.wheel_delta = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP if touch else Control.MOUSE_FILTER_IGNORE
	Audio.play2d("ui_click", -8.0)
	update()


func open_touch() -> void:
	if open:
		_close()
	elif _can_emote():
		_open(true)


func _close() -> void:
	open = false
	_touch = false
	_down = false
	visible = false
	Controls.wheel_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _slot_at(v: Vector2) -> int:
	var n: int = wheel().size()
	if v.length() < RADIUS_IN:
		return -1
	var a := atan2(v.x, -v.y)                                  # 0 = straight up, clockwise
	if a < 0.0:
		a += TAU
	return int(round(a / (TAU / n))) % n


func _update_sel() -> void:
	_sel = _slot_at(_cursor)


func _selected_id() -> String:
	var w := wheel()
	return w[_sel] if _sel >= 0 and _sel < w.size() else ""


func _gui_input(event: InputEvent) -> void:
	if not (open and _touch):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		var v: Vector2 = event.position - rect_size / 2.0
		var i := _slot_at(v)
		var id := ""
		if i >= 0 and v.length() < RADIUS_OUT + 70.0:
			id = wheel()[i]
		_close()
		if id != "":
			player.start_emote(id)
		accept_event()


func _draw() -> void:
	if not open or font == null:
		return
	var c := rect_size / 2.0
	var w := wheel()
	var n := w.size()
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0, 0, 0, 0.35))
	draw_circle(c, RADIUS_OUT + 12.0, Color(0.03, 0.05, 0.13, 0.55))
	var step := TAU / n
	for i in range(n):
		var a0 := -PI / 2.0 + (i - 0.5) * step
		var a1 := a0 + step
		var pts := PoolVector2Array()
		var arc := 10
		for k in range(arc + 1):
			var a: float = lerp(a0, a1, float(k) / arc)
			pts.append(c + Vector2(cos(a), sin(a)) * RADIUS_OUT)
		for k in range(arc, -1, -1):
			var a: float = lerp(a0, a1, float(k) / arc)
			pts.append(c + Vector2(cos(a), sin(a)) * RADIUS_IN)
		var info: Dictionary = Emotes.LIST[w[i]]
		var rc: Color = preload("res://scripts/Items.gd").RARITIES[info.rarity].color
		var on := i == _sel
		draw_colored_polygon(pts, Color(rc.r, rc.g, rc.b, 0.55) if on else Color(0.1, 0.14, 0.28, 0.82))
		draw_polyline(pts, Color(1, 1, 1, 0.8 if on else 0.25), 2.0)
		var mid := -PI / 2.0 + i * step
		var tp := c + Vector2(cos(mid), sin(mid)) * (RADIUS_IN + RADIUS_OUT) * 0.5
		var name: String = info.name
		var tw := font.get_string_size(name).x
		draw_string(font, tp + Vector2(-tw / 2.0, 6), name, Color(1, 1, 1, 1.0 if on else 0.8))
	draw_circle(c, RADIUS_IN - 4.0, Color(0.03, 0.05, 0.13, 0.9))
	var label := "TAP AN EMOTE" if _touch else ("RELEASE TO CANCEL" if _sel < 0 else "")
	var desc := ""
	if _sel >= 0:
		label = Emotes.LIST[w[_sel]].name
		desc = Emotes.LIST[w[_sel]].desc
	var lw := font.get_string_size(label).x
	draw_string(font, c + Vector2(-min(lw, RADIUS_IN * 1.8) / 2.0, 5), label, Color(1, 0.9, 0.4))
	if not _touch:
		draw_circle(c + _cursor, 7.0, Color(1, 1, 1, 0.95))
		draw_line(c, c + _cursor, Color(1, 1, 1, 0.5), 2.0)
	if desc != "":
		var dw := font.get_string_size(desc).x
		draw_string(font, c + Vector2(-dw / 2.0, RADIUS_OUT + 44.0), desc, Color(0.85, 0.92, 1.0))

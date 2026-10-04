extends Control
# The title splash: the night-window painting with the Storm Island logo, purple lightning bolts that strike with a screen
# flash and distant thunder, rain streaks, and a blinking "PRESS E TO START" (tap anywhere on a phone).

signal start

const FONT_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"
const RAIN := 110

var _t := 0.0
var _next := 0.6
var _flash := 0.0
var _bolts := []                       # {pts: PoolVector2Array, branches: [PoolVector2Array], life: float, max: float}
var _rain := []                        # [x, y, speed, length] in 0..1 screen units
var _bg: TextureRect
var _logo: TextureRect
var _fx: Control
var _prompt: Label
var _big: DynamicFont
var _armed := false                    # ignore input for a moment so the key press that launched the game does not skip it


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var data = load(FONT_PATH)
	if data != null:
		_big = DynamicFont.new()
		_big.font_data = data
		_big.size = 40
		_big.use_filter = true
	_bg = TextureRect.new()
	_bg.expand = true
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex = load("res://assets/ui/loading_bg.png")
	if tex != null:
		_bg.texture = tex
	add_child(_bg)
	_fx = Control.new()                              # bolts, rain and the flash: drawn over the painting, under the logo
	_fx.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.connect("draw", self, "_draw_fx")
	add_child(_fx)
	_logo = TextureRect.new()
	_logo.expand = true
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lt = load("res://assets/ui/logo.png")
	if lt != null:
		_logo.texture = lt
	add_child(_logo)
	for i in range(RAIN):
		_rain.append([randf(), randf(), rand_range(0.9, 1.5), rand_range(0.018, 0.045)])
	_prompt = Label.new()
	_prompt.align = Label.ALIGN_CENTER
	_prompt.valign = Label.VALIGN_CENTER
	_prompt.add_color_override("font_color", Color(1.0, 0.88, 0.35))
	_prompt.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	_prompt.add_constant_override("shadow_offset_x", 3)
	_prompt.add_constant_override("shadow_offset_y", 3)
	if _big != null:
		_prompt.add_font_override("font", _big)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	connect("resized", self, "_layout")
	visible = false
	_layout()


func _layout() -> void:
	var w := rect_size.x
	var h := rect_size.y
	var lw: float = min(w * 0.46, 640.0)
	_logo.rect_size = Vector2(lw, lw * 0.5625)
	_logo.rect_position = Vector2((w - lw) / 2.0, h * 0.44 - lw * 0.5625 / 2.0)
	_logo.rect_pivot_offset = _logo.rect_size / 2.0
	_prompt.rect_size = Vector2(w, 60)
	_prompt.rect_position = Vector2(0, h * 0.84)


func open() -> void:
	visible = true
	_t = 0.0
	_next = 0.5
	_flash = 0.0
	_bolts.clear()
	_armed = false
	get_tree().create_timer(0.35, true).connect("timeout", self, "_arm")


func _arm() -> void:
	_armed = true


func bolt_count() -> int:
	return _bolts.size()


# A lightning strike: a few jagged bolts, a bright flash and thunder a moment later.
func strike() -> void:
	var w := rect_size.x
	var h := rect_size.y
	var count := 1 + (randi() % 2)
	for k in range(count):
		var x := rand_range(0.18, 0.95) * w
		var end_y := rand_range(0.36, 0.64) * h
		var pts := PoolVector2Array()
		var branches := []
		var segs := 11
		var cx := x
		for i in range(segs + 1):
			var y: float = end_y * float(i) / segs
			pts.append(Vector2(cx, y))
			cx += rand_range(-38.0, 38.0)
			if i > 2 and i < segs - 1 and randf() < 0.28:             # a side branch
				var b := PoolVector2Array()
				var bx := cx
				var by := y
				var dir := 1.0 if randf() < 0.5 else -1.0
				for j in range(4):
					b.append(Vector2(bx, by))
					bx += dir * rand_range(14.0, 40.0)
					by += rand_range(16.0, 40.0)
				branches.append(b)
		var life := rand_range(0.18, 0.32)
		_bolts.append({"pts": pts, "branches": branches, "life": life, "max": life})
	_flash = 0.85
	var delay := rand_range(0.25, 0.8)
	get_tree().create_timer(delay, true).connect("timeout", self, "_thunder")


func _thunder() -> void:
	if visible:
		Audio.play2d("explosion", -19.0, rand_range(0.38, 0.55))


func _input(event: InputEvent) -> void:
	if not visible or not _armed:
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		go = event.is_action("interact") or event.scancode == KEY_ENTER or event.scancode == KEY_KP_ENTER or event.scancode == KEY_SPACE
	elif event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		go = true
	elif event is InputEventScreenTouch and event.pressed:
		go = true
	elif event is InputEventJoypadButton and event.pressed:
		go = true
	if go:
		get_tree().set_input_as_handled()
		visible = false
		emit_signal("start")


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_next -= delta
	if _next <= 0.0:
		_next = rand_range(1.6, 3.8)
		strike()
	_flash = max(0.0, _flash - delta * 2.6)
	for i in range(_bolts.size() - 1, -1, -1):
		_bolts[i].life -= delta
		if _bolts[i].life <= 0.0:
			_bolts.remove(i)
	for r in _rain:
		r[0] -= delta * 0.12 * r[2]
		r[1] += delta * r[2] * 1.15
		if r[1] > 1.1 or r[0] < -0.1:
			r[0] = rand_range(0.0, 1.2)
			r[1] = -0.05
	var pulse := 1.0 + sin(_t * 1.3) * 0.012 + _flash * 0.02
	_logo.rect_scale = Vector2(pulse, pulse)
	_logo.modulate = Color(1.0 + _flash * 0.9, 1.0 + _flash * 0.7, 1.0 + _flash * 0.4, 1.0)
	_bg.modulate = Color(0.85 + _flash * 0.6, 0.85 + _flash * 0.55, 0.9 + _flash * 0.5, 1.0)
	_prompt.text = prompt_text()
	_prompt.modulate.a = 0.55 + 0.45 * sin(_t * 3.4)
	_fx.update()


func _draw_fx() -> void:
	var w := rect_size.x
	var h := rect_size.y
	for r in _rain:                                               # rain streaks, slanted
		var p := Vector2(r[0] * w, r[1] * h)
		_fx.draw_line(p, p + Vector2(-0.35, 1.0).normalized() * r[3] * h, Color(0.75, 0.8, 1.0, 0.16), 1.5)
	for b in _bolts:
		var a: float = clamp(b.life / b.max, 0.0, 1.0) * (0.55 + 0.45 * randf())     # flicker
		_fx.draw_polyline(b.pts, Color(0.55, 0.3, 1.0, 0.20 * a), 16.0)
		_fx.draw_polyline(b.pts, Color(0.75, 0.6, 1.0, 0.55 * a), 7.0)
		_fx.draw_polyline(b.pts, Color(1.0, 1.0, 1.0, 0.95 * a), 2.6)
		for br in b.branches:
			_fx.draw_polyline(br, Color(0.7, 0.55, 1.0, 0.45 * a), 4.0)
			_fx.draw_polyline(br, Color(1.0, 1.0, 1.0, 0.8 * a), 1.6)
	if _flash > 0.01:
		_fx.draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.78, 0.72, 1.0, _flash * 0.38))


func prompt_text() -> String:
	return "TAP TO START" if Controls.touch_mode else ("PRESS %s TO START" % Controls.key_label("interact").to_upper())

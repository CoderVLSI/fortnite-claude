extends CanvasLayer
# Title screen, settings, how-to-play and pause menu. Built in code; works with mouse and touch.
# While the title or pause menu is open the scene tree is paused (this layer and the Audio
# autoload keep running). The title screen orbits a camera around the island.

const FONT_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"
const HELP_PC := "Move: WASD        Look: mouse        Fire: left click\nJump / handbrake: Space        Sprint: Shift        Reload / horn: R\nPick up / open / enter vehicle: E        Build mode: Q  (1-4 pieces, wheel = material)\nHotbar: 1-5 or wheel        Map: M        Pause: Esc"
const HELP_TOUCH := "Left thumb: move    Right side: look    FIRE / JUMP / RELOAD / SPRINT buttons\nPICK UP appears next to loot, chests and vehicles    BUILD toggles building\nTap the hotbar to switch items    Tap the minimap for the island map"
const HELP_GOAL := "Ride the Sky Ferry, jump, glide down and loot.  Fight bots, stay inside the shrinking storm,\ndrive vehicles, swim, climb ledges, take on the Warden at Iron Bunker for Mythic loot.\nBe the last one standing."

var world
var root: Control
var title_panel: Control
var settings_panel: Control
var help_panel: Control
var pause_panel: Control
var fps_label: Label
var orbit_cam: Camera
var state := "hidden"            # title | paused | hidden
var _orbit_t := 0.0
var _font: DynamicFont
var _settings_return := "title"


func _ready() -> void:
	layer = 40
	pause_mode = Node.PAUSE_MODE_PROCESS
	root = Control.new()
	root.name = "MenuRoot"
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.theme = _make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	title_panel = _build_title()
	settings_panel = _build_settings()
	help_panel = _build_help()
	pause_panel = _build_pause()
	fps_label = Label.new()
	fps_label.rect_position = Vector2(14, 8)
	fps_label.add_color_override("font_color", Color(1, 1, 0.5))
	fps_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	root.add_child(fps_label)
	_show_none()
	orbit_cam = Camera.new()
	orbit_cam.far = 700.0
	orbit_cam.fov = 55.0
	add_child(orbit_cam)


func _make_theme() -> Theme:
	var theme := Theme.new()
	var data = load(FONT_PATH)
	if data != null:
		_font = DynamicFont.new()
		_font.font_data = data
		_font.size = 24
		_font.use_filter = true
		theme.default_font = _font
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.17, 0.30, 0.92)
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.45, 0.55, 0.95, 0.9)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.22, 0.30, 0.55, 0.96)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.95, 0.75, 0.2, 0.96)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", hover)
	theme.set_color("font_color", "Button", Color.white)
	theme.set_color("font_color_hover", "Button", Color.white)
	theme.set_color("font_color_pressed", "Button", Color(0.1, 0.1, 0.15))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.45, 0.5, 0.72, 0.9)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var filled: StyleBoxFlat = track.duplicate()
	filled.bg_color = Color(0.95, 0.75, 0.2, 0.95)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.07, 0.14, 0.88)
	panel.set_corner_radius_all(10)
	theme.set_stylebox("panel", "Panel", panel)
	return theme


func bind(world_node) -> void:
	world = world_node


# ------------------------------------------------------------------ construction

func _label(text: String, size: int = 0, color: Color = Color.white) -> Label:
	var l := Label.new()
	l.text = text
	l.add_color_override("font_color", color)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.7))
	l.add_constant_override("shadow_offset_x", 2)
	l.add_constant_override("shadow_offset_y", 2)
	if size > 0 and _font != null:
		var f := DynamicFont.new()
		f.font_data = _font.font_data
		f.size = size
		f.use_filter = true
		l.add_font_override("font", f)
	return l


func _button(text: String, target: String, min_w: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.rect_min_size = Vector2(min_w, 62)
	b.connect("pressed", self, "_on_button", [target])
	return b


func _column(parent: Control, pos: Vector2, size: Vector2) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.rect_position = pos
	c.rect_size = size
	c.add_constant_override("separation", 14)
	parent.add_child(c)
	return c


func _build_title() -> Control:
	var p := Control.new()
	p.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.12, 0.62)
	shade.anchor_bottom = 1.0
	shade.margin_right = 660
	p.add_child(shade)
	var col := _column(p, Vector2(60, 90), Vector2(420, 560))
	var title := _label("STORM ISLAND", 60, Color(1.0, 0.88, 0.45))
	col.add_child(title)
	col.add_child(_label("Last one standing wins", 24, Color(0.8, 0.88, 1.0)))
	var spacer := Control.new()
	spacer.rect_min_size = Vector2(0, 30)
	col.add_child(spacer)
	col.add_child(_button("PLAY", "play"))
	col.add_child(_button("HOW TO PLAY", "help"))
	col.add_child(_button("SETTINGS", "settings_title"))
	if not OS.has_feature("mobile") and not OS.has_feature("HTML5"):
		col.add_child(_button("QUIT", "quit"))
	root.add_child(p)
	return p


func _build_settings() -> Control:
	var p := Panel.new()
	p.rect_size = Vector2(700, 560)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.margin_left = -350
	p.margin_right = 350
	p.margin_top = -280
	p.margin_bottom = 280
	var col := _column(p, Vector2(40, 24), Vector2(620, 500))
	col.add_child(_label("SETTINGS", 40, Color(1.0, 0.88, 0.45)))
	col.add_child(_slider_row("Music volume", Settings.music_volume, 0.0, 1.0, "music"))
	col.add_child(_slider_row("Effects volume", Settings.sfx_volume, 0.0, 1.0, "sfx"))
	col.add_child(_slider_row("Look sensitivity", Settings.look_sensitivity, 0.3, 2.5, "sens"))
	var inv := CheckBox.new()
	inv.text = "Invert Y axis"
	inv.pressed = Settings.invert_y
	inv.connect("toggled", self, "_on_invert")
	col.add_child(inv)
	var fps := CheckBox.new()
	fps.text = "Show FPS"
	fps.pressed = Settings.show_fps
	fps.connect("toggled", self, "_on_fps")
	col.add_child(fps)
	var qrow := HBoxContainer.new()
	qrow.add_child(_label("Graphics  ", 0))
	var ob := OptionButton.new()
	ob.add_item("Low (fast)")
	ob.add_item("Medium")
	ob.add_item("High (shadows, AA)")
	ob.selected = Settings.quality
	ob.connect("item_selected", self, "_on_quality")
	qrow.add_child(ob)
	col.add_child(qrow)
	col.add_child(_button("BACK", "settings_back", 240))
	root.add_child(p)
	return p


func _slider_row(text: String, value: float, lo: float, hi: float, id: String) -> Control:
	var row := HBoxContainer.new()
	row.rect_min_size = Vector2(0, 44)
	var l := _label(text, 0)
	l.rect_min_size = Vector2(230, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.rect_min_size = Vector2(340, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.connect("value_changed", self, "_on_slider", [id])
	row.add_child(s)
	return row


func _build_help() -> Control:
	var p := Panel.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.margin_left = -590
	p.margin_right = 590
	p.margin_top = -300
	p.margin_bottom = 300
	var col := _column(p, Vector2(40, 20), Vector2(1100, 560))
	col.add_child(_label("HOW TO PLAY", 40, Color(1.0, 0.88, 0.45)))
	col.add_child(_label(HELP_GOAL, 21))
	col.add_child(_label("PC", 26, Color(0.6, 0.85, 1.0)))
	col.add_child(_label(HELP_PC, 21))
	col.add_child(_label("PHONE / TABLET", 26, Color(0.6, 0.85, 1.0)))
	col.add_child(_label(HELP_TOUCH, 21))
	col.add_child(_button("BACK", "help_back", 240))
	root.add_child(p)
	return p


func _build_pause() -> Control:
	var p := Panel.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.margin_left = -230
	p.margin_right = 230
	p.margin_top = -230
	p.margin_bottom = 230
	var col := _column(p, Vector2(50, 30), Vector2(360, 400))
	col.add_child(_label("PAUSED", 44, Color(1.0, 0.88, 0.45)))
	col.add_child(_button("RESUME", "resume", 360))
	col.add_child(_button("SETTINGS", "settings_pause", 360))
	col.add_child(_button("HOW TO PLAY", "help_pause", 360))
	col.add_child(_button("QUIT TO MENU", "menu", 360))
	root.add_child(p)
	return p


# ------------------------------------------------------------------ state

func _show_none() -> void:
	title_panel.visible = false
	settings_panel.visible = false
	help_panel.visible = false
	pause_panel.visible = false


func show_title() -> void:
	state = "title"
	_show_none()
	title_panel.visible = true
	get_tree().paused = true
	Controls.capture_mouse(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	orbit_cam.make_current()
	Audio.music("music_menu", 1.0)
	root.mouse_filter = Control.MOUSE_FILTER_PASS


func start_game() -> void:
	state = "hidden"
	_show_none()
	get_tree().paused = false
	if world != null and world.player != null:
		world.player.camera.make_current()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Audio.set_paused(false)
	if world != null:
		world.on_game_started()
	if not Controls.touch_mode and not ("--no-capture" in OS.get_cmdline_args()):
		Controls.capture_mouse(true)


func toggle_pause() -> void:
	if state == "title" or (world != null and world.match_over):
		return
	if state == "paused":
		resume()
	elif state == "hidden":
		state = "paused"
		_show_none()
		pause_panel.visible = true
		get_tree().paused = true
		Audio.set_paused(true)
		Controls.capture_mouse(false)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		root.mouse_filter = Control.MOUSE_FILTER_PASS
	elif state == "settings" or state == "help":
		_back_from_sub()


func resume() -> void:
	state = "hidden"
	_show_none()
	get_tree().paused = false
	Audio.set_paused(false)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Controls.touch_mode and not ("--no-capture" in OS.get_cmdline_args()):
		Controls.capture_mouse(true)


func _open_sub(panel: Control, back_to: String) -> void:
	_settings_return = back_to
	title_panel.visible = false
	pause_panel.visible = false
	panel.visible = true
	state = "settings" if panel == settings_panel else "help"


func _back_from_sub() -> void:
	settings_panel.visible = false
	help_panel.visible = false
	if _settings_return == "title":
		state = "title"
		title_panel.visible = true
	else:
		state = "paused"
		pause_panel.visible = true


func _on_button(id: String) -> void:
	Audio.play2d("ui_click")
	match id:
		"play":
			start_game()
		"help":
			_open_sub(help_panel, "title")
		"settings_title":
			_open_sub(settings_panel, "title")
		"settings_pause":
			_open_sub(settings_panel, "pause")
		"help_pause":
			_open_sub(help_panel, "pause")
		"settings_back", "help_back":
			_back_from_sub()
		"resume":
			resume()
		"menu":
			get_tree().paused = false
			Audio.set_paused(false)
			Settings.autostart = false
			get_tree().reload_current_scene()
		"quit":
			get_tree().quit()


func _on_slider(value: float, id: String) -> void:
	match id:
		"music":
			Settings.music_volume = value
		"sfx":
			Settings.sfx_volume = value
		"sens":
			Settings.look_sensitivity = value
	Settings.save_settings()


func _on_invert(on: bool) -> void:
	Settings.invert_y = on
	Settings.save_settings()


func _on_fps(on: bool) -> void:
	Settings.show_fps = on
	Settings.save_settings()


func _on_quality(idx: int) -> void:
	Settings.quality = idx
	Settings.save_settings()
	if world != null:
		world.apply_quality()


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	fps_label.visible = Settings.show_fps
	if Settings.show_fps:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if state == "title" and world != null:
		_orbit_t += delta * 0.06
		var r := 150.0
		var pos := Vector3(cos(_orbit_t) * r, 70.0, sin(_orbit_t) * r)
		orbit_cam.look_at_from_position(pos, Vector3(0, 6, 0), Vector3.UP)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE and not event.echo:
		toggle_pause()
		get_tree().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.scancode == KEY_ENTER and state == "title":
		_on_button("play")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:      # Android back button
		if state == "hidden" or state == "paused" or state == "settings" or state == "help":
			toggle_pause()
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		if state == "hidden" and world != null and not world.match_over and OS.has_feature("mobile"):
			toggle_pause()                            # auto-pause when the app goes to the background

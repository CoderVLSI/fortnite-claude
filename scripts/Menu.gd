extends CanvasLayer
# Lobby (title screen), settings, how-to-play and pause menu. Built in code; works with mouse and touch.
# While the title or pause menu is open the scene tree is paused (this layer and the Audio
# autoload keep running). The title screen is a Fortnite-style lobby: Lobby.gd's stage with the
# character, a player card, the mode card with the big PLAY button and a tab bar.

const Sprites = preload("res://scripts/Sprites.gd")
const Skins = preload("res://scripts/Skins.gd")
const Cosmetics = preload("res://scripts/Cosmetics.gd")
const Items = preload("res://scripts/Items.gd")
const SplashScreen = preload("res://scripts/ui/SplashScreen.gd")
const FONT_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"
const HELP_PC := "Move: WASD        Look: mouse        Fire: left click        Aim / scope: right click\nJump / handbrake: Space        Sprint: Shift        Reload / horn: R\nPick up / swap / open / enter vehicle: E        Inventory: Tab  (X drops)        Build: Q toggles, Z X C V = wall / floor / ramp / roof, wheel = material\nItems: 1-4 or wheel, F = pickaxe        Map: M        Emote: B        Crouch / slide: Ctrl        Pause: Esc  (all keys can be changed in Settings > Controls)"
const HELP_TOUCH := "Left thumb: move    Right side: look    FIRE / JUMP / SPRINT buttons, scope button to aim down sights\nPICK UP appears next to loot, chests and vehicles    BUILD toggles building\nTap the hotbar to switch items, the bag button for the inventory    Tap the minimap for the island map"
const HELP_GOAL := "Ride the Sky Ferry, jump, glide down and loot.  Fight bots, stay inside the shrinking storm,\ndrive vehicles, swim, climb ledges, take on the Warden at Iron Bunker for Mythic loot.\nBe the last one standing."

const TIPS := [
	"Land away from the crowd, then loot up before the first storm circle.",
	"Pickaxe trees, rocks and buildings to gather wood, stone and metal for building.",
	"Mythic weapons are rare: the Warden at Iron Bunker carries one.",
	"Ramps beat walls: build up to the high ground before you shoot.",
	"Boats and the buggy get you across the island faster than running.",
	"Shield potions stack on top of your health: pop one before every fight.",
]

var world
var lobby
var root: Control
var sprite_button: Button
var tab_underline: ColorRect
var profile_panel: Panel
var profile_body: Control
var profile_error: Label
var profile_fields := {}
var card_sub: Label
var locker_panel: Panel
var locker_list: VBoxContainer
var locker_desc: Label
var locker_tabs := {}
var locker_cat := "skin"
var splash: Control
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
var settings_pages := {}
var settings_tabs := {}
var rebind_buttons := {}
var _rebind_action := ""
var name_edit: LineEdit
var name_label: Label
var mode_info: Label
var stat_labels := {}
var tip_label: Label
var _tip_t := 0.0
var _tip_i := 0
var _press_pos := Vector2.ZERO
var _moved := 0.0


func _ready() -> void:
	layer = 40
	pause_mode = Node.PAUSE_MODE_PROCESS
	root = Control.new()
	root.name = "MenuRoot"
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.theme = _make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	splash = SplashScreen.new()
	splash.connect("start", self, "show_title")
	root.add_child(splash)
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
	orbit_cam.far = 900.0
	orbit_cam.fov = 42.0
	if lobby != null and lobby.env != null:
		orbit_cam.environment = lobby.env
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


func _flat(color: Color, border: Color = Color(0, 0, 0, 0), radius: int = 6, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _style_button(b: Button, normal: StyleBox, hover: StyleBox, text_color: Color, size: int = 0) -> void:
	b.add_stylebox_override("normal", normal)
	b.add_stylebox_override("hover", hover)
	b.add_stylebox_override("pressed", hover)
	b.add_stylebox_override("focus", hover)
	b.add_color_override("font_color", text_color)
	b.add_color_override("font_color_hover", text_color)
	b.add_color_override("font_color_pressed", text_color)
	if size > 0 and _font != null:
		var f := DynamicFont.new()
		f.font_data = _font.font_data
		f.size = size
		f.use_filter = true
		b.add_font_override("font", f)


func _place(c: Control, ax: float, ay: float, off: Vector2, size: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.margin_left = off.x
	c.margin_top = off.y
	c.margin_right = off.x + size.x
	c.margin_bottom = off.y + size.y


func _build_title() -> Control:
	var p := Control.new()
	p.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	var gold := Color(1.0, 0.86, 0.15)

	# top tab bar
	var bar := ColorRect.new()
	bar.color = Color(0.03, 0.05, 0.13, 0.62)
	bar.anchor_right = 1.0
	bar.margin_bottom = 66
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(bar)
	var logo_tex = load("res://assets/ui/logo.png")
	if logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand = true
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.rect_position = Vector2(10, -2)
		logo.rect_size = Vector2(130, 74)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(logo)
	else:
		var logo := _label("STORM ISLAND", 30, gold)
		logo.rect_position = Vector2(26, 15)
		p.add_child(logo)
	var tabs := HBoxContainer.new()
	tabs.add_constant_override("separation", 6)
	_place(tabs, 0.5, 0.0, Vector2(-337, 8), Vector2(674, 50))
	p.add_child(tabs)
	var clear := _flat(Color(0, 0, 0, 0))
	var soft := _flat(Color(1, 1, 1, 0.12))
	for t in [["LOBBY", "lobby"], ["LOCKER", "locker"], ["PROFILE", "profile"], ["HOW TO PLAY", "help"], ["SETTINGS", "settings_title"]]:
		var b := Button.new()
		b.text = t[0]
		b.rect_min_size = Vector2(130, 50)
		b.connect("pressed", self, "_on_button", [t[1]])
		_style_button(b, clear, soft, Color.white if t[1] != "lobby" else gold, 20)
		tabs.add_child(b)
	var underline := ColorRect.new()       # marks the active LOBBY tab
	underline.color = gold
	_place(underline, 0.5, 0.0, Vector2(-337 + 8, 58), Vector2(114, 4))
	tab_underline = underline
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(underline)
	if not OS.has_feature("mobile") and not OS.has_feature("HTML5"):
		var q := Button.new()
		q.text = "QUIT"
		q.rect_min_size = Vector2(100, 46)
		q.connect("pressed", self, "_on_button", ["quit"])
		_style_button(q, _flat(Color(0.8, 0.2, 0.2, 0.8)), _flat(Color(0.95, 0.3, 0.3, 0.95)), Color.white, 20)
		_place(q, 1.0, 0.0, Vector2(-124, 10), Vector2(100, 46))
		p.add_child(q)

	# player card
	var card := Panel.new()
	card.add_stylebox_override("panel", _flat(Color(0.04, 0.07, 0.17, 0.78), Color(1, 1, 1, 0.18), 10, 2))
	_place(card, 0.0, 0.0, Vector2(26, 92), Vector2(330, 150))
	p.add_child(card)
	var avatar := ColorRect.new()
	avatar.color = Color(0.20, 0.45, 0.95)
	avatar.rect_position = Vector2(16, 16)
	avatar.rect_size = Vector2(58, 58)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(avatar)
	var face := ColorRect.new()
	face.color = Color(0.90, 0.72, 0.58)
	face.rect_position = Vector2(14, 12)
	face.rect_size = Vector2(30, 30)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_child(face)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.connect("gui_input", self, "_on_card_input")
	var name_l := _label(Settings.player_name, 30, Color.white)
	name_l.rect_position = Vector2(88, 14)
	card.add_child(name_l)
	name_label = name_l
	var sub := _label("", 15, Color(0.65, 0.78, 1.0))
	sub.rect_position = Vector2(90, 52)
	card.add_child(sub)
	card_sub = sub
	var x := 16.0
	for k in [["MATCHES", "matches"], ["WINS", "wins"], ["ELIMS", "elims"]]:
		var cap := _label(k[0], 14, Color(0.65, 0.78, 1.0))
		cap.rect_position = Vector2(x, 94)
		card.add_child(cap)
		var val := _label("0", 30, gold if k[1] == "wins" else Color.white)
		val.rect_position = Vector2(x, 104)
		card.add_child(val)
		stat_labels[k[1]] = val
		x += 104.0

	# mode card with the PLAY button
	var mode := Panel.new()
	mode.add_stylebox_override("panel", _flat(Color(0.04, 0.07, 0.17, 0.80), Color(1, 1, 1, 0.18), 10, 2))
	_place(mode, 0.0, 1.0, Vector2(26, -236), Vector2(460, 210))
	mode.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(mode)
	var kind := _label("BATTLE ROYALE", 16, Color(0.65, 0.78, 1.0))
	kind.rect_position = Vector2(22, 12)
	mode.add_child(kind)
	var solo := _label("SOLO", 38, Color.white)
	solo.rect_position = Vector2(22, 32)
	mode.add_child(solo)
	mode_info = _label("", 16, Color(0.85, 0.9, 1.0))
	mode_info.rect_position = Vector2(24, 82)
	mode.add_child(mode_info)
	var play := Button.new()
	play.text = "PLAY"
	play.rect_position = Vector2(20, 116)
	play.rect_size = Vector2(420, 78)
	play.connect("pressed", self, "_on_button", ["play"])
	_style_button(play, _flat(gold, Color(0.10, 0.08, 0.02), 4, 3), _flat(Color(1.0, 0.94, 0.45), Color(0.10, 0.08, 0.02), 4, 3), Color(0.08, 0.07, 0.02), 40)
	mode.add_child(play)

	# tips + hint
	tip_label = _label(TIPS[0], 17, Color(1, 1, 1, 0.9))
	tip_label.align = Label.ALIGN_RIGHT
	tip_label.autowrap = true
	_place(tip_label, 1.0, 1.0, Vector2(-560, -78), Vector2(530, 52))
	p.add_child(tip_label)
	var hint := _label("Drag to turn your character  -  tap to wave", 16, Color(1, 1, 1, 0.75))
	hint.align = Label.ALIGN_CENTER
	_place(hint, 0.5, 1.0, Vector2(-250, -30), Vector2(500, 24))
	p.add_child(hint)
	_build_locker(p)
	_build_profile(p)
	return p


# Settings is a set of dedicated pages (tabs): AUDIO, GRAPHICS, CONTROLS (look settings + a rebindable key list) and GAMEPLAY.
func _build_settings() -> Control:
	var gold := Color(1.0, 0.88, 0.45)
	var p := Panel.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.margin_left = -520
	p.margin_right = 520
	p.margin_top = -335
	p.margin_bottom = 335
	var col := _column(p, Vector2(36, 16), Vector2(968, 640))
	col.add_constant_override("separation", 10)
	col.add_child(_label("SETTINGS", 38, gold))
	var tabs := HBoxContainer.new()
	tabs.add_constant_override("separation", 10)
	col.add_child(tabs)
	for t in [["AUDIO", "audio"], ["GRAPHICS", "graphics"], ["CONTROLS", "controls"], ["GAMEPLAY", "gameplay"]]:
		var b := Button.new()
		b.text = t[0]
		b.rect_min_size = Vector2(190, 50)
		b.connect("pressed", self, "_show_settings_page", [t[1]])
		tabs.add_child(b)
		settings_tabs[t[1]] = b
	var holder := Control.new()
	holder.rect_min_size = Vector2(968, 450)
	col.add_child(holder)
	settings_pages["audio"] = _page(holder)
	settings_pages["audio"].add_child(_slider_row("Music volume", Settings.music_volume, 0.0, 1.0, "music"))
	settings_pages["audio"].add_child(_slider_row("Effects volume", Settings.sfx_volume, 0.0, 1.0, "sfx"))

	settings_pages["graphics"] = _page(holder)
	var qrow := HBoxContainer.new()
	var ql := _label("Graphics quality", 0)
	ql.rect_min_size = Vector2(230, 0)
	qrow.add_child(ql)
	var ob := OptionButton.new()
	ob.add_item("Low (fast)")
	ob.add_item("Medium")
	ob.add_item("High (shadows, AA)")
	ob.selected = Settings.quality
	ob.connect("item_selected", self, "_on_quality")
	qrow.add_child(ob)
	settings_pages["graphics"].add_child(qrow)
	var fps := CheckBox.new()
	fps.text = "Show FPS"
	fps.pressed = Settings.show_fps
	fps.connect("toggled", self, "_on_fps")
	settings_pages["graphics"].add_child(fps)

	var cp := _page(holder)
	settings_pages["controls"] = cp
	var look_row := HBoxContainer.new()
	look_row.add_child(_slider_row("Look sensitivity", Settings.look_sensitivity, 0.3, 2.5, "sens"))
	var inv := CheckBox.new()
	inv.text = "Invert Y axis"
	inv.pressed = Settings.invert_y
	inv.connect("toggled", self, "_on_invert")
	look_row.add_child(inv)
	cp.add_child(look_row)
	cp.add_child(_label("Click a key, then press the new key or mouse button (Esc or a left click cancels)", 16, Color(0.7, 0.8, 1.0)))
	var scroll := ScrollContainer.new()
	scroll.rect_min_size = Vector2(968, 255)
	scroll.scroll_horizontal_enabled = false
	cp.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_constant_override("separation", 5)
	list.rect_min_size = Vector2(930, 0)
	scroll.add_child(list)
	var groups := {"move_forward": "MOVEMENT", "fire": "COMBAT", "pickaxe": "ITEMS", "build_toggle": "BUILDING", "inventory": "INTERFACE AND EXTRAS"}
	for entry in Controls.BINDABLE:
		if groups.has(entry[0]):
			list.add_child(_label(groups[entry[0]], 18, Color(0.6, 0.85, 1.0)))
		var row := HBoxContainer.new()
		var rl := _label(entry[1], 0)
		rl.rect_min_size = Vector2(300, 0)
		row.add_child(rl)
		var kb := Button.new()
		kb.rect_min_size = Vector2(300, 38)
		kb.text = Controls.binding_text(entry[0])
		kb.connect("pressed", self, "_begin_rebind", [entry[0]])
		row.add_child(kb)
		rebind_buttons[entry[0]] = kb
		list.add_child(row)
	var reset := Button.new()
	reset.text = "RESET ALL KEYS TO DEFAULT"
	reset.rect_min_size = Vector2(380, 44)
	reset.connect("pressed", self, "_on_reset_keys")
	cp.add_child(reset)

	var gp := _page(holder)
	settings_pages["gameplay"] = gp
	var nrow := HBoxContainer.new()
	var nl := _label("Player name", 0)
	nl.rect_min_size = Vector2(230, 0)
	nrow.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.max_length = 14
	name_edit.rect_min_size = Vector2(340, 44)
	name_edit.connect("text_changed", self, "_on_name_changed")
	nrow.add_child(name_edit)
	gp.add_child(nrow)
	var at := CheckBox.new()
	at.text = "Toggle aim (tap to scope in and out)"
	at.pressed = Settings.aim_toggle
	at.connect("toggled", self, "_on_aim_toggle")
	gp.add_child(at)
	var dn := CheckBox.new()
	dn.text = "Show damage numbers"
	dn.pressed = Settings.damage_numbers
	dn.connect("toggled", self, "_on_damage_numbers")
	gp.add_child(dn)

	var er := CheckBox.new()
	er.text = "Confirm edits on release of the Edit key"
	er.pressed = Settings.edit_on_release
	er.connect("toggled", self, "_on_edit_release")
	gp.add_child(er)
	sprite_button = Button.new()
	sprite_button.rect_min_size = Vector2(520, 44)
	sprite_button.connect("pressed", self, "_on_starter_sprite")
	gp.add_child(sprite_button)
	_refresh_starter_sprite()

	col.add_child(_button("BACK", "settings_back", 240))
	root.add_child(p)
	_show_settings_page("audio")
	return p


func _page(holder: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.rect_position = Vector2.ZERO
	v.rect_size = Vector2(968, 450)
	v.add_constant_override("separation", 12)
	v.visible = false
	holder.add_child(v)
	return v


func _show_settings_page(id: String) -> void:
	_cancel_rebind()
	for k in settings_pages:
		settings_pages[k].visible = (k == id)
		settings_tabs[k].modulate = Color(1.0, 0.88, 0.35) if k == id else Color.white
	Audio.play2d("ui_click", -8.0)


func _begin_rebind(action: String) -> void:
	_cancel_rebind()
	_rebind_action = action
	rebind_buttons[action].text = "Press a key..."
	Audio.play2d("ui_click", -8.0)


func _cancel_rebind() -> void:
	if _rebind_action != "":
		rebind_buttons[_rebind_action].text = Controls.binding_text(_rebind_action)
		_rebind_action = ""


func _refresh_bindings() -> void:
	for a in rebind_buttons:
		rebind_buttons[a].text = Controls.binding_text(a)


func _on_reset_keys() -> void:
	_cancel_rebind()
	Controls.reset_bindings()
	_refresh_bindings()
	Audio.play2d("ui_click", -6.0)


func _on_name_changed(text: String) -> void:
	Settings.player_name = text.strip_edges().to_upper() if text.strip_edges() != "" else "PLAYER"
	Settings.save_settings()
	if name_label != null:
		name_label.text = Settings.player_name


# ------------------------------------------------------------------ account / profile

func _move_underline(idx: int) -> void:
	tab_underline.margin_left = -337 + 8 + 136 * idx
	tab_underline.margin_right = tab_underline.margin_left + 114


func _on_card_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		_on_button("profile")


func _build_profile(parent: Control) -> void:
	profile_panel = Panel.new()
	profile_panel.add_stylebox_override("panel", _flat(Color(0.03, 0.05, 0.13, 1.0), Color(1, 1, 1, 0.25), 10, 2))
	_place(profile_panel, 0.0, 0.0, Vector2(26, 80), Vector2(500, 630))
	profile_panel.visible = false
	parent.add_child(profile_panel)
	profile_body = Control.new()
	profile_body.rect_size = Vector2(500, 630)
	profile_panel.add_child(profile_body)


func _pf_clear() -> void:
	for ch in profile_body.get_children():
		profile_body.remove_child(ch)
		ch.queue_free()
	profile_fields.clear()
	profile_error = null


func _pf_label(text: String, size: int, pos: Vector2, color: Color = Color.white) -> Label:
	var l := _label(text, size, color)
	l.rect_position = pos
	profile_body.add_child(l)
	return l


func _pf_button(text: String, pos: Vector2, size: Vector2, method: String, args: Array = []) -> Button:
	var b := Button.new()
	b.text = text
	b.rect_position = pos
	b.rect_size = size
	b.connect("pressed", self, method, args)
	profile_body.add_child(b)
	return b


func _pf_field(key: String, caption: String, y: float, secret: bool = false) -> void:
	_pf_label(caption, 15, Vector2(24, y), Color(0.65, 0.78, 1.0))
	var e := LineEdit.new()
	e.rect_position = Vector2(24, y + 22)
	e.rect_size = Vector2(452, 42)
	e.secret = secret
	e.max_length = 64
	profile_body.add_child(e)
	profile_fields[key] = e


static func _fmt_time(seconds: int) -> String:
	return "%dh %02dm" % [seconds / 3600, (seconds % 3600) / 60] if seconds >= 3600 else "%dm %02ds" % [seconds / 60, seconds % 60]


func profile_show(view: String) -> void:
	_pf_clear()
	match view:
		"signin":
			_pf_label("SIGN IN", 30, Vector2(24, 14), Color(1.0, 0.82, 0.25))
			_pf_field("email", "EMAIL", 70)
			_pf_field("password", "PASSWORD", 150, true)
			profile_error = _pf_label("", 15, Vector2(24, 232), Color(1.0, 0.45, 0.4))
			_pf_button("SIGN IN", Vector2(24, 270), Vector2(452, 52), "profile_submit", ["signin"])
			_pf_button("BACK", Vector2(24, 334), Vector2(452, 46), "profile_show", ["home"])
		"create":
			_pf_label("CREATE ACCOUNT", 30, Vector2(24, 14), Color(1.0, 0.82, 0.25))
			_pf_label("Your guest progress (stats and Locker) moves into the new account.", 14, Vector2(24, 52), Color(0.85, 0.9, 1.0))
			_pf_field("email", "EMAIL", 84)
			_pf_field("name", "DISPLAY NAME", 164)
			_pf_field("password", "PASSWORD (6+ CHARACTERS)", 244, true)
			_pf_field("confirm", "CONFIRM PASSWORD", 324, true)
			profile_error = _pf_label("", 15, Vector2(24, 406), Color(1.0, 0.45, 0.4))
			_pf_button("CREATE ACCOUNT", Vector2(24, 440), Vector2(452, 52), "profile_submit", ["create"])
			_pf_button("BACK", Vector2(24, 504), Vector2(452, 46), "profile_show", ["home"])
		_:
			_pf_home()


func _pf_home() -> void:
	var guest: bool = Accounts.is_guest()
	_pf_label(Accounts.display_name(), 32, Vector2(24, 12))
	_pf_label("GUEST - progress is saved on this device only" if guest else Accounts.email(), 15, Vector2(24, 54), Color(0.65, 0.78, 1.0))
	var lp: Array = Accounts.level_progress()
	_pf_label("LEVEL %d" % Accounts.level(), 20, Vector2(24, 80), Color(1.0, 0.82, 0.25))
	var bar := ProgressBar.new()
	bar.rect_position = Vector2(130, 86)
	bar.rect_size = Vector2(346, 18)
	bar.max_value = max(lp[1], 1)
	bar.value = lp[0]
	bar.percent_visible = false
	profile_body.add_child(bar)
	var rows := [["MATCHES", str(Accounts.stat("matches"))], ["WINS", str(Accounts.stat("wins"))],
		["WIN RATE", "%d%%" % int(round(Accounts.win_rate() * 100.0))], ["TOP 3 FINISHES", str(Accounts.stat("top3"))],
		["ELIMINATIONS", str(Accounts.stat("elims"))], ["K / D", "%.2f" % Accounts.kd()], ["BEST ELIMS IN A MATCH", str(Accounts.stat("best_kills"))],
		["BEST PLACEMENT", ("#%d" % Accounts.stat("best_placement")) if Accounts.stat("best_placement") > 0 else "-"],
		["DAMAGE DEALT", str(Accounts.stat("damage"))], ["HEADSHOTS", str(Accounts.stat("headshots"))], ["CHESTS OPENED", str(Accounts.stat("chests"))],
		["PIECES BUILT", str(Accounts.stat("builds"))], ["TIME PLAYED", _fmt_time(Accounts.stat("playtime"))],
		["LONGEST SURVIVAL", _fmt_time(Accounts.stat("longest_survival"))]]
	var y := 122.0
	for r in rows:
		var l := _pf_label(r[0], 15, Vector2(24, y), Color(0.65, 0.78, 1.0))
		var v := _pf_label(r[1], 18, Vector2(300, y - 2))
		y += 28.0
	if guest:
		_pf_button("CREATE ACCOUNT", Vector2(24, 536), Vector2(220, 52), "profile_show", ["create"])
		_pf_button("SIGN IN", Vector2(256, 536), Vector2(220, 52), "profile_show", ["signin"])
	else:
		_pf_button("SIGN OUT", Vector2(24, 536), Vector2(452, 52), "profile_sign_out")


func profile_submit(kind: String) -> void:
	var err := ""
	var e: String = profile_fields["email"].text
	var pw: String = profile_fields["password"].text
	if kind == "create":
		if pw != profile_fields["confirm"].text:
			err = "The passwords do not match."
		else:
			err = Accounts.create_account(e, pw, profile_fields["name"].text)
	else:
		err = Accounts.sign_in(e, pw)
	if err != "":
		if profile_error != null:
			profile_error.text = err
		Audio.play2d("ui_error", -6.0)
		return
	Audio.play2d("loot_pickup", -4.0)
	_after_account_change()
	profile_show("home")


func profile_sign_out() -> void:
	Accounts.sign_out()
	_after_account_change()
	profile_show("home")


# A different profile is active: the lobby shows its name, stats and Locker.
func _after_account_change() -> void:
	if name_edit != null:
		name_edit.text = Settings.player_name
	_refresh_lobby()
	if lobby != null:
		lobby.apply_loadout(Settings.loadout, true)
	if sprite_button != null:
		_refresh_starter_sprite()
	if locker_panel != null:
		locker_show(locker_cat)


# ------------------------------------------------------------------ the Locker

func _build_locker(parent: Control) -> void:
	locker_panel = Panel.new()
	locker_panel.add_stylebox_override("panel", _flat(Color(0.03, 0.05, 0.13, 1.0), Color(1, 1, 1, 0.25), 10, 2))
	_place(locker_panel, 0.0, 0.0, Vector2(26, 80), Vector2(440, 620))
	locker_panel.visible = false
	parent.add_child(locker_panel)
	var title := _label("LOCKER", 30, Color(1.0, 0.82, 0.25))
	title.rect_position = Vector2(18, 10)
	locker_panel.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.rect_position = Vector2(14, 58)
	grid.add_constant_override("hseparation", 6)
	grid.add_constant_override("vseparation", 6)
	locker_panel.add_child(grid)
	for cat in Cosmetics.CATEGORIES:
		var b := Button.new()
		b.text = Cosmetics.TITLES[cat]
		b.rect_min_size = Vector2(134, 40)
		b.connect("pressed", self, "locker_show", [cat])
		grid.add_child(b)
		locker_tabs[cat] = b
	var scroll := ScrollContainer.new()
	scroll.rect_position = Vector2(14, 176)
	scroll.rect_size = Vector2(412, 380)
	scroll.scroll_horizontal_enabled = false
	locker_panel.add_child(scroll)
	locker_list = VBoxContainer.new()
	locker_list.add_constant_override("separation", 6)
	locker_list.rect_min_size = Vector2(390, 10)
	scroll.add_child(locker_list)
	locker_desc = _label("", 15, Color(0.85, 0.9, 1.0))
	locker_desc.rect_position = Vector2(18, 566)
	locker_panel.add_child(locker_desc)
	locker_show("skin")


func locker_show(cat: String) -> void:
	locker_cat = cat
	for c in locker_tabs:
		locker_tabs[c].modulate = Color(1.0, 0.88, 0.35) if c == cat else Color.white
	for ch in locker_list.get_children():
		locker_list.remove_child(ch)
		ch.queue_free()
	var t: Dictionary = Cosmetics.table(cat)
	for id in Cosmetics.order(cat):
		var d: Dictionary = t[id]
		var b := Button.new()
		var equipped: bool = Settings.loadout[cat] == id
		b.text = ("[x]  " if equipped else "      ") + d.name
		b.rect_min_size = Vector2(390, 50)
		b.align = Button.ALIGN_LEFT
		b.clip_text = true
		var rc: Color = Cosmetics.rarity_color(d.rarity)
		b.add_color_override("font_color", rc.lightened(0.25))
		b.add_color_override("font_color_hover", rc.lightened(0.5))
		if equipped:
			b.modulate = Color(1.0, 0.95, 0.6)
		b.connect("pressed", self, "locker_select", [cat, id])
		locker_list.add_child(b)
	var cur: Dictionary = t[Settings.loadout[cat]]
	locker_desc.text = "%s  -  %s" % [Items.RARITIES[cur.rarity].name, cur.desc]
	if get_tree() != null:
		Audio.play2d("ui_click", -10.0)


func locker_select(cat: String, id: String) -> void:
	Settings.loadout[cat] = id
	Settings.save_settings()
	if lobby != null:
		lobby.apply_loadout(Settings.loadout, true)
	Audio.play2d("ui_click", -6.0)
	locker_show(cat)


func _on_starter_sprite() -> void:
	var i: int = Sprites.STARTERS.find(Settings.starter_sprite)
	Settings.starter_sprite = Sprites.STARTERS[(i + 1) % Sprites.STARTERS.size()]
	Settings.save_settings()
	_refresh_starter_sprite()


func _refresh_starter_sprite() -> void:
	var id: String = Settings.starter_sprite
	sprite_button.text = "Starting Sprite: %s  (click to change)" % ("None" if id == "none" else Sprites.LIST[id].name)


func _on_aim_toggle(on: bool) -> void:
	Settings.aim_toggle = on
	Settings.save_settings()


func _on_edit_release(on: bool) -> void:
	Settings.edit_on_release = on
	Settings.save_settings()


func _on_damage_numbers(on: bool) -> void:
	Settings.damage_numbers = on
	Settings.save_settings()


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
	splash.visible = false
	title_panel.visible = false
	settings_panel.visible = false
	help_panel.visible = false
	pause_panel.visible = false


func _refresh_lobby() -> void:
	stat_labels["matches"].text = str(Accounts.stat("matches"))
	stat_labels["wins"].text = str(Accounts.stat("wins"))
	stat_labels["elims"].text = str(Accounts.stat("elims"))
	if name_label != null:
		name_label.text = Accounts.display_name()
	if card_sub != null:
		card_sub.text = "LEVEL %d   -   %s" % [Accounts.level(), "GUEST (click to sign in)" if Accounts.is_guest() else Accounts.email()]
	var bots: int = world.profile.get("bots", 24) if world != null else 24
	mode_info.text = "%d players  -  shrinking storm  -  Mythic boss" % (bots + 1)


# The very first screen: the lightning title splash. Press the interact key (E) / tap to continue to the lobby.
func show_splash() -> void:
	state = "splash"
	_show_none()
	get_tree().paused = true
	Controls.capture_mouse(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	orbit_cam.make_current()
	Audio.music("music_menu", 1.0)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	splash.open()


func show_title() -> void:
	state = "title"
	_refresh_lobby()
	_show_none()
	title_panel.visible = true
	get_tree().paused = true
	Controls.capture_mouse(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	orbit_cam.make_current()
	if lobby != null:
		lobby.set_active(true)
	Audio.music("music_menu", 1.0)
	root.mouse_filter = Control.MOUSE_FILTER_PASS


func start_game() -> void:
	state = "hidden"
	_show_none()
	get_tree().paused = false
	if world != null and world.player != null:
		world.player.camera.make_current()
	if lobby != null:
		lobby.set_active(false)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Audio.set_paused(false)
	if world != null:
		world.on_game_started()
	if not Controls.touch_mode and not ("--no-capture" in OS.get_cmdline_args()):
		Controls.capture_mouse(true)


func toggle_pause() -> void:
	if state == "title" or state == "splash" or (world != null and world.match_over):
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
	_cancel_rebind()
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
		"lobby":
			locker_panel.visible = false
			profile_panel.visible = false
			_move_underline(0)
		"locker":
			locker_panel.visible = true
			profile_panel.visible = false
			_move_underline(1)
			locker_show(locker_cat)
		"profile":
			locker_panel.visible = false
			profile_panel.visible = true
			_move_underline(2)
			profile_show("home")
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
	if state == "title" and lobby != null:
		orbit_cam.global_transform = lobby.camera_transform()
		_tip_t += delta
		if _tip_t > 6.0:
			_tip_t = 0.0
			_tip_i = (_tip_i + 1) % TIPS.size()
			tip_label.text = TIPS[_tip_i]


func _input(event: InputEvent) -> void:
	if _rebind_action != "" and event.is_pressed() and not event.is_echo():
		if event is InputEventKey:
			if event.scancode == KEY_ESCAPE:
				_cancel_rebind()
			else:
				Controls.set_binding(_rebind_action, "key", event.scancode)
				_rebind_action = ""
				_refresh_bindings()
			get_tree().set_input_as_handled()
			return
		elif event is InputEventMouseButton:
			if event.button_index == BUTTON_LEFT:
				_cancel_rebind()                              # a left click elsewhere just cancels (it would also steal Fire)
			else:      # right, middle, wheel and the side buttons (XBUTTON1 / XBUTTON2)
				Controls.set_binding(_rebind_action, "mouse", event.button_index)
				_rebind_action = ""
				_refresh_bindings()
				get_tree().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE and not event.echo:
		if world != null and world.hud != null and world.hud.inventory.visible:
			world.hud.close_inventory()                 # Esc closes the inventory screen before it pauses the game
			get_tree().set_input_as_handled()
			return
		if world != null and world.hud != null and world.hud.editor.visible:
			world.hud.editor.cancel()                   # ... and the build editor
			get_tree().set_input_as_handled()
			return
		toggle_pause()
		get_tree().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.scancode == KEY_ENTER and state == "title":
		_on_button("play")


# Drag on empty space turns the lobby character; a tap (almost no movement) makes it wave.
func _unhandled_input(event: InputEvent) -> void:
	if state != "title" or lobby == null:
		return
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		lobby.dragging = event.pressed
		if event.pressed:
			_press_pos = event.position
			_moved = 0.0
		elif _moved < 8.0:
			lobby.wave()
			Audio.play2d("ui_click", -8.0)
	elif event is InputEventMouseMotion and lobby.dragging:
		_moved += event.relative.length()
		lobby.yaw = clamp(lobby.yaw + event.relative.x * 0.012, -3.2, 3.2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:      # Android back button
		if state == "hidden" or state == "paused" or state == "settings" or state == "help":
			toggle_pause()
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		if state == "hidden" and world != null and not world.match_over and OS.has_feature("mobile"):
			toggle_pause()                            # auto-pause when the app goes to the background

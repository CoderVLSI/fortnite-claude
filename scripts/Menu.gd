extends CanvasLayer
# Lobby (title screen), settings, how-to-play and pause menu. Built in code; works with mouse and touch.
# While the title or pause menu is open the scene tree is paused (this layer and the Audio
# autoload keep running). The title screen is a Fortnite-style lobby: Lobby.gd's stage with the
# character, a player card, the mode card with the big PLAY button and a tab bar.

const Sprites = preload("res://scripts/Sprites.gd")
const Skins = preload("res://scripts/Skins.gd")
const Cosmetics = preload("res://scripts/Cosmetics.gd")
const Emotes = preload("res://scripts/Emotes.gd")
const Items = preload("res://scripts/Items.gd")
const SplashScreen = preload("res://scripts/ui/SplashScreen.gd")
const FONT_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"
const HELP_PC := "Move: WASD        Look: mouse        Fire: left click        Aim / scope: right click\nJump / handbrake: Space        Sprint: Shift        Reload / horn: R\nPick up / swap / open / enter vehicle: E        Inventory: Tab  (X drops)        Build: Q toggles, Z X C V = wall / floor / ramp / roof, wheel = material\nItems: 1-5 or wheel, F = pickaxe        Map: M        Emote: B        Crouch / slide: Ctrl        Pause: Esc  (all keys can be changed in Settings > Controls)"
const HELP_TOUCH := "Left thumb: move    Right side: look    FIRE / JUMP / SPRINT buttons, scope button to aim down sights\nPICK UP appears next to loot, chests and vehicles    BUILD toggles building\nTap the hotbar to switch items, the bag button for the inventory    Tap the minimap for the island map"
const HELP_PAD := "Xbox / PlayStation / Switch pads work as soon as they are connected:  left stick move, right stick look, RT fire, LT aim, A jump, B crouch\nX reload / pick up, Y build mode, D-Pad = wall / floor / ramp / roof, LB RB switch item (or material), L3 sprint, R3 edit, View = inventory, Menu = pause\nIn menus: D-Pad / stick + A to choose, B to go back, LB RB change tab   (Settings > Controls shows the controller and lets you remap every button)"
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
var party_panel: Panel
var party_body: Control
var party_error: Label
var party_fields := {}
var party_view := "home"
var wait_panel: Panel
var wait_label: Label
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
var pad_buttons := {}
var gpu_note: Label
var pad_status: Label
var play_button: Button
var _rebind_action := ""
var _rebind_pad := false
var _title_tab := 0
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
	_place(tabs, 0.5, 0.0, Vector2(-405, 8), Vector2(810, 50))
	p.add_child(tabs)
	var clear := _flat(Color(0, 0, 0, 0))
	var soft := _flat(Color(1, 1, 1, 0.12))
	for t in [["LOBBY", "lobby"], ["LOCKER", "locker"], ["PROFILE", "profile"], ["PARTY", "party"], ["HOW TO PLAY", "help"], ["SETTINGS", "settings_title"]]:
		var b := Button.new()
		b.text = t[0]
		b.rect_min_size = Vector2(130, 50)
		b.connect("pressed", self, "_on_button", [t[1]])
		_style_button(b, clear, soft, Color.white if t[1] != "lobby" else gold, 20)
		tabs.add_child(b)
	var underline := ColorRect.new()       # marks the active LOBBY tab
	underline.color = gold
	_place(underline, 0.5, 0.0, Vector2(-405 + 8, 58), Vector2(114, 4))
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
	play_button = play

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
	_build_party(p)
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
	if OS.get_name() == "Windows":
		var gpu := Button.new()
		gpu.text = "USE MY HIGH-PERFORMANCE GPU (laptops with NVIDIA / AMD)"
		gpu.rect_min_size = Vector2(620, 44)
		gpu.connect("pressed", self, "_on_high_gpu")
		settings_pages["graphics"].add_child(gpu)
		gpu_note = _label("The game may be running on the weak built-in graphics. This tells Windows to use the fast GPU for Storm Island, then restart the game.", 15, Color(0.7, 0.8, 1.0))
		gpu_note.autowrap = true
		gpu_note.rect_min_size = Vector2(900, 0)
		settings_pages["graphics"].add_child(gpu_note)
	var adapter := _label("Graphics card in use: " + VisualServer.get_video_adapter_name(), 16, Color(0.8, 0.95, 0.8))
	settings_pages["graphics"].add_child(adapter)
	var auto := CheckBox.new()
	auto.text = "Auto-adjust graphics when the game runs slowly"
	auto.pressed = Settings.auto_graphics
	auto.connect("toggled", self, "_on_auto_graphics")
	settings_pages["graphics"].add_child(auto)

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
	pad_status = _label("", 17, Color(0.55, 1.0, 0.65))
	cp.add_child(pad_status)
	cp.add_child(_label("Click a binding, then press the new key / mouse button / pad button  (Esc or Menu cancels)", 15, Color(0.7, 0.8, 1.0)))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.rect_min_size = Vector2(968, 235)
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
		rl.rect_min_size = Vector2(270, 0)
		row.add_child(rl)
		var kb := Button.new()
		kb.rect_min_size = Vector2(280, 38)
		kb.text = Controls.binding_text(entry[0])
		kb.connect("pressed", self, "_begin_rebind", [entry[0]])
		row.add_child(kb)
		rebind_buttons[entry[0]] = kb
		var pb := Button.new()
		pb.rect_min_size = Vector2(220, 38)
		pb.text = Controls.pad_binding_text(entry[0])
		if entry[0] in Controls.MOVE_ACTIONS:
			pb.disabled = true                      # the sticks are fixed: left = move, right = look
		pb.connect("pressed", self, "_begin_pad_rebind", [entry[0]])
		row.add_child(pb)
		pad_buttons[entry[0]] = pb
		list.add_child(row)
	var rrow := HBoxContainer.new()
	rrow.add_constant_override("separation", 14)
	var reset := Button.new()
	reset.text = "RESET KEYS"
	reset.rect_min_size = Vector2(240, 44)
	reset.connect("pressed", self, "_on_reset_keys")
	rrow.add_child(reset)
	var reset_pad := Button.new()
	reset_pad.text = "RESET CONTROLLER"
	reset_pad.rect_min_size = Vector2(280, 44)
	reset_pad.connect("pressed", self, "_on_reset_pad")
	rrow.add_child(reset_pad)
	cp.add_child(rrow)
	Controls.connect("pad_changed", self, "_on_pad_changed")
	_on_pad_changed(Controls.pad_name != "", Controls.pad_name)

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
	er.text = "Hold-to-edit (confirm on release)"
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
	_rebind_pad = false
	rebind_buttons[action].text = "Press a key..."
	Audio.play2d("ui_click", -8.0)


func _begin_pad_rebind(action: String) -> void:
	_cancel_rebind()
	_rebind_action = action
	_rebind_pad = true
	pad_buttons[action].text = "Press a button..."
	Audio.play2d("ui_click", -8.0)


func _cancel_rebind() -> void:
	if _rebind_action != "":
		rebind_buttons[_rebind_action].text = Controls.binding_text(_rebind_action)
		pad_buttons[_rebind_action].text = Controls.pad_binding_text(_rebind_action)
		_rebind_action = ""


func _refresh_bindings() -> void:
	for a in rebind_buttons:
		rebind_buttons[a].text = Controls.binding_text(a)
		pad_buttons[a].text = Controls.pad_binding_text(a)


func _on_pad_changed(connected: bool, pad_name: String) -> void:
	if pad_status != null:
		if connected:
			pad_status.text = "Controller detected: %s  (%s buttons)  -  it works right away, no setup needed" % [pad_name, {"xbox": "Xbox", "ps": "PlayStation", "nintendo": "Nintendo"}[Controls.pad_style()]]
			pad_status.modulate = Color(0.55, 1.0, 0.65)
		else:
			pad_status.text = "No controller detected - plug one in (USB) or pair it (Bluetooth) and it shows up here"
			pad_status.modulate = Color(1.0, 0.85, 0.5)
	_refresh_bindings()
	var hud = world.hud if world != null else null
	if hud != null and state == "hidden":
		hud.show_toast(("Controller connected: " + pad_name) if connected else "Controller disconnected")


func _on_reset_pad() -> void:
	_cancel_rebind()
	Controls.reset_pad_bindings()
	_refresh_bindings()
	Audio.play2d("ui_click", -6.0)


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


# ------------------------------------------------------------------ party (LAN multiplayer)

func _build_party(parent: Control) -> void:
	party_panel = Panel.new()
	party_panel.add_stylebox_override("panel", _flat(Color(0.03, 0.05, 0.13, 1.0), Color(1, 1, 1, 0.25), 10, 2))
	_place(party_panel, 0.0, 0.0, Vector2(26, 80), Vector2(540, 630))
	party_panel.visible = false
	parent.add_child(party_panel)
	party_body = Control.new()
	party_body.rect_size = Vector2(540, 630)
	party_panel.add_child(party_body)
	Net.connect("party_changed", self, "_on_party_changed")
	Net.connect("joined", self, "_on_party_joined")
	Net.connect("join_failed", self, "_on_party_failed")
	Net.connect("left", self, "_on_party_left")
	Net.connect("match_starting", self, "_on_match_starting")
	Net.connect("games_found", self, "_on_games_found")
	wait_panel = Panel.new()
	wait_panel.add_stylebox_override("panel", _flat(Color(0.02, 0.03, 0.08, 0.92), Color(1, 1, 1, 0.2), 10, 2))
	_place(wait_panel, 0.5, 0.5, Vector2(-300, -60), Vector2(600, 120))
	wait_panel.visible = false
	root.add_child(wait_panel)
	wait_label = _label("", 26, Color(1.0, 0.88, 0.45))
	wait_label.rect_position = Vector2(24, 40)
	wait_panel.add_child(wait_label)


func show_waiting(text: String) -> void:
	state = "waiting"
	_show_none()
	get_tree().paused = true
	Controls.capture_mouse(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	orbit_cam.make_current()
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	wait_label.text = text
	wait_panel.visible = true


func _pt_clear() -> void:
	for ch in party_body.get_children():
		party_body.remove_child(ch)
		ch.queue_free()
	party_fields.clear()
	party_error = null


func _pt_label(text: String, size: int, pos: Vector2, color: Color = Color.white) -> Label:
	var l := _label(text, size, color)
	l.rect_position = pos
	party_body.add_child(l)
	return l


func _pt_button(text: String, pos: Vector2, size: Vector2, method: String, args: Array = []) -> Button:
	var b := Button.new()
	b.text = text
	b.rect_position = pos
	b.rect_size = size
	b.connect("pressed", self, method, args)
	party_body.add_child(b)
	return b


func party_show(view: String) -> void:
	party_view = view
	_pt_clear()
	if view == "party" and Net.active:
		_party_view()
		return
	party_view = "home"
	_pt_label("PLAY WITH FRIENDS", 30, Vector2(24, 14), Color(1.0, 0.82, 0.25))
	_pt_label("Same Wi-Fi / network. Everybody needs the same version of the game.", 14, Vector2(24, 54), Color(0.85, 0.9, 1.0))
	_pt_button("HOST A GAME", Vector2(24, 92), Vector2(492, 58), "party_host")
	_pt_label("OR JOIN A GAME", 15, Vector2(24, 172), Color(0.65, 0.78, 1.0))
	var e := LineEdit.new()
	e.rect_position = Vector2(24, 196)
	e.rect_size = Vector2(340, 46)
	e.placeholder_text = "host's IP, e.g. 192.168.1.20"
	e.text = _last_ip
	party_body.add_child(e)
	party_fields["ip"] = e
	_pt_button("JOIN", Vector2(376, 196), Vector2(140, 46), "party_join")
	_pt_label("GAMES FOUND ON YOUR NETWORK", 15, Vector2(24, 270), Color(0.65, 0.78, 1.0))
	party_error = _pt_label("", 15, Vector2(24, 566), Color(1.0, 0.45, 0.4))
	Net.start_discovery()
	_games_list()


var _last_ip := ""


func _games_list() -> void:
	if party_view != "home":
		return
	for ch in party_body.get_children():
		if ch.has_meta("game_row"):
			party_body.remove_child(ch)
			ch.queue_free()
	var y := 296.0
	for ip in Net.sessions.keys():
		var s: Dictionary = Net.sessions[ip]
		var b := Button.new()
		b.text = "%s   (%d player%s)   %s" % [s.name, s.players, "" if s.players == 1 else "s", ip]
		b.rect_position = Vector2(24, y)
		b.rect_size = Vector2(492, 46)
		b.set_meta("game_row", true)
		b.connect("pressed", self, "party_join_ip", [ip, int(s.port)])
		party_body.add_child(b)
		y += 54.0
	if Net.sessions.empty():
		var l := _label("Searching... if nothing shows up, type the host's IP above.", 14, Color(0.7, 0.75, 0.9))
		l.rect_position = Vector2(24, 300)
		l.set_meta("game_row", true)
		party_body.add_child(l)


func _on_games_found() -> void:
	_games_list()


func _party_view() -> void:
	_pt_label("PARTY", 30, Vector2(24, 14), Color(1.0, 0.82, 0.25))
	if Net.is_host:
		var addr := "  /  ".join(Net.local_addresses())
		_pt_label("You are hosting.  Friends join with:  %s   (port %d)" % [addr if addr != "" else "your IP", Net.PORT], 14, Vector2(24, 54), Color(0.85, 0.9, 1.0))
	else:
		_pt_label("Connected. Waiting for the host to start the match.", 14, Vector2(24, 54), Color(0.85, 0.9, 1.0))
	var y := 96.0
	var ids := Net.members.keys()
	ids.sort()
	for id in ids:
		var m: Dictionary = Net.members[id]
		_pt_label("%s%s" % [m.name, "   (host)" if id == 1 else ""] + ("   (you)" if id == Net.my_id else ""), 22, Vector2(24, y))
		y += 38.0
	_pt_label("%d player%s + %d bots" % [Net.human_count(), "" if Net.human_count() == 1 else "s", max(Net.TOTAL_FIGHTERS - Net.human_count(), 0)], 15, Vector2(24, y + 6), Color(0.65, 0.78, 1.0))
	party_error = _pt_label("", 15, Vector2(24, 520), Color(1.0, 0.45, 0.4))
	if Net.is_host:
		_pt_button("START MATCH", Vector2(24, 460), Vector2(492, 56), "party_start")
	_pt_button("LEAVE PARTY", Vector2(24, 536), Vector2(492, 52), "party_leave")


func party_host() -> void:
	var err := Net.host_game(Settings.player_name, Settings.loadout)
	if err != "":
		if party_error != null:
			party_error.text = err
		return
	Audio.play2d("loot_pickup", -6.0)
	party_show("party")


func party_join() -> void:
	var ip: String = party_fields["ip"].text
	_last_ip = ip
	party_join_ip(ip, Net.PORT)


func party_join_ip(ip: String, port: int) -> void:
	var err := Net.join_game(ip, Settings.player_name, Settings.loadout, port)
	if err != "":
		if party_error != null:
			party_error.text = err
		return
	if party_error != null:
		party_error.text = "Connecting..."
		party_error.add_color_override("font_color", Color(0.8, 0.9, 1.0))


func party_start() -> void:
	Net.start_match()


func party_leave() -> void:
	Net.leave("")
	party_show("home")


func _on_party_changed() -> void:
	if party_panel != null and party_panel.visible and Net.active:
		party_show("party")


func _on_party_joined() -> void:
	Net.stop_discovery()
	if party_panel != null:
		party_show("party")
	_on_button("party")


func _on_party_failed(reason: String) -> void:
	if party_panel != null and party_panel.visible:
		party_show("home")
		if party_error != null:
			party_error.text = reason


func _on_party_left(reason: String) -> void:
	if party_panel != null and party_panel.visible:
		party_show("home")
		if party_error != null and reason != "":
			party_error.text = reason


# The host started the match: reload the world with the shared seed.
func _on_match_starting() -> void:
	get_tree().paused = false
	Settings.autostart = false
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ account / profile

func _move_underline(idx: int) -> void:
	tab_underline.margin_left = -405 + 8 + 136 * idx
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
func _side_panels(show: Control) -> void:
	for pn in [locker_panel, profile_panel, party_panel]:
		pn.visible = (pn == show)
	if show != party_panel:
		Net.stop_discovery()


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
	for cat in Cosmetics.CATEGORIES + ["emote"]:
		var b := Button.new()
		b.text = Cosmetics.TITLES.get(cat, "EMOTES")
		b.rect_min_size = Vector2(134, 40)
		b.connect("pressed", self, "locker_show", [cat])
		grid.add_child(b)
		locker_tabs[cat] = b
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
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
	if cat == "emote":
		_locker_emotes()
		return
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


# Emotes: click to put one on the wheel or take it off (the wheel keeps at least one and holds up to 8).
func _locker_emotes() -> void:
	var wheel: Array = Emotes.sanitize_wheel(Settings.emote_wheel)
	for id in Emotes.ORDER:
		var d: Dictionary = Emotes.LIST[id]
		var b := Button.new()
		var on: bool = id in wheel
		b.text = ("[x]  " if on else "      ") + d.name
		b.rect_min_size = Vector2(390, 50)
		b.align = Button.ALIGN_LEFT
		b.clip_text = true
		var rc: Color = Cosmetics.rarity_color(d.rarity)
		b.add_color_override("font_color", rc.lightened(0.25))
		b.add_color_override("font_color_hover", rc.lightened(0.5))
		if on:
			b.modulate = Color(1.0, 0.95, 0.6)
		b.connect("pressed", self, "locker_toggle_emote", [id])
		locker_list.add_child(b)
	locker_desc.text = "Emote wheel: %d / %d  -  hold %s in a match to open it. Click to add or remove." % [wheel.size(), Emotes.WHEEL_SIZE, Controls.key_label("emote")]
	if get_tree() != null:
		Audio.play2d("ui_click", -10.0)


func locker_toggle_emote(id: String) -> void:
	var wheel: Array = Emotes.sanitize_wheel(Settings.emote_wheel)
	if id in wheel:
		if wheel.size() > 1:
			wheel.erase(id)
	elif wheel.size() < Emotes.WHEEL_SIZE:
		wheel.append(id)
	Settings.emote_wheel = wheel
	Settings.save_settings()
	Audio.play2d("ui_click", -6.0)
	locker_show("emote")


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
	p.margin_top = -330
	p.margin_bottom = 330
	var head := _column(p, Vector2(40, 14), Vector2(1100, 60))
	head.add_child(_label("HOW TO PLAY", 40, Color(1.0, 0.88, 0.45)))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.rect_position = Vector2(40, 74)
	scroll.rect_size = Vector2(1110, 500)
	scroll.scroll_horizontal_enabled = false
	p.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_constant_override("separation", 8)
	col.rect_min_size = Vector2(1090, 0)
	scroll.add_child(col)
	col.add_child(_wrapped(HELP_GOAL, 19))
	col.add_child(_label("PC", 24, Color(0.6, 0.85, 1.0)))
	col.add_child(_wrapped(HELP_PC, 18))
	col.add_child(_label("CONTROLLER", 24, Color(0.6, 0.85, 1.0)))
	col.add_child(_wrapped(HELP_PAD, 18))
	col.add_child(_label("PHONE / TABLET", 24, Color(0.6, 0.85, 1.0)))
	col.add_child(_wrapped(HELP_TOUCH, 18))
	var foot := _column(p, Vector2(40, 584), Vector2(1100, 60))
	var back := _button("BACK", "help_back", 240)
	foot.add_child(back)
	root.add_child(p)
	return p


func _wrapped(text: String, size: int) -> Label:
	var l := _label(text, size)
	l.autowrap = true
	l.rect_min_size = Vector2(1100, 0)
	return l


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
	if wait_panel != null:
		wait_panel.visible = false
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
	if Net.active and not Net.in_match and party_panel != null:
		call_deferred("_on_button", "party")
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
			_title_tab = 0
			_side_panels(null)
			_move_underline(0)
		"locker":
			_title_tab = 1
			_side_panels(locker_panel)
			_move_underline(1)
			locker_show(locker_cat)
		"profile":
			_title_tab = 2
			_side_panels(profile_panel)
			_move_underline(2)
			profile_show("home")
		"party":
			_title_tab = 3
			_side_panels(party_panel)
			_move_underline(3)
			party_show("party" if Net.active else "home")
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
			Net.leave("")
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


# Windows "Graphics settings": ask for the high-performance GPU for this exe (the same switch as Settings > Display > Graphics).
func _on_high_gpu() -> void:
	var exe := OS.get_executable_path().replace("/", "\\")
	var out := []
	var code := OS.execute("reg", ["add", "HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences", "/v", exe, "/t", "REG_SZ", "/d", "GpuPreference=2;", "/f"], true, out)
	gpu_note.text = "Done - close the game completely and start it again." if code == 0 else "Could not change it automatically. Open Windows Settings > System > Display > Graphics, add StormIsland.exe and choose High performance."
	Audio.play2d("ui_click", -6.0)


func _on_auto_graphics(on: bool) -> void:
	Settings.auto_graphics = on
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
	Controls.menu_open = state != "hidden"
	fps_label.visible = Settings.show_fps
	if Settings.show_fps:
		var P = Performance
		fps_label.text = "%d FPS   script %.1f ms  physics %.1f ms  draws %d\n%s" % [Engine.get_frames_per_second(), P.get_monitor(P.TIME_PROCESS) * 1000.0,
			P.get_monitor(P.TIME_PHYSICS_PROCESS) * 1000.0, P.get_monitor(P.RENDER_DRAW_CALLS_IN_FRAME), VisualServer.get_video_adapter_name()]
	if state == "title" and lobby != null:
		orbit_cam.global_transform = lobby.camera_transform()
		_tip_t += delta
		if _tip_t > 6.0:
			_tip_t = 0.0
			_tip_i = (_tip_i + 1) % TIPS.size()
			tip_label.text = TIPS[_tip_i]


func _input(event: InputEvent) -> void:
	if _rebind_action != "" and _rebind_pad:
		var pb := _pad_press_of(event)
		if pb != -2:
			if pb == JOY_START or pb == -1:
				_cancel_rebind()                              # Menu / Start cancels
			elif not (pb in Controls.PAD_RESERVED):
				Controls.set_pad_binding(_rebind_action, pb)
				_rebind_action = ""
				_refresh_bindings()
			get_tree().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
			_cancel_rebind()
			get_tree().set_input_as_handled()
			return
	elif _rebind_action != "" and event.is_pressed() and not event.is_echo():
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
	if event is InputEventJoypadButton and event.pressed and _pad_menu_input(event):
		get_tree().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE and not event.echo:
		_escape()
		get_tree().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.scancode == KEY_ENTER and state == "title":
		_on_button("play")


# Esc / controller Menu: close the inventory or the build editor first, else pause / go back.
func _escape() -> void:
	if world != null and world.hud != null and world.hud.inventory.visible:
		world.hud.close_inventory()                 # closes the inventory screen before it pauses the game
		return
	if world != null and world.hud != null and world.hud.editor.visible:
		world.hud.editor.cancel()                   # ... and the build editor
		return
	toggle_pause()


# Which controller button this event is (triggers included), -1 for the Start button's cancel, -2 when it is not a pad press.
func _pad_press_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed:
		return event.button_index
	if event is InputEventJoypadMotion and abs(event.axis_value) > 0.7 and (event.axis == JOY_AXIS_6 or event.axis == JOY_AXIS_7):
		return JOY_L2 if event.axis == JOY_AXIS_6 else JOY_R2
	return -2


const TITLE_TABS := ["lobby", "locker", "profile", "party"]
const SETTINGS_TABS := ["audio", "graphics", "controls", "gameplay"]


# Controller handling on the menu screens. Returns true when the press was used here.
func _pad_menu_input(event: InputEventJoypadButton) -> bool:
	var b: int = event.button_index
	if state == "hidden":
		if b == JOY_START:
			_escape()
			return true
		if b == JOY_XBOX_B and world != null and world.hud != null and world.hud.inventory.visible:
			world.hud.close_inventory()
			return true
		return false
	if state == "splash":
		return false
	if b == JOY_START and state != "title":
		toggle_pause()
		return true
	if b == JOY_XBOX_B:
		match state:
			"paused", "settings", "help":
				toggle_pause()
				return true
			"title":
				if _title_tab != 0:
					_on_button("lobby")
					return true
		return false
	if b == JOY_L or b == JOY_R:
		var dir: int = 1 if b == JOY_R else -1
		if state == "title" and not wait_visible():
			_title_tab = int(posmod(_title_tab + dir, TITLE_TABS.size()))
			_on_button(TITLE_TABS[_title_tab])
			_grab_pad_focus()
			return true
		if state == "settings":
			var cur := 0
			for i in range(SETTINGS_TABS.size()):
				if settings_pages[SETTINGS_TABS[i]].visible:
					cur = i
			_show_settings_page(SETTINGS_TABS[int(posmod(cur + dir, SETTINGS_TABS.size()))])
			return true
		return false
	# A / D-pad with nothing focused yet: pick the sensible starting control instead of doing nothing.
	if (b == JOY_XBOX_A or b >= JOY_DPAD_UP and b <= JOY_DPAD_RIGHT) and not _focus_valid():
		_grab_pad_focus()
		return true
	return false


func wait_visible() -> bool:
	return wait_panel != null and wait_panel.visible


func _focus_valid() -> bool:
	var f := root.get_focus_owner()
	return f != null and f.is_visible_in_tree()


# Put the focus on something sensible for the screen that is up (PLAY in the lobby, the first control on other pages).
func _grab_pad_focus() -> void:
	var target: Control = null
	match state:
		"title":
			var side: Control = null
			for pnl in [locker_panel, profile_panel, party_panel]:
				if pnl != null and pnl.visible:
					side = pnl
			target = _first_focusable(side) if side != null else play_button
		"paused":
			target = _first_focusable(pause_panel)
		"settings":
			for k in settings_pages:
				if settings_pages[k].visible:
					target = _first_focusable(settings_pages[k])
		"help":
			target = _first_focusable(help_panel)
	if wait_visible():
		target = _first_focusable(wait_panel)
	if target != null:
		target.grab_focus()


func _first_focusable(n: Node) -> Control:
	if n == null:
		return null
	if n is Control and n.focus_mode != Control.FOCUS_NONE and n.is_visible_in_tree():
		return n as Control
	for c in n.get_children():
		var r: Control = _first_focusable(c)
		if r != null:
			return r
	return null


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

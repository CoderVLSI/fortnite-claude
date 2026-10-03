extends CanvasLayer
# Builds and updates the whole HUD in code: bars, ammo, minimap, storm timer,
# kill feed, damage flash, end screen and the touch controls.

const Items = preload("res://scripts/Items.gd")
const Bar = preload("res://scripts/ui/Bar.gd")
const Hotbar = preload("res://scripts/ui/Hotbar.gd")
const Compass = preload("res://scripts/ui/Compass.gd")
const MapScreen = preload("res://scripts/ui/MapScreen.gd")
const Crosshair = preload("res://scripts/ui/Crosshair.gd")
const ScopeOverlay = preload("res://scripts/ui/ScopeOverlay.gd")
const Minimap = preload("res://scripts/ui/Minimap.gd")
const Materials = preload("res://scripts/ui/Materials.gd")
const InventoryScreen = preload("res://scripts/ui/InventoryScreen.gd")
const TouchControls = preload("res://scripts/ui/TouchControls.gd")
const FONT_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"

const MAP_SIZE := 190.0
const MODE_BUS := 1         # mirrors Fighter.Mode
const MODE_FREEFALL := 2
const MODE_GLIDE := 3
const MODE_VEHICLE := 6

var world
var player
var root: Control
var crosshair: Control
var scope_overlay: Control
var minimap: Control
var hotbar: Control
var materials: Control
var inventory: Control
var compass: Control
var prompt_label: Label
var bus_label: Label
var use_bar: Control
var map_screen: Control
var pause_btn: Button
var poi_label: Label
var boss_label: Label
var boss_bar: Control
var _loc := ""
var _poi_t := 0.0
var touch: Control
var health_bar: Control
var shield_bar: Control
var ammo_label: Label
var storm_label: Label
var warn_label: Label
var stats_label: Label
var hint_label: Label
var toast_label: Label
var feed_box: VBoxContainer
var flash_rect: ColorRect
var storm_rect: ColorRect
var end_panel: Panel
var _dmg := []                  # floating damage numbers: {label, world position, age, headshot}
var hv_root: Control            # health bar over the tree / rock / wall being hit with the pickaxe
var hv_bar: Control
var hv_label: Label
var _hv_pos := Vector3.ZERO
var _hv_t := 0.0
var _hv_id := ""
var _hv_shown := 1.0
var _hv_target := 1.0
var end_bg: TextureRect
var badge: TextureRect
var _badge_name := ""
var _icons := {}                # icon / backdrop textures kept alive (an unreferenced texture is freed and draws blank)
var end_title: Label
var end_stats: Label

var _flash := 0.0
var _toast_t := 0.0
var _t := 0.0
var _big_font: DynamicFont


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "UI"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.theme = _make_theme()
	add_child(root)
	_build()
	Controls.connect("touch_mode_changed", self, "_on_touch_mode")


func _make_theme() -> Theme:
	var theme := Theme.new()
	var data = load(FONT_PATH)
	if data != null:
		var font := DynamicFont.new()
		font.font_data = data
		font.size = 21
		font.use_filter = true
		theme.default_font = font
		_big_font = DynamicFont.new()
		_big_font.font_data = data
		_big_font.size = 40
		_big_font.use_filter = true
	return theme


func _place(c: Control, ax: float, ay: float, off: Vector2, size: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.margin_left = off.x
	c.margin_top = off.y
	c.margin_right = off.x + size.x
	c.margin_bottom = off.y + size.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _label(text: String, align: int = Label.ALIGN_CENTER, color: Color = Color.white) -> Label:
	var l := Label.new()
	l.text = text
	l.align = align
	l.valign = Label.VALIGN_CENTER
	l.add_color_override("font_color", color)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	l.add_constant_override("shadow_offset_x", 2)
	l.add_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	storm_rect = ColorRect.new()
	storm_rect.color = Color(0.5, 0.1, 0.9, 0.0)
	storm_rect.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	storm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(storm_rect)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.9, 0.05, 0.05, 0.0)
	flash_rect.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

	scope_overlay = ScopeOverlay.new()                 # under the crosshair and every button
	scope_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	scope_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_overlay.visible = false
	root.add_child(scope_overlay)
	crosshair = Crosshair.new()
	_place(crosshair, 0.5, 0.5, Vector2(-80, -80), Vector2(160, 160))
	root.add_child(crosshair)

	minimap = Minimap.new()
	_place(minimap, 1.0, 0.0, Vector2(-MAP_SIZE - 16, 16), Vector2(MAP_SIZE, MAP_SIZE))
	minimap.rect_clip_content = true
	root.add_child(minimap)

	stats_label = _label("", Label.ALIGN_RIGHT)
	_place(stats_label, 1.0, 0.0, Vector2(-296, MAP_SIZE + 20), Vector2(280, 30))
	root.add_child(stats_label)

	compass = Compass.new()
	_place(compass, 0.5, 0.0, Vector2(-220, 8), Vector2(440, 30))
	root.add_child(compass)

	storm_label = _label("", Label.ALIGN_CENTER, Color(0.85, 0.7, 1.0))
	_place(storm_label, 0.5, 0.0, Vector2(-230, 58), Vector2(460, 30))
	root.add_child(storm_label)

	warn_label = _label("YOU ARE IN THE STORM", Label.ALIGN_CENTER, Color(1.0, 0.45, 0.9))
	_place(warn_label, 0.5, 0.0, Vector2(-230, 90), Vector2(460, 30))
	warn_label.visible = false
	root.add_child(warn_label)

	feed_box = VBoxContainer.new()
	_place(feed_box, 0.0, 0.0, Vector2(16, 16), Vector2(520, 130))
	root.add_child(feed_box)

	ammo_label = _label("", Label.ALIGN_CENTER)
	_place(ammo_label, 0.5, 1.0, Vector2(-190, -140), Vector2(380, 40))
	if _big_font:
		ammo_label.add_font_override("font", _big_font)
	root.add_child(ammo_label)

	shield_bar = Bar.new()
	shield_bar.fill_color = Color(0.30, 0.65, 1.0)
	_place(shield_bar, 0.5, 1.0, Vector2(-190, -92), Vector2(380, 26))
	root.add_child(shield_bar)
	health_bar = Bar.new()
	health_bar.fill_color = Color(0.35, 0.90, 0.40)
	_place(health_bar, 0.5, 1.0, Vector2(-190, -60), Vector2(380, 26))
	root.add_child(health_bar)

	toast_label = _label("", Label.ALIGN_CENTER, Color(1.0, 0.9, 0.4))
	_place(toast_label, 0.5, 1.0, Vector2(-200, -184), Vector2(400, 30))
	root.add_child(toast_label)

	hint_label = _label("Click to resume  (WASD move, Shift sprint, Space jump, R reload)", Label.ALIGN_CENTER)
	_place(hint_label, 0.5, 0.5, Vector2(-380, 110), Vector2(760, 34))
	hint_label.visible = false
	root.add_child(hint_label)

	hotbar = Hotbar.new()
	root.add_child(hotbar)
	hotbar.connect("slot_pressed", self, "_on_slot_pressed")

	prompt_label = _label("", Label.ALIGN_CENTER)
	_place(prompt_label, 0.5, 0.5, Vector2(-260, 70), Vector2(520, 32))
	prompt_label.visible = false
	root.add_child(prompt_label)

	bus_label = _label("", Label.ALIGN_CENTER, Color(1.0, 0.92, 0.55))
	_place(bus_label, 0.5, 0.5, Vector2(-330, -150), Vector2(660, 34))
	bus_label.visible = false
	root.add_child(bus_label)

	hv_root = Control.new()
	hv_root.rect_size = Vector2(150, 40)
	hv_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv_root.visible = false
	root.add_child(hv_root)
	hv_label = _label("", Label.ALIGN_CENTER)
	hv_label.rect_position = Vector2(0, 0)
	hv_label.rect_size = Vector2(150, 22)
	hv_root.add_child(hv_label)
	hv_bar = Bar.new()
	hv_bar.show_text = false
	hv_bar.max_value = 1.0
	hv_bar.rect_position = Vector2(5, 24)
	hv_bar.rect_size = Vector2(140, 12)
	hv_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv_root.add_child(hv_bar)

	badge = TextureRect.new()                   # what you are riding: bus, glider, buggy, quad or boat
	badge.expand = true
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_place(badge, 0.5, 0.5, Vector2(-34, -236), Vector2(68, 68))
	badge.visible = false
	root.add_child(badge)

	use_bar = Bar.new()
	use_bar.fill_color = Color(1.0, 0.85, 0.3)
	use_bar.max_value = 1.0
	_place(use_bar, 0.5, 0.5, Vector2(-90, 46), Vector2(180, 12))
	use_bar.visible = false
	root.add_child(use_bar)

	poi_label = _label("", Label.ALIGN_CENTER, Color(1.0, 0.95, 0.75))
	_place(poi_label, 0.5, 0.0, Vector2(-400, 150), Vector2(800, 60))
	if _big_font:
		poi_label.add_font_override("font", _big_font)
	poi_label.modulate.a = 0.0
	root.add_child(poi_label)

	boss_label = _label("THE WARDEN", Label.ALIGN_CENTER, Color(1.0, 0.55, 0.2))
	_place(boss_label, 0.5, 0.0, Vector2(-160, 96), Vector2(320, 26))
	boss_label.visible = false
	root.add_child(boss_label)
	boss_bar = Bar.new()
	boss_bar.fill_color = Color(1.0, 0.4, 0.15)
	_place(boss_bar, 0.5, 0.0, Vector2(-160, 122), Vector2(320, 16))
	boss_bar.visible = false
	root.add_child(boss_bar)

	pause_btn = Button.new()
	pause_btn.text = "II"
	_place(pause_btn, 1.0, 0.0, Vector2(-MAP_SIZE - 86, 16), Vector2(58, 58))
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.visible = Controls.touch_mode
	pause_btn.connect("pressed", self, "_on_pause_pressed")
	root.add_child(pause_btn)

	materials = Materials.new()
	_place(materials, 1.0, 0.0, Vector2(-Materials.wanted_size().x - 88.0, 14), Materials.wanted_size())
	materials.visible = Controls.touch_mode
	root.add_child(materials)

	map_screen = MapScreen.new()
	_place(map_screen, 0.5, 0.5, Vector2(-290, -290), Vector2(580, 580))
	map_screen.visible = false
	root.add_child(map_screen)

	inventory = InventoryScreen.new()
	inventory.connect("closed", self, "close_inventory")
	root.add_child(inventory)

	touch = TouchControls.new()
	touch.visible = Controls.touch_mode
	touch.hotbar = hotbar
	touch.minimap = minimap
	touch.materials = materials
	touch.connect("map_pressed", self, "toggle_map")
	touch.connect("bag_pressed", self, "toggle_inventory")
	touch.connect("piece_pressed", self, "_on_piece_pressed")
	touch.connect("material_pressed", self, "_on_material_pressed")
	root.add_child(touch)
	_layout()

	_build_end_panel()


func _tex(path: String):
	if not _icons.has(path):
		_icons[path] = load(path) if ResourceLoader.exists(path) else null
	return _icons[path]


func _build_end_panel() -> void:
	end_bg = TextureRect.new()                 # generated victory / eliminated painting behind the result panel
	end_bg.expand = true
	end_bg.stretch_mode = TextureRect.STRETCH_SCALE
	end_bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	end_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_bg.visible = false
	root.add_child(end_bg)
	end_panel = Panel.new()
	_place(end_panel, 0.5, 0.5, Vector2(-250, -150), Vector2(500, 300))
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	end_panel.visible = false
	root.add_child(end_panel)
	end_title = _label("ELIMINATED")
	end_title.rect_position = Vector2(0, 20)
	end_title.rect_size = Vector2(500, 70)
	if _big_font:
		end_title.add_font_override("font", _big_font)
	end_panel.add_child(end_title)
	end_stats = _label("")
	end_stats.rect_position = Vector2(0, 100)
	end_stats.rect_size = Vector2(500, 80)
	end_panel.add_child(end_stats)
	var button := Button.new()
	button.text = "PLAY AGAIN"
	button.rect_position = Vector2(150, 205)
	button.rect_size = Vector2(200, 60)
	button.connect("pressed", self, "_on_restart")
	end_panel.add_child(button)


func bind(world_node) -> void:
	world = world_node
	player = world.player
	minimap.world = world
	crosshair.player = player
	scope_overlay.player = player
	inventory.player = player
	player.connect("harvested", self, "_on_harvested")
	player.connect("damage_dealt", self, "_on_damage_dealt")
	player.connect("damaged", self, "_on_player_damaged")
	player.connect("hit_landed", self, "_on_hit_landed")
	player.connect("picked_up", self, "show_toast")
	hotbar.set_player(player)
	materials.set_player(player)
	touch.builder = player.builder
	map_screen.world = world


# Positions every widget for the current input mode: the PC HUD (minimap top-right, bars and
# ammo bottom-centre, hotbar bottom-right) or the phone HUD (minimap and bars top-left,
# materials and menu top-right, hotbar bottom-centre with the ammo readout beside it).
func _layout() -> void:
	var size: Vector2 = Hotbar.wanted_size()
	hotbar.show_materials = not Controls.touch_mode
	hotbar.show_build_row = not Controls.touch_mode
	if Controls.touch_mode:
		var map_px := 168.0
		_place(minimap, 0.0, 0.0, Vector2(20, 12), Vector2(map_px, map_px))
		_place(shield_bar, 0.0, 0.0, Vector2(20 + map_px + 14, 30), Vector2(300, 24))
		_place(health_bar, 0.0, 0.0, Vector2(20 + map_px + 14, 58), Vector2(300, 24))
		_place(stats_label, 0.0, 0.0, Vector2(20 + map_px + 14, 88), Vector2(300, 30))
		stats_label.align = Label.ALIGN_LEFT
		_place(feed_box, 0.0, 0.0, Vector2(20, map_px + 24), Vector2(480, 130))
		_place(pause_btn, 1.0, 0.0, Vector2(-70, 14), Vector2(54, 44))
		pause_btn.text = "="
		_place(hotbar, 0.5, 1.0, Vector2(-size.x / 2.0, -size.y + 2.0), size)
		_place(ammo_label, 0.5, 1.0, Vector2(size.x / 2.0 + 16.0, -64), Vector2(200, 44))
		ammo_label.align = Label.ALIGN_LEFT
		ammo_label.clip_text = true
		_place(toast_label, 0.5, 1.0, Vector2(-200, -196), Vector2(400, 30))
	else:
		_place(minimap, 1.0, 0.0, Vector2(-MAP_SIZE - 16, 16), Vector2(MAP_SIZE, MAP_SIZE))
		_place(shield_bar, 0.5, 1.0, Vector2(-190, -92), Vector2(380, 26))
		_place(health_bar, 0.5, 1.0, Vector2(-190, -60), Vector2(380, 26))
		_place(stats_label, 1.0, 0.0, Vector2(-296, MAP_SIZE + 20), Vector2(280, 30))
		stats_label.align = Label.ALIGN_RIGHT
		_place(feed_box, 0.0, 0.0, Vector2(16, 16), Vector2(520, 130))
		_place(pause_btn, 1.0, 0.0, Vector2(-MAP_SIZE - 86, 16), Vector2(58, 58))
		pause_btn.text = "II"
		_place(hotbar, 1.0, 1.0, Vector2(-size.x - 16.0, -size.y - 12.0), size)
		_place(ammo_label, 0.5, 1.0, Vector2(-190, -140), Vector2(380, 40))
		ammo_label.align = Label.ALIGN_CENTER
		_place(toast_label, 0.5, 1.0, Vector2(-200, -184), Vector2(400, 30))
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.visible = Controls.touch_mode
	materials.visible = Controls.touch_mode


func toggle_inventory() -> void:
	if inventory.visible:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	if player == null or player.is_dead or world == null or world.match_over or inventory.visible:
		return
	if world.menu != null and world.menu.state != "hidden":
		return
	map_screen.visible = false
	inventory.visible = true
	player.input_enabled = false                      # the character stands still while the screen is open
	for a in ["fire", "aim", "sprint", "jump", "reload", "interact"]:
		Input.action_release(a)
	Controls.touch_aim = false
	if touch:
		touch.visible = false
	Controls.capture_mouse(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Audio.play2d("ui_click", -6.0)


func close_inventory() -> void:
	if not inventory.visible:
		return
	inventory.visible = false
	if player != null:
		player.input_enabled = true
	if touch:
		touch.visible = Controls.touch_mode and not end_panel.visible
	if not Controls.touch_mode and not ("--no-capture" in OS.get_cmdline_args()) and not end_panel.visible:
		Controls.capture_mouse(true)
	Audio.play2d("ui_click", -6.0)


func _fit_map() -> void:
	var side: float = min(root.rect_size.x, root.rect_size.y) - 28.0     # the island map fills the screen
	_place(map_screen, 0.5, 0.5, Vector2(-side / 2.0, -side / 2.0), Vector2(side, side))
	map_screen.mouse_filter = Control.MOUSE_FILTER_STOP


func toggle_map() -> void:
	if not map_screen.visible:
		_fit_map()
	map_screen.visible = not map_screen.visible
	Audio.play2d("ui_click", -6.0)


func _on_piece_pressed(index: int) -> void:
	if player != null:
		player.press_piece(index)


func _on_material_pressed(kind: String) -> void:
	if player != null:
		player.builder.set_material(kind)


func _on_slot_pressed(index: int) -> void:
	if player == null:
		return
	if player.builder.active:
		player.builder.set_active(false)       # picking an item leaves build mode
	player.select_slot(index)


func _on_pause_pressed() -> void:
	if world != null and world.menu != null:
		world.menu.toggle_pause()


func _on_damage_dealt(pos: Vector3, amount: float, headshot: bool, killed: bool) -> void:
	if not Settings.damage_numbers:
		return
	var col := Color(1.0, 0.85, 0.2) if headshot else (Color(1.0, 0.4, 0.35) if killed else Color.white)
	var l := _label(str(int(round(amount))), Label.ALIGN_CENTER, col)
	l.rect_size = Vector2(90, 30)
	l.rect_pivot_offset = Vector2(45, 15)
	l.rect_scale = Vector2(1.5, 1.5) if headshot else Vector2.ONE
	root.add_child(l)
	_dmg.append({"label": l, "pos": pos + Vector3(rand_range(-0.25, 0.25), 0.0, rand_range(-0.25, 0.25)), "age": 0.0})
	while _dmg.size() > 14:                                  # a shotgun blast makes several numbers at once
		_dmg[0].label.queue_free()
		_dmg.pop_front()


func _update_damage_numbers(delta: float) -> void:
	var cam: Camera = player.camera
	for i in range(_dmg.size() - 1, -1, -1):
		var d: Dictionary = _dmg[i]
		d.age += delta
		var l: Label = d.label
		if d.age > 0.9 or cam == null or cam.is_position_behind(d.pos):
			l.queue_free()
			_dmg.remove(i)
			continue
		var sp: Vector2 = cam.unproject_position(d.pos)
		l.rect_position = sp - Vector2(45, 15 + d.age * 70.0)      # drifts upward
		l.modulate.a = clamp(1.0 - (d.age - 0.45) / 0.45, 0.0, 1.0)


func _on_harvested(pos: Vector3, fraction: float, kind: String, label: String, id: String) -> void:
	if id != _hv_id:
		_hv_id = id
		_hv_shown = 1.0                                   # a new target starts from full
	_hv_pos = pos
	_hv_t = 1.7 if fraction > 0.0 else 0.55            # linger, then vanish (quickly once it is gone)
	hv_label.text = label
	_hv_target = fraction
	var colors := {"wood": Color(0.80, 0.55, 0.25), "stone": Color(0.72, 0.74, 0.78), "metal": Color(0.45, 0.70, 1.0)}
	hv_bar.fill_color = colors.get(kind, Color(0.9, 0.8, 0.3))
	hv_root.visible = true


func _update_harvest_bar(delta: float) -> void:
	if _hv_t <= 0.0:
		hv_root.visible = false
		_hv_id = ""
		return
	_hv_t -= delta
	_hv_shown = lerp(_hv_shown, _hv_target, clamp(14.0 * delta, 0.0, 1.0))
	hv_bar.value = _hv_shown
	var cam: Camera = player.camera
	if cam == null or cam.is_position_behind(_hv_pos):
		hv_root.visible = false
		return
	var sp: Vector2 = cam.unproject_position(_hv_pos)
	var screen: Vector2 = root.rect_size
	hv_root.rect_position = Vector2(clamp(sp.x - 75.0, 6.0, screen.x - 156.0), clamp(sp.y - 64.0, 6.0, screen.y - 46.0))
	hv_root.modulate.a = clamp(_hv_t / 0.35, 0.0, 1.0)
	hv_root.visible = true


func _on_touch_mode(enabled: bool) -> void:
	_layout()
	if touch:
		touch.visible = enabled and not end_panel.visible


func _on_restart() -> void:
	Audio.play2d("ui_click")
	Settings.autostart = true
	get_tree().reload_current_scene()


func _on_player_damaged(_amount, source) -> void:
	if source != null:
		_flash = 1.0


func _on_hit_landed(_target, killed: bool, _headshot: bool) -> void:
	crosshair.flash(killed)


func show_toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 1.8


func add_feed(text: String, color: Color = Color.white) -> void:
	var l := _label(text, Label.ALIGN_LEFT, color)
	l.rect_min_size = Vector2(500, 26)
	feed_box.add_child(l)
	while feed_box.get_child_count() > 5:
		feed_box.get_child(0).queue_free()
		feed_box.remove_child(feed_box.get_child(0))
	get_tree().create_timer(6.0).connect("timeout", l, "queue_free")


func show_end(victory: bool, placement: int, kills: int) -> void:
	Audio.stop_all_ambients()
	Audio.music("music_victory" if victory else "music_defeat", 0.4)
	end_title.text = "LAST ONE STANDING!" if victory else "ELIMINATED"
	end_title.add_color_override("font_color", Color(1.0, 0.85, 0.3) if victory else Color(1.0, 0.45, 0.4))
	end_stats.text = "Placed #%d\nEliminations: %d" % [placement, kills]
	end_bg.texture = _tex("res://assets/ui/victory_bg.png" if victory else "res://assets/ui/eliminated_bg.png")
	end_bg.visible = end_bg.texture != null
	end_bg.modulate = Color(1, 1, 1, 0)
	end_panel.visible = true
	if touch:
		touch.visible = false
	Controls.capture_mouse(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float) -> void:
	if player == null or world == null:
		return
	_t += delta
	health_bar.max_value = player.max_health
	health_bar.value = player.health
	shield_bar.max_value = player.max_shield
	shield_bar.value = player.shield
	ammo_label.text = _ammo_text()
	compass.heading = -rad2deg(player.rotation.y)
	_update_poi(delta)
	if Input.is_action_just_pressed("map"):
		toggle_map()
	if Input.is_action_just_pressed("inventory") and not end_panel.visible:
		toggle_inventory()
	if inventory.visible and (player.is_dead or world.match_over):
		close_inventory()
	_update_prompts()
	storm_label.text = world.storm.status_text()
	stats_label.text = "ALIVE %d    KILLS %d" % [world.alive_count(), player.kills]

	var outside: bool = world.storm.active and not player.is_dead and not world.storm.is_inside(player.global_transform.origin)
	warn_label.visible = outside
	storm_rect.color.a = (0.16 + sin(_t * 5.0) * 0.04) if outside else 0.0
	_update_harvest_bar(delta)
	_update_damage_numbers(delta)
	if end_bg.visible and end_bg.modulate.a < 1.0:
		end_bg.modulate.a = min(1.0, end_bg.modulate.a + delta * 1.2)
	_flash = max(0.0, _flash - delta * 2.5)
	flash_rect.color.a = _flash * 0.40

	if _toast_t > 0.0:
		_toast_t -= delta
		toast_label.modulate.a = clamp(_toast_t, 0.0, 1.0)
	else:
		toast_label.text = ""

	hint_label.visible = (not Controls.touch_mode) and (not end_panel.visible) and (not inventory.visible) \
		and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED


func _ammo_text() -> String:
	if player.builder.active:
		if Controls.touch_mode:      # the ammo readout is narrow on the phone HUD
			return player.builder.PIECES[player.builder.piece].to_upper()
		return "BUILD  " + player.builder.PIECES[player.builder.piece].to_upper() + "  " + player.builder.material.to_upper()
	var item = player.selected_item()
	if item == null:
		return ""
	match item.kind:
		"weapon":
			if player.is_reloading():
				return "RELOADING..."
			return "%d  |  %d" % [item.mag, player.get_reserve()]
		"consumable":
			return Items.CONSUMABLES[item.id].name.to_upper()
	return "PICKAXE"


func _update_poi(delta: float) -> void:
	var loc: String = world.location_name(player.global_transform.origin)
	if loc != _loc:
		_loc = loc
		var named: bool = loc == "MAPLE SQUARE"
		for poi in world.pois:
			if poi.name == loc:
				named = true
		if named and player.mode == 0:
			poi_label.text = loc
			_poi_t = 3.6
	if _poi_t > 0.0:
		_poi_t -= delta
		poi_label.modulate.a = clamp(min(_poi_t, 3.6 - _poi_t + 0.0) * 2.0 if _poi_t < 3.0 else (3.6 - _poi_t) * 3.0, 0.0, 1.0)
	else:
		poi_label.modulate.a = 0.0
	var b = world.boss
	var show_boss: bool = b != null and is_instance_valid(b) and not b.is_dead and player.global_transform.origin.distance_to(b.global_transform.origin) < 90.0
	boss_label.visible = show_boss
	boss_bar.visible = show_boss
	if show_boss:
		boss_bar.max_value = b.max_health + b.max_shield
		boss_bar.value = b.health + b.shield


func _update_badge() -> void:
	var want := ""
	if not player.builder.active:
		match player.mode:
			MODE_BUS:
				want = "vehicle_bus"
			MODE_GLIDE:
				want = "vehicle_glider"
			MODE_VEHICLE:
				if player.vehicle != null and is_instance_valid(player.vehicle):
					want = "vehicle_" + str(player.vehicle.kind)
	if want != _badge_name:
		_badge_name = want
		badge.texture = _tex("res://assets/icons/%s.png" % want) if want != "" else null
	badge.visible = badge.texture != null


func _update_prompts() -> void:
	# interact prompt for the nearest loot / chest
	var target = player.interact_target
	var has_target: bool = target != null and is_instance_valid(target) and not player.is_dead
	if has_target:
		var key := "" if Controls.touch_mode else "[E] "
		prompt_label.text = key + target.prompt_text()
		prompt_label.add_color_override("font_color", target.prompt_color())
	prompt_label.visible = has_target
	touch.set_interact(has_target or player.mode == MODE_VEHICLE, "EXIT" if player.mode == MODE_VEHICLE else "PICK UP")
	# consumable progress
	use_bar.visible = player.is_using()
	if use_bar.visible:
		use_bar.value = player.use_progress()
	# bus / freefall / glider hints
	_update_badge()
	var jump_key := "JUMP" if Controls.touch_mode else "SPACE"
	if player.builder.active:
		bus_label.text = "BUILD  click: place   %s %s %s %s: piece   wheel: material   %s: exit" % [Controls.key_label("build_wall"), Controls.key_label("build_floor"), Controls.key_label("build_ramp"), Controls.key_label("build_roof"), Controls.key_label("build_toggle")] if not Controls.touch_mode else "BUILD   pick a piece, FIRE places"
		bus_label.visible = true
		return
	match player.mode:
		MODE_BUS:
			bus_label.text = "PRESS %s TO DROP FROM THE BUS" % jump_key
			bus_label.visible = true
		MODE_FREEFALL:
			bus_label.text = "FREEFALL  %dm   (%s: open glider)" % [int(player.ground_distance()), jump_key]
			bus_label.visible = true
		MODE_GLIDE:
			bus_label.text = "GLIDING  %dm" % int(player.ground_distance())
			bus_label.visible = true
		MODE_VEHICLE:
			var kmh := int(player.vehicle.linear_velocity.length() * 3.6) if player.vehicle != null and is_instance_valid(player.vehicle) else 0
			var keys := "" if Controls.touch_mode else "  [E] exit  [R] horn  [Shift] boost  [Space] brake"
			bus_label.text = ("%d km/h" % kmh) + (keys if player.vehicle_seat == 0 else "   [E] exit")
			bus_label.visible = true
		_:
			bus_label.visible = false

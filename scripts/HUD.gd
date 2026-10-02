extends CanvasLayer
# Builds and updates the whole HUD in code: bars, ammo, minimap, storm timer,
# kill feed, damage flash, end screen and the touch controls.

const Items = preload("res://scripts/Items.gd")
const Bar = preload("res://scripts/ui/Bar.gd")
const Hotbar = preload("res://scripts/ui/Hotbar.gd")
const Compass = preload("res://scripts/ui/Compass.gd")
const MapScreen = preload("res://scripts/ui/MapScreen.gd")
const Crosshair = preload("res://scripts/ui/Crosshair.gd")
const Minimap = preload("res://scripts/ui/Minimap.gd")
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
var minimap: Control
var hotbar: Control
var compass: Control
var prompt_label: Label
var bus_label: Label
var use_bar: Control
var map_screen: Control
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

	crosshair = Crosshair.new()
	_place(crosshair, 0.5, 0.5, Vector2(-40, -40), Vector2(80, 80))
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

	map_screen = MapScreen.new()
	_place(map_screen, 0.5, 0.5, Vector2(-290, -290), Vector2(580, 580))
	map_screen.visible = false
	root.add_child(map_screen)

	touch = TouchControls.new()
	touch.visible = Controls.touch_mode
	touch.hotbar = hotbar
	touch.minimap = minimap
	touch.connect("map_pressed", self, "toggle_map")
	root.add_child(touch)
	_layout_hotbar()

	_build_end_panel()


func _build_end_panel() -> void:
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
	player.connect("damaged", self, "_on_player_damaged")
	player.connect("hit_landed", self, "_on_hit_landed")
	player.connect("picked_up", self, "show_toast")
	hotbar.set_player(player)
	map_screen.world = world


func _layout_hotbar() -> void:
	var size: Vector2 = Hotbar.wanted_size()
	if Controls.touch_mode:      # centre, above the ammo readout: keeps the thumbs' corners free
		_place(hotbar, 0.5, 1.0, Vector2(-size.x / 2.0, -size.y - 150.0), size)
	else:                        # bottom-right like a PC shooter
		_place(hotbar, 1.0, 1.0, Vector2(-size.x - 16.0, -size.y - 12.0), size)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle_map() -> void:
	map_screen.visible = not map_screen.visible
	Audio.play2d("ui_click", -6.0)


func _on_slot_pressed(index: int) -> void:
	if player == null:
		return
	if player.builder.active:
		if index < 4:
			player.builder.set_piece(index)
		else:
			player.builder.cycle_material(1)
	else:
		player.select_slot(index)


func _on_touch_mode(enabled: bool) -> void:
	_layout_hotbar()
	if touch:
		touch.visible = enabled and not end_panel.visible


func _on_restart() -> void:
	Audio.play2d("ui_click")
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
	_update_prompts()
	storm_label.text = world.storm.status_text()
	stats_label.text = "ALIVE %d    KILLS %d" % [world.alive_count(), player.kills]

	var outside: bool = world.storm.active and not player.is_dead and not world.storm.is_inside(player.global_transform.origin)
	warn_label.visible = outside
	storm_rect.color.a = (0.16 + sin(_t * 5.0) * 0.04) if outside else 0.0
	_flash = max(0.0, _flash - delta * 2.5)
	flash_rect.color.a = _flash * 0.40

	if _toast_t > 0.0:
		_toast_t -= delta
		toast_label.modulate.a = clamp(_toast_t, 0.0, 1.0)
	else:
		toast_label.text = ""

	hint_label.visible = (not Controls.touch_mode) and (not end_panel.visible) \
		and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED


func _ammo_text() -> String:
	if player.builder.active:
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
	var jump_key := "JUMP" if Controls.touch_mode else "SPACE"
	if player.builder.active:
		bus_label.text = "BUILD  click: place   1-4: piece   wheel: material   Q: exit" if not Controls.touch_mode else "BUILD   pick a piece, FIRE places"
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

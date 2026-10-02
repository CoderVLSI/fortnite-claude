extends CanvasLayer
# Builds and updates the whole HUD in code: bars, ammo, minimap, storm timer,
# kill feed, damage flash, end screen and the touch controls.

const Bar = preload("res://scripts/ui/Bar.gd")
const Crosshair = preload("res://scripts/ui/Crosshair.gd")
const Minimap = preload("res://scripts/ui/Minimap.gd")
const TouchControls = preload("res://scripts/ui/TouchControls.gd")
const FONT_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"

const MAP_SIZE := 190.0

var world
var player
var root: Control
var crosshair: Control
var minimap: Control
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

	storm_label = _label("", Label.ALIGN_CENTER, Color(0.85, 0.7, 1.0))
	_place(storm_label, 0.5, 0.0, Vector2(-230, 14), Vector2(460, 34))
	root.add_child(storm_label)

	warn_label = _label("YOU ARE IN THE STORM", Label.ALIGN_CENTER, Color(1.0, 0.45, 0.9))
	_place(warn_label, 0.5, 0.0, Vector2(-230, 50), Vector2(460, 30))
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

	touch = TouchControls.new()
	touch.visible = Controls.touch_mode
	root.add_child(touch)

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


func _on_touch_mode(enabled: bool) -> void:
	if touch:
		touch.visible = enabled and not end_panel.visible


func _on_restart() -> void:
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
	if player.is_reloading():
		ammo_label.text = "RELOADING..."
	else:
		ammo_label.text = "%d  |  %d" % [player.ammo, player.reserve]
	storm_label.text = world.storm.status_text()
	stats_label.text = "ALIVE %d    KILLS %d" % [world.alive_count(), player.kills]

	var outside: bool = not player.is_dead and not world.storm.is_inside(player.global_transform.origin)
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

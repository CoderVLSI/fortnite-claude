extends Control
# One screen for vending machines and NPCs.
#   show_shop(title, entries)   a grid of item cards (picture, name, price); click / tap a card to buy it
#       entries: [{"icon": "heal_medkit", "name": "Medkit", "price": 80, "sub": "optional second line", "sold": false}]
#   show_menu(title, text, options)   a speech box with buttons (Talk / Hire / Buy ...)
#       options: [{"id": "talk", "label": "TALK", "sub": "optional", "enabled": true}]
# Signals: bought(index), chosen(id), closed.  Esc / the CLOSE button / interact again close it.

signal bought(index)
signal chosen(id)
signal closed

const NAVY := Color(0.05, 0.08, 0.19, 0.94)
const HEADER := Color(0.16, 0.24, 0.45, 0.98)
const GOLD := Color(1.0, 0.82, 0.2)

var gold := 0
var _tex := {}
var _panel: Panel
var _title: Label
var _gold_label: Label
var _body: Control
var _text: Label
var _grid: GridContainer
var _buttons := []
var _close: Button
var mode := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY
	sb.border_color = Color(1, 1, 1, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	_panel.add_stylebox_override("panel", sb)
	add_child(_panel)
	_title = Label.new()
	_title.add_color_override("font_color", Color.white)
	_title.rect_position = Vector2(20, 12)
	_panel.add_child(_title)
	_gold_label = Label.new()
	_gold_label.add_color_override("font_color", GOLD)
	_gold_label.align = Label.ALIGN_RIGHT
	_panel.add_child(_gold_label)
	_body = Control.new()
	_panel.add_child(_body)
	_close = Button.new()
	_close.text = "CLOSE  [Esc]"
	_close.connect("pressed", self, "close")
	_panel.add_child(_close)
	connect("resized", self, "_fit")
	_fit()


func icon(name: String):
	if name == "":
		return null
	if not _tex.has(name):
		var path := "res://assets/icons/%s.png" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func _fit() -> void:
	if _panel == null:
		return
	var w: float = clamp(rect_size.x - 40.0, 320.0, 760.0)
	var h: float = clamp(rect_size.y - 40.0, 260.0, 560.0)
	_panel.rect_position = (rect_size - Vector2(w, h)) / 2.0
	_panel.rect_size = Vector2(w, h)
	_gold_label.rect_position = Vector2(w - 220.0, 12)
	_gold_label.rect_size = Vector2(200, 24)
	_body.rect_position = Vector2(16, 48)
	_body.rect_size = Vector2(w - 32.0, h - 48.0 - 56.0)
	_close.rect_position = Vector2(w - 190.0, h - 48.0)
	_close.rect_size = Vector2(170, 38)


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	_buttons = []
	_grid = null
	_text = null


func is_open() -> bool:
	return visible


func set_gold(g: int) -> void:
	gold = g
	_gold_label.text = "GOLD  %d" % g


# ---------------------------------------------------------------- shop

func show_shop(title: String, entries: Array, g: int) -> void:
	mode = "shop"
	_clear()
	_title.text = title.to_upper()
	set_gold(g)
	_grid = GridContainer.new()
	_grid.columns = 3 if _body.rect_size.x < 620.0 else 3
	_grid.add_constant_override("hseparation", 10)
	_grid.add_constant_override("vseparation", 10)
	_body.add_child(_grid)
	var card_w: float = (_body.rect_size.x - 20.0) / 3.0
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var b := Button.new()
		b.rect_min_size = Vector2(card_w, 118)
		b.disabled = e.get("sold", false)
		b.connect("pressed", self, "_card_pressed", [i])
		var pic := TextureRect.new()
		pic.texture = icon(e.get("icon", ""))
		pic.expand = true
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.rect_position = Vector2(card_w / 2.0 - 36.0, 6)
		pic.rect_size = Vector2(72, 66)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(pic)
		var nm := Label.new()
		nm.text = str(e.get("name", ""))
		nm.align = Label.ALIGN_CENTER
		nm.rect_position = Vector2(2, 72)
		nm.rect_size = Vector2(card_w - 4.0, 20)
		nm.clip_text = true
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var pr := Label.new()
		pr.text = "%d gold" % int(e.get("price", 0)) if not e.get("sold", false) else "SOLD OUT"
		pr.align = Label.ALIGN_CENTER
		pr.add_color_override("font_color", GOLD if g >= int(e.get("price", 0)) else Color(1.0, 0.45, 0.4))
		pr.rect_position = Vector2(2, 92)
		pr.rect_size = Vector2(card_w - 4.0, 20)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(pr)
		_grid.add_child(b)
		_buttons.append(b)
	_open()


func refresh_shop(entries: Array, g: int) -> void:
	if mode == "shop":
		show_shop(_title.text, entries, g)


func _card_pressed(i: int) -> void:
	emit_signal("bought", i)


# ---------------------------------------------------------------- menu

func show_menu(title: String, text: String, options: Array, g: int = -1) -> void:
	mode = "menu"
	_clear()
	_title.text = title.to_upper()
	if g >= 0:
		set_gold(g)
	else:
		_gold_label.text = ""
	_text = Label.new()
	_text.text = text
	_text.autowrap = true
	_text.rect_position = Vector2(4, 4)
	_text.rect_size = Vector2(_body.rect_size.x - 8.0, 120)
	_body.add_child(_text)
	var y := 132.0
	for o in options:
		var b := Button.new()
		b.text = str(o.label) + (("   -   " + str(o.sub)) if o.get("sub", "") != "" else "")
		b.disabled = not o.get("enabled", true)
		b.rect_position = Vector2(4, y)
		b.rect_size = Vector2(_body.rect_size.x - 8.0, 44)
		b.connect("pressed", self, "_option_pressed", [o.id])
		_body.add_child(b)
		_buttons.append(b)
		y += 52.0
	_open()


func set_menu_text(text: String) -> void:
	if _text != null:
		_text.text = text


func _option_pressed(id) -> void:
	emit_signal("chosen", id)


# ---------------------------------------------------------------- open / close

func _open() -> void:
	_fit()
	visible = true
	Audio.play2d("ui_click", -6.0)


func close() -> void:
	if not visible:
		return
	visible = false
	mode = ""
	Audio.play2d("ui_click", -6.0)
	emit_signal("closed")


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and (event.scancode == KEY_ESCAPE or event.is_action("interact")):
		close()
		get_tree().set_input_as_handled()

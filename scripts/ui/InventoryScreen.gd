extends Control
# Full inventory screen (Tab / the bag button): item details on the left; on the right the materials, ammo and the five
# equipment slots. Click or tap an equipment slot to equip it, X (or the Drop button) drops the highlighted item, Esc /
# Tab / Back close it. The game keeps running behind it, but the player stops responding to input while it is open.

const Items = preload("res://scripts/Items.gd")
const SpriteBadge = preload("res://scripts/ui/SpriteBadge.gd")
const FONT_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"
const KINDS := ["wood", "stone", "metal"]
const AMMOS := ["light", "medium", "shells", "heavy"]
const NAVY := Color(0.05, 0.08, 0.19, 0.90)
const HEADER := Color(0.16, 0.24, 0.45, 0.95)

signal closed

var player
var _tex := {}                       # icons kept alive between draws
var _big: DynamicFont
var _hover := -1
var _drag_from := -1                 # equipment slot being dragged (press on an item, then move)
var _dragging := false
var _press_pos := Vector2.ZERO
var _drag_pos := Vector2.ZERO
var _rects := {}                     # filled by _layout(): "slots" [Rect2], "drop", "back"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var data = load(FONT_PATH)
	if data != null:
		_big = DynamicFont.new()
		_big.font_data = data
		_big.size = 34
		_big.use_filter = true
	visible = false


func icon(name: String):
	if not _tex.has(name):
		var path := "res://assets/icons/%s.png" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func icon_name_of(item: Dictionary) -> String:
	match item.kind:
		"pickaxe":
			return "weapon_pickaxe"
		"weapon":
			var mythic: String = "weapon_%s_mythic" % item.id
			if item.rarity == Items.MYTHIC and ResourceLoader.exists("res://assets/icons/%s.png" % mythic):
				return mythic
			return "weapon_" + str(item.id)
		"consumable":
			return "heal_" + str(item.id)
	return ""


# Rectangles for the current screen size (virtual pixels).
func _layout() -> Dictionary:
	var w := rect_size.x
	var h := rect_size.y
	var x0: float = max(w * 0.52, 520.0)
	var rw: float = w - x0 - 28.0
	var tile := 76.0
	var gap := 10.0
	var out := {"panel_x": x0, "panel_w": rw}
	out["res_y"] = 56.0
	out["ammo_y"] = 56.0 + 142.0
	out["eq_y"] = 56.0 + 284.0
	var slots := []
	var n := Items.SLOT_COUNT
	var sw: float = min(96.0, (rw - 28.0 - gap * (n - 1)) / float(n))
	for i in range(n):
		slots.append(Rect2(Vector2(x0 + 14.0 + i * (sw + gap), out["eq_y"] + 50.0), Vector2(sw, sw)))
	out["slots"] = slots
	out["tile"] = tile
	out["gap"] = gap
	out["drop"] = Rect2(Vector2(w - 28.0 - 190.0 * 2 - 14.0, h - 74.0), Vector2(190, 52))
	out["back"] = Rect2(Vector2(w - 28.0 - 190.0, h - 74.0), Vector2(190, 52))
	return out


func _process(_delta: float) -> void:
	if visible:
		update()


func _shown_index() -> int:
	if _hover >= 0 and player.slots[_hover] != null:
		return _hover
	return player.selected


func _input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_X:
			player.drop_slot(_shown_index())
			get_tree().set_input_as_handled()
		elif event.scancode == KEY_TAB:
			emit_signal("closed")
			get_tree().set_input_as_handled()


func _slot_at(pos: Vector2) -> int:
	var L := _layout()
	for i in range(L.slots.size()):
		if L.slots[i].has_point(pos):
			return i
	return -1


# Press on an item to pick it up; drag it onto another item slot to swap / move it; a plain click equips it.
func _gui_input(event: InputEvent) -> void:
	if player == null:
		return
	var L := _layout()
	if event is InputEventMouseMotion:
		_drag_pos = event.position
		_hover = _slot_at(event.position)
		if _drag_from >= 0 and not _dragging and event.position.distance_to(_press_pos) > 8.0 and _drag_from >= 1:
			_dragging = true
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed:
			var i := _slot_at(event.position)
			if i >= 0 and player.slots[i] != null:
				_drag_from = i
				_dragging = false
				_press_pos = event.position
				_drag_pos = event.position
				return
			if L.drop.has_point(event.position):
				player.drop_slot(_shown_index())
			elif L.back.has_point(event.position):
				Audio.play2d("ui_click", -6.0)
				emit_signal("closed")
		else:
			if _drag_from < 0:
				return
			var target := _slot_at(event.position)
			if _dragging:
				if target >= 1 and target != _drag_from and player.swap_slots(_drag_from, target):
					Audio.play2d("ui_slot", -4.0)
					_hover = target
			elif target == _drag_from:
				_hover = target
				player.select_slot(_drag_from)                # a plain click equips
				Audio.play2d("ui_slot", -6.0)
			_drag_from = -1
			_dragging = false


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if player == null:
		return
	var L := _layout()
	var font := get_font("font", "Label")
	var big: Font = _big if _big != null else font
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.02, 0.03, 0.08, 0.62))
	_draw_details(font, big)
	var x0: float = L.panel_x
	var rw: float = L.panel_w
	_panel(Rect2(Vector2(x0, L.res_y), Vector2(rw, 132)), "TRAPS & RESOURCES", font)
	for i in range(KINDS.size()):
		var r := Rect2(Vector2(x0 + 14.0 + i * (L.tile + L.gap), L.res_y + 46.0), Vector2(L.tile, L.tile))
		_tile(r, icon("material_" + KINDS[i]), str(player.materials[KINDS[i]]), Color(0.7, 0.72, 0.78), font)
	_panel(Rect2(Vector2(x0, L.ammo_y), Vector2(rw, 132)), "AMMO", font)
	for i in range(AMMOS.size()):
		var r := Rect2(Vector2(x0 + 14.0 + i * (L.tile + L.gap), L.ammo_y + 46.0), Vector2(L.tile, L.tile))
		_tile(r, icon("ammo_" + AMMOS[i]), str(player.reserves[AMMOS[i]]), Items.AMMO[AMMOS[i]].color, font)
	var sp_rect := Rect2(Vector2(x0, L.eq_y + 178.0), Vector2(rw, 104))
	_panel(sp_rect, "BACKPACK - SPRITE", font)
	if player.sprite.empty():
		draw_string(font, sp_rect.position + Vector2(16, 66), "No sprite equipped - catch a wild one", Color(0.7, 0.75, 0.9))
	else:
		SpriteBadge.draw_card(self, Rect2(sp_rect.position + Vector2(8, 38), Vector2(rw - 16, 62)), player.sprite, font, false, icon("sprite_" + player.sprite.id))
	_panel(Rect2(Vector2(x0, L.eq_y), Vector2(rw, 168)), "EQUIPMENT", font)
	for i in range(L.slots.size()):
		var r: Rect2 = L.slots[i]
		var item = player.slots[i]
		var col := Color(0.45, 0.5, 0.62)
		var label := ""
		var tex = null
		if item != null:
			col = Items.color_of(item)
			tex = icon(icon_name_of(item))
			if item.kind == "weapon":
				label = str(player.reserves[Items.WEAPONS[item.id].ammo])
			elif item.kind == "consumable":
				label = str(item.count)
		_tile(r, tex, label, col, font)
		if item != null and tex == null:                       # no generated icon yet: a simple stand-in
			var mid := r.position + r.size / 2.0
			draw_circle(mid, 24.0, Color(0.30, 0.40, 0.18) if item.id == "grenade" else col)
			if item.id == "grenade":
				draw_rect(Rect2(mid + Vector2(-6, -34), Vector2(12, 12)), Color(0.65, 0.67, 0.7))
		draw_string(font, r.position + Vector2(6, 20), Controls.key_label("pickaxe") if i == 0 else Controls.key_label("slot_%d" % i), Color(1, 1, 1, 0.8))
		if _dragging and i == _drag_from:
			draw_rect(r, Color(0, 0, 0, 0.55))                                      # the item being carried
		elif _dragging and i == _hover and i >= 1:
			draw_rect(r.grow(3.0), Color(0.3, 1.0, 0.45, 1.0), false, 4.0)         # a valid drop target
		if i == player.selected:
			draw_rect(r.grow(3.0), Color(1.0, 0.92, 0.1, 1.0), false, 4.0)         # equipped = yellow
		elif i == _hover:
			draw_rect(r.grow(2.0), Color(1, 1, 1, 0.9), false, 2.0)
	if _dragging and _drag_from >= 0 and player.slots[_drag_from] != null:
		var ghost: Rect2 = Rect2(_drag_pos - Vector2(44, 44), Vector2(88, 88))
		var gi = icon(icon_name_of(player.slots[_drag_from]))
		if gi != null:
			draw_texture_rect(gi, ghost, false, Color(1, 1, 1, 0.85))
		else:
			draw_rect(ghost, Color(1, 1, 1, 0.5))
	_button(L.drop, "X   Drop", Color(0.16, 0.24, 0.45, 0.95), font)
	_button(L.back, "TAB   Back", Color(0.16, 0.24, 0.45, 0.95), font)


func _panel(r: Rect2, title: String, font: Font) -> void:
	draw_rect(r, NAVY)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 34)), HEADER)
	draw_string(font, r.position + Vector2(14, 25), title, Color(0.82, 0.88, 1.0))


func _tile(r: Rect2, tex, label: String, border: Color, font: Font) -> void:
	draw_rect(r, Color(0.12, 0.14, 0.22, 0.95))
	if tex != null:
		draw_texture_rect(tex, r, false)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 6), Vector2(r.size.x, 6)), Color(border.r, border.g, border.b, 0.95))
	draw_rect(r, Color(border.r, border.g, border.b, 0.7), false, 2.0)
	if label != "":
		var w := font.get_string_size(label).x
		draw_rect(Rect2(r.position + Vector2(r.size.x - w - 10, r.size.y - 32), Vector2(w + 8, 24)), Color(0, 0, 0, 0.62))
		draw_string(font, r.position + Vector2(r.size.x - w - 6, r.size.y - 13), label, Color.white)


func _button(r: Rect2, text: String, color: Color, font: Font) -> void:
	var hot := r.has_point(get_local_mouse_position())
	draw_rect(r, color.lightened(0.15) if hot else color)
	draw_rect(r, Color(0.45, 0.6, 1.0, 0.9), false, 2.0)
	var w := font.get_string_size(text).x
	draw_string(font, r.position + Vector2((r.size.x - w) / 2.0, r.size.y / 2.0 + 8.0), text, Color.white)


func _draw_details(font: Font, big: Font) -> void:
	var idx := _shown_index()
	var item = player.slots[idx] if idx < player.slots.size() else null
	var x := 28.0
	var y := 56.0
	var w: float = min(rect_size.x * 0.44, 470.0)
	if item == null:
		_panel(Rect2(Vector2(x, y), Vector2(w, 90)), "EMPTY SLOT", font)
		return
	var col := Items.color_of(item)
	var kind_text := "Pickaxe | Harvesting Tool"
	var name_text := "PICKAXE"
	var rows := []
	match item.kind:
		"weapon":
			var s: Dictionary = Items.weapon_stats(item)
			var r_name: String = Items.RARITIES[item.rarity].name
			kind_text = "%s | Ranged Weapon" % r_name
			name_text = Items.name_of(item).to_upper()
			var dps: float = s.damage * s.pellets / s.interval
			rows = [["DPS", "%.1f" % dps], ["Damage", "%.0f%s" % [s.damage, (" x %d pellets" % s.pellets) if s.pellets > 1 else ""]],
				["Fire Rate", "%.2f" % (1.0 / s.interval)], ["Magazine Size", str(item.mag) + " / " + str(s.mag)],
				["Reload Time", "%.1f s" % s.reload], ["Range", "%.0f m" % s.range]]
		"consumable":
			var c: Dictionary = Items.CONSUMABLES[item.id]
			kind_text = "%s | %s" % [Items.RARITIES[c.rarity].name, "Throwable" if c.get("throw", false) else "Consumable"]
			name_text = c.name.to_upper()
			if c.get("throw", false):
				rows.append(["Damage", "up to 127"])
				rows.append(["Blast Radius", "8 m"])
				rows.append(["Fuse", "2.4 s"])
			if c.heal > 0.0:
				rows.append(["Heals", "+%.0f (up to %.0f)" % [c.heal, c.heal_cap]])
			if c.shield > 0.0:
				rows.append(["Shield", "+%.0f (up to %.0f)" % [c.shield, c.shield_cap]])
			if not c.get("throw", false):
				rows.append(["Use Time", "%.1f s" % c.time])
			rows.append(["Carried", "%d / %d" % [item.count, c.stack]])
		_:
			rows = [["Damage", "20"], ["Swing Rate", "1.8"], ["Gathers", "wood, stone, metal"]]
	draw_rect(Rect2(Vector2(x, y), Vector2(w, 118)), Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.96))
	draw_rect(Rect2(Vector2(x, y), Vector2(w, 118)), Color(col.r, col.g, col.b, 0.9), false, 3.0)
	draw_string(font, Vector2(x + 16, y + 30), kind_text, Color(1, 1, 1, 0.95))
	draw_string(big, Vector2(x + 16, y + 78), name_text, Color.white)
	var ry := y + 126.0
	for r in rows:
		draw_rect(Rect2(Vector2(x, ry), Vector2(w, 40)), Color(0.05, 0.08, 0.19, 0.9))
		draw_string(font, Vector2(x + 16, ry + 27), r[0], Color(0.78, 0.84, 1.0))
		var vw := font.get_string_size(r[1]).x
		draw_string(font, Vector2(x + w - vw - 16, ry + 27), r[1], Color.white)
		ry += 42.0

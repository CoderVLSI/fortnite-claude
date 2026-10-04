extends Control
# 5-slot hotbar (pickaxe + 4 item slots) with rarity-coloured borders, drawn item
# icons, ammo / stack counts, a selected-item name popup and the materials counter.

signal slot_pressed(index)

const Items = preload("res://scripts/Items.gd")
const SLOT := 62.0
const GAP := 6.0
const BUILD_ROW := 90.0         # PC: the always-visible build pieces sit in their own row above the slots
const TOP := 76.0 + BUILD_ROW   # room above the slots for materials, the build row and the name popup

const ICON_DIR := "res://assets/icons/"

var _icons := {}                # name -> Texture or null (the drawn shapes below are the fallback)
var player
var builder
var show_build_row := true
var show_materials := true      # the touch HUD draws materials in its own widget (Materials.gd)
var _pop := 0.0
var _pop_text := ""
var _pop_color := Color.white


static func wanted_size() -> Vector2:
	return Vector2(Items.SLOT_COUNT * SLOT + (Items.SLOT_COUNT - 1) * GAP, TOP + SLOT + 10.0)


func icon(name: String):
	if not _icons.has(name):
		var path: String = ICON_DIR + name + ".png"
		_icons[name] = load(path) if ResourceLoader.exists(path) else null      # not every item has generated art yet
	return _icons[name]


func icon_name_of(item: Dictionary) -> String:
	match item.kind:
		"pickaxe":
			return "weapon_pickaxe"
		"weapon":
			var mythic: String = "weapon_%s_mythic" % item.id
			if item.rarity == Items.MYTHIC and ResourceLoader.exists(ICON_DIR + mythic + ".png"):
				return mythic
			return "weapon_" + str(Items.WEAPONS[item.id].get("icon", item.id))
		"consumable":
			return "heal_" + str(item.id)
	return ""


func set_player(p) -> void:
	player = p
	builder = p.builder
	p.connect("slot_changed", self, "_on_slot_changed")
	p.connect("picked_up", self, "_on_picked")


func _on_slot_changed() -> void:
	var item = player.selected_item()
	if item != null:
		_pop = 1.6
		_pop_text = Items.name_of(item)
		_pop_color = Items.color_of(item)


func _on_picked(_text) -> void:
	update()


func slot_rect(i: int) -> Rect2:
	var lift := 8.0 if (player != null and i == player.selected) else 0.0
	return Rect2(Vector2(i * (SLOT + GAP), TOP + 8.0 - lift), Vector2(SLOT, SLOT))


# Which slot is under a canvas-space position (touch hit-testing), or -1.
func slot_at(canvas_pos: Vector2) -> int:
	var local := canvas_pos - rect_global_position
	for i in range(Items.SLOT_COUNT):
		if slot_rect(i).grow(3.0).has_point(local):
			return i
	return -1


func _process(delta: float) -> void:
	if _pop > 0.0:
		_pop -= delta
	update()


func _draw() -> void:
	if player == null:
		return
	var font := get_font("font", "Label")
	if show_materials:
		_draw_materials(font)
	if _pop > 0.0:
		var w := font.get_string_size(_pop_text).x
		var c := Color(_pop_color.r, _pop_color.g, _pop_color.b, clamp(_pop, 0.0, 1.0))
		draw_string(font, Vector2(rect_size.x - w, TOP - 10.0), _pop_text, c)
	if show_build_row:
		_draw_build_row(font)
	for i in range(Items.SLOT_COUNT):
		_draw_slot(i, font)


func _draw_materials(font: Font) -> void:
	var kinds := [["wood", Color(0.62, 0.40, 0.18)], ["stone", Color(0.62, 0.64, 0.68)], ["metal", Color(0.45, 0.62, 0.85)]]
	var x := 0.0
	for k in kinds:
		draw_rect(Rect2(Vector2(x, 0), Vector2(78, 28)), Color(0, 0, 0, 0.5))
		var tex = icon("material_" + k[0])
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2(x + 2, 1), Vector2(26, 26)), false)
		else:
			draw_rect(Rect2(Vector2(x + 5, 6), Vector2(16, 16)), k[1])
			draw_rect(Rect2(Vector2(x + 5, 6), Vector2(16, 16)), Color(1, 1, 1, 0.5), false, 1.5)
		var chosen: bool = builder != null and builder.active and builder.material == k[0]
		if chosen:
			draw_rect(Rect2(Vector2(x, 0), Vector2(78, 28)), Color(1.0, 0.9, 0.3), false, 3.0)
		draw_string(font, Vector2(x + 28, 21), str(player.materials[k[0]]), Color.white)
		x += 84.0
	_draw_gold(Vector2(x, 0), font)


# The gold-bar wallet, drawn as a small stack of bars (no art needed).
func _draw_gold(pos: Vector2, font: Font) -> void:
	draw_rect(Rect2(pos, Vector2(78, 28)), Color(0, 0, 0, 0.5))
	var gold := Color(1.0, 0.8, 0.2)
	draw_rect(Rect2(pos + Vector2(5, 14), Vector2(8, 6)), gold)
	draw_rect(Rect2(pos + Vector2(14, 14), Vector2(8, 6)), gold)
	draw_rect(Rect2(pos + Vector2(9, 8), Vector2(9, 6)), Color(1.0, 0.9, 0.4))
	draw_string(font, pos + Vector2(28, 21), str(player.gold), gold)


func _draw_slot(i: int, font: Font) -> void:
	var r := slot_rect(i)
	var item = player.slots[i]
	var selected: bool = i == player.selected
	draw_rect(r, Color(0.05, 0.07, 0.12, 0.72 if selected else 0.55))
	if item != null:
		var col := Items.color_of(item)
		draw_rect(Rect2(r.position + Vector2(0, SLOT - 6), Vector2(SLOT, 6)), Color(col.r, col.g, col.b, 0.9))
		draw_rect(r, Color(col.r, col.g, col.b, 0.35 if not selected else 0.55), false, 2.0)
		var tex = icon(icon_name_of(item))
		if tex != null:
			draw_texture_rect(tex, r, false)
			draw_rect(Rect2(r.position + Vector2(0, SLOT - 6), Vector2(SLOT, 6)), Color(col.r, col.g, col.b, 0.9))
			draw_rect(r, Color(col.r, col.g, col.b, 0.6 if not selected else 0.9), false, 2.0)
		else:
			_draw_icon(item, r.position + Vector2(SLOT / 2.0, SLOT / 2.0 - 3.0))
		var count := ""
		if item.kind == "weapon":
			count = str(player.reserves[Items.WEAPONS[item.id].ammo])
		elif item.kind == "consumable":
			count = str(item.count)
		if count != "":
			var w := font.get_string_size(count).x
			draw_rect(Rect2(r.position + Vector2(SLOT - w - 8, SLOT - 30), Vector2(w + 6, 22)), Color(0, 0, 0, 0.55))
			draw_string(font, r.position + Vector2(SLOT - w - 5, SLOT - 12), count, Color.white)
	if selected:
		draw_rect(r.grow(2.0), Color(1, 1, 1, 0.95), false, 3.0)
	draw_string(font, r.position + Vector2(5, 17), Controls.key_label("pickaxe") if i == 0 else Controls.key_label("slot_%d" % i), Color(1, 1, 1, 0.75))


# Fortnite-style build row: [Q build mode] [wall Z] [floor X] [ramp C] [roof V], right-aligned over the item slots.
func _draw_build_row(font: Font) -> void:
	var active: bool = builder != null and builder.active
	var y := TOP - 40.0 - SLOT
	var tint := Color(1, 1, 1)
	if builder != null:
		tint = Color(1, 1, 1) if builder.material == "wood" else (Color(0.82, 0.86, 0.95) if builder.material == "stone" else Color(0.7, 0.85, 1.0))
	# cell 0: build-mode key
	var q := Rect2(Vector2(0, y), Vector2(SLOT, SLOT))
	draw_rect(q, Color(0.05, 0.07, 0.12, 0.62 if not active else 0.8))
	draw_rect(q, Color(0.45, 0.78, 1.0, 0.95) if active else Color(1, 1, 1, 0.35), false, 3.0 if active else 2.0)
	var qw := font.get_string_size(Controls.key_label("build_toggle")).x
	draw_string(font, q.position + Vector2((SLOT - qw) / 2.0, SLOT / 2.0 + 8.0), Controls.key_label("build_toggle"), Color.white)
	for i in range(4):
		var r := Rect2(Vector2((i + 1) * (SLOT + GAP), y), Vector2(SLOT, SLOT))
		var chosen: bool = active and builder.piece == i
		if chosen:
			draw_rect(r.grow(5.0), Color(0.3, 0.7, 1.0, 0.35))             # blue glow on the chosen piece
		draw_rect(r, Color(0.05, 0.07, 0.12, 0.72 if chosen else 0.55))
		var tex = icon("build_" + builder.PIECES[i]) if builder != null else null
		if tex != null:
			draw_texture_rect(tex, r, false, tint)
		var afford: bool = player != null and builder != null and player.materials[builder.material] >= builder.COST
		draw_rect(Rect2(r.position + Vector2(SLOT - 30, SLOT - 24), Vector2(28, 20)), Color(0, 0, 0, 0.55))
		draw_string(font, r.position + Vector2(SLOT - 27, SLOT - 8), str(builder.COST) if builder != null else "10", Color.white if afford else Color(1.0, 0.4, 0.3))
		draw_rect(r, Color(0.45, 0.78, 1.0, 1.0) if chosen else Color(1, 1, 1, 0.35), false, 3.0 if chosen else 2.0)
		draw_string(font, r.position + Vector2(5, 17), Controls.key_label(["build_wall", "build_floor", "build_ramp", "build_roof"][i]), Color(1, 1, 1, 0.9))


func _draw_icon(item: Dictionary, c: Vector2) -> void:
	var steel := Color(0.86, 0.88, 0.94)
	var dark := Color(0.22, 0.24, 0.30)
	var wood := Color(0.62, 0.40, 0.18)
	match item.kind:
		"pickaxe":
			draw_line(c + Vector2(-13, 15), c + Vector2(9, -9), wood, 5.0)
			draw_line(c + Vector2(-6, -14), c + Vector2(22, -4), steel, 5.0)
			draw_line(c + Vector2(-6, -14), c + Vector2(-16, 2), steel, 5.0)
		"weapon":
			_draw_gun(item.id, c, steel, dark, wood)
		"consumable":
			_draw_consumable(item.id, c)


func _draw_gun(id: String, c: Vector2, steel: Color, dark: Color, wood: Color) -> void:
	match id:
		"pistol":
			draw_rect(Rect2(c + Vector2(-13, -8), Vector2(26, 9)), steel)
			draw_rect(Rect2(c + Vector2(-10, 0), Vector2(9, 15)), dark)
		"smg":
			draw_rect(Rect2(c + Vector2(-17, -8), Vector2(32, 10)), steel)
			draw_rect(Rect2(c + Vector2(15, -6), Vector2(8, 4)), steel)
			draw_rect(Rect2(c + Vector2(-4, 1), Vector2(7, 16)), dark)
			draw_rect(Rect2(c + Vector2(-23, -6), Vector2(7, 8)), dark)
		"assault":
			draw_rect(Rect2(c + Vector2(-20, -8), Vector2(34, 10)), steel)
			draw_rect(Rect2(c + Vector2(14, -6), Vector2(13, 4)), steel)
			draw_rect(Rect2(c + Vector2(-28, -7), Vector2(9, 10)), wood)
			draw_rect(Rect2(c + Vector2(-6, 2), Vector2(7, 15)), dark)
		"shotgun", "charge_shotgun":
			draw_rect(Rect2(c + Vector2(-22, -6), Vector2(44, 6)), steel)
			draw_rect(Rect2(c + Vector2(-30, -5), Vector2(11, 10)), wood)
			draw_rect(Rect2(c + Vector2(2, -1), Vector2(14, 6)), wood)
		"sniper":
			draw_rect(Rect2(c + Vector2(-26, -5), Vector2(54, 6)), steel)
			draw_rect(Rect2(c + Vector2(-4, -13), Vector2(15, 6)), Color(0.4, 0.65, 1.0))
			draw_rect(Rect2(c + Vector2(-32, -4), Vector2(9, 10)), wood)


func _draw_consumable(id: String, c: Vector2) -> void:
	var red := Color(0.88, 0.15, 0.15)
	match id:
		"bandage":
			draw_rect(Rect2(c + Vector2(-14, -9), Vector2(28, 18)), Color(0.96, 0.96, 0.92))
			draw_rect(Rect2(c + Vector2(-3, -7), Vector2(6, 14)), red)
			draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 6)), red)
		"medkit":
			draw_rect(Rect2(c + Vector2(-16, -11), Vector2(32, 24)), Color(0.96, 0.96, 0.96))
			draw_rect(Rect2(c + Vector2(-3, -8), Vector2(6, 18)), red)
			draw_rect(Rect2(c + Vector2(-9, -2), Vector2(18, 6)), red)
			draw_rect(Rect2(c + Vector2(-6, -15), Vector2(12, 5)), Color(0.45, 0.45, 0.5))
		"mini_shield":
			draw_circle(c + Vector2(0, 5), 10.0, Color(0.30, 0.60, 1.0))
			draw_rect(Rect2(c + Vector2(-3, -12), Vector2(6, 9)), Color(0.55, 0.78, 1.0))
		"shield_potion":
			draw_circle(c + Vector2(0, 5), 14.0, Color(0.22, 0.50, 1.0))
			draw_rect(Rect2(c + Vector2(-4, -15), Vector2(8, 12)), Color(0.55, 0.78, 1.0))
			draw_circle(c + Vector2(-4, 1), 3.5, Color(1, 1, 1, 0.6))
		"grenade":
			draw_circle(c + Vector2(0, 5), 13.0, Color(0.30, 0.40, 0.18))
			draw_rect(Rect2(c + Vector2(-4, -12), Vector2(8, 7)), Color(0.6, 0.62, 0.66))
			draw_line(c + Vector2(2, -12), c + Vector2(14, -8), Color(0.7, 0.72, 0.76), 3.0)
			draw_circle(c + Vector2(-8, -10), 4.0, Color(0.9, 0.75, 0.2))
		"shockwave_grenade":
			draw_circle(c + Vector2(0, 5), 13.0, Color(0.25, 0.5, 0.8))
			draw_rect(Rect2(c + Vector2(-4, -12), Vector2(8, 7)), Color(0.6, 0.62, 0.66))
			draw_arc(c + Vector2(0, 5), 18.0, 0.0, TAU, 20, Color(0.5, 0.85, 1.0), 2.0)
		"junk_rift":
			draw_arc(c + Vector2(0, -8), 12.0, 0.0, TAU, 20, Color(0.75, 0.4, 1.0), 3.0)
			draw_rect(Rect2(c + Vector2(-10, 2), Vector2(20, 7)), Color(0.35, 0.36, 0.42))
			draw_rect(Rect2(c + Vector2(-6, 9), Vector2(12, 6)), Color(0.35, 0.36, 0.42))
		"jetpack":
			draw_rect(Rect2(c + Vector2(-13, -14), Vector2(10, 26)), Color(0.8, 0.22, 0.2))
			draw_rect(Rect2(c + Vector2(3, -14), Vector2(10, 26)), Color(0.8, 0.22, 0.2))
			draw_rect(Rect2(c + Vector2(-11, 12), Vector2(6, 5)), Color(1.0, 0.7, 0.2))
			draw_rect(Rect2(c + Vector2(5, 12), Vector2(6, 5)), Color(1.0, 0.7, 0.2))
		"skateboard":
			draw_rect(Rect2(c + Vector2(-17, -3), Vector2(34, 7)), Color(0.2, 0.7, 0.95))
			draw_circle(c + Vector2(-10, 8), 4.0, Color(0.95, 0.85, 0.2))
			draw_circle(c + Vector2(10, 8), 4.0, Color(0.95, 0.85, 0.2))
		"rift_to_go":
			draw_arc(c, 13.0, 0.0, TAU, 24, Color(0.75, 0.4, 1.0), 4.0)
			draw_circle(c, 9.0, Color(0.4, 0.12, 0.8, 0.7))
		_:                                   # slurp juice, chug jug and anything new: a potion in its rarity colour
			var col: Color = Items.RARITIES[Items.CONSUMABLES[id].rarity].color
			draw_circle(c + Vector2(0, 5), 14.0, col)
			draw_rect(Rect2(c + Vector2(-4, -15), Vector2(8, 12)), col.lightened(0.4))

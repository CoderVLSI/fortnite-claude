extends Control
# The equipped Sprite: a small card with a ghost icon, name, level, an xp bar and what it does.
# draw_card() is shared with the inventory screen's Sprite panel.

const Sprites = preload("res://scripts/Sprites.gd")

var player


func set_player(p) -> void:
	player = p
	p.connect("sprite_changed", self, "update")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var want: bool = player != null and not player.sprite.empty() and not player.is_dead
	if visible != want:
		visible = want
	if want:
		update()


static func draw_ghost(ci: CanvasItem, c: Vector2, col: Color, r: float) -> void:
	ci.draw_circle(c + Vector2(0, -r * 0.15), r, col)
	ci.draw_rect(Rect2(c + Vector2(-r, -r * 0.15), Vector2(r * 2.0, r * 1.0)), col)
	for k in range(4):
		ci.draw_circle(c + Vector2(-r * 0.75 + k * r * 0.5, r * 0.85), r * 0.27, col)
	ci.draw_circle(c + Vector2(-r * 0.34, -r * 0.3), r * 0.16, Color(0.08, 0.08, 0.12))
	ci.draw_circle(c + Vector2(r * 0.34, -r * 0.3), r * 0.16, Color(0.08, 0.08, 0.12))


# Draws the card into `r`. Returns nothing; text uses the given font.
static func draw_card(ci: CanvasItem, r: Rect2, sprite: Dictionary, font: Font, show_desc: bool = true) -> void:
	var id: String = sprite.id
	var variant: String = sprite.get("variant", "")
	var rc: Color = Sprites.rarity_color(id)
	ci.draw_rect(r, Color(0.04, 0.06, 0.14, 0.82))
	ci.draw_rect(r, rc, false, 2.5)
	draw_ghost(ci, r.position + Vector2(34, r.size.y / 2.0 - 4.0), Sprites.color(id, variant), 17.0)
	var tx := r.position.x + 66.0
	var lvl: int = int(sprite.get("level", 1))
	ci.draw_string(font, Vector2(tx, r.position.y + 22.0), Sprites.title(id, variant).to_upper(), rc, r.size.x - 130.0)
	ci.draw_string(font, Vector2(r.end.x - 52.0, r.position.y + 22.0), "Lv %d" % lvl, Color.white)
	var bar := Rect2(Vector2(tx, r.position.y + 30.0), Vector2(r.size.x - 66.0 - 12.0, 7.0))
	ci.draw_rect(bar, Color(0, 0, 0, 0.6))
	var frac := 1.0
	if lvl < Sprites.MAX_LEVEL:
		var base: float = Sprites.xp_to_next(lvl - 1) if lvl > 1 else 0.0
		frac = clamp((float(sprite.get("xp", 0.0)) - base) / (Sprites.xp_to_next(lvl) - base), 0.0, 1.0)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), rc)
	if show_desc:
		ci.draw_string(font, Vector2(tx, r.position.y + 54.0), Sprites.LIST[id].desc, Color(0.85, 0.9, 1.0), r.size.x - 74.0)
		if Sprites.VARIANTS.has(variant):
			ci.draw_string(font, Vector2(tx, r.position.y + 74.0), Sprites.VARIANTS[variant].desc, Sprites.VARIANTS[variant].tint, r.size.x - 74.0)


func _draw() -> void:
	if player == null or player.sprite.empty():
		return
	draw_card(self, Rect2(Vector2.ZERO, rect_size), player.sprite, get_font("font", "Label"), rect_size.y > 60.0)

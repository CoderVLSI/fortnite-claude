extends Control
# Touch HUD: wood / stone / metal counters in the top-right corner. While building, the chosen
# material is outlined; tapping a box chooses it (hit-tested by TouchControls via material_at).

const KINDS := [["wood", Color(0.62, 0.40, 0.18)], ["stone", Color(0.62, 0.64, 0.68)], ["metal", Color(0.45, 0.62, 0.85)]]
const BOX := Vector2(76, 40)
const GAP := 6.0

var player
var builder


static func wanted_size() -> Vector2:
	return Vector2(KINDS.size() * BOX.x + (KINDS.size() - 1) * GAP, BOX.y)


func set_player(p) -> void:
	player = p
	builder = p.builder


func _process(_delta: float) -> void:
	update()


# Which material (name) is under a canvas-space position, or "".
func material_at(canvas_pos: Vector2) -> String:
	var local := canvas_pos - rect_global_position
	for i in range(KINDS.size()):
		if Rect2(Vector2(i * (BOX.x + GAP), 0), BOX).grow(4.0).has_point(local):
			return KINDS[i][0]
	return ""


func _draw() -> void:
	if player == null:
		return
	var font := get_font("font", "Label")
	for i in range(KINDS.size()):
		var k = KINDS[i]
		var r := Rect2(Vector2(i * (BOX.x + GAP), 0), BOX)
		var chosen: bool = builder != null and builder.active and builder.material == k[0]
		draw_rect(r, Color(0.05, 0.07, 0.12, 0.62))
		draw_rect(Rect2(r.position + Vector2(8, 11), Vector2(18, 18)), k[1])
		draw_rect(Rect2(r.position + Vector2(8, 11), Vector2(18, 18)), Color(1, 1, 1, 0.55), false, 1.5)
		draw_string(font, r.position + Vector2(34, 28), str(player.materials[k[0]]), Color.white)
		if chosen:
			draw_rect(r, Color(0.45, 0.75, 1.0), false, 3.0)

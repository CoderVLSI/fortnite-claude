extends Control
# Build editing: a 3x3 grid for the wall / floor you were looking at. Click or drag cells to cut them away or put them back,
# use the DOOR / WINDOW / HOLE presets, then CONFIRM (G / Enter). Esc or CANCEL leaves the piece unchanged.

const Items = preload("res://scripts/Items.gd")
const TILE := 112.0
const GAP := 8.0

signal finished(confirmed)

var piece                         # the BuildPiece being edited
var mask := []
var _paint := true
var _painting := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	visible = false


func open(p) -> void:
	piece = p
	mask = p.get_mask()
	_painting = false
	visible = true


func _grid_origin() -> Vector2:
	var side := TILE * 3.0 + GAP * 2.0
	return Vector2((rect_size.x - side) / 2.0, (rect_size.y - side) / 2.0 - 20.0)


# Screen position of a cell. Walls: row 0 is the bottom row; floors: row 0 is the far edge.
func _cell_rect(col: int, row: int) -> Rect2:
	var screen_row: int = (2 - row) if piece.kind == "wall" else row
	return Rect2(_grid_origin() + Vector2(col * (TILE + GAP), screen_row * (TILE + GAP)), Vector2(TILE, TILE))


func _cell_at(pos: Vector2) -> int:
	for row in range(3):
		for col in range(3):
			if _cell_rect(col, row).has_point(pos):
				return row * 3 + col
	return -1


func _buttons() -> Dictionary:
	var o := _grid_origin()
	var y := o.y + TILE * 3.0 + GAP * 2.0 + 22.0
	var out := {}
	var names: Array = ["DOOR", "WINDOW", "RESET"] if piece.kind == "wall" else ["HOLE", "BIG HOLE", "RESET"]
	for i in range(3):
		out[names[i]] = Rect2(Vector2(o.x + i * 138.0, y), Vector2(128, 44))
	out["CANCEL"] = Rect2(Vector2(o.x, y + 56.0), Vector2(190, 50))
	out["CONFIRM"] = Rect2(Vector2(o.x + 206.0, y + 56.0), Vector2(190, 50))
	return out


func _preset(name: String) -> void:
	mask = [true, true, true, true, true, true, true, true, true]
	match name:
		"DOOR":
			mask[1] = false                      # bottom middle ...
			mask[4] = false                      # ... and the one above it
		"WINDOW":
			mask[4] = false
		"HOLE":
			mask[4] = false
		"BIG HOLE":
			for i in [1, 3, 4, 5, 7]:
				mask[i] = false


func confirm() -> void:
	if piece != null and is_instance_valid(piece):
		if piece.apply_mask(mask):
			Audio.play2d("build_place", -4.0)
		else:
			Audio.play2d("ui_error", -6.0)
	visible = false
	emit_signal("finished", true)


func cancel() -> void:
	visible = false
	emit_signal("finished", false)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_ENTER or event.scancode == KEY_KP_ENTER or event.scancode == KEY_G:
			confirm()
			get_tree().set_input_as_handled()
		elif event.scancode == KEY_ESCAPE:
			cancel()
			get_tree().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if piece == null:
		return
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed:
			var i := _cell_at(event.position)
			if i >= 0:
				_paint = not mask[i]
				mask[i] = _paint
				_painting = true
				Audio.play2d("ui_slot", -10.0)
				return
			var b := _buttons()
			for name in b:
				if b[name].has_point(event.position):
					match name:
						"CONFIRM":
							confirm()
						"CANCEL":
							cancel()
						_:
							_preset(name)
					return
		else:
			_painting = false
	elif event is InputEventMouseMotion and _painting:
		var j := _cell_at(event.position)
		if j >= 0 and mask[j] != _paint:
			mask[j] = _paint


func _process(_delta: float) -> void:
	if visible:
		update()


func _draw() -> void:
	if piece == null:
		return
	var font := get_font("font", "Label")
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.02, 0.03, 0.08, 0.66))
	var o := _grid_origin()
	var side := TILE * 3.0 + GAP * 2.0
	var title: String = "EDIT %s" % piece.kind.to_upper()
	draw_string(font, Vector2(o.x, o.y - 50.0), title, Color(1.0, 0.9, 0.45))
	var hint := "click or drag the cells you want to remove"
	draw_string(font, Vector2(o.x, o.y - 22.0), hint, Color(0.75, 0.85, 1.0, 0.85))
	var col: Color = piece.MAT_COLOR[piece.mat_name]
	for row in range(3):
		for c in range(3):
			var r := _cell_rect(c, row)
			if mask[row * 3 + c]:
				draw_rect(r, Color(col.r, col.g, col.b, 0.92))
				draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
			else:
				draw_rect(r, Color(0.05, 0.08, 0.16, 0.7))
				draw_rect(r, Color(1, 1, 1, 0.18), false, 2.0)
				draw_line(r.position + Vector2(18, 18), r.position + r.size - Vector2(18, 18), Color(1, 0.4, 0.35, 0.55), 3.0)
				draw_line(r.position + Vector2(r.size.x - 18, 18), r.position + Vector2(18, r.size.y - 18), Color(1, 0.4, 0.35, 0.55), 3.0)
	var b := _buttons()
	for name in b:
		var r: Rect2 = b[name]
		var primary: bool = name == "CONFIRM"
		draw_rect(r, Color(0.2, 0.55, 0.3, 0.95) if primary else Color(0.16, 0.24, 0.45, 0.95))
		draw_rect(r, Color(0.45, 0.6, 1.0, 0.9), false, 2.0)
		var label: String = name if name != "CONFIRM" else "%s  Confirm" % Controls.key_label("edit")
		var w := font.get_string_size(label).x
		draw_string(font, r.position + Vector2((r.size.x - w) / 2.0, r.size.y / 2.0 + 8.0), label, Color.white)

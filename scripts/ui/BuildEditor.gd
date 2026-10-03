extends Control
# Build editing for the wall / floor you were looking at.
# PC and controller (Fortnite style): hold Edit, a 3x3 grid appears on the piece in the world; aim the crosshair at a tile and
# click (or drag) to cut it away or put it back; let go of Edit to confirm. Reset Edit (a key, mouse button or the wheel,
# set in Settings) restores the whole piece; Esc cancels.
# Touch: a 3x3 grid overlay with DOOR / WINDOW / HOLE presets and a CONFIRM button.

const Items = preload("res://scripts/Items.gd")
const TILE := 112.0
const GAP := 8.0

signal finished(confirmed)

var piece                         # the BuildPiece being edited
var mask := []
var _paint := true
var _painting := false
var aim_mode := false             # in-world editing with the crosshair (no touch screen)
var hover := -1                   # the tile under the crosshair
var _player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	visible = false


func open(p) -> void:
	piece = p
	mask = p.get_mask()
	_painting = false
	hover = -1
	aim_mode = not Controls.touch_mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE if aim_mode else Control.MOUSE_FILTER_STOP
	Controls.edit_aim = aim_mode
	var ps: Array = p.get_tree().get_nodes_in_group("player")
	_player = ps[0] if ps.size() > 0 else null
	visible = true
	Audio.play2d("ui_slot", -8.0)


func reset_edit() -> void:
	mask = [true, true, true, true, true, true, true, true, true]
	Audio.play2d("ui_click", -6.0)


# Which of the nine tiles the crosshair points at (-1 = none): the camera ray is intersected with the piece's plane.
func aim_cell() -> int:
	if piece == null or not is_instance_valid(piece) or _player == null:
		return -1
	var a: Array = _player.aim_origin_and_dir()
	var xf: Transform = piece.global_transform
	var n: Vector3 = xf.basis.y if piece.kind == "floor" else xf.basis.z
	var denom: float = a[1].dot(n)
	if abs(denom) < 0.001:
		return -1
	var t: float = (xf.origin - a[0]).dot(n) / denom
	if t < 0.0 or t > 16.0:
		return -1
	var local: Vector3 = xf.xform_inv(a[0] + a[1] * t)
	var size: Vector3 = piece.full_size()
	var u: float = local.x / size.x + 0.5
	var v: float = (local.y / size.y + 0.5) if piece.kind == "wall" else (local.z / size.z + 0.5)
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return -1
	return int(floor(v * 3.0)) * 3 + int(floor(u * 3.0))


# The four world-space corners of a tile.
func _cell_corners(col: int, row: int) -> Array:
	var size: Vector3 = piece.full_size()
	var cw := size.x / 3.0
	var out := []
	if piece.kind == "wall":
		var ch := size.y / 3.0
		var c := Vector3((col - 1) * cw, (row - 1) * ch, 0.0)
		for d in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			out.append(piece.global_transform.xform(c + Vector3(d[0] * cw / 2.0, d[1] * ch / 2.0, 0.0)))
	else:
		var cd := size.z / 3.0
		var c2 := Vector3((col - 1) * cw, 0.0, (row - 1) * cd)
		for d in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			out.append(piece.global_transform.xform(c2 + Vector3(d[0] * cw / 2.0, 0.0, d[1] * cd / 2.0)))
	return out


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
	Controls.edit_aim = false
	if piece != null and is_instance_valid(piece):
		if piece.apply_mask(mask):
			Audio.play2d("build_place", -4.0)
			if Net.active and Net.in_match:
				Net.send_event("bmask", [piece.key, mask])
		else:
			Audio.play2d("ui_error", -6.0)
	visible = false
	emit_signal("finished", true)


func cancel() -> void:
	Controls.edit_aim = false
	visible = false
	emit_signal("finished", false)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if aim_mode:
		if event.is_action_pressed("edit_reset") and not event.is_echo():
			reset_edit()
			get_tree().set_input_as_handled()
			return
		if event.is_action_pressed("fire") and not event.is_echo():
			hover = aim_cell()
			if hover >= 0:
				_paint = not mask[hover]
				mask[hover] = _paint
				_painting = true
				Audio.play2d("ui_slot", -10.0)
			get_tree().set_input_as_handled()
			return
		if event.is_action_released("fire"):
			_painting = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_ENTER or event.scancode == KEY_KP_ENTER or (event.scancode == KEY_G and not aim_mode):
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
	if not visible:
		return
	if aim_mode:
		hover = aim_cell()
		if _painting and hover >= 0 and mask[hover] != _paint:
			mask[hover] = _paint
	update()


func _draw_aim(font: Font) -> void:
	if piece == null or not is_instance_valid(piece) or _player == null:
		return
	var cam: Camera = _player.camera
	var col: Color = piece.MAT_COLOR[piece.mat_name]
	for row in range(3):
		for c in range(3):
			var pts := PoolVector2Array()
			var ok := true
			for w in _cell_corners(c, row):
				if cam.is_position_behind(w):
					ok = false
					break
				pts.append(cam.unproject_position(w))
			if not ok:
				continue
			var i := row * 3 + c
			if not mask[i]:
				draw_colored_polygon(pts, Color(0.3, 0.6, 1.0, 0.55))             # cut away: blue
			else:
				draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.10))
			var closed := PoolVector2Array(pts)
			closed.append(pts[0])
			draw_polyline(closed, Color(1, 1, 1, 0.55), 2.0)
			if i == hover:
				draw_polyline(closed, Color(1.0, 0.92, 0.2), 4.0)
	var title := "EDIT %s   click / drag tiles   %s reset   press %s again to confirm" % [piece.kind.to_upper(), Controls.key_label("edit_reset"), Controls.key_label("edit")]
	if Settings.edit_on_release:
		title = "EDIT %s   click / drag tiles   %s reset   release %s to confirm" % [piece.kind.to_upper(), Controls.key_label("edit_reset"), Controls.key_label("edit")]
	var w := font.get_string_size(title).x
	draw_string(font, Vector2((rect_size.x - w) / 2.0, 245.0), title, Color(1.0, 0.92, 0.45))


func _draw() -> void:
	if piece == null:
		return
	var font := get_font("font", "Label")
	if aim_mode:
		_draw_aim(font)
		return
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

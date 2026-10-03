extends Control
# "Visualize sound effects" (Settings > Display): coloured icons on a ring around the reticle show where footsteps (white),
# gunfire (orange), unopened chests (gold) and driven vehicles (blue) are, relative to where you are looking.

const RING := 96.0
const COLORS := {"step": Color(1, 1, 1), "gun": Color(1.0, 0.6, 0.15), "chest": Color(1.0, 0.85, 0.25), "car": Color(0.4, 0.75, 1.0)}

var player
var _marks := []            # [{kind, pos, t}] sampled a few times a second


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)


var _sample_t := 0.0


func _process(delta: float) -> void:
	var want: bool = Settings.pref("visual_sound") and player != null and not player.is_dead
	if visible != want:
		visible = want
	if not want:
		return
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = 0.35
		_sample()
	for m in _marks:
		m.t -= delta
	for i in range(_marks.size() - 1, -1, -1):
		if _marks[i].t <= 0.0:
			_marks.remove(i)
	update()


func _add(kind: String, pos: Vector3, life: float) -> void:
	for m in _marks:                                  # one mark per thing: refresh it rather than stacking
		if m.kind == kind and m.pos.distance_to(pos) < 2.5:
			m.pos = pos
			m.t = life
			return
	_marks.append({"kind": kind, "pos": pos, "t": life})


func _sample() -> void:
	var me: Vector3 = player.global_transform.origin
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == player or f.is_dead:
			continue
		var d: float = f.global_transform.origin.distance_to(me)
		var flat := Vector2(f.velocity.x, f.velocity.z).length()
		if d < 30.0 and f.grounded and flat > 2.6 and f.mode == 0 and not f.crouching:
			_add("step", f.global_transform.origin, 0.9)
	for c in get_tree().get_nodes_in_group("interactable"):
		if is_instance_valid(c) and c.has_method("prompt_text") and "opened" in c and not c.opened and c.global_transform.origin.distance_to(me) < 16.0:
			_add("chest", c.global_transform.origin, 0.9)
	for v in get_tree().get_nodes_in_group("vehicles"):
		if is_instance_valid(v) and not v.exploded and v.linear_velocity.length() > 3.0 and v.global_transform.origin.distance_to(me) < 60.0:
			_add("car", v.global_transform.origin, 0.9)
	for e in Audio.events:                              # gunfire reported by the fighters
		if e.pos.distance_to(me) < 90.0 and e.pos.distance_to(me) > 1.0:
			_add("gun", e.pos, 1.0)
	Audio.events.clear()


func _draw() -> void:
	var cam := get_viewport().get_camera()
	if cam == null or player == null:
		return
	var c := rect_size / 2.0
	var me: Vector3 = player.global_transform.origin
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	for m in _marks:
		var to: Vector3 = m.pos - me
		to.y = 0.0
		if to.length() < 0.5:
			continue
		var v := Vector2(to.dot(right), -to.dot(fwd)).normalized()          # up on screen = straight ahead
		var col: Color = COLORS[m.kind]
		var a: float = clamp(m.t * 2.5, 0.0, 1.0)
		var near: float = clamp(1.0 - to.length() / 90.0, 0.25, 1.0)
		var p := c + v * RING
		var s: float = 5.0 + 6.0 * near
		match m.kind:
			"step":
				draw_circle(p + v.tangent() * 3.5, s * 0.5, Color(col.r, col.g, col.b, a))
				draw_circle(p - v.tangent() * 3.5 - v * 5.0, s * 0.5, Color(col.r, col.g, col.b, a))
			"gun":
				for k in range(6):
					var ang: float = k * TAU / 6.0
					draw_line(p, p + Vector2(cos(ang), sin(ang)) * s * 1.3, Color(col.r, col.g, col.b, a), 2.5)
				draw_circle(p, s * 0.45, Color(1, 0.95, 0.7, a))
			"chest":
				draw_rect(Rect2(p - Vector2(s, s * 0.7), Vector2(s * 2.0, s * 1.4)), Color(col.r, col.g, col.b, a))
				draw_rect(Rect2(p - Vector2(s, s * 0.7), Vector2(s * 2.0, s * 1.4)), Color(0, 0, 0, a * 0.7), false, 1.5)
			"car":
				draw_rect(Rect2(p - Vector2(s * 1.2, s * 0.6), Vector2(s * 2.4, s * 1.2)), Color(col.r, col.g, col.b, a))
				draw_circle(p + Vector2(-s * 0.7, s * 0.6), s * 0.3, Color(0, 0, 0, a))
				draw_circle(p + Vector2(s * 0.7, s * 0.6), s * 0.3, Color(0, 0, 0, a))

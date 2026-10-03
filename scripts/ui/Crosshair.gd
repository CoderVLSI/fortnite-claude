extends Control
# Centre reticle that follows the equipped weapon. Hip-fire: a different crosshair per gun that opens with the
# weapon's spread (pistol dot, AR cross, SMG wide cross, shotgun ring, sniper far cross). Aimed down sights: the
# gun's sight picture (iron posts, red dot, holo ring, shotgun bead); the sniper's full scope is ScopeOverlay.gd.
# A hit marker flashes when a shot lands.

const Items = preload("res://scripts/Items.gd")

var player
var hit := 0.0
var killed := false


func flash(is_kill: bool) -> void:
	hit = 1.0
	killed = is_kill


func _process(delta: float) -> void:
	if hit > 0.0:
		hit = max(0.0, hit - delta * 5.0)
	update()


func _line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, Color(0, 0, 0, col.a * 0.85), width + 2.5)      # dark outline keeps it readable on any background
	draw_line(a, b, col, width)


func _ticks(c: Vector2, gap: float, length: float, col: Color, width: float) -> void:
	_line(c + Vector2(gap, 0), c + Vector2(gap + length, 0), col, width)
	_line(c - Vector2(gap, 0), c - Vector2(gap + length, 0), col, width)
	_line(c + Vector2(0, gap), c + Vector2(0, gap + length), col, width)
	_line(c - Vector2(0, gap), c - Vector2(0, gap + length), col, width)


func _ring(c: Vector2, radius: float, col: Color, width: float) -> void:
	draw_arc(c, radius, 0, TAU, 40, Color(0, 0, 0, col.a * 0.8), width + 2.5)
	draw_arc(c, radius, 0, TAU, 40, col, width)


func _draw() -> void:
	var c := rect_size / 2.0
	var white := Color(1, 1, 1, 0.92)
	var item = null
	var aiming := false
	var spread := 1.0
	if player != null:
		item = player.selected_item()
		aiming = player.aiming
		spread = player.spread_deg
	var sc: Dictionary = {}
	if item != null and item.kind == "weapon":
		sc = Items.scope_of(item.id)
	if sc.empty():                                  # pickaxe, items, building: a plain dot
		draw_circle(c, 2.2, Color(0, 0, 0, 0.5))
		draw_circle(c, 1.5, white)
	elif aiming:
		_draw_sight(c, sc.kind)
	else:
		_draw_hip(c, sc.hip, spread, white)
	if item != null and item.kind == "weapon" and Items.WEAPONS[item.id].has("charge"):
		_draw_charge(c)
	_draw_hit(c)


func _draw_hip(c: Vector2, style: String, spread: float, col: Color) -> void:
	var open: float = clamp(spread, 0.0, 6.0)
	match style:
		"dot":
			var g := 5.0 + open * 3.0
			_ticks(c, g, 5.0, col, 2.0)
			draw_circle(c, 1.6, col)
		"cross":
			_ticks(c, 6.0 + open * 3.0, 9.0, col, 2.0)
			draw_circle(c, 1.4, col)
		"cross_wide":
			_ticks(c, 8.0 + open * 3.0, 12.0, col, 2.5)
			draw_circle(c, 1.6, col)
		"ring":
			_ring(c, 16.0 + open * 3.4, col, 2.0)
			draw_circle(c, 1.6, col)
		"cross_far":
			_ticks(c, 16.0, 16.0, col, 1.5)
			draw_circle(c, 1.4, col)


func _draw_sight(c: Vector2, kind: String) -> void:
	var red := Color(1.0, 0.25, 0.18, 0.95)
	match kind:
		"irons":                                    # rear posts either side, front post in the middle
			_line(c + Vector2(-13, -7), c + Vector2(-13, 7), Color(1, 1, 1, 0.9), 3.0)
			_line(c + Vector2(13, -7), c + Vector2(13, 7), Color(1, 1, 1, 0.9), 3.0)
			_line(c + Vector2(0, -10), c + Vector2(0, 1), Color(1.0, 0.85, 0.3, 0.95), 3.0)
		"reddot":                                   # small glowing dot in a faint housing ring
			draw_circle(c, 7.0, Color(1.0, 0.2, 0.1, 0.22))
			draw_circle(c, 3.2, red)
			_ring(c, 22.0, Color(1, 1, 1, 0.38), 1.5)
		"holo":                                     # holographic ring with a centre dot and four reference ticks
			_ring(c, 30.0, red, 2.0)
			draw_circle(c, 2.2, red)
			_ticks(c, 30.0, 8.0, red, 2.0)
		"bead":                                     # a big bead ring for the shotgun spread
			_ring(c, 34.0, Color(1, 1, 1, 0.65), 1.5)
			draw_circle(c, 3.0, Color(0, 0, 0, 0.5))
			draw_circle(c, 2.2, Color(1.0, 0.85, 0.3, 1.0))


# Charge Shotgun: a bar under the crosshair that fills as you hold fire, with FULL CHARGE when it is ready.
func _draw_charge(c: Vector2) -> void:
	var ch: float = clamp(player.charge, 0.0, 1.0) if player != null else 0.0
	var bar := Rect2(c + Vector2(-70, 52), Vector2(140, 12))
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.7))
	draw_rect(bar, Color(0.12, 0.14, 0.2, 0.85))
	var col: Color = Color(1.0, 0.85, 0.3).linear_interpolate(Color(1.0, 0.3, 0.15), clamp((ch - 0.5) * 2.0, 0.0, 1.0))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ch, bar.size.y)), col)
	draw_rect(bar, Color(1, 1, 1, 0.75), false, 1.5)
	for i in range(1, 4):                                         # quarter marks
		var x := bar.position.x + bar.size.x * float(i) / 4.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.5), 1.0)
	var font := get_font("font", "Label")
	var text := "CHARGE"
	var tc := Color(1, 1, 1, 0.75)
	if ch >= 1.0:
		text = "FULL CHARGE"
		tc = Color(1.0, 0.35 + 0.35 * abs(sin(OS.get_ticks_msec() * 0.012)), 0.2)
	elif ch > 0.0:
		text = "CHARGE %d%%" % int(ch * 100.0)
	var w := font.get_string_size(text).x
	draw_string(font, c + Vector2(-w / 2.0, 82), text, tc)


func _draw_hit(c: Vector2) -> void:
	if hit > 0.0:
		var hc := Color(1.0, 0.25, 0.2, hit) if killed else Color(1, 1, 1, hit)
		var d := 12.0
		draw_line(c + Vector2(d, d), c + Vector2(d * 2, d * 2), hc, 3.0)
		draw_line(c + Vector2(-d, d), c + Vector2(-d * 2, d * 2), hc, 3.0)
		draw_line(c + Vector2(d, -d), c + Vector2(d * 2, -d * 2), hc, 3.0)
		draw_line(c + Vector2(-d, -d), c + Vector2(-d * 2, -d * 2), hc, 3.0)

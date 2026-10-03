extends Control
# Low health: the edges of the screen pulse red (Settings > Display > Low health warning).

var player
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)


# 0 = healthy, 1 = nearly dead
func danger() -> float:
	if player == null or player.is_dead or not Settings.pref("warn_health"):
		return 0.0
	var frac: float = player.health / max(player.max_health, 1.0)
	return clamp((0.35 - frac) / 0.35, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	var want: bool = danger() > 0.0
	if visible != want:
		visible = want
	if want:
		update()


func _draw() -> void:
	var d := danger()
	if d <= 0.0:
		return
	var pulse: float = 0.55 + 0.45 * sin(_t * (3.0 + 4.0 * d))
	var a: float = (0.10 + 0.28 * d) * pulse
	var w := rect_size.x
	var h := rect_size.y
	var steps := 9
	for i in range(steps):                                   # stacked bands fade inwards from every edge
		var k: float = 1.0 - float(i) / steps
		var band: float = 0.05 * min(w, h) * 1.0
		var col := Color(0.85, 0.05, 0.05, a * k * k)
		draw_rect(Rect2(0, i * band * 0.55, w, band * 0.55), col)
		draw_rect(Rect2(0, h - (i + 1) * band * 0.55, w, band * 0.55), col)
		draw_rect(Rect2(i * band * 0.55, 0, band * 0.55, h), col)
		draw_rect(Rect2(w - (i + 1) * band * 0.55, 0, band * 0.55, h), col)

extends SceneTree
# Accessibility: the HUD size slider scales the whole HUD but keeps it on the screen, and the colour-blind filter turns on / off.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	settings.reset_prefs()
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	for f in get_nodes_in_group("fighters"):
		if f != world.player:
			f.set_physics_process(false)
	var hud = world.hud
	var v: Vector2 = root.get_visible_rect().size
	yield(_frames(5), "completed")
	check(is_equal_approx(hud.root.rect_scale.x, 1.0) and hud.root.rect_size.is_equal_approx(v), "the HUD starts at full size")
	settings.set_pref("hud_scale", 1.4)
	yield(_frames(5), "completed")
	check(is_equal_approx(hud.root.rect_scale.x, 1.4), "the HUD size slider scales the HUD (%.2f)" % hud.root.rect_scale.x)
	var shown: Vector2 = hud.root.rect_size * hud.root.rect_scale
	check(abs(shown.x - v.x) < 1.5 and abs(shown.y - v.y) < 1.5, "and it still fills the screen (%s vs %s)" % [shown, v])
	settings.set_pref("hud_scale", 0.7)
	yield(_frames(5), "completed")
	shown = hud.root.rect_size * hud.root.rect_scale
	check(abs(shown.x - v.x) < 1.5 and abs(shown.y - v.y) < 1.5, "a smaller HUD also fills the screen")
	check(not settings.filter.rect.visible, "the colour-blind filter is off by default")
	for m in [1, 2, 3]:
		settings.set_pref("colorblind", m)
		check(settings.filter.rect.visible and int(settings.filter.mat.get_shader_param("mode")) == m, "colour-blind mode %d turns the filter on" % m)
	settings.set_pref("colorblind", 0)
	check(not settings.filter.rect.visible, "and Off turns it off")
	settings.reset_prefs()
	yield(_frames(5), "completed")
	check(is_equal_approx(hud.root.rect_scale.x, 1.0), "reset restores the HUD size")
	print("A11Y_RESULT failures=%d" % failures.size())
	quit(1 if failures.size() > 0 else 0)

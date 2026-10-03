extends SceneTree
# Skins: eight looks, picked in the lobby, applied to the player model and shared by the lobby character.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _init() -> void:
	call_deferred("_run")


func _props(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c.name == "SkinProps":
			n += c.get_child_count()
		n += _props(c)
	return n


func _run() -> void:
	yield(self, "idle_frame")
	var settings = root.get_node("Settings")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var Skins = load("res://scripts/Skins.gd")
	var p = world.player
	check(Skins.ORDER.size() == 8 and Skins.LIST.size() == 8, "eight skins exist")

	var torso: MeshInstance = p.model.find_node("TorsoMesh", true, false)
	var base_vest: Color = torso.get_surface_material(0).albedo_color
	p.set_skin("ninja")
	var ninja_vest: Color = torso.get_surface_material(0).albedo_color
	check(ninja_vest.v < 0.2 and base_vest.v >= 0.2, "the Ninja wears black (%s)" % str(ninja_vest))
	check(_props(p.model) >= 3, "and a headband and scarf (%d props)" % _props(p.model))
	p.set_skin("knight")
	var knight_mat: SpatialMaterial = torso.get_surface_material(0)
	check(knight_mat.metallic > 0.5, "the Knight's armour is metal")
	check(_props(p.model) >= 4, "with a helmet, plume and cape, and the Ninja's props are gone (%d props)" % _props(p.model))
	for id in Skins.ORDER:
		p.set_skin(id)
		check(p.skin_id == id, "'%s' can be worn" % id)
	p.set_skin("not_a_skin")
	check(p.skin_id == "ranger", "an unknown skin falls back to the Ranger")

	# the lobby picker
	var menu = world.menu
	settings.skin = "ranger"
	menu._cycle_skin(1)
	check(settings.skin == Skins.ORDER[1] and menu.skin_name_label.text == Skins.LIST[Skins.ORDER[1]].name.to_upper(), "the arrows pick the next skin (%s)" % settings.skin)
	var lobby_torso: MeshInstance = menu.lobby.character.find_node("TorsoMesh", true, false)
	check(lobby_torso.get_surface_material(0).albedo_color.v < 0.2, "the lobby character tries it on")
	menu._cycle_skin(-1)
	check(settings.skin == "ranger", "and the other arrow goes back")
	menu._cycle_skin(-1)
	check(settings.skin == Skins.ORDER[Skins.ORDER.size() - 1], "the list wraps around")
	settings.skin = "ranger"
	settings.save_settings()

	var kinds := {}
	for f in get_nodes_in_group("fighters"):
		kinds[f.skin_id] = true
	check(kinds.size() >= 4, "the bots wear a mix of skins (%d kinds)" % kinds.size())

	print("SKIN_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

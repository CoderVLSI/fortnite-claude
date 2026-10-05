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
	check(Skins.ORDER.size() == 19 and Skins.LIST.size() == 19, "nineteen skins exist")

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

	# the Locker
	var menu = world.menu
	var Cosmetics = load("res://scripts/Cosmetics.gd")
	settings.loadout = Cosmetics.DEFAULT_LOADOUT.duplicate()
	menu._on_button("locker")
	check(menu.locker_panel.visible, "the Locker tab opens the locker")
	check(menu.locker_tabs.size() == 6 and menu.locker_tabs.has("emote"), "it has six tabs (skin, pickaxe, back bling, contrail, glider, emotes)")
	menu.locker_select("skin", "ninja")
	check(settings.loadout.skin == "ninja", "picking a skin equips it")
	var lobby_torso: MeshInstance = menu.lobby.character.find_node("TorsoMesh", true, false)
	check(lobby_torso.get_surface_material(0).albedo_color.v < 0.2, "the lobby character tries it on")
	menu.locker_select("backbling", "wings")
	check(menu.lobby._backbling != null, "back bling appears on the lobby character")
	menu.locker_select("pickaxe", "starwand")
	check(menu.lobby._held != null and menu.lobby._held.get_child_count() >= 2, "the lobby character holds the Star Wand")
	menu.locker_select("glider", "dragon")
	check(menu.lobby._glider_model != null and menu.lobby._glider_model.get_child_count() > 10, "the showcase glider becomes the Dragon")
	menu.locker_select("contrail", "rainbow")
	check(menu.lobby._contrail != null, "and the contrail streams behind it")
	for cat in Cosmetics.CATEGORIES:
		check(Cosmetics.table(cat).size() >= 5, "%s has at least five choices" % cat)

	# in a match: the player wears the loadout
	p.apply_loadout(settings.loadout)
	check(p.skin_id == "ninja" and p.glider != null and p._backbling_node != null and p._contrail != null, "the player model takes the whole loadout")
	check(p.held != null and p.held.get_child_count() >= 2, "the player swings the Star Wand")
	p.equip_sprite("earth")
	var sp_parent: Node = p._sprite_model.get_parent()
	check(sp_parent.name == "Spine" and p._sprite_model.translation.z > 0.2, "the sprite rides on the back (parent %s)" % sp_parent.name)
	p.tick_sprite(0.1)
	check(not p._backbling_node.visible, "and takes the back bling's place")
	p.clear_sprite()
	p.tick_sprite(0.1)
	check(p._backbling_node.visible, "back bling returns when the sprite is gone")
	p.mode = p.Mode.GLIDE
	p.tick_sprite(0.1)
	check(p._contrail.emitting, "the contrail streams while gliding")
	p.mode = p.Mode.GROUND
	p.tick_sprite(0.1)
	check(not p._contrail.emitting, "and stops on the ground")
	settings.loadout = Cosmetics.DEFAULT_LOADOUT.duplicate()
	settings.save_settings()

	var kinds := {}
	for f in get_nodes_in_group("fighters"):
		kinds[f.skin_id] = true
	check(kinds.size() >= 4, "the bots wear a mix of skins (%d kinds)" % kinds.size())

	print("SKIN_RESULT failures=", failures.size())
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

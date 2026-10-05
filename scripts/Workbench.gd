extends Spatial
# A workbench: spend gold to fit weapon mods to the weapon in your hand, or to upgrade it one rarity step. Opens the same shop window
# as the vending machines (same interface: title / entries / buy_offer).

const Items = preload("res://scripts/Items.gd")

const UPGRADE_BASE := 70


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("workbenches")
	var wood := SpatialMaterial.new()
	wood.albedo_color = Color(0.55, 0.38, 0.2)
	var steel := SpatialMaterial.new()
	steel.albedo_color = Color(0.35, 0.37, 0.42)
	steel.metallic = 0.7
	steel.roughness = 0.4
	var accent := SpatialMaterial.new()
	accent.albedo_color = Color(1.0, 0.6, 0.15)
	accent.emission_enabled = true
	accent.emission = Color(1.0, 0.5, 0.1)
	accent.emission_energy = 0.6
	_box(Vector3(1.9, 0.14, 0.9), Vector3(0, 0.95, 0), wood)                       # the bench top
	for sx in [-0.8, 0.8]:
		for sz in [-0.35, 0.35]:
			_box(Vector3(0.12, 0.9, 0.12), Vector3(sx, 0.45, sz), steel)           # legs
	_box(Vector3(1.7, 0.1, 0.7), Vector3(0, 0.35, 0), steel)                       # lower shelf
	_box(Vector3(0.35, 0.22, 0.3), Vector3(-0.6, 1.13, 0), steel)                  # vise
	_box(Vector3(0.2, 0.1, 0.3), Vector3(-0.6, 1.3, 0), accent)
	_box(Vector3(0.5, 0.05, 0.3), Vector3(0.3, 1.04, 0.1), accent)                 # a glowing blueprint
	_box(Vector3(1.9, 0.6, 0.08), Vector3(0, 1.45, 0.4), steel)                    # tool board
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape.new()
	shape.extents = Vector3(0.95, 0.55, 0.45)
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 0.55, 0)
	body.add_child(cs)
	add_child(body)
	var glow := OmniLight.new()
	glow.light_color = Color(1.0, 0.6, 0.2)
	glow.light_energy = 0.6
	glow.omni_range = 5.0
	glow.translation = Vector3(0, 1.8, -0.6)
	add_child(glow)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance.new()
	var c := CubeMesh.new()
	c.size = size
	m.mesh = c
	m.material_override = mat
	m.translation = pos
	add_child(m)


func can_interact() -> bool:
	return true


func prompt_text() -> String:
	return "Use the Workbench  (weapon mods and upgrades)"


func prompt_color() -> Color:
	return Color(1.0, 0.7, 0.3)


func interact(by) -> void:
	for w in get_tree().get_nodes_in_group("world"):
		if w.hud != null and by.is_in_group("player"):
			w.hud.open_vending(self)
			return


func title() -> String:
	return "Workbench"


func _held(by = null):
	for p in get_tree().get_nodes_in_group("player"):
		return p.selected_item()
	return null


func upgrade_price(item) -> int:
	return UPGRADE_BASE * (int(item.rarity) + 2) if item != null and item.kind == "weapon" else 0


func can_upgrade(item) -> bool:
	return item != null and item.kind == "weapon" and Items.WEAPONS.has(item.id) and Items.WEAPONS[item.id].has("dmg") and int(item.rarity) < 4


func _icon_for_mod(id: String) -> String:
	if ResourceLoader.exists("res://assets/icons/mod_%s.png" % id):
		return "mod_" + id
	return {"ext_mag": "ammo_medium", "fast_mag": "ammo_light", "grip": "ammo_shells", "sight": "weapon_dmr"}[id]


func entries() -> Array:
	var out := []
	for id in Items.MODS:
		var m: Dictionary = Items.MODS[id]
		out.append({"name": m.name, "icon": _icon_for_mod(id), "price": m.price, "sub": m.desc})
	var held = _held()
	out.append({"name": "Upgrade weapon", "icon": "weapon_assault", "price": upgrade_price(held) if can_upgrade(held) else 0,
		"sub": "held gun +1 rarity" if can_upgrade(held) else "hold a weapon first"})
	return out


func buy_offer(by, index: int) -> bool:
	var ids: Array = Items.MODS.keys()
	var held = by.selected_item()
	if index < 0 or index > ids.size():
		return false
	if index < ids.size():
		var id: String = ids[index]
		var price: int = Items.MODS[id].price
		if by.gold < price:
			by.emit_signal("picked_up", "Need %d gold" % price)
			Audio.play2d("ui_error", -4.0)
			return false
		if not Items.can_mod(held, id) and by.mod_stash.size() >= 6:
			by.emit_signal("picked_up", "Mod stash full")
			return false
		by.gold -= price
		if Items.can_mod(held, id):
			by.attach_mod(id)
			by.emit_signal("picked_up", "%s fitted to %s" % [Items.MODS[id].name, Items.name_of(held)])
		else:
			by.mod_stash.append(id)
			by.emit_signal("picked_up", "%s kept for your next weapon" % Items.MODS[id].name)
		Audio.play3d("chest_open", global_transform.origin + Vector3(0, 1.0, 0), -2.0, 1.3)
		return true
	# the upgrade
	if not can_upgrade(held):
		by.emit_signal("picked_up", "Hold a weapon that can be upgraded")
		Audio.play2d("ui_error", -4.0)
		return false
	var cost := upgrade_price(held)
	if by.gold < cost:
		by.emit_signal("picked_up", "Need %d gold" % cost)
		Audio.play2d("ui_error", -4.0)
		return false
	by.gold -= cost
	held.rarity = int(held.rarity) + 1
	by._apply_selected()
	by.emit_signal("slot_changed")
	by.emit_signal("picked_up", "Upgraded: " + Items.name_of(held))
	Audio.play3d("rarity_%d" % (int(held.rarity) + 1), global_transform.origin, -2.0)
	return true

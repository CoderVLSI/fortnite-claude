extends Spatial
# A vending machine: spend gold bars (press interact next to it) to get a random item that pops out of the dispenser.
#   weapons  a rare-or-better weapon with ammo
#   healing  heals and shields
#   utility  grenades, building materials, ammo or the odd Chug Jug
# Every purchase makes the next one from that machine a bit dearer.

const Items = preload("res://scripts/Items.gd")

const KINDS := {
	"weapons": {"title": "Weapon Machine", "buy": "a weapon", "base": 100, "color": Color(1.0, 0.32, 0.25)},
	"healing": {"title": "Healing Machine", "buy": "healing", "base": 40, "color": Color(0.4, 1.0, 0.5)},
	"utility": {"title": "Utility Machine", "buy": "supplies", "base": 60, "color": Color(0.4, 0.7, 1.0)},
}

export var kind := "weapons"

var price := 100
var uses := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	add_to_group("interactable")
	add_to_group("vending")
	price = KINDS[kind].base
	var scene = load("res://assets/models/vending_machine.glb")
	if scene != null:
		var model: Spatial = scene.instance()
		add_child(model)
		Items.apply_accent(model, KINDS[kind].color)
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape.new()
	shape.extents = Vector3(0.52, 1.05, 0.45)
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 1.05, 0)
	body.add_child(cs)
	add_child(body)
	var glow := OmniLight.new()                          # a coloured glow so the machine reads from a distance
	glow.light_color = KINDS[kind].color
	glow.light_energy = 0.7
	glow.omni_range = 6.0
	glow.translation = Vector3(0, 1.6, -1.0)
	add_child(glow)


func can_interact() -> bool:
	return true


func prompt_text() -> String:
	return "Open the %s  (from %d gold)" % [KINDS[kind].title, int(entries()[0].price)]


func prompt_color() -> Color:
	return Items.GOLD_COLOR


# The shop window: a fixed stock of six things per machine, each with a picture and a price. Every purchase makes the whole
# machine a little dearer.
func title() -> String:
	return KINDS[kind].title


func _price_mult() -> float:
	return 1.0 + 0.10 * float(uses)


func stock() -> Array:
	match kind:
		"healing":
			return [
				{"name": "Bandage x6", "icon": "heal_bandage", "price": 40, "give": [Items.make_consumable("bandage", 6)]},
				{"name": "Mini Shield x3", "icon": "heal_mini_shield", "price": 60, "give": [Items.make_consumable("mini_shield", 3)]},
				{"name": "Medkit", "icon": "heal_medkit", "price": 80, "give": [Items.make_consumable("medkit", 1)]},
				{"name": "Shield Potion", "icon": "heal_shield_potion", "price": 90, "give": [Items.make_consumable("shield_potion", 1)]},
				{"name": "Slurp Juice x2", "icon": "heal_slurp_juice", "price": 110, "give": [Items.make_consumable("slurp_juice", 2)]},
				{"name": "Chug Jug", "icon": "heal_chug_jug", "price": 200, "give": [Items.make_consumable("chug_jug", 1)]},
			]
		"utility":
			return [
				{"name": "Grenade x3", "icon": "heal_grenade", "price": 60, "give": [Items.make_consumable("grenade", 3)]},
				{"name": "Bouncer x2", "icon": "heal_bouncer", "price": 70, "give": [Items.make_consumable("bouncer", 2)]},
				{"name": "Wood 150", "icon": "material_wood", "price": 40, "give": [Items.make_material("wood", 150)]},
				{"name": "Stone 150", "icon": "material_stone", "price": 50, "give": [Items.make_material("stone", 150)]},
				{"name": "Metal 150", "icon": "material_metal", "price": 60, "give": [Items.make_material("metal", 150)]},
				{"name": "Heavy Ammo", "icon": "ammo_heavy", "price": 60, "give": [Items.make_ammo("heavy", Items.AMMO["heavy"].pack * 2)]},
			]
	var out := []
	for w in [["pistol", 70], ["smg", 90], ["assault", 110], ["shotgun", 110], ["burst_assault", 130], ["sniper", 160]]:
		var it := Items.make_weapon(w[0], 2)
		out.append({"name": Items.name_of(it), "icon": "weapon_" + str(Items.WEAPONS[w[0]].get("icon", w[0])), "price": w[1],
			"give": [it, Items.make_ammo(Items.WEAPONS[w[0]].ammo, Items.AMMO[Items.WEAPONS[w[0]].ammo].pack * 2)]})
	return out


# What the window shows right now: the stock with today's prices.
func entries() -> Array:
	var out := []
	for e in stock():
		out.append({"name": e.name, "icon": e.icon, "price": int(ceil(float(e.price) * _price_mult() / 5.0)) * 5})
	return out


# Buy offer `index` with the gold of `by`. Returns true when something was sold.
func buy_offer(by, index: int) -> bool:
	var st := stock()
	var en := entries()
	if index < 0 or index >= st.size():
		return false
	var cost: int = en[index].price
	if by.gold < cost:
		by.emit_signal("picked_up", "Need %d gold" % cost)
		Audio.play2d("ui_error", -4.0)
		return false
	by.gold -= cost
	if by.has_method("stat_add"):
		by.stat_add("buys")
	uses += 1
	_dispense(st[index].give)
	by.emit_signal("picked_up", "Bought: " + str(st[index].name))
	return true


func _dispense(items: Array) -> void:
	var out := global_transform.origin + (-global_transform.basis.z) * 1.2 + Vector3(0, 0.5, 0)
	var spread := global_transform.basis.x
	for i in range(items.size()):
		for w in get_tree().get_nodes_in_group("world"):
			w.spawn_item(items[i], out + spread * (float(i) - float(items.size() - 1) / 2.0) * 0.9)
	Audio.play3d("chest_open", global_transform.origin + Vector3(0, 1.0, 0), -2.0, 1.2)


# Press interact: the shop window opens (the old "random item" button is quick_buy, used when there is no screen to show it on).
func interact(by) -> void:
	for w in get_tree().get_nodes_in_group("world"):
		if w.hud != null and by.is_in_group("player"):
			w.hud.open_vending(self)
			return
	quick_buy(by)


func quick_buy(by) -> void:
	if by.gold < price:
		by.emit_signal("picked_up", "Need %d gold" % price)
		Audio.play2d("ui_error", -4.0)
		return
	by.gold -= price
	if by.has_method("stat_add"):
		by.stat_add("buys")
	uses += 1
	price = int(ceil(price * 1.3 / 5.0)) * 5
	var out := global_transform.origin + (-global_transform.basis.z) * 1.2 + Vector3(0, 0.5, 0)
	var items := roll()
	var spread := global_transform.basis.x
	for i in range(items.size()):
		for w in get_tree().get_nodes_in_group("world"):
			w.spawn_item(items[i], out + spread * (float(i) - float(items.size() - 1) / 2.0) * 0.9)
	Audio.play3d("chest_open", global_transform.origin + Vector3(0, 1.0, 0), -2.0, 1.2)
	by.emit_signal("picked_up", "Bought: " + Items.name_of(items[0]))


# What one purchase gives (also used by the tests).
func roll() -> Array:
	match kind:
		"weapons":
			var w := Items.random_weapon(rng, 2)
			return [w, Items.ammo_for(w, rng, 1.5)]
		"healing":
			var table := [["medkit", 1], ["shield_potion", 1], ["slurp_juice", 2], ["bandage", 6], ["mini_shield", 3]]
			var pick: Array = table[rng.randi() % table.size()]
			return [Items.make_consumable(pick[0], pick[1])]
	var r := rng.randf()
	if r < 0.35:
		return [Items.make_consumable("grenade", 3)]
	if r < 0.70:
		var kinds := ["wood", "stone", "metal"]
		return [Items.make_material(kinds[rng.randi() % 3], 150)]
	if r < 0.90:
		var types: Array = Items.AMMO.keys()
		types.shuffle()
		return [Items.make_ammo(types[0], Items.AMMO[types[0]].pack * 2), Items.make_ammo(types[1], Items.AMMO[types[1]].pack * 2)]
	return [Items.make_consumable("chug_jug", 1)]

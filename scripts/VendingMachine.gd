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
	return "Buy %s  (%d gold)" % [KINDS[kind].buy, price]


func prompt_color() -> Color:
	return Items.GOLD_COLOR


func interact(by) -> void:
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

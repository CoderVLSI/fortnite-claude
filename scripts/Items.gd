extends Reference
# Item database and helpers. Items are plain Dictionaries:
#   {"kind": "weapon",     "id": "assault", "rarity": 2, "mag": 30}
#   {"kind": "consumable", "id": "medkit",  "count": 1}
#   {"kind": "ammo",       "id": "light",   "count": 30}     (floor pickup only, goes to reserves)
#   {"kind": "pickaxe"}

const SLOT_COUNT := 5

const RARITIES := [
	{"name": "Common", "color": Color(0.72, 0.74, 0.78), "mult": 1.00},
	{"name": "Uncommon", "color": Color(0.36, 0.80, 0.30), "mult": 1.06},
	{"name": "Rare", "color": Color(0.25, 0.55, 1.00), "mult": 1.12},
	{"name": "Epic", "color": Color(0.70, 0.35, 0.95), "mult": 1.18},
	{"name": "Legendary", "color": Color(1.00, 0.72, 0.15), "mult": 1.25},
]
const RARITY_WEIGHTS := [50, 28, 14, 6, 2]

const WEAPONS := {
	"pistol": {"name": "Pistol", "damage": 23.0, "interval": 0.30, "mag": 16, "reload": 1.5, "spread": 0.9,
		"pellets": 1, "auto": false, "ammo": "light", "range": 120.0, "head": 2.0},
	"smg": {"name": "Submachine Gun", "damage": 14.0, "interval": 0.075, "mag": 30, "reload": 1.9, "spread": 2.4,
		"pellets": 1, "auto": true, "ammo": "light", "range": 95.0, "head": 1.6},
	"assault": {"name": "Assault Rifle", "damage": 20.0, "interval": 0.12, "mag": 30, "reload": 2.0, "spread": 1.1,
		"pellets": 1, "auto": true, "ammo": "medium", "range": 160.0, "head": 1.8},
	"shotgun": {"name": "Pump Shotgun", "damage": 11.0, "interval": 0.95, "mag": 5, "reload": 3.0, "spread": 4.5,
		"pellets": 9, "auto": false, "ammo": "shells", "range": 42.0, "head": 1.5},
	"sniper": {"name": "Bolt Sniper", "damage": 85.0, "interval": 1.50, "mag": 1, "reload": 2.6, "spread": 0.0,
		"pellets": 1, "auto": false, "ammo": "heavy", "range": 260.0, "head": 2.5},
}

const AMMO := {
	"light": {"name": "Light Ammo", "color": Color(0.95, 0.75, 0.25), "pack": 30},
	"medium": {"name": "Medium Ammo", "color": Color(0.55, 0.85, 0.35), "pack": 30},
	"shells": {"name": "Shells", "color": Color(0.95, 0.45, 0.25), "pack": 10},
	"heavy": {"name": "Heavy Ammo", "color": Color(0.45, 0.65, 1.0), "pack": 6},
}

const CONSUMABLES := {
	"bandage": {"name": "Bandage", "heal": 15.0, "heal_cap": 75.0, "shield": 0.0, "shield_cap": 0.0,
		"time": 3.0, "stack": 15, "rarity": 0},
	"medkit": {"name": "Medkit", "heal": 100.0, "heal_cap": 100.0, "shield": 0.0, "shield_cap": 0.0,
		"time": 7.0, "stack": 3, "rarity": 2},
	"mini_shield": {"name": "Mini Shield", "heal": 0.0, "heal_cap": 0.0, "shield": 25.0, "shield_cap": 50.0,
		"time": 2.0, "stack": 6, "rarity": 1},
	"shield_potion": {"name": "Shield Potion", "heal": 0.0, "heal_cap": 0.0, "shield": 50.0, "shield_cap": 100.0,
		"time": 4.0, "stack": 2, "rarity": 2},
}

const MODEL_DIR := "res://assets/models/"


static func pickaxe() -> Dictionary:
	return {"kind": "pickaxe", "id": "pickaxe"}


static func make_weapon(id: String, rarity: int = 0) -> Dictionary:
	return {"kind": "weapon", "id": id, "rarity": rarity, "mag": WEAPONS[id].mag}


static func make_consumable(id: String, count: int = 1) -> Dictionary:
	return {"kind": "consumable", "id": id, "count": count}


static func make_ammo(type: String, count: int = 0) -> Dictionary:
	return {"kind": "ammo", "id": type, "count": count if count > 0 else AMMO[type].pack}


static func rarity_of(item: Dictionary) -> int:
	match item.kind:
		"weapon":
			return item.rarity
		"consumable":
			return CONSUMABLES[item.id].rarity
	return 0


static func color_of(item: Dictionary) -> Color:
	if item.kind == "ammo":
		return AMMO[item.id].color
	if item.kind == "pickaxe":
		return RARITIES[0].color
	return RARITIES[rarity_of(item)].color


static func name_of(item: Dictionary) -> String:
	match item.kind:
		"weapon":
			return "%s %s" % [RARITIES[item.rarity].name, WEAPONS[item.id].name]
		"consumable":
			var n: String = CONSUMABLES[item.id].name
			return n if item.count <= 1 else "%s x%d" % [n, item.count]
		"ammo":
			return "%s x%d" % [AMMO[item.id].name, item.count]
	return "Pickaxe"


static func model_of(item: Dictionary) -> String:
	if item.kind == "weapon":
		return MODEL_DIR + ("rifle" if item.id == "assault" else item.id) + ".glb"
	if item.kind == "consumable":
		return MODEL_DIR + item.id + ".glb"
	if item.kind == "ammo":
		return MODEL_DIR + "ammo_pickup.glb"
	return MODEL_DIR + "pickaxe.glb"


# Effective weapon stats for a weapon item (rarity scales damage).
static func weapon_stats(item: Dictionary) -> Dictionary:
	var s: Dictionary = WEAPONS[item.id].duplicate()
	s.damage = s.damage * RARITIES[item.rarity].mult
	return s


static func roll_rarity(rng: RandomNumberGenerator, bonus: int = 0) -> int:
	var total := 0
	for w in RARITY_WEIGHTS:
		total += w
	var r := rng.randi() % total
	var tier := 0
	for i in range(RARITY_WEIGHTS.size()):
		if r < RARITY_WEIGHTS[i]:
			tier = i
			break
		r -= RARITY_WEIGHTS[i]
	return int(min(tier + bonus, RARITIES.size() - 1))


static func random_weapon(rng: RandomNumberGenerator, bonus: int = 0) -> Dictionary:
	var table := ["assault", "assault", "assault", "smg", "smg", "shotgun", "shotgun", "pistol", "pistol", "sniper"]
	return make_weapon(table[rng.randi() % table.size()], roll_rarity(rng, bonus))


static func random_consumable(rng: RandomNumberGenerator) -> Dictionary:
	var table := ["bandage", "bandage", "bandage", "mini_shield", "mini_shield", "medkit", "shield_potion"]
	var id: String = table[rng.randi() % table.size()]
	var count := 1
	if id == "bandage":
		count = 3 + rng.randi() % 4
	elif id == "mini_shield":
		count = 1 + rng.randi() % 2
	return make_consumable(id, count)


static func random_floor_item(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	if r < 0.42:
		return random_weapon(rng)
	if r < 0.78:
		return random_consumable(rng)
	return make_ammo(AMMO.keys()[rng.randi() % AMMO.size()])


static func ammo_for(weapon: Dictionary, rng: RandomNumberGenerator, mult: float = 1.0) -> Dictionary:
	var type: String = WEAPONS[weapon.id].ammo
	return make_ammo(type, int(AMMO[type].pack * (1.0 + rng.randf()) * mult))


# What each chest variety holds.
static func chest_loot(kind: String, rng: RandomNumberGenerator) -> Array:
	var loot := []
	match kind:
		"chest":      # treasure chest: a real weapon (uncommon+), a heal/shield, matching ammo
			var w := random_weapon(rng, 1)
			loot.append(w)
			loot.append(ammo_for(w, rng, 1.5))
			loot.append(random_consumable(rng))
		"ammo_box":   # ammo box: lots of ammo, two types
			var types: Array = AMMO.keys()
			types.shuffle()
			for i in range(2):
				loot.append(make_ammo(types[i], int(AMMO[types[i]].pack * (1.5 + rng.randf()))))
		"supply":     # supply drop: top-tier weapons plus shield/heal
			var w1 := make_weapon(["assault", "sniper", "shotgun", "smg"][rng.randi() % 4], 3 + rng.randi() % 2)
			var w2 := random_weapon(rng, 2)
			loot.append(w1)
			loot.append(w2)
			loot.append(make_consumable("shield_potion", 2))
			loot.append(make_consumable("medkit", 1))
			loot.append(ammo_for(w1, rng, 2.0))
			loot.append(ammo_for(w2, rng, 2.0))
	return loot


# Beam / glow colour for each chest variety.
static func chest_color(kind: String) -> Color:
	match kind:
		"chest":
			return Color(1.0, 0.75, 0.2)
		"ammo_box":
			return Color(0.45, 0.85, 0.4)
		"supply":
			return Color(1.0, 0.3, 0.25)
	return Color.white

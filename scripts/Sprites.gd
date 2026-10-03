extends Reference
# Sprites: little companions that float beside you while equipped (your backpack's Sprite slot) and grant one passive power.
# Rarer sprites have stranger powers. A sprite levels up as you eliminate players and open chests (power scales with level),
# and may be a Gold or Galaxy variant with a small extra perk. Catch wild ones around the island; catching one swaps it
# with whatever you carry.

const LIST := {
	"earth": {"name": "Earth Sprite", "rarity": 2, "color": Color(0.45, 0.85, 0.3), "desc": "Chests may hold an extra rare weapon"},
	"fire": {"name": "Fire Sprite", "rarity": 2, "color": Color(1.0, 0.5, 0.15), "desc": "Dealing heavy damage sets off a fiery burst"},
	"water": {"name": "Water Sprite", "rarity": 2, "color": Color(0.25, 0.62, 1.0), "desc": "Refills your shield while swimming"},
	"duck": {"name": "Duck Sprite", "rarity": 3, "color": Color(1.0, 0.86, 0.2), "desc": "Emoting refills your shield"},
	"ghost": {"name": "Ghost Sprite", "rarity": 3, "color": Color(0.82, 0.86, 1.0), "desc": "Reloading cloaks you for a moment"},
	"demon": {"name": "Demon Sprite", "rarity": 3, "color": Color(0.9, 0.2, 0.3), "desc": "Eliminations restore health and shield"},
	"king": {"name": "King Sprite", "rarity": 3, "color": Color(0.85, 0.62, 1.0), "desc": "Your pickaxe hits harder and harvests more"},
	"dream": {"name": "Dream Sprite", "rarity": 4, "color": Color(0.75, 0.5, 1.0), "desc": "Gives an item each level; bursts with loot at max level"},
	"punk": {"name": "Punk Sprite", "rarity": 4, "color": Color(1.0, 0.35, 0.7), "desc": "Eliminations can grant unlimited ammo"},
	"aegis": {"name": "Aegis Sprite", "rarity": 5, "color": Color(0.4, 1.0, 0.9), "desc": "Healing raises a protective bubble"},
	"lucky": {"name": "Lucky Sprite", "rarity": 5, "color": Color(1.0, 0.72, 0.15), "desc": "Eliminations may drop extra loot"},
}
const ORDER := ["earth", "fire", "water", "duck", "ghost", "demon", "king", "dream", "punk", "aegis", "lucky"]
const STARTERS := ["none", "earth", "fire", "water"]      # what you may bring to a match
const MAX_LEVEL := 5
const XP_NEEDED := [3.0, 7.0, 12.0, 18.0]               # total xp for level 2, 3, 4, 5
const VARIANTS := {
	"gold": {"name": "Gold", "tint": Color(1.0, 0.84, 0.25), "desc": "Eliminations pay gold"},
	"galaxy": {"name": "Galaxy", "tint": Color(0.55, 0.4, 1.0), "desc": "Ammo pickups give 30% more"},
}


static func title(id: String, variant: String = "") -> String:
	var n: String = LIST[id].name
	return (VARIANTS[variant].name + " " + n) if VARIANTS.has(variant) else n


static func color(id: String, variant: String = "") -> Color:
	if VARIANTS.has(variant):
		return LIST[id].color.linear_interpolate(VARIANTS[variant].tint, 0.55)
	return LIST[id].color


static func rarity_color(id: String) -> Color:
	return preload("res://scripts/Items.gd").RARITIES[LIST[id].rarity].color


# Total xp needed to reach level+1 (0 at max level).
static func xp_to_next(level: int) -> float:
	return XP_NEEDED[level - 1] if level >= 1 and level < MAX_LEVEL else 0.0


# {id, variant, level, xp} for a random wild sprite: most are rare, few mythic.
static func random_wild(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	var rarity := 2 if r < 0.55 else (3 if r < 0.83 else (4 if r < 0.96 else 5))
	var pool := []
	for id in ORDER:
		if LIST[id].rarity == rarity:
			pool.append(id)
	var variant := ""
	var v := rng.randf()
	if v < 0.10:
		variant = "gold"
	elif v < 0.18:
		variant = "galaxy"
	return {"id": pool[rng.randi() % pool.size()], "variant": variant, "level": 1, "xp": 0.0}

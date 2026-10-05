extends Reference
# Player skins: each one recolours the character (skin, outfit, boots, hair, gloves, pack) and may add props (hats,
# helmets, tails). apply() works on a model built from player.glb, so the lobby, the player and the bots share it.

const LIST := {
	"ranger": {"name": "Ranger", "desc": "The classic field kit", "skin": Color(0.80, 0.52, 0.36), "vest": Color(0.30, 0.42, 0.22),
		"pants": Color(0.32, 0.22, 0.14), "boots": Color(0.10, 0.09, 0.08), "hair": Color(0.07, 0.05, 0.04),
		"glove": Color(0.14, 0.14, 0.16), "pack": Color(0.27, 0.23, 0.17)},
	"ninja": {"name": "Shadow Ninja", "desc": "Quiet, dark and fast", "skin": Color(0.10, 0.10, 0.13), "vest": Color(0.09, 0.09, 0.12),
		"pants": Color(0.08, 0.08, 0.10), "boots": Color(0.05, 0.05, 0.06), "hair": Color(0.05, 0.05, 0.06),
		"glove": Color(0.06, 0.06, 0.08), "pack": Color(0.55, 0.08, 0.08), "eyes": Color(1.0, 1.0, 1.0), "no_face": true, "acc": ["headband", "scarf"]},
	"astronaut": {"name": "Astro", "desc": "One small step for a battle royale", "skin": Color(0.88, 0.88, 0.92), "vest": Color(0.92, 0.92, 0.95),
		"pants": Color(0.88, 0.88, 0.92), "boots": Color(0.55, 0.57, 0.62), "hair": Color(0.88, 0.88, 0.92),
		"glove": Color(0.95, 0.60, 0.15), "pack": Color(0.70, 0.72, 0.78), "acc": ["bubble", "bigpack"]},
	"knight": {"name": "Silver Knight", "desc": "Plate armour, plume and all", "skin": Color(0.62, 0.64, 0.70), "vest": Color(0.60, 0.62, 0.68),
		"pants": Color(0.46, 0.48, 0.54), "boots": Color(0.30, 0.31, 0.35), "hair": Color(0.60, 0.62, 0.68),
		"glove": Color(0.40, 0.42, 0.48), "pack": Color(0.70, 0.12, 0.12), "metal": true, "eyes": Color(0.02, 0.02, 0.04), "no_face": true, "acc": ["helm", "plume", "cape"]},
	"robot": {"name": "Unit 7", "desc": "Beep. Boop. Eliminate.", "skin": Color(0.55, 0.60, 0.68), "vest": Color(0.25, 0.30, 0.42),
		"pants": Color(0.35, 0.38, 0.46), "boots": Color(0.15, 0.16, 0.20), "hair": Color(0.55, 0.60, 0.68),
		"glove": Color(0.20, 0.22, 0.28), "pack": Color(0.18, 0.20, 0.26), "metal": true, "eyes": Color(0.2, 1.0, 1.0), "glow_eyes": true,
		"no_face": true, "acc": ["antenna"]},
	"pirate": {"name": "Captain Jolly", "desc": "Arr, mind the storm", "skin": Color(0.78, 0.50, 0.34), "vest": Color(0.55, 0.12, 0.12),
		"pants": Color(0.18, 0.22, 0.38), "boots": Color(0.20, 0.12, 0.07), "hair": Color(0.12, 0.08, 0.05),
		"glove": Color(0.22, 0.14, 0.08), "pack": Color(0.35, 0.22, 0.10), "stache": true, "acc": ["tricorn", "eyepatch"]},
	"cowboy": {"name": "Dusty Rider", "desc": "Yeehaw, partner", "skin": Color(0.82, 0.55, 0.38), "vest": Color(0.52, 0.34, 0.18),
		"pants": Color(0.22, 0.30, 0.50), "boots": Color(0.30, 0.18, 0.09), "hair": Color(0.30, 0.20, 0.10),
		"glove": Color(0.35, 0.22, 0.12), "pack": Color(0.40, 0.26, 0.14), "stache": true, "acc": ["cowboyhat", "bandana"]},
	"dino": {"name": "Rex Hoodie", "desc": "Rawr (it means eliminate)", "skin": Color(0.35, 0.72, 0.30), "vest": Color(0.30, 0.62, 0.26),
		"pants": Color(0.27, 0.52, 0.22), "boots": Color(0.22, 0.40, 0.18), "hair": Color(0.30, 0.62, 0.26),
		"glove": Color(0.27, 0.52, 0.22), "pack": Color(0.95, 0.55, 0.15), "acc": ["spikes", "tail"]},
	"banana": {"name": "Banana Bandit", "desc": "A whole banana. Do not slip.", "skin": Color(1.0, 0.86, 0.15), "vest": Color(1.0, 0.86, 0.15),
		"pants": Color(0.98, 0.82, 0.12), "boots": Color(0.42, 0.28, 0.10), "hair": Color(1.0, 0.86, 0.15),
		"glove": Color(1.0, 0.86, 0.15), "pack": Color(0.82, 0.62, 0.10), "eyes": Color(0.08, 0.05, 0.03), "no_nose": true, "acc": ["bananabody"]},
	"fishhead": {"name": "Captain Fishbone", "desc": "Something is fishy about this one", "skin": Color(0.45, 0.62, 0.72), "vest": Color(0.20, 0.32, 0.45),
		"pants": Color(0.16, 0.22, 0.32), "boots": Color(0.08, 0.10, 0.14), "hair": Color(0.45, 0.62, 0.72),
		"glove": Color(0.45, 0.62, 0.72), "pack": Color(0.55, 0.30, 0.15), "no_face": true, "acc": ["fishhead"]},
	"marine": {"name": "Emerald Marine", "desc": "Finish the fight in green armour", "skin": Color(0.30, 0.42, 0.22), "vest": Color(0.32, 0.45, 0.24),
		"pants": Color(0.26, 0.36, 0.20), "boots": Color(0.20, 0.27, 0.16), "hair": Color(0.30, 0.42, 0.22),
		"glove": Color(0.20, 0.27, 0.16), "pack": Color(0.55, 0.57, 0.60), "metal": true, "no_face": true, "acc": ["marinehelm"]},
	"wristhero": {"name": "Dial Kid", "desc": "One twist and anything can happen", "skin": Color(0.88, 0.66, 0.50), "vest": Color(0.08, 0.08, 0.10),
		"pants": Color(0.36, 0.28, 0.18), "boots": Color(0.10, 0.10, 0.12), "hair": Color(0.34, 0.20, 0.10),
		"glove": Color(0.30, 0.95, 0.35), "pack": Color(0.22, 0.60, 0.25), "acc": ["emblem"]},
	"pumpkin": {"name": "Jack Pumpkin", "desc": "Spooky all year round", "skin": Color(0.95, 0.50, 0.10), "vest": Color(0.20, 0.12, 0.25),
		"pants": Color(0.14, 0.09, 0.18), "boots": Color(0.08, 0.05, 0.10), "hair": Color(0.95, 0.50, 0.10),
		"glove": Color(0.14, 0.09, 0.18), "pack": Color(0.30, 0.55, 0.15), "no_face": true, "acc": ["pumpkinhead"]},
	"shark": {"name": "Shark Hoodie", "desc": "Needs a bigger boat", "skin": Color(0.84, 0.58, 0.42), "vest": Color(0.45, 0.55, 0.65),
		"pants": Color(0.30, 0.36, 0.44), "boots": Color(0.15, 0.18, 0.24), "hair": Color(0.45, 0.55, 0.65),
		"glove": Color(0.45, 0.55, 0.65), "pack": Color(0.85, 0.88, 0.92), "acc": ["sharkhood"]},
	"panda": {"name": "Pandamonium", "desc": "Bamboo not included", "skin": Color(0.95, 0.95, 0.95), "vest": Color(0.12, 0.12, 0.14),
		"pants": Color(0.12, 0.12, 0.14), "boots": Color(0.06, 0.06, 0.07), "hair": Color(0.95, 0.95, 0.95),
		"glove": Color(0.95, 0.95, 0.95), "pack": Color(0.20, 0.55, 0.20), "acc": ["pandaears"]},
	"viking": {"name": "Berserker", "desc": "Valhalla can wait", "skin": Color(0.88, 0.64, 0.48), "vest": Color(0.48, 0.30, 0.16),
		"pants": Color(0.28, 0.24, 0.20), "boots": Color(0.20, 0.13, 0.08), "hair": Color(0.85, 0.62, 0.22),
		"glove": Color(0.30, 0.20, 0.12), "pack": Color(0.70, 0.45, 0.20), "stache": true, "acc": ["vikinghelm", "beard"]},
	"chef": {"name": "Chef Moustachio", "desc": "Too many cooks, not enough storm shelters", "skin": Color(0.90, 0.68, 0.52), "vest": Color(0.95, 0.95, 0.96),
		"pants": Color(0.25, 0.28, 0.40), "boots": Color(0.10, 0.10, 0.12), "hair": Color(0.15, 0.10, 0.08),
		"glove": Color(0.95, 0.95, 0.96), "pack": Color(0.75, 0.15, 0.12), "stache": true, "acc": ["chefhat"]},
	"cactus": {"name": "Prickly Pete", "desc": "Hug at your own risk", "skin": Color(0.35, 0.65, 0.30), "vest": Color(0.28, 0.55, 0.25),
		"pants": Color(0.22, 0.45, 0.20), "boots": Color(0.55, 0.30, 0.15), "hair": Color(0.28, 0.55, 0.25),
		"glove": Color(0.35, 0.65, 0.30), "pack": Color(0.95, 0.55, 0.65), "acc": ["flower", "spikes"]},
	"chicken": {"name": "Big Chicken", "desc": "Fluffy, plump and very proud", "skin": Color(0.98, 0.94, 0.86), "vest": Color(0.98, 0.94, 0.86),
		"pants": Color(0.96, 0.90, 0.80), "boots": Color(0.95, 0.55, 0.12), "hair": Color(0.98, 0.94, 0.86),
		"glove": Color(0.97, 0.78, 0.20), "pack": Color(0.85, 0.22, 0.18), "eyes": Color(0.05, 0.04, 0.03), "no_face": true, "acc": ["chicken"]},
	"ranger_f": {"name": "Ranger Rose", "desc": "The field kit, with flair", "skin": Color(0.84, 0.58, 0.42), "vest": Color(0.30, 0.42, 0.22),
		"pants": Color(0.32, 0.22, 0.14), "boots": Color(0.10, 0.09, 0.08), "hair": Color(0.50, 0.24, 0.10),
		"glove": Color(0.14, 0.14, 0.16), "pack": Color(0.27, 0.23, 0.17), "fem": true, "acc": ["longhair"]},
	"aviator": {"name": "Ace Aviator", "desc": "Chocks away, storm ahead", "skin": Color(0.90, 0.68, 0.52), "vest": Color(0.45, 0.28, 0.14),
		"pants": Color(0.20, 0.24, 0.34), "boots": Color(0.20, 0.12, 0.08), "hair": Color(0.12, 0.08, 0.06),
		"glove": Color(0.30, 0.20, 0.12), "pack": Color(0.60, 0.50, 0.30), "fem": true, "acc": ["ponytail", "goggles"]},
	"scientist": {"name": "Dr. Spark", "desc": "For science! (and the storm circle)", "skin": Color(0.93, 0.72, 0.58), "vest": Color(0.96, 0.96, 0.98),
		"pants": Color(0.22, 0.26, 0.38), "boots": Color(0.15, 0.15, 0.18), "hair": Color(0.85, 0.35, 0.40),
		"glove": Color(0.20, 0.75, 0.55), "pack": Color(0.20, 0.75, 0.55), "fem": true, "acc": ["bun", "glasses", "labcoat"]},
	"witch": {"name": "Midnight Witch", "desc": "Brews trouble before breakfast", "skin": Color(0.88, 0.70, 0.60), "vest": Color(0.25, 0.12, 0.38),
		"pants": Color(0.20, 0.10, 0.30), "boots": Color(0.10, 0.06, 0.14), "hair": Color(0.45, 0.20, 0.65),
		"glove": Color(0.12, 0.08, 0.18), "pack": Color(0.55, 0.30, 0.75), "fem": true, "skirt": Color(0.20, 0.10, 0.30), "acc": ["longhair", "witchhat", "skirt"]},
	"pigtails": {"name": "Pippa", "desc": "Puddles are for jumping in", "skin": Color(0.92, 0.70, 0.55), "vest": Color(1.0, 0.85, 0.15),
		"pants": Color(0.25, 0.40, 0.75), "boots": Color(0.85, 0.20, 0.20), "hair": Color(0.90, 0.55, 0.15),
		"glove": Color(1.0, 0.85, 0.15), "pack": Color(0.85, 0.20, 0.20), "fem": true, "scale": 0.85, "skirt": Color(0.25, 0.40, 0.75), "acc": ["pigtails", "skirt"]},
	"princess": {"name": "Little Princess", "desc": "The crown is non-negotiable", "skin": Color(0.95, 0.76, 0.62), "vest": Color(0.98, 0.62, 0.80),
		"pants": Color(0.98, 0.62, 0.80), "boots": Color(0.95, 0.85, 0.40), "hair": Color(0.95, 0.80, 0.35),
		"glove": Color(1.0, 1.0, 1.0), "pack": Color(0.60, 0.40, 0.85), "fem": true, "scale": 0.85, "skirt": Color(0.98, 0.62, 0.80), "acc": ["longhair", "tiara", "skirt"]},
	"soccer": {"name": "Striker Zoe", "desc": "Kicks things. Mostly the storm.", "skin": Color(0.78, 0.55, 0.40), "vest": Color(0.15, 0.50, 0.90),
		"pants": Color(0.95, 0.95, 0.97), "boots": Color(0.10, 0.10, 0.12), "hair": Color(0.10, 0.07, 0.05),
		"glove": Color(0.15, 0.50, 0.90), "pack": Color(0.95, 0.95, 0.97), "fem": true, "scale": 0.85, "acc": ["ponytail", "headband"]},
	"bunny": {"name": "Bunny Hoodie", "desc": "Hop to it", "skin": Color(0.92, 0.72, 0.60), "vest": Color(0.98, 0.78, 0.86),
		"pants": Color(0.95, 0.90, 0.92), "boots": Color(0.98, 0.78, 0.86), "hair": Color(0.60, 0.38, 0.20),
		"glove": Color(0.98, 0.78, 0.86), "pack": Color(1.0, 1.0, 1.0), "fem": true, "scale": 0.85, "acc": ["bunnyears", "bow"]},
	"rodeo": {"name": "Rodeo Queen", "desc": "Rides hard, aims harder", "skin": Color(0.86, 0.60, 0.44), "vest": Color(0.75, 0.25, 0.30),
		"pants": Color(0.22, 0.30, 0.50), "boots": Color(0.35, 0.20, 0.10), "hair": Color(0.90, 0.62, 0.22),
		"glove": Color(0.40, 0.25, 0.12), "pack": Color(0.40, 0.26, 0.14), "fem": true, "acc": ["longhair", "cowboyhat", "bandana"]},
	"piratequeen": {"name": "Pirate Queen", "desc": "The seven seas, politely conquered", "skin": Color(0.82, 0.56, 0.40), "vest": Color(0.12, 0.30, 0.45),
		"pants": Color(0.30, 0.12, 0.14), "boots": Color(0.20, 0.12, 0.07), "hair": Color(0.10, 0.06, 0.05),
		"glove": Color(0.22, 0.14, 0.08), "pack": Color(0.35, 0.22, 0.10), "fem": true, "acc": ["longhair", "tricorn", "skirt"], "skirt": Color(0.30, 0.12, 0.14)},
	"shieldmaiden": {"name": "Shieldmaiden", "desc": "Braids, axes and zero fear", "skin": Color(0.92, 0.70, 0.55), "vest": Color(0.48, 0.30, 0.16),
		"pants": Color(0.28, 0.24, 0.20), "boots": Color(0.20, 0.13, 0.08), "hair": Color(0.88, 0.66, 0.25),
		"glove": Color(0.30, 0.20, 0.12), "pack": Color(0.70, 0.45, 0.20), "fem": true, "acc": ["vikinghelm", "braids"]},
	"chefbella": {"name": "Chef Bella", "desc": "Plates up eliminations", "skin": Color(0.88, 0.64, 0.48), "vest": Color(0.96, 0.96, 0.98),
		"pants": Color(0.24, 0.24, 0.30), "boots": Color(0.10, 0.10, 0.12), "hair": Color(0.20, 0.10, 0.08),
		"glove": Color(0.96, 0.96, 0.98), "pack": Color(0.85, 0.25, 0.30), "fem": true, "acc": ["bun", "chefhat"]},
	"astroada": {"name": "Astro Ada", "desc": "Mission control, we have a style", "skin": Color(0.90, 0.88, 0.92), "vest": Color(0.95, 0.95, 0.98),
		"pants": Color(0.90, 0.90, 0.94), "boots": Color(0.55, 0.57, 0.62), "hair": Color(0.15, 0.10, 0.20),
		"glove": Color(0.95, 0.45, 0.65), "pack": Color(0.70, 0.72, 0.78), "fem": true, "acc": ["ponytail", "bubble", "bigpack"]},
	"dame": {"name": "Dame Silver", "desc": "Plate armour with a pink plume", "skin": Color(0.62, 0.64, 0.70), "vest": Color(0.66, 0.68, 0.74),
		"pants": Color(0.50, 0.52, 0.58), "boots": Color(0.34, 0.35, 0.40), "hair": Color(0.62, 0.64, 0.70),
		"glove": Color(0.44, 0.46, 0.52), "pack": Color(0.90, 0.35, 0.55), "metal": true, "eyes": Color(0.02, 0.02, 0.04), "no_face": true, "acc": ["helm", "pinkplume", "cape"]},
}
const ORDER := ["ranger", "ninja", "astronaut", "knight", "robot", "pirate", "cowboy", "dino",
	"banana", "fishhead", "marine", "wristhero", "pumpkin", "shark", "panda", "viking", "chef", "cactus", "chicken",
	"ranger_f", "aviator", "scientist", "witch", "pigtails", "princess", "soccer", "bunny",
	"rodeo", "piratequeen", "shieldmaiden", "chefbella", "astroada", "dame"]


static func _mat(c: Color, metal: bool = false, emissive: bool = false) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = c
	m.roughness = 0.35 if metal else 0.9
	m.metallic = 0.7 if metal else 0.0
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy = 1.4
	return m


static func _box(parent: Spatial, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance:
	var mi := MeshInstance.new()
	var m := CubeMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.translation = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _ball(parent: Spatial, r: float, pos: Vector3, mat: Material, squash: Vector3 = Vector3.ONE) -> MeshInstance:
	var mi := MeshInstance.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	mi.mesh = m
	mi.material_override = mat
	mi.translation = pos
	mi.scale = squash
	parent.add_child(mi)
	return mi


static func _cone(parent: Spatial, r_bottom: float, r_top: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance:
	var mi := MeshInstance.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r_bottom
	m.top_radius = r_top
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	mi.translation = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func apply(model: Spatial, id: String, vest_override = null) -> void:
	if not LIST.has(id):
		id = "ranger"
	var d: Dictionary = LIST[id]
	model.scale = Vector3.ONE * float(d.get("scale", 1.0))          # the girls are a little smaller
	var metal: bool = d.get("metal", false)
	var vest: Color = vest_override if (vest_override != null and (id == "ranger" or id == "ranger_f")) else d.vest
	var roles := {"skin": _mat(d.skin, metal), "vest": _mat(vest, metal), "pants": _mat(d.pants, metal), "boots": _mat(d.boots, metal),
		"hair": _mat(d.hair, metal), "glove": _mat(d.glove), "pack": _mat(d.pack),
		"eyes": _mat(d.get("eyes", Color(0.05, 0.05, 0.08)), false, d.get("glow_eyes", false))}
	var layout := {"ShinL": ["pants", "boots"], "ShinR": ["pants", "boots"], "ThighL": ["pants"], "ThighR": ["pants"], "PelvisMesh": ["pants"],
		"HeadMesh": ["skin", "hair", "eyes"], "ForearmL": ["skin", "glove"], "ForearmR": ["skin", "glove"],
		"UpperArmL": ["vest"], "UpperArmR": ["vest"], "TorsoMesh": ["vest", "pack"]}
	for n in layout:
		var node := model.find_node(n, true, false)
		if node != null and node is MeshInstance:
			var rl: Array = layout[n]
			for i in range(rl.size()):
				node.set_surface_material(i, roles[rl[i]])
	# props from a previous skin go away
	for old in model.get_tree().get_nodes_in_group("skin_props") if model.is_inside_tree() else []:
		if model.is_a_parent_of(old):
			old.queue_free()
	for holder in _find_props(model):
		holder.get_parent().remove_child(holder)
		holder.queue_free()
	var head := model.find_node("Head", true, false)
	var spine := model.find_node("Spine", true, false)
	var hips := model.find_node("Hips", true, false)
	if head == null or spine == null or hips == null:
		return
	var hh := Spatial.new()
	hh.name = "SkinProps"
	head.add_child(hh)
	var sh := Spatial.new()
	sh.name = "SkinProps"
	spine.add_child(sh)
	var hp := Spatial.new()
	hp.name = "SkinProps"
	hips.add_child(hp)
	for acc in d.get("acc", []):
		_accessory(acc, hh, sh, hp, d)
	if not d.get("no_face", false):                 # helmets, masks and robots keep a blank face
		_face(hh, id, d, vest_override)


# A nose and a mouth on every visible face, and a moustache on pirates, cowboys and about half of the other fighters.
# Head-local coordinates: the face plane is z = -0.13, the eyes sit at y = 0.16.
static func _face(head: Spatial, id: String, d: Dictionary, vest_override) -> void:
	var skin: Color = d.skin
	var nose_mat := _mat(skin.darkened(0.14))
	var mouth_mat := _mat(Color(0.36, 0.12, 0.10) if skin.v > 0.3 else Color(0.8, 0.45, 0.4))
	if d.get("no_nose", false):                                                                   # a banana has a big smile and no nose
		_box(head, Vector3(0.14, 0.02, 0.012), Vector3(0, 0.07, -0.134), mouth_mat)
		_box(head, Vector3(0.025, 0.04, 0.012), Vector3(-0.075, 0.09, -0.134), mouth_mat)
		_box(head, Vector3(0.025, 0.04, 0.012), Vector3(0.075, 0.09, -0.134), mouth_mat)
		return
	_box(head, Vector3(0.045, 0.06, 0.05), Vector3(0, 0.115, -0.152), nose_mat)                 # nose
	_box(head, Vector3(0.09, 0.014, 0.012), Vector3(0, 0.05, -0.134), mouth_mat)                 # mouth
	if d.get("fem", false):                                                                       # lashes and lips
		var lash := _mat(Color(0.03, 0.02, 0.02))
		_box(head, Vector3(0.06, 0.012, 0.012), Vector3(-0.06, 0.2, -0.134), lash, Vector3(0, 0, 0.25))
		_box(head, Vector3(0.06, 0.012, 0.012), Vector3(0.06, 0.2, -0.134), lash, Vector3(0, 0, -0.25))
		_box(head, Vector3(0.075, 0.02, 0.014), Vector3(0, 0.05, -0.135), _mat(Color(0.82, 0.18, 0.28)))   # red lips
		_box(head, Vector3(0.06, 0.012, 0.012), Vector3(-0.06, 0.208, -0.134), lash, Vector3(0, 0, 0.25))  # a second, fuller lash line
		_box(head, Vector3(0.06, 0.012, 0.012), Vector3(0.06, 0.208, -0.134), lash, Vector3(0, 0, -0.25))
		var blush := _mat(Color(0.98, 0.55, 0.60))
		_box(head, Vector3(0.05, 0.035, 0.012), Vector3(-0.085, 0.095, -0.134), blush)                    # rosy cheeks
		_box(head, Vector3(0.05, 0.035, 0.012), Vector3(0.085, 0.095, -0.134), blush)
		var shadow := _mat(Color(0.70, 0.45, 0.80))
		_box(head, Vector3(0.055, 0.012, 0.012), Vector3(-0.06, 0.225, -0.134), shadow)                   # eyeshadow
		_box(head, Vector3(0.055, 0.012, 0.012), Vector3(0.06, 0.225, -0.134), shadow)
		var gold := _mat(Color(0.98, 0.85, 0.30), true)
		_ball(head, 0.022, Vector3(-0.135, 0.07, -0.02), gold)                                            # earrings
		_ball(head, 0.022, Vector3(0.135, 0.07, -0.02), gold)
	var moustache: bool = d.get("stache", false)
	if (id == "ranger" or id == "ranger_f") and vest_override != null and not d.get("fem", false):
		moustache = (int(vest_override.r * 10.0) + int(vest_override.g * 7.0) + int(vest_override.b * 5.0)) % 2 == 0
	if moustache:
		var hair_mat := _mat(d.hair.darkened(0.1))
		_box(head, Vector3(0.12, 0.024, 0.03), Vector3(0, 0.083, -0.142), hair_mat)               # moustache: a bar...
		_box(head, Vector3(0.03, 0.03, 0.03), Vector3(-0.065, 0.07, -0.14), hair_mat, Vector3(0, 0, 0.5))   # ...and curled ends
		_box(head, Vector3(0.03, 0.03, 0.03), Vector3(0.065, 0.07, -0.14), hair_mat, Vector3(0, 0, -0.5))
	if id == "pirate":
		_box(head, Vector3(0.10, 0.07, 0.03), Vector3(0, 0.0, -0.13), _mat(d.hair.darkened(0.1)))   # and a short beard on the chin


static func _find_props(model: Node) -> Array:
	var out := []
	for c in model.get_children():
		if c.name == "SkinProps":
			out.append(c)
		out += _find_props(c)
	return out


# Joint-local coordinates: Head origin is the neck (head centre 0.14 up), Spine origin is the waist (chest 0.24 up, the back is +Z).
static func _accessory(name: String, head: Spatial, spine: Spatial, hips: Spatial, d: Dictionary) -> void:
	match name:
		"headband":
			_box(head, Vector3(0.29, 0.05, 0.29), Vector3(0, 0.22, 0), _mat(Color(0.8, 0.1, 0.1)))
			_box(head, Vector3(0.05, 0.05, 0.16), Vector3(0.0, 0.22, 0.2), _mat(Color(0.8, 0.1, 0.1)), Vector3(0.3, 0, 0))
		"scarf":
			_box(head, Vector3(0.30, 0.09, 0.30), Vector3(0, -0.02, 0), _mat(Color(0.8, 0.1, 0.1)))
			_box(spine, Vector3(0.1, 0.4, 0.04), Vector3(0.05, 0.1, 0.17), _mat(Color(0.8, 0.1, 0.1)), Vector3(0.25, 0, 0.1))
		"bubble":
			var g := SpatialMaterial.new()
			g.albedo_color = Color(0.7, 0.9, 1.0, 0.28)
			g.flags_transparent = true
			g.roughness = 0.1
			_ball(head, 0.27, Vector3(0, 0.15, 0), g)
			_box(head, Vector3(0.34, 0.06, 0.34), Vector3(0, -0.02, 0), _mat(Color(0.7, 0.72, 0.78), true))
		"bigpack":
			_box(spine, Vector3(0.42, 0.55, 0.22), Vector3(0, 0.24, 0.3), _mat(Color(0.82, 0.84, 0.9)))
			_box(spine, Vector3(0.3, 0.1, 0.1), Vector3(0, 0.34, 0.43), _mat(Color(0.95, 0.5, 0.15)))
		"helm":
			var steel := _mat(Color(0.72, 0.74, 0.80), true)
			_box(head, Vector3(0.32, 0.34, 0.32), Vector3(0, 0.15, 0), steel)
			_box(head, Vector3(0.20, 0.03, 0.02), Vector3(0, 0.15, -0.165), _mat(Color(0.03, 0.03, 0.05)))       # visor slit
		"plume":
			_box(head, Vector3(0.05, 0.14, 0.26), Vector3(0, 0.38, 0.02), _mat(Color(0.8, 0.12, 0.12)))
		"cape":
			_box(spine, Vector3(0.5, 0.75, 0.04), Vector3(0, 0.05, 0.22), _mat(Color(0.7, 0.12, 0.12)), Vector3(0.1, 0, 0))
		"antenna":
			_box(head, Vector3(0.025, 0.2, 0.025), Vector3(0.0, 0.38, 0), _mat(Color(0.5, 0.55, 0.6), true))
			_ball(head, 0.045, Vector3(0, 0.5, 0), _mat(Color(1.0, 0.3, 0.3), false, true))
			_box(head, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.14, 0.0), _mat(d.skin, true))
		"tricorn":
			var hat := _mat(Color(0.08, 0.07, 0.07))
			_box(head, Vector3(0.42, 0.04, 0.42), Vector3(0, 0.3, 0), hat)
			_box(head, Vector3(0.26, 0.12, 0.26), Vector3(0, 0.37, 0), hat)
			_box(head, Vector3(0.12, 0.05, 0.1), Vector3(0, 0.44, -0.12), _mat(Color(0.9, 0.85, 0.7)))
		"eyepatch":
			_box(head, Vector3(0.08, 0.07, 0.02), Vector3(0.06, 0.17, -0.14), _mat(Color(0.03, 0.03, 0.04)))
		"cowboyhat":
			var brown := _mat(Color(0.45, 0.28, 0.13))
			_cone(head, 0.30, 0.30, 0.03, Vector3(0, 0.3, 0), brown)
			_cone(head, 0.15, 0.13, 0.17, Vector3(0, 0.39, 0), brown)
		"bandana":
			_box(head, Vector3(0.30, 0.08, 0.30), Vector3(0, -0.02, 0), _mat(Color(0.2, 0.35, 0.8)))
		"spikes":
			for i in range(4):
				_cone(spine, 0.06, 0.0, 0.18, Vector3(0, 0.1 + i * 0.16, 0.2), _mat(Color(0.95, 0.55, 0.15)), Vector3(0.6, 0, 0))
		"bananabody":
			var yel := _mat(Color(1.0, 0.86, 0.15))
			var tip := _mat(Color(0.38, 0.24, 0.08))
			_ball(head, 0.17, Vector3(0.0, 0.28, 0.0), yel, Vector3(1.0, 1.35, 1.0))               # a long curved banana for a head:
			_ball(head, 0.15, Vector3(0.02, 0.45, 0.01), yel, Vector3(0.95, 1.3, 0.95))            # three overlapping lumps bend to one side
			_ball(head, 0.12, Vector3(0.07, 0.62, 0.02), yel, Vector3(0.9, 1.2, 0.9))
			_ball(head, 0.05, Vector3(0.12, 0.76, 0.03), tip, Vector3(0.9, 1.3, 0.9))              # the brown stem
			_box(head, Vector3(0.012, 0.15, 0.012), Vector3(-0.1, 0.38, -0.13), _mat(Color(0.85, 0.65, 0.08)))   # a ridge down the front
			_box(spine, Vector3(0.50, 0.04, 0.30), Vector3(0, 0.38, 0), _mat(Color(0.85, 0.65, 0.08)))            # the peel line round the middle
			_box(spine, Vector3(0.10, 0.12, 0.03), Vector3(0, 0.12, -0.16), _mat(Color(0.38, 0.24, 0.08)))         # a brown belly spot
		"chicken":
			var cream := _mat(Color(0.98, 0.94, 0.86))
			var down := _mat(Color(0.99, 0.80, 0.45))
			var red := _mat(Color(0.88, 0.16, 0.14))
			var org := _mat(Color(0.97, 0.58, 0.12))
			_ball(head, 0.17, Vector3(0, 0.14, 0.0), cream, Vector3(1.05, 1.0, 1.0))                  # a round fluffy head
			_ball(head, 0.055, Vector3(0, 0.34, -0.02), red)                                           # comb
			_ball(head, 0.06, Vector3(0, 0.38, 0.03), red)
			_ball(head, 0.05, Vector3(0, 0.33, 0.07), red)
			_cone(head, 0.05, 0.0, 0.12, Vector3(0, 0.12, -0.2), org, Vector3(-1.5708, 0, 0))          # beak
			_ball(head, 0.04, Vector3(0, 0.03, -0.15), red)                                            # wattle
			_ball(head, 0.022, Vector3(-0.08, 0.2, -0.155), _mat(Color(0.04, 0.03, 0.03)))             # dot eyes
			_ball(head, 0.022, Vector3(0.08, 0.2, -0.155), _mat(Color(0.04, 0.03, 0.03)))
			_ball(spine, 0.34, Vector3(0, 0.2, -0.06), cream, Vector3(1.25, 1.0, 1.0))                 # a big round belly
			for r in range(3):                                                                         # scalloped feathers down the front
				for c in range(3 - (r % 2)):
					var fx := (float(c) - float(2 - (r % 2)) / 2.0) * 0.17
					_ball(spine, 0.07, Vector3(fx, 0.32 - float(r) * 0.12, -0.3 + float(r) * 0.01), down, Vector3(1.2, 0.8, 0.5))
			_box(spine, Vector3(0.16, 0.34, 0.22), Vector3(-0.44, 0.2, 0.0), cream, Vector3(0, 0, 0.35))   # stubby wings
			_box(spine, Vector3(0.16, 0.34, 0.22), Vector3(0.44, 0.2, 0.0), cream, Vector3(0, 0, -0.35))
			for i in range(3):                                                                         # tail feathers
				_cone(hips, 0.06, 0.0, 0.3, Vector3(float(i - 1) * 0.1, 0.12, 0.25), down if i == 1 else cream, Vector3(-0.9, 0, float(i - 1) * 0.3))
		"longhair":
			var hr := _mat(d.hair)
			_box(head, Vector3(0.30, 0.46, 0.07), Vector3(0, 0.03, 0.15), hr)
			_box(head, Vector3(0.05, 0.34, 0.24), Vector3(-0.155, 0.05, 0.03), hr)
			_box(head, Vector3(0.05, 0.34, 0.24), Vector3(0.155, 0.05, 0.03), hr)
		"ponytail":
			var pr := _mat(d.hair)
			_ball(head, 0.07, Vector3(0, 0.22, 0.16), pr)
			_cone(head, 0.06, 0.02, 0.32, Vector3(0, 0.02, 0.2), pr, Vector3(0.3, 0, 0))
			_box(head, Vector3(0.05, 0.03, 0.05), Vector3(0, 0.22, 0.14), _mat(Color(0.9, 0.2, 0.3)))
		"pigtails":
			var tr := _mat(d.hair)
			for sx in [-1.0, 1.0]:
				_ball(head, 0.07, Vector3(sx * 0.18, 0.16, 0.04), tr)
				_cone(head, 0.06, 0.02, 0.26, Vector3(sx * 0.2, 0.0, 0.04), tr, Vector3(0, 0, sx * -0.15))
				_box(head, Vector3(0.07, 0.05, 0.05), Vector3(sx * 0.18, 0.2, 0.03), _mat(Color(0.9, 0.2, 0.35)))
		"bun":
			_ball(head, 0.1, Vector3(0, 0.36, 0.03), _mat(d.hair))
			_box(head, Vector3(0.28, 0.1, 0.1), Vector3(0, 0.03, 0.13), _mat(d.hair))
		"bow":
			var bw := _mat(Color(0.98, 0.35, 0.55))
			_box(head, Vector3(0.07, 0.07, 0.04), Vector3(-0.07, 0.3, 0.0), bw, Vector3(0, 0, 0.5))
			_box(head, Vector3(0.07, 0.07, 0.04), Vector3(0.07, 0.3, 0.0), bw, Vector3(0, 0, -0.5))
			_ball(head, 0.035, Vector3(0, 0.3, 0.0), bw)
		"goggles":
			var gl := _mat(Color(0.2, 0.2, 0.22))
			_box(head, Vector3(0.30, 0.05, 0.31), Vector3(0, 0.25, 0.0), gl)
			_box(head, Vector3(0.09, 0.07, 0.02), Vector3(-0.07, 0.27, -0.16), _mat(Color(0.6, 0.85, 1.0), false, true))
			_box(head, Vector3(0.09, 0.07, 0.02), Vector3(0.07, 0.27, -0.16), _mat(Color(0.6, 0.85, 1.0), false, true))
		"glasses":
			var fr := _mat(Color(0.12, 0.12, 0.16))
			_box(head, Vector3(0.09, 0.07, 0.012), Vector3(-0.06, 0.16, -0.138), fr)
			_box(head, Vector3(0.09, 0.07, 0.012), Vector3(0.06, 0.16, -0.138), fr)
			_box(head, Vector3(0.07, 0.05, 0.016), Vector3(-0.06, 0.16, -0.141), _mat(Color(0.75, 0.9, 1.0, 1.0)))
			_box(head, Vector3(0.07, 0.05, 0.016), Vector3(0.06, 0.16, -0.141), _mat(Color(0.75, 0.9, 1.0, 1.0)))
		"labcoat":
			_box(spine, Vector3(0.54, 0.55, 0.32), Vector3(0, 0.1, 0.0), _mat(Color(0.97, 0.97, 0.99)))
			_box(spine, Vector3(0.1, 0.56, 0.02), Vector3(0, 0.1, -0.165), _mat(Color(0.8, 0.82, 0.88)))
		"witchhat":
			var wh := _mat(Color(0.12, 0.07, 0.18))
			_cone(head, 0.30, 0.30, 0.03, Vector3(0, 0.3, 0), wh)
			_cone(head, 0.17, 0.0, 0.38, Vector3(0, 0.5, 0), wh)
			_box(head, Vector3(0.32, 0.05, 0.32), Vector3(0, 0.33, 0), _mat(Color(0.85, 0.7, 0.2)))
		"skirt":
			_cone(hips, 0.36, 0.22, 0.34, Vector3(0, -0.12, 0), _mat(d.get("skirt", d.vest)))
		"tiara":
			var gd := _mat(Color(0.98, 0.85, 0.25), true)
			_box(head, Vector3(0.24, 0.04, 0.2), Vector3(0, 0.3, -0.03), gd)
			for i in range(3):
				_cone(head, 0.03, 0.0, 0.08, Vector3(-0.07 + i * 0.07, 0.35, -0.03), gd)
			_ball(head, 0.025, Vector3(0, 0.34, -0.12), _mat(Color(0.9, 0.2, 0.5), false, true))
		"bunnyears":
			var bn := _mat(Color(0.98, 0.78, 0.86))
			var inner := _mat(Color(1.0, 0.55, 0.7))
			for sx in [-1.0, 1.0]:
				_ball(head, 0.06, Vector3(sx * 0.08, 0.5, 0.0), bn, Vector3(0.75, 2.4, 0.5))
				_ball(head, 0.035, Vector3(sx * 0.08, 0.5, -0.02), inner, Vector3(0.6, 2.0, 0.4))
			_box(head, Vector3(0.30, 0.1, 0.3), Vector3(0, 0.28, 0.0), bn)
		"braids":
			var br := _mat(d.hair)
			for sx in [-1.0, 1.0]:
				for i in range(4):
					_ball(head, 0.055, Vector3(sx * 0.16, 0.08 - float(i) * 0.09, -0.02 + float(i) * 0.02), br)
				_box(head, Vector3(0.05, 0.04, 0.05), Vector3(sx * 0.16, -0.28, 0.0), _mat(Color(0.8, 0.2, 0.3)))
		"pinkplume":
			_box(head, Vector3(0.05, 0.16, 0.28), Vector3(0, 0.38, 0.02), _mat(Color(0.95, 0.35, 0.55)))
		"fishhead":
			var fm := _mat(Color(0.45, 0.62, 0.72))
			_ball(head, 0.20, Vector3(0, 0.15, -0.02), fm, Vector3(0.9, 1.0, 1.15))
			_ball(head, 0.055, Vector3(-0.13, 0.20, -0.1), _mat(Color(1, 1, 1)))
			_ball(head, 0.055, Vector3(0.13, 0.20, -0.1), _mat(Color(1, 1, 1)))
			_ball(head, 0.025, Vector3(-0.14, 0.20, -0.145), _mat(Color(0.02, 0.02, 0.04)))
			_ball(head, 0.025, Vector3(0.14, 0.20, -0.145), _mat(Color(0.02, 0.02, 0.04)))
			_box(head, Vector3(0.18, 0.025, 0.03), Vector3(0, 0.06, -0.2), _mat(Color(0.25, 0.1, 0.1)))
			_cone(head, 0.07, 0.0, 0.2, Vector3(0, 0.38, 0.02), _mat(Color(0.30, 0.50, 0.65)))
		"marinehelm":
			var gm := _mat(Color(0.30, 0.44, 0.22), true)
			_box(head, Vector3(0.33, 0.35, 0.33), Vector3(0, 0.15, 0), gm)
			_box(head, Vector3(0.25, 0.13, 0.03), Vector3(0, 0.16, -0.17), _mat(Color(0.95, 0.72, 0.15), true))     # gold visor
			_box(head, Vector3(0.1, 0.06, 0.05), Vector3(0, 0.02, -0.16), _mat(Color(0.5, 0.52, 0.55), true))      # mouthpiece
			_box(spine, Vector3(0.22, 0.2, 0.34), Vector3(-0.36, 0.42, 0), gm)                                      # shoulder pads
			_box(spine, Vector3(0.22, 0.2, 0.34), Vector3(0.36, 0.42, 0), gm)
		"emblem":
			var glow := _mat(Color(0.30, 0.95, 0.35), false, true)
			_box(spine, Vector3(0.09, 0.09, 0.02), Vector3(-0.045, 0.30, -0.15), glow, Vector3(0, 0, 0.78))       # an hourglass: two diamonds
			_box(spine, Vector3(0.09, 0.09, 0.02), Vector3(0.045, 0.20, -0.15), glow, Vector3(0, 0, 0.78))
			_box(spine, Vector3(0.28, 0.025, 0.02), Vector3(0, 0.25, -0.15), glow)
		"pumpkinhead":
			var om := _mat(Color(0.95, 0.50, 0.10))
			_ball(head, 0.21, Vector3(0, 0.15, 0), om, Vector3(1.1, 0.95, 1.1))
			_cone(head, 0.03, 0.04, 0.1, Vector3(0, 0.37, 0), _mat(Color(0.30, 0.55, 0.15)))
			var cut := _mat(Color(0.15, 0.08, 0.02), false, true)
			cut.emission = Color(1.0, 0.7, 0.1)
			_box(head, Vector3(0.07, 0.07, 0.03), Vector3(-0.07, 0.18, -0.2), cut, Vector3(0, 0, 0.5))
			_box(head, Vector3(0.07, 0.07, 0.03), Vector3(0.07, 0.18, -0.2), cut, Vector3(0, 0, -0.5))
			_box(head, Vector3(0.16, 0.05, 0.03), Vector3(0, 0.07, -0.2), cut)
		"sharkhood":
			var sg := _mat(Color(0.45, 0.55, 0.65))
			_ball(head, 0.17, Vector3(0, 0.27, 0.01), sg, Vector3(1.0, 0.75, 1.05))
			_cone(head, 0.06, 0.0, 0.2, Vector3(0, 0.44, 0.02), sg)                                                    # dorsal fin
			for i in range(4):
				_cone(head, 0.02, 0.0, 0.05, Vector3(-0.075 + i * 0.05, 0.215, -0.16), _mat(Color(1, 1, 1)), Vector3(3.14159, 0, 0))   # teeth
		"pandaears":
			var bk := _mat(Color(0.08, 0.08, 0.1))
			_ball(head, 0.06, Vector3(-0.11, 0.3, 0), bk)
			_ball(head, 0.06, Vector3(0.11, 0.3, 0), bk)
			_box(head, Vector3(0.07, 0.06, 0.012), Vector3(-0.06, 0.16, -0.136), bk)                                    # eye patches
			_box(head, Vector3(0.07, 0.06, 0.012), Vector3(0.06, 0.16, -0.136), bk)
		"vikinghelm":
			var hm := _mat(Color(0.55, 0.57, 0.62), true)
			_cone(head, 0.17, 0.17, 0.12, Vector3(0, 0.27, 0), hm)
			_ball(head, 0.16, Vector3(0, 0.3, 0), hm, Vector3(1, 0.7, 1))
			var horn := _mat(Color(0.95, 0.92, 0.80))
			_cone(head, 0.04, 0.0, 0.2, Vector3(-0.21, 0.34, 0), horn, Vector3(0, 0, 0.7))
			_cone(head, 0.04, 0.0, 0.2, Vector3(0.21, 0.34, 0), horn, Vector3(0, 0, -0.7))
		"beard":
			_box(head, Vector3(0.20, 0.12, 0.05), Vector3(0, 0.0, -0.135), _mat(d.hair))
			_box(head, Vector3(0.05, 0.18, 0.05), Vector3(-0.1, 0.02, -0.125), _mat(d.hair))
			_box(head, Vector3(0.05, 0.18, 0.05), Vector3(0.1, 0.02, -0.125), _mat(d.hair))
		"chefhat":
			var wh := _mat(Color(0.97, 0.97, 0.98))
			_cone(head, 0.15, 0.15, 0.1, Vector3(0, 0.3, 0), wh)
			_ball(head, 0.17, Vector3(0, 0.45, 0), wh, Vector3(1.0, 0.9, 1.0))
		"flower":
			_ball(head, 0.07, Vector3(0.05, 0.31, 0), _mat(Color(0.95, 0.55, 0.65)))
			_ball(head, 0.03, Vector3(0.05, 0.36, 0), _mat(Color(1.0, 0.85, 0.2)))
		"tail":
			_box(hips, Vector3(0.1, 0.1, 0.4), Vector3(0, 0.0, 0.3), _mat(d.vest), Vector3(-0.3, 0, 0))
			_box(hips, Vector3(0.06, 0.06, 0.3), Vector3(0, -0.1, 0.58), _mat(d.vest), Vector3(-0.5, 0, 0))

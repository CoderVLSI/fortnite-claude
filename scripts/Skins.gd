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
		"glove": Color(0.22, 0.14, 0.08), "pack": Color(0.35, 0.22, 0.10), "acc": ["tricorn", "eyepatch"]},
	"cowboy": {"name": "Dusty Rider", "desc": "Yeehaw, partner", "skin": Color(0.82, 0.55, 0.38), "vest": Color(0.52, 0.34, 0.18),
		"pants": Color(0.22, 0.30, 0.50), "boots": Color(0.30, 0.18, 0.09), "hair": Color(0.30, 0.20, 0.10),
		"glove": Color(0.35, 0.22, 0.12), "pack": Color(0.40, 0.26, 0.14), "acc": ["cowboyhat", "bandana"]},
	"dino": {"name": "Rex Hoodie", "desc": "Rawr (it means eliminate)", "skin": Color(0.35, 0.72, 0.30), "vest": Color(0.30, 0.62, 0.26),
		"pants": Color(0.27, 0.52, 0.22), "boots": Color(0.22, 0.40, 0.18), "hair": Color(0.30, 0.62, 0.26),
		"glove": Color(0.27, 0.52, 0.22), "pack": Color(0.95, 0.55, 0.15), "acc": ["spikes", "tail"]},
}
const ORDER := ["ranger", "ninja", "astronaut", "knight", "robot", "pirate", "cowboy", "dino"]


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
	var metal: bool = d.get("metal", false)
	var vest: Color = vest_override if (vest_override != null and id == "ranger") else d.vest
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
	_box(head, Vector3(0.045, 0.06, 0.05), Vector3(0, 0.115, -0.152), nose_mat)                 # nose
	_box(head, Vector3(0.09, 0.014, 0.012), Vector3(0, 0.05, -0.134), mouth_mat)                 # mouth
	var moustache: bool = id == "pirate" or id == "cowboy"
	if id == "ranger" and vest_override != null:
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
		"tail":
			_box(hips, Vector3(0.1, 0.1, 0.4), Vector3(0, 0.0, 0.3), _mat(d.vest), Vector3(-0.3, 0, 0))
			_box(hips, Vector3(0.06, 0.06, 0.3), Vector3(0, -0.1, 0.58), _mat(d.vest), Vector3(-0.5, 0, 0))

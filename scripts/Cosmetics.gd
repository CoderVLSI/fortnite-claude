extends Reference
# The Locker: everything a player can wear or carry into a match, picked in the lobby.
#   skin       the whole outfit (Skins.gd)           pickaxe    the harvesting tool in hand
#   backbling  what rides on your back                contrail   the trail you leave in the sky
#   glider     what you open after the freefall
# All the models are built here from primitives. Pickaxes use the hand frame (handle along -Z, head spreading up / down);
# gliders use the pilot frame (origin at the feet, facing -Z, canopy overhead).

const Skins = preload("res://scripts/Skins.gd")

const CATEGORIES := ["skin", "pickaxe", "backbling", "contrail", "glider"]
const TITLES := {"skin": "SKIN", "pickaxe": "PICKAXE", "backbling": "BACK BLING", "contrail": "CONTRAIL", "glider": "GLIDER"}

const PICKAXES := {
	"classic": {"name": "Field Pickaxe", "rarity": 0, "desc": "Reliable as ever"},
	"candy": {"name": "Candy Cane", "rarity": 1, "desc": "Sweet, sticky and sharp"},
	"battleaxe": {"name": "Battle Axe", "rarity": 2, "desc": "A great steel blade"},
	"starwand": {"name": "Star Wand", "rarity": 3, "desc": "Sparkles with every swing"},
	"scythe": {"name": "Crystal Scythe", "rarity": 4, "desc": "A curved blade of glowing crystal"},
	"energy": {"name": "Energy Sword", "rarity": 5, "desc": "Hums with a cyan beam"},
}
const BACKBLINGS := {
	"none": {"name": "Nothing", "rarity": 0, "desc": "A clean back"},
	"cape": {"name": "Hero Cape", "rarity": 1, "desc": "Flutter dramatically"},
	"teddy": {"name": "Teddy Buddy", "rarity": 2, "desc": "A cuddly friend along for the ride"},
	"rocket": {"name": "Mini Rocket", "rarity": 2, "desc": "Strapped on, never lit"},
	"shell": {"name": "Turtle Shell", "rarity": 3, "desc": "Safe and slow"},
	"wings": {"name": "Angel Wings", "rarity": 4, "desc": "Feathered and shining"},
	"dragonwings": {"name": "Dragon Wings", "rarity": 5, "desc": "Leathery, spiked and fierce"},
}
const CONTRAILS := {
	"none": {"name": "No Trail", "rarity": 0, "desc": "Leave nothing behind"},
	"smoke": {"name": "Smoke", "rarity": 1, "desc": "A grey puff behind you"},
	"bubbles": {"name": "Bubbles", "rarity": 2, "desc": "Floating soap bubbles"},
	"stars": {"name": "Stardust", "rarity": 3, "desc": "A trail of tiny stars"},
	"flame": {"name": "Flame", "rarity": 4, "desc": "Burns the whole way down"},
	"rainbow": {"name": "Rainbow", "rarity": 5, "desc": "Every colour at once"},
}
const GLIDERS := {
	"classic": {"name": "Classic Glider", "rarity": 0, "desc": "The standard orange canopy"},
	"umbrella": {"name": "Umbrella", "rarity": 1, "desc": "Mary would approve"},
	"hang": {"name": "Hang Glider", "rarity": 2, "desc": "A delta wing"},
	"carpet": {"name": "Magic Carpet", "rarity": 3, "desc": "Ride it standing up"},
	"ufo": {"name": "Flying Saucer", "rarity": 4, "desc": "Not from around here"},
	"dragon": {"name": "Dragon", "rarity": 5, "desc": "A real dragon carries you down"},
}

const DEFAULT_LOADOUT := {"skin": "ranger", "pickaxe": "classic", "backbling": "none", "contrail": "none", "glider": "classic"}


static func table(cat: String) -> Dictionary:
	match cat:
		"skin":
			var t := {}
			var rar := {"ranger": 0, "cowboy": 1, "pirate": 2, "ninja": 3, "astronaut": 3, "knight": 4, "dino": 4, "robot": 5}
			for id in Skins.ORDER:
				t[id] = {"name": Skins.LIST[id].name, "rarity": rar.get(id, 1), "desc": Skins.LIST[id].desc}
			return t
		"pickaxe":
			return PICKAXES
		"backbling":
			return BACKBLINGS
		"contrail":
			return CONTRAILS
	return GLIDERS


static func order(cat: String) -> Array:
	return Skins.ORDER if cat == "skin" else table(cat).keys()


static func rarity_color(rarity: int) -> Color:
	return preload("res://scripts/Items.gd").RARITIES[rarity].color


# Fill in anything missing from a saved loadout.
static func sanitize(d: Dictionary) -> Dictionary:
	var out := DEFAULT_LOADOUT.duplicate()
	for c in CATEGORIES:
		if d.has(c) and table(c).has(d[c]):
			out[c] = d[c]
	return out


# ------------------------------------------------------------------ small mesh helpers

static func _mat(c: Color, emissive: float = 0.0, metal: float = 0.0, alpha: float = 1.0) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = 0.6
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy = emissive
	if alpha < 1.0:
		m.flags_transparent = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	return m


static func _box(p: Spatial, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance:
	var mi := MeshInstance.new()
	var m := CubeMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.translation = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


static func _ball(p: Spatial, r: float, pos: Vector3, mat: Material, squash: Vector3 = Vector3.ONE) -> MeshInstance:
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
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


static func _cyl(p: Spatial, r_bottom: float, r_top: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, seg: int = 12) -> MeshInstance:
	var mi := MeshInstance.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r_bottom
	m.top_radius = r_top
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	mi.translation = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


# A flat triangle fan (double sided) from points, for wings and sails.
static func _poly(p: Spatial, pts: Array, mat: Material) -> MeshInstance:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size() - 1):
		st.add_vertex(pts[0])
		st.add_vertex(pts[i])
		st.add_vertex(pts[i + 1])
	st.generate_normals()
	var mi := MeshInstance.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


# ------------------------------------------------------------------ pickaxes (null = the classic glb)

static func build_pickaxe(id: String):
	if id == "classic" or not PICKAXES.has(id):
		return null
	var root := Spatial.new()
	var wood := _mat(Color(0.42, 0.26, 0.12))
	var steel := _mat(Color(0.72, 0.74, 0.80), 0.0, 0.7)
	match id:
		"candy":
			var red := _mat(Color(0.9, 0.1, 0.15))
			var white := _mat(Color(0.97, 0.97, 0.97))
			for i in range(8):                                    # striped shaft
				_box(root, Vector3(0.05, 0.05, 0.1), Vector3(0, 0, 0.05 - i * 0.1), red if i % 2 == 0 else white)
			for i in range(5):                                    # the hooked top bends over
				var a := float(i) / 4.0 * PI * 0.9
				_box(root, Vector3(0.05, 0.05, 0.1), Vector3(0, sin(a) * 0.2, -0.8 - cos(a) * 0.2 + 0.2 + 0.0), red if i % 2 == 0 else white, Vector3(a, 0, 0))
		"battleaxe":
			_box(root, Vector3(0.045, 0.045, 0.95), Vector3(0, 0, -0.36), wood)
			_box(root, Vector3(0.05, 0.1, 0.1), Vector3(0, 0, -0.8), _mat(Color(0.2, 0.2, 0.24)))
			_box(root, Vector3(0.03, 0.34, 0.26), Vector3(0, 0.2, -0.82), steel)                  # the blade
			_box(root, Vector3(0.025, 0.12, 0.34), Vector3(0, 0.37, -0.82), steel, Vector3(0.3, 0, 0))
			_box(root, Vector3(0.03, 0.1, 0.12), Vector3(0, -0.1, -0.8), steel)
		"starwand":
			_box(root, Vector3(0.03, 0.03, 0.85), Vector3(0, 0, -0.3), _mat(Color(0.95, 0.75, 0.2), 0.3, 0.5))
			var star := _mat(Color(1.0, 0.9, 0.3), 1.8)
			var sp := Spatial.new()
			sp.translation = Vector3(0, 0, -0.8)
			root.add_child(sp)
			for i in range(5):                                     # a five-pointed star from five spikes
				var ang := float(i) / 5.0 * TAU
				_box(sp, Vector3(0.025, 0.2, 0.05), Vector3(0, cos(ang) * 0.1, sin(ang) * 0.1), star, Vector3(ang, 0, 0))
			_ball(sp, 0.07, Vector3.ZERO, star)
		"scythe":
			_box(root, Vector3(0.04, 0.04, 1.0), Vector3(0, 0, -0.4), _mat(Color(0.2, 0.15, 0.25)))
			var crystal := _mat(Color(0.35, 0.95, 1.0), 1.3, 0.2, 0.92)
			for i in range(6):                                     # a long curved blade
				var a := float(i) / 5.0
				_box(root, Vector3(0.02, 0.07 - a * 0.04, 0.17), Vector3(0, 0.1 + a * 0.16 - a * a * 0.0, -0.9 - a * 0.28 + a * a * 0.12), crystal, Vector3(-0.35 - a * 0.7, 0, 0))
		"energy":
			_box(root, Vector3(0.05, 0.05, 0.28), Vector3(0, 0, -0.04), _mat(Color(0.18, 0.18, 0.22), 0.0, 0.8))
			_box(root, Vector3(0.05, 0.16, 0.04), Vector3(0, 0, -0.2), _mat(Color(0.18, 0.18, 0.22), 0.0, 0.8))
			_box(root, Vector3(0.035, 0.035, 0.95), Vector3(0, 0, -0.7), _mat(Color(0.5, 1.0, 1.0), 2.2))
			var glow := OmniLight.new()
			glow.light_color = Color(0.4, 0.95, 1.0)
			glow.light_energy = 0.8
			glow.omni_range = 3.0
			glow.translation = Vector3(0, 0, -0.6)
			root.add_child(glow)
	return root


# ------------------------------------------------------------------ back bling (Spine joint frame: chest 0.24 up, back = +Z)

static func build_backbling(id: String):
	if id == "none" or not BACKBLINGS.has(id):
		return null
	var root := Spatial.new()
	match id:
		"cape":
			var red := _mat(Color(0.75, 0.1, 0.12))
			_box(root, Vector3(0.5, 0.1, 0.05), Vector3(0, 0.45, 0.2), red)
			_box(root, Vector3(0.52, 0.7, 0.04), Vector3(0, 0.05, 0.24), red, Vector3(0.12, 0, 0))
			_box(root, Vector3(0.6, 0.45, 0.04), Vector3(0, -0.55, 0.42), red, Vector3(0.3, 0, 0))
		"teddy":
			var fur := _mat(Color(0.65, 0.42, 0.22))
			var light := _mat(Color(0.85, 0.7, 0.5))
			_ball(root, 0.2, Vector3(0, 0.15, 0.36), fur, Vector3(1, 1.1, 0.8))
			_ball(root, 0.14, Vector3(0, 0.42, 0.36), fur)
			_ball(root, 0.05, Vector3(-0.1, 0.55, 0.35), fur)
			_ball(root, 0.05, Vector3(0.1, 0.55, 0.35), fur)
			_ball(root, 0.06, Vector3(0, 0.4, 0.46), light)
			_ball(root, 0.035, Vector3(-0.05, 0.45, 0.47), _mat(Color(0.05, 0.05, 0.05)))
			_ball(root, 0.035, Vector3(0.05, 0.45, 0.47), _mat(Color(0.05, 0.05, 0.05)))
			_ball(root, 0.07, Vector3(-0.2, 0.2, 0.42), fur)
			_ball(root, 0.07, Vector3(0.2, 0.2, 0.42), fur)
		"rocket":
			var body := _mat(Color(0.92, 0.92, 0.95))
			_cyl(root, 0.1, 0.1, 0.6, Vector3(0, 0.2, 0.28), body)
			_cyl(root, 0.1, 0.0, 0.22, Vector3(0, 0.62, 0.28), _mat(Color(0.9, 0.15, 0.15)))
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.02, 0.2, 0.16), Vector3(sx * 0.13, -0.02, 0.28), _mat(Color(0.9, 0.15, 0.15)))
			_box(root, Vector3(0.16, 0.02, 0.2), Vector3(0, -0.02, 0.28), _mat(Color(0.9, 0.15, 0.15)))
			_cyl(root, 0.06, 0.04, 0.08, Vector3(0, -0.14, 0.28), _mat(Color(0.3, 0.3, 0.33), 0.0, 0.6))
		"shell":
			var green := _mat(Color(0.3, 0.55, 0.25))
			_ball(root, 0.32, Vector3(0, 0.22, 0.3), green, Vector3(1.05, 1.0, 0.55))
			var rim := _mat(Color(0.8, 0.7, 0.4))
			for i in range(3):
				_box(root, Vector3(0.12, 0.12, 0.05), Vector3(-0.14 + i * 0.14, 0.3 + (0.05 if i == 1 else 0.0), 0.5 - 0.0), rim)
			_box(root, Vector3(0.12, 0.12, 0.05), Vector3(0, 0.14, 0.5), rim)
		"wings":
			var feather := _mat(Color(0.98, 0.98, 1.0), 0.25)
			for sx in [-1.0, 1.0]:
				for i in range(5):
					_box(root, Vector3(0.5 - i * 0.05, 0.07, 0.025), Vector3(sx * (0.35 + i * 0.07), 0.55 - i * 0.14, 0.26 + i * 0.012), feather, Vector3(0, 0, sx * (0.6 - i * 0.12)))
		"dragonwings":
			var membrane := _mat(Color(0.65, 0.1, 0.12), 0.0, 0.0, 0.95)
			var bone := _mat(Color(0.25, 0.05, 0.07))
			for sx in [-1.0, 1.0]:
				_poly(root, [Vector3(sx * 0.1, 0.45, 0.24), Vector3(sx * 0.9, 0.85, 0.3), Vector3(sx * 1.0, 0.1, 0.32), Vector3(sx * 0.55, -0.2, 0.28), Vector3(sx * 0.1, 0.0, 0.24)], membrane)
				_box(root, Vector3(0.9, 0.04, 0.04), Vector3(sx * 0.5, 0.65, 0.27), bone, Vector3(0, 0, sx * 0.45))
				_box(root, Vector3(1.0, 0.03, 0.03), Vector3(sx * 0.55, 0.25, 0.3), bone, Vector3(0, 0, sx * -0.12))
				_cyl(root, 0.025, 0.0, 0.16, Vector3(sx * 0.92, 0.9, 0.3), bone, Vector3(0, 0, sx * -0.4), 6)
	return root


# ------------------------------------------------------------------ gliders (origin at the pilot's feet, facing -Z)

static func build_glider(id: String):
	if id == "classic" or not GLIDERS.has(id):
		return null
	var root := Spatial.new()
	var rope := _mat(Color(0.2, 0.2, 0.22))
	match id:
		"umbrella":
			var cols := [Color(0.9, 0.15, 0.2), Color(0.98, 0.85, 0.2)]
			for i in range(2):                                    # two cone layers = stripes
				_cyl(root, 1.8 - i * 0.9, 0.0, 0.85 - i * 0.1, Vector3(0, 2.5 + i * 0.12, 0), _mat(cols[i]), Vector3.ZERO, 16)
			_cyl(root, 0.025, 0.025, 1.3, Vector3(0, 2.0, 0), _mat(Color(0.25, 0.15, 0.08)))
			_ball(root, 0.06, Vector3(0, 3.0, 0), _mat(Color(0.9, 0.8, 0.3), 0.3, 0.6))
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.015, 1.2, 0.015), Vector3(sx * 0.35, 1.9, 0), rope, Vector3(0, 0, sx * 0.25))
		"hang":
			var sail := _mat(Color(0.2, 0.7, 0.95))
			_poly(root, [Vector3(0, 2.7, -1.5), Vector3(-2.4, 2.45, 0.9), Vector3(0, 2.6, 0.45), Vector3(2.4, 2.45, 0.9)], sail)
			_box(root, Vector3(0.05, 0.05, 2.1), Vector3(0, 2.6, -0.2), _mat(Color(0.8, 0.8, 0.85), 0.0, 0.6))
			_box(root, Vector3(4.6, 0.04, 0.04), Vector3(0, 2.45, 0.85), _mat(Color(0.8, 0.8, 0.85), 0.0, 0.6))
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.02, 1.2, 0.02), Vector3(sx * 0.35, 1.95, 0), rope, Vector3(0, 0, sx * 0.3))
		"carpet":
			var weave := _mat(Color(0.65, 0.12, 0.5))
			_box(root, Vector3(1.6, 0.06, 2.2), Vector3(0, -0.05, 0), weave)
			_box(root, Vector3(1.4, 0.07, 0.12), Vector3(0, -0.04, -0.85), _mat(Color(0.95, 0.8, 0.25)))
			_box(root, Vector3(1.4, 0.07, 0.12), Vector3(0, -0.04, 0.85), _mat(Color(0.95, 0.8, 0.25)))
			for i in range(7):
				for sz in [-1.0, 1.0]:
					_box(root, Vector3(0.04, 0.04, 0.18), Vector3(-0.68 + i * 0.227, -0.05, sz * 1.18), _mat(Color(0.95, 0.8, 0.25)))
		"ufo":
			var hull := _mat(Color(0.7, 0.72, 0.8), 0.0, 0.7)
			_cyl(root, 2.0, 1.2, 0.35, Vector3(0, 2.55, 0), hull, Vector3.ZERO, 20)
			_cyl(root, 1.2, 0.5, 0.3, Vector3(0, 2.8, 0), hull, Vector3.ZERO, 20)
			_ball(root, 0.6, Vector3(0, 3.0, 0), _mat(Color(0.5, 0.95, 0.9), 0.6, 0.0, 0.55), Vector3(1, 0.8, 1))
			for i in range(8):
				var a := float(i) / 8.0 * TAU
				_ball(root, 0.07, Vector3(cos(a) * 1.7, 2.44, sin(a) * 1.7), _mat(Color(1.0, 0.9, 0.3), 2.0))
			var beam := _cyl(root, 0.7, 1.1, 1.8, Vector3(0, 1.5, 0), _mat(Color(0.6, 1.0, 0.8), 1.0, 0.0, 0.18), Vector3.ZERO, 16)
			beam.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		"dragon":
			var scale_c := _mat(Color(0.75, 0.15, 0.12))
			var belly := _mat(Color(0.95, 0.75, 0.3))
			var membrane := _mat(Color(0.55, 0.08, 0.1), 0.0, 0.0, 0.95)
			var bone := _mat(Color(0.25, 0.05, 0.07))
			_box(root, Vector3(0.7, 0.55, 1.7), Vector3(0, 2.55, 0.1), scale_c)                   # body
			_box(root, Vector3(0.6, 0.15, 1.5), Vector3(0, 2.3, 0.1), belly)
			_box(root, Vector3(0.4, 0.4, 0.6), Vector3(0, 2.72, -1.1), scale_c, Vector3(-0.3, 0, 0))   # neck
			_box(root, Vector3(0.5, 0.4, 0.7), Vector3(0, 2.95, -1.55), scale_c)                  # head
			_box(root, Vector3(0.36, 0.2, 0.4), Vector3(0, 2.88, -2.05), scale_c)                 # snout
			for sx in [-1.0, 1.0]:
				_cyl(root, 0.05, 0.0, 0.3, Vector3(sx * 0.18, 3.25, -1.4), bone, Vector3(0.4, 0, sx * 0.2), 6)   # horns
				_ball(root, 0.06, Vector3(sx * 0.22, 3.02, -1.85), _mat(Color(1.0, 0.85, 0.2), 2.0))               # eyes
				_poly(root, [Vector3(sx * 0.3, 2.8, -0.2), Vector3(sx * 2.8, 3.3, -0.4), Vector3(sx * 3.1, 2.55, 0.5), Vector3(sx * 2.0, 2.3, 0.9), Vector3(sx * 0.3, 2.35, 0.7)], membrane)
				_box(root, Vector3(2.7, 0.07, 0.07), Vector3(sx * 1.6, 3.05, -0.3), bone, Vector3(0, 0, sx * 0.24))
				_box(root, Vector3(2.9, 0.05, 0.05), Vector3(sx * 1.7, 2.55, 0.5), bone, Vector3(0, 0, sx * -0.12))
				_box(root, Vector3(0.1, 0.5, 0.1), Vector3(sx * 0.3, 2.0, -0.3), scale_c)       # legs holding the pilot
			for i in range(4):                                                                  # a spiked tail
				_box(root, Vector3(0.4 - i * 0.08, 0.3 - i * 0.05, 0.6), Vector3(0, 2.55 - i * 0.05, 1.2 + i * 0.5), scale_c)
			_cyl(root, 0.1, 0.0, 0.25, Vector3(0, 2.5, 3.25), bone, Vector3(PI / 2.0, 0, 0), 6)
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.015, 1.1, 0.015), Vector3(sx * 0.3, 1.5, 0.0), rope)
	return root


# ------------------------------------------------------------------ contrails

static func build_contrail(id: String):
	if id == "none" or not CONTRAILS.has(id):
		return null
	var p := CPUParticles.new()
	p.gravity = Vector3.ZERO
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.vertex_color_use_as_albedo = true
	var mesh: Mesh
	var amount := 70
	var life := 1.6
	var size := 0.18
	var cols := []
	var offs := []
	match id:
		"smoke":
			mesh = SphereMesh.new()
			mat.albedo_color = Color(0.85, 0.85, 0.88, 0.7)
			cols = [Color(0.9, 0.9, 0.92, 0.8), Color(0.5, 0.5, 0.55, 0.0)]
			size = 0.32
			life = 2.2
		"bubbles":
			mesh = SphereMesh.new()
			mat.albedo_color = Color(0.7, 0.9, 1.0, 0.55)
			cols = [Color(0.75, 0.95, 1.0, 0.7), Color(0.9, 0.7, 1.0, 0.0)]
			size = 0.25
			p.gravity = Vector3(0, 0.6, 0)
		"stars":
			mesh = CubeMesh.new()
			cols = [Color(1.0, 0.95, 0.4, 1.0), Color(1.0, 0.5, 0.9, 0.0)]
			size = 0.16
			p.angle = 360.0
			p.angle_random = 1.0
			amount = 90
		"flame":
			mesh = SphereMesh.new()
			cols = [Color(1.0, 0.95, 0.4, 1.0), Color(1.0, 0.35, 0.05, 0.6), Color(0.3, 0.05, 0.0, 0.0)]
			offs = [0.0, 0.45, 1.0]
			size = 0.2
			life = 1.0
			amount = 80
		"rainbow":
			mesh = SphereMesh.new()
			cols = [Color(1, 0.2, 0.2), Color(1, 0.8, 0.2), Color(0.3, 1, 0.3), Color(0.2, 0.7, 1), Color(0.7, 0.3, 1, 0.0)]
			offs = [0.0, 0.25, 0.5, 0.75, 1.0]
			size = 0.28
			amount = 100
	if mesh is SphereMesh:
		mesh.radius = size / 2.0
		mesh.height = size
		mesh.radial_segments = 6
		mesh.rings = 3
	elif mesh is CubeMesh:
		mesh.size = Vector3(size, size, size * 0.2)
	mesh.material = mat
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 12.0
	p.initial_velocity = 0.6
	p.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	if offs.empty():
		for i in range(cols.size()):
			offs.append(float(i) / float(max(cols.size() - 1, 1)))
	var ramp := Gradient.new()
	ramp.offsets = PoolRealArray(offs)
	ramp.colors = PoolColorArray(cols)
	p.color_ramp = ramp
	p.scale_amount = 1.0
	p.scale_amount_random = 0.4
	p.emitting = false
	return p

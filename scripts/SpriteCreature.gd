extends Reference
# The look of a Sprite: a glowing little ghost with a face and stubby arms, tinted by its element.
# build() returns a fresh Spatial (faces -Z, about 0.8 m tall at scale 1).

const Sprites = preload("res://scripts/Sprites.gd")


static func _sphere(r: float, mat: Material, pos: Vector3, squash: Vector3 = Vector3.ONE) -> MeshInstance:
	var mi := MeshInstance.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 7
	mi.mesh = m
	mi.material_override = mat
	mi.translation = pos
	mi.scale = squash
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	return mi


static func build_for(id: String, variant: String = "", size: float = 1.0) -> Spatial:
	var root := build(Sprites.color(id, variant), size)
	var acc := Spatial.new()
	root.add_child(acc)
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	match id:
		"king":       # a little gold crown
			mat.albedo_color = Color(1.0, 0.82, 0.2)
			for i in range(3):
				var b := MeshInstance.new()
				var cm := CubeMesh.new()
				cm.size = Vector3(0.1, 0.16 if i == 1 else 0.11, 0.1)
				b.mesh = cm
				b.material_override = mat
				b.translation = Vector3(-0.14 + i * 0.14, 0.82 + (0.03 if i == 1 else 0.0), 0)
				acc.add_child(b)
		"demon":      # two horns
			mat.albedo_color = Color(0.25, 0.04, 0.08)
			for sx in [-1.0, 1.0]:
				var h := MeshInstance.new()
				var hm := CylinderMesh.new()
				hm.top_radius = 0.0
				hm.bottom_radius = 0.06
				hm.height = 0.2
				hm.radial_segments = 6
				h.mesh = hm
				h.material_override = mat
				h.translation = Vector3(0.17 * sx, 0.8, -0.02)
				h.rotation.z = -0.35 * sx
				acc.add_child(h)
		"duck":       # a bill
			mat.albedo_color = Color(1.0, 0.5, 0.1)
			acc.add_child(_sphere(0.07, mat, Vector3(0, 0.42, -0.3), Vector3(1.6, 0.5, 1.0)))
		"fire":       # a flame tuft
			mat.albedo_color = Color(1.0, 0.45, 0.05)
			var f := MeshInstance.new()
			var fm := CylinderMesh.new()
			fm.top_radius = 0.0
			fm.bottom_radius = 0.1
			fm.height = 0.26
			fm.radial_segments = 6
			f.mesh = fm
			f.material_override = mat
			f.translation = Vector3(0, 0.88, 0)
			acc.add_child(f)
		"punk":       # a mohawk
			mat.albedo_color = Color(0.2, 1.0, 0.5)
			for i in range(3):
				var m := MeshInstance.new()
				var mm := CubeMesh.new()
				mm.size = Vector3(0.05, 0.16, 0.12)
				m.mesh = mm
				m.material_override = mat
				m.translation = Vector3(0, 0.84 - abs(i - 1) * 0.04, -0.1 + i * 0.1)
				acc.add_child(m)
		"aegis":      # a halo ring
			mat.albedo_color = Color(0.5, 1.0, 0.95)
			var ring := MeshInstance.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.2
			cyl.bottom_radius = 0.2
			cyl.height = 0.02
			cyl.radial_segments = 14
			ring.mesh = cyl
			ring.material_override = mat
			ring.translation = Vector3(0, 0.95, 0)
			acc.add_child(ring)
		"lucky":      # a clover-green bow tie
			mat.albedo_color = Color(0.2, 0.8, 0.3)
			acc.add_child(_sphere(0.05, mat, Vector3(-0.07, 0.33, -0.3), Vector3(1.4, 1, 0.6)))
			acc.add_child(_sphere(0.05, mat, Vector3(0.07, 0.33, -0.3), Vector3(1.4, 1, 0.6)))
	return root


static func build(col: Color, size: float = 1.0) -> Spatial:
	var root := Spatial.new()
	var body := SpatialMaterial.new()
	body.albedo_color = col
	body.emission_enabled = true
	body.emission = col
	body.emission_energy = 0.75
	body.flags_do_not_receive_shadows = true
	var dark := SpatialMaterial.new()
	dark.albedo_color = Color(0.08, 0.08, 0.12)
	dark.flags_unshaded = true
	root.add_child(_sphere(0.3, body, Vector3(0, 0.46, 0), Vector3(1, 1.1, 1)))
	var skirt := MeshInstance.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.34
	cyl.height = 0.28
	cyl.radial_segments = 14
	cyl.rings = 1
	skirt.mesh = cyl
	skirt.material_override = body
	skirt.translation = Vector3(0, 0.26, 0)
	skirt.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	root.add_child(skirt)
	for i in range(5):                                      # wavy ghost hem
		var a := float(i) / 5.0 * TAU
		root.add_child(_sphere(0.1, body, Vector3(cos(a) * 0.27, 0.13, sin(a) * 0.27)))
	root.add_child(_sphere(0.05, dark, Vector3(-0.1, 0.52, -0.27), Vector3(1, 1.3, 0.6)))     # eyes
	root.add_child(_sphere(0.05, dark, Vector3(0.1, 0.52, -0.27), Vector3(1, 1.3, 0.6)))
	root.add_child(_sphere(0.04, dark, Vector3(0, 0.40, -0.29), Vector3(1.6, 0.6, 0.5)))      # smile
	root.add_child(_sphere(0.075, body, Vector3(-0.33, 0.34, 0)))                             # arms
	root.add_child(_sphere(0.075, body, Vector3(0.33, 0.34, 0)))
	var glow := OmniLight.new()
	glow.light_color = col
	glow.light_energy = 0.6
	glow.omni_range = 5.0
	glow.translation = Vector3(0, 0.5, 0)
	glow.shadow_enabled = false
	root.add_child(glow)
	root.scale = Vector3(size, size, size)
	return root


# A burst / stream of little glowing dots (fountains, vortices, rift sparks).
static func particles(color: Color, amount: int, life: float, up: float, spread: float, gravity: float, radius: float = 0.3) -> CPUParticles:
	var p := CPUParticles.new()
	var m := SphereMesh.new()
	m.radius = 0.07
	m.height = 0.14
	m.radial_segments = 6
	m.rings = 3
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.albedo_color = color
	m.material = mat
	p.mesh = m
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3(0, 1, 0)
	p.spread = spread
	p.initial_velocity = up
	p.gravity = Vector3(0, -gravity, 0)
	p.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.scale_amount_random = 0.5
	p.emitting = true
	return p

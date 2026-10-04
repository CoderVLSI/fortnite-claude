extends Reference
# Procedural models for the gadget items (no Blender needed): the jetpack and the skateboard.


static func _mat(c: Color, metal: float = 0.0) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.55
	return m


static func _cyl(parent: Spatial, r: float, h: float, mat: Material, pos: Vector3, rot_x: float = 0.0) -> MeshInstance:
	var mi := MeshInstance.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.translation = pos
	mi.rotation.x = rot_x
	parent.add_child(mi)
	return mi


static func _box(parent: Spatial, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance:
	var mi := MeshInstance.new()
	var bm := CubeMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.translation = pos
	parent.add_child(mi)
	return mi


static func _emissive(c: Color) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy = 1.6
	return m


# Two red fuel tanks with gold bands, a dark frame, silver nozzles and a little flame, about 0.7 m tall.
static func jetpack() -> Spatial:
	var root := Spatial.new()
	var body := _mat(Color(0.82, 0.14, 0.14), 0.4)
	var steel := _mat(Color(0.6, 0.62, 0.68), 0.7)
	var gold := _mat(Color(0.95, 0.75, 0.2), 0.6)
	var dark := _mat(Color(0.14, 0.14, 0.17), 0.3)
	var flame := _emissive(Color(1.0, 0.55, 0.1))
	for sx in [-1.0, 1.0]:
		_cyl(root, 0.14, 0.6, body, Vector3(0.17 * sx, 0.35, 0))
		_cyl(root, 0.145, 0.04, gold, Vector3(0.17 * sx, 0.5, 0))
		_cyl(root, 0.145, 0.04, gold, Vector3(0.17 * sx, 0.22, 0))
		_cyl(root, 0.09, 0.12, steel, Vector3(0.17 * sx, 0.02, 0))
		_cyl(root, 0.06, 0.1, steel, Vector3(0.17 * sx, 0.68, 0))
		var f := MeshInstance.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.0
		cm.height = 0.2
		cm.radial_segments = 8
		cm.rings = 1
		f.mesh = cm
		f.material_override = flame
		f.translation = Vector3(0.17 * sx, -0.14, 0)
		root.add_child(f)
	_box(root, Vector3(0.4, 0.1, 0.12), dark, Vector3(0, 0.45, 0.1))
	_box(root, Vector3(0.4, 0.08, 0.12), dark, Vector3(0, 0.2, 0.1))
	return root


# A cyan deck with kicked-up ends, a yellow lightning bolt and four yellow wheels, 0.8 m long.
static func skateboard() -> Spatial:
	var root := Spatial.new()
	var deck := _mat(Color(0.2, 0.75, 0.98))
	var bolt := _mat(Color(1.0, 0.95, 0.5))
	var wheel := _mat(Color(0.95, 0.85, 0.2))
	var truck := _mat(Color(0.7, 0.72, 0.78), 0.6)
	_box(root, Vector3(0.28, 0.04, 0.6), deck, Vector3(0, 0.1, 0))
	for sz in [-1.0, 1.0]:                                           # the kicked-up nose and tail
		var kick := _box(root, Vector3(0.28, 0.04, 0.16), deck, Vector3(0, 0.125, 0.36 * sz))
		kick.rotation.x = 0.35 * sz
	_box(root, Vector3(0.06, 0.012, 0.2), bolt, Vector3(0.02, 0.125, -0.1)).rotation.y = 0.5     # a zig-zag bolt on the deck
	_box(root, Vector3(0.06, 0.012, 0.2), bolt, Vector3(-0.02, 0.125, 0.1)).rotation.y = -0.5
	for sz in [-1.0, 1.0]:
		_box(root, Vector3(0.2, 0.03, 0.05), truck, Vector3(0, 0.07, 0.27 * sz))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := _cyl(root, 0.05, 0.045, wheel, Vector3(0.13 * sx, 0.05, 0.27 * sz))
			w.rotation.z = PI / 2.0
	return root


static func build(id: String) -> Spatial:
	return jetpack() if id == "jetpack" else skateboard()

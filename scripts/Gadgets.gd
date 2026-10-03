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


# Two fuel tanks with nozzles, about 0.7 m tall.
static func jetpack() -> Spatial:
	var root := Spatial.new()
	var body := _mat(Color(0.75, 0.2, 0.2), 0.4)
	var steel := _mat(Color(0.6, 0.62, 0.68), 0.7)
	for sx in [-1.0, 1.0]:
		_cyl(root, 0.14, 0.6, body, Vector3(0.17 * sx, 0.35, 0))
		_cyl(root, 0.09, 0.12, steel, Vector3(0.17 * sx, 0.02, 0))
		_cyl(root, 0.06, 0.1, steel, Vector3(0.17 * sx, 0.68, 0))
	_box(root, Vector3(0.4, 0.1, 0.12), steel, Vector3(0, 0.45, 0.1))
	return root


# A deck on four wheels, 0.8 m long.
static func skateboard() -> Spatial:
	var root := Spatial.new()
	var deck := _mat(Color(0.2, 0.7, 0.95))
	var grip := _mat(Color(0.1, 0.1, 0.12))
	var wheel := _mat(Color(0.95, 0.85, 0.2))
	_box(root, Vector3(0.28, 0.04, 0.8), deck, Vector3(0, 0.1, 0))
	_box(root, Vector3(0.26, 0.01, 0.78), grip, Vector3(0, 0.125, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := _cyl(root, 0.045, 0.04, wheel, Vector3(0.13 * sx, 0.05, 0.27 * sz))
			w.rotation.z = PI / 2.0
	return root


static func build(id: String) -> Spatial:
	return jetpack() if id == "jetpack" else skateboard()

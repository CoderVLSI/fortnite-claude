extends StaticBody
# One placed building piece (wall / floor / ramp / roof) in wood, stone or metal.
# Weapons and the pickaxe damage it through take_damage(); when destroyed it frees its grid slot.

const MAT_COLOR := {"wood": Color(0.62, 0.42, 0.22), "stone": Color(0.58, 0.58, 0.62), "metal": Color(0.45, 0.60, 0.80)}
const MAT_HP := {"wood": 150.0, "stone": 300.0, "metal": 450.0}

var kind := "wall"
var mat_name := "wood"
var health := 150.0
var is_dead := false
var key := ""
var registry: Dictionary
var _mesh_node: MeshInstance
var _flash := 0.0


static func make_mesh(piece_kind: String) -> Mesh:
	match piece_kind:
		"wall":
			var m := CubeMesh.new()
			m.size = Vector3(4.0, 3.0, 0.25)
			return m
		"floor":
			var m := CubeMesh.new()
			m.size = Vector3(4.0, 0.25, 4.0)
			return m
		"ramp":
			var m := CubeMesh.new()
			m.size = Vector3(4.0, 0.25, 5.0)
			return m
		_:
			var m := PrismMesh.new()          # peaked roof
			m.size = Vector3(4.0, 2.2, 4.0)
			return m


# Base transform for a piece centred at pos; ramps are tilted so the high end faces -Z.
static func piece_basis(piece_kind: String, yaw: float) -> Basis:
	var b := Basis(Vector3.UP, yaw)
	if piece_kind == "ramp":
		b = b * Basis(Vector3.RIGHT, atan2(3.0, 4.0))
	return b


func setup(piece_kind: String, material_name: String, slot_key: String, slots: Dictionary) -> void:
	kind = piece_kind
	mat_name = material_name
	health = MAT_HP[material_name]
	key = slot_key
	registry = slots


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	set_meta("harvest", mat_name)
	add_to_group("build_pieces")
	var mesh := make_mesh(kind)
	_mesh_node = MeshInstance.new()
	_mesh_node.mesh = mesh
	var mat := SpatialMaterial.new()
	mat.albedo_color = MAT_COLOR[mat_name]
	mat.roughness = 0.8
	_mesh_node.material_override = mat
	add_child(_mesh_node)
	var shape: Shape
	if kind == "roof":
		shape = mesh.create_convex_shape()
	else:
		var box := BoxShape.new()
		box.extents = (mesh as CubeMesh).size / 2.0
		shape = box
	var cs := CollisionShape.new()
	cs.shape = shape
	add_child(cs)


func take_damage(amount: float, _source = null) -> void:
	if is_dead:
		return
	health -= amount
	_flash = 0.12
	if _mesh_node != null:
		_mesh_node.material_override.albedo_color = MAT_COLOR[mat_name].linear_interpolate(Color(1, 1, 1), 0.45)
	if health <= 0.0:
		is_dead = true
		Audio.play3d("build_break", global_transform.origin, 0.0, rand_range(0.9, 1.1))
		if registry.has(key):
			registry.erase(key)
		remove_from_group("build_pieces")
		queue_free()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and _mesh_node != null and not is_dead:
			_mesh_node.material_override.albedo_color = MAT_COLOR[mat_name]

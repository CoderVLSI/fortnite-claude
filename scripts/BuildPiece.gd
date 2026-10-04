extends StaticBody
# One placed building piece (wall / floor / ramp / roof) in wood, stone or metal.
# Weapons and the pickaxe damage it through take_damage(); when destroyed it frees its grid slot.

const MAT_COLOR := {"wood": Color(0.62, 0.42, 0.22), "stone": Color(0.58, 0.58, 0.62), "metal": Color(0.45, 0.60, 0.80)}
const MAT_HP := {"wood": 200.0, "stone": 300.0, "metal": 400.0}       # as in Fortnite

var kind := "wall"
var mat_name := "wood"
var health := 150.0
var is_dead := false
var key := ""
var registry: Dictionary
var _mesh_node: MeshInstance
var _full_shape: CollisionShape
var _cells := []                    # per-cell meshes and collision shapes once the piece has been edited
var mask := [true, true, true, true, true, true, true, true, true]   # 3x3: index = row * 3 + col (wall: row 0 is the bottom)
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
	_full_shape = cs


# Walls and floors can be edited: each of the nine cells is kept or cut away (doors, windows, holes).
func editable() -> bool:
	return kind == "wall" or kind == "floor"


func full_size() -> Vector3:
	return (_mesh_node.mesh as CubeMesh).size


func get_mask() -> Array:
	return mask.duplicate()


func is_full() -> bool:
	for c in mask:
		if not c:
			return false
	return true


# Apply a new cell mask. At least one cell must remain. Returns false if the mask was rejected.
func apply_mask(new_mask: Array) -> bool:
	if not editable() or new_mask.size() != 9 or is_dead:
		return false
	var any := false
	for c in new_mask:
		any = any or c
	if not any:
		return false
	mask = new_mask.duplicate()
	for n in _cells:
		remove_child(n)                  # gone right away (queue_free alone would leave them until the frame ends)
		n.queue_free()
	_cells.clear()
	var full := is_full()
	_mesh_node.visible = full
	_full_shape.disabled = not full         # the whole-piece collider is only used while no cell is cut away
	if full:
		return true
	var full_size: Vector3 = (_mesh_node.mesh as CubeMesh).size
	var cell := Vector3(full_size.x / 3.0, full_size.y / 3.0, full_size.z) if kind == "wall" else Vector3(full_size.x / 3.0, full_size.y, full_size.z / 3.0)
	var cm := CubeMesh.new()
	cm.size = cell
	var box := BoxShape.new()
	box.extents = cell / 2.0
	for row in range(3):
		for col in range(3):
			if not mask[row * 3 + col]:
				continue
			var center := Vector3((col - 1) * cell.x, (row - 1) * cell.y, 0.0) if kind == "wall" else Vector3((col - 1) * cell.x, 0.0, (row - 1) * cell.z)
			var mi := MeshInstance.new()
			mi.mesh = cm
			mi.material_override = _mesh_node.material_override      # shared, so the hit flash colours every cell
			mi.translation = center
			add_child(mi)
			var cs := CollisionShape.new()
			cs.shape = box
			cs.translation = center
			add_child(cs)
			_cells.append(mi)
			_cells.append(cs)
	return true


func take_damage(amount: float, _source = null) -> void:
	if is_dead:
		return
	health -= amount
	if _source != null and "net_owner" in _source and _source.net_owner == 0 and Net.active and Net.in_match:
		Net.send_event("bdmg", [key, amount])          # damage we dealt: the other machines apply it too
	if _source != null and _source.has_signal("harvested"):      # shows the health bar over the piece being hit
		_source.emit_signal("harvested", global_transform.origin + Vector3(0, 0.6, 0), clamp(health / MAT_HP[mat_name], 0.0, 1.0),
			mat_name, "%s %s" % [mat_name.to_upper(), kind.to_upper()], "piece:%d" % get_instance_id())
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

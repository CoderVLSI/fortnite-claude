extends Spatial
# A door that swings open by itself when anyone comes close and shuts again when they leave.
# Child of a building; the hinge sits on the doorway's left edge, front of the building = local +Z.

var door_w := 1.3
var door_h := 2.25
var _pivot: Spatial
var _body: StaticBody
var _open := false
var _angle := 0.0
var _t := rand_range(0.0, 0.2)
const OPEN_ANGLE := -1.75       # swings outward (towards +Z)
const TRIGGER := 3.0


func _ready() -> void:
	add_to_group("doors")
	_pivot = Spatial.new()
	_pivot.translation = Vector3(-door_w / 2.0, 0.0, 0.0)
	add_child(_pivot)
	_body = StaticBody.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("harvest", "wood")
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = Vector3(door_w - 0.06, door_h - 0.04, 0.09)
	mi.mesh = cm
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.45, 0.30, 0.17)
	mat.roughness = 0.85
	mi.material_override = mat
	mi.translation = Vector3(door_w / 2.0, door_h / 2.0, 0)
	_body.add_child(mi)
	var cs := CollisionShape.new()
	var sh := BoxShape.new()
	sh.extents = cm.size / 2.0
	cs.shape = sh
	cs.translation = mi.translation
	_body.add_child(cs)
	_pivot.add_child(_body)
	var handle := MeshInstance.new()
	var hm := SphereMesh.new()
	hm.radius = 0.05
	hm.height = 0.1
	hm.radial_segments = 8
	hm.rings = 4
	handle.mesh = hm
	var hmat := SpatialMaterial.new()
	hmat.albedo_color = Color(0.85, 0.75, 0.3)
	hmat.metallic = 0.6
	handle.material_override = hmat
	handle.translation = Vector3(door_w - 0.18, door_h * 0.45, 0.07)
	_body.add_child(handle)


func _physics_process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.15
		var c := global_transform.origin + global_transform.basis.y * 1.0
		var want := false
		for f in get_tree().get_nodes_in_group("fighters"):
			if f.is_dead:
				continue
			if f.global_transform.origin.distance_to(c) < TRIGGER:
				want = true
				break
		if want != _open:
			_open = want
			Audio.play3d("door", c, -4.0, 1.0 if _open else 0.85)
			for cs in _body.get_children():
				if cs is CollisionShape:
					cs.set_deferred("disabled", _open)
	_angle = lerp(_angle, OPEN_ANGLE if _open else 0.0, clamp(7.0 * delta, 0.0, 1.0))
	_pivot.rotation.y = _angle

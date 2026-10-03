extends Area
# A Bouncer: a spring pad you place. Whoever steps on it (friend or foe) is flung up and a little forward.

const LIFETIME := 90.0

var power := 21.0
var owner_fighter = null
var _t := 0.0
var _cool := {}                       # fighter instance id -> seconds until it can bounce again


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2                   # fighters
	monitoring = true
	var cs := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(0.9, 0.35, 0.9)
	cs.shape = box
	cs.translation = Vector3(0, 0.3, 0)
	add_child(cs)
	var base := MeshInstance.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.85
	bm.bottom_radius = 0.95
	bm.height = 0.18
	bm.radial_segments = 14
	base.mesh = bm
	base.translation = Vector3(0, 0.09, 0)
	var m1 := SpatialMaterial.new()
	m1.albedo_color = Color(0.15, 0.55, 0.95)
	m1.metallic = 0.3
	base.material_override = m1
	add_child(base)
	var top := MeshInstance.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.6
	tm.bottom_radius = 0.7
	tm.height = 0.1
	tm.radial_segments = 14
	top.mesh = tm
	top.translation = Vector3(0, 0.23, 0)
	var m2 := SpatialMaterial.new()
	m2.albedo_color = Color(1.0, 0.85, 0.2)
	m2.emission_enabled = true
	m2.emission = Color(1.0, 0.7, 0.1)
	m2.emission_energy = 0.8
	top.material_override = m2
	add_child(top)
	add_to_group("bounce_pads")


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > LIFETIME:
		queue_free()
		return
	for k in _cool.keys():
		_cool[k] -= delta
		if _cool[k] <= 0.0:
			_cool.erase(k)
	for b in get_overlapping_bodies():
		if b.has_method("bounce_launch") and not _cool.has(b.get_instance_id()) and not b.is_dead:
			_cool[b.get_instance_id()] = 0.6
			b.bounce_launch(power, global_transform.basis.y)
			Audio.play3d("jump", global_transform.origin + Vector3(0, 0.3, 0), 2.0, 1.6)

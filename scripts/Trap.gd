extends Area
# A placed trap. "spike": floor spikes that stab whoever steps on them (three times, then they are spent).
# "mine": a proximity mine that arms after a moment and blows up when an enemy comes within a few metres.
# The owner and the owner's team never trigger it.

const RADIUS := 5.0                  # mine blast radius
const MINE_DAMAGE := 100.0
const SPIKE_DAMAGE := 45.0
const LIFETIME := 150.0

var kind := "spike"
var owner_fighter = null
var visual_only := false             # a copy of a trap another machine placed: shows up, but that machine does the damage
var charges := 3
var _t := 0.0
var _cool := {}
var _armed := 0.0
var _spikes: Spatial
var _mat: SpatialMaterial


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	add_to_group("traps")
	var cs := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(0.9, 0.5, 0.9) if kind == "spike" else Vector3(0.45, 0.4, 0.45)
	cs.shape = box
	cs.translation = Vector3(0, 0.4, 0)
	add_child(cs)
	_mat = SpatialMaterial.new()
	if kind == "spike":
		_build_spikes()
	else:
		_build_mine()


func _build_spikes() -> void:
	var plate := MeshInstance.new()
	var pm := CubeMesh.new()
	pm.size = Vector3(1.7, 0.1, 1.7)
	plate.mesh = pm
	plate.translation = Vector3(0, 0.05, 0)
	var m := SpatialMaterial.new()
	m.albedo_color = Color(0.3, 0.3, 0.34)
	m.metallic = 0.5
	plate.material_override = m
	add_child(plate)
	_spikes = Spatial.new()
	add_child(_spikes)
	var sm := SpatialMaterial.new()
	sm.albedo_color = Color(0.75, 0.78, 0.85)
	sm.metallic = 0.8
	sm.roughness = 0.3
	for ix in range(4):
		for iz in range(4):
			var s := MeshInstance.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.1
			cm.height = 0.55
			cm.radial_segments = 6
			cm.rings = 1
			s.mesh = cm
			s.material_override = sm
			s.translation = Vector3(-0.6 + ix * 0.4, 0.38, -0.6 + iz * 0.4)
			_spikes.add_child(s)
	_spikes.scale = Vector3(1, 0.25, 1)             # lying low until somebody steps on it


func _build_mine() -> void:
	var disc := MeshInstance.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.34
	dm.bottom_radius = 0.4
	dm.height = 0.14
	dm.radial_segments = 12
	disc.mesh = dm
	disc.translation = Vector3(0, 0.07, 0)
	var m := SpatialMaterial.new()
	m.albedo_color = Color(0.25, 0.3, 0.22)
	m.metallic = 0.4
	disc.material_override = m
	add_child(disc)
	var led := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 0.07
	sph.height = 0.14
	sph.radial_segments = 8
	sph.rings = 4
	led.mesh = sph
	led.translation = Vector3(0, 0.17, 0)
	_mat.flags_unshaded = true
	_mat.albedo_color = Color(1.0, 0.7, 0.1)
	led.material_override = _mat
	add_child(led)


func hostile_to(f) -> bool:
	if f == null or not is_instance_valid(f) or f.is_dead:
		return false
	if owner_fighter != null and is_instance_valid(owner_fighter) and (f == owner_fighter or owner_fighter.is_ally(f)):
		return false
	return true


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > LIFETIME:
		queue_free()
		return
	for k in _cool.keys():
		_cool[k] -= delta
		if _cool[k] <= 0.0:
			_cool.erase(k)
	if kind == "mine":
		_armed += delta
		var armed := _armed > 1.5
		_mat.albedo_color = (Color(1.0, 0.15, 0.1) if fmod(_t * 4.0, 1.0) < 0.5 else Color(0.2, 0.0, 0.0)) if armed else Color(1.0, 0.7, 0.1)
		if armed and not visual_only:
			for f in get_tree().get_nodes_in_group("fighters"):
				if hostile_to(f) and f.global_transform.origin.distance_to(global_transform.origin) < 2.6:
					_detonate()
					return
		return
	if _spikes != null:
		_spikes.scale.y = lerp(_spikes.scale.y, 1.0 if not _cool.empty() else 0.25, clamp(14.0 * delta, 0.0, 1.0))
	if visual_only:
		return
	for b in get_overlapping_bodies():
		if b.has_method("take_damage") and hostile_to(b) and not _cool.has(b.get_instance_id()):
			_stab(b)


func _stab(f) -> void:
	_cool[f.get_instance_id()] = 1.0
	Audio.play3d("hit_metal", global_transform.origin, -2.0, 0.8)
	f.take_damage(SPIKE_DAMAGE, owner_fighter)
	if f.has_method("knockback") and not f.is_dead:
		f.knockback(Vector3(0, 7.5, 0))
	charges -= 1
	if charges <= 0:
		get_tree().create_timer(0.6).connect("timeout", self, "queue_free")
		set_physics_process(false)


func _detonate() -> void:
	set_physics_process(false)
	var pos := global_transform.origin + Vector3(0, 0.3, 0)
	Audio.play3d("explosion", pos, 3.0)
	var space := get_world().direct_space_state
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.is_dead:
			continue
		var chest: Vector3 = f.global_transform.origin + Vector3(0, 1.0, 0)
		var d: float = chest.distance_to(pos)
		if d >= RADIUS:
			continue
		var dmg: float = MINE_DAMAGE * (1.0 - 0.6 * d / RADIUS)
		if space.intersect_ray(pos, chest, [self], 1):
			dmg *= 0.35
		var was_alive: bool = not f.is_dead
		if owner_fighter == null or not is_instance_valid(owner_fighter) or not owner_fighter.is_ally(f) or f == owner_fighter:
			f.take_damage(dmg, owner_fighter)
		if owner_fighter != null and is_instance_valid(owner_fighter) and owner_fighter != f:
			owner_fighter.emit_signal("hit_landed", f, was_alive and f.is_dead, false)
		if f.has_method("knockback") and not f.is_dead:
			f.knockback(((chest - pos).normalized() + Vector3(0, 0.8, 0)) * 9.0)
	for piece in get_tree().get_nodes_in_group("build_pieces"):
		if is_instance_valid(piece) and not piece.is_dead and piece.global_transform.origin.distance_to(pos) < RADIUS:
			piece.take_damage(220.0, owner_fighter)
	var fire := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	fire.mesh = sph
	fire.material_override = mat
	var parent := get_parent()
	parent.add_child(fire)
	fire.global_transform.origin = pos + Vector3(0, 0.4, 0)
	var tw := Tween.new()
	fire.add_child(tw)
	tw.interpolate_property(fire, "scale", Vector3(0.4, 0.4, 0.4), Vector3(RADIUS * 0.5, RADIUS * 0.4, RADIUS * 0.5), 0.5, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.interpolate_property(mat, "albedo_color:a", 0.85, 0.0, 0.55)
	tw.start()
	fire.get_tree().create_timer(0.7).connect("timeout", fire, "queue_free")
	queue_free()

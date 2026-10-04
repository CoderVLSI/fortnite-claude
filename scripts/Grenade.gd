extends RigidBody
# A thrown frag grenade: bounces off the world, blinks faster as the fuse burns down, then explodes. The blast hurts every
# fighter (the thrower too) and every build piece in range, less behind cover, and shows a hit marker / damage number
# for the thrower.

const Items = preload("res://scripts/Items.gd")

const RADIUS := 8.0
const SHOCK_RADIUS := 9.0
const MAX_DAMAGE := 115.0
const PIECE_DAMAGE := 300.0

var thrower = null
var visual_only := false            # a copy of somebody else's grenade: same look and sound, no damage here
var shock := false                   # Shockwave Grenade: no damage, flings everyone nearby
var boogie := false                  # Boogie Bomb: everybody close has to dance
var stink := false                   # Stink Bomb: leaves a harmful cloud
var damage_mult := 1.0               # bots throw weaker grenades than the player's
var fuse := 2.4
var _mat: SpatialMaterial
var _t := 0.0
var _done := false


func _ready() -> void:
	mass = 0.6
	collision_layer = 0                      # nothing collides with it...
	collision_mask = 1                       # ...it only bounces off the world
	contact_monitor = true
	contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.38
	pm.friction = 0.8
	physics_material_override = pm
	var cs := CollisionShape.new()
	var sh := SphereShape.new()
	sh.radius = 0.13
	cs.shape = sh
	add_child(cs)
	var scene = load("res://assets/models/grenade.glb")
	var model: Spatial
	if scene != null:
		model = scene.instance()
		model.scale = Vector3(1.4, 1.4, 1.4)
		model.translation = Vector3(0, -0.14, 0)
	else:
		var mi := MeshInstance.new()
		mi.mesh = SphereMesh.new()
		mi.scale = Vector3(0.13, 0.13, 0.13)
		model = mi
	add_child(model)
	_mat = SpatialMaterial.new()
	_mat.flags_unshaded = true
	_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.0) if shock else (Color(1.0, 0.3, 0.85, 0.0) if boogie else (Color(0.5, 0.95, 0.2, 0.0) if stink else Color(1, 0.2, 0.1, 0.0)))
	_mat.flags_transparent = true
	var glow := MeshInstance.new()                         # a red light on top that blinks faster and faster
	var sph := SphereMesh.new()
	sph.radius = 0.05
	sph.height = 0.1
	sph.radial_segments = 8
	sph.rings = 4
	glow.mesh = sph
	glow.material_override = _mat
	glow.translation = Vector3(0, 0.2, 0)
	add_child(glow)
	connect("body_entered", self, "_on_hit")


func _on_hit(_body) -> void:
	if linear_velocity.length() > 2.0:
		Audio.play3d("hit_metal", global_transform.origin, -10.0, rand_range(1.2, 1.5))


func _physics_process(delta: float) -> void:
	if _done:
		return
	fuse -= delta
	_t += delta
	var rate: float = lerp(14.0, 4.0, clamp(fuse / 2.4, 0.0, 1.0))
	_mat.albedo_color.a = 1.0 if fmod(_t * rate, 1.0) < 0.5 else 0.0
	if fuse <= 0.0:
		_explode()


func _shockwave() -> void:
	_done = true
	var pos := global_transform.origin
	Audio.play3d("shockwave_boom", pos + Vector3(0, 0.5, 0), 0.0)
	Audio.play3d("explosion", pos + Vector3(0, 0.5, 0), -6.0, 1.8)
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.is_dead or f.net_owner != 0:          # a puppet is flung by its own machine (it runs its own copy)
			continue
		var chest: Vector3 = f.global_transform.origin + Vector3(0, 1.0, 0)
		var d: float = chest.distance_to(pos)
		if d >= SHOCK_RADIUS:
			continue
		var dir: Vector3 = (chest - pos)
		dir.y = max(dir.y, 0.0) * 0.5
		dir = dir.normalized() if dir.length() > 0.05 else Vector3.UP
		var power: float = 1.0 - 0.55 * d / SHOCK_RADIUS
		f.knockback(dir * 20.0 * power + Vector3(0, 13.0 * power, 0))
	var parent := get_parent()
	var ring := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 16
	sph.rings = 8
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.45)
	ring.mesh = sph
	ring.material_override = mat
	parent.add_child(ring)
	ring.global_transform.origin = pos + Vector3(0, 0.4, 0)
	var tw := Tween.new()
	ring.add_child(tw)
	tw.interpolate_property(ring, "scale", Vector3(0.3, 0.3, 0.3), Vector3(SHOCK_RADIUS, SHOCK_RADIUS, SHOCK_RADIUS), 0.4, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.interpolate_property(mat, "albedo_color:a", 0.45, 0.0, 0.45)
	tw.start()
	ring.get_tree().create_timer(0.55).connect("timeout", ring, "queue_free")
	queue_free()


const BOOGIE_RADIUS := 7.5
const BOOGIE_TIME := 5.0


func _boogie_burst() -> void:
	_done = true
	var pos := global_transform.origin
	Audio.play3d("shockwave_boom", pos + Vector3(0, 0.5, 0), -6.0, 1.6)
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.is_dead or f.net_owner != 0:          # a puppet dances on its own machine (and we see it through its pose flags)
			continue
		var d: float = (f.global_transform.origin + Vector3(0, 1.0, 0)).distance_to(pos)
		if d < BOOGIE_RADIUS:
			f.start_boogie(BOOGIE_TIME)
	_ring(pos, BOOGIE_RADIUS, Color(1.0, 0.4, 0.85, 0.5))
	queue_free()


func _stink_burst() -> void:
	_done = true
	var pos := global_transform.origin
	Audio.play3d("explosion", pos + Vector3(0, 0.5, 0), -8.0, 2.0)
	var cloud := preload("res://scripts/GasCloud.gd").new()
	cloud.thrower = thrower
	get_parent().add_child(cloud)
	cloud.global_transform.origin = pos
	queue_free()


func _ring(pos: Vector3, radius: float, color: Color) -> void:
	var parent := get_parent()
	var ring := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 16
	sph.rings = 8
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mat.albedo_color = color
	ring.mesh = sph
	ring.material_override = mat
	parent.add_child(ring)
	ring.global_transform.origin = pos + Vector3(0, 0.4, 0)
	var tw := Tween.new()
	ring.add_child(tw)
	tw.interpolate_property(ring, "scale", Vector3(0.3, 0.3, 0.3), Vector3(radius, radius, radius), 0.4, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.interpolate_property(mat, "albedo_color:a", color.a, 0.0, 0.45)
	tw.start()
	ring.get_tree().create_timer(0.55).connect("timeout", ring, "queue_free")


func _explode() -> void:
	if shock:
		_shockwave()
		return
	if boogie:
		_boogie_burst()
		return
	if stink:
		_stink_burst()
		return
	_done = true
	var pos := global_transform.origin
	Audio.play3d("explosion", pos + Vector3(0, 0.5, 0), 3.0)
	var space := get_world().direct_space_state
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.is_dead or visual_only:
			continue
		var chest: Vector3 = f.global_transform.origin + Vector3(0, 1.0, 0)
		var d: float = chest.distance_to(pos)
		if d >= RADIUS:
			continue
		var dmg: float = (MAX_DAMAGE * (1.0 - d / RADIUS) + 12.0) * damage_mult
		var block := space.intersect_ray(pos + Vector3(0, 0.3, 0), chest, [self], 1)    # cover soaks up most of the blast
		if block:
			dmg *= 0.35
		var was_alive: bool = not f.is_dead
		f.take_damage(dmg, thrower)
		if thrower != null and is_instance_valid(thrower) and thrower != f:
			thrower.emit_signal("hit_landed", f, was_alive and f.is_dead, false)
			thrower.emit_signal("damage_dealt", chest, dmg, false, was_alive and f.is_dead)
	for piece in get_tree().get_nodes_in_group("build_pieces"):
		if visual_only or not is_instance_valid(piece) or piece.is_dead:
			continue
		var pd: float = piece.global_transform.origin.distance_to(pos)
		if pd < RADIUS:
			piece.take_damage(PIECE_DAMAGE * (1.0 - pd / RADIUS) + 20.0, thrower)
	_fireball(pos)
	queue_free()


func _fireball(pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var fire := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.albedo_color = Color(1.0, 0.6, 0.15, 0.85)
	fire.mesh = sph
	fire.material_override = mat
	fire.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fire)
	fire.global_transform.origin = pos + Vector3(0, 0.6, 0)
	var tw := Tween.new()
	fire.add_child(tw)
	tw.interpolate_property(fire, "scale", Vector3(0.4, 0.4, 0.4), Vector3(RADIUS * 0.55, RADIUS * 0.42, RADIUS * 0.55), 0.55, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.interpolate_property(mat, "albedo_color:a", 0.85, 0.0, 0.6)
	tw.start()
	fire.get_tree().create_timer(0.7).connect("timeout", fire, "queue_free")

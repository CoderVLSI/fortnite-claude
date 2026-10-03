extends RigidBody
# A thrown Junk Rift. Where it lands, a rift tears open high above and something very heavy (an anvil, a car, a boulder)
# plunges through it: 200 damage to anyone it lands on, a 100-damage shockwave around it, and it flattens build pieces
# and brings buildings down.

const Items = preload("res://scripts/Items.gd")
const Rift = preload("res://scripts/Rift.gd")

const DIRECT_RADIUS := 2.6
const SHOCK_RADIUS := 9.0
const FALL_HEIGHT := 48.0
const OPEN_TIME := 0.7

var thrower = null
var visual_only := false
var _age := 0.0
var _struck := false


func _ready() -> void:
	mass = 0.5
	collision_layer = 0
	collision_mask = 1
	contact_monitor = true
	contacts_reported = 2
	var cs := CollisionShape.new()
	var sh := SphereShape.new()
	sh.radius = 0.2
	cs.shape = sh
	add_child(cs)
	var orb := MeshInstance.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.radial_segments = 12
	sm.rings = 6
	orb.mesh = sm
	var m := SpatialMaterial.new()
	m.albedo_color = Color(0.7, 0.35, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.3, 1.0)
	m.emission_energy = 1.8
	orb.material_override = m
	add_child(orb)
	var l := OmniLight.new()
	l.light_color = Color(0.7, 0.35, 1.0)
	l.omni_range = 5.0
	add_child(l)


func _physics_process(delta: float) -> void:
	if _struck:
		return
	_age += delta
	if _age > 0.25 and (get_colliding_bodies().size() > 0 or _age > 3.0):
		_open_rift()


func _open_rift() -> void:
	_struck = true
	var pos := global_transform.origin
	var parent := get_parent()
	Audio.play3d("junk_rift_open", pos, 0.0)
	Audio.play3d("glider_open", pos, -4.0, 0.6)
	var holder := Spatial.new()                           # the portal lies flat above the impact point
	parent.add_child(holder)
	holder.global_transform.origin = pos + Vector3(0, FALL_HEIGHT, 0)
	var vis := Rift.build_visual(3.2)
	vis.rotation.x = PI / 2.0
	holder.add_child(vis)
	var tw := Tween.new()
	holder.add_child(tw)
	tw.interpolate_property(holder, "scale", Vector3(0.05, 0.05, 0.05), Vector3.ONE, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.interpolate_property(holder, "scale", Vector3.ONE, Vector3(0.05, 0.05, 0.05), 0.5, Tween.TRANS_QUAD, Tween.EASE_IN, 1.4)
	tw.start()
	parent.get_tree().create_timer(2.0).connect("timeout", holder, "queue_free")
	var obj := JunkObject.new()
	obj.thrower = thrower
	obj.visual_only = visual_only
	obj.delay = OPEN_TIME
	parent.add_child(obj)
	obj.global_transform.origin = pos + Vector3(0, FALL_HEIGHT, 0)
	queue_free()


# The heavy thing itself.
class JunkObject extends Spatial:
	var thrower = null
	var visual_only := false
	var delay := 0.7
	var _vy := 0.0
	var _landed := false

	func _ready() -> void:
		var pick := randi() % 3
		var mat := SpatialMaterial.new()
		mat.roughness = 0.6
		match pick:
			0:        # an anvil
				mat.albedo_color = Color(0.2, 0.2, 0.24)
				mat.metallic = 0.6
				_part(Vector3(1.5, 0.5, 0.8), Vector3(0, 0.55, 0), mat)
				_part(Vector3(0.7, 0.5, 0.6), Vector3(0, 0.1, 0), mat)
				_part(Vector3(1.0, 0.3, 0.7), Vector3(0, -0.2, 0), mat)
			1:        # a car
				mat.albedo_color = Color(0.85, 0.15, 0.12)
				_part(Vector3(2.0, 0.7, 4.2), Vector3(0, 0.0, 0), mat)
				_part(Vector3(1.7, 0.6, 2.0), Vector3(0, 0.6, -0.2), mat)
				var tire := SpatialMaterial.new()
				tire.albedo_color = Color(0.08, 0.08, 0.1)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						_part(Vector3(0.35, 0.8, 0.8), Vector3(1.0 * sx, -0.4, 1.4 * sz), tire)
			_:        # a boulder
				mat.albedo_color = Color(0.5, 0.48, 0.45)
				_part(Vector3(2.6, 2.2, 2.4), Vector3(0, 0, 0), mat)
				_part(Vector3(1.8, 1.8, 1.8), Vector3(0.5, 0.9, 0.3), mat)
		rotation.y = randf() * TAU

	func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
		var mi := MeshInstance.new()
		var cm := CubeMesh.new()
		cm.size = size
		mi.mesh = cm
		mi.material_override = mat
		mi.translation = pos
		add_child(mi)

	func _physics_process(delta: float) -> void:
		if _landed:
			return
		if delay > 0.0:
			delay -= delta
			return
		_vy = min(_vy + 60.0 * delta, 70.0)
		var from := global_transform.origin
		var to := from + Vector3(0, -_vy * delta, 0)
		var hit := get_world().direct_space_state.intersect_ray(from + Vector3(0, 1.0, 0), to + Vector3(0, -1.0, 0), [], 1)
		if hit:
			_land(hit.position)
		else:
			global_transform.origin = to

	func _land(pos: Vector3) -> void:
		_landed = true
		global_transform.origin = pos + Vector3(0, 0.6, 0)
		var tree := get_tree()
		Audio.play3d("junk_impact", pos, 4.0)
		Audio.play3d("explosion", pos, 2.0, 0.5)
		for f in tree.get_nodes_in_group("fighters"):
			if f.is_dead or visual_only:
				continue
			var fo: Vector3 = f.global_transform.origin
			var flat := Vector2(fo.x - pos.x, fo.z - pos.z).length()
			var dmg := 0.0
			if flat < 2.6 and abs(fo.y - pos.y) < 3.0:
				dmg = 200.0
			elif Vector3(fo.x, fo.y + 1.0, fo.z).distance_to(pos) < 9.0:
				dmg = lerp(100.0, 35.0, Vector3(fo.x, fo.y + 1.0, fo.z).distance_to(pos) / 9.0)
			if dmg > 0.0:
				var was_alive: bool = not f.is_dead
				f.take_damage(dmg, thrower)
				if thrower != null and is_instance_valid(thrower) and thrower != f:
					thrower.emit_signal("hit_landed", f, was_alive and f.is_dead, false)
					thrower.emit_signal("damage_dealt", fo + Vector3(0, 1.0, 0), dmg, false, was_alive and f.is_dead)
		for piece in tree.get_nodes_in_group("build_pieces"):
			if not visual_only and is_instance_valid(piece) and not piece.is_dead and piece.global_transform.origin.distance_to(pos) < 5.0:
				piece.take_damage(5000.0, thrower)
		if not visual_only:
			for w in tree.get_nodes_in_group("world"):
				w.break_pieces_near(pos, 7.0)
		var dust: CPUParticles = preload("res://scripts/SpriteCreature.gd").particles(Color(0.7, 0.66, 0.6, 0.85), 80, 1.6, 8.0, 80.0, 4.0, 2.5)
		dust.one_shot = true
		dust.explosiveness = 0.9
		get_parent().add_child(dust)
		dust.global_transform.origin = pos + Vector3(0, 0.5, 0)
		tree.create_timer(2.5).connect("timeout", dust, "queue_free")
		tree.create_timer(6.0).connect("timeout", self, "queue_free")

extends KinematicBody
# Island wildlife. Chickens scatter when you come close; boars leave you alone until you hurt one, then charge. Both drop
# Roast Meat (heals) when they go down. They are scenery: every machine has its own, only the meat they drop is shared.

const Items = preload("res://scripts/Items.gd")

const KINDS := {
	"chicken": {"hp": 12.0, "speed": 2.2, "run": 5.2, "scale": 0.55, "meat": [0, 1], "title": "Chicken"},
	"boar": {"hp": 70.0, "speed": 1.8, "run": 6.2, "scale": 1.0, "meat": [2, 3], "title": "Boar"},
}

export var kind := "chicken"

var terrain = null
var health := 12.0
var is_dead := false
var home := Vector2.ZERO
var _target := Vector2.ZERO
var _pause := rand_range(0.0, 3.0)
var _angry := 0.0
var _enemy = null
var _bite_cd := 0.0
var _scare := 0.0
var _flee_from := Vector2.ZERO
var _t := rand_range(0.0, 10.0)
var _model: Spatial
var _y := 0.0
var _acc := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("animals")
	add_to_group("wildlife")
	_rng.randomize()
	health = KINDS[kind].hp
	collision_layer = 2                     # shots land on it, like on a fighter
	collision_mask = 0
	var shape := CapsuleShape.new()
	shape.radius = 0.28 * KINDS[kind].scale + 0.12
	shape.height = 0.3 * KINDS[kind].scale
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.rotation_degrees.x = 90
	cs.translation = Vector3(0, 0.4 * KINDS[kind].scale + 0.1, 0)
	add_child(cs)
	_model = Spatial.new()
	add_child(_model)
	if kind == "chicken":
		_build_chicken()
	else:
		_build_boar()
	home = Vector2(translation.x, translation.z)
	_target = home


func _mat(c: Color) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Spatial = null) -> MeshInstance:
	var m := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	m.mesh = cm
	m.material_override = mat
	m.translation = pos
	(parent if parent != null else _model).add_child(m)
	return m


func _build_chicken() -> void:
	var white := _mat(Color(0.96, 0.95, 0.9))
	_box(Vector3(0.34, 0.3, 0.46), Vector3(0, 0.34, 0), white)             # body
	_box(Vector3(0.2, 0.22, 0.2), Vector3(0, 0.6, -0.22), white)           # head (front is -Z)
	_box(Vector3(0.06, 0.1, 0.16), Vector3(0, 0.76, -0.22), _mat(Color(0.85, 0.12, 0.12)))     # comb
	_box(Vector3(0.07, 0.07, 0.12), Vector3(0, 0.58, -0.36), _mat(Color(1.0, 0.7, 0.1)))       # beak
	_box(Vector3(0.28, 0.2, 0.16), Vector3(0, 0.42, 0.28), white)          # tail
	for sx in [-0.08, 0.08]:
		_box(Vector3(0.04, 0.2, 0.04), Vector3(sx, 0.1, 0.02), _mat(Color(1.0, 0.7, 0.1)))
	_model.scale = Vector3.ONE * 1.1


func _build_boar() -> void:
	var fur := _mat(Color(0.38, 0.27, 0.2))
	_box(Vector3(0.7, 0.62, 1.2), Vector3(0, 0.62, 0), fur)                # body
	_box(Vector3(0.5, 0.5, 0.5), Vector3(0, 0.62, -0.78), fur)              # head
	_box(Vector3(0.3, 0.24, 0.3), Vector3(0, 0.52, -1.1), _mat(Color(0.55, 0.38, 0.32)))   # snout
	for sx in [-0.15, 0.15]:
		_box(Vector3(0.06, 0.06, 0.2), Vector3(sx, 0.52, -1.12), _mat(Color(0.95, 0.93, 0.8)))   # tusks
		_box(Vector3(0.12, 0.16, 0.06), Vector3(sx * 2.0, 0.95, -0.66), fur)                      # ears
	for sx in [-0.24, 0.24]:
		for z in [-0.4, 0.45]:
			_box(Vector3(0.14, 0.4, 0.14), Vector3(sx, 0.2, z), fur)


func take_damage(amount: float, source = null) -> void:
	if is_dead:
		return
	health -= amount
	_flash()
	if source != null and is_instance_valid(source):
		if kind == "boar":
			_angry = 12.0
			_enemy = source
		else:
			_scare = 5.0
			_flee_from = Vector2(source.global_transform.origin.x, source.global_transform.origin.z)
	if health <= 0.0:
		_die(source)


func _flash() -> void:
	_model.translation.y = 0.08
	Audio.play3d("chicken_cluck" if kind == "chicken" else "boar_grunt", global_transform.origin + Vector3(0, 0.5, 0), 0.0)


func _die(killer) -> void:
	is_dead = true
	collision_layer = 0
	remove_from_group("animals")
	if killer != null and is_instance_valid(killer) and killer.has_method("stat_add"):
		killer.stat_add("hunts")
		killer.emit_signal("hit_landed", self, true, false)
	var n: int = _rng.randi_range(KINDS[kind].meat[0], KINDS[kind].meat[1])
	for w in get_tree().get_nodes_in_group("world"):
		for i in range(n):
			w.spawn_item(Items.make_consumable("meat", 1), global_transform.origin + Vector3(_rng.randf_range(-0.6, 0.6), 0.6, _rng.randf_range(-0.6, 0.6)))
	var tw := Tween.new()
	add_child(tw)
	tw.interpolate_property(_model, "rotation:z", 0.0, PI / 2.0, 0.4, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.start()
	get_tree().create_timer(6.0).connect("timeout", self, "queue_free")


func _nearest_fighter(max_d: float):
	var best = null
	var best_d := max_d
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.is_dead:
			continue
		var d: float = f.global_transform.origin.distance_to(global_transform.origin)
		if d < best_d:
			best_d = d
			best = f
	return best


func _physics_process(delta: float) -> void:
	if is_dead or terrain == null or (not visible and _angry <= 0.0):
		return                                   # far away (Perf.gd hides it): not worth simulating
	_t += delta
	_acc += delta
	_model.translation.y = lerp(_model.translation.y, 0.0, clamp(10.0 * delta, 0.0, 1.0))
	var pos := Vector2(translation.x, translation.z)
	var step := Vector2.ZERO
	var heading := Vector2.ZERO
	_bite_cd -= delta
	if _angry > 0.0 and _enemy != null and is_instance_valid(_enemy) and not _enemy.is_dead:
		_angry -= delta
		var ep := Vector2(_enemy.global_transform.origin.x, _enemy.global_transform.origin.z)
		var to := ep - pos
		heading = to.normalized()
		step = heading * KINDS[kind].run * delta
		if to.length() < 1.7 and _bite_cd <= 0.0:
			_bite_cd = 1.0
			_enemy.take_damage(14.0, null)
			Audio.play3d("hit_flesh", global_transform.origin + Vector3(0, 0.5, 0), -2.0, 0.7)
		if to.length() < 1.4:
			step = Vector2.ZERO
	else:
		_enemy = null
		_scare = max(0.0, _scare - delta)
		var near = null
		if kind == "chicken":
			near = _nearest_fighter(6.5)
		if near != null:
			_scare = max(_scare, 1.5)
			_flee_from = Vector2(near.global_transform.origin.x, near.global_transform.origin.z)
		if _scare > 0.0:
			heading = (pos - _flee_from).normalized()
			step = heading * KINDS[kind].run * delta
		elif _pause > 0.0:
			_pause -= delta
		else:
			var to2 := _target - pos
			if to2.length() < 0.7:
				_pause = rand_range(1.5, 5.0)
				var a := rand_range(0.0, TAU)
				_target = home + Vector2(cos(a), sin(a)) * rand_range(2.0, 12.0)
			else:
				heading = to2.normalized()
				step = heading * KINDS[kind].speed * delta
	if step != Vector2.ZERO:
		var np := pos + step
		var ny: float = terrain.height_at(np.x, np.y)
		if ny < 1.6 or abs(ny - translation.y) > 0.9:          # water or a cliff: turn around
			_target = home
			_scare = 0.0
			_pause = 0.5
		else:
			translation.x = np.x
			translation.z = np.y
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-heading.x, -heading.y), clamp(8.0 * delta, 0.0, 1.0))
		_model.translation.y = max(_model.translation.y, abs(sin(_t * 14.0)) * 0.05)
	translation.y = terrain.height_at(translation.x, translation.z)

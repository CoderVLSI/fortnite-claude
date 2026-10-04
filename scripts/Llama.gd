extends StaticBody
# A Supply Llama: a big party pinata. Shoot it or hit it with the pickaxe until it bursts and a pile of loot falls out.
# Every machine has the same llamas (same ids); when one bursts the others pop theirs, and the loot is shared as usual.

const Items = preload("res://scripts/Items.gd")

var net_id := ""
var health := 220.0
var is_dead := false
var _model: Spatial
var _t := rand_range(0.0, 6.0)
var _wobble := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("llamas")
	add_to_group("wildlife")
	collision_layer = 1
	collision_mask = 0
	_rng.randomize()
	var shape := BoxShape.new()
	shape.extents = Vector3(0.55, 1.35, 0.9)
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 1.35, 0)
	add_child(cs)
	_model = Spatial.new()
	add_child(_model)
	_build()
	var light := OmniLight.new()
	light.light_color = Color(1.0, 0.5, 0.9)
	light.light_energy = 0.8
	light.omni_range = 7.0
	light.translation = Vector3(0, 3.0, 0)
	add_child(light)


func _mat(c: Color) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var m := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	m.mesh = cm
	m.material_override = mat
	m.translation = pos
	m.rotation_degrees = rot
	_model.add_child(m)


func _build() -> void:
	var pink := _mat(Color(1.0, 0.45, 0.78))
	var teal := _mat(Color(0.2, 0.85, 0.85))
	var yellow := _mat(Color(1.0, 0.85, 0.2))
	var dark := _mat(Color(0.2, 0.1, 0.25))
	_box(Vector3(1.0, 1.1, 1.8), Vector3(0, 1.45, 0), pink)                   # body (front is -Z)
	_box(Vector3(1.02, 0.3, 1.82), Vector3(0, 1.35, 0), teal)                  # stripe
	_box(Vector3(0.9, 0.35, 0.4), Vector3(0, 1.95, 0.4), yellow)               # saddle blanket
	_box(Vector3(0.4, 1.3, 0.4), Vector3(0, 2.3, -0.85), pink)                 # neck
	_box(Vector3(0.5, 0.45, 0.7), Vector3(0, 3.0, -1.1), pink)                 # head
	_box(Vector3(0.3, 0.2, 0.2), Vector3(0, 2.88, -1.5), teal)                 # muzzle
	for sx in [-0.16, 0.16]:
		_box(Vector3(0.1, 0.1, 0.05), Vector3(sx, 3.1, -1.46), dark)           # eyes
		_box(Vector3(0.12, 0.4, 0.12), Vector3(sx * 1.6, 3.4, -0.95), yellow)  # ears
	for sx in [-0.3, 0.3]:
		for z in [-0.6, 0.6]:
			_box(Vector3(0.22, 1.0, 0.22), Vector3(sx, 0.5, z), pink)
			_box(Vector3(0.24, 0.12, 0.24), Vector3(sx, 0.08, z), dark)
	_box(Vector3(0.18, 0.18, 0.18), Vector3(0, 1.1, 1.0), yellow, Vector3(45, 45, 0))   # tail tuft


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_wobble = max(0.0, _wobble - delta * 3.0)
	_model.rotation_degrees.z = sin(_t * 30.0) * _wobble * 6.0
	_model.translation.y = abs(sin(_t * 2.0)) * 0.05


func take_damage(amount: float, source = null) -> void:
	if is_dead:
		return
	health -= amount
	_wobble = 1.0
	Audio.play3d("hit_flesh", global_transform.origin + Vector3(0, 1.5, 0), -4.0, 1.4)
	if health <= 0.0:
		burst(source)


# Loot: a couple of weapons or helpful items, ammo, materials and gold.
func loot() -> Array:
	var out := []
	out.append(Items.random_weapon(_rng, 2))
	out.append(Items.ammo_for(out[0], _rng, 2.0))
	out.append(Items.random_consumable(_rng))
	out.append(Items.make_consumable("slurp_juice", 2))
	out.append(Items.make_material("wood", 150))
	out.append(Items.make_material("stone", 150))
	out.append(Items.make_material("metal", 150))
	out.append(Items.make_gold(_rng.randi_range(8, 16) * 5))
	return out


func burst(source = null, from_net: bool = false) -> void:
	if is_dead:
		return
	is_dead = true
	var pos := global_transform.origin + Vector3(0, 2.0, 0)
	Audio.play3d("chest_open", pos, 2.0, 0.8)
	Audio.play3d("explosion", pos, -4.0, 1.8)
	_confetti(pos)
	for w in get_tree().get_nodes_in_group("world"):
		if not from_net:
			var items := loot()
			for i in range(items.size()):
				var a := float(i) / float(items.size()) * TAU
				w.spawn_item(items[i], pos + Vector3(cos(a), 0.2, sin(a)) * 1.3)
			if w.net_live and net_id != "":
				Net.send_event("llama_pop", net_id)
			if source != null and is_instance_valid(source) and source.has_method("stat_add"):
				source.stat_add("llamas")
	queue_free()


func _confetti(pos: Vector3) -> void:
	var p := CPUParticles.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 60
	p.lifetime = 1.6
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity = 7.0
	p.gravity = Vector3(0, -9.0, 0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	p.mesh = mesh
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.vertex_color_use_as_albedo = true
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mesh.material = mat
	var grad := Gradient.new()
	grad.colors = PoolColorArray([Color(1, 0.4, 0.8), Color(0.3, 0.9, 0.9), Color(1, 0.85, 0.2)])
	grad.offsets = PoolRealArray([0.0, 0.5, 1.0])
	p.color_ramp = grad
	get_parent().add_child(p)
	p.global_transform.origin = pos
	p.get_tree().create_timer(2.5).connect("timeout", p, "queue_free")

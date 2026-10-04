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
	var scene = load("res://assets/models/bouncer.glb")
	if scene != null:
		var model: Spatial = scene.instance()
		model.scale = Vector3(3.6, 3.6, 3.6)         # 0.5 m item, 1.8 m pad
		add_child(model)
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

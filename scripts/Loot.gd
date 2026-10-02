extends Area
# Glowing loot crate: walk into it to get health, shield or ammo.

const KINDS := ["ammo", "shield", "heal"]

var kind := "ammo"
var _model: Spatial
var _t := rand_range(0.0, 6.0)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2        # fighters
	var sphere := SphereShape.new()
	sphere.radius = 1.4
	var cs := CollisionShape.new()
	cs.shape = sphere
	cs.translation = Vector3(0, 0.6, 0)
	add_child(cs)
	var scene = load("res://assets/models/crate.glb")
	if scene != null:
		_model = scene.instance()
		add_child(_model)
	else:
		_model = Spatial.new()
		add_child(_model)
	connect("body_entered", self, "_on_body_entered")


func _process(delta: float) -> void:
	_t += delta
	if _model:
		_model.rotation.y += delta * 1.3
		_model.translation.y = 0.15 + sin(_t * 2.2) * 0.08


func _on_body_entered(body: Node) -> void:
	if not body.has_method("heal") or body.is_dead:
		return
	var text := ""
	match kind:
		"ammo":
			body.add_ammo(60)
			text = "+60 ammo"
		"shield":
			body.add_shield(50.0)
			text = "+50 shield"
		_:
			body.heal(40.0)
			text = "+40 health"
	body.emit_signal("picked_up", text)
	queue_free()

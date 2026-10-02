extends Spatial
# The "Sky Ferry": flies straight across the island at altitude; everyone starts aboard
# and drops from it (players with JUMP, bots at random moments). Remaining riders are
# ejected when it reaches the end of its route.

signal finished

const MODEL_PATH := "res://assets/models/battle_bus.glb"

var direction := Vector3.FORWARD
var speed := 24.0
var route_length := 480.0
var traveled := 0.0
var start := Vector3.ZERO
var _props := []
var _done := false


func setup(from: Vector3, dir: Vector3, length: float) -> void:
	start = from
	direction = dir.normalized()
	route_length = length
	translation = from
	rotation.y = atan2(-direction.x, -direction.z)     # model forward is -Z


func _ready() -> void:
	var scene = load(MODEL_PATH)
	if scene != null:
		var m: Spatial = scene.instance()
		m.scale = Vector3(1.6, 1.6, 1.6)
		add_child(m)
		for n in ["PropL", "PropR"]:
			var p := m.get_node_or_null(n)
			if p:
				_props.append(p)
	Audio.make_loop3d("bus_loop", self, 4.0, 450.0)


func _process(delta: float) -> void:
	if _done:
		return
	traveled += speed * delta
	translation = start + direction * traveled
	for p in _props:
		p.rotate_object_local(Vector3(0, 0, 1), 25.0 * delta)
	if traveled >= route_length:
		_done = true
		emit_signal("finished")
		get_tree().create_timer(6.0).connect("timeout", self, "queue_free")


func seat_position() -> Vector3:
	return global_transform.origin + Vector3(0, -1.0, 0)

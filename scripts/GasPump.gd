extends Spatial
# A fuel pump: press interact next to a vehicle (or while sitting in one) and its tank is filled up.

const REACH := 12.0

var _glow: SpatialMaterial


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("gas_pumps")
	var red := SpatialMaterial.new()
	red.albedo_color = Color(0.85, 0.15, 0.12)
	red.roughness = 0.5
	var dark := SpatialMaterial.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	_glow = SpatialMaterial.new()
	_glow.flags_unshaded = true
	_glow.albedo_color = Color(0.4, 1.0, 0.4)
	_box(Vector3(0.7, 1.7, 0.5), Vector3(0, 0.85, 0), red)
	_box(Vector3(0.9, 0.12, 0.7), Vector3(0, 0.06, 0), dark)
	_box(Vector3(0.5, 0.3, 0.05), Vector3(0, 1.35, 0.26), _glow)           # the little display
	_box(Vector3(0.12, 0.5, 0.12), Vector3(0.42, 0.8, 0.0), dark)           # the hose holder
	_box(Vector3(0.8, 0.14, 0.6), Vector3(0, 1.75, 0), dark)                # the roof of the pump
	var sb := StaticBody.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := BoxShape.new()
	shape.extents = Vector3(0.45, 0.9, 0.35)
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 0.9, 0)
	sb.add_child(cs)
	add_child(sb)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	m.mesh = cm
	m.material_override = mat
	m.translation = pos
	add_child(m)


# The vehicle this pump would fill: the one the player drives, else the nearest within reach.
func target_for(by):
	if by.mode == 6 and by.vehicle != null and is_instance_valid(by.vehicle) and "fuel" in by.vehicle:
		return by.vehicle
	var best = null
	var best_d := REACH
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not is_instance_valid(v) or not ("fuel" in v) or v.exploded:
			continue
		var d: float = v.global_transform.origin.distance_to(global_transform.origin)
		if d < best_d:
			best_d = d
			best = v
	return best


func can_interact() -> bool:
	return true


func prompt_text() -> String:
	for pl in get_tree().get_nodes_in_group("player"):
		var v = target_for(pl)
		if v == null:
			return "Fuel pump  (park a vehicle beside it)"
		if v.fuel >= 99.0:
			return "Fuel pump  (%s tank is full)" % v.title
		return "Refuel the %s  (%d%%)" % [v.title, int(v.fuel)]
	return "Fuel pump"


func prompt_color() -> Color:
	return Color(1.0, 0.6, 0.3)


func interact(by) -> void:
	var v = target_for(by)
	if v == null:
		by.emit_signal("picked_up", "Park a vehicle next to the pump")
		Audio.play2d("ui_error", -4.0)
	elif v.fuel >= 99.0:
		by.emit_signal("picked_up", "The tank is already full")
	else:
		v.fuel = 100.0
		Audio.play3d("pump_fill", global_transform.origin + Vector3(0, 1.0, 0), 0.0)
		by.emit_signal("picked_up", "Refuelled the %s" % v.title)

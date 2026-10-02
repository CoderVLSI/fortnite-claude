extends Reference
# Logic shared by the wheeled vehicles (Vehicle.gd) and the boat (Boat.gd): seats, interaction,
# damage and the explosion. The vehicle node supplies: occupants[], seat_offsets[], health,
# exploded, is_dead, title, model, last_attacker.

const TITLES := {"buggy": "Buggy", "quad": "Quad Bike", "boat": "Motor Boat"}


static func free_seat(v) -> int:
	for i in range(v.occupants.size()):
		if v.occupants[i] == null or not is_instance_valid(v.occupants[i]):
			v.occupants[i] = null
			return i
	return -1


static func can_interact(v) -> bool:
	return not v.exploded and free_seat(v) >= 0 and v.linear_velocity.length() < 5.0


static func prompt(v) -> String:
	var seat := free_seat(v)
	return ("Drive " if seat == 0 else "Ride ") + TITLES[v.kind]


static func interact(v, by) -> void:
	var seat := free_seat(v)
	if seat < 0 or v.exploded:
		return
	v.occupants[seat] = by
	by.enter_vehicle(v, seat)


static func seat_position(v, seat: int) -> Vector3:
	return v.global_transform.xform(v.seat_offsets[seat])


# Where an occupant steps out: beside the seat, on the ground.
static func exit_position(v, seat: int) -> Vector3:
	var side: float = -1.0 if v.seat_offsets[seat].x <= 0.0 else 1.0
	var p: Vector3 = v.global_transform.xform(Vector3(side * 1.9, 0.6, v.seat_offsets[seat].z))
	var space = v.get_world().direct_space_state
	var hit = space.intersect_ray(p + Vector3(0, 1.5, 0), p + Vector3(0, -4.0, 0), [v], 1)
	if hit:
		p.y = hit.position.y + 0.1
	return p


static func release(v, seat: int) -> void:
	if seat >= 0 and seat < v.occupants.size():
		v.occupants[seat] = null


static func take_damage(v, amount: float, source) -> void:
	if v.exploded:
		return
	v.health -= amount
	if source != null:
		v.last_attacker = source
	if v.health <= 0.0:
		explode(v)


static func explode(v) -> void:
	if v.exploded:
		return
	v.exploded = true
	v.is_dead = true
	var pos: Vector3 = v.global_transform.origin
	Audio.play3d("explosion", pos + Vector3(0, 1.0, 0), 4.0)
	for i in range(v.occupants.size()):
		var o = v.occupants[i]
		if o != null and is_instance_valid(o):
			o.exit_vehicle(true)
	for f in v.get_tree().get_nodes_in_group("fighters"):
		if f.is_dead:
			continue
		var d: float = f.global_transform.origin.distance_to(pos)
		if d < 9.0:
			f.take_damage(95.0 * (1.0 - d / 9.0), v.last_attacker)
	# wreck: blackened, thrown upward, no longer drivable
	if v.model != null:
		var Items = load("res://scripts/Items.gd")
		Items.apply_accent(v.model, Color(0.05, 0.05, 0.05))
	v.apply_central_impulse(Vector3(0, v.mass * 5.0, 0))
	v.apply_torque_impulse(Vector3(v.mass * 0.8, 0, v.mass * 0.6))
	v.remove_from_group("interactable")
	var fire := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.albedo_color = Color(1.0, 0.55, 0.12, 0.85)
	fire.mesh = sph
	fire.material_override = mat
	v.get_parent().add_child(fire)
	fire.global_transform.origin = pos + Vector3(0, 1.0, 0)
	var tw := Tween.new()
	fire.add_child(tw)
	tw.interpolate_property(fire, "scale", Vector3(0.5, 0.5, 0.5), Vector3(5.5, 4.0, 5.5), 0.8, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.interpolate_property(mat, "albedo_color:a", 0.85, 0.0, 0.9)
	tw.start()
	v.get_tree().create_timer(1.0).connect("timeout", fire, "queue_free")

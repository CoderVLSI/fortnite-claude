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
	return not v.exploded and v.net_owner == 0 and free_seat(v) >= 0 and v.linear_velocity.length() < 5.0


static func prompt(v) -> String:
	var seat := free_seat(v)
	return ("Drive " if seat == 0 else "Ride ") + TITLES[v.kind]


static func interact(v, by) -> void:
	var seat := free_seat(v)
	if seat < 0 or v.exploded:
		return
	v.occupants[seat] = by
	by.enter_vehicle(v, seat)
	if seat == 0 and by.net_owner == 0 and v.net_id != "" and Net.active and Net.in_match:
		Net.send_event("veh_claim", v.net_id)          # the driver's machine runs the vehicle; the others follow it


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
		var was = v.occupants[seat]
		v.occupants[seat] = null
		if seat == 0 and was != null and is_instance_valid(was) and was.net_owner == 0 and v.net_id != "" and Net.active and Net.in_match:
			Net.send_event("veh_release", [v.net_id, v.global_transform])


# Network: another machine is driving this vehicle.
static func net_claim(v, owner_id: int) -> void:
	v.net_owner = owner_id
	v.mode = RigidBody.MODE_KINEMATIC
	v._net_has = false


static func net_release(v, xf: Transform) -> void:
	v.net_owner = 0
	v.mode = RigidBody.MODE_RIGID
	v.global_transform = xf
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO


static func net_follow(v, delta: float) -> void:
	if not v._net_has:
		return
	var cur: Transform = v.global_transform
	var t: float = clamp(12.0 * delta, 0.0, 1.0)
	v.global_transform = Transform(cur.basis.slerp(v._net_xf.basis, t), cur.origin.linear_interpolate(v._net_xf.origin, t))


static func take_damage(v, amount: float, source, from_net: bool = false) -> void:
	if v.exploded:
		return
	v.health -= amount
	if source != null:
		v.last_attacker = source
	if not from_net and source != null and "net_owner" in source and source.net_owner == 0 and v.net_id != "" and Net.active and Net.in_match:
		Net.send_event("vdmg", [v.net_id, amount])        # the others apply the same damage
	if v.health <= 0.0:
		explode(v, from_net)


static func explode(v, from_net: bool = false) -> void:
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
		if f.is_dead or from_net:            # the machine that caused the blast hurts people; here it is only a show
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


# --- fuel ----------------------------------------------------------------------
# Every wheeled vehicle and boat has a tank (0..100). Driving burns it (more with the throttle down and the boost on); with an
# empty tank the engine is dead and you coast. Fuel pumps (GasPump.gd) fill it.

const FUEL_IDLE := 0.04
const FUEL_THROTTLE := 0.55


static func burn_fuel(v, thr: float, boost: bool, delta: float) -> bool:
	if v.fuel <= 0.0:
		return false
	v.fuel = max(0.0, v.fuel - (FUEL_IDLE + abs(thr) * FUEL_THROTTLE * (1.8 if boost else 1.0)) * delta)
	if v.fuel <= 0.0:
		var d = v.occupants[0] if v.occupants.size() > 0 else null
		Audio.play3d("out_of_fuel", v.global_transform.origin, 2.0)
		if d != null and is_instance_valid(d):
			d.emit_signal("picked_up", "OUT OF FUEL - find a pump")
		return false
	if v.fuel < 15.0 and not v.low_warned:
		v.low_warned = true
		var d2 = v.occupants[0] if v.occupants.size() > 0 else null
		if d2 != null and is_instance_valid(d2):
			d2.emit_signal("picked_up", "Low fuel")
	elif v.fuel > 25.0:
		v.low_warned = false
	return true

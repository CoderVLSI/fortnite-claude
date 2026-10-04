extends Spatial
# A Reboot Van: bring a fallen team-mate's card here (interact) and they drop back into the match beside the van.

var _screen_mat: SpatialMaterial
var _t := 0.0
var _light: OmniLight


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("reboot_vans")
	var body_mat := SpatialMaterial.new()
	body_mat.albedo_color = Color(0.92, 0.92, 0.95)
	body_mat.roughness = 0.5
	var stripe := SpatialMaterial.new()
	stripe.albedo_color = Color(0.1, 0.65, 0.95)
	var dark := SpatialMaterial.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.roughness = 0.9
	_screen_mat = SpatialMaterial.new()
	_screen_mat.flags_unshaded = true
	_screen_mat.albedo_color = Color(0.3, 0.9, 1.0)
	_box(Vector3(2.2, 1.7, 4.4), Vector3(0, 1.25, 0), body_mat)             # the box body
	_box(Vector3(2.22, 0.3, 4.42), Vector3(0, 1.3, 0), stripe)
	_box(Vector3(2.0, 1.0, 1.3), Vector3(0, 1.0, -2.65), body_mat)          # the cab (front is -Z)
	_box(Vector3(1.7, 0.5, 0.05), Vector3(0, 1.4, -3.3), dark)              # windscreen
	for sx in [-1.0, 1.0]:
		for z in [-2.2, 1.6]:
			var w := MeshInstance.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.42
			cm.bottom_radius = 0.42
			cm.height = 0.3
			cm.radial_segments = 10
			w.mesh = cm
			w.material_override = dark
			w.rotation_degrees.z = 90
			w.translation = Vector3(sx * 1.1, 0.42, z)
			add_child(w)
	var screen := MeshInstance.new()                                         # the glowing "reboot" panel on the back
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 0.9)
	screen.mesh = qm
	screen.material_override = _screen_mat
	screen.translation = Vector3(0, 1.7, 2.21)
	screen.rotation_degrees.y = 0
	add_child(screen)
	var dish := MeshInstance.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.6
	dm.bottom_radius = 0.05
	dm.height = 0.3
	dm.radial_segments = 10
	dish.mesh = dm
	dish.material_override = stripe
	dish.translation = Vector3(0, 2.25, 0.3)
	add_child(dish)
	_light = OmniLight.new()
	_light.light_color = Color(0.3, 0.9, 1.0)
	_light.light_energy = 0.9
	_light.omni_range = 9.0
	_light.translation = Vector3(0, 2.8, 1.5)
	add_child(_light)
	var sb := StaticBody.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := BoxShape.new()
	shape.extents = Vector3(1.1, 1.15, 2.2)
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 1.2, -0.3)
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


func _process(delta: float) -> void:
	_t += delta
	var has := false
	for pl in get_tree().get_nodes_in_group("player"):
		has = "cards" in pl and not pl.cards.empty()
	_screen_mat.albedo_color = Color(0.3, 0.9, 1.0) * (0.7 + 0.3 * sin(_t * 4.0)) if has else Color(0.2, 0.35, 0.4)
	_light.light_energy = 1.3 if has else 0.5


func _player():
	for pl in get_tree().get_nodes_in_group("player"):
		return pl
	return null


func _usable_card(by):
	if not ("cards" in by):
		return null
	for c in by.cards:
		if c != null and is_instance_valid(c) and c.is_dead:
			return c
	return null


func can_interact() -> bool:
	var pl = _player()
	return pl != null and not pl.is_dead and not pl.downed


func prompt_text() -> String:
	var pl = _player()
	if pl != null:
		var c = _usable_card(pl)
		if c != null:
			return "Reboot %s" % str(c.display_name)
	return "Reboot Van  (needs a team-mate's card)"


func prompt_color() -> Color:
	return Color(0.4, 0.9, 1.0)


func interact(by) -> void:
	var c = _usable_card(by)
	if c == null:
		by.emit_signal("picked_up", "Bring a fallen team-mate's reboot card here")
		Audio.play2d("ui_error", -4.0)
		return
	by.cards.erase(c)
	var out: Vector3 = global_transform.origin + global_transform.basis.z * 4.2 + Vector3(0, 1.0, 0)
	for w in get_tree().get_nodes_in_group("world"):
		w.reboot_fighter(c, out)
	by.emit_signal("picked_up", "Rebooted %s!" % str(c.display_name))

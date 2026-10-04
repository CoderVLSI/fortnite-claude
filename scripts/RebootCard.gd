extends Spatial
# The card a fallen team-mate leaves behind. A living team-mate picks it up (interact), carries it to a Reboot Van, and the
# fallen fighter drops back into the match there. Cards fade after two minutes.

const LIFETIME := 120.0

var fighter                          # whose card this is
var victim_key = null
var _t := 0.0
var _mesh: MeshInstance


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("reboot_cards")
	_mesh = MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = Vector3(0.5, 0.7, 0.04)
	_mesh.mesh = cm
	var m := SpatialMaterial.new()
	m.albedo_color = Color(0.3, 0.9, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.8, 1.0)
	m.emission_energy = 1.4
	_mesh.material_override = m
	_mesh.translation = Vector3(0, 1.0, 0)
	add_child(_mesh)
	var light := OmniLight.new()
	light.light_color = Color(0.3, 0.9, 1.0)
	light.light_energy = 0.8
	light.omni_range = 5.0
	light.translation = Vector3(0, 1.0, 0)
	add_child(light)
	var beam := MeshInstance.new()                 # a thin light pillar so a card can be spotted across a field
	var bm := CylinderMesh.new()
	bm.top_radius = 0.05
	bm.bottom_radius = 0.05
	bm.height = 14.0
	beam.mesh = bm
	var bmat := SpatialMaterial.new()
	bmat.flags_unshaded = true
	bmat.flags_transparent = true
	bmat.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	beam.translation = Vector3(0, 7.0, 0)
	add_child(beam)


func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.y += delta * 2.0
	_mesh.translation.y = 1.0 + sin(_t * 2.5) * 0.12
	if _t > LIFETIME:
		queue_free()


func _carrier():
	for pl in get_tree().get_nodes_in_group("player"):
		return pl
	return null


func can_interact() -> bool:
	if fighter == null or not is_instance_valid(fighter) or not fighter.is_dead:
		return false
	var pl = _carrier()
	return pl != null and pl != fighter and not pl.is_dead and not pl.downed and pl.is_ally(fighter)


func prompt_text() -> String:
	return "Take %s's reboot card" % str(fighter.display_name)


func prompt_color() -> Color:
	return Color(0.4, 0.9, 1.0)


func interact(by) -> void:
	if not ("cards" in by):
		return
	by.cards.append(fighter)
	by.emit_signal("picked_up", "Got %s's reboot card - take it to a Reboot Van" % str(fighter.display_name))
	Audio.play2d("rarity_3", -4.0)
	if Net.active and Net.in_match and victim_key != null:
		Net.send_event("card_taken", victim_key)
	queue_free()

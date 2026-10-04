extends Spatial
# A sealed concrete vault. The node sits at the middle of the door (door side = local +Z); the room extends behind it (-Z).
# The steel door opens with a Vault Keycard (dropped by the Warden bosses). Mythic chests wait inside (World places them).

var net_id := ""
var opened := false
var vault_name := "Vault"
var _door: StaticBody
var _strip: MeshInstance
var _t := 0.0

const W := 8.0
const D := 7.0
const H := 3.9
const DOOR_W := 2.4
const DOOR_H := 2.7


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("vaults")
	var concrete := Color(0.52, 0.53, 0.55)
	var wall_t := 0.5
	var zc := -D / 2.0 - 0.0
	_box(Vector3(0, 0.15, zc), Vector3(W, 0.3, D), Color(0.3, 0.3, 0.32))
	_box(Vector3(0, H / 2.0, -D), Vector3(W, H, wall_t), concrete)                       # back
	_box(Vector3(-W / 2.0, H / 2.0, zc), Vector3(wall_t, H, D), concrete)               # sides
	_box(Vector3(W / 2.0, H / 2.0, zc), Vector3(wall_t, H, D), concrete)
	var seg := (W - DOOR_W) / 2.0
	_box(Vector3(-(DOOR_W / 2.0 + seg / 2.0), H / 2.0, 0), Vector3(seg, H, wall_t), concrete)     # front, either side of the door
	_box(Vector3(DOOR_W / 2.0 + seg / 2.0, H / 2.0, 0), Vector3(seg, H, wall_t), concrete)
	_box(Vector3(0, DOOR_H + (H - DOOR_H) / 2.0, 0), Vector3(DOOR_W, H - DOOR_H, wall_t), concrete)     # above the door
	_box(Vector3(0, H + 0.2, zc), Vector3(W + 0.6, 0.4, D + 0.6), Color(0.38, 0.39, 0.41))      # roof
	_door = _box(Vector3(0, DOOR_H / 2.0, 0.0), Vector3(DOOR_W - 0.05, DOOR_H, 0.34), Color(0.62, 0.64, 0.7))
	var strip := CubeMesh.new()
	strip.size = Vector3(DOOR_W, 0.18, 0.1)
	_strip = MeshInstance.new()
	_strip.mesh = strip
	_strip.material_override = _glow(Color(1.0, 0.15, 0.1))
	_strip.translation = Vector3(0, DOOR_H + 0.3, 0.3)
	add_child(_strip)
	var light := OmniLight.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 1.1
	light.omni_range = 7.0
	light.translation = Vector3(0, 2.6, -D / 2.0)
	add_child(light)


func _glow(c: Color) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy = 1.6
	return m


func _box(pos: Vector3, size: Vector3, color: Color) -> StaticBody:
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	mi.mesh = cm
	var mat := SpatialMaterial.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape.new()
	var sh := BoxShape.new()
	sh.extents = size / 2.0
	cs.shape = sh
	body.add_child(cs)
	body.translation = pos
	add_child(body)
	return body


func _carrier():
	for pl in get_tree().get_nodes_in_group("player"):
		return pl
	return null


func can_interact() -> bool:
	return not opened


func prompt_text() -> String:
	var pl = _carrier()
	if pl != null and "keycards" in pl and pl.keycards > 0:
		return "Open %s (use keycard)" % vault_name
	return "%s is locked - needs a keycard from a Warden" % vault_name


func prompt_color() -> Color:
	return Color(1.0, 0.35, 0.1)


func interact(by) -> void:
	if not ("keycards" in by) or by.keycards <= 0:
		by.emit_signal("picked_up", "Locked - a Warden carries the keycard")
		Audio.play2d("keycard_deny", -2.0)
		return
	by.keycards -= 1
	by.emit_signal("picked_up", "Vault unlocked!")
	open()
	if Net.active and Net.in_match and net_id != "":
		Net.send_event("vault", net_id)


func open(_from_net := false) -> void:
	if opened:
		return
	opened = true
	remove_from_group("interactable")
	Audio.play3d("vault_unlock", global_transform.origin + Vector3(0, 1.0, 0), 2.0)
	Audio.play3d("vault_door", global_transform.origin + Vector3(0, 1.0, 0), 4.0)
	Audio.play3d("vault_alarm", global_transform.origin + Vector3(0, 2.0, -3.0), -4.0)
	_strip.material_override = _glow(Color(0.2, 1.0, 0.3))
	var tween := Tween.new()
	add_child(tween)
	tween.interpolate_property(_door, "translation:y", _door.translation.y, _door.translation.y + DOOR_H + 0.2, 1.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	tween.interpolate_callback(self, 1.35, "_door_done")
	tween.start()


func _door_done() -> void:
	for c in _door.get_children():
		if c is CollisionShape:
			c.disabled = true

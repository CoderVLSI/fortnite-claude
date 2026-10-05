extends Spatial
# A mound of fresh earth with a glint of gold. Swing the pickaxe at it: three digs uncover a treasure chest.
# Placed deterministically (every machine builds the same mounds); digging is told to the other players.

const Chest = preload("res://scripts/Chest.gd")

var net_id := ""
var hits := 0
var revealed := false
var chest = null
var _mound: MeshInstance
var _body: StaticBody
var _glint: MeshInstance
var _t := 0.0
var _shake := 0.0

const HITS_NEEDED := 3


func _ready() -> void:
	add_to_group("buried_chests")
	var dirt := SpatialMaterial.new()
	dirt.albedo_color = Color(0.36, 0.24, 0.14)
	dirt.roughness = 1.0
	_mound = MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 0.9
	sph.height = 1.0
	sph.radial_segments = 10
	sph.rings = 4
	_mound.mesh = sph
	_mound.material_override = dirt
	_mound.scale = Vector3(1.0, 0.45, 0.8)
	_mound.translation = Vector3(0, 0.1, 0)
	add_child(_mound)
	for i in range(4):                                         # a few clods and stones on top
		var c := MeshInstance.new()
		var cm := SphereMesh.new()
		cm.radius = 0.16
		cm.height = 0.3
		cm.radial_segments = 6
		cm.rings = 3
		c.mesh = cm
		c.material_override = dirt
		c.translation = Vector3(cos(float(i) * 1.7) * 0.6, 0.08, sin(float(i) * 1.7) * 0.5)
		add_child(c)
	var gm := SpatialMaterial.new()                            # the glint that gives it away
	gm.flags_unshaded = true
	gm.albedo_color = Color(1.0, 0.85, 0.25)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.8, 0.2)
	gm.emission_energy = 1.6
	_glint = MeshInstance.new()
	var gs := SphereMesh.new()
	gs.radius = 0.07
	gs.height = 0.14
	_glint.mesh = gs
	_glint.material_override = gm
	_glint.translation = Vector3(0.1, 0.5, 0.0)
	add_child(_glint)
	_body = StaticBody.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("harvest", "dirt")
	_body.set_meta("buried", self)
	var cs := CollisionShape.new()
	var sh := SphereShape.new()
	sh.radius = 0.9
	cs.shape = sh
	cs.translation = Vector3(0, 0.1, 0)
	_body.add_child(cs)
	add_child(_body)


func _process(delta: float) -> void:
	_t += delta
	if _glint != null and not revealed:
		_glint.translation.y = 0.5 + sin(_t * 3.0) * 0.06
		_glint.visible = int(_t * 3.0) % 5 != 0
	if _shake > 0.0 and _mound != null:
		_shake = max(0.0, _shake - delta)
		_mound.translation.x = sin(_t * 60.0) * 0.05 * _shake * 4.0


# A pickaxe swing (called by World.harvest_hit). `by` may be null for a dig reported from another machine.
func dig(by = null, from_net: bool = false) -> void:
	if revealed:
		return
	hits += 1
	_shake = 0.25
	Audio.play3d("hit_stone", global_transform.origin + Vector3(0, 0.4, 0), -2.0, rand_range(0.6, 0.75))
	if by != null and not from_net and "net_owner" in by and by.net_owner == 0 and Net.active and Net.in_match and net_id != "":
		Net.send_event("dig", net_id)
	if hits >= HITS_NEEDED:
		reveal()
	else:
		_mound.scale = _mound.scale * Vector3(0.9, 0.78, 0.9)


func reveal() -> void:
	if revealed:
		return
	revealed = true
	_body.get_child(0).disabled = true
	remove_from_group("buried_chests")
	_glint.visible = false
	Audio.play3d("chest_open", global_transform.origin + Vector3(0, 0.5, 0), -2.0, 0.8)
	for w in get_tree().get_nodes_in_group("world"):
		chest = w._add_chest("chest", global_transform.origin + Vector3(0, 0.1, 0), rotation.y, "bc_" + net_id, int(hash(net_id)) % 100000 + 1)
	if chest != null:
		chest.translation.y -= 0.8
		var tw := Tween.new()
		chest.add_child(tw)
		tw.interpolate_property(chest, "translation:y", chest.translation.y, chest.translation.y + 0.8, 0.6, Tween.TRANS_BACK, Tween.EASE_OUT)
		tw.start()
	var tw2 := Tween.new()
	add_child(tw2)
	tw2.interpolate_property(_mound, "scale", _mound.scale, Vector3(1.2, 0.12, 1.0), 0.5)
	tw2.start()

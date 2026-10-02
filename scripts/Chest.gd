extends Spatial
# Openable containers, three varieties:
#   "chest"    treasure chest: a weapon (uncommon or better), a consumable, ammo
#   "ammo_box" green ammo crate: lots of ammo of two types
#   "supply"   supply drop: floats down under a balloon, holds top-tier weapons + shield/heal
# Opening pops the contents out onto the floor as LootItems.

const Items = preload("res://scripts/Items.gd")

const MODELS := {"chest": "chest", "ammo_box": "ammo_box", "supply": "supply", "vault": "vault"}
const TITLES := {"chest": "Treasure Chest", "ammo_box": "Ammo Box", "supply": "Supply Drop", "vault": "Vault"}
const BEAM_HEIGHT := {"chest": 6.0, "ammo_box": 5.0, "supply": 26.0, "vault": 14.0}

export var kind := "chest"

var opened := false
var falling := false
var ground_y := 0.0
var rng := RandomNumberGenerator.new()
var _lid: Spatial
var _balloon: Spatial
var _beam: MeshInstance


func _ready() -> void:
	rng.randomize()
	add_to_group("interactable")
	if kind == "supply":
		add_to_group("supply")
	var scene = load("res://assets/models/%s.glb" % MODELS[kind])
	var model: Spatial = scene.instance() if scene != null else Spatial.new()
	add_child(model)
	_lid = model.get_node_or_null("Lid")
	_balloon = model.get_node_or_null("Balloon")

	var half := Vector3(0.55, 0.3, 0.36)
	if kind == "ammo_box":
		half = Vector3(0.45, 0.25, 0.25)
	elif kind == "supply":
		half = Vector3(0.6, 0.45, 0.6)
	elif kind == "vault":
		half = Vector3(0.65, 0.42, 0.45)
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape.new()
	shape.extents = half
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, half.y, 0)
	body.add_child(cs)
	add_child(body)

	var color := Items.chest_color(kind)
	var h: float = BEAM_HEIGHT[kind]
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18 if kind != "supply" else 0.35
	mesh.bottom_radius = mesh.top_radius
	mesh.height = h
	mesh.radial_segments = 8
	mesh.rings = 1
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
	_beam = MeshInstance.new()
	_beam.mesh = mesh
	_beam.material_override = mat
	_beam.translation = Vector3(0, h / 2.0, 0)
	_beam.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)

	if _balloon:
		_balloon.visible = falling


func start_fall(from_height: float, ground: float) -> void:
	falling = true
	ground_y = ground
	translation.y = ground + from_height
	if _balloon:
		_balloon.visible = true


func _process(delta: float) -> void:
	if not falling:
		return
	translation.y -= 8.0 * delta
	if translation.y <= ground_y:
		translation.y = ground_y
		falling = false
		Audio.play3d("land", global_transform.origin, -2.0)
		if _balloon:
			var tween := Tween.new()
			add_child(tween)
			tween.interpolate_property(_balloon, "scale", Vector3.ONE, Vector3(0.01, 0.01, 0.01), 0.8)
			tween.interpolate_callback(_balloon, 0.85, "hide")
			tween.start()


func can_interact() -> bool:
	return not opened and not falling


func prompt_text() -> String:
	return "Open " + TITLES[kind]


func prompt_color() -> Color:
	return Items.chest_color(kind)


func interact(_by) -> void:
	open()


func _chime(tier: int) -> void:
	Audio.play3d("rarity_%d" % (tier + 1), global_transform.origin + Vector3(0, 1.0, 0), -3.0)


func open() -> void:
	if opened:
		return
	opened = true
	remove_from_group("interactable")
	if _beam:
		_beam.queue_free()
	if _lid:
		var tween := Tween.new()
		add_child(tween)
		tween.interpolate_property(_lid, "rotation:x", 0.0, -1.9, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
		tween.start()
	Audio.play3d("ammo_box_open" if kind == "ammo_box" else "chest_open", global_transform.origin + Vector3(0, 0.5, 0), 0.0)
	var loot := Items.chest_loot(kind, rng)
	var best := 0
	for it in loot:
		best = int(max(best, Items.rarity_of(it) if it.kind == "weapon" else 0))
	if best >= 1:
		get_tree().create_timer(0.45).connect("timeout", self, "_chime", [best])
	var n := loot.size()
	for i in range(n):
		var a := PI * (0.2 + 0.6 * float(i) / max(n - 1, 1))      # fan out on the open (front, +Z) side
		var dir := Vector3(cos(a), 0.0, sin(a)).rotated(Vector3.UP, rotation.y)
		for w in get_tree().get_nodes_in_group("world"):
			w.spawn_item(loot[i], global_transform.origin + dir * (1.5 + 0.2 * (i % 2)) + Vector3(0, 0.1, 0))

extends Spatial
# An item lying on the floor: spinning model, rarity-coloured beam and ring.
# Weapons and consumables are picked up with "interact"; ammo is collected by walking over it.

const Items = preload("res://scripts/Items.gd")

var item: Dictionary = {}
var _model: Spatial
var _t := rand_range(0.0, 6.0)
var _rest_y := 0.0


func setup(it: Dictionary) -> void:
	item = it


func _ready() -> void:
	add_to_group("interactable")
	var color := Items.color_of(item)
	var scene = load(Items.model_of(item))
	_model = scene.instance() if scene != null else Spatial.new()
	var s := 1.5 if item.kind == "weapon" else 1.8
	_model.scale = Vector3(s, s, s)
	add_child(_model)

	var beam := MeshInstance.new()
	beam.mesh = _shared_mesh("loot_beam_mesh", 0.10, 4.5, 8)
	beam.material_override = _shared_material("loot_beam_" + color.to_html(false), Color(color.r, color.g, color.b, 0.38))
	beam.translation = Vector3(0, 2.25, 0)
	beam.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var ring := MeshInstance.new()
	ring.mesh = _shared_mesh("loot_ring_mesh", 0.75, 0.03, 16)
	ring.material_override = _shared_material("loot_ring_" + color.to_html(false), Color(color.r, color.g, color.b, 0.55))
	ring.translation = Vector3(0, 0.03, 0)
	ring.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_rest_y = 0.55


func _cache() -> Dictionary:
	# Shared meshes/materials live on the World node so they are released before the renderer shuts down.
	var worlds := get_tree().get_nodes_in_group("world")
	return worlds[0].shared if worlds.size() > 0 else {}


func _shared_mesh(key: String, radius: float, height: float, segments: int) -> Mesh:
	var cache := _cache()
	if cache.has(key):
		return cache[key]
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	cache[key] = m
	return m


func _shared_material(key: String, color: Color) -> Material:
	var cache := _cache()
	if cache.has(key):
		return cache[key]
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.flags_do_not_receive_shadows = true
	m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.albedo_color = color
	cache[key] = m
	return m


func _process(delta: float) -> void:
	_t += delta
	if _model:
		_model.rotation.y += delta * 1.4
		_model.translation.y = _rest_y + sin(_t * 2.4) * 0.08


func _physics_process(_delta: float) -> void:
	if item.kind != "ammo" or Engine.get_physics_frames() % 5 != 0:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if not p.is_dead and p.global_transform.origin.distance_to(global_transform.origin) < 1.9:
			interact(p)
			return


func can_interact() -> bool:
	return true


func prompt_text() -> String:
	return Items.name_of(item)


func prompt_color() -> Color:
	return Items.color_of(item)


func interact(by) -> void:
	var res: Dictionary = by.pickup(item)
	by.emit_signal("picked_up", res.text)
	if not res.ok:
		return
	if res.dropped != null:
		for w in get_tree().get_nodes_in_group("world"):
			w.spawn_item(res.dropped, global_transform.origin + Vector3(0.9, 0.0, 0.0))
	remove_from_group("interactable")
	queue_free()

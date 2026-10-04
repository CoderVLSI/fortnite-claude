extends Spatial
# A Stink Bomb's cloud: a green haze that hurts everybody inside it (the thrower too) for a few seconds.

const RADIUS := 5.5
const DURATION := 7.0
const DPS := 9.0

var thrower = null
var _t := 0.0
var _tick := 0.0
var _mesh: MeshInstance
var _mat: SpatialMaterial


func _ready() -> void:
	add_to_group("gas_clouds")
	_mesh = MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 14
	sph.rings = 7
	_mesh.mesh = sph
	_mat = SpatialMaterial.new()
	_mat.flags_unshaded = true
	_mat.flags_transparent = true
	_mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_mat.albedo_color = Color(0.45, 0.85, 0.2, 0.0)
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_mesh.scale = Vector3(0.5, 0.5, 0.5)
	add_child(_mesh)


func contains(pos: Vector3) -> bool:
	return pos.distance_to(global_transform.origin + Vector3(0, 1.0, 0)) < RADIUS


func _physics_process(delta: float) -> void:
	_t += delta
	var grow: float = clamp(_t / 0.8, 0.0, 1.0)
	var r: float = RADIUS * (0.4 + 0.6 * grow)
	_mesh.scale = Vector3(r, r * 0.55, r)
	_mesh.translation = Vector3(0, 0.9, 0)
	var fade: float = clamp((DURATION - _t) / 1.2, 0.0, 1.0)
	_mat.albedo_color.a = 0.28 * min(grow * 2.0, 1.0) * fade + 0.04 * sin(_t * 5.0)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		for f in get_tree().get_nodes_in_group("fighters"):
			if f.is_dead or f.net_owner != 0:      # a puppet is hurt by its own machine's copy of the cloud
				continue
			if contains(f.global_transform.origin + Vector3(0, 0.9, 0)):
				f.take_damage(DPS * 0.5, thrower)
	if _t >= DURATION:
		queue_free()

extends Spatial
# A rift: a violet portal. Step into it and you are flung high above the island with your glider ready to open.
# World rifts close once used (lifetime 0); a Rift-to-Go stays open for `lifetime` seconds.

var lifetime := 0.0
var used := false
var _t := 0.0
var _ring: Spatial
var _fade := 1.0
var _light: OmniLight
var _mats := []

const CENTER_Y := 1.7


static func _torus(inner: float, outer: float, segs: int, sides: int) -> Mesh:
	var mid := (inner + outer) / 2.0
	var tube := (outer - inner) / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segs):
		for j in range(sides):
			var q := []
			for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var a := float(i + d[0]) / segs * TAU
				var b := float(j + d[1]) / sides * TAU
				var rr := mid + cos(b) * tube
				q.append(Vector3(cos(a) * rr, sin(b) * tube, sin(a) * rr))
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[idx])
	st.generate_normals()
	return st.commit()


# The portal graphics, reused as the Rift-to-Go loot model.
static func build_visual(r: float) -> Spatial:
	var root := Spatial.new()
	var ring_mat := SpatialMaterial.new()
	ring_mat.albedo_color = Color(0.72, 0.4, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.7, 0.3, 1.0)
	ring_mat.emission_energy = 1.6
	var ring := MeshInstance.new()
	ring.mesh = _torus(r * 0.82, r, 28, 8)
	ring.material_override = ring_mat
	ring.rotation.x = PI / 2.0
	root.add_child(ring)
	var disc_mat := SpatialMaterial.new()
	disc_mat.flags_unshaded = true
	disc_mat.flags_transparent = true
	disc_mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	disc_mat.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	disc_mat.albedo_color = Color(0.45, 0.15, 0.85, 0.55)
	var disc := MeshInstance.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.85
	cm.bottom_radius = r * 0.85
	cm.height = 0.04
	cm.radial_segments = 20
	cm.rings = 1
	disc.mesh = cm
	disc.material_override = disc_mat
	disc.rotation.x = PI / 2.0
	root.add_child(disc)
	root.set_meta("mats", [ring_mat, disc_mat])
	return root


func _ready() -> void:
	add_to_group("rifts")
	_ring = build_visual(1.5)
	_ring.translation = Vector3(0, CENTER_Y, 0)
	add_child(_ring)
	_mats = _ring.get_meta("mats")
	_light = OmniLight.new()
	_light.light_color = Color(0.7, 0.35, 1.0)
	_light.light_energy = 1.4
	_light.omni_range = 14.0
	_light.translation = Vector3(0, CENTER_Y, 0)
	add_child(_light)
	var sparks := preload("res://scripts/SpriteCreature.gd").particles(Color(0.85, 0.6, 1.0, 0.9), 30, 1.6, 2.0, 180.0, -1.0, 1.4)
	sparks.translation = Vector3(0, CENTER_Y, 0)
	add_child(sparks)


func _process(delta: float) -> void:
	_t += delta
	_ring.rotation.y = sin(_t * 0.7) * 0.6                    # the portal slowly swings
	_ring.scale = Vector3.ONE * (1.0 + sin(_t * 4.0) * 0.04)
	if used or (lifetime > 0.0 and _t > lifetime - 1.0):
		_fade = max(0.0, _fade - delta * 1.5)
		_ring.scale *= max(_fade, 0.01)
		_light.light_energy = 1.4 * _fade
		if _fade <= 0.0:
			queue_free()


func _physics_process(_delta: float) -> void:
	if used or _fade < 1.0:
		return
	var c := global_transform.origin + Vector3(0, CENTER_Y, 0)
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_dead or (p.mode != p.Mode.GROUND and p.mode != p.Mode.SWIM):
			continue
		var o: Vector3 = p.global_transform.origin + Vector3(0, 1.0, 0)
		if Vector2(o.x - c.x, o.z - c.z).length() < 1.5 and abs(o.y - c.y) < 2.4:
			p.rift_launch()
			Audio.play3d("rift_enter", c, 0.0)
			Audio.play3d("glider_open", c, -5.0, 0.7)
			if lifetime <= 0.0:
				used = true
			return

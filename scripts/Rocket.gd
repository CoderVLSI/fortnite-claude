extends Spatial
# A rocket from the Rocket Launcher: flies straight, explodes on whatever it touches (or after a few seconds). The blast is a
# Grenade that goes off at once, plus it takes buildings down piece by piece around the impact.

const GrenadeScript = preload("res://scripts/Grenade.gd")

const SPEED := 58.0
const LIFE := 4.0
const BLAST_PIECES := 4.6

var thrower = null
var velocity := Vector3.ZERO
var damage_mult := 1.0
var visual_only := false            # somebody else's rocket on another machine: same look and sound, no damage here
var _t := 0.0
var _done := false
var _trail: CPUParticles


func _ready() -> void:
	var body := MeshInstance.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.09
	cyl.height = 0.5
	cyl.radial_segments = 8
	body.mesh = cyl
	body.rotation_degrees = Vector3(90, 0, 0)               # along -Z
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.85, 0.2, 0.15)
	mat.metallic = 0.3
	body.material_override = mat
	body.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	var tip := MeshInstance.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 0.18
	cone.radial_segments = 8
	tip.mesh = cone
	tip.rotation_degrees = Vector3(-90, 0, 0)
	tip.translation = Vector3(0, 0, -0.33)
	tip.material_override = mat
	add_child(tip)
	var flame := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 0.11
	sph.height = 0.22
	sph.radial_segments = 8
	sph.rings = 4
	flame.mesh = sph
	var fm := SpatialMaterial.new()
	fm.flags_unshaded = true
	fm.albedo_color = Color(1.0, 0.75, 0.2)
	flame.material_override = fm
	flame.translation = Vector3(0, 0, 0.32)
	flame.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	_trail = preload("res://scripts/SpriteCreature.gd").particles(Color(0.85, 0.8, 0.75, 0.7), 24, 0.7, 0.4, 30.0, 0.5, 0.0)
	add_child(_trail)
	_trail.translation = Vector3(0, 0, 0.4)
	Audio.play3d("swing", global_transform.origin, 2.0, 0.45)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var from := global_transform.origin
	var to := from + velocity * delta
	var excl := [thrower] if thrower != null and is_instance_valid(thrower) and _t < 0.25 else []
	var hit := get_world().direct_space_state.intersect_ray(from, to, excl, 11)
	if velocity.length() > 0.1 and abs(velocity.normalized().y) < 0.98:
		look_at(from + velocity, Vector3.UP)
	if hit:
		global_transform.origin = hit.position
		_explode(hit.position + hit.normal * 0.3)
		return
	global_transform.origin = to
	if _t > LIFE or to.y < -5.0:
		_explode(to)


func _explode(pos: Vector3) -> void:
	_done = true
	var parent := get_parent()
	if parent == null:
		queue_free()
		return
	var g := GrenadeScript.new()
	g.thrower = thrower
	g.damage_mult = damage_mult
	g.visual_only = visual_only
	g.fuse = 0.02
	parent.add_child(g)
	g.global_transform.origin = pos
	if not visual_only:
		for w in get_tree().get_nodes_in_group("world"):
			w.break_pieces_near(pos, BLAST_PIECES)
	queue_free()

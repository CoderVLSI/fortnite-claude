extends KinematicBody
# Shared base for the player and the bots: health/shield, the pivoted character
# model with procedural limb animation, and a hitscan rifle.
#
# Subclasses call setup_fighter() from their own _ready(), and drive movement
# with move_body() from their own _physics_process().

signal died(victim, killer)
signal damaged(amount, source)
signal hit_landed(target, killed, headshot)
signal picked_up(text)

const MODEL_PATH := "res://assets/models/player.glb"
const RIFLE_PATH := "res://assets/models/rifle.glb"
const LIMB_NAMES := ["Torso", "Head", "LegL", "LegR", "ArmL", "ArmR"]

export var max_health := 100.0
export var max_shield := 100.0
export var walk_speed := 5.5
export var sprint_speed := 8.6
export var jump_speed := 8.0
export var gun_damage := 20.0
export var fire_interval := 0.11
export var mag_size := 30
export var reload_time := 1.6
export var spread_deg := 1.0

var display_name := "Fighter"
var vest_color := Color(0.30, 0.42, 0.22)
var health := 100.0
var shield := 0.0
var ammo := 30
var reserve := 90
var kills := 0
var is_dead := false
var velocity := Vector3.ZERO
var map_half := 155.0
var aim_pitch := 0.0

var model: Spatial
var weapon: Spatial
var muzzle: Spatial
var limbs := {}

var _anim := 0.0
var _fire_cd := 0.0
var _reload_left := 0.0
var _gravity := 24.0
var _tracer_mat: SpatialMaterial


func setup_fighter(fighter_name: String, color: Color) -> void:
	display_name = fighter_name
	vest_color = color
	health = max_health
	ammo = mag_size
	collision_layer = 2
	collision_mask = 1 | 2
	add_to_group("fighters")

	var capsule := CapsuleShape.new()   # Godot 3 capsules lie along Z: rotate upright
	capsule.radius = 0.38
	capsule.height = 1.0
	var cs := CollisionShape.new()
	cs.shape = capsule
	cs.transform = Transform(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.88, 0))
	add_child(cs)
	_build_model()


func _build_model() -> void:
	var scene = load(MODEL_PATH)
	if scene == null:
		model = _fallback_model()
	else:
		model = scene.instance()
	add_child(model)
	for n in LIMB_NAMES:
		var node := model.get_node_or_null(n)
		if node:
			limbs[n] = node
	var vest := SpatialMaterial.new()
	vest.albedo_color = vest_color
	vest.roughness = 0.9
	for n in ["Torso", "ArmL", "ArmR"]:
		if limbs.has(n) and limbs[n] is MeshInstance:
			limbs[n].set_surface_material(0, vest)   # surface 0 is the vest colour

	var rifle = load(RIFLE_PATH)
	if rifle != null:
		weapon = rifle.instance()
		model.add_child(weapon)
		weapon.translation = Vector3(0.17, 1.20, -0.30)
		muzzle = weapon.get_node_or_null("Muzzle")


func _fallback_model() -> Spatial:
	# Used only if the .glb assets have not been imported yet.
	var root := Spatial.new()
	var mi := MeshInstance.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.38
	cm.mid_height = 1.0
	mi.mesh = cm
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.translation = Vector3(0, 0.88, 0)
	root.add_child(mi)
	return root


# ------------------------------------------------------------------ movement

func move_body(delta: float, wish: Vector3, speed: float, want_jump: bool) -> void:
	var on_floor := is_on_floor()
	var accel := 16.0 if on_floor else 4.0
	var k: float = clamp(accel * delta, 0.0, 1.0)
	velocity.x = lerp(velocity.x, wish.x * speed, k)
	velocity.z = lerp(velocity.z, wish.z * speed, k)
	if on_floor:
		velocity.y = -2.0
		if want_jump:
			velocity.y = jump_speed
	else:
		velocity.y -= _gravity * delta
	velocity = move_and_slide(velocity, Vector3.UP, true, 4, deg2rad(52.0))
	var o := global_transform.origin
	o.x = clamp(o.x, -map_half, map_half)
	o.z = clamp(o.z, -map_half, map_half)
	if o.y < -40.0:                       # fell through the world: put back on the island
		o = Vector3(0, 40, 0)
		velocity = Vector3.ZERO
	global_transform.origin = o


func animate(delta: float) -> void:
	if is_dead or not limbs.has("LegL"):
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_anim += delta * (3.0 + speed * 1.1)
	var amount: float = clamp(speed / 3.0, 0.0, 1.0)
	var swing := sin(_anim) * 0.75 * amount
	limbs["LegL"].rotation.x = swing
	limbs["LegR"].rotation.x = -swing
	var raise := 1.25 + aim_pitch * 0.9
	if limbs.has("ArmR"):
		limbs["ArmR"].rotation.x = raise
		limbs["ArmL"].rotation.x = raise - 0.15
	if weapon:
		weapon.rotation.x = aim_pitch
	if limbs.has("Torso"):
		limbs["Torso"].translation.y = abs(sin(_anim)) * 0.03 * amount


# ------------------------------------------------------------------ combat

func tick_weapon(delta: float) -> void:
	_fire_cd = max(0.0, _fire_cd - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			var take: int = min(mag_size - ammo, reserve)
			ammo += take
			reserve -= take


func is_reloading() -> bool:
	return _reload_left > 0.0


func start_reload() -> void:
	if is_dead or _reload_left > 0.0 or ammo >= mag_size or reserve <= 0:
		return
	_reload_left = reload_time


func muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_transform.origin
	return global_transform.origin + Vector3(0, 1.3, 0)


func try_fire(aim_from: Vector3, aim_dir: Vector3) -> bool:
	if is_dead or _fire_cd > 0.0 or _reload_left > 0.0:
		return false
	if ammo <= 0:
		start_reload()
		return false
	_fire_cd = fire_interval
	ammo -= 1
	var dir := _spread(aim_dir)
	var to := aim_from + dir * 170.0
	var hit := get_world().direct_space_state.intersect_ray(aim_from, to, [self], 3)
	var end := to
	if hit:
		end = hit.position
		var target = hit.collider
		if target != null and target.has_method("take_damage"):
			var head: bool = hit.position.y > target.global_transform.origin.y + 1.42
			var was_alive: bool = not target.is_dead
			target.take_damage(gun_damage * (2.0 if head else 1.0), self)
			emit_signal("hit_landed", target, was_alive and target.is_dead, head)
	_spawn_tracer(muzzle_position(), end)
	if ammo == 0:
		start_reload()
	return true


func _spread(dir: Vector3) -> Vector3:
	var s := deg2rad(spread_deg)
	var b := Basis(Vector3.UP, rand_range(-s, s)) * Basis(Vector3.RIGHT, rand_range(-s, s))
	return b.xform(dir).normalized()


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5 or get_parent() == null:
		return
	if _tracer_mat == null:
		_tracer_mat = SpatialMaterial.new()
		_tracer_mat.flags_unshaded = true
		_tracer_mat.albedo_color = Color(1.0, 0.92, 0.5)
	var mesh := CubeMesh.new()
	mesh.size = Vector3(0.035, 0.035, length)
	var tracer := MeshInstance.new()
	tracer.mesh = mesh
	tracer.material_override = _tracer_mat
	tracer.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(tracer)
	var mid := (from + to) / 2.0
	var up := Vector3.UP if abs((to - from).normalized().y) < 0.98 else Vector3.RIGHT
	tracer.look_at_from_position(mid, to, up)
	get_tree().create_timer(0.06).connect("timeout", tracer, "queue_free")


func take_damage(amount: float, source = null) -> void:
	if is_dead:
		return
	var remaining := amount
	if shield > 0.0:
		var absorbed: float = min(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	health -= remaining
	emit_signal("damaged", amount, source)
	if health <= 0.0:
		_die(source)


func _die(killer) -> void:
	is_dead = true
	health = 0.0
	collision_layer = 0
	if killer != null and "kills" in killer and killer != self:
		killer.kills += 1
	if model:
		var tween := Tween.new()
		add_child(tween)
		tween.interpolate_property(model, "rotation:x", 0.0, -PI / 2.0, 0.6, Tween.TRANS_QUAD, Tween.EASE_OUT)
		tween.start()
	emit_signal("died", self, killer)


func heal(amount: float) -> void:
	health = min(max_health, health + amount)


func add_shield(amount: float) -> void:
	shield = min(max_shield, shield + amount)


func add_ammo(amount: int) -> void:
	reserve += amount

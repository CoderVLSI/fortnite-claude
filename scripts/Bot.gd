extends "res://scripts/Fighter.gd"
# Simple battle-royale bot: wanders the island, runs from the storm, and
# fights anything it can see (the player and other bots).

enum State { WANDER, STORM, CHASE, ATTACK }

const SIGHT_RANGE := 75.0
const ATTACK_RANGE := 48.0

var world                       # set by World before add_child (duck-typed)
var is_boss := false             # "The Warden": guards a POI with a mythic weapon
var home := Vector3.ZERO
var skill := 0.5                # 0 = clumsy, 1 = sharp
var state: int = State.WANDER
var target = null

var jump_at := 200.0            # distance along the bus route at which this bot drops
var land_target := Vector3.ZERO
var _think := 0.0
var _wander_to := Vector3.ZERO
var _react := 0.0
var _burst := 0.0
var _pause := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _avoid_t := 0.0
var _avoid_dir := 1.0
var _stuck_t := 0.0
var _nade_cd := 6.0             # seconds until this bot may throw a grenade


func _ready() -> void:
	damage_scale = 0.45 + skill * 0.2      # bots hit softer than the player's weapons
	if is_boss:
		max_health = 300.0
		max_shield = 100.0
		damage_scale = 0.85
		skill = 0.95
		home = translation
	setup_fighter(display_name, vest_color)
	_equip_loadout()
	if is_boss:
		shield = 100.0
		air_pivot.scale = Vector3(1.2, 1.2, 1.2)
	walk_speed = 4.6
	sprint_speed = 7.4
	_think = rand_range(0.0, 0.5)
	_wander_to = global_transform.origin
	connect("died", self, "_on_died")


func _equip_loadout() -> void:
	var w: Dictionary = Items.random_weapon(world.rng, 0)
	if is_boss:
		w = Items.make_weapon(["assault", "shotgun", "sniper", "smg"][world.rng.randi() % 4], Items.MYTHIC)
	give_weapon(w.id, w.rarity)
	gold = 150 if is_boss else (world.rng.randi_range(0, 8) * 5 if world.rng.randf() < 0.5 else 0)    # what you get for an elimination
	if not is_boss:                          # a few heals, and now and then a grenade or two
		var heal_id: String = ["bandage", "bandage", "mini_shield", "slurp_juice", "medkit"][world.rng.randi() % 5]
		pickup(Items.make_consumable(heal_id, 3 if heal_id == "bandage" else 1))
		if world.rng.randf() < 0.3:
			pickup(Items.make_consumable("grenade", 2))
		select_slot(_weapon_slot())
	for type in reserves.keys():
		reserves[type] = 99999
	# bots reload instantly-ish and never run dry
	spread_deg += (1.0 - skill) * 1.5


func _weapon_slot() -> int:
	for i in range(1, slots.size()):
		if slots[i] != null and slots[i].kind == "weapon":
			return i
	return 0


func _grenade_slot() -> int:
	for i in range(1, slots.size()):
		if slots[i] != null and slots[i].kind == "consumable" and Items.CONSUMABLES[slots[i].id].get("throw", false):
			return i
	return -1


# The first heal / shield item that would actually do something right now (-1 = none).
func _heal_slot() -> int:
	for i in range(1, slots.size()):
		var it = slots[i]
		if it == null or it.kind != "consumable":
			continue
		var c: Dictionary = Items.CONSUMABLES[it.id]
		if c.get("throw", false):
			continue
		if (c.heal > 0.0 and health < c.heal_cap - 10.0) or (c.shield > 0.0 and shield < c.shield_cap - 15.0):
			return i
	return -1


func _on_died(_victim, _killer) -> void:
	get_tree().create_timer(10.0).connect("timeout", self, "queue_free")


func _physics_process(delta: float) -> void:
	tick_weapon(delta)
	if is_dead:
		move_body(delta, Vector3.ZERO, 0.0, false)
		animate(delta)
		return
	if mode == Mode.SWIM:
		_swim_logic(delta)
		return
	if mode == Mode.MANTLE:
		mantle_physics(delta)
		animate(delta)
		return
	if mode != Mode.GROUND:
		_air_logic(delta)
		return
	_think -= delta
	if _think <= 0.0:
		_think = rand_range(0.25, 0.5)
		_decide()
	_nade_cd -= delta
	if state == State.WANDER and target == null and not is_boss and health < 70.0 + skill * 10.0:
		var hs: int = _heal_slot()
		if hs > 0:                           # nobody around: stand still and patch up
			if selected != hs:
				select_slot(hs)
			use_selected(delta)
			move_body(delta, Vector3.ZERO, 0.0, false)
			animate(delta)
			return
	if is_using() and (state != State.WANDER or target != null):
		cancel_use()                         # spotted someone mid-heal: back to the gun
	var held = selected_item()
	if held == null or held.kind != "weapon":
		select_slot(_weapon_slot())

	var origin := global_transform.origin
	var wish := Vector3.ZERO
	var speed := walk_speed
	var face := Vector3.ZERO
	var shoot := false

	match state:
		State.WANDER:
			wish = _flat_dir(_wander_to - origin)
			if origin.distance_to(_wander_to) < 3.0:
				_pick_wander()
			face = wish
		State.STORM:
			var c: Vector3 = world.storm.center_3d(origin.y)
			wish = _flat_dir(c - origin)
			speed = sprint_speed
			face = wish
		State.CHASE:
			if _valid(target):
				wish = _flat_dir(target.global_transform.origin - origin)
				speed = sprint_speed
				face = wish
		State.ATTACK:
			if _valid(target):
				var to_t: Vector3 = target.global_transform.origin - origin
				var dist := to_t.length()
				var fwd := _flat_dir(to_t)
				_strafe_t -= delta
				if _strafe_t <= 0.0:
					_strafe_t = rand_range(0.8, 2.4)
					_strafe = -_strafe
				var side := fwd.cross(Vector3.UP) * _strafe
				wish = side * 0.7
				var prefer: float = min(30.0, weapon_range * 0.55)
				if dist > prefer:
					wish += fwd
				elif dist < prefer * 0.4:
					wish -= fwd
				face = fwd
				if _nade_cd <= 0.0 and dist > 9.0 and dist < 24.0 and _line_of_sight(target):
					var gs: int = _grenade_slot()
					if gs > 0:
						var eye2 := origin + Vector3(0, 1.45, 0)
						var aim: Vector3 = (target.global_transform.origin + Vector3(0, 1.0, 0) - eye2).normalized()
						throw_grenade(eye2, aim, gs, 0.6)
					_nade_cd = rand_range(8.0, 16.0)
				_react -= delta
				shoot = _react <= 0.0 and _line_of_sight(target)
				if shoot:
					_burst -= delta
					if _burst <= 0.0:
						_pause = rand_range(0.4, 1.2)
						_burst = rand_range(0.6, 1.2)
					if _pause > 0.0:
						_pause -= delta
						shoot = false

	sprinting = speed > walk_speed + 0.5
	wish = _avoid_walls(wish, delta)
	var want_jump := is_on_wall() and is_on_floor() and randf() < 0.08
	var before := origin
	move_body(delta, wish, speed, want_jump)
	_check_stuck(delta, before, wish)

	if face.length() > 0.01:
		var yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, yaw, clamp(9.0 * delta, 0.0, 1.0))
	aim_pitch = 0.0
	if shoot and _valid(target):
		var eye := origin + Vector3(0, 1.45, 0)
		var chest: Vector3 = target.global_transform.origin + Vector3(0, 1.15, 0)
		var dir := (chest - eye).normalized()
		aim_pitch = asin(clamp(dir.y, -1.0, 1.0))
		try_fire(eye, dir)
	animate(delta)


func _swim_logic(delta: float) -> void:
	# head for the island centre until we can stand again
	var to := Vector3(0, 0, 0) - global_transform.origin
	to.y = 0.0
	var wish := to.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-wish.x, -wish.z), clamp(5.0 * delta, 0.0, 1.0))
	sprinting = false
	swim_physics(delta, wish, 3.4)
	aim_pitch = 0.0
	animate(delta)


func _air_logic(delta: float) -> void:
	if mode == Mode.BUS:
		follow_bus()
		if bus != null and bus.traveled >= jump_at:
			_pick_landing(bus.global_transform.origin)
			rotation.y = atan2(-(land_target.x - global_transform.origin.x), -(land_target.z - global_transform.origin.z))
			leave_bus()
		return
	var to := land_target - global_transform.origin
	to.y = 0.0
	var dist := to.length()
	if dist > 1.0:
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, clamp(4.0 * delta, 0.0, 1.0))
	air_input = Vector2(0, -1) if dist > 14.0 else Vector2(0, 1 if mode == Mode.FREEFALL else 0)
	if mode == Mode.FREEFALL and ground_distance() < DEPLOY_ALTITUDE + 10.0:
		deploy_glider()
	air_physics(delta)
	aim_pitch = 0.0
	animate(delta)


func _pick_landing(from_pos: Vector3) -> void:
	land_target = world.random_point_near(from_pos, 85.0)


func _decide() -> void:
	var origin := global_transform.origin
	if not world.storm.is_inside(origin):
		state = State.STORM
		target = null
		return
	if state == State.STORM:
		state = State.WANDER
		_pick_wander()
	if is_boss and Vector2(origin.x - home.x, origin.z - home.z).length() > 42.0:
		state = State.WANDER                 # the boss does not chase far from his post
		target = null
		_wander_to = home
		return
	if not _valid(target) or origin.distance_to(target.global_transform.origin) > SIGHT_RANGE * 1.3:
		target = _find_target(origin)
	if target == null:
		if state != State.WANDER:
			state = State.WANDER
			_pick_wander()
		return
	var dist := origin.distance_to(target.global_transform.origin)
	if dist < min(ATTACK_RANGE, weapon_range * 0.85) and _line_of_sight(target):
		if state != State.ATTACK:
			_react = rand_range(0.35, 0.9) * (1.5 - skill)
			_burst = rand_range(0.4, 0.9)
		state = State.ATTACK
	else:
		state = State.CHASE


func _find_target(origin: Vector3):
	var best = null
	var best_d := SIGHT_RANGE
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == self or f.is_dead:
			continue
		var d := origin.distance_to(f.global_transform.origin)
		if d < best_d and _line_of_sight(f):
			best_d = d
			best = f
	return best


func _valid(f) -> bool:
	return f != null and is_instance_valid(f) and not f.is_dead


func _line_of_sight(f) -> bool:
	var from := global_transform.origin + Vector3(0, 1.5, 0)
	var to: Vector3 = f.global_transform.origin + Vector3(0, 1.2, 0)
	return get_world().direct_space_state.intersect_ray(from, to, [self, f], 1).empty()


func _pick_wander() -> void:
	if is_boss:
		_wander_to = home + Vector3(world.rng.randf_range(-18.0, 18.0), 0.0, world.rng.randf_range(-18.0, 18.0))
		return
	_wander_to = world.random_point_in_safe_zone()


func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.01 else Vector3.ZERO


func _avoid_walls(wish: Vector3, delta: float) -> Vector3:
	if wish.length() < 0.01:
		return wish
	_avoid_t -= delta
	if _avoid_t <= 0.0:
		var from := global_transform.origin + Vector3(0, 0.7, 0)
		var hit := get_world().direct_space_state.intersect_ray(from, from + wish.normalized() * 2.6, [self], 1)
		if hit and abs(hit.normal.y) < 0.6:    # a wall, not the ground
			_avoid_t = 0.9
			_avoid_dir = 1.0 if randf() < 0.5 else -1.0
	if _avoid_t > 0.0:
		return wish.rotated(Vector3.UP, deg2rad(75.0) * _avoid_dir)
	return wish


func _check_stuck(delta: float, before: Vector3, wish: Vector3) -> void:
	if wish.length() > 0.1 and global_transform.origin.distance_to(before) < 0.01:
		_stuck_t += delta
		if _stuck_t > 0.5 and try_mantle(-global_transform.basis.z):
			_stuck_t = 0.0
			return
		if _stuck_t > 1.2:
			_stuck_t = 0.0
			_avoid_t = 1.0
			_avoid_dir = -_avoid_dir
			if state == State.WANDER:
				_pick_wander()
	else:
		_stuck_t = 0.0

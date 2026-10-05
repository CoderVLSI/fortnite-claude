extends "res://scripts/Fighter.gd"
# Simple battle-royale bot: wanders the island, runs from the storm, and
# fights anything it can see (the player and other bots).

enum State { WANDER, STORM, CHASE, ATTACK }

const SIGHT_RANGE := 75.0
const ATTACK_RANGE := 48.0

var world                       # set by World before add_child (duck-typed)
var boss_weapons := []           # a named boss carries these mythics (weapon ids); empty = a random mythic (the Warden)
var boss_id := "warden"
var ally_of = null                # hired as an ally: follows this fighter and fights for them
var guard := false                # a henchman: stays near its boss's post, like the boss does
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
var _storm_goal := Vector3.ZERO
var _storm_goal_center := Vector2.ZERO
var _stuck_t := 0.0
var _nade_cd := 6.0             # seconds until this bot may throw a grenade


func _ready() -> void:
	damage_scale = 0.45 + skill * 0.2      # bots hit softer than the player's weapons
	if guard:
		home = translation
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
	if is_boss:
		connect("damaged", self, "_boss_hurt")
	_think = rand_range(0.0, 0.5)
	_wander_to = global_transform.origin
	connect("died", self, "_on_died")


# Boss fights have three phases. Below 2/3 health: a fresh shield and two reinforcements. Below 1/3: enraged (faster, hits harder).
var boss_phase := 1


func _boss_hurt(_amount, _source) -> void:
	if net_owner != 0 or is_dead:
		return
	var ratio: float = health / max_health
	if boss_phase == 1 and ratio <= 0.66:
		boss_phase = 2
		shield = max_shield
		world.boss_phase_change(self, 2)
	elif boss_phase == 2 and ratio <= 0.33:
		boss_phase = 3
		damage_scale *= 1.25
		sprint_speed *= 1.2
		walk_speed *= 1.15
		world.boss_phase_change(self, 3)


func _equip_loadout() -> void:
	var w: Dictionary = Items.random_weapon(world.rng, 0)
	if is_boss:
		w = Items.make_weapon(["assault", "shotgun", "sniper", "smg"][world.rng.randi() % 4], Items.MYTHIC)
	if is_boss and not boss_weapons.empty():
		for wid in boss_weapons:
			give_weapon(wid, Items.MYTHIC)
		select_slot(_weapon_slot())
	else:
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
	for i in range(1, slots.size()):                 # tools (the Grappler) and the Shockwave Launcher are not what a bot shoots with
		if slots[i] != null and slots[i].kind == "weapon" and not Items.WEAPONS[slots[i].id].has("tool") and Items.WEAPONS[slots[i].id].get("projectile", "") != "shockwave":
			return i
	for i in range(1, slots.size()):
		if slots[i] != null and slots[i].kind == "weapon":
			return i
	return 0


# A teammate is down nearby and nobody is shooting at us: go and get them up.
var _mate_t := 0.0
var _mate = null
var _revive_t := 0.0


func _revive_task(delta: float) -> bool:
	_mate_t -= delta
	if _mate_t <= 0.0:
		_mate_t = 0.5
		_mate = null
		var best := 45.0
		for f in get_tree().get_nodes_in_group("fighters"):
			if f != self and f.downed and not f.is_dead and is_ally(f):
				var d: float = f.global_transform.origin.distance_to(global_transform.origin)
				if d < best:
					best = d
					_mate = f
	if _mate == null or not is_instance_valid(_mate) or not _mate.downed:
		_revive_t = 0.0
		return false
	if _valid(target) and global_transform.origin.distance_to(target.global_transform.origin) < 22.0:
		return false                                 # somebody is on us: fight first
	var to: Vector3 = _mate.global_transform.origin - global_transform.origin
	to.y = 0.0
	if to.length() > 2.3:
		_revive_t = 0.0
		var wish := to.normalized()
		sprinting = true
		move_body(delta, wish, sprint_speed, false)
		rotation.y = lerp_angle(rotation.y, atan2(-wish.x, -wish.z), clamp(9.0 * delta, 0.0, 1.0))
	else:
		move_body(delta, Vector3.ZERO, 0.0, false)
		_revive_t += delta
		if _revive_t >= REVIVE_TIME:
			_revive_t = 0.0
			revive_other(_mate)
	animate(delta)
	return true


func _grenade_slot() -> int:
	for i in range(1, slots.size()):
		if slots[i] != null and slots[i].kind == "consumable" and slots[i].id == "grenade":
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
	# in team modes a corpse stays around for the length of a reboot card, so a Reboot Van can bring the bot back
	get_tree().create_timer(125.0 if team >= 0 and not is_boss else 10.0).connect("timeout", self, "_free_if_dead")


func _free_if_dead() -> void:
	if is_dead:
		queue_free()


func _on_reboot() -> void:
	state = State.WANDER
	target = null
	_think = 0.0
	_wander_to = global_transform.origin


var _lod_acc := 0.0
var _lod_n := 0


func _physics_process(delta: float) -> void:
	tick_weapon(delta)
	if net_owner != 0:                     # on a client the host runs this bot; we only show it
		net_smooth(delta)
		animate(delta)
		return
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
	if not visible and state == State.WANDER and target == null and health >= max_health * 0.7:
		_lod_acc += delta                      # far from the camera (Perf.gd) and just wandering: move a third as often
		_lod_n += 1
		if _lod_n % 3 != 0:
			return
		delta = _lod_acc
		_lod_acc = 0.0
	_think -= delta
	if _think <= 0.0:
		_think = rand_range(0.25, 0.5)
		_decide()
	_nade_cd -= delta
	if downed:                                  # crawling about until a teammate comes
		move_body(delta, Vector3.ZERO, 0.0, false)
		animate(delta)
		return
	if boogie_t > 0.0:                          # a Boogie Bomb: dancing on the spot
		move_body(delta, Vector3.ZERO, 0.0, false)
		animate(delta)
		return
	if _revive_task(delta):
		return
	if _zip_ride(delta):
		return
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
			if ally_of != null and is_instance_valid(ally_of):
				var d_ally: float = origin.distance_to(ally_of.global_transform.origin)
				if d_ally > 14.0:                                        # catch up with the boss
					_wander_to = ally_of.global_transform.origin
					speed = sprint_speed
				if d_ally > 80.0:                                        # lost: pop back next to them
					var ap2: Vector3 = ally_of.global_transform.origin
					global_transform.origin = Vector3(ap2.x + 2.0, ap2.y + 0.5, ap2.z + 2.0)
			wish = _flat_dir(_wander_to - origin)
			if origin.distance_to(_wander_to) < 3.0:
				_pick_wander()
			face = wish
		State.STORM:
			# every bot runs to its OWN spot inside the safe zone (on dry land), so they spread out instead of queueing in one line
			var sc: Vector2 = world.storm.center
			if _storm_goal == Vector3.ZERO or _storm_goal_center.distance_to(sc) > 1.0 or Vector2(origin.x - _storm_goal.x, origin.z - _storm_goal.z).length() < 4.0:
				_storm_goal = world.random_point_in_safe_zone()
				_storm_goal_center = sc
			var c: Vector3 = _storm_goal
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

	if _zip_plan != null and target == null and (state == State.WANDER or state == State.STORM):
		var zd := Vector2(_zip_plan.pos.x - origin.x, _zip_plan.pos.z - origin.z).length()
		if zd < 2.4:
			_zip_start()
		else:
			wish = _flat_dir(_zip_plan.pos - origin)
			speed = sprint_speed
			face = wish
	sprinting = speed > walk_speed + 0.5
	var goal_dir := wish                                           # where it wants to go (the side-step below only bends the walk)
	wish = _avoid_walls(wish, delta)
	wish = _avoid_water(wish)
	var want_jump := is_on_wall() and is_on_floor() and randf() < 0.08
	var before := origin
	move_body(delta, wish, speed, want_jump)
	_check_stuck(delta, before, wish, goal_dir)

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
		_consider_zipline(origin, _storm_goal if _storm_goal != Vector3.ZERO else world.storm.center_3d(origin.y))
		return
	if state == State.STORM:
		state = State.WANDER
		_pick_wander()
	if (is_boss or guard) and Vector2(origin.x - home.x, origin.z - home.z).length() > 42.0:
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
		_consider_zipline(origin, _wander_to)
		return
	var dist := origin.distance_to(target.global_transform.origin)
	if dist < min(ATTACK_RANGE, weapon_range * 0.85) and _line_of_sight(target):
		if state != State.ATTACK:
			_react = rand_range(0.35, 0.9) * (1.5 - skill)
			_burst = rand_range(0.4, 0.9)
		state = State.ATTACK
	else:
		state = State.CHASE


# ---------------------------------------------------------------- water and ziplines

# Do not walk off a beach into deep water: bend away from it towards higher ground (only when we are on dry land ourselves).
func _avoid_water(wish: Vector3) -> Vector3:
	if wish.length() < 0.01 or mode != Mode.GROUND:
		return wish
	var o := global_transform.origin
	var tr = world.terrain
	if tr.height_at(o.x, o.z) < 0.4:
		return wish                                    # already wading: keep going
	var d := wish.normalized()
	var ahead := o + d * 5.0
	if tr.height_at(ahead.x, ahead.z) > -0.7:
		return wish
	var best := wish
	var best_h := -99.0
	for ang in [50.0, -50.0, 95.0, -95.0]:
		var dir := d.rotated(Vector3.UP, deg2rad(ang))
		var q := o + dir * 5.0
		var h: float = tr.height_at(q.x, q.z)
		if h > best_h:
			best_h = h
			best = dir
	return best if best_h > -0.7 else wish


var _zip_plan = null              # {line, end, pos} a pole we are walking to
var _zip_run = null              # while riding: {line, from, to, t}
var _zip_cd := 0.0


# Called every think: with somewhere far to go and a zipline nearby that gets us closer, walk to the pole.
func _consider_zipline(origin: Vector3, goal: Vector3) -> void:
	_zip_cd -= 0.35
	if _zip_run != null or _zip_cd > 0.0 or is_boss or guard or ally_of != null or world.ziplines.empty():
		return
	if _zip_plan != null:
		if Vector2(origin.x - _zip_plan.pos.x, origin.z - _zip_plan.pos.z).length() > 60.0:
			_zip_plan = null
		return
	var goal_d := Vector2(origin.x - goal.x, origin.z - goal.z).length()
	if goal_d < 120.0:
		return
	for z in world.ziplines:
		for e in range(2):
			var st = z.stations[e]
			var sp: Vector3 = st.global_transform.origin
			if Vector2(origin.x - sp.x, origin.z - sp.z).length() > 45.0:
				continue
			var far: Vector3 = z.stations[1 - e].global_transform.origin
			if goal_d - Vector2(far.x - goal.x, far.z - goal.z).length() > 70.0:
				_zip_plan = {"line": z, "end": e, "pos": sp}
				return
	_zip_cd = 6.0


func _zip_start() -> void:
	var z = _zip_plan.line
	var e: int = _zip_plan.end
	_zip_plan = null
	if z.busy():
		_zip_cd = 4.0
		return
	z.bots_riding += 1
	_zip_run = {"line": z, "from": z.a if e == 0 else z.b, "to": z.b if e == 0 else z.a, "t": 0.0}
	Audio.play3d("door", global_transform.origin, 0.0, 1.4)


# Rides the cable like a player would (teleporting along it). Returns true while riding.
func _zip_ride(delta: float) -> bool:
	if _zip_run == null:
		return false
	var r: Dictionary = _zip_run
	var span: float = r.from.distance_to(r.to)
	r.t += 18.0 * delta
	if r.t >= span or is_dead:
		var dir: Vector3 = (r.to - r.from).normalized()
		var gx: float = r.to.x + dir.x * 1.5
		var gz: float = r.to.z + dir.z * 1.5
		global_transform.origin = Vector3(gx, world.terrain.height_at(gx, gz) + 1.0, gz)
		velocity = Vector3.ZERO
		r.line.bots_riding = max(0, r.line.bots_riding - 1)
		_zip_run = null
		_zip_cd = 12.0
		return false
	global_transform.origin = r.from + (r.to - r.from) * (r.t / span) + Vector3(0, -2.0, 0)
	velocity = Vector3.ZERO
	return true


func _find_target(origin: Vector3):
	var best = null
	var best_d := SIGHT_RANGE
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == self or f.is_dead or is_ally(f):
			continue
		var d := origin.distance_to(f.global_transform.origin)
		if f.cloak_t > 0.0 and d > 7.0:          # a Ghost Sprite's cloak hides you from afar
			continue
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
	if ally_of != null and is_instance_valid(ally_of):
		var ap: Vector3 = ally_of.global_transform.origin
		_wander_to = ap + Vector3(world.rng.randf_range(-6.0, 6.0), 0.0, world.rng.randf_range(-6.0, 6.0))
		return
	if is_boss or guard:
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


# Slow-progress watchdog: bots that walk into a big mountain or a cliff and just keep pushing do not give up. After a couple of
# seconds without real progress they hop and sidestep; after four they are lifted over the obstacle in the direction they wanted.
var _prog_pos := Vector3.ZERO
var _prog_t := 0.0
var _prog_fail := 0


func _progress_watch(delta: float, wish: Vector3, goal: Vector3 = Vector3.ZERO) -> void:
	if state == State.ATTACK or wish.length() < 0.1 or mode != Mode.GROUND:
		_prog_t = 0.0
		_prog_fail = 0
		_prog_pos = global_transform.origin
		return
	_prog_t += delta
	if _prog_t < 1.0:
		return
	_prog_t = 0.0
	var o := global_transform.origin
	var moved := Vector2(o.x - _prog_pos.x, o.z - _prog_pos.z).length()
	if goal.length() > 0.1:                                      # sliding sideways along a cliff is not progress: count the way towards the goal
		var gd := goal.normalized()
		moved = min(moved, max(0.0, (o.x - _prog_pos.x) * gd.x + (o.z - _prog_pos.z) * gd.z) * 1.6)
	_prog_pos = o
	if moved > 1.8:
		_prog_fail = 0
		return
	_prog_fail += 1
	if _prog_fail >= 2:
		_avoid_t = 1.3
		_avoid_dir = -_avoid_dir
		if is_on_floor():
			velocity.y = 7.5                                     # a hop
		try_mantle(wish)
	var storm_run: bool = state == State.STORM                    # in the storm every second counts: lift sooner and further
	if _prog_fail >= (2 if storm_run else 4):                    # lifted over the mountain / ledge towards where it wanted to go
		_prog_fail = 0
		var dir := (goal if goal.length() > 0.1 else wish).normalized()
		var np := o + dir * (18.0 if storm_run else 9.0)
		var lim: float = world.MAP_HALF - 8.0
		np.x = clamp(np.x, -lim, lim)
		np.z = clamp(np.z, -lim, lim)
		global_transform.origin = Vector3(np.x, world.terrain.height_at(np.x, np.z) + 1.4, np.z)
		velocity = Vector3.ZERO


func _check_stuck(delta: float, before: Vector3, wish: Vector3, goal: Vector3) -> void:
	_progress_watch(delta, wish, goal)
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

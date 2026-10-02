extends KinematicBody
# Shared base for the player and the bots: health/shield, a pivoted character
# model with procedural limb animation, a 5-slot inventory (pickaxe, weapons with
# rarity, heal/shield consumables), hitscan weapons and the bus / freefall / glider
# movement states.
#
# Subclasses call setup_fighter() from their own _ready(), and drive movement with
# move_body() (ground) or air_physics() (freefall / glider) from _physics_process().

const Items = preload("res://scripts/Items.gd")

signal died(victim, killer)
signal damaged(amount, source)
signal hit_landed(target, killed, headshot)
signal picked_up(text)
signal slot_changed
signal landed

enum Mode { GROUND, BUS, FREEFALL, GLIDE }

const MODEL_PATH := "res://assets/models/player.glb"
const GLIDER_PATH := "res://assets/models/glider.glb"
const LIMB_NAMES := ["Torso", "Head", "LegL", "LegR", "ArmL", "ArmR"]
const HAND_POS := Vector3(0.17, 1.20, -0.30)
const DEPLOY_ALTITUDE := 75.0

export var max_health := 100.0
export var max_shield := 100.0
export var walk_speed := 5.5
export var sprint_speed := 8.6
export var jump_speed := 8.0

var display_name := "Fighter"
var vest_color := Color(0.30, 0.42, 0.22)
var health := 100.0
var shield := 0.0
var kills := 0
var is_dead := false
var velocity := Vector3.ZERO
var map_half := 155.0
var aim_pitch := 0.0
var damage_scale := 1.0

# inventory
var slots := []
var selected := 0
var reserves := {"light": 0, "medium": 0, "shells": 0, "heavy": 0}
var materials := {"wood": 0, "stone": 0, "metal": 0}

# stats of the selected item (filled by _apply_selected)
var gun_damage := 20.0
var fire_interval := 0.5
var mag_size := 0
var reload_time := 1.5
var spread_deg := 1.0
var pellets := 1
var automatic := false
var ammo_type := ""
var weapon_range := 100.0
var head_mult := 2.0

# movement state
var mode: int = Mode.GROUND
var bus = null
var air_input := Vector2.ZERO     # x = right, y = back; set by the controller each frame

var model: Spatial
var air_pivot: Spatial
var glider: Spatial
var held: Spatial
var muzzle: Spatial
var limbs := {}

var _anim := 0.0
var _swing := 0.0
var _fire_cd := 0.0
var _reload_left := 0.0
var _use_left := 0.0
var _use_total := 0.0
var _gravity := 24.0
var _tracer_mat: SpatialMaterial


func setup_fighter(fighter_name: String, color: Color) -> void:
	display_name = fighter_name
	vest_color = color
	health = max_health
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
	slots = [Items.pickaxe(), null, null, null, null]
	_apply_selected()


func _build_model() -> void:
	# air_pivot sits at the body centre so the diving pose rotates around it;
	# model hangs below it so its own origin stays at the feet (death tip-over).
	air_pivot = Spatial.new()
	air_pivot.name = "AirPivot"
	air_pivot.translation = Vector3(0, 0.9, 0)
	add_child(air_pivot)
	var scene = load(MODEL_PATH)
	model = scene.instance() if scene != null else _fallback_model()
	model.translation = Vector3(0, -0.9, 0)
	air_pivot.add_child(model)
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

	var gl = load(GLIDER_PATH)
	if gl != null:
		glider = gl.instance()
		glider.visible = false
		model.add_child(glider)


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


# ------------------------------------------------------------------ inventory

func selected_item():
	return slots[selected] if selected < slots.size() else null


func select_slot(index: int) -> void:
	if index < 0 or index >= slots.size() or index == selected or is_dead:
		return
	selected = index
	_apply_selected()


func cycle_slot(direction: int) -> void:
	# skip empty slots
	for i in range(1, slots.size() + 1):
		var idx := int(posmod(selected + direction * i, slots.size()))
		if slots[idx] != null:
			select_slot(idx)
			return


func _apply_selected() -> void:
	_reload_left = 0.0
	_use_left = 0.0
	pellets = 1
	automatic = false
	ammo_type = ""
	mag_size = 0
	var item = selected_item()
	if item != null and item.kind == "weapon":
		var s: Dictionary = Items.weapon_stats(item)
		gun_damage = s.damage * damage_scale
		fire_interval = s.interval
		mag_size = s.mag
		reload_time = s.reload
		spread_deg = s.spread
		pellets = s.pellets
		automatic = s.auto
		ammo_type = s.ammo
		weapon_range = s.range
		head_mult = s.head
	elif item != null and item.kind == "pickaxe":
		gun_damage = 20.0 * damage_scale
		fire_interval = 0.55
		weapon_range = 3.4
		automatic = true
	_equip_model(item)
	emit_signal("slot_changed")


func _equip_model(item) -> void:
	if held:
		held.queue_free()
		held = null
		muzzle = null
	if item == null or model == null:
		return
	var scene = load(Items.model_of(item))
	if scene == null:
		return
	held = scene.instance()
	model.add_child(held)
	held.translation = HAND_POS
	if item.kind == "consumable":
		held.scale = Vector3(1.5, 1.5, 1.5)
		held.translation = Vector3(0.12, 1.15, -0.38)
	elif item.kind == "pickaxe":
		held.translation = Vector3(0.20, 1.05, -0.28)
	muzzle = held.get_node_or_null("Muzzle")


func get_ammo() -> int:
	var item = selected_item()
	return item.mag if item != null and item.kind == "weapon" else 0


func get_reserve() -> int:
	return reserves[ammo_type] if ammo_type != "" else 0


func add_ammo(amount: int, type: String = "medium") -> void:
	reserves[type] = int(min(reserves[type] + amount, 999))


func give_weapon(id: String, rarity: int = 0, fill_reserve: int = 0) -> void:
	# Helper for bots/tests: put a weapon into the first free slot and select it.
	var item := Items.make_weapon(id, rarity)
	var res: Dictionary = pickup(item)
	if res.ok:
		for i in range(1, slots.size()):
			var s = slots[i]
			if s != null and s.kind == "weapon" and s.id == id and s.rarity == rarity:
				select_slot(i)
				break
	if fill_reserve > 0:
		add_ammo(fill_reserve, Items.WEAPONS[id].ammo)


# Try to put an item in the inventory. Returns {ok, text, dropped (item or null)}.
func pickup(item: Dictionary) -> Dictionary:
	match item.kind:
		"ammo":
			add_ammo(item.count, item.id)
			return {"ok": true, "text": "+%d %s" % [item.count, Items.AMMO[item.id].name], "dropped": null}
		"weapon":
			for i in range(1, slots.size()):
				if slots[i] == null:
					slots[i] = item
					if selected == 0:
						select_slot(i)
					emit_signal("slot_changed")
					return {"ok": true, "text": Items.name_of(item), "dropped": null}
			if selected > 0 and slots[selected] != null and slots[selected].kind == "weapon":
				var old = slots[selected]
				slots[selected] = item
				_apply_selected()
				return {"ok": true, "text": Items.name_of(item), "dropped": old}
			return {"ok": false, "text": "Inventory full", "dropped": null}
		"consumable":
			var cap: int = Items.CONSUMABLES[item.id].stack
			var remaining: int = item.count
			for i in range(1, slots.size()):
				var s = slots[i]
				if s != null and s.kind == "consumable" and s.id == item.id and s.count < cap:
					var add: int = int(min(cap - s.count, remaining))
					s.count += add
					remaining -= add
			if remaining > 0:
				for i in range(1, slots.size()):
					if slots[i] == null:
						slots[i] = Items.make_consumable(item.id, int(min(cap, remaining)))
						remaining -= int(min(cap, remaining))
						break
			emit_signal("slot_changed")
			if remaining == item.count:
				return {"ok": false, "text": "Inventory full", "dropped": null}
			var leftover = null
			if remaining > 0:
				leftover = Items.make_consumable(item.id, remaining)
			return {"ok": true, "text": Items.name_of(item), "dropped": leftover}
	return {"ok": false, "text": "", "dropped": null}


func add_material(kind: String, amount: int) -> void:
	materials[kind] = int(min(materials[kind] + amount, 999))


# ------------------------------------------------------------------ consumables

func is_using() -> bool:
	return _use_left > 0.0


func use_progress() -> float:
	return 0.0 if _use_total <= 0.0 or _use_left <= 0.0 else 1.0 - _use_left / _use_total


func can_use_selected() -> bool:
	var item = selected_item()
	if item == null or item.kind != "consumable":
		return false
	var c: Dictionary = Items.CONSUMABLES[item.id]
	return (c.heal > 0.0 and health < c.heal_cap) or (c.shield > 0.0 and shield < c.shield_cap)


# Call every frame while the player holds "fire" with a consumable selected.
func use_selected(delta: float) -> void:
	if is_dead or mode != Mode.GROUND or not can_use_selected():
		cancel_use()
		return
	var item = selected_item()
	var c: Dictionary = Items.CONSUMABLES[item.id]
	if _use_left <= 0.0:
		_use_total = c.time
		_use_left = c.time
	_use_left -= delta
	if _use_left <= 0.0:
		_use_left = 0.0
		if c.heal > 0.0:
			health = min(c.heal_cap, health + c.heal)
		if c.shield > 0.0:
			shield = min(c.shield_cap, shield + c.shield)
		item.count -= 1
		emit_signal("picked_up", "Used " + c.name)
		if item.count <= 0:
			slots[selected] = null
			selected = 0
			_apply_selected()
		else:
			emit_signal("slot_changed")


func cancel_use() -> void:
	_use_left = 0.0


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
	_clamp_to_map()


func _clamp_to_map() -> void:
	var o := global_transform.origin
	o.x = clamp(o.x, -map_half, map_half)
	o.z = clamp(o.z, -map_half, map_half)
	if o.y < -40.0:                       # fell through the world: put back on the island
		o = Vector3(0, 40, 0)
		velocity = Vector3.ZERO
	global_transform.origin = o


# ------------------------------------------------------------------ bus / freefall / glider

func enter_bus(bus_node) -> void:
	bus = bus_node
	mode = Mode.BUS
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if air_pivot:
		air_pivot.visible = false


func leave_bus() -> void:
	if mode != Mode.BUS:
		return
	mode = Mode.FREEFALL
	collision_layer = 2
	collision_mask = 1 | 2
	if air_pivot:
		air_pivot.visible = true
	var drift: Vector3 = bus.direction * 8.0 if bus != null else Vector3.ZERO
	velocity = drift + Vector3(0, -6.0, 0)
	bus = null


func follow_bus() -> void:
	if bus != null:
		global_transform.origin = bus.seat_position()


func ground_distance() -> float:
	var o := global_transform.origin
	var hit := get_world().direct_space_state.intersect_ray(o, o + Vector3(0, -600, 0), [self], 1)
	return o.distance_to(hit.position) if hit else 999.0


func deploy_glider() -> void:
	if mode != Mode.FREEFALL:
		return
	mode = Mode.GLIDE
	if glider:
		glider.visible = true
		glider.scale = Vector3(0.2, 0.2, 0.2)
		var tween := Tween.new()
		add_child(tween)
		tween.interpolate_property(glider, "scale", Vector3(0.2, 0.2, 0.2), Vector3.ONE, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
		tween.start()


func _land() -> void:
	mode = Mode.GROUND
	if glider:
		glider.visible = false
	velocity = Vector3(0, -2.0, 0)
	emit_signal("landed")


# Freefall / glide step. The controller sets air_input (x right, y back) first.
func air_physics(delta: float) -> void:
	var b := global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var wish := b.x * air_input.x + fwd * (-air_input.y)
	var dive := air_input.y < -0.5
	var flare := air_input.y > 0.5
	var target := Vector3.ZERO
	var fall := 0.0
	if mode == Mode.FREEFALL:
		target = wish * (20.0 if dive else 11.0)
		fall = 52.0 if dive else (30.0 if flare else 42.0)
	else:
		target = wish * (21.0 if dive else (9.0 if flare else 15.0))
		fall = 14.0 if dive else (7.0 if flare else 10.0)
	velocity.x = lerp(velocity.x, target.x, clamp(2.5 * delta, 0.0, 1.0))
	velocity.z = lerp(velocity.z, target.z, clamp(2.5 * delta, 0.0, 1.0))
	velocity.y = lerp(velocity.y, -fall, clamp(1.6 * delta, 0.0, 1.0))
	velocity = move_and_slide(velocity, Vector3.UP)
	_clamp_to_map()
	if mode == Mode.FREEFALL and ground_distance() < DEPLOY_ALTITUDE:
		deploy_glider()
	if is_on_floor():
		_land()


func _air_pose(delta: float) -> void:
	if air_pivot == null:
		return
	var tilt := 0.0
	var roll := 0.0
	if mode == Mode.FREEFALL:
		tilt = -1.25 if air_input.y <= 0.5 else -0.7
		roll = -air_input.x * 0.35
	elif mode == Mode.GLIDE:
		tilt = -0.12 + (-0.2 if air_input.y < -0.5 else 0.0)
		roll = -air_input.x * 0.25
	var k: float = clamp(6.0 * delta, 0.0, 1.0)
	air_pivot.rotation.x = lerp(air_pivot.rotation.x, tilt, k)
	air_pivot.rotation.z = lerp(air_pivot.rotation.z, roll, k)


# ------------------------------------------------------------------ animation

func animate(delta: float) -> void:
	if is_dead or not limbs.has("LegL"):
		return
	_air_pose(delta)
	_swing = max(0.0, _swing - delta)
	if mode == Mode.FREEFALL:
		limbs["LegL"].rotation.x = 0.25
		limbs["LegR"].rotation.x = 0.1
		limbs["ArmR"].rotation.x = -0.6
		limbs["ArmL"].rotation.x = -0.6
		return
	if mode == Mode.GLIDE:
		limbs["LegL"].rotation.x = 0.1
		limbs["LegR"].rotation.x = 0.1
		limbs["ArmR"].rotation.x = 2.7
		limbs["ArmL"].rotation.x = 2.7
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_anim += delta * (3.0 + speed * 1.1)
	var amount: float = clamp(speed / 3.0, 0.0, 1.0)
	var swing := sin(_anim) * 0.75 * amount
	limbs["LegL"].rotation.x = swing
	limbs["LegR"].rotation.x = -swing
	var item = selected_item()
	var raise := 1.25 + aim_pitch * 0.9
	if item != null and item.kind == "pickaxe":
		raise = 0.55 + (sin(_swing / 0.3 * PI) * 1.5 if _swing > 0.0 else 0.0)
	elif item == null or item.kind == "consumable":
		raise = 0.9
	limbs["ArmR"].rotation.x = raise
	limbs["ArmL"].rotation.x = raise - 0.15 if (item != null and item.kind == "weapon") else swing * -0.6
	if held and item != null and item.kind == "weapon":
		held.rotation.x = aim_pitch
	elif held:
		held.rotation.x = 0.0
	if limbs.has("Torso"):
		limbs["Torso"].translation.y = abs(sin(_anim)) * 0.03 * amount


# ------------------------------------------------------------------ combat

func tick_weapon(delta: float) -> void:
	_fire_cd = max(0.0, _fire_cd - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			var item = selected_item()
			if item != null and item.kind == "weapon":
				var take: int = int(min(mag_size - item.mag, reserves[ammo_type]))
				item.mag += take
				reserves[ammo_type] -= take


func is_reloading() -> bool:
	return _reload_left > 0.0


func start_reload() -> void:
	var item = selected_item()
	if is_dead or item == null or item.kind != "weapon" or _reload_left > 0.0:
		return
	if item.mag >= mag_size or reserves[ammo_type] <= 0:
		return
	_reload_left = reload_time


func muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_transform.origin
	return global_transform.origin + Vector3(0, 1.3, 0)


func try_fire(aim_from: Vector3, aim_dir: Vector3) -> bool:
	if is_dead or mode != Mode.GROUND or _fire_cd > 0.0 or _reload_left > 0.0 or _use_left > 0.0:
		return false
	var item = selected_item()
	if item == null:
		return false
	if item.kind == "pickaxe":
		return _swing_pickaxe(aim_from, aim_dir)
	if item.kind != "weapon":
		return false
	if item.mag <= 0:
		start_reload()
		return false
	_fire_cd = fire_interval
	item.mag -= 1
	for i in range(pellets):
		_fire_ray(aim_from, aim_dir, i < 3)
	if item.mag == 0:
		start_reload()
	return true


func _fire_ray(aim_from: Vector3, aim_dir: Vector3, show_tracer: bool) -> void:
	var dir := _spread(aim_dir)
	var to := aim_from + dir * weapon_range
	var hit := get_world().direct_space_state.intersect_ray(aim_from, to, [self], 3)
	var end := to
	if hit:
		end = hit.position
		var target = hit.collider
		if target != null and target.has_method("take_damage"):
			var head: bool = hit.position.y > target.global_transform.origin.y + 1.42
			var was_alive: bool = not target.is_dead
			var falloff: float = 1.0 - 0.35 * clamp(aim_from.distance_to(hit.position) / weapon_range, 0.0, 1.0)
			target.take_damage(gun_damage * falloff * (head_mult if head else 1.0), self)
			emit_signal("hit_landed", target, was_alive and target.is_dead, head)
	if show_tracer:
		_spawn_tracer(muzzle_position(), end)


func _swing_pickaxe(aim_from: Vector3, aim_dir: Vector3) -> bool:
	_fire_cd = fire_interval
	_swing = 0.3
	var hit := get_world().direct_space_state.intersect_ray(aim_from, aim_from + aim_dir * weapon_range, [self], 3)
	if not hit:
		return true
	var target = hit.collider
	if target != null and target.has_method("take_damage"):
		var was_alive: bool = not target.is_dead
		target.take_damage(gun_damage, self)
		emit_signal("hit_landed", target, was_alive and target.is_dead, false)
	elif target != null and target.has_meta("harvest"):
		for w in get_tree().get_nodes_in_group("world"):
			w.harvest_hit(target, hit.shape, target.get_meta("harvest"), self)
	return true


func _spread(dir: Vector3) -> Vector3:
	if spread_deg <= 0.0:
		return dir
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
	if is_dead or mode == Mode.BUS:
		return
	cancel_use()
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
	mode = Mode.GROUND
	if glider:
		glider.visible = false
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

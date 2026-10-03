extends KinematicBody
# Shared base for the player and the bots: health/shield, a pivoted character
# model with procedural limb animation, a 5-slot inventory (pickaxe, weapons with
# rarity, heal/shield consumables), hitscan weapons and the bus / freefall / glider
# movement states.
#
# Subclasses call setup_fighter() from their own _ready(), and drive movement with
# move_body() (ground) or air_physics() (freefall / glider) from _physics_process().

const Items = preload("res://scripts/Items.gd")
const Animator = preload("res://scripts/Animator.gd")

signal died(victim, killer)
signal damaged(amount, source)
signal hit_landed(target, killed, headshot)
signal picked_up(text)
signal damage_dealt(pos, amount, headshot, killed)    # for the HUD's floating damage numbers
signal harvested(pos, fraction, kind, label, id)   # a pickaxe hit on a tree / rock / build piece: what is left (0 = gone)
signal slot_changed
signal sprite_changed
signal landed

enum Mode { GROUND, BUS, FREEFALL, GLIDE, SWIM, MANTLE, VEHICLE }

const MODEL_PATH := "res://assets/models/player.glb"
const Grenade = preload("res://scripts/Grenade.gd")
const Rift = preload("res://scripts/Rift.gd")
const Sprites = preload("res://scripts/Sprites.gd")
const SpriteCreature = preload("res://scripts/SpriteCreature.gd")
const FALL_SAFE_SPEED := 19.0          # landing faster than this hurts (about a 7 m drop)
const FALL_DAMAGE_PER_MS := 3.5
const GLIDER_PATH := "res://assets/models/glider.glb"
const DEPLOY_ALTITUDE := 75.0
const WATER_LEVEL := 0.0
const BODY_MASK := 1 | 2 | 8          # world, fighters, vehicles
const SWIM_ENTER := -0.75          # feet below this -> swimming (depth > 0.75 m)
const SWIM_EXIT := -0.55           # feet above this while on the floor -> wading again
const SWIM_FEET_Y := -1.05         # swimmers float with their feet this far below the surface
const MANTLE_MAX := 2.3
const MANTLE_MIN := 0.7
const MANTLE_MAX_FROM_GROUND := 2.6   # a jump does not let you climb a higher wall

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
var last_item_slot := 1           # the last non-pickaxe slot held: where a swap goes when the pickaxe is out
var reserves := {"light": 0, "medium": 0, "shells": 0, "heavy": 0}
var materials := {"wood": 0, "stone": 0, "metal": 0}
var gold := 0                     # gold bars: spent at vending machines
var sprite := {}                  # the equipped Sprite: {id, variant, level, xp} (empty = none)
var cloak_t := 0.0                # Ghost Sprite: seconds of cloak left (bots lose you beyond arm's length)
var unlimited_t := 0.0            # Punk Sprite: seconds of unlimited ammo left
var bubble_t := 0.0               # Aegis Sprite: seconds of protective bubble left
var _sprite_model: Spatial
var _burst_acc := 0.0
var _in_burst := false
var _srng := RandomNumberGenerator.new()

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
var animator
var grounded := true
var forward_speed := 0.0
var sprinting := false
var crouching := false            # hold crouch: slower, lower, steadier aim
var sliding := false              # sprint then crouch: a short momentum slide
var emoting := false              # dancing: cancelled by moving, firing or jumping
var emote_t := 0.0
var _slide_t := 0.0
var _slide_dir := Vector3.ZERO
var aiming := false               # aim-down-sights (player only; see Player._update_aim)
var vehicle = null
var vehicle_seat := 0
var vehicle_steer := 0.0
var vehicle_hands_on_wheel := true
var _mantle_t := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_dir := Vector3.FORWARD
var _mantle_dur := 0.6
var _mantle_cd := 0.0
var _ripple_t := 0.0
var _stroke_sign := 1.0
var _use_snd_t := 0.0
var _hurt_cd := 0.0
var _was_grounded := true

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
	collision_mask = BODY_MASK
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
	# air_pivot sits at the body centre so the diving / swimming pose rotates around it;
	# model hangs below it so its own origin stays at the feet (death tip-over).
	air_pivot = Spatial.new()
	air_pivot.name = "AirPivot"
	air_pivot.translation = Vector3(0, 0.9, 0)
	add_child(air_pivot)
	var scene = load(MODEL_PATH)
	model = scene.instance() if scene != null else _fallback_model()
	model.translation = Vector3(0, -0.9, 0)
	air_pivot.add_child(model)
	animator = Animator.new()
	animator.setup(model)
	var vest := SpatialMaterial.new()
	vest.albedo_color = vest_color
	vest.roughness = 0.9
	for n in ["TorsoMesh", "UpperArmL", "UpperArmR"]:
		var node := model.find_node(n, true, false)
		if node != null and node is MeshInstance:
			node.set_surface_material(0, vest)   # surface 0 is the vest colour

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
	if index > 0:
		last_item_slot = index
	_apply_selected()


# Which slot a full-inventory pickup replaces: the item in hand, or (pickaxe out) the last item held.
func swap_slot() -> int:
	if selected > 0 and slots[selected] != null:
		return selected
	if last_item_slot > 0 and last_item_slot < slots.size() and slots[last_item_slot] != null:
		return last_item_slot
	for i in range(1, slots.size()):
		if slots[i] != null:
			return i
	return -1


# Put `item` into slot t (dropping whatever was there) and equip it.
func _swap_into(t: int, item: Dictionary):
	var old = slots[t]
	slots[t] = item
	selected = t
	last_item_slot = t
	_apply_selected()
	return old


# Move an item between two item slots (an empty target just moves it). The same item stays equipped.
func swap_slots(a: int, b: int) -> bool:
	if is_dead or a == b or a < 1 or b < 1 or a >= slots.size() or b >= slots.size():
		return false
	if slots[a] == null and slots[b] == null:
		return false
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	if selected == a:
		selected = b
	elif selected == b:
		selected = a
	if last_item_slot == a:
		last_item_slot = b
	elif last_item_slot == b:
		last_item_slot = a
	emit_signal("slot_changed")
	return true


# Drop the item in slot i on the ground in front of the character. The pickaxe cannot be dropped.
func drop_slot(i: int) -> bool:
	if is_dead or i <= 0 or i >= slots.size() or slots[i] == null:
		return false
	var it: Dictionary = slots[i]
	slots[i] = null
	if selected == i:
		selected = 0
		_apply_selected()
	else:
		emit_signal("slot_changed")
	var fwd := -global_transform.basis.z
	for w in get_tree().get_nodes_in_group("world"):
		w.spawn_item(it, global_transform.origin + fwd * 1.6 + Vector3(0, 0.3, 0))
	Audio.play3d("loot_pickup", global_transform.origin, -8.0, 0.8)
	return true


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
	var hand: Node = animator.nodes.get("HandR", model) if animator != null else model
	hand.add_child(held)
	held.translation = Vector3(0, -0.02, -0.04)
	if item.kind == "consumable":
		held.scale = Vector3(0.75, 0.75, 0.75)
	else:
		held.scale = Vector3(1.0, 1.0, 1.0)
	Items.apply_accent(held, Items.color_of(item))
	muzzle = held.get_node_or_null("Muzzle")


func get_ammo() -> int:
	var item = selected_item()
	return item.mag if item != null and item.kind == "weapon" else 0


func get_reserve() -> int:
	return reserves[ammo_type] if ammo_type != "" else 0


func add_ammo(amount: int, type: String = "medium") -> void:
	if sprite.get("variant", "") == "galaxy":
		amount = int(ceil(amount * 1.3))
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
		"gold":
			gold += item.count
			return {"ok": true, "text": "+%d Gold" % item.count, "dropped": null}
		"material":
			add_material(item.id, item.count)
			return {"ok": true, "text": "+%d %s" % [item.count, Items.MATERIAL_NAMES[item.id]], "dropped": null}
		"weapon":
			for i in range(1, slots.size()):
				if slots[i] == null:
					slots[i] = item
					if selected == 0:
						select_slot(i)
					emit_signal("slot_changed")
					return {"ok": true, "text": Items.name_of(item), "dropped": null}
			var t := swap_slot()          # full: the new weapon replaces the item in hand (or the last one held)
			if t > 0:
				var old = _swap_into(t, item)
				return {"ok": true, "text": "Swapped: " + Items.name_of(item), "dropped": old}
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
			var swapped = null
			if remaining > 0:             # no room: replace the item in hand (not another stack of the same thing)
				var t := swap_slot()
				if t > 0 and not (slots[t].kind == "consumable" and slots[t].id == item.id):
					var take: int = int(min(cap, remaining))
					swapped = _swap_into(t, Items.make_consumable(item.id, take))
					remaining -= take
			if remaining == item.count:
				return {"ok": false, "text": "Inventory full", "dropped": null}
			var leftover = null
			if remaining > 0:
				leftover = Items.make_consumable(item.id, remaining)
			if swapped != null:
				return {"ok": true, "text": "Swapped: " + Items.name_of(item), "dropped": swapped, "dropped2": leftover}
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
		_use_snd_t = 0.0
	_use_snd_t -= delta
	if _use_snd_t <= 0.0:
		_use_snd_t = 0.95
		Audio.play3d("consume_bandage" if item.id == "bandage" or item.id == "medkit" else "consume_potion", global_transform.origin + Vector3(0, 1.2, 0), -6.0)
	_use_left -= delta
	if _use_left <= 0.0:
		_use_left = 0.0
		if c.heal > 0.0:
			health = min(c.heal_cap, health + c.heal)
		if c.shield > 0.0:
			shield = min(c.shield_cap, shield + c.shield)
		if has_sprite("aegis") and (c.heal > 0.0 or c.shield > 0.0):
			bubble_t = 3.0 + sprite_level()
			emit_signal("picked_up", "Aegis bubble up!")
		item.count -= 1
		Audio.play3d("shield_up" if c.shield > 0.0 else "heal_up", global_transform.origin + Vector3(0, 1.2, 0), -3.0)
		emit_signal("picked_up", "Used " + c.name)
		if item.count <= 0:
			slots[selected] = null
			selected = 0
			_apply_selected()
		else:
			emit_signal("slot_changed")


# A throwable (grenade) is thrown instantly with "fire"; the rest of the stack stays in the slot.
func is_throwable_selected() -> bool:
	var item = selected_item()
	return item != null and item.kind == "consumable" and Items.CONSUMABLES[item.id].get("throw", false)


func throw_grenade(aim_from: Vector3, aim_dir: Vector3, slot: int = -1, damage_mult: float = 1.0) -> bool:
	if slot < 0:
		slot = selected
	if is_dead or mode != Mode.GROUND or _fire_cd > 0.0 or slot >= slots.size() or slots[slot] == null:
		return false
	var item: Dictionary = slots[slot]
	if item.kind != "consumable" or not Items.CONSUMABLES[item.id].get("throw", false):
		return false
	_fire_cd = 0.9
	_swing = 0.3
	Audio.play3d("swing", global_transform.origin + Vector3(0, 1.3, 0), -4.0, 0.7)
	var def: Dictionary = Items.CONSUMABLES[item.id]
	var hand: Vector3 = global_transform.origin + Vector3(0, 1.55, 0) + aim_dir * 0.9
	if def.get("rift", false):                      # Rift-to-Go: open a rift at our feet and jump through it
		var rift := Rift.new()
		rift.lifetime = 10.0
		get_parent().add_child(rift)
		rift.global_transform.origin = global_transform.origin
		rift_launch()
	else:
		var g := Grenade.new()
		g.thrower = self
		g.damage_mult = damage_mult
		get_parent().add_child(g)
		g.global_transform.origin = hand
		g.linear_velocity = aim_dir * 17.0 + Vector3(0, 4.0, 0) + Vector3(velocity.x, 0, velocity.z) * 0.6
		g.angular_velocity = Vector3(rand_range(-6, 6), rand_range(-6, 6), rand_range(-6, 6))
	item.count -= 1
	if item.count <= 0:
		slots[slot] = null
		if selected == slot:
			selected = 0
			_apply_selected()
		else:
			emit_signal("slot_changed")
	else:
		emit_signal("slot_changed")
	return true


func cancel_use() -> void:
	_use_left = 0.0


# ------------------------------------------------------------------ movement

func move_body(delta: float, wish: Vector3, speed: float, want_jump: bool) -> void:
	var on_floor := is_on_floor()
	var accel := 16.0 if on_floor else 4.0
	var k: float = clamp(accel * delta, 0.0, 1.0)
	velocity.x = lerp(velocity.x, wish.x * speed, k)
	velocity.z = lerp(velocity.z, wish.z * speed, k)
	var snap := Vector3(0, -0.45, 0)
	if on_floor:
		velocity.y = 0.0                     # the snap keeps us glued to slopes, ramps and stairs
		if want_jump:
			velocity.y = jump_speed
			snap = Vector3.ZERO
			Audio.play3d("jump", global_transform.origin + Vector3(0, 0.5, 0), -8.0, rand_range(0.95, 1.1))
	else:
		velocity.y -= _gravity * delta
		snap = Vector3.ZERO
	var vy_before := velocity.y
	velocity = move_and_slide_with_snap(velocity, snap, Vector3.UP, true, 4, deg2rad(52.0))
	grounded = is_on_floor()
	if grounded and not _was_grounded and vy_before < -7.0:
		Audio.play3d("land", global_transform.origin, clamp(-18.0 + (-vy_before) * 1.2, -14.0, -2.0), rand_range(0.95, 1.05))
		if mode == Mode.GROUND and -vy_before > FALL_SAFE_SPEED and not is_dead:
			take_damage((-vy_before - FALL_SAFE_SPEED) * FALL_DAMAGE_PER_MS, null)      # a hard landing hurts
	_was_grounded = grounded
	forward_speed = Vector3(velocity.x, 0.0, velocity.z).dot(-global_transform.basis.z)
	_clamp_to_map()
	if mode == Mode.GROUND and global_transform.origin.y < SWIM_ENTER:
		enter_swim()


func _clamp_to_map() -> void:
	var o := global_transform.origin
	o.x = clamp(o.x, -map_half, map_half)
	o.z = clamp(o.z, -map_half, map_half)
	if o.y < -40.0:                       # fell through the world: put back on the island
		o = Vector3(0, 40, 0)
		velocity = Vector3.ZERO
	global_transform.origin = o


# ------------------------------------------------------------------ swimming

func enter_swim() -> void:
	mode = Mode.SWIM
	velocity.y *= 0.2
	cancel_use()
	var o := global_transform.origin
	Audio.play3d("splash", Vector3(o.x, WATER_LEVEL, o.z), -2.0, rand_range(0.95, 1.05))
	_ripple(3.5)


# One swim step. wish is a horizontal direction (length <= 1); speed in m/s.
func swim_physics(delta: float, wish: Vector3, speed: float) -> void:
	var k: float = clamp(4.0 * delta, 0.0, 1.0)
	velocity.x = lerp(velocity.x, wish.x * speed, k)
	velocity.z = lerp(velocity.z, wish.z * speed, k)
	var bob := sin(OS.get_ticks_msec() / 1000.0 * 2.0 + float(get_instance_id() % 7)) * 0.04
	var floor_y := floor_y_below()
	# float at the surface, but never below the sea floor: swimmers glide up the beach
	var target_y: float = max(SWIM_FEET_Y + bob, floor_y + 0.03)
	velocity.y = clamp((target_y - global_transform.origin.y) * 8.0, -4.0, 4.0)
	velocity = move_and_slide(velocity, Vector3.UP, false, 4, deg2rad(65.0))
	grounded = is_on_floor()
	forward_speed = Vector3(velocity.x, 0.0, velocity.z).dot(-global_transform.basis.z)
	_clamp_to_map()
	_ripple_t -= delta
	if _ripple_t <= 0.0 and Vector2(velocity.x, velocity.z).length() > 0.8:
		_ripple_t = 0.45
		_ripple(1.8)
	if floor_y > SWIM_EXIT and global_transform.origin.y > SWIM_EXIT - 0.15:
		mode = Mode.GROUND


func floor_y_below() -> float:
	var o := global_transform.origin
	var hit := get_world().direct_space_state.intersect_ray(o + Vector3(0, 0.6, 0), o + Vector3(0, -6.0, 0), [self], 1)
	return hit.position.y if hit else -999.0


func swim_stroke() -> void:
	Audio.play3d("swim_stroke", global_transform.origin + Vector3(0, 0.3, 0), -9.0, rand_range(0.9, 1.1))


func _ripple(spread: float) -> void:
	if get_parent() == null:
		return
	var mi := MeshInstance.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.02
	mesh.radial_segments = 20
	mesh.rings = 1
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.albedo_color = Color(1, 1, 1, 0.55)
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	var o := global_transform.origin
	mi.global_transform.origin = Vector3(o.x, WATER_LEVEL + 0.04, o.z)
	mi.scale = Vector3(0.4, 1.0, 0.4)
	var tw := Tween.new()
	mi.add_child(tw)
	tw.interpolate_property(mi, "scale", Vector3(0.4, 1.0, 0.4), Vector3(spread, 1.0, spread), 1.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.interpolate_property(mat, "albedo_color:a", 0.55, 0.0, 1.0)
	tw.start()
	get_tree().create_timer(1.1).connect("timeout", mi, "queue_free")


# ------------------------------------------------------------------ vehicles

func enter_vehicle(v, seat: int) -> void:
	cancel_use()
	vehicle = v
	vehicle_seat = seat
	mode = Mode.VEHICLE
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	sprinting = false
	Audio.play3d("door", global_transform.origin, -2.0)


func exit_vehicle(eject: bool = false) -> void:
	if mode != Mode.VEHICLE:
		return
	var v = vehicle
	var seat := vehicle_seat
	mode = Mode.GROUND
	collision_layer = 2
	collision_mask = BODY_MASK
	if v != null and is_instance_valid(v):
		global_transform.origin = v.exit_position(seat)
		velocity = v.linear_velocity * (0.6 if eject else 0.25)
		v.release_seat(seat)
	vehicle = null
	air_pivot.rotation = Vector3.ZERO
	air_pivot.translation = Vector3(0, 0.9, 0)
	grounded = false
	Audio.play3d("door", global_transform.origin, -2.0)


func follow_vehicle() -> void:
	if vehicle != null and is_instance_valid(vehicle):
		global_transform.origin = vehicle.seat_position(vehicle_seat)


# ------------------------------------------------------------------ mantling

# Climb onto a ledge in front of us. dir = facing / movement direction. Returns true if started.
func try_mantle(dir: Vector3) -> bool:
	if is_dead or mode != Mode.GROUND or _mantle_cd > 0.0:
		return false
	dir.y = 0.0
	if dir.length() < 0.1:
		return false
	dir = dir.normalized()
	var o := global_transform.origin
	var space := get_world().direct_space_state
	var chest := o + Vector3(0, 0.95, 0)
	var wall := space.intersect_ray(chest, chest + dir * 0.95, [self], 1)
	if not wall or abs(wall.normal.y) > 0.35:
		return false
	var probe: Vector3 = wall.position - wall.normal * 0.4
	var from := probe + Vector3(0, MANTLE_MAX + 0.35, 0)
	var top := space.intersect_ray(from, from + Vector3(0, -(MANTLE_MAX + 0.45), 0), [self], 1)
	if not top or top.normal.y < 0.7:
		return false
	var rise: float = top.position.y - o.y
	if rise < MANTLE_MIN or rise > MANTLE_MAX:
		return false
	var gd := ground_distance()
	if gd < 6.0 and rise + gd > MANTLE_MAX_FROM_GROUND:
		return false
	if space.intersect_ray(top.position + Vector3(0, 0.1, 0), top.position + Vector3(0, 1.85, 0), [self], 1):
		return false                      # no headroom up there
	mode = Mode.MANTLE
	_mantle_from = o
	_mantle_to = top.position + Vector3(0, 0.05, 0)
	_mantle_dir = dir
	_mantle_dur = 0.5 + 0.16 * rise
	_mantle_t = 0.0
	velocity = Vector3.ZERO
	collision_mask = 0
	Audio.play3d("mantle", o + Vector3(0, 1.0, 0), -4.0)
	return true


func mantle_physics(delta: float) -> void:
	_mantle_t += delta / _mantle_dur
	var t: float = clamp(_mantle_t, 0.0, 1.0)
	var rise: float = smoothstep(0.0, 0.75, t)
	var fwd: float = smoothstep(0.35, 1.0, t)
	var p := Vector3(lerp(_mantle_from.x, _mantle_to.x, fwd), lerp(_mantle_from.y, _mantle_to.y, rise), lerp(_mantle_from.z, _mantle_to.z, fwd))
	global_transform.origin = p
	if _mantle_t >= 1.0:
		mode = Mode.GROUND
		collision_mask = BODY_MASK
		velocity = _mantle_dir * 2.0
		_mantle_cd = 0.5
		_mantle_t = 0.0


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
	collision_mask = BODY_MASK
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
	Audio.play3d("glider_open", global_transform.origin, -2.0)
	if glider:
		glider.visible = true
		glider.scale = Vector3(0.2, 0.2, 0.2)
		var tween := Tween.new()
		add_child(tween)
		tween.interpolate_property(glider, "scale", Vector3(0.2, 0.2, 0.2), Vector3.ONE, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
		tween.start()


# Rift: hurled high above the island, skydiving (jump opens the glider; it opens by itself near the ground).
func rift_launch() -> void:
	if is_dead or (mode != Mode.GROUND and mode != Mode.SWIM):
		return
	var o := global_transform.origin
	global_transform.origin = Vector3(o.x, o.y + 150.0, o.z)
	mode = Mode.FREEFALL
	collision_layer = 2
	collision_mask = BODY_MASK
	if air_pivot:
		air_pivot.visible = true
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	velocity = fwd.normalized() * 10.0 + Vector3(0, 4.0, 0)


# Air Sprite updraft: pop off the ground (or keep climbing) with the glider already open.
func updraft_launch() -> void:
	if mode == Mode.GROUND or mode == Mode.SWIM:
		mode = Mode.FREEFALL
		if air_pivot:
			air_pivot.visible = true
		velocity.y = 20.0
		deploy_glider()
	elif mode == Mode.FREEFALL or mode == Mode.GLIDE:
		if mode == Mode.FREEFALL:
			deploy_glider()
		velocity.y = max(velocity.y, 13.0)


func _land() -> void:
	mode = Mode.GROUND
	if glider:
		glider.visible = false
	velocity = Vector3(0, -2.0, 0)
	Audio.play3d("land", global_transform.origin, -4.0)
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
	var lift := 0.0
	match mode:
		Mode.FREEFALL:
			tilt = -1.25 if air_input.y <= 0.5 else -0.7
			roll = -air_input.x * 0.35
		Mode.GLIDE:
			tilt = -0.12 + (-0.2 if air_input.y < -0.5 else 0.0)
			roll = -air_input.x * 0.25
		Mode.SWIM:
			var swimming_fast := Vector2(velocity.x, velocity.z).length() > 0.8
			tilt = -1.38 if swimming_fast else -0.05
			lift = -0.15 if swimming_fast else 0.0
		Mode.MANTLE:
			tilt = -0.25
	var k: float = clamp(6.0 * delta, 0.0, 1.0)
	air_pivot.rotation.x = lerp(air_pivot.rotation.x, tilt, k)
	air_pivot.rotation.z = lerp(air_pivot.rotation.z, roll, k)
	air_pivot.translation.y = lerp(air_pivot.translation.y, 0.9 + lift, k)


# ------------------------------------------------------------------ animation

func animate(delta: float) -> void:
	if animator == null:
		return
	_air_pose(delta)
	_swing = max(0.0, _swing - delta)
	animator.update(self, delta)


func reload_fraction_left() -> float:
	return clamp(_reload_left / max(reload_time, 0.01), 0.0, 1.0)


func swing_fraction() -> float:
	return _swing / 0.3


func mantle_fraction() -> float:
	return clamp(_mantle_t, 0.0, 1.0)


# ------------------------------------------------------------------ combat

func footstep(speed: float) -> void:
	var o := global_transform.origin
	if Audio.listener_distance(o) > 45.0:
		return
	var snd := "step_grass"
	if o.y < -0.15:
		snd = "step_water"
	elif o.y < 1.6:
		snd = "step_sand"
	else:
		var hit := get_world().direct_space_state.intersect_ray(o + Vector3(0, 0.4, 0), o + Vector3(0, -0.8, 0), [self], 1)
		if hit and hit.collider != null and hit.collider.has_meta("harvest"):
			snd = "step_wood"
	var vol: float = lerp(-18.0, -8.0, clamp(speed / 8.0, 0.0, 1.0))
	Audio.play3d(snd, o, vol, rand_range(0.9, 1.12))


func tick_weapon(delta: float) -> void:
	tick_sprite(delta)
	_mantle_cd = max(0.0, _mantle_cd - delta)
	_hurt_cd = max(0.0, _hurt_cd - delta)
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
	if has_sprite("ghost"):
		cloak_t = 2.0 + sprite_level()
	var snd := "pump" if item.id == "shotgun" else ("bolt" if item.id == "sniper" else "reload")
	Audio.play3d(snd, global_transform.origin + Vector3(0, 1.2, 0), -4.0)


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
		if is_in_group("player"):
			Audio.play2d("dry_fire", -4.0)
		start_reload()
		return false
	_fire_cd = fire_interval
	if unlimited_t <= 0.0:
		item.mag -= 1
	var snd := "shot_" + ("rifle" if item.id == "assault" else item.id)
	if item.rarity == Items.MYTHIC:     # each mythic has its own report; the sniper keeps the original mythic shot
		snd = "shot_mythic" if item.id == "sniper" else "shot_mythic_" + item.id
	Audio.play3d(snd, muzzle_position(), -2.0 if is_in_group("player") else -6.0, rand_range(0.96, 1.04))
	for i in range(pellets):
		_fire_ray(aim_from, aim_dir, i < 3)
	if animator != null:
		animator.kick(1.0 if pellets == 1 else 1.4)
	if item.mag == 0:
		start_reload()
	return true


func _fire_ray(aim_from: Vector3, aim_dir: Vector3, show_tracer: bool) -> void:
	var dir := _spread(aim_dir)
	var to := aim_from + dir * weapon_range
	var hit := get_world().direct_space_state.intersect_ray(aim_from, to, [self], 11)
	var end := to
	if hit:
		end = hit.position
		var target = hit.collider
		if target != null and target.has_method("take_damage"):
			var head: bool = hit.position.y > target.global_transform.origin.y + 1.42
			var was_alive: bool = not target.is_dead
			var falloff: float = 1.0 - 0.35 * clamp(aim_from.distance_to(hit.position) / weapon_range, 0.0, 1.0)
			var dealt: float = gun_damage * falloff * (head_mult if head else 1.0)
			target.take_damage(dealt, self)
			emit_signal("hit_landed", target, was_alive and target.is_dead, head)
			emit_signal("damage_dealt", hit.position, dealt, head, was_alive and target.is_dead)
	if show_tracer:
		_spawn_tracer(muzzle_position(), end)


func _swing_pickaxe(aim_from: Vector3, aim_dir: Vector3) -> bool:
	_fire_cd = fire_interval
	_swing = 0.3
	Audio.play3d("swing", global_transform.origin + Vector3(0, 1.3, 0), -4.0, rand_range(0.9, 1.1))
	var hit := get_world().direct_space_state.intersect_ray(aim_from, aim_from + aim_dir * weapon_range, [self], 11)
	if not hit:
		return true
	var target = hit.collider
	if target != null and target.has_method("take_damage"):
		Audio.play3d("hit_flesh", hit.position, -2.0)
		var was_alive: bool = not target.is_dead
		target.take_damage(gun_damage * (1.0 + 0.35 * sprite_level() if has_sprite("king") else 1.0), self)
		emit_signal("hit_landed", target, was_alive and target.is_dead, false)
	elif target != null and target.has_meta("harvest"):
		var kind: String = target.get_meta("harvest")
		Audio.play3d("hit_" + kind if kind != "metal" else "hit_metal", hit.position, 0.0, rand_range(0.92, 1.08))
		for w in get_tree().get_nodes_in_group("world"):
			w.harvest_hit(target, hit.shape, target.get_meta("harvest"), self, hit.position)
	return true


func _spread(dir: Vector3) -> Vector3:
	var deg := spread_deg
	var item = selected_item()
	if item != null and item.kind == "weapon" and is_in_group("player"):
		var sc: Dictionary = Items.scope_of(item.id)
		deg = deg * sc.spread if aiming else deg + sc.get("hip_spread", 0.0)    # aiming tightens; a sniper hip-fires wide
		if crouching:
			deg *= 0.7                                                          # crouching steadies the shot
	if deg <= 0.0:
		return dir
	var s := deg2rad(deg)
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
	if bubble_t > 0.0:
		amount *= 0.35
	if _hurt_cd <= 0.0 and amount >= 1.0:
		_hurt_cd = 0.3
		if is_in_group("player"):
			Audio.play2d("hurt", -3.0, rand_range(0.95, 1.05))
		else:
			Audio.play3d("hurt", global_transform.origin + Vector3(0, 1.4, 0), -4.0, rand_range(0.85, 1.25))
	var remaining := amount
	if shield > 0.0:
		var absorbed: float = min(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	health -= remaining
	emit_signal("damaged", amount, source)
	if source != null and source != self and is_instance_valid(source) and source.has_method("sprite_on_hit"):
		source.sprite_on_hit(self, amount)
	if health <= 0.0:
		_die(source)


func _die(killer) -> void:
	is_dead = true
	health = 0.0
	collision_layer = 0
	mode = Mode.GROUND
	if glider:
		glider.visible = false
	Audio.play3d("death", global_transform.origin + Vector3(0, 1.0, 0), -2.0, rand_range(0.85, 1.1))
	if killer != null and "kills" in killer and killer != self:
		killer.kills += 1
		if killer.has_method("sprite_on_kill"):
			killer.sprite_on_kill(self)
	if _sprite_model != null:
		_sprite_model.visible = false
	if model:
		var tween := Tween.new()
		add_child(tween)
		tween.interpolate_property(model, "rotation:x", 0.0, -PI / 2.0, 0.6, Tween.TRANS_QUAD, Tween.EASE_OUT)
		tween.start()
	emit_signal("died", self, killer)


# ------------------------------------------------------------------ sprites

func has_sprite(id: String) -> bool:
	return sprite.get("id", "") == id


func sprite_level() -> int:
	return int(sprite.get("level", 1))


# Equip a sprite (it floats over your shoulder). Returns the one it replaces ({} if none).
func equip_sprite(id: String, variant: String = "", level: int = 1, xp: float = 0.0) -> Dictionary:
	var old := sprite.duplicate()
	sprite = {"id": id, "variant": variant, "level": level, "xp": xp}
	if _sprite_model != null:
		_sprite_model.queue_free()
		_sprite_model = null
	_sprite_model = SpriteCreature.build_for(id, variant, 0.55)
	_sprite_model.translation = Vector3(0.6, 1.85, 0.4)
	_sprite_model.visible = not is_dead
	add_child(_sprite_model)
	emit_signal("sprite_changed")
	return old


func clear_sprite() -> void:
	sprite = {}
	if _sprite_model != null:
		_sprite_model.queue_free()
		_sprite_model = null
	emit_signal("sprite_changed")


func tick_sprite(delta: float) -> void:
	cloak_t = max(0.0, cloak_t - delta)
	unlimited_t = max(0.0, unlimited_t - delta)
	bubble_t = max(0.0, bubble_t - delta)
	if _sprite_model != null:
		_sprite_model.translation.y = 1.85 + sin(OS.get_ticks_msec() * 0.003) * 0.08
		_sprite_model.visible = not is_dead and mode != Mode.BUS and mode != Mode.VEHICLE
	if sprite.empty() or is_dead:
		return
	if has_sprite("water") and mode == Mode.SWIM:
		add_shield((3.0 + sprite_level()) * delta)
	elif has_sprite("duck") and emoting:
		add_shield((4.0 + 2.0 * sprite_level()) * delta)


func sprite_gain_xp(amount: float) -> void:
	if sprite.empty() or sprite_level() >= Sprites.MAX_LEVEL:
		return
	sprite.xp += amount
	while sprite.level < Sprites.MAX_LEVEL and sprite.xp >= Sprites.xp_to_next(sprite.level):
		sprite.level += 1
		emit_signal("picked_up", "%s reached level %d!" % [Sprites.LIST[sprite.id].name, sprite.level])
		Audio.play2d("rarity_3", -8.0)
		if sprite.id == "dream":
			_dream_reward()
	emit_signal("sprite_changed")


func _spawn_near(item: Dictionary, spread: float) -> void:
	var a := _srng.randf() * TAU
	for w in get_tree().get_nodes_in_group("world"):
		w.spawn_item(item, global_transform.origin + Vector3(cos(a), 0.4, sin(a)) * spread)


func _dream_reward() -> void:
	_srng.randomize()
	if sprite.level >= Sprites.MAX_LEVEL:                       # max level: a burst of legendary loot
		var id: String = ["assault", "sniper", "shotgun", "smg"][_srng.randi() % 4]
		var w := Items.make_weapon(id, 4)
		_spawn_near(w, 1.6)
		_spawn_near(Items.make_ammo(Items.WEAPONS[id].ammo, 60), 1.8)
		_spawn_near(Items.make_consumable("shield_potion", 2), 1.7)
		_spawn_near(Items.make_consumable("medkit", 1), 1.7)
		_spawn_near(Items.make_gold(100), 1.6)
		emit_signal("picked_up", "The Dream Sprite bursts with loot!")
	else:
		_spawn_near(Items.random_consumable(_srng), 1.4)


# Called by whoever hurt someone while we were the source.
func sprite_on_hit(target, amount: float) -> void:
	if sprite.empty():
		return
	sprite_gain_xp(amount * 0.015)
	if has_sprite("fire") and not _in_burst:
		_burst_acc += amount
		if _burst_acc >= 60.0 - 6.0 * sprite_level():
			_burst_acc = 0.0
			_in_burst = true
			var at: Vector3 = target.global_transform.origin + Vector3(0, 1.0, 0)
			for f in get_tree().get_nodes_in_group("fighters"):
				if f != self and not f.is_dead and f.global_transform.origin.distance_to(at) < 3.5:
					f.take_damage(10.0 + 5.0 * sprite_level(), self)
			_in_burst = false
			var p := SpriteCreature.particles(Color(1.0, 0.5, 0.1, 0.9), 40, 0.7, 5.0, 180.0, 2.0, 0.4)
			get_parent().add_child(p)
			p.global_transform.origin = at
			p.one_shot = true
			get_tree().create_timer(1.2).connect("timeout", p, "queue_free")
			Audio.play3d("explosion", at, -12.0, 1.5)


func sprite_on_kill(victim) -> void:
	if sprite.empty():
		return
	sprite_gain_xp(1.0)
	var lvl := sprite_level()
	_srng.randomize()
	match sprite.id:
		"demon":
			heal(15.0 + 5.0 * lvl)
			add_shield(10.0 + 5.0 * lvl)
		"punk":
			if _srng.randf() < 0.35 + 0.1 * lvl:
				unlimited_t = 6.0 + 2.0 * lvl
				emit_signal("picked_up", "Unlimited ammo!")
		"lucky":
			if _srng.randf() < 0.15 + 0.07 * lvl:
				for w in get_tree().get_nodes_in_group("world"):
					w.spawn_item(Items.random_floor_item(_srng), victim.global_transform.origin + Vector3(0, 0.6, 0))
				emit_signal("picked_up", "Lucky drop!")
	if sprite.get("variant", "") == "gold":
		gold += 10 * lvl
		emit_signal("picked_up", "+%d Gold" % (10 * lvl))


# Earth Sprite: a chest may hold an extra rare weapon. Every opened chest also feeds the sprite.
func sprite_on_chest(loot: Array, rng: RandomNumberGenerator) -> void:
	if sprite.empty():
		return
	sprite_gain_xp(1.0)
	if has_sprite("earth") and rng.randf() < 0.2 + 0.08 * sprite_level():
		var w := Items.random_weapon(rng, 2)
		loot.append(w)
		loot.append(Items.ammo_for(w, rng, 1.0))
		emit_signal("picked_up", "Earth Sprite found an extra weapon!")


func heal(amount: float) -> void:
	health = min(max_health, health + amount)


func add_shield(amount: float) -> void:
	shield = min(max_shield, shield + amount)

extends Node
# Build mode for the player (toggle with Q / the BUILD button): pick a piece and a material,
# aim, and place walls / floors / ramps / roofs snapped to a 4 m grid. Costs materials.

const BuildPiece = preload("res://scripts/BuildPiece.gd")

const CELL := 4.0
const STEP := 3.0
const COST := 10
const PIECES := ["wall", "floor", "ramp", "roof"]
const MATERIALS := ["wood", "stone", "metal"]
const REACH := 9.0

signal changed

var player
var world
var active := false
var piece := 0
var material := "wood"
var _origin_y := 0.0
var _has_origin := false
var _ghost: MeshInstance
var _ghost_mat: SpatialMaterial
var _target := {}


func setup(p, w) -> void:
	player = p
	world = w
	_ghost_mat = SpatialMaterial.new()
	_ghost_mat.flags_unshaded = true
	_ghost_mat.flags_transparent = true
	_ghost_mat.albedo_color = Color(0.2, 1.0, 0.4, 0.35)
	_ghost = MeshInstance.new()
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	world.call_deferred("add_child", _ghost)


func toggle() -> void:
	set_active(not active)


func set_active(on: bool) -> void:
	if on and player.mode != 0:
		return
	if on and Net.zero_build_on():
		if player.has_signal("picked_up"):
			player.emit_signal("picked_up", "Zero Build: building is off in this mode")
		return
	if on == active:
		return
	active = on
	if on:
		auto_route()
	_ghost.visible = false
	Audio.play2d("build_toggle", -4.0)
	emit_signal("changed")


func set_piece(i: int) -> void:
	piece = int(clamp(i, 0, PIECES.size() - 1))
	_ghost.mesh = BuildPiece.make_mesh(PIECES[piece])
	Audio.play2d("ui_slot", -8.0)
	emit_signal("changed")


func cycle_material(direction: int) -> void:
	var idx := MATERIALS.find(material)
	material = MATERIALS[int(posmod(idx + direction, MATERIALS.size()))]
	Audio.play2d("ui_slot", -8.0)
	emit_signal("changed")


const EDIT_REACH := 11.0


# The editable build piece under the crosshair (walls and floors), or null.
func looked_at_piece():
	if player == null:
		return null
	var a: Array = player.aim_origin_and_dir()
	var hit: Dictionary = player.get_world().direct_space_state.intersect_ray(a[0], a[0] + a[1] * EDIT_REACH, [player], 1)
	if hit and hit.collider != null and hit.collider.has_method("apply_mask") and hit.collider.editable():
		return hit.collider
	return null


func set_material(name: String) -> void:
	if name in MATERIALS and name != material:
		material = name
		Audio.play2d("ui_slot", -8.0)
		emit_signal("changed")


# Out of the selected material? Jump straight to the next one that has enough (wood -> brick -> metal), no menu.
func auto_route() -> void:
	if player == null or player.materials[material] >= COST:
		return
	for i in range(1, MATERIALS.size()):
		var m: String = MATERIALS[int(posmod(MATERIALS.find(material) + i, MATERIALS.size()))]
		if player.materials[m] >= COST:
			material = m
			Audio.play2d("ui_slot", -8.0)
			emit_signal("changed")
			return


func can_afford() -> bool:
	return player.materials[material] >= COST


func compute_target() -> Dictionary:
	var a: Array = player.aim_origin_and_dir()
	var hit: Dictionary = player.get_world().direct_space_state.intersect_ray(a[0], a[0] + a[1] * REACH, [player], 1 | 8)
	var p: Vector3 = a[0] + a[1] * 5.5
	if hit:
		p = hit.position + hit.normal * 0.3
	if not _has_origin or player.global_transform.origin.distance_to(Vector3(p.x, _origin_y, p.z)) > 60.0:
		_origin_y = round(p.y * 2.0) / 2.0
		_has_origin = true
	var lvl: float = round((p.y - _origin_y) / STEP) * STEP + _origin_y
	var ci := int(floor(p.x / CELL))
	var cj := int(floor(p.z / CELL))
	var cx := ci * CELL + CELL / 2.0
	var cz := cj * CELL + CELL / 2.0
	var level_idx := int(round((lvl - _origin_y) / STEP))
	var kind: String = PIECES[piece]
	var pos := Vector3.ZERO
	var yaw := 0.0
	var key := ""
	var f: Vector3 = a[1]
	match kind:
		"floor":
			pos = Vector3(cx, lvl - 0.125, cz)
			key = "floor:%d:%d:%d" % [ci, cj, level_idx]
		"wall":
			var dx := p.x - cx
			var dz := p.z - cz
			if abs(dx) > abs(dz):
				var side: float = sign(dx) if dx != 0.0 else 1.0
				pos = Vector3(cx + side * CELL / 2.0, lvl + 1.5, cz)
				yaw = PI / 2.0
				key = "wallx:%d:%d:%d" % [ci + (1 if side > 0 else 0), cj, level_idx]
			else:
				var side2: float = sign(dz) if dz != 0.0 else 1.0
				pos = Vector3(cx, lvl + 1.5, cz + side2 * CELL / 2.0)
				key = "wallz:%d:%d:%d" % [ci, cj + (1 if side2 > 0 else 0), level_idx]
		"ramp":
			yaw = round(atan2(-f.x, -f.z) / (PI / 2.0)) * (PI / 2.0)
			pos = Vector3(cx, lvl + 1.5, cz)
			key = "ramp:%d:%d:%d" % [ci, cj, level_idx]
		_:
			pos = Vector3(cx, lvl + 1.1, cz)
			key = "roof:%d:%d:%d" % [ci, cj, level_idx]
	var free: bool = not world.build_slots.has(key)
	return {"kind": kind, "pos": pos, "yaw": yaw, "key": key, "valid": free and can_afford()}


func _process(_delta: float) -> void:
	if not active or player == null or player.mode != 0 or player.is_dead:
		if _ghost.visible:
			_ghost.visible = false
		if active and player != null and player.mode != 0:
			active = false
			emit_signal("changed")
		return
	auto_route()
	_target = compute_target()
	if _ghost.mesh == null:
		_ghost.mesh = BuildPiece.make_mesh(PIECES[piece])
	_ghost.visible = true
	_ghost.global_transform = Transform(BuildPiece.piece_basis(_target.kind, _target.yaw), _target.pos)
	_ghost_mat.albedo_color = Color(0.2, 1.0, 0.4, 0.35) if _target.valid else Color(1.0, 0.25, 0.2, 0.35)


# Called by the player when "fire" is pressed in build mode.
func place() -> bool:
	if not active:
		return false
	auto_route()
	_target = compute_target()          # never place from a stale ghost
	if not _target.valid:
		Audio.play2d("ui_error", -6.0)
		if not can_afford():     # say why: the usual cause is simply having no materials yet
			player.emit_signal("picked_up", "Need %d %s - hit trees, rocks and buildings with the pickaxe" % [COST, material.to_upper()])
		else:
			player.emit_signal("picked_up", "Already built there")
		return false
	var node: StaticBody = world.spawn_build(_target.kind, material, _target.key, _target.pos, _target.yaw)
	if world.net_live:
		Net.send_event("build", [_target.kind, material, _target.key, _target.pos, _target.yaw])
	player.materials[material] -= COST
	player.stat_add("builds")
	auto_route()
	Audio.play3d("build_place", _target.pos, 0.0, rand_range(0.95, 1.05))
	emit_signal("changed")
	return node != null

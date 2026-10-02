extends Spatial
# Main scene. Builds the island (terrain, town, houses, trees, rocks, chests, floor loot),
# spawns the player and bots on the battle bus, runs the shrinking storm and supply drops,
# and decides the match result. Quality is chosen per platform: Android gets fewer
# bots/trees and no real-time shadows.

const Items = preload("res://scripts/Items.gd")
const Terrain = preload("res://scripts/Terrain.gd")
const Storm = preload("res://scripts/Storm.gd")
const Player = preload("res://scripts/Player.gd")
const Bot = preload("res://scripts/Bot.gd")
const LootItem = preload("res://scripts/LootItem.gd")
const Chest = preload("res://scripts/Chest.gd")
const Bus = preload("res://scripts/Bus.gd")
const HUD = preload("res://scripts/HUD.gd")
const Pois = preload("res://scripts/Pois.gd")
const BuildPiece = preload("res://scripts/BuildPiece.gd")
const Vehicle = preload("res://scripts/Vehicle.gd")
const Boat = preload("res://scripts/Boat.gd")

const MAP_HALF := 160.0
const SEED := 20241002
const MODEL_DIR := "res://assets/models/"
const HOUSES := ["house_a", "house_b"]
const BUS_ALTITUDE := 260.0
const BUS_LENGTH := 480.0
const BOT_NAMES := ["Rook", "Nova", "Echo", "Blitz", "Sable", "Juno", "Kestrel", "Moxie", "Vesper", "Dash",
	"Onyx", "Pixel", "Zephyr", "Ember", "Gizmo", "Havoc", "Indigo", "Lynx", "Maverick", "Nimbus",
	"Orbit", "Pepper", "Quill", "Riot", "Sprout"]
const BOT_COLORS := [Color(0.85, 0.25, 0.22), Color(0.90, 0.60, 0.15), Color(0.70, 0.25, 0.80),
	Color(0.20, 0.70, 0.65), Color(0.85, 0.80, 0.20), Color(0.90, 0.40, 0.60)]

var rng := RandomNumberGenerator.new()
var profile := {}
var terrain
var storm
var player
var hud
var bus = null
var building_positions := []     # Vector2 (x, z) for the minimap
var tree_positions := []         # Vector2 (x, z), used to keep spawns out of foliage
var match_over := false

var shared := {}                 # cached meshes/materials shared by loot items
var pois := []                   # runtime POIs: {id, name, center (Vector2), frame_yaw, def, zone}
var poi_roads := []              # [Vector2 a, Vector2 b] for the map
var boss = null
var build_slots := {}            # grid key -> BuildPiece
var _spinners := []
var _props := {}                 # model name -> {mm, body, hits}
var _supply_phase := -1
var _amb_t := 0.0
var _bird_t := 6.0
var _music_t := 0.0
var _last_waiting := true


func _ready() -> void:
	add_to_group("world")
	rng.seed = SEED
	profile = _make_profile()
	if not profile.mobile:
		get_viewport().msaa = Viewport.MSAA_4X
	_setup_environment()

	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.setup(MAP_HALF, SEED, profile.cell)
	add_child(terrain)
	_plan_pois()
	var plan := _plan_buildings()
	terrain.build()
	_spawn_buildings(plan)
	_build_pois()
	_scatter_props("tree", profile.trees, 0.8, 1.5, 0.45, 3.0, 2.2, "wood")
	_scatter_props("rock", profile.rocks, 1.0, 2.6, 0.9, 1.4, 1.6, "stone")

	storm = Storm.new()
	storm.name = "Storm"
	storm.active = not profile.use_bus
	add_child(storm)
	storm.setup(MAP_HALF - 8.0, rng)

	rng.randomize()      # same island every match, different spawns/loot
	_spawn_containers_and_loot(plan)
	_spawn_poi_loot()
	_spawn_fighters()
	_spawn_boss()
	_spawn_vehicles()
	if profile.use_bus:
		_start_bus()

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(self)
	player.connect("damaged", self, "_on_player_damaged")
	Audio.music("music_bus" if profile.use_bus else "music_game", 0.5)
	if not Controls.touch_mode and not ("--no-capture" in OS.get_cmdline_args()):
		Controls.capture_mouse(true)


func _make_profile() -> Dictionary:
	var args := OS.get_cmdline_args()
	var mobile := OS.has_feature("mobile") or ("--mobile" in args)
	var p := {
		"mobile": mobile,
		"bots": 14 if mobile else 24,
		"trees": 170 if mobile else 420,
		"rocks": 22 if mobile else 55,
		"outlying": 9 if mobile else 14,
		"floor_items": 22 if mobile else 38,
		"outdoor_chests": 3 if mobile else 5,
		"shadows": not mobile,
		"cell": 4.0 if mobile else 3.0,
		"use_bus": not ("--no-bus" in args),
	}
	for a in args:
		if a.begins_with("--bots="):
			p.bots = int(a.substr(7))
	return p


# ------------------------------------------------------------------ environment

func _setup_environment() -> void:
	var sky := ProceduralSky.new()
	sky.sky_top_color = Color(0.22, 0.48, 0.92)
	sky.sky_horizon_color = Color(0.72, 0.84, 0.96)
	sky.sky_curve = 0.25
	sky.ground_bottom_color = Color(0.25, 0.38, 0.5)
	sky.ground_horizon_color = Color(0.72, 0.84, 0.96)
	sky.sun_latitude = 48.0
	sky.sun_longitude = 215.0
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_sky = sky
	env.ambient_light_color = Color(0.62, 0.70, 0.82)
	env.ambient_light_energy = 0.7
	env.ambient_light_sky_contribution = 0.35
	env.fog_enabled = true
	env.fog_color = Color(0.74, 0.85, 0.96)
	env.fog_depth_begin = 150.0
	env.fog_depth_end = 520.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 0.95
	sun.shadow_enabled = profile.shadows
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	var water := MeshInstance.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	water.mesh = plane
	var wm := SpatialMaterial.new()
	wm.albedo_color = Color(0.10, 0.48, 0.68, 0.86)
	wm.flags_transparent = true
	wm.roughness = 0.15
	wm.metallic = 0.25
	water.material_override = wm
	water.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	water.translation.y = Terrain.WATER_LEVEL
	add_child(water)


# ------------------------------------------------------------------ buildings

func _facing_center(p: Vector2) -> float:
	var d := -p.normalized()
	return round(atan2(d.x, d.y) / (PI / 2.0)) * (PI / 2.0)   # snap to a wall axis; door is on local +Z


func _plan_buildings() -> Array:
	var plan := []
	terrain.add_zone(0.0, 0.0, 62.0)                       # the town: one flat pad
	plan.append({"res": "tower", "pos": Vector2.ZERO, "yaw": 0.0, "house": false})
	var spacing := 21.0
	for gx in [-1, 0, 1]:
		for gz in [-1, 0, 1]:
			if gx == 0 and gz == 0:
				continue
			var p := Vector2(gx, gz) * spacing + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			var big: bool = abs(gx) == abs(gz)
			plan.append({"res": HOUSES[1] if big else HOUSES[0], "pos": p, "yaw": _facing_center(p), "house": true})
	var placed := 0
	var tries := 0
	while placed < profile.outlying and tries < 500:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(80.0, MAP_HALF * 0.74)
		var p := Vector2(cos(a), sin(a)) * r
		if terrain.raw_height(p.x, p.y) < 3.0 or not terrain.is_free(p.x, p.y, 18.0):
			continue
		terrain.add_zone(p.x, p.y, 11.0)
		plan.append({"res": HOUSES[rng.randi() % 2], "pos": p, "yaw": float(rng.randi() % 4) * PI / 2.0, "house": true})
		placed += 1
	return plan


func _spawn_buildings(plan: Array) -> void:
	for entry in plan:
		var scene = load(MODEL_DIR + entry.res + ".glb")
		if scene == null:
			push_warning("missing model: " + entry.res)
			continue
		var inst: Spatial = scene.instance()
		var p: Vector2 = entry.pos
		inst.translation = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		inst.rotation.y = entry.yaw
		add_child(inst)
		_add_trimesh_collision(inst, "metal" if entry.res == "tower" else "wood")
		building_positions.append(p)


func _add_trimesh_collision(node: Node, harvest_kind: String) -> void:
	if node is MeshInstance:
		node.create_trimesh_collision()
	for c in node.get_children():
		if c is StaticBody:
			c.set_meta("harvest", harvest_kind)
		_add_trimesh_collision(c, harvest_kind)


func _find_mesh(node: Node):
	if node is MeshInstance:
		return node.mesh
	for c in node.get_children():
		var m = _find_mesh(c)
		if m != null:
			return m
	return null


# ------------------------------------------------------------------ points of interest

func _locate_poi(def: Dictionary) -> Vector2:
	var a := deg2rad(def.angle)
	var dir := Vector2(cos(a), sin(a))
	if def.mode == "shore":
		var r_land := 60.0
		for r in range(60, 155, 2):
			if terrain.raw_height(dir.x * r, dir.y * r) > 1.5:
				r_land = float(r)
		return dir * (r_land - def.inland)
	var best_r: float = def.rmin
	var best_score := -1e9
	var r: float = def.rmin
	while r <= def.rmax:
		var c := dir * r
		var h: float = terrain.raw_height(c.x, c.y)
		if h > 4.0:
			var variance := 0.0
			for k in range(8):
				var q := c + Vector2(cos(k * PI / 4.0), sin(k * PI / 4.0)) * 16.0
				variance += abs(terrain.raw_height(q.x, q.y) - h)
			var score: float = (h * 0.5 if def.mode == "hill" else 0.0) - variance
			if score > best_score:
				best_score = score
				best_r = r
		r += 3.0
	return dir * best_r


func _plan_pois() -> void:
	var centers := {"maple": Vector2.ZERO}
	for def in Pois.POIS:
		var c := _locate_poi(def)
		centers[def.id] = c
		terrain.add_zone(c.x, c.y, def.zone)
		pois.append({"id": def.id, "name": def.name, "center": c, "frame_yaw": -deg2rad(def.angle), "def": def, "zone": def.zone})
	for r in Pois.ROADS:
		terrain.add_road(centers[r[0]], centers[r[1]])
		poi_roads.append([centers[r[0]], centers[r[1]]])


# POI-local (x outward, z tangent) -> world position; y follows the terrain.
func _poi_point(poi: Dictionary, local: Vector2) -> Vector3:
	var off := Basis(Vector3.UP, poi.frame_yaw).xform(Vector3(local.x, 0.0, local.y))
	var x: float = poi.center.x + off.x
	var z: float = poi.center.y + off.z
	return Vector3(x, terrain.height_at(x, z), z)


func _build_pois() -> void:
	for poi in pois:
		var def: Dictionary = poi.def
		poi["nodes"] = []
		var idx := 0
		for pr in def.props:
			var scene = load(MODEL_DIR + pr.res + ".glb")
			if scene == null:
				poi.nodes.append(null)
				continue
			var inst: Spatial = scene.instance()
			var pos := _poi_point(poi, pr.at)
			pos.y += pr.get("y", 0.0)
			var yaw: float = poi.frame_yaw + deg2rad(pr.get("yaw", 0.0))
			if pr.get("face_center", false):
				var to_c := -Vector2(pr.at.x, pr.at.y)     # local direction to the POI middle
				if to_c.length() < 0.5:
					to_c = Vector2(-1, 0)                   # the main building faces the island centre
				var w := Basis(Vector3.UP, poi.frame_yaw).xform(Vector3(to_c.x, 0, to_c.y))
				yaw = round(atan2(w.x, w.z) / (PI / 2.0)) * (PI / 2.0)
			inst.translation = pos
			inst.rotation.y = yaw
			add_child(inst)
			if pr.has("tint"):
				Items.apply_accent(inst, pr.tint)
			if not pr.get("decor", false):
				_add_trimesh_collision(inst, pr.get("harvest", "wood"))
			if pr.get("building", false):
				building_positions.append(Vector2(pos.x, pos.z))
			if pr.has("spin"):
				var part := inst.find_node("Blades" if pr.spin == "blades" else "Dish", true, false)
				if part:
					_spinners.append({"node": part, "kind": pr.spin})
			poi.nodes.append({"node": inst, "yaw": yaw, "pos": pos, "res": pr.res})
			idx += 1
		if def.has("pier"):
			_build_pier(poi, def.pier)
		if def.has("helipad"):
			_build_helipad(_poi_point(poi, def.helipad))


func _add_box(pos: Vector3, size: Vector3, color: Color, yaw: float = 0.0, harvest: String = "wood", collide: bool = true) -> Spatial:
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	if harvest != "":
		body.set_meta("harvest", harvest)
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	mi.mesh = cm
	var mat := SpatialMaterial.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	body.add_child(mi)
	if collide:
		var cs := CollisionShape.new()
		var sh := BoxShape.new()
		sh.extents = size / 2.0
		cs.shape = sh
		body.add_child(cs)
	body.translation = pos
	body.rotation.y = yaw
	add_child(body)
	return body


func _build_pier(poi: Dictionary, spec: Dictionary) -> void:
	var top := 1.3
	var basis := Basis(Vector3.UP, poi.frame_yaw)
	var length: float = spec.length
	var width: float = spec.width
	var from: float = spec.from
	var wood := Color(0.52, 0.37, 0.21)
	var c := Vector3(poi.center.x, 0.0, poi.center.y)
	var deck := c + basis.xform(Vector3(from + length / 2.0, 0, 0))
	deck.y = top - 0.15
	_add_box(deck, Vector3(length, 0.3, width), wood, poi.frame_yaw)
	var tee := c + basis.xform(Vector3(from + length - 1.5, 0, 0))
	tee.y = top - 0.15
	_add_box(tee, Vector3(3.0, 0.3, 13.0), wood, poi.frame_yaw)
	var i := 0.0
	while i < length:
		for side in [-1.0, 1.0]:
			var p := c + basis.xform(Vector3(from + i, 0, side * (width / 2.0 - 0.3)))
			p.y = (top - 7.0) / 2.0
			_add_box(p, Vector3(0.5, top + 7.0, 0.5), Color(0.35, 0.25, 0.14), poi.frame_yaw, "wood", false)
		i += 4.0
	building_positions.append(Vector2(deck.x, deck.z))


func _build_helipad(pos: Vector3) -> void:
	_add_box(pos + Vector3(0, 0.1, 0), Vector3(14.0, 0.2, 14.0), Color(0.42, 0.43, 0.45), 0.0, "stone")
	var white := Color(0.95, 0.95, 0.9)
	_add_box(pos + Vector3(-2.0, 0.22, 0), Vector3(0.9, 0.05, 6.0), white, 0.0, "", false)   # the "H"
	_add_box(pos + Vector3(2.0, 0.22, 0), Vector3(0.9, 0.05, 6.0), white, 0.0, "", false)
	_add_box(pos + Vector3(0, 0.22, 0), Vector3(3.2, 0.05, 0.9), white, 0.0, "", false)


func _prop_point(poi: Dictionary, entry: Dictionary) -> Array:
	# returns [world position, world yaw] for a chest/item entry (optionally inside a prop)
	if entry.has("in") and poi.has("nodes") and entry["in"] < poi.nodes.size() and poi.nodes[entry["in"]] != null:
		var n: Dictionary = poi.nodes[entry["in"]]
		var big: bool = n.res == "house_b"
		var l := Basis(Vector3.UP, n.yaw).xform(Vector3(entry.at.x, 0.0, entry.at.y))
		return [Vector3(n.pos.x + l.x, n.pos.y + 0.15, n.pos.z + l.z), n.yaw + deg2rad(entry.get("yaw", 0.0))]
	var p := _poi_point(poi, entry.at)
	return [p, poi.frame_yaw + deg2rad(entry.get("yaw", 0.0))]


func _spawn_poi_loot() -> void:
	for poi in pois:
		var def: Dictionary = poi.def
		for ch in def.get("chests", []):
			var pp := _prop_point(poi, ch)
			_add_chest(ch.kind, pp[0], pp[1])
		for it in def.get("items", []):
			var p := _poi_point(poi, it)
			var item: Dictionary = Items.random_weapon(rng, 1) if rng.randf() < 0.55 else Items.random_floor_item(rng)
			spawn_item(item, p + Vector3(0, 0.1, 0))


func spawn_build(kind: String, material: String, key: String, pos: Vector3, yaw: float) -> Node:
	var piece := BuildPiece.new()
	piece.setup(kind, material, key, build_slots)
	piece.transform = Transform(BuildPiece.piece_basis(kind, yaw), pos)
	add_child(piece)
	build_slots[key] = piece
	return piece


func spawn_vehicle(kind: String, pos: Vector3, yaw: float) -> Node:
	var v: Node
	if kind == "boat":
		v = Boat.new()
	else:
		v = Vehicle.new()
		v.kind = kind
	v.translation = pos
	v.rotation.y = yaw
	add_child(v)
	return v


func _spawn_vehicles() -> void:
	for poi in pois:
		for def in poi.def.get("vehicles", []):
			var p := _poi_point(poi, def.at)
			var yaw: float = poi.frame_yaw + deg2rad(def.get("yaw", 0.0))
			if def.kind == "boat":
				var found := false
				for step in range(0, 28, 2):          # slide out to open water
					var q := _poi_point(poi, def.at + Vector2(step, 0))
					if q.y < -1.8:
						p = Vector3(q.x, Terrain.WATER_LEVEL + 0.4, q.z)
						found = true
						break
				if not found:
					continue
			else:
				p.y += 1.2
			spawn_vehicle(def.kind, p, yaw)
	# a few extra along the roads
	for i in range(2 if profile.mobile else 4):
		var seg: Array = poi_roads[rng.randi() % poi_roads.size()]
		var t := rng.randf_range(0.25, 0.75)
		var base: Vector2 = seg[0].linear_interpolate(seg[1], t)
		var dir: Vector2 = (seg[1] - seg[0]).normalized()
		var side := Vector2(-dir.y, dir.x) * 3.0
		var q := base + side
		var h: float = terrain.height_at(q.x, q.y)
		if h > 2.0:
			spawn_vehicle("quad" if i % 2 == 1 else "buggy", Vector3(q.x, h + 1.2, q.y), atan2(-dir.x, -dir.y))


func _spawn_boss() -> void:
	for poi in pois:
		var def: Dictionary = poi.def
		if not def.has("boss"):
			continue
		var p := _poi_point(poi, def.boss.at)
		var b := Bot.new()
		b.name = "Warden"
		b.is_boss = true
		b.world = self
		b.display_name = "The Warden"
		b.vest_color = Color(1.0, 0.72, 0.1)
		b.skill = 0.95
		b.map_half = MAP_HALF - 4.0
		b.translation = p + Vector3(0, 1.0, 0)
		add_child(b)
		b.connect("died", self, "_on_fighter_died")
		boss = b
		if hud:
			hud.add_feed("The Warden guards %s - Mythic loot!" % poi.name.capitalize(), Color(1.0, 0.45, 0.15))


# ------------------------------------------------------------------ props

func _scatter_props(model: String, count: int, smin: float, smax: float, col_radius: float, col_height: float, min_h: float, harvest_kind: String) -> void:
	var scene = load(MODEL_DIR + model + ".glb")
	if scene == null:
		return
	var transforms := []
	var scales := []
	var tries := 0
	while transforms.size() < count and tries < count * 10:
		tries += 1
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * MAP_HALF
		if p.length() > MAP_HALF * 0.84:
			continue
		var h: float = terrain.height_at(p.x, p.y)
		if h < min_h or not terrain.is_free(p.x, p.y, 2.5):
			continue
		var s := rng.randf_range(smin, smax)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		transforms.append(Transform(basis, Vector3(p.x, h - 0.1, p.y)))
		scales.append(s)
		if model == "tree":
			tree_positions.append(p)
	if transforms.empty():
		return

	var inst: Node = scene.instance()
	var mesh = _find_mesh(inst)
	inst.free()
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance.new()
	mmi.name = model.capitalize() + "s"
	mmi.multimesh = mm
	add_child(mmi)

	var body := StaticBody.new()
	body.name = model.capitalize() + "Colliders"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("harvest", harvest_kind)
	add_child(body)
	for i in range(transforms.size()):
		var cyl := CylinderShape.new()
		cyl.radius = col_radius * scales[i]
		cyl.height = col_height * scales[i]
		var cs := CollisionShape.new()
		cs.shape = cyl
		cs.translation = transforms[i].origin + Vector3(0, cyl.height / 2.0, 0)
		body.add_child(cs)
	_props[body.name] = {"mm": mm, "body": body, "hits": {}, "transforms": transforms}


# Pickaxe hit on a harvestable thing. Trees / rocks run out after a few swings.
func harvest_hit(body, shape_idx: int, kind: String, by) -> void:
	by.add_material(kind, 8 + rng.randi() % 5)
	if not _props.has(body.name):
		return
	var data: Dictionary = _props[body.name]
	var hits: int = data.hits.get(shape_idx, 0) + 1
	data.hits[shape_idx] = hits
	if hits >= 5 and shape_idx < data.body.get_child_count():
		var gone := Transform(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), data.transforms[shape_idx].origin)
		data.mm.set_instance_transform(shape_idx, gone)
		data.body.get_child(shape_idx).set_deferred("disabled", true)


# ------------------------------------------------------------------ containers, loot, fighters

func _interior_point(entry: Dictionary, local: Vector3) -> Vector3:
	var p: Vector2 = entry.pos
	var big: bool = entry.res == HOUSES[1]
	var l := Vector3(local.x * (1.25 if big else 1.0), 0.0, local.z * (1.15 if big else 1.0)).rotated(Vector3.UP, entry.yaw)
	return Vector3(p.x + l.x, terrain.height_at(p.x, p.y) + 0.15, p.y + l.z)


func _spawn_containers_and_loot(plan: Array) -> void:
	for entry in plan:
		if not entry.house:
			continue
		if rng.randf() < 0.85:
			_add_chest("chest", _interior_point(entry, Vector3(-2.7, 0, -2.3)), entry.yaw)
		if rng.randf() < 0.4:
			_add_chest("ammo_box", _interior_point(entry, Vector3(2.7, 0, -2.5)), entry.yaw)
		for local in [Vector3(2.5, 0, 1.2), Vector3(-2.4, 0, 1.5)]:
			var it: Dictionary = Items.random_weapon(rng) if rng.randf() < 0.5 else Items.random_floor_item(rng)
			spawn_item(it, _interior_point(entry, local) + Vector3(0, 0.1, 0))

	var placed := 0
	var tries := 0
	while placed < profile.floor_items and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * MAP_HALF * 0.78
		var h: float = terrain.height_at(p.x, p.y)
		if h < 2.5 or _near_tree(p, 2.5):
			continue
		spawn_item(Items.random_floor_item(rng), Vector3(p.x, h + 0.1, p.y))
		placed += 1
	placed = 0
	tries = 0
	while placed < profile.outdoor_chests and tries < 300:
		tries += 1
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * MAP_HALF * 0.74
		var h: float = terrain.height_at(p.x, p.y)
		if h < 2.5 or _near_building(p, 12.0) or _near_tree(p, 3.0):
			continue
		_add_chest("chest" if placed % 2 == 0 else "ammo_box", Vector3(p.x, h, p.y), rng.randf() * TAU)
		placed += 1


func _add_chest(kind: String, pos: Vector3, yaw: float) -> Node:
	var c := Chest.new()
	c.kind = kind
	c.translation = pos
	c.rotation.y = yaw
	add_child(c)
	return c


func spawn_item(item: Dictionary, pos: Vector3) -> Node:
	var li := LootItem.new()
	li.setup(item)
	li.translation = pos
	add_child(li)
	return li


func _drop_inventory(victim) -> void:
	var pos: Vector3 = victim.global_transform.origin
	var n := 0
	for i in range(1, victim.slots.size()):
		var it = victim.slots[i]
		if it == null:
			continue
		var a := float(n) * 1.7
		spawn_item(it.duplicate(), pos + Vector3(cos(a), 0.2, sin(a)) * 1.1)
		n += 1
		if it.kind == "weapon":
			var ammo := Items.make_ammo(Items.WEAPONS[it.id].ammo, Items.AMMO[Items.WEAPONS[it.id].ammo].pack)
			spawn_item(ammo, pos + Vector3(cos(a + 1.0), 0.2, sin(a + 1.0)) * 1.4)


func _near_building(p: Vector2, dist: float) -> bool:
	for b in building_positions:
		if b.distance_to(p) < dist:
			return true
	return false


func _near_tree(p: Vector2, dist: float) -> bool:
	for t in tree_positions:
		if t.distance_to(p) < dist:
			return true
	return false


func _spawn_point(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y) + 1.0, p.y)


func _find_spawn(taken: Array, min_dist: float, rmin: float, rmax: float) -> Vector2:
	var best := Vector2.ZERO
	for i in range(120):
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax) * MAP_HALF
		var p := Vector2(cos(a), sin(a)) * r
		best = p
		if terrain.height_at(p.x, p.y) < 2.5 or _near_building(p, 10.0) or _near_tree(p, 7.0):
			continue
		var ok := true
		for t in taken:
			if t.distance_to(p) < min_dist:
				ok = false
				break
		if ok:
			return p
	return best


func _spawn_fighters() -> void:
	var taken := []
	var ppos := _find_spawn(taken, 0.0, 0.55, 0.7)
	player = Player.new()
	player.name = "Player"
	player.map_half = MAP_HALF - 4.0
	player.translation = _spawn_point(ppos)
	add_child(player)
	player.rotation.y = atan2(ppos.x, ppos.y)      # face the island centre
	player.connect("died", self, "_on_fighter_died")
	taken.append(ppos)
	for i in range(profile.bots):
		var p := _find_spawn(taken, 32.0, 0.1, 0.78)
		taken.append(p)
		var bot := Bot.new()
		bot.name = "Bot%d" % i
		bot.world = self
		bot.display_name = BOT_NAMES[i % BOT_NAMES.size()]
		bot.vest_color = BOT_COLORS[i % BOT_COLORS.size()]
		bot.skill = rng.randf_range(0.2, 0.85)
		bot.map_half = MAP_HALF - 4.0
		bot.translation = _spawn_point(p)
		bot.jump_at = rng.randf_range(110.0, 380.0)
		add_child(bot)
		bot.rotation.y = rng.randf() * TAU
		bot.connect("died", self, "_on_fighter_died")


func _start_bus() -> void:
	var a := rng.randf() * TAU
	var dir := Vector3(cos(a), 0.0, sin(a))
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var start := -dir * (BUS_LENGTH / 2.0) + perp * rng.randf_range(-45.0, 45.0) + Vector3(0, BUS_ALTITUDE, 0)
	bus = Bus.new()
	bus.name = "Bus"
	add_child(bus)
	bus.setup(start, dir, BUS_LENGTH)
	bus.connect("finished", self, "_on_bus_finished")
	for f in get_tree().get_nodes_in_group("fighters"):
		if "is_boss" in f and f.is_boss:
			continue
		f.enter_bus(bus)
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.pitch = -0.2


func _on_bus_finished() -> void:
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.mode == 1:
			f.leave_bus()
	storm.active = true


func alive_count() -> int:
	var n := 0
	for f in get_tree().get_nodes_in_group("fighters"):
		if not f.is_dead:
			n += 1
	return n


func random_point_in_safe_zone() -> Vector3:
	for i in range(12):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * max(storm.radius - 6.0, 3.0)
		var p: Vector2 = storm.center + Vector2(cos(a), sin(a)) * r
		var h: float = terrain.height_at(p.x, p.y)
		if h > 2.0:
			return Vector3(p.x, h, p.y)
	return Vector3(storm.center.x, 10.0, storm.center.y)


func random_point_near(pos: Vector3, radius: float) -> Vector3:
	for i in range(14):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := Vector2(pos.x + cos(a) * r, pos.z + sin(a) * r)
		if p.length() > MAP_HALF * 0.8:
			continue
		var h: float = terrain.height_at(p.x, p.y)
		if h > 2.0:
			return Vector3(p.x, h, p.y)
	return random_point_in_safe_zone()


func location_name(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	for poi in pois:
		if p.distance_to(poi.center) < poi.zone + 6.0:
			return poi.name
	if p.length() < 62.0:
		return "MAPLE SQUARE"
	if _near_building(p, 22.0):
		return "LONE HOUSE"
	if terrain.height_at(p.x, p.y) < 1.5:
		return "SHORELINE"
	return "OPEN FIELDS"


func _on_player_damaged(_amount, source) -> void:
	if source != null:
		player.combat_until = OS.get_ticks_msec() / 1000.0 + 8.0


func _audio_process(delta: float) -> void:
	if player == null or storm == null or match_over:
		return
	var pp: Vector3 = player.global_transform.origin
	_amb_t -= delta
	if _amb_t <= 0.0:
		_amb_t = 0.2
		var airborne: bool = player.mode == 1 or player.mode == 2 or player.mode == 3
		Audio.ambient("ambient_loop", -30.0 if airborne else -22.0)
		var h: float = terrain.height_at(pp.x, pp.z)
		var waves := Audio.SILENT_DB
		if not airborne:
			if h < 5.0:
				waves = lerp(-8.0, -20.0, clamp(h / 5.0, 0.0, 1.0))
			elif Vector2(pp.x, pp.z).length() > MAP_HALF * 0.7:
				waves = -24.0
		Audio.ambient("waves_loop", waves)
		var storm_db := Audio.SILENT_DB
		if storm.active:
			var inside: float = storm.radius - Vector2(pp.x - storm.center.x, pp.z - storm.center.y).length()
			if inside < 45.0:
				storm_db = lerp(-5.0, -34.0, clamp(inside / 45.0, 0.0, 1.0))
		Audio.ambient("storm_loop", storm_db)
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = rng.randf_range(5.0, 12.0)
		if player.mode == 0 and terrain.height_at(pp.x, pp.z) > 3.0:
			var a := rng.randf() * TAU
			var r := rng.randf_range(14.0, 28.0)
			Audio.play3d("bird_%d" % (1 + rng.randi() % 3), pp + Vector3(cos(a) * r, 7.0, sin(a) * r), -11.0, rng.randf_range(0.9, 1.15))
	if storm.active and _last_waiting and not storm.waiting and not storm.finished:
		Audio.play2d("storm_warn", -3.0)
		if hud:
			hud.add_feed("The storm is closing in!", Color(0.8, 0.6, 1.0))
	_last_waiting = storm.waiting
	_music_t -= delta
	if _music_t <= 0.0:
		_music_t = 0.5
		var want := "music_game"
		if player.mode == 1 or player.mode == 2 or player.mode == 3:
			want = "music_bus"
		elif OS.get_ticks_msec() / 1000.0 < player.combat_until:
			want = "music_combat"
		Audio.music(want, 2.0)


func _process(delta: float) -> void:
	_audio_process(delta)
	for sp in _spinners:
		if is_instance_valid(sp.node):
			if sp.kind == "blades":
				sp.node.rotate_object_local(Vector3(0, 0, 1), delta * 0.9)
			else:
				sp.node.rotate_y(delta * 0.6)
	if storm == null or not storm.active or storm.finished:
		return
	if storm.waiting and storm.phase != _supply_phase:
		_supply_phase = storm.phase
		if storm.phase % 2 == 0:
			_spawn_supply()


func _spawn_supply() -> void:
	var p := random_point_in_safe_zone()
	var c := _add_chest("supply", p, rng.randf() * TAU)
	c.start_fall(150.0, p.y)
	if hud:
		hud.add_feed("A supply drop is on its way!", Color(1.0, 0.45, 0.35))


func _on_fighter_died(victim, killer) -> void:
	var alive := alive_count()
	var text := ""
	var color := Color.white
	if killer == null:
		text = "%s was lost to the storm" % victim.display_name
		color = Color(0.8, 0.6, 1.0)
	else:
		text = "%s eliminated %s" % [killer.display_name, victim.display_name]
		if killer == player:
			color = Color(1.0, 0.85, 0.3)
		elif victim == player:
			color = Color(1.0, 0.45, 0.4)
	if hud:
		hud.add_feed(text, color)
	_drop_inventory(victim)

	if match_over:
		return
	if victim == player:
		match_over = true
		get_tree().create_timer(1.8).connect("timeout", hud, "show_end", [false, alive + 1, player.kills])
	elif alive <= 1 and not player.is_dead:
		match_over = true
		get_tree().create_timer(1.2).connect("timeout", hud, "show_end", [true, 1, player.kills])


func _input(event: InputEvent) -> void:
	if Controls.touch_mode or match_over:
		return
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Controls.capture_mouse(true)
	elif event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		Controls.capture_mouse(false)

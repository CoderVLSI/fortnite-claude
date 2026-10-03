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
const Menu = preload("res://scripts/Menu.gd")
const Lobby = preload("res://scripts/Lobby.gd")
const VendingMachine = preload("res://scripts/VendingMachine.gd")
const Pois = preload("res://scripts/Pois.gd")
const BuildPiece = preload("res://scripts/BuildPiece.gd")
const Vehicle = preload("res://scripts/Vehicle.gd")
const Boat = preload("res://scripts/Boat.gd")
const Rift = preload("res://scripts/Rift.gd")
const AutoDoor = preload("res://scripts/AutoDoor.gd")
const WildSprite = preload("res://scripts/WildSprite.gd")
const RemotePlayer = preload("res://scripts/RemotePlayer.gd")
const VehicleCommon = preload("res://scripts/VehicleCommon.gd")
const GrenadeScript = preload("res://scripts/Grenade.gd")
const JunkRiftScript = preload("res://scripts/JunkRift.gd")
const FighterScript = preload("res://scripts/Fighter.gd")
const SpriteCreature = preload("res://scripts/SpriteCreature.gd")
const Sprites = preload("res://scripts/Sprites.gd")
const Skins = preload("res://scripts/Skins.gd")
const Cosmetics = preload("res://scripts/Cosmetics.gd")

const MAP_HALF := 360.0                  # a 720 m island (it was 480 m): room for 50 players
const MAP_SCALE := MAP_HALF / 160.0      # POI radii and spacing are authored for the old 160 m island
const SEED := 20241002
const MODEL_DIR := "res://assets/models/"
const HOUSES := ["house_a", "house_b"]
# front door of each building model: [half depth, door width, door height]; they get a door that opens by itself
const DOORS := {"house_a": [3.5, 1.3, 2.25], "house_b": [4.0, 1.3, 2.25], "lodge": [5.0, 1.8, 2.5], "cabin": [2.75, 1.3, 2.25],
	"barn": [7.0, 3.4, 3.4], "warehouse": [5.5, 4.0, 4.2], "bunker": [4.0, 1.8, 2.4], "keeper_house": [2.5, 1.3, 2.25],
	"highrise_a": [5.5, 2.4, 2.8], "highrise_b": [6.0, 2.4, 2.8], "highrise_c": [6.5, 2.4, 2.8]}
# how many pickaxe hits a building takes before it comes down
const STRUCTURE_SINK := {"highrise_a": 24.0, "highrise_b": 32.0, "highrise_c": 44.0}
const STRUCTURE_HITS := {"house_a": 16, "house_b": 22, "lodge": 30, "cabin": 12, "barn": 34, "warehouse": 40, "bunker": 60, "keeper_house": 14,
	"tower": 50, "silo": 26, "watchtower": 18, "windmill": 30, "lighthouse": 45, "highrise_a": 70, "highrise_b": 95, "highrise_c": 130, "container": 14, "tank": 22, "crane": 28, "chimney": 16, "radar": 18}
const BUS_ALTITUDE := 260.0
const BUS_LENGTH := 1000.0
const BOT_NAMES := ["Rook", "Nova", "Echo", "Blitz", "Sable", "Juno", "Kestrel", "Moxie", "Vesper", "Dash",
	"Onyx", "Pixel", "Zephyr", "Ember", "Gizmo", "Havoc", "Indigo", "Lynx", "Maverick", "Nimbus",
	"Orbit", "Pepper", "Quill", "Riot", "Sprout"]
const BOT_COLORS := [Color(0.85, 0.25, 0.22), Color(0.90, 0.60, 0.15), Color(0.70, 0.25, 0.80),
	Color(0.20, 0.70, 0.65), Color(0.85, 0.80, 0.20), Color(0.90, 0.40, 0.60)]

var rng := RandomNumberGenerator.new()
var profile := {}
var perf                      # Perf.gd: distance culling + the automatic graphics governor
var terrain
var storm
var player
var hud
var bus = null
var building_positions := []     # Vector2 (x, z) for the minimap
var tree_positions := []         # Vector2 (x, z), used to keep spawns out of foliage
var spectating := false           # watching the remaining fighters after being eliminated
var _spec_target = null
var _spec_cam: Camera
var match_over := false

var shared := {}                 # cached meshes/materials shared by loot items
var pois := []                   # runtime POIs: {id, name, center (Vector2), frame_yaw, def, zone}
var poi_roads := []              # [Vector2 a, Vector2 b] for the map
var boss = null
var menu
var sun: DirectionalLight
var build_slots := {}            # grid key -> BuildPiece
var _spinners := []
var _props := {}                 # model name -> {mm, body, hits}
var _supply_phase := -1
var net_match := false           # a network match: the island is built from the shared seed
var _net_pose_t := 0.0
var _net_bots_t := 0.0
var _net_storm_t := 0.0
var net_nodes := {}               # network id -> node (loot, chests, wild sprites, rifts, buildings)
var _loot_seq := 0
var _chest_seq := 0
var _struct_seq := 0
var _wild_seq := 0
var _rift_seq := 0
var _veh_seq := 0
var _net_veh_t := 0.0
var net_live := false            # true once the match has started on this machine
var _amb_t := 0.0
var _bird_t := 6.0
var _music_t := 0.0
var _last_waiting := true


func _ready() -> void:
	add_to_group("world")
	net_match = Net.active and Net.in_match
	rng.seed = SEED
	profile = _make_profile()
	_setup_environment()
	apply_quality()
	perf = preload("res://scripts/Perf.gd").new()
	perf.setup(self)
	add_child(perf)

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
	var storm_rng := RandomNumberGenerator.new()
	if net_match:
		storm_rng.seed = Net.match_seed + 17
	else:
		storm_rng.randomize()
	storm.setup(MAP_HALF - 8.0, storm_rng)

	if net_match:
		rng.seed = Net.match_seed          # every machine builds the same loot, chests and spawns
	else:
		rng.randomize()      # same island every match, different spawns/loot
	_spawn_containers_and_loot(plan)
	_spawn_poi_loot()
	_spawn_fighters()
	_spawn_boss()
	_spawn_vehicles()
	_spawn_vending()
	_spawn_rifts_and_sprites()
	if profile.use_bus:
		_start_bus()

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(self)
	player.connect("damaged", self, "_on_player_damaged")
	player.connect("damage_dealt", self, "_on_player_dealt")
	var lobby := Lobby.new()
	lobby.name = "Lobby"
	add_child(lobby)
	menu = Menu.new()
	menu.name = "Menu"
	menu.lobby = lobby
	add_child(menu)
	menu.bind(self)
	hud.root.visible = false
	if net_match:
		Settings.autostart = false
		Net.connect("match_go", self, "_on_net_go", [], CONNECT_ONESHOT)
		menu.show_waiting("WAITING FOR THE OTHER PLAYERS...")
		Net.world_ready(self)
	elif "--skip-menu" in OS.get_cmdline_args() or Settings.autostart:
		Settings.autostart = false
		menu.start_game()
	else:
		menu.show_splash()


# Called by the menu when the player presses Play (or immediately with --skip-menu).
func on_game_started() -> void:
	hud.root.visible = true
	_match_start_ms = OS.get_ticks_msec()
	player.match_stats = {}
	player.apply_loadout(Settings.loadout)
	if Settings.starter_sprite != "none" and not ("--skip-menu" in OS.get_cmdline_args()):
		player.equip_sprite(Settings.starter_sprite)
	Audio.music("music_bus" if profile.use_bus else "music_game", 0.5)
	if boss != null and is_instance_valid(boss):
		for poi in pois:
			if poi.def.has("boss"):
				hud.add_feed("The Warden guards %s - Mythic loot!" % poi.name.capitalize(), Color(1.0, 0.45, 0.15))


func apply_quality() -> void:
	var q: int = Settings.quality
	if sun != null:
		sun.shadow_enabled = q >= 1 and not profile.get("force_no_shadows", false)
	get_viewport().msaa = Viewport.MSAA_4X if q >= 2 else (Viewport.MSAA_2X if q == 1 and not profile.mobile else Viewport.MSAA_DISABLED)


func _make_profile() -> Dictionary:
	var args := OS.get_cmdline_args()
	var mobile := OS.has_feature("mobile") or ("--mobile" in args)
	var p := {
		"mobile": mobile,
		"bots": 28 if mobile else 49,
		"trees": 520 if mobile else 1500,
		"rocks": 80 if mobile else 200,
		"outlying": 24 if mobile else 40,
		"floor_items": 70 if mobile else 150,
		"outdoor_chests": 10 if mobile else 20,
		"shadows": not mobile,
		"cell": 5.0 if mobile else 4.0,
		"use_bus": not ("--no-bus" in args),
	}
	if Net.active and Net.in_match:
		p.bots = Net.bot_count
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
	env.fog_depth_end = 380.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 0.95
	sun.shadow_enabled = Settings.quality >= 1
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight.SHADOW_PARALLEL_2_SPLITS
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
		inst.add_to_group("structures")
		_add_trimesh_collision(inst, "metal" if entry.res == "tower" else "wood", inst, entry.res)
		_add_door(inst, entry.res)
		building_positions.append(p)


func _add_trimesh_collision(node: Node, harvest_kind: String, root: Node = null, res: String = "") -> void:
	if node is MeshInstance:
		node.create_trimesh_collision()
	for c in node.get_children():
		if c is StaticBody:
			c.set_meta("harvest", harvest_kind)
			if root != null:
				c.set_meta("structure", root)
		_add_trimesh_collision(c, harvest_kind, root, res)
	if root != null and node == root:
		root.set_meta("net_id", "b%d" % _struct_seq)
		net_nodes["b%d" % _struct_seq] = root
		_struct_seq += 1
		root.set_meta("hits_max", STRUCTURE_HITS.get(res, 20))
		root.set_meta("sink", STRUCTURE_SINK.get(res, 6.0))
		root.set_meta("hits", 0)


func _add_door(inst: Spatial, res: String) -> void:
	if not DOORS.has(res):
		return
	var d: Array = DOORS[res]
	var door := AutoDoor.new()
	door.door_w = d[1]
	door.door_h = d[2]
	door.translation = Vector3(0, 0.12, d[0])
	inst.add_child(door)


# A structure that has taken enough pickaxe hits: its colliders vanish and it sinks into a cloud of dust.
func collapse_and_sync(root: Spatial) -> void:
	if net_live and root.has_meta("net_id"):
		Net.send_event("collapse", root.get_meta("net_id"))
	_collapse(root)


func _collapse(root: Spatial) -> void:
	if root.has_meta("fallen"):
		return
	root.set_meta("fallen", true)
	var pos := root.global_transform.origin
	_strip_colliders(root)
	Audio.play3d("explosion", pos + Vector3(0, 2, 0), -4.0, 0.6)
	Audio.play3d("building_collapse", pos, 2.0)
	var dust := preload("res://scripts/SpriteCreature.gd").particles(Color(0.72, 0.68, 0.6, 0.8), 70, 1.8, 6.0, 80.0, 3.0, 4.0)
	dust.one_shot = true
	dust.explosiveness = 0.85
	add_child(dust)
	dust.global_transform.origin = pos + Vector3(0, 1.5, 0)
	get_tree().create_timer(3.0).connect("timeout", dust, "queue_free")
	var tween := Tween.new()
	add_child(tween)
	tween.interpolate_property(root, "translation:y", root.translation.y, root.translation.y - float(root.get_meta("sink") if root.has_meta("sink") else 6.0), 1.6 if not root.has_meta("sink") or root.get_meta("sink") < 10.0 else 3.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.interpolate_property(root, "rotation:z", root.rotation.z, root.rotation.z + rand_range(-0.12, 0.12), 1.6, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.start()
	get_tree().create_timer(1.8 if not root.has_meta("sink") or root.get_meta("sink") < 10.0 else 3.2).connect("timeout", root, "queue_free")


func _strip_colliders(node: Node) -> void:
	for c in node.get_children():
		if c is StaticBody:
			c.collision_layer = 0
			for k in c.get_children():
				if k is CollisionShape:
					k.set_deferred("disabled", true)
		_strip_colliders(c)


func _find_mesh(node: Node):
	if node is MeshInstance:
		return node.mesh
	for c in node.get_children():
		var m = _find_mesh(c)
		if m != null:
			return m
	return null


# ------------------------------------------------------------------ points of interest

# Pick a POI centre: near its authored angle, on good ground for its mode, and clear of the town and every POI already
# placed. The first pass fans out a few degrees either side of the authored angle and radius band (preferring the
# authored spot); if that finds nothing it searches the whole sector and a wider radius band, and as a last resort
# takes the spot with the most clearance.
func _locate_poi(def: Dictionary, placed: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -1e9
	var roomiest := Vector2.ZERO
	var most_room := -1e9
	for attempt in range(2):
		var fan: Array = [0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0, 20.0, -20.0, 26.0, -26.0, 32.0, -32.0, 40.0, -40.0, 50.0, -50.0]
		var rmin: float = def.get("rmin", 60.0) * MAP_SCALE
		var rmax: float = def.get("rmax", 90.0) * MAP_SCALE
		if attempt == 1:
			fan = []
			for k in range(0, 21):
				fan.append(float(k) * 9.0 * (1.0 if k % 2 == 0 else -1.0) / 1.0)
			rmin = max(rmin * 0.8, 78.0)
			rmax = min(rmax * 1.2, MAP_HALF * 0.74)
		for da in fan:
			var a := deg2rad(def.angle + da)
			var dir := Vector2(cos(a), sin(a))
			var cands := []                           # [centre, score]
			if def.mode == "shore":
				var r_land := 0.0
				for r in range(60, int(MAP_HALF) - 5, 2):
					if terrain.raw_height(dir.x * r, dir.y * r) > 1.5:
						r_land = float(r)
				if r_land > 0.0:
					cands.append([dir * (r_land - def.inland), 0.0])
			else:
				var r := rmin
				while r <= rmax:
					var c := dir * r
					var h: float = terrain.raw_height(c.x, c.y)
					var on_land := true             # the whole flattened pad must be land, or it would cut a cliff into the beach
					for k in range(8):
						var edge := c + Vector2(cos(k * PI / 4.0), sin(k * PI / 4.0)) * (float(def.zone) + 6.0)
						if terrain.raw_height(edge.x, edge.y) < 2.0:
							on_land = false
							break
					if h > 4.0 and on_land:
						var variance := 0.0
						for k in range(8):
							var q := c + Vector2(cos(k * PI / 4.0), sin(k * PI / 4.0)) * 16.0
							variance += abs(terrain.raw_height(q.x, q.y) - h)
						cands.append([c, (h * 0.5 if def.mode == "hill" else 0.0) - variance])
					r += 3.0 * MAP_SCALE
			for cand in cands:
				var room := 1e9                       # smallest gap to the town or an earlier POI (negative = overlap)
				for q in placed:
					room = min(room, cand[0].distance_to(q.center) - def.zone - q.zone)
				if room > most_room:
					most_room = room
					roomiest = cand[0]
				var score: float = cand[1] - abs(da) * 0.25
				if room >= 6.0 and score > best_score:
					best_score = score
					best = cand[0]
		if best_score > -1e9:
			return best
	return roomiest if most_room > -1e9 else Vector2(cos(deg2rad(def.angle)), sin(deg2rad(def.angle))) * 90.0


func _plan_pois() -> void:
	var centers := {"maple": Vector2.ZERO}
	var placed := [{"center": Vector2.ZERO, "zone": 62.0}]      # the town pad
	# Shore POIs have only one possible spot per angle, so place them first; the inland ones then fit around them.
	var order := []
	for def in Pois.POIS:
		if def.mode == "shore":
			order.append(def)
	for def in Pois.POIS:
		if def.mode != "shore":
			order.append(def)
	for def in order:
		var c := _locate_poi(def, placed)
		placed.append({"center": c, "zone": def.zone})
		centers[def.id] = c
	for def in Pois.POIS:                                         # keep the authored order for the lists and the map
		var c: Vector2 = centers[def.id]
		terrain.add_zone(c.x, c.y, def.zone)
		pois.append({"id": def.id, "name": def.name, "center": c, "frame_yaw": -atan2(c.y, c.x), "def": def, "zone": def.zone})   # local +X points away from the island centre
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
			inst.add_to_group("structures")
			if pr.has("tint"):
				Items.apply_accent(inst, pr.tint)
			if not pr.get("decor", false):
				_add_trimesh_collision(inst, pr.get("harvest", "wood"), inst, pr.res)
				_add_door(inst, pr.res)
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
		return [Vector3(n.pos.x + l.x, n.pos.y + 0.15 + entry.get("y", 0.0), n.pos.z + l.z), n.yaw + deg2rad(entry.get("yaw", 0.0))]
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


# ------------------------------------------------------------------ vending machines

const VENDING_KINDS := ["weapons", "healing", "utility"]
const VENDING_SPOTS := [Vector2(4, 18), Vector2(-6, 19), Vector2(22, -4), Vector2(-12, -18), Vector2(8, -20), Vector2(-20, 6)]


func _spawn_vending() -> void:
	var plaza := [Vector2(7, 9), Vector2(-7, 9), Vector2(0, -11)]       # one of each around the town tower
	for i in range(3):
		add_vending(VENDING_KINDS[i], plaza[i], Vector2.ZERO)
	var n := 0
	for poi in pois:
		var spot := _vending_spot(poi)
		if spot != Vector2.INF:
			add_vending(VENDING_KINDS[n % 3], spot, poi.center)
			n += 1


# Rifts (single-use portals to the sky) and wild Sprites. Own random stream, so the rest of the island is unchanged.
func _spawn_rifts_and_sprites() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = SEED + 4242
	var rifts := 0
	var sprites := 0
	var tries := 0
	var want_sprites: int = 18 if profile.mobile else 40
	while (rifts < 14 or sprites < want_sprites) and tries < 900:
		tries += 1
		var p := Vector2(rr.randf_range(-1.0, 1.0), rr.randf_range(-1.0, 1.0)) * MAP_HALF * 0.8
		if p.length() < 40.0 or p.length() > MAP_HALF * 0.7:
			continue
		var h: float = terrain.height_at(p.x, p.y)
		if h < 3.0 or not terrain.is_free(p.x, p.y, 4.0) or _near_building(p, 8.0) or _near_tree(p, 3.0):
			continue
		if rifts < 14 and (sprites >= want_sprites or rr.randf() < 0.4):
			var ok := true
			for r in get_tree().get_nodes_in_group("rifts"):
				if Vector2(r.translation.x, r.translation.z).distance_to(p) < 60.0:
					ok = false
			if ok:
				add_rift(Vector3(p.x, h, p.y), 0.0)
				rifts += 1
		elif sprites < want_sprites:
			add_wild_sprite(Sprites.random_wild(rr), Vector3(p.x, h + 0.9, p.y))
			sprites += 1


func add_wild_sprite(data: Dictionary, pos: Vector3, nid: String = "") -> Node:
	var ws := WildSprite.new()
	ws.data = data.duplicate()
	ws.terrain = terrain
	ws.translation = pos
	if nid == "":
		if net_live:
			nid = Net.new_id("w")
			Net.send_event("wild", [nid, data, pos])
		else:
			nid = "w%d" % _wild_seq
			_wild_seq += 1
	ws.net_id = nid
	net_nodes[nid] = ws
	add_child(ws)
	return ws


func add_rift(pos: Vector3, lifetime: float, nid: String = "") -> Node:
	var rift := Rift.new()
	rift.lifetime = lifetime
	rift.translation = pos
	if nid == "":
		if net_live:
			nid = Net.new_id("r")
			Net.send_event("rift", [nid, pos, lifetime])
		else:
			nid = "r%d" % _rift_seq
			_rift_seq += 1
	rift.net_id = nid
	net_nodes[nid] = rift
	add_child(rift)
	return rift


# A free spot around a POI: on land, away from its buildings and props.
func _vending_spot(poi: Dictionary) -> Vector2:
	for c in VENDING_SPOTS:
		var p3 := _poi_point(poi, c)
		var p := Vector2(p3.x, p3.z)
		if p3.y < 1.0 or _near_building(p, 6.0):
			continue
		var clear := true
		for nd in poi.get("nodes", []):
			if nd != null and Vector2(nd.pos.x, nd.pos.z).distance_to(p) < 7.0:
				clear = false
				break
		if clear:
			return p
	return Vector2.INF


func add_vending(kind: String, pos: Vector2, face_to: Vector2) -> Node:
	var v := VendingMachine.new()
	v.kind = kind
	v.translation = Vector3(pos.x, terrain.height_at(pos.x, pos.y), pos.y)
	var to := (face_to - pos)
	if to.length() > 0.1:
		v.rotation.y = atan2(-to.x, -to.y)                         # the front (-Z) looks at the town / POI middle
	add_child(v)
	return v


func spawn_vehicle(kind: String, pos: Vector3, yaw: float) -> Node:
	var v: Node
	if kind == "boat":
		v = Boat.new()
	else:
		v = Vehicle.new()
		v.kind = kind
	v.translation = pos
	v.rotation.y = yaw
	v.net_id = "v%d" % _veh_seq
	net_nodes[v.net_id] = v
	_veh_seq += 1
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
	for i in range(6 if profile.mobile else 12):
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
		if model == "tree":       # lava fields are bare and deserts nearly so; snow keeps its pines (drawn last: same stream as before)
			var bw: Vector3 = terrain.biome_weights(p.x, p.y)
			if fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0) < bw.y * 1.1 + bw.z * 0.85:
				continue
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
	# One MultiMesh per 80 m square, so the renderer can skip (and not shadow) the squares that are out of view.
	var cells := {}
	var slots := []
	for i in range(transforms.size()):
		var o: Vector3 = transforms[i].origin
		var key := Vector2(floor(o.x / 80.0), floor(o.z / 80.0))
		if not cells.has(key):
			cells[key] = []
		slots.append([key, cells[key].size()])
		cells[key].append(i)
	var mms := {}
	for key in cells:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = cells[key].size()
		for k in range(cells[key].size()):
			mm.set_instance_transform(k, transforms[cells[key][k]])
		var mmi := MultiMeshInstance.new()
		mmi.name = model.capitalize() + "s"
		mmi.multimesh = mm
		add_child(mmi)
		mmi.add_to_group("scenery")
		mms[key] = mm
	var mm_of := []
	for sl in slots:
		mm_of.append([mms[sl[0]], sl[1]])

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
	_props[body.name] = {"mm_of": mm_of, "body": body, "hits": {}, "transforms": transforms}


# Pickaxe hit on a harvestable thing. Trees / rocks run out after a few swings.
const HARVEST_HITS := 5
const HARVEST_LABELS := {"wood": "TREE", "stone": "ROCK", "metal": "METAL"}


func harvest_hit(body, shape_idx: int, kind: String, by, at: Vector3 = Vector3.ZERO) -> void:
	var yield_mult: float = 1.0 + 0.25 * by.sprite_level() if by.has_sprite("king") else 1.0
	by.add_material(kind, int((8 + rng.randi() % 5) * yield_mult))
	var local_hit: bool = by.net_owner == 0 and net_live
	if body.has_meta("structure"):
		var root = body.get_meta("structure")
		_structure_hit(root, kind, by, at)
		if local_hit and is_instance_valid(root) and root.has_meta("net_id"):
			Net.send_event("harvest", ["S", root.get_meta("net_id"), kind])
		return
	if not _props.has(body.name):
		return
	_prop_hit(body.name, shape_idx, kind, by, at)
	if local_hit:
		Net.send_event("harvest", ["P", body.name, shape_idx, kind])


func _structure_hit(root, kind: String, by, at: Vector3) -> void:
	if is_instance_valid(root) and root.has_meta("hits_max") and not root.has_meta("fallen"):
		var sh: int = int(root.get_meta("hits")) + 1
		root.set_meta("hits", sh)
		var smax: int = int(root.get_meta("hits_max"))
		if by != null:
			by.emit_signal("harvested", at, clamp(1.0 - float(sh) / smax, 0.0, 1.0), kind, "BUILDING", "struct:%d" % root.get_instance_id())
		if sh >= smax:
			_collapse(root)


func _prop_hit(body_name: String, shape_idx: int, kind: String, by, at: Vector3) -> void:
	var data: Dictionary = _props[body_name]
	var hits: int = data.hits.get(shape_idx, 0) + 1
	data.hits[shape_idx] = hits
	var left: float = clamp(1.0 - float(hits) / HARVEST_HITS, 0.0, 1.0)
	if by != null:
		by.emit_signal("harvested", at, left, kind, HARVEST_LABELS.get(kind, kind.to_upper()), "%s:%d" % [body_name, shape_idx])
	if hits >= HARVEST_HITS and shape_idx < data.body.get_child_count():
		var gone := Transform(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), data.transforms[shape_idx].origin)
		data.mm_of[shape_idx][0].set_instance_transform(data.mm_of[shape_idx][1], gone)
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


func _add_chest(kind: String, pos: Vector3, yaw: float, forced_id: String = "", forced_seed: int = 0) -> Node:
	var c := Chest.new()
	c.kind = kind
	c.translation = pos
	c.rotation.y = yaw
	if forced_id != "":
		c.net_id = forced_id
		c.seed_value = forced_seed
	else:
		c.net_id = "c%d" % _chest_seq
		_chest_seq += 1
		c.seed_value = rng.randi() + 1           # the same loot on every machine
	net_nodes[c.net_id] = c
	add_child(c)
	return c


# nid: given by a network event or a chest (deterministic); empty = created here, so the other machines are told.
func spawn_item(item: Dictionary, pos: Vector3, nid: String = "") -> Node:
	var li := LootItem.new()
	li.setup(item)
	li.translation = pos
	if nid == "":
		if net_live:
			nid = Net.new_id("d")
			Net.send_event("spawn", [nid, item, pos])
		else:
			nid = "f%d" % _loot_seq
			_loot_seq += 1
	li.net_id = nid
	net_nodes[nid] = li
	add_child(li)
	return li


# This machine removed something (picked it up...): the others remove their copy.
func net_item_taken(node) -> void:
	if node.net_id != "":
		net_nodes.erase(node.net_id)
		if net_live:
			Net.send_event("gone", node.net_id)


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
	if victim.gold >= 5:
		var ag := float(n) * 1.7 + 0.3
		spawn_item(Items.make_gold(victim.gold), pos + Vector3(cos(ag), 0.2, sin(ag)) * 1.3)
		n += 1
	for kind in Items.MATERIAL_NAMES:                  # and whatever materials they were carrying
		var have: int = victim.materials.get(kind, 0)
		if have >= 10:
			var a2 := float(n) * 1.7 + 0.6
			spawn_item(Items.make_material(kind, have), pos + Vector3(cos(a2), 0.2, sin(a2)) * 1.2)
			n += 1


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
	var humans: Array = Net.order if net_match else [0]
	for hi in range(humans.size()):
		var hid: int = humans[hi]
		var ppos := _find_spawn(taken, 0.0 if hi == 0 else 24.0, 0.55, 0.7)
		taken.append(ppos)
		if not net_match or hid == Net.my_id:
			player = Player.new()
			player.name = "Player"
			player.map_half = MAP_HALF - 4.0
			player.translation = _spawn_point(ppos)
			add_child(player)
			player.rotation.y = atan2(ppos.x, ppos.y)      # face the island centre
			player.connect("died", self, "_on_fighter_died")
			if net_match:
				player.net_key_v = Net.my_id
		else:
			var rp := RemotePlayer.new()
			rp.name = "Remote%d" % hid
			rp.peer_id = hid
			rp.player_name = Net.members[hid].name if Net.members.has(hid) else "PLAYER"
			rp.color = BOT_COLORS[(hi + 3) % BOT_COLORS.size()]
			rp.loadout = Net.members[hid].loadout if Net.members.has(hid) else {}
			rp.map_half = MAP_HALF - 4.0
			rp.translation = _spawn_point(ppos)
			add_child(rp)
	for i in range(profile.bots):
		var p := _find_spawn(taken, 32.0, 0.1, 0.78)
		taken.append(p)
		var bot := Bot.new()
		bot.name = "Bot%d" % i
		bot.world = self
		bot.display_name = BOT_NAMES[i % BOT_NAMES.size()]
		bot.vest_color = BOT_COLORS[i % BOT_COLORS.size()]
		bot.skin_id = Skins.ORDER[(i * 3 + 1) % Skins.ORDER.size()]
		bot.loadout = Cosmetics.sanitize({"skin": bot.skin_id, "pickaxe": Cosmetics.PICKAXES.keys()[(i * 5 + 2) % Cosmetics.PICKAXES.size()],
			"backbling": Cosmetics.BACKBLINGS.keys()[(i * 7 + 1) % Cosmetics.BACKBLINGS.size()], "glider": Cosmetics.GLIDERS.keys()[(i * 3) % Cosmetics.GLIDERS.size()]})
		bot.skill = rng.randf_range(0.2, 0.85)
		bot.map_half = MAP_HALF - 4.0
		bot.translation = _spawn_point(p)
		bot.jump_at = rng.randf_range(110.0, 380.0) * MAP_SCALE
		bot.net_key_v = bot.name
		if net_match and not Net.is_host:
			bot.net_owner = 1                  # the host runs the bots; here they are puppets
		add_child(bot)
		bot.rotation.y = rng.randf() * TAU
		bot.connect("died", self, "_on_fighter_died")


func _start_bus() -> void:
	var a := rng.randf() * TAU
	var dir := Vector3(cos(a), 0.0, sin(a))
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var start := -dir * (BUS_LENGTH / 2.0) + perp * rng.randf_range(-70.0, 70.0) + Vector3(0, BUS_ALTITUDE, 0)
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
	if net_live:
		_net_process(delta)
	_audio_process(delta)
	_update_spectator(delta)
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
		if storm.phase % 2 == 0 and (not net_match or Net.is_host):      # in a network match the host decides
			_spawn_supply()


func _spawn_supply() -> void:
	var p := random_point_in_safe_zone()
	var yaw := rng.randf() * TAU
	var c: Node
	if net_live:
		var sid := Net.new_id("s")
		var sseed: int = rng.randi() + 1
		c = _add_chest("supply", p, yaw, sid, sseed)
		Net.send_event("supply", [p, yaw, sid, sseed])
	else:
		c = _add_chest("supply", p, yaw)
	c.start_fall(150.0, p.y)
	if hud:
		hud.add_feed("A supply drop is on its way!", Color(1.0, 0.45, 0.35))


func _on_fighter_died(victim, killer) -> void:
	var alive := alive_count()
	var text := ""
	var color := Color.white
	if victim.has_meta("left"):
		text = "%s left the game" % victim.display_name
		color = Color(0.8, 0.8, 0.8)
	elif killer == null:
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
	if victim.net_owner == 0:
		_drop_inventory(victim)          # puppets drop on the machine that owns them (the loot is sent to everyone)

	if match_over:
		return
	if victim == player:
		match_over = true
		_record_match(false, alive + 1)
		get_tree().create_timer(1.8).connect("timeout", hud, "show_end", [false, alive + 1, player.kills])
	elif alive <= 1 and not player.is_dead:
		match_over = true
		_record_match(true, 1)
		get_tree().create_timer(1.2).connect("timeout", hud, "show_end", [true, 1, player.kills])


var _match_start_ms := 0


func _on_player_dealt(_pos, amount, headshot, _killed) -> void:
	player.stat_add("damage", amount)
	if headshot:
		player.stat_add("headshots")


# The match is over: the signed-in account (or the guest profile) gets the result.
func _record_match(victory: bool, placement: int) -> void:
	var ms: Dictionary = player.match_stats
	Accounts.record_match({"victory": victory, "placement": placement, "kills": player.kills, "damage": ms.get("damage", 0),
		"headshots": ms.get("headshots", 0), "chests": ms.get("chests", 0), "builds": ms.get("builds", 0),
		"survival": int((OS.get_ticks_msec() - _match_start_ms) / 1000.0)})


# ------------------------------------------------------------------ network match (see Net.gd)

func _on_net_go() -> void:
	net_live = true
	Net.connect("left", self, "_on_net_left", [], CONNECT_ONESHOT)
	menu.start_game()


func _on_net_left(reason: String) -> void:
	net_live = false
	if hud and not match_over:
		hud.add_feed(reason if reason != "" else "Disconnected.", Color(1.0, 0.5, 0.4))
	get_tree().create_timer(2.5).connect("timeout", self, "_leave_match")


func _leave_match() -> void:
	Settings.autostart = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func fighter_by_key(key):
	if typeof(key) == TYPE_INT:
		if key == Net.my_id:
			return player
		for r in get_tree().get_nodes_in_group("remote_players"):
			if r.peer_id == key:
				return r
		return null
	if typeof(key) == TYPE_STRING:
		return get_node_or_null(NodePath(key))
	return null


func _net_process(delta: float) -> void:
	if not Net.active or not Net.in_match:
		return
	_net_pose_t -= delta
	if _net_pose_t <= 0.0:
		_net_pose_t = 1.0 / 15.0
		Net.send_pose(player.net_pack())
	_net_veh_t -= delta
	if _net_veh_t <= 0.0:
		_net_veh_t = 1.0 / 15.0
		if player.mode == player.Mode.VEHICLE and player.vehicle_seat == 0 and player.vehicle != null and is_instance_valid(player.vehicle) and player.vehicle.net_id != "":
			Net.send_vehicle(player.vehicle.net_id, player.vehicle.global_transform)
	if Net.is_host:
		_net_bots_t -= delta
		if _net_bots_t <= 0.0:
			_net_bots_t = 0.1
			var chunk := []
			for f in get_tree().get_nodes_in_group("fighters"):
				if typeof(f.net_key_v) == TYPE_STRING and f.net_owner == 0:
					chunk.append([f.name, f.net_pack()])
					if chunk.size() >= 8:               # keep every packet under the network MTU
						Net.send_bots(chunk)
						chunk = []
			if not chunk.empty():
				Net.send_bots(chunk)
		_net_storm_t -= delta
		if _net_storm_t <= 0.0:
			_net_storm_t = 1.0
			Net.send_event("storm", storm.net_state())


func net_vehicle(from: int, id: String, xf: Transform) -> void:
	var v = net_nodes.get(id)
	if v != null and is_instance_valid(v) and v.net_owner == from:
		v._net_xf = xf
		v._net_has = true


func net_pose(from: int, packed: Array) -> void:
	var f = fighter_by_key(from)
	if f != null and f != player and f.net_owner != 0:
		f.net_apply(FighterScript.net_unpack(packed))


func net_bots(chunk: Array) -> void:
	for st in chunk:
		var b = get_node_or_null(NodePath(st[0]))
		if b != null and b.net_owner != 0:
			b.net_apply(FighterScript.net_unpack(st[1]))


# Damage that another machine dealt to a character this machine owns.
func net_damage(_from: int, target_key, amount: float, source_key, _headshot: bool) -> void:
	var t = fighter_by_key(target_key)
	if t == null or t.net_owner != 0 or t.is_dead:
		return
	t.take_damage(amount, fighter_by_key(source_key))


# A grenade / shockwave / junk rift thrown by somebody else: a look-alike without the damage (the thrower's machine does that).
func net_spawn_throw(data: Array) -> void:
	var thrower = fighter_by_key(data[0])
	match data[1]:
		"junk":
			var jr := JunkRiftScript.new()
			jr.thrower = thrower
			jr.visual_only = true
			add_child(jr)
			jr.global_transform.origin = data[2]
			jr.linear_velocity = data[3]
		_:
			var g := GrenadeScript.new()
			g.thrower = thrower
			g.shock = (data[1] == "shock")
			g.visual_only = true
			add_child(g)
			g.global_transform.origin = data[2]
			g.linear_velocity = data[3]
			g.angular_velocity = Vector3(rand_range(-6, 6), rand_range(-6, 6), rand_range(-6, 6))


func net_peer_left(id: int, player_name: String) -> void:
	var f = fighter_by_key(id)
	if f != null and not f.is_dead:
		f.set_meta("left", true)
		f._die(null)


func net_event(from: int, kind: String, data) -> void:
	match kind:
		"died":
			var victim = fighter_by_key(data[0])
			if victim != null and victim != player and not victim.is_dead:
				victim._die(fighter_by_key(data[1]), false)       # the score goes to the killer's own machine (see "kill")
		"kill":                         # we (or a bot we run) eliminated somebody who lives on another machine
			var v = fighter_by_key(data[0])
			var killer = fighter_by_key(data[1])
			if killer == player:
				player.kills += 1
				player.emit_signal("hit_landed", v, true, false)
				if v != null:
					player.sprite_on_kill(v)
			elif killer != null and "kills" in killer:
				killer.kills += 1
		"storm":
			if not Net.is_host:
				storm.net_apply(data)
		"spawn":                         # loot dropped by another machine
			spawn_item(data[1], data[2], data[0])
		"gone":
			var n = net_nodes.get(data)
			net_nodes.erase(data)
			if n != null and is_instance_valid(n):
				if n.is_in_group("interactable"):
					n.remove_from_group("interactable")
				n.queue_free()
		"chest":
			var c = net_nodes.get(data)
			if c != null and is_instance_valid(c) and not c.opened:
				c.open(null, true)
		"supply":
			var sc := _add_chest("supply", data[0], data[1], data[2], data[3])
			sc.start_fall(150.0, data[0].y)
			if hud:
				hud.add_feed("A supply drop is on its way!", Color(1.0, 0.45, 0.35))
		"wild":
			add_wild_sprite(data[1], data[2], data[0])
		"rift":
			add_rift(data[1], data[2], data[0])
		"build":
			if not build_slots.has(data[2]):
				spawn_build(data[0], data[1], data[2], data[3], data[4])
		"bdmg":
			var bp = build_slots.get(data[0])
			if bp != null and is_instance_valid(bp):
				bp.take_damage(data[1], null)
		"bmask":
			var bm = build_slots.get(data[0])
			if bm != null and is_instance_valid(bm):
				bm.apply_mask(data[1])
		"harvest":
			if data[0] == "S":
				var root = net_nodes.get(data[1])
				if root != null:
					_structure_hit(root, data[2], null, Vector3.ZERO)
			elif _props.has(data[1]):
				_prop_hit(data[1], int(data[2]), data[3], null, Vector3.ZERO)
		"veh_claim":
			var vc = net_nodes.get(data)
			if vc != null and is_instance_valid(vc):
				VehicleCommon.net_claim(vc, from)
		"veh_release":
			var vr = net_nodes.get(data[0])
			if vr != null and is_instance_valid(vr):
				VehicleCommon.net_release(vr, data[1])
		"vdmg":
			var vd = net_nodes.get(data[0])
			if vd != null and is_instance_valid(vd):
				VehicleCommon.take_damage(vd, data[1], null, true)
		"collapse":
			var cr = net_nodes.get(data)
			if cr != null and is_instance_valid(cr):
				_collapse(cr)
		"shot":                          # [shooter key, sound, muzzle position, tracer ends]
			var sh = fighter_by_key(data[0])
			if sh != null and sh.net_owner != 0:
				sh.net_play_shot(data[1], data[2], data[3])
		"swing":
			var sw = fighter_by_key(data)
			if sw != null and sw.net_owner != 0:
				sw.net_play_swing()
		"throw":                         # [shooter key, kind, from, velocity]
			net_spawn_throw(data)


# ------------------------------------------------------------------ spectating

func start_spectating() -> void:
	if spectating or alive_count() <= 0:
		return
	spectating = true
	_spec_cam = Camera.new()
	_spec_cam.far = 520.0
	_spec_cam.fov = 72.0
	add_child(_spec_cam)
	_spec_target = null
	cycle_spectate(1)
	if not spectating:
		return
	var tp: Vector3 = _spec_target.global_transform.origin
	_spec_cam.global_transform.origin = tp + Vector3(0, 2.6, 0) + _spec_target.global_transform.basis.z * 5.5
	_spec_cam.make_current()


func stop_spectating() -> void:
	if not spectating:
		return
	spectating = false
	_spec_target = null
	if _spec_cam != null:
		_spec_cam.queue_free()
		_spec_cam = null
	if player != null and player.camera != null:
		player.camera.make_current()


# Switch to the next / previous living fighter (the player's own body is not a choice).
func cycle_spectate(dir: int) -> void:
	var living := []
	for f in get_tree().get_nodes_in_group("fighters"):
		if f != player and not f.is_dead:
			living.append(f)
	if living.empty():
		stop_spectating()
		return
	var idx: int = living.find(_spec_target)
	_spec_target = living[int(posmod(idx + dir, living.size()))] if idx >= 0 else living[0]


func _update_spectator(delta: float) -> void:
	if not spectating:
		return
	if _spec_target == null or not is_instance_valid(_spec_target) or _spec_target.is_dead:
		cycle_spectate(1)
		if not spectating:
			return
	var tp: Vector3 = _spec_target.global_transform.origin
	var fwd: Vector3 = -_spec_target.global_transform.basis.z
	var want: Vector3 = tp + Vector3(0, 2.8, 0) - fwd * 6.0
	_spec_cam.global_transform.origin = _spec_cam.global_transform.origin.linear_interpolate(want, clamp(5.0 * delta, 0.0, 1.0))
	_spec_cam.look_at(tp + Vector3(0, 1.4, 0), Vector3.UP)


func spectate_name() -> String:
	return _spec_target.display_name if _spec_target != null and is_instance_valid(_spec_target) else ""


func _input(event: InputEvent) -> void:
	if spectating and event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_RIGHT or event.scancode == KEY_D:
			cycle_spectate(1)
		elif event.scancode == KEY_LEFT or event.scancode == KEY_A:
			cycle_spectate(-1)
	if Controls.touch_mode or match_over or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Controls.capture_mouse(true)

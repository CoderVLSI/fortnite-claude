extends Spatial
# Main scene. Builds the island (terrain, town, houses, trees, rocks, loot),
# spawns the player and bots, runs the shrinking storm and decides the match
# result. Quality is chosen per platform: Android gets fewer bots/trees and no
# real-time shadows.

const Terrain = preload("res://scripts/Terrain.gd")
const Storm = preload("res://scripts/Storm.gd")
const Player = preload("res://scripts/Player.gd")
const Bot = preload("res://scripts/Bot.gd")
const Loot = preload("res://scripts/Loot.gd")
const HUD = preload("res://scripts/HUD.gd")

const MAP_HALF := 160.0
const SEED := 20241002
const MODEL_DIR := "res://assets/models/"
const HOUSES := ["house_a", "house_b"]
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
var building_positions := []     # Vector2 (x, z) for the minimap
var tree_positions := []         # Vector2 (x, z), used to keep spawns out of foliage
var match_over := false


func _ready() -> void:
	rng.seed = SEED
	profile = _make_profile()
	if not profile.mobile:
		get_viewport().msaa = Viewport.MSAA_4X
	_setup_environment()

	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.setup(MAP_HALF, SEED, profile.cell)
	add_child(terrain)
	var plan := _plan_buildings()
	terrain.build()
	_spawn_buildings(plan)
	_scatter_props("tree", profile.trees, 0.8, 1.5, 0.45, 3.0, 2.2)
	_scatter_props("rock", profile.rocks, 1.0, 2.6, 0.9, 1.4, 1.6)

	storm = Storm.new()
	storm.name = "Storm"
	add_child(storm)
	storm.setup(MAP_HALF - 8.0, rng)

	rng.randomize()      # same island every match, different spawns/loot
	_spawn_loot(plan)
	_spawn_fighters()

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(self)
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
		"crates": 14 if mobile else 26,
		"shadows": not mobile,
		"cell": 4.0 if mobile else 3.0,
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
	env.fog_depth_end = 430.0
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
	plane.size = Vector2(1600, 1600)
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
		_add_trimesh_collision(inst)
		building_positions.append(p)


func _add_trimesh_collision(node: Node) -> void:
	if node is MeshInstance:
		node.create_trimesh_collision()
	for c in node.get_children():
		_add_trimesh_collision(c)


func _find_mesh(node: Node):
	if node is MeshInstance:
		return node.mesh
	for c in node.get_children():
		var m = _find_mesh(c)
		if m != null:
			return m
	return null


# ------------------------------------------------------------------ props

func _scatter_props(model: String, count: int, smin: float, smax: float, col_radius: float, col_height: float, min_h: float) -> void:
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
	add_child(body)
	for i in range(transforms.size()):
		var cyl := CylinderShape.new()
		cyl.radius = col_radius * scales[i]
		cyl.height = col_height * scales[i]
		var cs := CollisionShape.new()
		cs.shape = cyl
		cs.translation = transforms[i].origin + Vector3(0, cyl.height / 2.0, 0)
		body.add_child(cs)


# ------------------------------------------------------------------ loot & fighters

func _spawn_loot(plan: Array) -> void:
	for entry in plan:
		if not entry.house:
			continue
		var local := Vector3(2.0, 0.0, -1.0).rotated(Vector3.UP, entry.yaw)
		var p: Vector2 = entry.pos
		_add_loot(Vector3(p.x + local.x, terrain.height_at(p.x, p.y) + 0.15, p.y + local.z))
	var placed := 0
	var tries := 0
	while placed < profile.crates and tries < 200:
		tries += 1
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * MAP_HALF * 0.75
		var h: float = terrain.height_at(p.x, p.y)
		if h < 2.5 or _near_building(p, 8.0):
			continue
		_add_loot(Vector3(p.x, h + 0.1, p.y))
		placed += 1


func _add_loot(pos: Vector3, kind: String = "") -> void:
	var loot := Loot.new()
	loot.kind = kind if kind != "" else Loot.KINDS[rng.randi() % Loot.KINDS.size()]
	loot.translation = pos
	add_child(loot)


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
		add_child(bot)
		bot.rotation.y = rng.randf() * TAU
		bot.connect("died", self, "_on_fighter_died")


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
	_add_loot(victim.global_transform.origin + Vector3(0, 0.3, 0))

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

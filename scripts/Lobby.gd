extends Spatial
# The pre-match lobby stage: the player's character idling on a floating island, a glider and
# the battle bus overhead, drifting rocks and clouds. It lives far from the real island and is
# shown through the menu's camera (Menu.gd). Drag to turn the character, tap it to wave.

const Items = preload("res://scripts/Items.gd")
const MODEL := "res://assets/models/player.glb"
const ORIGIN := Vector3(4000, 300, 0)
const CAMERA_POS := Vector3(0.0, 1.35, 5.0)      # relative to ORIGIN, looks at CAMERA_TARGET
const CAMERA_TARGET := Vector3(0.0, 1.05, 0.0)

var character: Spatial
var nodes := {}
var rest_hips := Vector3.ZERO
var yaw := 0.0                  # drag offset, springs back to 0 when released
var dragging := false
var _t := 0.0
var _wave := 0.0
var env: Environment             # the lobby camera's environment: draws the backdrop image behind the 3D stage
var _backdrop: TextureRect
var _bg_layer: CanvasLayer
var _bus: Spatial
var _glider: Spatial
var _floaters := []             # [node, base position, phase]
var _cur := {}


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS      # the menu pauses the tree; the lobby keeps animating
	translation = ORIGIN
	_build_island()
	_build_character()
	_build_backdrop()
	_build_lights()


func _mat(color: Color, rough: float = 0.9, emissive: float = 0.0) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = color
	m.roughness = rough
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy = emissive
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Spatial = null) -> MeshInstance:
	var mi := MeshInstance.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.translation = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _scene(path: String, pos: Vector3, scale: float = 1.0, parent: Spatial = null):
	var res = load(path)
	if res == null:
		return null
	var n: Spatial = res.instance()
	n.translation = pos
	n.scale = Vector3(scale, scale, scale)
	(parent if parent != null else self).add_child(n)
	return n


func _build_island() -> void:
	var top := CylinderMesh.new()
	top.top_radius = 3.4
	top.bottom_radius = 3.4
	top.height = 0.5
	top.radial_segments = 36
	_mesh(top, _mat(Color(0.26, 0.50, 0.18), 1.0), Vector3(0, -0.25, 0))
	var ring := CylinderMesh.new()
	ring.top_radius = 3.5
	ring.bottom_radius = 3.5
	ring.height = 0.12
	ring.radial_segments = 36
	_mesh(ring, _mat(Color(0.80, 0.62, 0.15), 0.6), Vector3(0, -0.12, 0))     # top at y = -0.06: below the grass, no z-fighting
	var under := CylinderMesh.new()
	under.top_radius = 3.4
	under.bottom_radius = 0.5
	under.height = 3.5
	under.radial_segments = 20
	_mesh(under, _mat(Color(0.42, 0.30, 0.22)), Vector3(0, -2.25, 0))    # starts inside the grass slab (no coplanar faces)
	_scene("res://assets/models/tree.glb", Vector3(-2.4, 0, -1.8), 0.42)
	_scene("res://assets/models/tree.glb", Vector3(2.6, 0, -2.2), 0.34)
	_scene("res://assets/models/rock.glb", Vector3(2.5, 0, 0.2), 0.45)
	_scene("res://assets/models/rock.glb", Vector3(-2.6, 0, 0.6), 0.3)
	var chest = _scene("res://assets/models/chest.glb", Vector3(1.8, 0, 0.9), 0.6)
	if chest != null:
		chest.rotation_degrees = Vector3(0, -35, 0)


func _build_character() -> void:
	var res = load(MODEL)
	if res == null:
		return
	character = res.instance()
	character.rotation_degrees = Vector3(0, 168, 0)      # faces the camera (+Z), turned slightly
	add_child(character)
	for n in ["Hips", "Spine", "Head", "ShoulderL", "ElbowL", "HandL", "ShoulderR", "ElbowR", "HandR", "HipL", "KneeL", "HipR", "KneeR"]:
		var node := character.find_node(n, true, false)
		if node:
			nodes[n] = node
			_cur[n] = Vector3.ZERO
	if nodes.has("Hips"):
		rest_hips = nodes["Hips"].translation
	if nodes.has("HandR"):       # the mythic Stormcaller held low, like a lobby idle pose
		var item := Items.make_weapon("assault", Items.MYTHIC)
		var gun = load(Items.model_of(item))
		if gun != null:
			var held: Spatial = gun.instance()
			nodes["HandR"].add_child(held)
			held.translation = Vector3(0, -0.02, -0.04)
			held.rotation_degrees = Vector3(-35, 0, 0)
			Items.apply_accent(held, Items.color_of(item))
	var glider = load("res://assets/models/glider.glb")
	if glider != null:
		_glider = glider.instance()
		_glider.translation = Vector3(-0.2, 3.1, -1.8)
		_glider.rotation_degrees = Vector3(-18, 0, 0)
		add_child(_glider)


# The generated lobby painting (assets/ui/lobby_bg.png) sits behind the 3D island and character. A canvas layer below
# layer 0 is drawn as the 3D background when the camera's Environment uses BG_CANVAS. Without the image (not yet
# imported) the lobby falls back to drifting rocks, clouds and the bus in the normal sky.
func _build_backdrop() -> void:
	var tex = load("res://assets/ui/lobby_bg.png")
	if tex == null:
		_build_sky()
		return
	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = -10
	add_child(_bg_layer)
	_backdrop = TextureRect.new()
	_backdrop.texture = tex
	_backdrop.expand = true
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(_backdrop)
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -10
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.9
	var glow := _glider                                  # keep the glider; the painting already has the clouds and the bus
	if glow != null:
		glow.translation = Vector3(-0.2, 3.1, -1.8)


# Only draw the backdrop while the lobby camera is the active one.
func set_active(on: bool) -> void:
	if _backdrop != null:
		_backdrop.visible = on


func _build_sky() -> void:
	var cloud_mat := _mat(Color(1, 1, 1, 1), 1.0, 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(14):
		var puff := SphereMesh.new()
		puff.radius = 1.0
		puff.height = 2.0
		var a := rng.randf() * TAU
		var d := rng.randf_range(12.0, 30.0)
		var pos := Vector3(cos(a) * d, rng.randf_range(-7.0, 1.0), sin(a) * d - 6.0)
		for k in range(3):
			var mi := _mesh(puff, cloud_mat, pos + Vector3(k * 2.2, rng.randf() * 0.6, rng.randf() * 1.5))
			mi.scale = Vector3(rng.randf_range(2.2, 4.0), rng.randf_range(0.8, 1.4), rng.randf_range(1.6, 2.6))
	for i in range(5):       # drifting rock islands
		var rock = _scene("res://assets/models/rock.glb", Vector3.ZERO, rng.randf_range(1.6, 3.0))
		if rock != null:
			var p := Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(0.5, 6.0), rng.randf_range(-14.0, -6.0))
			rock.translation = p
			_floaters.append([rock, p, rng.randf() * TAU])
	var bus = _scene("res://assets/models/battle_bus.glb", Vector3(34, 5, -60), 1.8)
	if bus != null:
		bus.rotation_degrees = Vector3(0, 90, 0)
		_bus = bus


func _build_lights() -> void:
	var key := OmniLight.new()
	key.translation = Vector3(3.5, 4.0, 5.0)
	key.light_color = Color(1.0, 0.93, 0.80)
	key.light_energy = 0.55
	key.omni_range = 18.0
	add_child(key)
	var rim := OmniLight.new()
	rim.translation = Vector3(-4.5, 3.0, -3.0)
	rim.light_color = Color(0.55, 0.75, 1.0)
	rim.light_energy = 0.9
	rim.omni_range = 16.0
	add_child(rim)


func wave() -> void:
	_wave = 2.4


func camera_transform() -> Transform:
	var from := ORIGIN + CAMERA_POS + Vector3(sin(_t * 0.35) * 0.12, sin(_t * 0.5) * 0.04, 0)
	return Transform(Basis(), from).looking_at(ORIGIN + CAMERA_TARGET, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	if not dragging:
		yaw = lerp(yaw, 0.0, 1.0 - exp(-2.5 * delta))
	if character != null:
		character.rotation.y = deg2rad(168.0) + yaw + sin(_t * 0.4) * 0.05
	_wave = max(0.0, _wave - delta)
	if _backdrop != null:                                  # slow push-in / pull-out on the painting
		var z := 1.04 + sin(_t * 0.12) * 0.03
		_backdrop.rect_pivot_offset = _backdrop.rect_size / 2.0
		_backdrop.rect_scale = Vector2(z, z)
	_pose(delta)
	if _glider != null:
		_glider.translation.y = 3.1 + sin(_t * 1.1) * 0.12
	if _bus != null:
		_bus.translation.x -= delta * 2.2
		if _bus.translation.x < -34.0:
			_bus.translation.x = 34.0
	for f in _floaters:
		f[0].translation = f[1] + Vector3(0, sin(_t * 0.7 + f[2]) * 0.35, 0)


func _pose(delta: float) -> void:
	if nodes.empty():
		return
	var breathe := sin(_t * 1.8)
	var tgt := {}
	for n in nodes:
		tgt[n] = Vector3.ZERO
	tgt["Spine"] = Vector3(-0.03 + breathe * 0.012, sin(_t * 0.5) * 0.04, 0)
	tgt["Head"] = Vector3(sin(_t * 0.7) * 0.04, sin(_t * 0.35) * 0.22, 0)
	tgt["ShoulderL"] = Vector3(0.06 + breathe * 0.02, 0, 0.12)
	tgt["ElbowL"] = Vector3(0.22, 0, 0)
	tgt["ShoulderR"] = Vector3(0.25, 0, -0.08)      # holding the rifle low
	tgt["ElbowR"] = Vector3(0.55, 0, 0)
	tgt["HipL"] = Vector3(0.03, 0, 0)
	tgt["HipR"] = Vector3(-0.04, 0, 0)
	if _wave > 0.0:             # tap = wave with the free hand
		var w := sin(_t * 11.0)
		tgt["ShoulderL"] = Vector3(2.55, 0, 0.35)
		tgt["ElbowL"] = Vector3(0.7 + w * 0.45, 0, 0)
		tgt["Head"] = Vector3(-0.05, 0.25, 0)
	var k := 1.0 - exp(-10.0 * delta)
	for n in nodes:
		_cur[n] = _cur[n].linear_interpolate(tgt[n], k)
		nodes[n].rotation = _cur[n]
	if nodes.has("Hips"):
		nodes["Hips"].translation = rest_hips + Vector3(0, breathe * 0.008, 0)

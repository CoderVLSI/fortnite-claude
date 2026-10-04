extends Spatial
# A Keeper: a villager who hands out quests and pays the rewards (press interact next to them).

const Skins = preload("res://scripts/Skins.gd")
const Animator = preload("res://scripts/Animator.gd")
const Quests = preload("res://scripts/Quests.gd")

export var npc_name := "Keeper"
export var skin := "cowboy"
export var seed_n := 0

var model: Spatial
var animator
var _t := 0.0
var _wave := 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npcs")
	var scene = load("res://assets/models/player.glb")
	if scene != null:
		model = scene.instance()
		add_child(model)
		animator = Animator.new()
		animator.setup(model)
		Skins.apply(model, skin, Color(0.85, 0.65, 0.2))
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CapsuleShape.new()
	shape.radius = 0.4
	shape.height = 1.0
	var cs := CollisionShape.new()
	cs.shape = shape
	cs.translation = Vector3(0, 0.95, 0)
	body.add_child(cs)
	add_child(body)
	var glow := OmniLight.new()
	glow.light_color = Color(1.0, 0.85, 0.35)
	glow.light_energy = 0.5
	glow.omni_range = 5.0
	glow.translation = Vector3(0, 2.4, 0)
	add_child(glow)
	_build_marker()


# A floating gold "!" over the head so Keepers read from far away.
func _build_marker() -> void:
	var m := MeshInstance.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.28, 0.4, 0.28)
	m.mesh = mesh
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.1)
	mat.emission_energy = 1.2
	m.material_override = mat
	m.rotation_degrees.x = 180
	m.translation = Vector3(0, 2.45, 0)
	m.name = "Marker"
	add_child(m)


func _log():
	for n in get_tree().get_nodes_in_group("quest_log"):
		return n
	return null


func can_interact() -> bool:
	return _log() != null


func prompt_text() -> String:
	var q = _log()
	if q == null:
		return ""
	if q.ready_count() > 0:
		return "Collect quest reward  (%s)" % npc_name
	var offer: Dictionary = q.next_offer(seed_n)
	if offer.empty():
		return "%s: no more quests this match" % npc_name
	if q.active_count() >= Quests.MAX_ACTIVE:
		return "%s: finish your quests first" % npc_name
	return "Quest: %s - %s" % [offer.title, offer.desc]


func prompt_color() -> Color:
	return Color(1.0, 0.85, 0.3)


func interact(by) -> void:
	var q = _log()
	if q == null:
		return
	_wave = 2.0
	var claimed: String = q.claim_all()
	if claimed != "":
		by.emit_signal("picked_up", claimed)
		Audio.play2d("rarity_4", -4.0)
		return
	var offer: Dictionary = q.next_offer(seed_n)
	if offer.empty():
		by.emit_signal("picked_up", "%s: that is all I have for you" % npc_name)
	elif q.accept(offer):
		by.emit_signal("picked_up", "New quest: %s" % offer.desc)
		Audio.play2d("ui_select", -4.0)
	else:
		by.emit_signal("picked_up", "%s: finish your current quests first" % npc_name)
		Audio.play2d("ui_error", -4.0)


func _process(delta: float) -> void:
	_t += delta
	if model == null or animator == null or animator.nodes.empty():
		return
	var near := false
	for p in get_tree().get_nodes_in_group("player"):
		var d: Vector3 = p.global_transform.origin - global_transform.origin
		if d.length() < 14.0:
			near = true
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clamp(3.0 * delta, 0.0, 1.0))
	_wave = max(0.0, _wave - delta)
	var n: Dictionary = animator.nodes
	var waving := near and (_wave > 0.0 or int(_t * 0.4) % 4 == 0)
	n["ShoulderR"].rotation = n["ShoulderR"].rotation.linear_interpolate(Vector3(PI * 0.88, 0.0, 0.0) if waving else Vector3(0.05, 0.0, 0.12), clamp(8.0 * delta, 0.0, 1.0))
	n["ElbowR"].rotation = n["ElbowR"].rotation.linear_interpolate(Vector3(0.5 + sin(_t * 9.0) * 0.5, 0.0, 0.0) if waving else Vector3(0.2, 0, 0), clamp(8.0 * delta, 0.0, 1.0))
	n["ShoulderL"].rotation = Vector3(0.05, 0.0, -0.12)
	n["Head"].rotation = Vector3(sin(_t * 0.8) * 0.04, 0.0, 0.0)

extends Spatial
# A Keeper: a villager who hands out quests and pays the rewards (press interact next to them).

const Skins = preload("res://scripts/Skins.gd")
const Animator = preload("res://scripts/Animator.gd")
const Quests = preload("res://scripts/Quests.gd")
const Items = preload("res://scripts/Items.gd")

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
		return "Talk to %s  (a quest reward is waiting)" % npc_name
	return "Talk to %s  (talk, hire, buy)" % npc_name


func prompt_color() -> Color:
	return Color(1.0, 0.85, 0.3)


# ---------------------------------------------------------------- the three-button menu: TALK / HIRE AS ALLY / BUY

const HIRE_COST := 150
const LINES := [
	"Storm's coming, friend. Keep an eye on the circle.",
	"Three Wardens guard this island. Each one carries a vault keycard.",
	"See a dirt mound with a glint of gold? Swing your pickaxe at it.",
	"Vending machines take gold bars. Eliminations pay well.",
	"The big mountains are good cover, but bots hate climbing them.",
	"Ziplines and helicopters will get you across the island fast.",
	"Slurp Juice trickles health back slowly. Drink it before the fight, not during.",
	"A jetpack burns about eight seconds of fuel. Spend it wisely.",
]
var hired := false
var _spoke := 0


func greeting() -> String:
	return "%s: \"Hello, traveller. What can I do for you?\"" % npc_name


func options(by) -> Array:
	var online: bool = Net.active and Net.in_match
	return [
		{"id": "talk", "label": "TALK", "sub": "chat, quests and rewards", "enabled": true},
		{"id": "hire", "label": "HIRE AS ALLY", "sub": "already with you" if hired else ("solo matches only" if online else "%d gold" % HIRE_COST), "enabled": not hired and not online},
		{"id": "buy", "label": "BUY", "sub": "supplies", "enabled": true},
	]


# The menu button was pressed. `hud` is where the screens live.
func choose(id, by, hud) -> void:
	match id:
		"talk":
			_wave = 2.0
			var line: String = LINES[(seed_n + _spoke) % LINES.size()]
			_spoke += 1
			var quest_note := _quest_step(by)
			hud.shop.set_menu_text("%s: \"%s\"%s" % [npc_name, line, ("\n\n" + quest_note) if quest_note != "" else ""])
		"hire":
			if hired:
				return
			if by.gold < HIRE_COST:
				hud.shop.set_menu_text("%s: \"I do not work for free. %d gold, please.\"" % [npc_name, HIRE_COST])
				Audio.play2d("ui_error", -4.0)
				return
			var ally = null
			for w in get_tree().get_nodes_in_group("world"):
				ally = w.hire_ally(by, self)
			if ally == null:
				hud.shop.set_menu_text("%s: \"Not right now.\"" % npc_name)
				return
			by.gold -= HIRE_COST
			hired = true
			hud.shop.set_gold(by.gold)
			hud.shop.set_menu_text("%s: \"You have a deal. I will watch your back!\"" % npc_name)
			Audio.play2d("quest_accept", -2.0)
			by.emit_signal("picked_up", "%s joined you as an ally" % npc_name)
			hud.shop.show_menu(npc_name, "%s: \"You have a deal. I will watch your back!\"" % npc_name, options(by), by.gold)
		"buy":
			hud.shop.show_shop("%s's goods" % npc_name, entries(), by.gold)


func stock() -> Array:
	return [
		{"name": "Bandage x5", "icon": "heal_bandage", "price": 35, "give": [Items.make_consumable("bandage", 5)]},
		{"name": "Mini Shield x2", "icon": "heal_mini_shield", "price": 45, "give": [Items.make_consumable("mini_shield", 2)]},
		{"name": "Medkit", "icon": "heal_medkit", "price": 70, "give": [Items.make_consumable("medkit", 1)]},
		{"name": "Grenade x2", "icon": "heal_grenade", "price": 50, "give": [Items.make_consumable("grenade", 2)]},
		{"name": "Wood 100", "icon": "material_wood", "price": 25, "give": [Items.make_material("wood", 100)]},
		{"name": "Medium Ammo", "icon": "ammo_medium", "price": 40, "give": [Items.make_ammo("medium", Items.AMMO["medium"].pack)]},
	]


func entries() -> Array:
	var out := []
	for e in stock():
		out.append({"name": e.name, "icon": e.icon, "price": e.price})
	return out


func buy_offer(by, index: int) -> bool:
	var st := stock()
	if index < 0 or index >= st.size():
		return false
	if by.gold < st[index].price:
		by.emit_signal("picked_up", "Need %d gold" % st[index].price)
		Audio.play2d("ui_error", -4.0)
		return false
	by.gold -= st[index].price
	var out := global_transform.origin + (-global_transform.basis.z) * 1.4 + Vector3(0, 0.5, 0)
	for i in range(st[index].give.size()):
		for w in get_tree().get_nodes_in_group("world"):
			w.spawn_item(st[index].give[i], out + global_transform.basis.x * float(i) * 0.9)
	Audio.play2d("loot_pickup", -4.0)
	by.emit_signal("picked_up", "Bought: " + str(st[index].name))
	return true


# The quest part of "Talk": reward ready, new quest on offer, or nothing more.
func _quest_step(by) -> String:
	var q = _log()
	if q == null:
		return ""
	var claimed: String = q.claim_all()
	if claimed != "":
		by.emit_signal("picked_up", claimed)
		Audio.play2d("quest_complete", -2.0)
		return claimed
	var offer: Dictionary = q.next_offer(seed_n)
	if offer.empty():
		return "(No more quests from me this match.)"
	if q.accept(offer):
		Audio.play2d("quest_accept", -2.0)
		return "New quest: %s" % offer.desc
	return "(Finish your current quests first.)"


func interact(by) -> void:
	for w in get_tree().get_nodes_in_group("world"):
		if w.hud != null and by.is_in_group("player"):
			w.hud.open_npc(self)
			return
	quick_interact(by)


func quick_interact(by) -> void:
	var q = _log()
	if q == null:
		return
	_wave = 2.0
	var claimed: String = q.claim_all()
	if claimed != "":
		by.emit_signal("picked_up", claimed)
		Audio.play2d("quest_complete", -2.0)
		return
	var offer: Dictionary = q.next_offer(seed_n)
	if offer.empty():
		by.emit_signal("picked_up", "%s: that is all I have for you" % npc_name)
	elif q.accept(offer):
		by.emit_signal("picked_up", "New quest: %s" % offer.desc)
		Audio.play2d("quest_accept", -2.0)
	else:
		by.emit_signal("picked_up", "%s: finish your current quests first" % npc_name)
		Audio.play2d("ui_error", -4.0)


func _process(delta: float) -> void:
	if not visible:
		return
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

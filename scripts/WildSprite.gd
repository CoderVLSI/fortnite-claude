extends Spatial
# A wild Sprite drifting around the island. Walk up and press interact to catch it (it joins your inventory as a throwable).

const Items = preload("res://scripts/Items.gd")
const SpriteCreature = preload("res://scripts/SpriteCreature.gd")
const Sprites = preload("res://scripts/Sprites.gd")

var data := {"id": "earth", "variant": "", "level": 1, "xp": 0.0}
var terrain = null
var net_id := ""
var home := Vector2.ZERO
var _target := Vector2.ZERO
var _t := rand_range(0.0, 6.0)
var _pause := 0.0
var _model: Spatial
const ROAM := 14.0
const SPEED := 1.6


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("wild_sprites")
	_model = SpriteCreature.build_for(data.id, data.variant, 1.4)
	add_child(_model)
	home = Vector2(translation.x, translation.z)
	_target = home


func _process(delta: float) -> void:
	_t += delta
	var pos := Vector2(translation.x, translation.z)
	var to := _target - pos
	if _pause > 0.0:
		_pause -= delta
	elif to.length() < 0.6:
		_pause = rand_range(1.5, 4.0)
		var a := rand_range(0.0, TAU)
		_target = home + Vector2(cos(a), sin(a)) * rand_range(2.0, ROAM)
		if terrain != null and terrain.height_at(_target.x, _target.y) < 1.5:
			_target = home
	else:
		var step := to.normalized() * SPEED * delta
		translation.x += step.x
		translation.z += step.y
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-to.x, -to.y), clamp(4.0 * delta, 0.0, 1.0))
	var ground: float = terrain.height_at(translation.x, translation.z) if terrain != null else translation.y
	translation.y = ground + 0.9 + sin(_t * 2.2) * 0.14


func can_interact() -> bool:
	return true


func prompt_text() -> String:
	var lv: String = (" Lv%d" % data.level) if data.level > 1 else ""
	return "Equip %s%s - %s" % [Sprites.title(data.id, data.variant), lv, Sprites.LIST[data.id].desc]


func prompt_color() -> Color:
	return Sprites.rarity_color(data.id)


# Catching one equips it; the sprite you were carrying is released right here (nothing is lost).
func interact(by) -> void:
	if not by.has_method("equip_sprite"):
		return
	var old: Dictionary = by.equip_sprite(data.id, data.variant, data.level, data.xp)
	by.emit_signal("picked_up", "Equipped " + Sprites.title(data.id, data.variant))
	Audio.play2d("sprite_equip", 3.0)
	Audio.play2d("loot_pickup", -8.0)
	if not old.empty():
		for w in get_tree().get_nodes_in_group("world"):
			w.add_wild_sprite(old, global_transform.origin + Vector3(1.4, 0, 0))
	remove_from_group("interactable")
	for w in get_tree().get_nodes_in_group("world"):
		w.net_item_taken(self)
	queue_free()

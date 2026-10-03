extends Spatial
# Lives on a downed fighter: the thing a teammate looks at to pick them up ("hold E to revive").

var fighter


func _ready() -> void:
	translation = Vector3(0, 0.5, 0)
	add_to_group("interactable")


func can_interact() -> bool:
	if fighter == null or not is_instance_valid(fighter) or not fighter.downed:
		return false
	for pl in get_tree().get_nodes_in_group("player"):
		return pl != fighter and not pl.downed and not pl.is_dead and pl.is_ally(fighter)
	return false


func prompt_text() -> String:
	return "HOLD to revive %s" % str(fighter.display_name)


func prompt_color() -> Color:
	return Color(0.4, 1.0, 0.5)


func interact(by) -> void:
	if fighter != null and is_instance_valid(fighter) and fighter.downed and by.has_method("begin_revive"):
		by.begin_revive(fighter)

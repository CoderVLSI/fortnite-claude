extends Spatial
# The grab point at the foot of a zipline pole.

var line
var end := 0


func _ready() -> void:
	add_to_group("interactable")


func can_interact() -> bool:
	return line != null and is_instance_valid(line) and not _busy()


func _busy() -> bool:
	for r in get_tree().get_nodes_in_group("zip_riders"):
		if r.line == line and not r.finished:
			return true
	return false


func prompt_text() -> String:
	return "Ride the zipline  (%d m)" % int(line.length())


func prompt_color() -> Color:
	return Color(0.45, 0.9, 1.0)


func interact(by) -> void:
	if can_interact():
		line.board(by, end)

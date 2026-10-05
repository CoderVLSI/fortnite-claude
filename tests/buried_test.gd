extends SceneTree
# Buried chests: mounds are scattered about, three pickaxe digs uncover a chest, and the chest has loot.
var failures := []


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _initialize() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.queue_free()
	var mounds := get_nodes_in_group("buried_chests")
	check(mounds.size() >= 10, "buried chests are scattered over the island (%d)" % mounds.size())
	var b = mounds[0]
	var body = null
	for c in b.get_children():
		if c is StaticBody and c.has_meta("buried"):
			body = c
	check(body != null and body.get_meta("harvest") == "dirt", "a mound is something the pickaxe can hit")
	var chests0 := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("open") and "kind" in n:
			chests0 += 1
	world.harvest_hit(body, 0, "dirt", p, b.global_transform.origin)
	world.harvest_hit(body, 0, "dirt", p, b.global_transform.origin)
	check(not b.revealed and b.hits == 2, "two digs are not enough (%d)" % b.hits)
	world.harvest_hit(body, 0, "dirt", p, b.global_transform.origin)
	yield(_frames(5), "completed")
	check(b.revealed and b.chest != null and is_instance_valid(b.chest), "the third dig uncovers a chest")
	var chests1 := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("open") and "kind" in n:
			chests1 += 1
	check(chests1 == chests0 + 1, "it is a real, closed chest (%d -> %d)" % [chests0, chests1])
	var items0 := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup"):
			items0 += 1
	b.chest.open(p)
	yield(_frames(5), "completed")
	var items1 := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup"):
			items1 += 1
	check(items1 >= items0 + 3, "opening it drops loot (%d -> %d)" % [items0, items1])
	# a swing of the real pickaxe: stand next to another mound and hit it
	var b2 = mounds[1]
	p.global_transform.origin = b2.global_transform.origin + Vector3(1.6, 1.0, 0)
	p.mode = p.Mode.GROUND
	p.slots[0] = load("res://scripts/Items.gd").pickaxe()
	p.select_slot(0)
	yield(_frames(10), "completed")
	var look: Vector3 = b2.global_transform.origin + Vector3(0, 0.3, 0)
	var from: Vector3 = p.global_transform.origin + Vector3(0, 1.4, 0)
	p._fire_cd = 0.0
	p.try_fire(from, (look - from).normalized())
	yield(_frames(3), "completed")
	check(b2.hits >= 1, "a real pickaxe swing digs (%d hit)" % b2.hits)
	print("BURIED_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

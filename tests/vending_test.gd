extends SceneTree
# Gold bars and vending machines: machines stand around the town and every POI, buying needs gold, each machine type
# gives its own kind of item, prices climb, and gold is picked up from the floor.
#
#   xvfb-run -a godot3 --path . -s res://tests/vending_test.gd -- --no-capture --no-bus --skip-menu

const Items = preload("res://scripts/Items.gd")

var failures := []
var toasts := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _on_toast(t: String) -> void:
	toasts.append(t)


func _floor_items() -> Array:
	var out := []
	for n in get_nodes_in_group("interactable"):
		if is_instance_valid(n) and n.has_method("setup") and n.get("item") != null and not n.item.empty():
			out.append(n.item)
	return out


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.queue_free()
	p.max_health = 1000000.0
	p.health = p.max_health
	p.connect("picked_up", self, "_on_toast")

	var machines := get_nodes_in_group("vending")
	var kinds := {}
	var on_land := true
	for m in machines:
		kinds[m.kind] = true
		if m.global_transform.origin.y < 0.9:
			on_land = false
	check(machines.size() >= 3 + world.pois.size() - 1, "vending machines stand in the town and at the POIs (%d)" % machines.size())
	check(kinds.size() == 3 and on_land, "all three kinds exist and stand on land")

	# stand next to a fresh machine of each kind
	var y: float = world.terrain.height_at(40.0, 60.0)
	p.global_transform.origin = Vector3(40.0, y + 1.0, 62.0)
	p.velocity = Vector3.ZERO
	var w = world.add_vending("weapons", Vector2(40.0, 60.0), Vector2(40.0, 70.0))
	var h = world.add_vending("healing", Vector2(44.0, 60.0), Vector2(44.0, 70.0))
	var u = world.add_vending("utility", Vector2(36.0, 60.0), Vector2(36.0, 70.0))
	yield(_frames(30), "completed")
	check(w.prompt_text().find("gold") >= 0, "the prompt shows a price (%s)" % w.prompt_text())

	# no gold: refused
	p.gold = 0
	toasts.clear()
	var floor_before := _floor_items().size()
	w.quick_buy(p)
	yield(_frames(5), "completed")
	check(p.gold == 0 and _floor_items().size() == floor_before and toasts.size() > 0 and "Need" in toasts[0], "without gold nothing is sold (%s)" % (toasts[0] if toasts.size() > 0 else "no message"))

	# weapon machine
	p.gold = 500
	w.quick_buy(p)
	yield(_frames(5), "completed")
	var items := _floor_items()
	var got_weapon := false
	for it in items:
		if it.kind == "weapon" and it.rarity >= 2:
			got_weapon = true
	check(p.gold == 400 and got_weapon, "the weapon machine sells a rare-or-better weapon for 100 gold (gold left %d)" % p.gold)
	check(w.price > 100, "the next purchase costs more (%d)" % w.price)
	var rolled = w.roll()
	check(rolled[0].kind == "weapon" and rolled.size() == 2 and rolled[1].kind == "ammo", "a weapon comes with its ammo")

	# healing machine
	var gold_before: int = p.gold
	h.quick_buy(p)
	yield(_frames(5), "completed")
	check(p.gold == gold_before - 40, "the healing machine costs 40 (gold %d)" % p.gold)
	for i in range(30):
		var r: Array = h.roll()
		if r[0].kind != "consumable":
			check(false, "healing machines only give consumables")
			break
	# utility machine
	gold_before = p.gold
	u.quick_buy(p)
	yield(_frames(5), "completed")
	check(p.gold == gold_before - 60, "the utility machine costs 60 (gold %d)" % p.gold)
	var kinds_seen := {}
	for i in range(80):
		for it in u.roll():
			kinds_seen[it.kind] = true
	check(kinds_seen.has("material") or kinds_seen.has("consumable") or kinds_seen.has("ammo"), "utility gives supplies (%s)" % str(kinds_seen.keys()))

	# gold on the floor is collected by walking over it
	p.gold = 0
	world.spawn_item(Items.make_gold(45), p.global_transform.origin + Vector3(0.6, 0.1, 0.0))
	yield(_frames(30), "completed")
	check(p.gold == 45, "walking over gold bars collects them (%d)" % p.gold)

	# every container variety can hold gold; a fallen fighter drops theirs
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for kind in ["chest", "vault", "supply"]:
		var has := false
		for it in Items.chest_loot(kind, rng):
			if it.kind == "gold":
				has = true
		check(has, "a %s holds gold" % kind)
	p.gold = 70
	p.is_dead = true
	world._drop_inventory(p)
	yield(_frames(8), "completed")
	p.is_dead = false
	var dropped := false
	for it in _floor_items():
		if it.kind == "gold" and it.count == 70:
			dropped = true
	check(dropped, "an eliminated fighter drops their gold")

	print("VENDING_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

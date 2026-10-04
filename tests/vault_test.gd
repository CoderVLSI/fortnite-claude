extends SceneTree
# Vaults and keycards: three vault rooms, Wardens carry keycards, the door needs one, and the loot behind it is reachable.

var failures := []


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		failures.append(msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss:
			f.queue_free()
	yield(self, "idle_frame")
	check(get_nodes_in_group("vaults").size() == 3, "three vaults on the island (%d)" % get_nodes_in_group("vaults").size())
	check(world.bosses.size() == 3, "three Wardens (%d)" % world.bosses.size())
	var carrying := 0
	for b in world.bosses:
		carrying += b.keycards
	check(carrying == 3, "each Warden carries a keycard")
	var v = get_nodes_in_group("vaults")[0]
	var chests := 0
	for n in get_nodes_in_group("interactable"):
		if n.has_method("open") and "kind" in n and n.kind == "vault" and n.global_transform.origin.distance_to(v.global_transform.origin) < 9.0:
			chests += 1
	check(chests == 3, "three mythic chests inside the vault (%d)" % chests)

	# locked without a keycard
	var door_at: Vector3 = v.global_transform.origin
	p.set_physics_process(false)
	p.global_transform.origin = door_at + v.global_transform.basis.z * 2.0 + Vector3(0, 1, 0)
	p.keycards = 0
	check(v.can_interact() and "locked" in v.prompt_text(), "the door is locked and says why (%s)" % v.prompt_text())
	v.interact(p)
	yield(self, "idle_frame")
	check(not v.opened, "interacting without a keycard does nothing")
	# a closed door blocks the way
	var space = p.get_world().direct_space_state
	var from: Vector3 = door_at + v.global_transform.basis.z * 3.0 + Vector3(0, 1.2, 0)
	var hit = space.intersect_ray(from, from - v.global_transform.basis.z * 6.0, [p], 1)
	check(hit and hit.position.distance_to(door_at + Vector3(0, 1.2, 0)) < 1.0, "the closed door is solid")

	# a Warden's death drops the keycard; picking it up counts it
	var w = world.bosses[0]
	w.take_damage(9999.0, p)
	yield(self, "physics_frame")
	yield(self, "physics_frame")
	var card = null
	for n in get_nodes_in_group("interactable"):
		if n.has_method("setup") and n.item.kind == "keycard":
			card = n
	check(card != null, "the Warden dropped a keycard")
	if card != null:
		card.interact(p)
	check(p.keycards == 1, "picked up: you carry %d keycard" % p.keycards)
	check("use keycard" in v.prompt_text(), "the prompt now offers to use it (%s)" % v.prompt_text())
	v.interact(p)
	check(v.opened and p.keycards == 0, "the door opens and the keycard is used")
	yield(create_timer(1.7), "timeout")
	hit = space.intersect_ray(from, from - v.global_transform.basis.z * 6.0, [p], 1)
	check(not hit or hit.position.distance_to(door_at + Vector3(0, 1.2, 0)) > 1.5, "the way in is open")
	print("VAULT_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

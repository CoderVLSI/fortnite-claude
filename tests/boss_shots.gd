extends SceneTree
# Screenshots for the bosses: the map, a boss with his henchmen, the drops after he falls, the vault outside and inside.
#   xvfb-run -a godot3 --path . --resolution 960x540 -s res://tests/boss_shots.gd -- --no-bus --skip-menu --no-capture --out=/tmp/claude-0/shots
var out := "/tmp/claude-0/shots"


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run()


func _snap(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)


func _run() -> void:
	yield(self, "idle_frame")
	var d := Directory.new()
	d.make_dir_recursive(out)
	var Items = load("res://scripts/Items.gd")
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(12):
		yield(self, "idle_frame")
	var p = world.player
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss and not f.guard:
			f.queue_free()
	p.set_physics_process(false)
	p.max_health = 100000.0
	p.health = p.max_health
	var cam := Camera.new()
	cam.far = 900.0
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	var v = null
	for b in world.bosses:
		if b.boss_id == "voltra":
			v = b
	# 1. the big map with the boss markers
	p.global_transform.origin = v.global_transform.origin + Vector3(0, 30, 0)
	world.hud.root.visible = true
	world.hud.map_screen.visible = true
	cam.look_at_from_position(Vector3(0, 90, 0), Vector3(0, 0, 0), Vector3.UP)
	yield(_snap("1_map_with_bosses"), "completed")
	world.hud.map_screen.visible = false
	# 2. Voltra with his henchmen
	world.hud.root.visible = false
	var guards := []
	for h in world.henchmen:
		if h.global_transform.origin.distance_to(v.global_transform.origin) < 30.0:
			guards.append(h)
	var vp: Vector3 = v.global_transform.origin
	for h in world.henchmen + world.bosses:
		h.set_physics_process(false)
	var back: Vector3 = Vector3(vp.x, 0, vp.z).normalized()
	cam.look_at_from_position(vp + back * 13.0 + Vector3(0, 4.5, 0), vp + Vector3(0, 1.2, 0), Vector3.UP)
	print("SHOT info henchmen near Voltra: ", guards.size())
	yield(_snap("2_voltra_and_henchmen"), "completed")
	# 3. the drops after he is defeated
	v.take_damage(9999.0, p)
	for i in range(30):
		yield(self, "physics_frame")
	cam.look_at_from_position(vp + back * 7.0 + Vector3(0, 4.0, 0), vp + Vector3(0, 0.4, 0), Vector3.UP)
	yield(_snap("3_voltra_defeated_drops"), "completed")
	# 4. a vault from outside, then opened from inside
	var vault = get_nodes_in_group("vaults")[0]
	var vo: Vector3 = vault.global_transform.origin
	var vz: Vector3 = vault.global_transform.basis.z
	cam.look_at_from_position(vo + vz * 9.0 + Vector3(0, 3.0, 0) + vault.global_transform.basis.x * 3.0, vo + Vector3(0, 1.4, -1.0), Vector3.UP)
	yield(_snap("4_vault_closed"), "completed")
	p.keycards = 1
	vault.interact(p)
	yield(self, "idle_frame")
	for i in range(100):
		yield(self, "physics_frame")
	cam.look_at_from_position(vo + vz * 4.0 + Vector3(0, 1.8, 0), vo + Vector3(0, 0.9, -4.5), Vector3.UP)
	yield(_snap("5_vault_open_inside"), "completed")
	print("BOSSSHOTS_DONE")
	quit()

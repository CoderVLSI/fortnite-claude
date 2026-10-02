extends SceneTree
# Pose gallery: forces the player rig into each animation state and screenshots it from a
# 3/4 view. tools/contact_sheet.py stitches the shots into one image.
#
#   xvfb-run -a godot3 --path . -s res://tests/anim_test.gd -- --no-bus --skip-menu --no-capture --shots=tests/out/anim

const Items = preload("res://scripts/Items.gd")
var shots_dir := "tests/out/anim"
var cam: Camera


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	_run()


func _frames(n: int) -> void:
	for i in range(n):
		yield(self, "physics_frame")


func _apply(p, cfg: Dictionary) -> void:
	var fwd: Vector3 = -p.global_transform.basis.z
	var speed: float = cfg.get("speed", 0.0)
	p.mode = cfg.get("mode", 0)
	p.velocity = fwd * speed + Vector3(0, cfg.get("vy", 0.0), 0)
	p.forward_speed = speed
	p.grounded = not cfg.get("air", false)
	p.sprinting = cfg.get("sprint", false)
	p._swing = cfg.get("swing", 0.0)
	p._reload_left = p.reload_time * (1.0 - cfg["reload"]) if cfg.has("reload") else 0.0
	p._use_total = 4.0
	p._use_left = cfg.get("use", 0.0)
	p.animator.recoil = cfg.get("recoil", 0.0)
	p.air_input = Vector2(0, cfg.get("air_y", 0.0))
	p.is_dead = cfg.get("dead", false)


func _pose(p, name: String, cfg: Dictionary) -> void:
	for i in range(60):
		_apply(p, cfg)
		p.animate(1.0 / 60.0)
	var o: Vector3 = p.global_transform.origin
	var b: Basis = p.global_transform.basis
	var eye := o + b.x * 2.4 + b.z * 1.4 + Vector3(0, 1.5, 0)
	cam.look_at_from_position(eye, o + Vector3(0, 0.95, 0), Vector3.UP)
	yield(self, "idle_frame")
	_apply(p, cfg)
	p.animate(1.0 / 60.0)
	yield(self, "idle_frame")
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("SHOT ", name)


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
	var y: float = world.terrain.height_at(0.0, 30.0)
	p.global_transform.origin = Vector3(0.0, y + 0.1, 30.0)
	p.rotation.y = PI / 2.0
	p.set_physics_process(false)
	cam = Camera.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.make_current()
	yield(_frames(3), "completed")

	p.give_weapon("assault", 2, 120)
	p.give_weapon("shotgun", 4, 20)
	p.pickup(Items.make_consumable("shield_potion", 1))
	p.pickup(Items.make_weapon("sniper", 5))
	p.select_slot(1)
	yield(_pose(p, "01_idle_rifle", {}), "completed")
	yield(_pose(p, "02_walk_rifle", {"speed": 4.0}), "completed")
	yield(_pose(p, "03_sprint_rifle", {"speed": 8.0, "sprint": true}), "completed")
	yield(_pose(p, "04_reload", {"reload": 0.5}), "completed")
	yield(_pose(p, "05_fire_recoil", {"recoil": 1.0}), "completed")
	p.select_slot(2)
	yield(_pose(p, "06_shotgun_idle", {}), "completed")
	p.select_slot(4)
	yield(_pose(p, "07_sniper_mythic", {}), "completed")
	p.select_slot(0)
	yield(_pose(p, "08_pickaxe_walk", {"speed": 4.0}), "completed")
	yield(_pose(p, "09_pickaxe_swing_wind", {"swing": 0.22}), "completed")
	yield(_pose(p, "10_pickaxe_swing_hit", {"swing": 0.08}), "completed")
	p.select_slot(3)
	yield(_pose(p, "11_drink_potion", {"use": 1.5}), "completed")
	p.select_slot(1)
	yield(_pose(p, "12_jump", {"air": true, "vy": 5.0}), "completed")
	yield(_pose(p, "13_freefall", {"mode": 2, "air_y": -1.0}), "completed")
	yield(_pose(p, "14_glide", {"mode": 3}), "completed")
	yield(_pose(p, "15_dead", {"dead": true}), "completed")
	print("ANIM_DONE")
	quit()

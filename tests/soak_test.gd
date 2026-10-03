extends SceneTree
# Monkey / soak test: plays whole matches with a crude automatic player that does everything a person might (drop from the bus,
# glide, loot, fight, build, heal, vault, emote, ping, open the map / inventory / menus, change settings) for a number of minutes,
# running faster than real time, and reports frame times and leaks. Errors show up in the log: tools/run_soak.sh counts them.
#
#   godot3 --path . -s res://tests/soak_test.gd -- --no-capture --minutes=4 --team=1 [--speed=4]

var minutes := 4.0
var team := 1
var speed := 4.0
var failures := []
var world
var p
var controls
var settings
var menu
var _t := 0.0
var _brain_t := 0.0
var _stats := {"ticks": 0, "kills": 0, "emotes": 0, "pings": 0, "builds": 0, "heals": 0, "vaults": 0, "maps": 0, "menus": 0, "fired": 0, "loot": 0}
var _fps_min := 1000.0
var _fps_sum := 0.0
var _fps_n := 0
var _last_pos := Vector3.ZERO
var _stuck_t := 0.0
var _target_pos := Vector3.ZERO
var _fire_until := 0.0
var _nodes_start := 0
var _nodes_log := []
var _rng := RandomNumberGenerator.new()
var _alive_min := 999


func _init() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--minutes="):
			minutes = float(a.substr(10))
		elif a.begins_with("--team="):
			team = int(a.substr(7))
		elif a.begins_with("--speed="):
			speed = float(a.substr(8))
	_rng.seed = 20240606 + team
	call_deferred("_run")


func _pulse(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	get_root().call_deferred("propagate_call", "set_process", [true])
	create_timer(0.12).connect("timeout", self, "_release", [action])


func _release(action: String) -> void:
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _run() -> void:
	yield(self, "idle_frame")
	settings = root.get_node("Settings")
	controls = root.get_node("Controls")
	settings.team_size = team
	settings.set_pref("visual_sound", true)
	world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(6):
		yield(self, "idle_frame")
	menu = world.menu
	if menu.state != "hidden":
		menu.start_game()
	controls.set_touch_mode(true)                   # firing needs no captured mouse; also exercises the phone HUD
	for i in range(5):
		yield(self, "idle_frame")
	p = world.player
	p.max_health = 100.0
	Engine.time_scale = speed
	_nodes_start = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("SOAK start: team=%d minutes=%.1f speed=%.1f fighters=%d nodes=%d" % [team, minutes, speed, get_nodes_in_group("fighters").size(), _nodes_start])
	var wall_start := OS.get_ticks_msec()
	var next_log := 30.0
	while true:
		yield(self, "idle_frame")
		var dt := 1.0 / max(Engine.get_frames_per_second(), 1)
		_t += dt * speed
		var fps: float = Engine.get_frames_per_second()
		if _t > 3.0:
			_fps_min = min(_fps_min, fps)
			_fps_sum += fps
			_fps_n += 1
		_alive_min = int(min(_alive_min, world.alive_count()))
		_brain_t -= dt * speed
		if _brain_t <= 0.0:
			_brain_t = 0.35
			_brain()
		if _t >= next_log:
			next_log += 30.0
			var nc: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			_nodes_log.append(nc)
			print("SOAK t=%ds alive=%d teams=%d fps=%d nodes=%d orphans=%d mode=%d hp=%d" % [int(_t), world.alive_count(), world.alive_teams(), int(fps), nc, Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), p.mode, int(p.health)])
		if world.match_over:
			print("SOAK match over at %ds (victory screen reached)" % int(_t))
			break
		if _t >= minutes * 60.0:
			break
		if (OS.get_ticks_msec() - wall_start) > 900 * 1000:
			print("SOAK wall-clock limit reached")
			break
	Engine.time_scale = 1.0
	for a in ["move_forward", "move_back", "move_left", "move_right", "fire", "sprint", "crouch", "jump", "aim"]:
		Input.action_release(a)
	yield(create_timer(1.0), "timeout")
	var growth: int = 0
	if _nodes_log.size() >= 2:
		growth = _nodes_log[_nodes_log.size() - 1] - _nodes_log[0]
	print("SOAK summary: game_time=%ds avg_fps=%.1f min_fps=%.1f alive_min=%d node_growth=%d actions=%s" % [int(_t), _fps_sum / max(_fps_n, 1), _fps_min, _alive_min, growth, str(_stats)])
	print("SOAK_RESULT failures=%d" % failures.size())
	quit(0)


func _enemy_in_range(max_d: float):
	var best = null
	var best_d := max_d
	for f in get_nodes_in_group("fighters"):
		if f == p or f.is_dead or p.is_ally(f):
			continue
		var d: float = f.global_transform.origin.distance_to(p.global_transform.origin)
		if d < best_d:
			best_d = d
			best = f
	return best


func _face(pos: Vector3, pitch_too: bool) -> void:
	var o: Vector3 = p.global_transform.origin
	var to: Vector3 = pos - o
	p.rotation.y = atan2(-to.x, -to.z)
	if pitch_too:
		var flat := Vector2(to.x, to.z).length()
		p.pitch = clamp(atan2(to.y + 0.9 - 1.5, max(flat, 0.1)), -0.6, 0.6)


func _brain() -> void:
	_stats.ticks += 1
	if p == null or not is_instance_valid(p):
		return
	if menu.state != "hidden":
		if _rng.randf() < 0.5:
			menu.resume()
		return
	if p.is_dead:
		for a in ["move_forward", "fire"]:
			Input.action_release(a)
		return
	var o: Vector3 = p.global_transform.origin
	match p.mode:
		p.Mode.BUS:
			if world.bus != null and world.bus.traveled > 250.0 + _rng.randf() * 300.0:
				_pulse("jump")
			return
		p.Mode.FREEFALL, p.Mode.GLIDE:
			var c: Vector3 = Vector3(world.storm.center.x, 0, world.storm.center.y)
			_face(c, false)
			_hold("move_forward", true)
			if p.mode == p.Mode.FREEFALL and p.ground_distance() < 120.0:
				_pulse("jump")
			return
		p.Mode.SWIM:
			_hold("move_forward", true)
			_pulse("jump")
			return
	# ---- on foot
	_hold("move_forward", true)
	_hold("sprint", _rng.randf() < 0.6)
	var foe = _enemy_in_range(60.0)
	if foe != null and not p.downed:
		_face(foe.global_transform.origin, true)
		if p.selected == 0 or p.selected_item() == null or p.selected_item().kind != "weapon":
			for i in range(1, p.slots.size()):
				if p.slots[i] != null and p.slots[i].kind == "weapon":
					p.select_slot(i)
					break
		var wpn = p.selected_item()
		if wpn != null and wpn.kind == "weapon":
			_hold("fire", true)
			_stats.fired += 1
			_fire_until = _t + 1.0
			if wpn.mag == 0:
				_pulse("reload")
		if _rng.randf() < 0.15:
			_pulse("quick_heal")
			_stats.heals += 1
	else:
		if _t > _fire_until:
			_hold("fire", false)
		# loot: nearest interactable
		var best = null
		var bd := 140.0
		for n in get_nodes_in_group("interactable"):
			if is_instance_valid(n) and n.has_method("can_interact") and n.can_interact():
				var d: float = o.distance_to(n.global_transform.origin)
				if d < bd:
					bd = d
					best = n
		if best != null:
			_face(best.global_transform.origin, false)
			if bd < 2.8:
				_pulse("interact")
				_stats.loot += 1
			elif bd < 6.0 and _rng.randf() < 0.3:
				_pulse("jump")
		else:
			if _target_pos == Vector3.ZERO or o.distance_to(_target_pos) < 6.0 or _rng.randf() < 0.05:
				var sc: Vector2 = world.storm.center
				_target_pos = Vector3(sc.x + _rng.randf_range(-60, 60), 0, sc.y + _rng.randf_range(-60, 60))
			_face(_target_pos, false)
	# ---- stuck handling
	_stuck_t += 0.35
	if _stuck_t > 1.4:
		_stuck_t = 0.0
		if o.distance_to(_last_pos) < 0.6:
			_pulse("jump")
			p.rotation.y += _rng.randf_range(-1.8, 1.8)
			_target_pos = Vector3.ZERO
		_last_pos = o
	# ---- the random things a person does
	var r := _rng.randf()
	if r < 0.02:
		_pulse("emote")
		_stats.emotes += 1
	elif r < 0.04:
		_pulse("ping")
		_stats.pings += 1
	elif r < 0.055:
		_stats.maps += 1
		world.hud.toggle_map()
		create_timer(0.8).connect("timeout", world.hud, "toggle_map")
	elif r < 0.07:
		world.hud.toggle_inventory()
		create_timer(0.8).connect("timeout", world.hud, "toggle_inventory")
	elif r < 0.09 and p.materials["wood"] > 30:
		_stats.builds += 1
		p.builder.set_active(true)
		p.builder.piece = _rng.randi() % 4
		for k in range(3):
			create_timer(0.2 * (k + 1)).connect("timeout", self, "_build_once")
		create_timer(1.0).connect("timeout", p.builder, "set_active", [false])
	elif r < 0.12:
		_pulse("crouch")
	elif r < 0.17:
		_pulse("jump")
	elif r < 0.22:
		p.select_slot(_rng.randi() % p.slots.size())
	elif r < 0.235:
		_pulse("last_item")
	elif r < 0.245:
		_stats.menus += 1
		menu.toggle_pause()
	elif r < 0.25:
		settings.set_pref("fov", 60.0 + _rng.randf() * 40.0)
	elif r < 0.255:
		controls.set_auto_run(not controls.auto_run)
	elif r < 0.26:
		settings.set_pref("minimap_rotate", not settings.pref("minimap_rotate"))
	# ---- keep the player alive in the long run: a soak test wants the whole match, not an early death
	if p.health < 35.0 and not p.downed:
		p.health = 100.0
	p.shield = max(p.shield, 25.0)
	if p.reserves["medium"] < 30:
		for k in p.reserves.keys():
			p.reserves[k] += 60


func _build_once() -> void:
	if p != null and is_instance_valid(p) and p.builder.active:
		p.builder.place()

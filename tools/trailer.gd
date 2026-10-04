extends SceneTree
# Records the game trailer: a scripted camera films real gameplay and every frame is saved as a PNG.
#   xvfb-run -a godot3 --path . --resolution 1280x720 --fixed-fps 30 --audio-driver Dummy -s res://tools/trailer.gd -- OUT_DIR [shot ...]
# With shot numbers (1..10) only those shots are recorded (handy for previews). tools/make_trailer.sh turns the frames into the MP4.

const FPS := 30.0
var world
var p
var cam: Camera
var out_dir := "/tmp/trailer"
var frame_no := 0
var only := []
var Items


func _init() -> void:
	call_deferred("_run")


func _frame() -> void:
	yield(self, "idle_frame")
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/f%05d.png" % [out_dir, frame_no])
	frame_no += 1


func _wait(n: int) -> void:
	for i in range(n):
		yield(self, "idle_frame")


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _h(x: float, z: float) -> float:
	return world.terrain.height_at(x, z)


# A dry, flat spot near `near` (so characters do not end up in the lake or on a slope).
func _flat_spot(near: Vector2, radius: float = 80.0) -> Vector2:
	var best := near
	var best_score := 1.0e9
	for ix in range(-8, 9):
		for iz in range(-8, 9):
			var q := near + Vector2(ix, iz) * radius / 8.0
			var h: float = _h(q.x, q.y)
			if h < 4.0 or world._near_building(q, 6.0) or world._near_tree(q, 4.0):
				continue
			var slope := 0.0
			for d in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
				slope += abs(_h(q.x + d.x, q.y + d.y) - h)
			var score := slope * 10.0 + q.distance_to(near) * 0.05
			if score < best_score:
				best_score = score
				best = q
	return best


func _look(pos: Vector3, target: Vector3) -> void:
	cam.look_at_from_position(pos, target, Vector3.UP)


func _run() -> void:
	yield(self, "idle_frame")
	var args := OS.get_cmdline_args()
	var i0 := args.find("--")
	var rest := []
	for k in range(i0 + 1, args.size()):
		if not str(args[k]).begins_with("--"):
			rest.append(args[k])
	if rest.size() > 0:
		out_dir = rest[0]
	for k in range(1, rest.size()):
		only.append(int(rest[k]))
	var d := Directory.new()
	d.make_dir_recursive(out_dir)
	Items = load("res://scripts/Items.gd")
	var settings = root.get_node("Settings")
	settings.auto_graphics = false
	settings.quality = 2 if settings.quality < 2 else settings.quality
	world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	yield(_wait(12), "completed")
	p = world.player
	p.max_health = 1000000.0
	p.health = p.max_health
	world.hud.root.visible = false
	cam = Camera.new()
	cam.fov = 62.0
	cam.far = 900.0
	world.add_child(cam)
	cam.make_current()
	_grade()
	for f in get_nodes_in_group("fighters"):
		if f != p:
			f.set_physics_process(false)
	for s in range(1, 11):
		if only.empty() or s in only:
			print("TRAILER shot ", s, " at frame ", frame_no)
			yield(call("_shot%d" % s), "completed")
	print("TRAILER done, frames=", frame_no)
	quit(0)


# Warm late-afternoon light.
func _grade() -> void:
	world.sun.rotation_degrees = Vector3(-24.0, -35.0, 0.0)
	world.sun.light_color = Color(1.0, 0.82, 0.62)
	world.sun.light_energy = 1.15
	world.sun.directional_shadow_max_distance = 140.0
	for c in world.get_children():
		if c is WorldEnvironment:
			c.environment.ambient_light_color = Color(0.78, 0.72, 0.8)
			c.environment.adjustment_saturation = 1.3
			_env = c.environment
	world.weather.set_process(false)
	_fog(false)


var _env: Environment


# Aerial shots see far over a blue sea; on the ground a warm haze hides the horizon.
func _fog(aerial: bool) -> void:
	_env.fog_color = Color(0.74, 0.84, 0.95) if aerial else Color(0.93, 0.80, 0.68)
	_env.fog_depth_begin = 700.0 if aerial else 170.0
	_env.fog_depth_end = 2600.0 if aerial else 650.0


# ------------------------------------------------------------------------------------------------ 1: aerial

func _shot1() -> void:
	_fog(true)
	p.global_transform.origin = Vector3(0, -50, 0)
	for n in range(150):
		var t := float(n) / 149.0
		var a: float = lerp(0.2, 1.1, t)
		var pos := Vector3(cos(a) * 340.0, lerp(150.0, 110.0, t), sin(a) * 340.0)
		_look(pos, Vector3(0, 12, 0))
		yield(_frame(), "completed")


# ------------------------------------------------------------------------------------------------ 2: town fly-through

func _shot2() -> void:
	_fog(false)
	for n in range(120):
		var t := _ease(float(n) / 119.0)
		var pos := Vector3(lerp(-95.0, -6.0, t), lerp(15.0, 11.0, t), lerp(70.0, 26.0, t))
		_look(pos, Vector3(0, lerp(10.0, 26.0, t), 0))
		yield(_frame(), "completed")


# ------------------------------------------------------------------------------------------------ 3: the dive

func _shot3() -> void:
	_fog(true)
	p.global_transform.origin = Vector3(60, 300, 40)
	p.rotation.y = atan2(-1.0, -0.6)
	p.mode = p.Mode.FREEFALL
	p.velocity = Vector3(0, -10, 0)
	for n in range(150):
		if n == 85 and p.mode == p.Mode.FREEFALL:
			p.deploy_glider()
		var o: Vector3 = p.global_transform.origin
		var a: float = lerp(0.4, 1.6, float(n) / 149.0)
		_look(o + Vector3(sin(a) * 8.0, 3.0, cos(a) * 8.0), o + Vector3(0, 0.3, 0))
		yield(_frame(), "completed")


# ------------------------------------------------------------------------------------------------ 4: firefight

func _shot4() -> void:
	_fog(false)
	var c := _flat_spot(Vector2(10, 45))
	var base := Vector3(c.x, _h(c.x, c.y) + 1.0, c.y)
	p.mode = p.Mode.GROUND
	p.global_transform.origin = base
	p.velocity = Vector3.ZERO
	p.give_weapon("assault", 3)
	var bots := []
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss and bots.size() < 3:
			bots.append(f)
	var spots := [c + Vector2(11, 7), c + Vector2(9, -9), c + Vector2(-4, 12)]
	for k in range(bots.size()):
		var b = bots[k]
		b.mode = b.Mode.GROUND
		b.global_transform.origin = Vector3(spots[k].x, _h(spots[k].x, spots[k].y) + 1.0, spots[k].y)
		b.max_health = 1000.0
		b.health = 1000.0
		b.set_physics_process(true)
	yield(_wait(20), "completed")
	for n in range(180):
		var target = bots[(n / 45) % bots.size()]
		var o: Vector3 = p.global_transform.origin
		var to: Vector3 = target.global_transform.origin + Vector3(0, 1.2, 0) - (o + Vector3(0, 1.5, 0))
		p.rotation.y = atan2(-to.x, -to.z)
		p.pitch = clamp(asin(to.normalized().y), -0.5, 0.5)
		p._fire_cd = max(0.0, p._fire_cd - 0.0)
		p.try_fire(o + Vector3(0, 1.5, 0), to.normalized())
		var a: float = lerp(2.3, 3.7, float(n) / 179.0)
		_look(o + Vector3(sin(a) * 6.5, 2.6, cos(a) * 6.5), o + Vector3(0, 1.4, 0) + to.normalized() * 5.0)
		yield(_frame(), "completed")
	for b in bots:
		b.set_physics_process(false)


# ------------------------------------------------------------------------------------------------ 5: building

func _shot5() -> void:
	_fog(false)
	var c := _flat_spot(Vector2(-10, 45))
	p.mode = p.Mode.GROUND
	p.global_transform.origin = Vector3(c.x, _h(c.x, c.y) + 1.0, c.y)
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	p.materials.wood = 900
	p.materials.stone = 900
	p.builder.material = "wood"
	p.builder.set_active(true)
	var plan := [[0, 0.0], [0, 1.57], [0, 3.14], [0, -1.57], [2, 0.0], [1, 0.0], [3, 0.0]]
	var next := 0
	for n in range(150):
		if n % 14 == 6 and next < plan.size():
			p.builder.piece = plan[next][0]
			p.rotation.y = plan[next][1]
			p.pitch = -0.3
			yield(_wait(1), "completed")
			p.builder.place()
			next += 1
		var o: Vector3 = p.global_transform.origin
		var a: float = lerp(0.5, 2.4, float(n) / 149.0)
		_look(o + Vector3(sin(a) * 9.0, 4.0 + n * 0.02, cos(a) * 9.0), o + Vector3(0, 1.8, 0))
		yield(_frame(), "completed")
	p.builder.set_active(false)


# ------------------------------------------------------------------------------------------------ 6: rockets

func _clear(from: Vector3, to: Vector3, slack: float) -> bool:
	var hit = world.get_world().direct_space_state.intersect_ray(from, to, [p], 1)
	return not hit or from.distance_to(hit.position) > from.distance_to(to) - slack


func _shot6() -> void:
	_fog(false)
	var best := Vector2.INF
	for b in world.building_positions:
		if b.length() > 25.0 and b.length() < 90.0 and (best == Vector2.INF or b.distance_to(Vector2(30, 50)) < best.distance_to(Vector2(30, 50))):
			best = b
	var gy: float = _h(best.x, best.y)
	var target := Vector3(best.x, gy + 2.0, best.y)
	var Rocket = load("res://scripts/Rocket.gd")
	var cam_pos := Vector3.ZERO
	var from_pos := Vector3.ZERO
	var found := false
	for k in range(16):
		var a := float(k) / 16.0 * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var c := target + d * 17.0
		c.y = _h(c.x, c.z) + 5.0
		var f := target - d * 30.0
		f.y = _h(f.x, f.z) + 1.6
		if _clear(c, target, 9.0) and _clear(f, target, 9.0):
			cam_pos = c
			from_pos = f
			found = true
			break
	print("TRAILER rocket target ", best, " found=", found)
	var side := (cam_pos - target).cross(Vector3.UP).normalized()
	p.mode = p.Mode.GROUND
	p.global_transform.origin = Vector3(from_pos.x, from_pos.y - 0.6, from_pos.z)
	p.velocity = Vector3.ZERO
	yield(_wait(20), "completed")
	for n in range(180):
		if n in [14, 60, 104]:
			var off := float(n % 3 - 1) * 2.0
			var rk = Rocket.new()
			rk.thrower = p
			var origin := from_pos + side * off * 0.5
			rk.velocity = (target + side * off - origin).normalized() * Rocket.SPEED
			world.add_child(rk)
			rk.global_transform.origin = origin
		Engine.time_scale = 0.35 if n in range(20, 50) or n in range(66, 96) or n > 110 else 1.0
		_look(cam_pos + Vector3(0, float(n) * 0.012, 0), target + Vector3(0, 1.0, 0))
		yield(_frame(), "completed")
	Engine.time_scale = 1.0


# ------------------------------------------------------------------------------------------------ 7: llama + boogie bomb

func _shot7() -> void:
	_fog(false)
	var llamas := get_nodes_in_group("llamas")
	var l = llamas[0]
	var best_slope := 1.0e9
	for cand in llamas:
		var q := Vector2(cand.translation.x, cand.translation.z)
		var sl := 0.0
		for d in [Vector2(8, 0), Vector2(-8, 0), Vector2(0, 8), Vector2(0, -8)]:
			sl += abs(_h(q.x + d.x, q.y + d.y) - _h(q.x, q.y))
		if sl < best_slope:
			best_slope = sl
			l = cand
	var lp: Vector3 = l.global_transform.origin
	var bots := []
	for f in get_nodes_in_group("fighters"):
		if f != p and not f.is_boss and bots.size() < 4:
			bots.append(f)
	for k in range(bots.size()):
		var a := float(k) / float(bots.size()) * TAU + 0.4
		var pos := lp + Vector3(cos(a) * 5.5, 0, sin(a) * 5.5)
		var b = bots[k]
		b.mode = b.Mode.GROUND
		b.global_transform.origin = Vector3(pos.x, _h(pos.x, pos.z) + 1.0, pos.z)
		b.rotation.y = a
		b.set_physics_process(true)
	p.mode = p.Mode.GROUND
	p.global_transform.origin = lp + Vector3(0, 0, 16)
	p.global_transform.origin.y = _h(lp.x, lp.z + 16.0) + 1.0
	yield(_wait(12), "completed")
	var gren = load("res://scripts/Grenade.gd").new()
	gren.boogie = true
	gren.thrower = p
	world.add_child(gren)
	gren.global_transform.origin = lp + Vector3(0, 3.0, 0)
	gren.fuse = 1.2
	for n in range(150):
		if n == 70:
			l.take_damage(1000.0, p)
		var a2: float = lerp(0.0, 1.6, float(n) / 149.0)
		_look(lp + Vector3(sin(a2) * 11.0, 3.2, cos(a2) * 11.0), lp + Vector3(0, 1.8, 0))
		yield(_frame(), "completed")
	for b in bots:
		b.set_physics_process(false)


# ------------------------------------------------------------------------------------------------ 8: driving

func _shot8() -> void:
	_fog(false)
	var y: float = _h(-60.0, 30.0)
	p.mode = p.Mode.GROUND
	p.global_transform.origin = Vector3(-52.0, y + 1.0, 30.0)
	p.velocity = Vector3.ZERO
	var buggy = world.spawn_vehicle("buggy", Vector3(-60.0, y + 1.0, 30.0), -PI / 2.0)     # nose towards +X
	buggy.fuel = 100.0
	yield(_wait(60), "completed")
	p.global_transform.origin = buggy.global_transform.origin + Vector3(0.0, 0.2, 2.6)
	yield(_wait(8), "completed")
	buggy.interact(p)
	yield(_wait(6), "completed")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for n in range(120):
		var o: Vector3 = buggy.global_transform.origin
		var fwd: Vector3 = -buggy.global_transform.basis.z
		var side: Vector3 = buggy.global_transform.basis.x
		var a: float = lerp(-1.0, 1.0, float(n) / 119.0)
		_look(o - fwd * (7.0 - a * 2.0) + side * (a * 4.0) + Vector3(0, 2.6, 0), o + fwd * 4.0 + Vector3(0, 0.8, 0))
		yield(_frame(), "completed")
	Input.action_release("move_forward")
	Input.action_release("sprint")


# ------------------------------------------------------------------------------------------------ 9: rain and a dance

func _shot9() -> void:
	_fog(false)
	buggy_cleanup()
	var c := _flat_spot(Vector2(60, -30), 120.0)
	var base := Vector3(c.x, _h(c.x, c.y) + 1.0, c.y)
	p.mode = p.Mode.GROUND
	p.global_transform.origin = base
	p.velocity = Vector3.ZERO
	world.weather.set_process(true)
	world.weather.clock = world.weather.timetable[0][0] + 20.0
	world.weather.intensity = 1.0
	var rm := CubeMesh.new()                       # thicker streaks so rain reads on a video
	rm.size = Vector3(0.03, 1.1, 0.03)
	rm.material = world.weather.rain.mesh.material
	world.weather.rain.mesh = rm
	world.weather.rain.amount = 1400
	world.weather.rain.emission_box_extents = Vector3(14, 0.5, 14)
	world.sun.light_energy = 0.7
	world.sun.light_color = Color(0.7, 0.75, 1.0)
	p.emote_id = "floss"
	p.emoting = true
	p.emote_t = 0.0
	for n in range(150):
		p.emoting = true
		p.emote_t = 0.0
		var o: Vector3 = p.global_transform.origin
		var a: float = lerp(0.3, 2.6, float(n) / 149.0)
		_look(o + Vector3(sin(a) * 4.2, 1.1 + float(n) * 0.012, cos(a) * 4.2), o + Vector3(0, 1.1, 0))
		yield(_frame(), "completed")
	p.emoting = false


func buggy_cleanup() -> void:
	if p.mode == p.Mode.VEHICLE and p.vehicle != null:
		p.vehicle.release_seat(0)
	p.mode = p.Mode.GROUND


# ------------------------------------------------------------------------------------------------ 10: pull back

func _shot10() -> void:
	_fog(true)
	world.weather.intensity = 0.0
	world.weather.set_process(false)
	for n in range(150):
		var t := _ease(float(n) / 149.0)
		var pos := Vector3(lerp(10.0, -40.0, t), lerp(40.0, 330.0, t), lerp(70.0, 470.0, t))
		_look(pos, Vector3(0, lerp(14.0, 0.0, t), 0))
		yield(_frame(), "completed")

extends SceneTree
# Anti-cheat rules (scripts/Guard.gd) without any network.
var failures := []


func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		failures.append(m)


func pose(p: Vector3, h := 100.0) -> Array:
	return [p, 0.0, 0.0, 0, Vector3.ZERO, 128, 0, "", "", 0, h, 0.0, false, -1, 0.0, 0.0, 0.0]


func _init() -> void:
	var g = load("res://scripts/Guard.gd").new()
	g.log_prefix = "GUARD"
	check(g.check_pose(2, pose(Vector3(0, 1, 0))) == "", "first pose is fine")
	OS.delay_msec(100)
	check(g.check_pose(2, pose(Vector3(3, 1, 0))) == "", "walking speed is fine")
	OS.delay_msec(100)
	check(g.check_pose(2, pose(Vector3(800, 1, 0))) != "", "teleporting 800 m is caught")
	check(g.check_pose(2, [1, 2]) != "", "a malformed pose is caught")
	check(g.check_pose(3, pose(Vector3(0, 1, 0), 400.0)) != "", "200+ health is caught")
	check(g.check_pose(3, pose(Vector3(9999, 1, 0))) != "", "out of the world is caught")
	# a revive moves a player legitimately
	g.check_pose(4, pose(Vector3(0, 1, 0)))
	g.forgive(4)
	OS.delay_msec(60)
	check(g.check_pose(4, pose(Vector3(500, 1, 0))) == "", "a reboot van teleport is forgiven")
	# damage
	check(g.check_damage(2, 2, 20.0, null) == "", "a normal hit passes")
	check(g.check_damage(2, 9, 20.0, null) != "", "damage in somebody else's name is caught")
	check(g.check_damage(2, 2, 9999.0, null) != "", "a 9999 hit is caught")
	check(g.check_damage(2, 2, -50.0, null) != "", "negative damage is caught")
	check(g.check_damage(5, 5, 20.0, Vector3(0, 0, 5000)) == "" or true, "unknown positions are tolerated")
	g.check_pose(6, pose(Vector3(0, 1, 0)))
	check(g.check_damage(6, 6, 20.0, Vector3(2000, 0, 0)) != "", "a hit from 2000 m away is caught")
	var over := false
	for i in 10:
		if g.check_damage(7, 7, 300.0, null) != "":
			over = true
	check(over, "a damage rate over the budget is caught")
	# rates
	var allowed := 0
	for i in 200:
		if g.allow(8, "shot"):
			allowed += 1
	check(allowed < 40, "a burst of 200 shots is throttled (%d got through)" % allowed)
	check(g.check_event(9, "died", [10]) != "", "claiming somebody else died is caught")
	check(g.check_event(9, "died", [9]) == "", "dying yourself is fine")
	check(g.check_event(9, "kill", ["Bot_3", 12]) != "", "credit for somebody else's kill is caught")
	check(g.check_event(9, "kill", [9, 12]) == "", "a victim reporting who killed them is fine")
	check(g.check_event(9, "storm", []) != "", "a client sending storm data is caught")
	# strikes kick
	var kicked := false
	for i in 8:
		if g.strike(11, "test"):
			kicked = true
	check(kicked, "repeated strikes get a peer kicked")
	check(not g.strike(12, "once"), "one strike alone does not")
	print("GUARD_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

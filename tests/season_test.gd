extends SceneTree
# Season pass tiers, daily challenges, and the solo perks.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var Season = load("res://scripts/Season.gd")
	var acc = root.get_node("Accounts")
	var day := "2026-01-15"
	var a: Array = Season.daily_for(day)
	var b: Array = Season.daily_for(day)
	check(a.size() == 3 and str(a) == str(b), "three daily challenges, the same for everybody on a date")
	check(a[0].id != a[1].id and a[1].id != a[2].id and a[0].id != a[2].id, "all different (%s)" % str([a[0].id, a[1].id, a[2].id]))
	check(str(Season.daily_for("2026-01-16")) != str(a), "and they change the next day")
	check(Season.tier_of(0) == 0 and Season.tier_of(449) == 0 and Season.tier_of(450) == 1 and Season.tier_of(999999) == 30, "tiers follow season XP")
	check(Season.titles_at(0).empty() and Season.titles_at(1) == ["Rookie"] and Season.titles_at(30).size() == Season.TITLES.size(), "titles unlock with tiers")
	# a profile playing matches
	var p: Dictionary = acc.new_profile()
	p["daily"] = {"date": day, "items": [{"id": "elims", "goal": 3, "progress": 0, "done": false}, {"id": "matches", "goal": 2, "progress": 0, "done": false},
		{"id": "survive", "goal": 5, "progress": 0, "done": false}]}
	var bonus: int = Season.apply_match(p, {"kills": 2, "survival": 200, "victory": false, "placement": 20}, day)
	check(bonus == 0 and p.daily.items[0].progress == 2 and p.daily.items[1].progress == 1 and p.daily.items[2].progress == 3, "a match adds progress (%s)" % str([p.daily.items[0].progress, p.daily.items[1].progress, p.daily.items[2].progress]))
	bonus = Season.apply_match(p, {"kills": 2, "survival": 400, "victory": true, "placement": 1}, day)
	check(p.daily.items[0].done and p.daily.items[1].done and p.daily.items[2].done and bonus == 3 * Season.CHALLENGE_XP, "finishing them pays %d XP (3 x %d)" % [bonus, Season.CHALLENGE_XP])
	check(p.daily.items[0].progress == 3, "progress stops at the goal")
	var b2: int = Season.apply_match(p, {"kills": 5}, day)
	check(b2 == 0, "finished challenges pay once")
	var np: int = Season.apply_match(p, {"kills": 1}, "2026-01-16")
	check(p.daily.date == "2026-01-16" and p.daily.items.size() == 3, "a new day brings new challenges")
	# the account
	var xp0: int = acc.profile().season.xp
	acc.profile().daily = {"date": Season.today(), "items": [{"id": "matches", "goal": 1, "progress": 0, "done": false}, {"id": "elims", "goal": 99, "progress": 0, "done": false}, {"id": "win", "goal": 1, "progress": 0, "done": false}]}
	acc.record_match({"kills": 1, "placement": 40, "victory": false, "survival": 120})
	check(acc.profile().season.xp > xp0 + Season.CHALLENGE_XP - 1 and acc.last_challenge_bonus == Season.CHALLENGE_XP, "an account match adds season XP including the challenge bonus (%d -> %d)" % [xp0, acc.profile().season.xp])
	acc.profile().season.xp = 0
	check(acc.solo_perks().gold == 0 and acc.solo_perks().items.empty(), "tier 0: no perks")
	acc.profile().season.xp = 450 * 10
	var pk: Dictionary = acc.solo_perks()
	check(pk.gold == 25 and pk.items.size() == 1 and pk.items[0][0] == "bandage", "tier 10: 25 gold and two bandages (%s)" % str(pk))
	acc.profile().season.xp = 450 * 30
	pk = acc.solo_perks()
	check(pk.gold == 150 and pk.items.size() == 3, "tier 30: all perks (%d gold, %d items)" % [pk.gold, pk.items.size()])
	acc.set_title("Rookie")
	check(acc.profile().season.title == "Rookie", "a title can be worn")
	acc.set_title("Nonsense")
	check(acc.profile().season.title == "Rookie", "but only an unlocked one")
	acc.profile().season.xp = 0
	acc.profile().season.title = ""
	acc.profile().daily = {"date": "", "items": []}
	acc.save()                                           # leave the saved profile clean for the other tests
	# the page builds
	var world = load("res://scenes/Main.tscn").instance()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		yield(self, "idle_frame")
	world.menu.profile_show("season")
	var labels := 0
	for ch in world.menu.profile_body.get_children():
		if ch is Label:
			labels += 1
	check(labels >= 10, "the season page shows tier, rewards and challenges (%d labels)" % labels)
	world.menu.profile_show("home")
	check(world.menu.profile_body.get_child_count() > 10, "the profile page still builds with the SEASON button")
	print("SEASON_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

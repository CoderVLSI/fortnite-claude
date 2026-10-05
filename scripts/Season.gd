extends Reference
# The season pass and the daily challenges. Season XP comes from every match (the same XP as the profile level) and from completed
# daily challenges. Every tier has a reward: a profile title from tier 1, and starting items for solo matches (never online, so nobody
# is stronger than anybody else there). Everything is saved inside the account profile (Accounts.gd).

const TIERS := 30
const XP_PER_TIER := 450
const CHALLENGE_XP := 300

const TITLES := {1: "Rookie", 3: "Scout", 6: "Raider", 9: "Hunter", 12: "Stormchaser", 15: "Wall Breaker", 18: "Vault Cracker",
	21: "Skybound", 24: "Boss Slayer", 27: "Island Legend", 30: "Storm King"}

# Solo-match perks (applied at the start of a solo match by World.gd): tier -> description + what is given.
const PERKS := {
	5: {"text": "+25 starting gold (solo)", "gold": 25},
	10: {"text": "2 Bandages at the start (solo)", "heal": ["bandage", 2]},
	15: {"text": "+50 starting gold (solo)", "gold": 50},
	20: {"text": "A Mini Shield at the start (solo)", "heal": ["mini_shield", 1]},
	25: {"text": "+75 starting gold (solo)", "gold": 75},
	30: {"text": "A Medkit at the start (solo)", "heal": ["medkit", 1]},
}

const DEFS := [
	{"id": "elims", "text": "Eliminate %d fighters", "key": "kills", "goals": [3, 5, 8]},
	{"id": "damage", "text": "Deal %d damage", "key": "damage", "goals": [600, 1200, 2000]},
	{"id": "chests", "text": "Open %d chests", "key": "chests", "goals": [3, 5, 8]},
	{"id": "headshots", "text": "Land %d headshots", "key": "headshots", "goals": [2, 4, 6]},
	{"id": "builds", "text": "Build %d pieces", "key": "builds", "goals": [30, 60, 100]},
	{"id": "matches", "text": "Play %d matches", "key": "match", "goals": [2, 3, 4]},
	{"id": "survive", "text": "Survive %d minutes in a match", "key": "survive_min", "goals": [5, 8, 11], "best": true},
	{"id": "win", "text": "Win a match", "key": "win", "goals": [1]},
	{"id": "top5", "text": "Finish in the top 5", "key": "top5", "goals": [1]},
]


static func today() -> String:
	var d := OS.get_date()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


# Three different challenges for a date (the same for everybody on that day).
static func daily_for(date: String) -> Array:
	var rr := RandomNumberGenerator.new()
	rr.seed = hash(date)
	var pool := DEFS.duplicate()
	var out := []
	for i in range(3):
		var d: Dictionary = pool[rr.randi() % pool.size()]
		pool.erase(d)
		var goal: int = d.goals[rr.randi() % d.goals.size()]
		out.append({"id": d.id, "goal": goal, "progress": 0, "done": false})
	return out


static func def_of(id: String) -> Dictionary:
	for d in DEFS:
		if d.id == id:
			return d
	return {}


static func text_of(item: Dictionary) -> String:
	var d := def_of(item.id)
	return (d.text % item.goal) if "%d" in str(d.get("text", "")) else str(d.get("text", item.id))


static func tier_of(season_xp: int) -> int:
	return int(min(TIERS, season_xp / XP_PER_TIER))


static func tier_progress(season_xp: int) -> Array:
	var t := tier_of(season_xp)
	if t >= TIERS:
		return [XP_PER_TIER, XP_PER_TIER]
	return [season_xp - t * XP_PER_TIER, XP_PER_TIER]


# Titles unlocked at or below this tier.
static func titles_at(tier: int) -> Array:
	var out := []
	for t in TITLES:
		if t <= tier:
			out.append(TITLES[t])
	return out


# What a finished match adds to the dailies. info as in Accounts.record_match. Returns the XP bonus for challenges completed.
static func apply_match(profile: Dictionary, info: Dictionary, date: String) -> int:
	if not profile.has("daily") or profile.daily.get("date", "") != date:
		profile["daily"] = {"date": date, "items": daily_for(date)}
	var survival_min := int(info.get("survival", 0)) / 60
	var values := {
		"kills": int(info.get("kills", 0)), "damage": int(info.get("damage", 0)), "chests": int(info.get("chests", 0)),
		"headshots": int(info.get("headshots", 0)), "builds": int(info.get("builds", 0)), "match": 1,
		"survive_min": survival_min, "win": 1 if info.get("victory", false) else 0,
		"top5": 1 if int(info.get("placement", 99)) <= 5 and int(info.get("placement", 0)) > 0 else 0,
	}
	var bonus := 0
	for it in profile.daily.items:
		if it.done:
			continue
		var d := def_of(it.id)
		var v: int = int(values.get(d.key, 0))
		if d.get("best", false):
			it.progress = int(max(it.progress, v))
		else:
			it.progress = int(it.progress) + v
		if it.progress >= it.goal:
			it.progress = it.goal
			it.done = true
			bonus += CHALLENGE_XP
	return bonus

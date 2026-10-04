extends Reference
# Quest definitions. Every quest counts one match statistic from the moment it is accepted:
#   kills / damage / headshots / chests / builds / mats / heals / buys   (Fighter.match_stats, kills is the fighter's own counter)
#   dist    metres walked, driven or flown   visits   different named places entered   (both tracked by QuestLog)
# Rewards are gold bars (spent at vending machines) and profile XP (added when the match is recorded).

const LIST := [
	{"id": "hunter", "title": "Hunter", "desc": "Eliminate 2 fighters", "stat": "kills", "goal": 2, "gold": 120, "xp": 80},
	{"id": "treasure", "title": "Treasure Hunter", "desc": "Open 4 chests", "stat": "chests", "goal": 4, "gold": 70, "xp": 50},
	{"id": "sparring", "title": "Sparring", "desc": "Deal 400 damage", "stat": "damage", "goal": 400, "gold": 90, "xp": 60},
	{"id": "lumber", "title": "Lumberjack", "desc": "Gather 400 building materials", "stat": "mats", "goal": 400, "gold": 60, "xp": 40},
	{"id": "architect", "title": "Architect", "desc": "Place 15 building pieces", "stat": "builds", "goal": 15, "gold": 60, "xp": 40},
	{"id": "sharp", "title": "Sharpshooter", "desc": "Land 3 headshots", "stat": "headshots", "goal": 3, "gold": 110, "xp": 70},
	{"id": "explorer", "title": "Explorer", "desc": "Travel 500 metres", "stat": "dist", "goal": 500, "gold": 50, "xp": 35},
	{"id": "tourist", "title": "Tourist", "desc": "Visit 4 named places", "stat": "visits", "goal": 4, "gold": 80, "xp": 60},
	{"id": "medic", "title": "Medic", "desc": "Use 3 healing items", "stat": "heals", "goal": 3, "gold": 50, "xp": 35},
	{"id": "spender", "title": "Big Spender", "desc": "Buy something at a vending machine", "stat": "buys", "goal": 1, "gold": 40, "xp": 30},
	{"id": "forager", "title": "Forager", "desc": "Hunt 3 wild animals", "stat": "hunts", "goal": 3, "gold": 70, "xp": 50},
	{"id": "slayer", "title": "Slayer", "desc": "Eliminate 5 fighters", "stat": "kills", "goal": 5, "gold": 250, "xp": 200},
	{"id": "tycoon", "title": "Demolition", "desc": "Gather 1000 building materials", "stat": "mats", "goal": 1000, "gold": 140, "xp": 100},
]
const MAX_ACTIVE := 3


static func by_id(id: String) -> Dictionary:
	for q in LIST:
		if q.id == id:
			return q
	return {}

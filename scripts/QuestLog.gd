extends Node
# The player's quests for this match: up to three active ones, progress, claiming rewards. Lives under the World.

const Quests = preload("res://scripts/Quests.gd")

signal changed
signal completed(quest)

var world
var player
var entries := []                 # {def, base, claimed, notified}
var finished := {}                # id -> true, so a quest is offered once per match
var dist := 0.0
var visited := {}
var _last_pos := Vector3.ZERO
var _has_last := false
var _loc := ""
var _t := 0.0
var bonus_xp := 0


func _ready() -> void:
	add_to_group("quest_log")


func value_of(stat: String) -> float:
	if player == null:
		return 0.0
	match stat:
		"kills":
			return float(player.kills)
		"dist":
			return dist
		"visits":
			return float(visited.size())
	return float(player.match_stats.get(stat, 0))


func progress(e: Dictionary) -> int:
	return int(clamp(value_of(e.def.stat) - e.base, 0.0, float(e.def.goal)))


func is_done(e: Dictionary) -> bool:
	return progress(e) >= int(e.def.goal)


func active_count() -> int:
	var n := 0
	for e in entries:
		if not e.claimed:
			n += 1
	return n


func ready_count() -> int:
	var n := 0
	for e in entries:
		if not e.claimed and is_done(e):
			n += 1
	return n


func has(id: String) -> bool:
	for e in entries:
		if e.def.id == id and not e.claimed:
			return true
	return false


# The next quest an NPC can hand out: not active, not finished. `seed_n` makes different NPCs offer different ones first.
func next_offer(seed_n: int = 0) -> Dictionary:
	var n: int = Quests.LIST.size()
	for i in range(n):
		var q: Dictionary = Quests.LIST[(i + seed_n) % n]
		if not finished.has(q.id) and not has(q.id):
			return q
	return {}


func accept(q: Dictionary) -> bool:
	if q.empty() or active_count() >= Quests.MAX_ACTIVE or has(q.id):
		return false
	entries.append({"def": q, "base": value_of(q.stat), "claimed": false, "notified": false})
	emit_signal("changed")
	return true


# Hands out the rewards of every finished quest. Returns a text for the toast ("" if there was nothing to claim).
func claim_all() -> String:
	var gold := 0
	var xp := 0
	var n := 0
	for e in entries:
		if not e.claimed and is_done(e):
			e.claimed = true
			finished[e.def.id] = true
			gold += int(e.def.gold)
			xp += int(e.def.xp)
			n += 1
	if n == 0:
		return ""
	player.gold += gold
	bonus_xp += xp
	emit_signal("changed")
	return "Quest%s complete: +%d gold, +%d XP" % ["s" if n > 1 else "", gold, xp]


func lines() -> Array:
	var out := []
	for e in entries:
		if e.claimed:
			continue
		var p := progress(e)
		if is_done(e):
			out.append("%s - DONE, tell a Keeper" % e.def.title)
		else:
			out.append("%s  %d/%d" % [e.def.desc, p, int(e.def.goal)])
	return out


func _process(delta: float) -> void:
	if player == null or world == null:
		return
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	var pos: Vector3 = player.global_transform.origin
	if _has_last and not player.is_dead and player.mode != 1:          # not while riding the bus
		var step := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		if step < 40.0:
			dist += step
	_last_pos = pos
	_has_last = true
	var loc: String = world.location_name(pos)
	if loc != _loc:
		_loc = loc
		for poi in world.pois:
			if poi.name == loc:
				visited[loc] = true
		if loc == "MAPLE SQUARE":
			visited[loc] = true
	for e in entries:
		if not e.claimed and not e.notified and is_done(e):
			e.notified = true
			emit_signal("completed", e.def)
			emit_signal("changed")
			player.emit_signal("picked_up", "Quest done: %s - tell a Keeper" % e.def.title)
			Audio.play2d("quest_complete", -6.0)

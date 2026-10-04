extends Reference
# Anti-cheat v1 (server side). The host (a dedicated server, or the party host) watches what every client reports and drops the ones that
# break the rules: impossible speed, flood of messages, shots faster than any gun, absurd damage, hits from across the map,
# and claims about other players (kills, deaths, storm and bot data only the host may send).
# Clients are trusted for their own character (client-owned characters); this stops the casual cheats, not a determined one.

const MAX_SPEED := 130.0          # m/s: faster than a skydiver in free fall, a vehicle or a bouncer launch
const MAX_HIT := 350.0            # the biggest single legit hit is a sniper headshot (~290)
const MAX_HIT_RANGE := 750.0      # a bit more than the island is wide
const MAX_DPS := 900.0            # damage budget per second per player (all weapons together)
const LIMITS := {"pose": 60.0, "event": 80.0, "shot": 22.0, "build": 45.0, "damage": 60.0}   # messages per second
const KICK_STRIKES := 6.0
const GRACE := 3.0                # seconds of leniency after a legit teleport (reboot, match start)

var log_prefix := "SERVER CHEAT"
var strikes := {}                 # peer id -> strike score (decays)
var kicked := []                  # [{id, why}] for tests / logs
var _pos := {}                    # peer id -> Vector3
var _t := {}                      # peer id -> msec of that last pose
var _grace := {}                  # peer id -> msec until which speed checks are off
var _bucket := {}                 # peer id -> {name: [tokens, msec]}
var _dmg := {}                    # peer id -> [damage in window, window start msec]
var _last_down := {}              # peer id -> bool
var enabled := true


func reset() -> void:
	strikes = {}
	_pos = {}
	_t = {}
	_grace = {}
	_bucket = {}
	_dmg = {}
	_last_down = {}


func forgive(id, secs: float = GRACE) -> void:
	if not str(id).is_valid_integer():
		return                                      # a bot: not checked
	var k := int(str(id))
	_grace[k] = OS.get_ticks_msec() + int(secs * 1000.0)


# Token bucket: false when this peer sends `what` more often than allowed.
func allow(id: int, what: String) -> bool:
	if not enabled:
		return true
	var now := OS.get_ticks_msec()
	var b: Dictionary = _bucket.get(id, {})
	var cap: float = LIMITS[what]
	var e: Array = b.get(what, [cap, now])
	var tokens: float = min(cap, e[0] + (now - e[1]) * 0.001 * cap)
	if tokens < 1.0:
		b[what] = [tokens, now]
		_bucket[id] = b
		return false
	b[what] = [tokens - 1.0, now]
	_bucket[id] = b
	return true


# Returns true when the peer should be thrown out.
func strike(id: int, why: String, amount: float = 1.0) -> bool:
	if not enabled:
		return false
	var now := OS.get_ticks_msec()
	var s: Array = strikes.get(id, [0.0, now])
	var score: float = max(0.0, s[0] - (now - s[1]) * 0.001 * 0.25) + amount      # decays by one every 4 s
	strikes[id] = [score, now]
	print("%s peer %d: %s (score %.1f)" % [log_prefix, id, why, score])
	if score >= KICK_STRIKES:
		kicked.append({"id": id, "why": why})
		return true
	return false


# A pose packet (see Fighter.net_pack). Returns "" if fine, else a reason.
func check_pose(id: int, a) -> String:
	if not enabled:
		return ""
	if typeof(a) != TYPE_ARRAY or a.size() < 17 or typeof(a[0]) != TYPE_VECTOR3 or typeof(a[4]) != TYPE_VECTOR3:
		return "malformed pose"
	var p: Vector3 = a[0]
	if is_nan(p.x) or is_nan(p.y) or is_nan(p.z) or abs(p.x) > 4000.0 or abs(p.z) > 4000.0 or p.y < -200.0 or p.y > 3000.0:
		return "pose out of bounds"
	if (typeof(a[10]) != TYPE_REAL and typeof(a[10]) != TYPE_INT) or a[10] > 100.5 or a[11] > 100.5:
		return "health above maximum"
	var now := OS.get_ticks_msec()
	var down := (int(a[5]) & 4096) != 0 or bool(a[12])
	if _last_down.get(id, false) and not down:
		_grace[id] = now + int(GRACE * 1000.0)          # got up (revive / reboot van moved them)
	_last_down[id] = down
	var why := ""
	if _pos.has(id) and now < _grace.get(id, 0):
		pass
	elif _pos.has(id):
		var dt: float = max(0.05, (now - _t[id]) * 0.001)
		var spd: float = _pos[id].distance_to(p) / dt
		if spd > MAX_SPEED and dt < 2.0 or _pos[id].distance_to(p) > MAX_SPEED * 2.0:
			why = "speed hack (%.0f m/s)" % spd
	_pos[id] = p
	_t[id] = now
	return why


func pos_of(id: int):
	return _pos.get(id)


# Damage a client claims it dealt. target_pos may be null (unknown). Returns "" if fine, else a reason.
func check_damage(id: int, source, amount, target_pos) -> String:
	if not enabled:
		return ""
	if str(source) != str(id):
		return "damage sent as somebody else"
	if typeof(amount) != TYPE_REAL and typeof(amount) != TYPE_INT:
		return "malformed damage"
	if is_nan(amount) or amount <= 0.0 or amount > MAX_HIT:
		return "damage %.0f per hit" % amount
	var now := OS.get_ticks_msec()
	var w: Array = _dmg.get(id, [0.0, now])
	if now - w[1] > 1000:
		w = [0.0, now]
	w[0] += amount
	_dmg[id] = w
	if w[0] > MAX_DPS:
		return "damage rate %.0f/s" % w[0]
	if target_pos != null and _pos.has(id) and _pos[id].distance_to(target_pos) > MAX_HIT_RANGE:
		return "hit from %.0f m away" % _pos[id].distance_to(target_pos)
	return ""


# Reliable events. Returns "" if fine, else a reason.
func check_event(id: int, kind: String, data) -> String:
	if not enabled:
		return ""
	if not allow(id, "event"):
		return "event flood"
	match kind:
		"shot":
			if not allow(id, "shot"):
				return "fire rate"
			if typeof(data) == TYPE_ARRAY and data.size() > 0 and str(data[0]) != str(id):
				return "shot for somebody else"
		"build":
			if not allow(id, "build"):
				return "build rate"
		"died":
			if typeof(data) == TYPE_ARRAY and data.size() > 0 and str(data[0]) != str(id):
				return "killed somebody remotely"
		"kill":
			# sent by the victim's machine to the killer's ("you were killed by ..."), or by the killer's machine for bots
			if typeof(data) == TYPE_ARRAY and data.size() > 1 and str(data[1]) != str(id) and str(data[0]) != str(id):
				return "kill credited to somebody else"
		"storm":
			return "host-only event"
	return ""

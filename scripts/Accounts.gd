extends Node
# Player accounts and career stats, saved on this device (user://accounts.json).
#
#   * A built-in GUEST profile always exists, so nothing is ever lost; creating an account claims the guest profile
#     (stats, loadout and name carry over) and signing out returns to a fresh guest.
#   * An account is an email + password (salted, iterated SHA-256; the password itself is never stored) with its own
#     display name, Locker loadout, starting sprite and stats. The last signed-in account stays signed in.
#   * Stats and level: matches, wins, top-3 finishes, eliminations, deaths, damage, headshots, chests, builds, play time,
#     best kills in a match, best placement, longest survival. XP gives the profile level shown in the lobby.
#
# Sync hook for a cloud backend (Convex, Google sign-in...): export_profile() / import_profile() move one account's
# data as a plain Dictionary, and the `saved` signal fires after every write. See docs/ACCOUNTS.md.

signal changed          # who is signed in, or their profile, changed
signal saved            # the file was written (a cloud sync can listen to this)

const VERSION := 1
const HASH_ROUNDS := 4000
const MIN_PASSWORD := 6

var path := "user://accounts.json"
var current_email := ""                 # "" = the guest profile
var _data := {}


func _ready() -> void:
	load_data()
	_adopt_legacy_settings()
	apply_to_settings()


# ------------------------------------------------------------------ data

static func new_profile() -> Dictionary:
	return {
		"name": "PLAYER",
		"loadout": {"skin": "ranger", "pickaxe": "classic", "backbling": "none", "contrail": "none", "glider": "classic"},
		"starter": "earth",
		"xp": 0,
		"stats": {"matches": 0, "wins": 0, "top3": 0, "elims": 0, "deaths": 0, "damage": 0, "headshots": 0, "chests": 0, "builds": 0,
			"playtime": 0, "best_kills": 0, "best_placement": 0, "longest_survival": 0},
	}


func load_data() -> void:
	_data = {"version": VERSION, "last": "", "guest": new_profile(), "accounts": {}}
	var f := File.new()
	if f.open(path, File.READ) == OK:
		var parsed = JSON.parse(f.get_as_text()).result
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			for k in ["last", "guest", "accounts"]:
				if parsed.has(k):
					_data[k] = parsed[k]
	_fill_defaults(_data.guest)
	for e in _data.accounts:
		_fill_defaults(_data.accounts[e].profile)
	current_email = ""
	var last: String = str(_data.get("last", ""))
	if last != "" and _data.accounts.has(last):
		current_email = last                      # stay signed in


func _fill_defaults(profile: Dictionary) -> void:
	var base := new_profile()
	for k in base:
		if not profile.has(k):
			profile[k] = base[k]
	for k in base.stats:
		if not profile.stats.has(k):
			profile.stats[k] = base.stats[k]
	for k in base.loadout:
		if not profile.loadout.has(k):
			profile.loadout[k] = base.loadout[k]


func save() -> void:
	_data["last"] = current_email
	var f := File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(JSON.print(_data, "  "))
		f.close()
	emit_signal("saved")


# The first run after accounts were introduced: the old settings.cfg stats and loadout become the guest profile.
func _adopt_legacy_settings() -> void:
	var settings = get_node_or_null("/root/Settings")
	if settings == null or _data.guest.stats.matches > 0 or _data.guest.xp > 0 or File.new().file_exists(path):
		return
	var g: Dictionary = _data.guest
	g.name = settings.player_name
	g.loadout = settings.loadout.duplicate()
	g.starter = settings.starter_sprite
	g.stats.matches = int(settings.get("matches"))
	g.stats.wins = int(settings.get("wins"))
	g.stats.elims = int(settings.get("elims"))
	g.xp = _xp_for(g.stats)
	save()


func profile() -> Dictionary:
	if current_email != "" and _data.accounts.has(current_email):
		return _data.accounts[current_email].profile
	return _data.guest


func is_guest() -> bool:
	return current_email == "" or not _data.accounts.has(current_email)


func display_name() -> String:
	return str(profile().name)


func email() -> String:
	return current_email


func stat(key: String) -> int:
	return int(profile().stats.get(key, 0))


# ------------------------------------------------------------------ settings <-> profile

# Make the signed-in profile's name, loadout and starting sprite the live settings.
func apply_to_settings() -> void:
	var settings = get_node_or_null("/root/Settings")
	if settings == null:
		return
	var p := profile()
	settings.player_name = str(p.name)
	for c in settings.loadout.keys():
		settings.loadout[c] = str(p.loadout.get(c, settings.loadout[c]))
	settings.starter_sprite = str(p.starter)
	emit_signal("changed")


# Called whenever the settings are saved: the name, loadout and starter belong to the profile.
func capture_from_settings() -> void:
	var settings = get_node_or_null("/root/Settings")
	if settings == null:
		return
	var p := profile()
	p.name = settings.player_name
	p.loadout = settings.loadout.duplicate()
	p.starter = settings.starter_sprite
	save()


# ------------------------------------------------------------------ accounts

static func normalize_email(e: String) -> String:
	return e.strip_edges().to_lower()


static func valid_email(e: String) -> bool:
	var s := normalize_email(e)
	var at := s.find("@")
	return s.length() >= 5 and at > 0 and s.find("@", at + 1) < 0 and s.find(".", at) > at + 1 and not s.ends_with(".") and s.find(" ") < 0


static func _hash(password: String, salt: String) -> String:
	var h := (salt + password).sha256_text()
	for i in range(HASH_ROUNDS):
		h = (h + salt + password).sha256_text()
	return h


static func _salt() -> String:
	var c := Crypto.new()
	return c.generate_random_bytes(16).hex_encode()


# Create an account. The guest profile (stats, loadout) moves into it. Returns "" or an error message.
func create_account(email_in: String, password: String, name_in: String = "") -> String:
	var e := normalize_email(email_in)
	if not valid_email(e):
		return "Enter a valid email address."
	if password.length() < MIN_PASSWORD:
		return "Use a password of at least %d characters." % MIN_PASSWORD
	if _data.accounts.has(e):
		return "An account with that email already exists."
	var prof: Dictionary = _data.guest.duplicate(true)
	var nm := name_in.strip_edges().to_upper()
	if nm.length() >= 2:
		prof.name = nm.substr(0, 14)
	elif str(prof.name) == "PLAYER":
		prof.name = e.split("@")[0].to_upper().substr(0, 14)
	var salt := _salt()
	_data.accounts[e] = {"email": e, "salt": salt, "hash": _hash(password, salt), "created": OS.get_unix_time(), "profile": prof}
	_data.guest = new_profile()
	current_email = e
	save()
	apply_to_settings()
	return ""


func sign_in(email_in: String, password: String) -> String:
	var e := normalize_email(email_in)
	if not _data.accounts.has(e):
		return "No account with that email."
	var acc: Dictionary = _data.accounts[e]
	if _hash(password, str(acc.salt)) != str(acc.hash):
		return "Wrong password."
	current_email = e
	save()
	apply_to_settings()
	return ""


func sign_out() -> void:
	capture_from_settings()
	current_email = ""
	save()
	apply_to_settings()


func change_password(old_pw: String, new_pw: String) -> String:
	if is_guest():
		return "Sign in first."
	var acc: Dictionary = _data.accounts[current_email]
	if _hash(old_pw, str(acc.salt)) != str(acc.hash):
		return "Wrong password."
	if new_pw.length() < MIN_PASSWORD:
		return "Use a password of at least %d characters." % MIN_PASSWORD
	acc.salt = _salt()
	acc.hash = _hash(new_pw, str(acc.salt))
	save()
	return ""


func delete_account(password: String) -> String:
	if is_guest():
		return "Sign in first."
	var acc: Dictionary = _data.accounts[current_email]
	if _hash(password, str(acc.salt)) != str(acc.hash):
		return "Wrong password."
	_data.accounts.erase(current_email)
	current_email = ""
	save()
	apply_to_settings()
	return ""


func account_count() -> int:
	return _data.accounts.size()


# ------------------------------------------------------------------ stats

static func _xp_for(stats: Dictionary) -> int:
	return int(stats.matches) * 25 + int(stats.elims) * 20 + int(stats.wins) * 150 + int(stats.top3) * 40


# info: {victory, placement, kills, damage, headshots, chests, builds, survival (seconds)}
func record_match(info: Dictionary) -> void:
	var p := profile()
	var s: Dictionary = p.stats
	var kills := int(info.get("kills", 0))
	var place := int(info.get("placement", 0))
	var survival := int(info.get("survival", 0))
	s.matches += 1
	s.elims += kills
	if info.get("victory", false):
		s.wins += 1
	else:
		s.deaths += 1
	if place > 0 and place <= 3:
		s.top3 += 1
	s.damage += int(info.get("damage", 0))
	s.headshots += int(info.get("headshots", 0))
	s.chests += int(info.get("chests", 0))
	s.builds += int(info.get("builds", 0))
	s.playtime += survival
	s.best_kills = int(max(s.best_kills, kills))
	if place > 0 and (s.best_placement == 0 or place < s.best_placement):
		s.best_placement = place
	s.longest_survival = int(max(s.longest_survival, survival))
	var gained: int = 25 + kills * 20 + (150 if info.get("victory", false) else 0) + (40 if place > 0 and place <= 3 else 0) + int(survival / 20)
	p.xp += gained
	save()
	emit_signal("changed")


func level() -> int:
	return 1 + int(sqrt(float(profile().xp) / 120.0))


# [xp into this level, xp the level needs]
func level_progress() -> Array:
	var l := level()
	var base := int(pow(l - 1, 2) * 120.0)
	var nxt := int(pow(l, 2) * 120.0)
	return [int(profile().xp) - base, nxt - base]


func win_rate() -> float:
	var m := stat("matches")
	return float(stat("wins")) / float(m) if m > 0 else 0.0


func kd() -> float:
	var d := stat("deaths")
	return float(stat("elims")) / float(max(d, 1))


# ------------------------------------------------------------------ cloud hooks

func export_profile() -> Dictionary:
	return {"email": current_email, "profile": profile().duplicate(true)}


func import_profile(d: Dictionary) -> void:
	if d.has("profile"):
		var p := profile()
		for k in d.profile:
			p[k] = d.profile[k]
		_fill_defaults(p)
		save()
		apply_to_settings()

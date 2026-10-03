extends Node
# Persistent user settings (autoload). Stored in user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.9
var look_sensitivity := 1.0       # multiplier on the base mouse / touch sensitivity
var invert_y := false
var quality := 1                  # 0 low, 1 medium, 2 high (picked by platform on first run)
var show_fps := false
var auto_graphics := true          # lower the graphics by itself when the game runs slowly (Perf.gd)
var player_name := "PLAYER"
var matches := 0                  # career stats shown on the lobby card
var wins := 0
var elims := 0
var aim_toggle := false           # tap to aim instead of hold
var loadout := {"skin": "ranger", "pickaxe": "classic", "backbling": "none", "contrail": "none", "glider": "classic"}     # the Locker
var starter_sprite := "earth"    # the sprite you bring to a match (none / earth / fire / water)
var damage_numbers := true
var edit_on_release := false     # builds: false = press Edit once to start and again to confirm; true = hold it and let go to confirm
var team_size := 1                 # 1 solo, 2 duos, 3 trios, 4 squads
var friends := []                  # [{name, ip}] saved LAN friends
var recent := []                   # [{name, ip}] people you played with lately (newest first)
var emote_wheel := []              # emote ids on the wheel, in order (Locker > Emotes); sanitised in Emotes.sanitize_wheel
var last_emote := "boogie"
var padbinds := {}                # action -> controller button (-1 = none); only the ones the player changed
var keybinds := {}                # action -> [[type, code], ...]; only the actions the player changed
var autostart := false            # runtime only: skip the title screen after "Play again"


func _ready() -> void:
	quality = 0 if OS.has_feature("mobile") else 1
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	look_sensitivity = float(cfg.get_value("controls", "sensitivity", look_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	quality = int(cfg.get_value("graphics", "quality", quality))
	show_fps = bool(cfg.get_value("graphics", "show_fps", show_fps))
	auto_graphics = bool(cfg.get_value("graphics", "auto", auto_graphics))
	aim_toggle = bool(cfg.get_value("gameplay", "aim_toggle", aim_toggle))
	starter_sprite = str(cfg.get_value("gameplay", "starter_sprite", starter_sprite))
	for c in loadout.keys():
		loadout[c] = str(cfg.get_value("loadout", c, loadout[c]))
	damage_numbers = bool(cfg.get_value("gameplay", "damage_numbers", damage_numbers))
	edit_on_release = bool(cfg.get_value("gameplay", "edit_hold_to_confirm", edit_on_release))
	if cfg.has_section("keybinds"):
		for action in cfg.get_section_keys("keybinds"):
			keybinds[action] = cfg.get_value("keybinds", action, [])
	team_size = int(clamp(int(cfg.get_value("gameplay", "team_size", team_size)), 1, 4))
	friends = cfg.get_value("social", "friends", [])
	recent = cfg.get_value("social", "recent", [])
	emote_wheel = Array(str(cfg.get_value("gameplay", "emote_wheel", "")).split(",", false))
	last_emote = str(cfg.get_value("gameplay", "last_emote", last_emote))
	if cfg.has_section("padbinds"):
		for action in cfg.get_section_keys("padbinds"):
			padbinds[action] = int(cfg.get_value("padbinds", action, -1))
	player_name = str(cfg.get_value("profile", "name", player_name))
	matches = int(cfg.get_value("profile", "matches", matches))
	wins = int(cfg.get_value("profile", "wins", wins))
	elims = int(cfg.get_value("profile", "elims", elims))


func is_friend(ip: String, friend_name: String = "") -> bool:
	for f in friends:
		if f.ip == ip or (friend_name != "" and str(f.name).to_lower() == friend_name.to_lower()):
			return true
	return false


func add_friend(friend_name: String, ip: String) -> void:
	ip = ip.strip_edges()
	friend_name = friend_name.strip_edges().substr(0, 14)
	if ip == "" or is_friend(ip):
		return
	friends.append({"name": friend_name if friend_name != "" else ip, "ip": ip})
	save_settings()


func remove_friend(ip: String) -> void:
	for i in range(friends.size()):
		if friends[i].ip == ip:
			friends.remove(i)
			break
	save_settings()


# Remember who you played with (shown under Friends > Recent players).
func add_recent(player_name: String, ip: String) -> void:
	if ip == "" or ip == "127.0.0.1":
		return
	for i in range(recent.size()):
		if recent[i].ip == ip:
			recent.remove(i)
			break
	recent.push_front({"name": player_name, "ip": ip})
	while recent.size() > 8:
		recent.pop_back()
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "sensitivity", look_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("graphics", "auto", auto_graphics)
	cfg.set_value("gameplay", "aim_toggle", aim_toggle)
	cfg.set_value("gameplay", "starter_sprite", starter_sprite)
	for c in loadout.keys():
		cfg.set_value("loadout", c, loadout[c])
	cfg.set_value("gameplay", "damage_numbers", damage_numbers)
	cfg.set_value("gameplay", "edit_hold_to_confirm", edit_on_release)
	for action in keybinds:
		cfg.set_value("keybinds", action, keybinds[action])
	cfg.set_value("gameplay", "team_size", team_size)
	cfg.set_value("social", "friends", friends)
	cfg.set_value("social", "recent", recent)
	cfg.set_value("gameplay", "emote_wheel", PoolStringArray(emote_wheel).join(","))
	cfg.set_value("gameplay", "last_emote", last_emote)
	for action in padbinds:
		cfg.set_value("padbinds", action, padbinds[action])
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "matches", matches)
	cfg.set_value("profile", "wins", wins)
	cfg.set_value("profile", "elims", elims)
	cfg.save(PATH)
	var acc = get_node_or_null("/root/Accounts")
	if acc != null:
		acc.capture_from_settings()                  # name, loadout and starter sprite belong to the signed-in profile
	emit_signal("changed")


func record_match(victory: bool, kills: int) -> void:      # legacy: stats now live on the account (Accounts.gd)
	var acc = get_node_or_null("/root/Accounts")
	if acc != null:
		acc.record_match({"victory": victory, "kills": kills})

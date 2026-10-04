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
var zero_build := false            # Zero Build: no building pieces, only the weapons, the terrain and the buildings that stand
var friends := []                  # [{name, ip}] saved LAN friends
var recent := []                   # [{name, ip}] people you played with lately (newest first)
var emote_wheel := []              # emote ids on the wheel, in order (Locker > Emotes); sanitised in Emotes.sanitize_wheel
var last_emote := "boogie"
# Display / comfort options (Settings > DISPLAY and COMFORT). Every key here is saved automatically under [prefs].
const PREF_DEFAULTS := {
	"toggle_sprint": false,       # tap Sprint to start running, again (or stop moving) to stop
	"toggle_crouch": false,       # tap Crouch to stay down
	"fov": 72.0,                  # field of view in degrees
	"ads_sens": 1.0,              # extra sensitivity multiplier while aiming down sights
	"crosshair_color": 0,         # index into CROSSHAIR_COLORS
	"crosshair_size": 1.0,
	"fps_cap": 0,                 # frames per second limit, 0 = none
	"vsync": true,
	"minimap_rotate": false,      # the minimap turns with you
	"pause_on_focus": true,       # pause when the window loses focus
	"vibration": true,            # controller rumble
	"show_hints": true,           # the control hint line at the bottom
	"touch_scale": 1.0,           # size of the on-screen buttons
	"master_volume": 1.0,
	"warn_health": true,          # red pulse at the screen edges when health is low
	"warn_ammo": true,            # RELOAD / NO AMMO warning
	"visual_sound": false,        # accessibility: icons on a ring round the reticle for footsteps, gunfire, chests, cars
	"turbo_build": true,          # hold fire in build mode to keep placing pieces
	"colorblind": 0,              # 0 off, 1 protanopia, 2 deuteranopia, 3 tritanopia (ColorFilter.gd)
	"colorblind_strength": 1.0,
	"weather": true,              # rain storms (cosmetic)
	"hud_scale": 1.0,             # size of the HUD
	"touch_auto_fire": false,     # phones: shoot automatically while an enemy is in the crosshair
}
const CROSSHAIR_COLORS := [Color(1, 1, 1), Color(0.35, 1.0, 0.45), Color(1.0, 0.3, 0.3), Color(0.35, 0.9, 1.0), Color(1.0, 0.9, 0.3)]
const FPS_CAPS := [0, 30, 60, 120, 144]
var prefs := PREF_DEFAULTS.duplicate()
var padbinds := {}                # action -> controller button (-1 = none); only the ones the player changed
var keybinds := {}                # action -> [[type, code], ...]; only the actions the player changed
var server_addr := ""             # the online server: "host", "host:7777" or "host:7777+4" (4 server instances on consecutive ports)
var autostart := false            # runtime only: skip the title screen after "Play again"


var filter                        # the colour-blind ColorFilter layer


func _ready() -> void:
	quality = 0 if OS.has_feature("mobile") else 1
	load_settings()
	filter = load("res://scripts/ColorFilter.gd").new()
	add_child(filter)
	apply_display()


# The online server clients connect to: what the player typed, else the one baked into the build (res://server.cfg).
func server_endpoint() -> Dictionary:
	var text := server_addr.strip_edges()
	if text == "":
		var cfg := ConfigFile.new()
		if cfg.load("res://server.cfg") == OK:
			text = str(cfg.get_value("server", "addr", "")).strip_edges()
	if text == "":
		return {}
	var count := 1
	var port := 7777
	if "+" in text:
		var pc := text.split("+")
		count = int(max(1, int(pc[1])))
		text = pc[0]
	if ":" in text:
		var hp := text.split(":")
		text = hp[0]
		port = int(hp[1])
	return {"host": text, "port": port, "count": count}


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
	zero_build = bool(cfg.get_value("gameplay", "zero_build", zero_build))
	friends = cfg.get_value("social", "friends", [])
	recent = cfg.get_value("social", "recent", [])
	emote_wheel = Array(str(cfg.get_value("gameplay", "emote_wheel", "")).split(",", false))
	last_emote = str(cfg.get_value("gameplay", "last_emote", last_emote))
	if cfg.has_section("prefs"):
		for k in PREF_DEFAULTS:
			if cfg.has_section_key("prefs", k):
				var v = cfg.get_value("prefs", k, PREF_DEFAULTS[k])
				prefs[k] = type_convert_pref(PREF_DEFAULTS[k], v)
	if cfg.has_section("padbinds"):
		for action in cfg.get_section_keys("padbinds"):
			padbinds[action] = int(cfg.get_value("padbinds", action, -1))
	server_addr = str(cfg.get_value("online", "server", server_addr))
	player_name = str(cfg.get_value("profile", "name", player_name))
	matches = int(cfg.get_value("profile", "matches", matches))
	wins = int(cfg.get_value("profile", "wins", wins))
	elims = int(cfg.get_value("profile", "elims", elims))


func type_convert_pref(default, v):
	match typeof(default):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v)
		TYPE_REAL:
			return float(v)
	return v


func pref(key: String):
	return prefs.get(key, PREF_DEFAULTS.get(key))


# Change an option, save it and apply whatever needs applying right away.
func set_pref(key: String, value) -> void:
	prefs[key] = type_convert_pref(PREF_DEFAULTS[key], value)
	save_settings()
	apply_display()
	emit_signal("changed")


func reset_prefs() -> void:
	prefs = PREF_DEFAULTS.duplicate()
	save_settings()
	apply_display()
	emit_signal("changed")


func crosshair_color() -> Color:
	return CROSSHAIR_COLORS[int(clamp(int(prefs.crosshair_color), 0, CROSSHAIR_COLORS.size() - 1))]


# Frame limit, vertical sync and the master volume.
func apply_display() -> void:
	Engine.target_fps = int(prefs.fps_cap)
	OS.vsync_enabled = bool(prefs.vsync)
	AudioServer.set_bus_volume_db(0, linear2db(max(float(prefs.master_volume), 0.0001)))
	if filter != null:
		filter.apply()


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
	cfg.set_value("gameplay", "zero_build", zero_build)
	cfg.set_value("social", "friends", friends)
	cfg.set_value("social", "recent", recent)
	cfg.set_value("gameplay", "emote_wheel", PoolStringArray(emote_wheel).join(","))
	cfg.set_value("gameplay", "last_emote", last_emote)
	for k in prefs:
		cfg.set_value("prefs", k, prefs[k])
	for action in padbinds:
		cfg.set_value("padbinds", action, padbinds[action])
	cfg.set_value("online", "server", server_addr)
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

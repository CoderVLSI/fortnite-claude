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
var player_name := "PLAYER"
var matches := 0                  # career stats shown on the lobby card
var wins := 0
var elims := 0
var aim_toggle := false           # tap to aim instead of hold
var skin := "ranger"             # the character skin chosen in the lobby
var starter_sprite := "earth"    # the sprite you bring to a match (none / earth / fire / water)
var damage_numbers := true
var edit_on_release := true      # builds: confirm an edit when the Edit key is let go (Fortnite style)
var keybinds := {}                # action -> [[type, code], ...]; only the actions the player changed
var autostart := false            # runtime only: skip the title screen after "Play again"


func _ready() -> void:
	quality = 0 if OS.has_feature("mobile") else 2
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
	aim_toggle = bool(cfg.get_value("gameplay", "aim_toggle", aim_toggle))
	starter_sprite = str(cfg.get_value("gameplay", "starter_sprite", starter_sprite))
	skin = str(cfg.get_value("player", "skin", skin))
	damage_numbers = bool(cfg.get_value("gameplay", "damage_numbers", damage_numbers))
	edit_on_release = bool(cfg.get_value("gameplay", "edit_on_release", edit_on_release))
	if cfg.has_section("keybinds"):
		for action in cfg.get_section_keys("keybinds"):
			keybinds[action] = cfg.get_value("keybinds", action, [])
	player_name = str(cfg.get_value("profile", "name", player_name))
	matches = int(cfg.get_value("profile", "matches", matches))
	wins = int(cfg.get_value("profile", "wins", wins))
	elims = int(cfg.get_value("profile", "elims", elims))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "sensitivity", look_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("gameplay", "aim_toggle", aim_toggle)
	cfg.set_value("gameplay", "starter_sprite", starter_sprite)
	cfg.set_value("player", "skin", skin)
	cfg.set_value("gameplay", "damage_numbers", damage_numbers)
	cfg.set_value("gameplay", "edit_on_release", edit_on_release)
	for action in keybinds:
		cfg.set_value("keybinds", action, keybinds[action])
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "matches", matches)
	cfg.set_value("profile", "wins", wins)
	cfg.set_value("profile", "elims", elims)
	cfg.save(PATH)
	emit_signal("changed")


func record_match(victory: bool, kills: int) -> void:
	matches += 1
	elims += kills
	if victory:
		wins += 1
	save_settings()

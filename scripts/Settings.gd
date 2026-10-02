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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "sensitivity", look_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.save(PATH)
	emit_signal("changed")

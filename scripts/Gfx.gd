extends Node
# Graphics style: "OG Pixel Mode" (the original blocky look, assets in res://assets/models) or "HD Mode" (Sketchfab models in
# res://hd/models). The HD folder mirrors the pixel one by file name: any model that exists there is used in HD mode, anything missing
# falls back to the pixel version, so HD assets can be added one by one. Credits for the HD models: docs/CREDITS_HD.md.

const PIXEL_DIR := "res://assets/models/"
const HD_DIR := "res://hd/models/"


static func _tree_root():
	return Engine.get_main_loop().root


# Cache of "does this HD file exist" lookups, kept in the Engine so the functions below can be static (scripts that preload
# this one, such as Items.gd, then compile without the autoload being registered yet).
static func _cache() -> Dictionary:
	if not Engine.has_meta("gfx_exists"):
		Engine.set_meta("gfx_exists", {})
	return Engine.get_meta("gfx_exists")


static func is_hd() -> bool:
	var st = _tree_root().get_node_or_null("Settings")
	return st != null and int(st.pref("graphics_mode")) == 1


# The file to load for `path` (a res://assets/models/*.glb path) in the current style.
static func model_path(path: String) -> String:
	if not is_hd() or not path.begins_with(PIXEL_DIR):
		return path
	var hd: String = HD_DIR + path.substr(PIXEL_DIR.length())
	var c := _cache()
	if not c.has(hd):
		c[hd] = ResourceLoader.exists(hd)
	return hd if c[hd] else path


static func load_model(path: String):
	return load(model_path(path))


# Does this model have an HD version (and is HD on)?
static func has_hd(path: String) -> bool:
	return is_hd() and model_path(path) != path


static func style_name() -> String:
	return "HD Mode" if is_hd() else "OG Pixel Mode"


# HD Mode character for a skin id (res://hd/models/skin_<id>.glb), or "" when that skin has no HD model (it then stays pixel).
static func skin_path(skin_id: String) -> String:
	if not is_hd():
		return ""
	var p: String = HD_DIR + "skin_%s.glb" % skin_id
	var c := _cache()
	if not c.has(p):
		c[p] = ResourceLoader.exists(p)
	return p if c[p] else ""

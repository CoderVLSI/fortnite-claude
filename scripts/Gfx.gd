extends Node
# Graphics style: "OG Pixel Mode" (the original blocky look, assets in res://assets/models) or "HD Mode" (Sketchfab models in
# res://hd/models). The HD folder mirrors the pixel one by file name: any model that exists there is used in HD mode, anything missing
# falls back to the pixel version, so HD assets can be added one by one. Credits for the HD models: docs/CREDITS_HD.md.

const PIXEL_DIR := "res://assets/models/"
const HD_DIR := "res://hd/models/"

var _exists := {}


func is_hd() -> bool:
	return int(Settings.pref("graphics_mode")) == 1


# The file to load for `path` (a res://assets/models/*.glb path) in the current style.
func model_path(path: String) -> String:
	if not is_hd() or not path.begins_with(PIXEL_DIR):
		return path
	var hd: String = HD_DIR + path.substr(PIXEL_DIR.length())
	if not _exists.has(hd):
		_exists[hd] = ResourceLoader.exists(hd)
	return hd if _exists[hd] else path


func load_model(path: String):
	return load(model_path(path))


# Does this model have an HD version (and is HD on)?
func has_hd(path: String) -> bool:
	return is_hd() and model_path(path) != path


func style_name() -> String:
	return "HD Mode" if is_hd() else "OG Pixel Mode"

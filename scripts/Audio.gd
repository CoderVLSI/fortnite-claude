extends Node
# Sound manager (autoload): SFX and Music buses, pooled positional players, 2D one-shots,
# named looping ambients and crossfading music. Streams are the synthesised WAVs in
# assets/audio (tools/audio/generate_audio.py) and are loaded lazily.
#
#   Audio.play3d("shot_rifle", position, -3.0)     positional one-shot
#   Audio.play2d("hitmarker")                      UI / player-centred one-shot
#   Audio.ambient("storm_loop", -12.0)             start/adjust a looping 2D sound
#   Audio.music("music_bus", 1.5)                  crossfade to a music track

const DIR := "res://assets/audio/"
const POOL_3D := 24
const POOL_2D := 10
const SILENT_DB := -60.0

var stats := {}                   # sound name -> times played (tests assert on this)
var muted := false

var _cache := {}
var _pool3d := []
var _pool2d := []
var _next3d := 0
var _next2d := 0
var _ambients := {}               # name -> AudioStreamPlayer
var _music_players := []
var _music_idx := 0
var _music_name := ""
var _music_fade := 0.0
var _music_time := 0.0
var _music_loop := true


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_setup_buses()
	for i in range(POOL_3D):
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 9.0
		p.max_distance = 230.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	for i in range(POOL_2D):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in range(2):
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = SILENT_DB
		add_child(m)
		_music_players.append(m)
	Settings.connect("changed", self, "apply_volumes")
	apply_volumes()


func _setup_buses() -> void:
	for name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear2db(max(Settings.sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear2db(max(Settings.music_volume, 0.0001)))


func _stream(name: String):
	if _cache.has(name):
		return _cache[name]
	var st = load(DIR + name + ".wav") if ResourceLoader.exists(DIR + name + ".wav") else null     # new sounds may not exist yet: stay silent
	if st != null and (name.ends_with("_loop") or (name.begins_with("music_") and not name.ends_with("victory") and not name.ends_with("defeat"))):
		st.loop_mode = AudioStreamSample.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = _sample_count(st)
	_cache[name] = st
	return st


# Number of sample frames in an imported stream (PCM 8/16-bit or IMA-ADPCM, mono or stereo).
func _sample_count(st: AudioStreamSample) -> int:
	var bytes: int = st.data.size()
	var frames: int = bytes
	match st.format:
		AudioStreamSample.FORMAT_16_BITS:
			frames = bytes / 2
		AudioStreamSample.FORMAT_IMA_ADPCM:
			frames = bytes * 2
	return frames / (2 if st.stereo else 1)


func _count(name: String) -> void:
	stats[name] = stats.get(name, 0) + 1


func count_of(name: String) -> int:
	return stats.get(name, 0)


func play3d(name: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	_count(name)
	var st = _stream(name)
	if st == null or muted:
		return
	var p: AudioStreamPlayer3D = _pool3d[_next3d]
	_next3d = (_next3d + 1) % POOL_3D
	p.stream = st
	p.unit_db = db
	p.pitch_scale = pitch
	p.global_transform = Transform(Basis(), pos)
	p.play()


func play2d(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
	_count(name)
	var st = _stream(name)
	if st == null or muted:
		return
	var p: AudioStreamPlayer = _pool2d[_next2d]
	_next2d = (_next2d + 1) % POOL_2D
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


# Looping 2D sound that stays alive; call again to change the level. db <= SILENT_DB pauses it.
func ambient(name: String, db: float, pitch: float = 1.0) -> void:
	var p = _ambients.get(name)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = _stream(name)
		p.volume_db = SILENT_DB
		add_child(p)
		_ambients[name] = p
		_count(name)
	if p.stream == null:
		return
	p.volume_db = db
	p.pitch_scale = pitch
	if db <= SILENT_DB + 1.0:
		if p.playing:
			p.stop()
	elif not p.playing:
		p.play()


func stop_ambient(name: String) -> void:
	ambient(name, SILENT_DB)


func set_paused(on: bool) -> void:
	for p in _pool3d + _pool2d + _ambients.values():
		p.stream_paused = on


func stop_all_ambients() -> void:
	for n in _ambients.keys():
		stop_ambient(n)


# A looping positional player owned by the caller (vehicle engines, the bus).
func make_loop3d(name: String, parent: Node, db: float = 0.0, max_dist: float = 160.0) -> AudioStreamPlayer3D:
	_count(name)
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = _stream(name)
	p.unit_db = db
	p.unit_size = 10.0
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	if p.stream != null and not muted:
		p.play()
	return p


# ------------------------------------------------------------------ music

func music(name: String, fade: float = 1.5) -> void:
	if name == _music_name:
		return
	_music_name = name
	_count("music:" + name)
	var old: AudioStreamPlayer = _music_players[_music_idx]
	_music_idx = 1 - _music_idx
	var nw: AudioStreamPlayer = _music_players[_music_idx]
	_music_loop = not (name.ends_with("victory") or name.ends_with("defeat"))
	nw.stream = _stream(name)
	nw.volume_db = SILENT_DB if fade > 0.0 else 0.0
	if nw.stream != null and not muted:
		nw.play()
	_music_fade = max(fade, 0.001)
	_music_time = 0.0
	if old.playing and fade <= 0.0:
		old.stop()


func stop_music(fade: float = 1.0) -> void:
	_music_name = ""
	_music_fade = max(fade, 0.001)
	_music_time = 0.0
	_music_idx = 1 - _music_idx          # nothing fades in; the current track fades out
	_music_players[_music_idx].stop()


func current_music() -> String:
	return _music_name


func _process(delta: float) -> void:
	if _music_time < _music_fade:
		_music_time += delta
		var k: float = clamp(_music_time / _music_fade, 0.0, 1.0)
		var nw: AudioStreamPlayer = _music_players[_music_idx]
		var old: AudioStreamPlayer = _music_players[1 - _music_idx]
		if _music_name != "":
			nw.volume_db = lerp(SILENT_DB, 0.0, k)
		old.volume_db = lerp(old.volume_db, SILENT_DB, k)
		if k >= 1.0 and old.playing:
			old.stop()


# Distance from the active camera, for deciding whether a sound is worth playing.
func listener_distance(pos: Vector3) -> float:
	var cam := get_viewport().get_camera()
	return cam.global_transform.origin.distance_to(pos) if cam != null else 0.0

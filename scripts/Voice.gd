extends Node
# Voice chat. The microphone is captured on a muted bus (AudioEffectCapture), turned into 16 kHz mono, squeezed to one byte per
# sample with a mu-law style curve (about 16 kB/s while you talk), and sent in 40 ms packets through Net (unreliable, relayed by the
# host / server). Everybody else plays it through an AudioStreamGenerator: your team-mates are heard at full volume anywhere, the
# others positionally from the speaker's character (about 40 m). Push to talk (default N) or open mic (Settings > Comfort).

signal speakers_changed

const RATE := 16000
const CHUNK := 640                  # samples per packet = 40 ms
const MAX_HEAR := 45.0              # metres for non-team voices
const PREBUFFER := 0.08             # seconds queued before playback starts (hides jitter)
const MAX_QUEUE := 0.45             # more than this waiting = we are behind: drop
const OPEN_THRESHOLD := 0.015       # open mic: RMS that counts as speech
const HANG := 0.5                   # open mic: keep sending this long after the speech stops

var mic_ready := false
var mic_error := ""
var talking := false                # we are transmitting right now
var touch_talk := false             # the on-screen MIC button is held
var level := 0.0                    # our microphone level 0..1 (for the HUD)
var speakers := {}                  # peer id -> {gen, player, last, level, name, packets}
var sent_packets := 0
var inject_only := false            # tests: no real microphone, samples come from transmit_samples()

var _capture: AudioEffectCapture
var _bus := -1
var _mic: AudioStreamPlayer
var _pending := PoolRealArray()     # 16 kHz samples waiting for a full packet
var _pos := 0.0                     # fractional read position into the incoming block
var _carry := PoolRealArray()       # input samples left over from the last block
var _hang := 0.0
var _seq := 0


# ------------------------------------------------------------------ codec (also used by the tests)

static func encode(samples: PoolRealArray) -> PoolByteArray:
	var out := PoolByteArray()
	out.resize(samples.size())
	for i in range(samples.size()):
		var x: float = clamp(samples[i], -1.0, 1.0)
		var y: float = sign(x) * log(1.0 + 255.0 * abs(x)) / log(256.0)
		out[i] = int(clamp((y + 1.0) * 127.5, 0.0, 255.0))
	return out


static func decode(bytes: PoolByteArray) -> PoolRealArray:
	var out := PoolRealArray()
	out.resize(bytes.size())
	for i in range(bytes.size()):
		var y: float = float(bytes[i]) / 127.5 - 1.0
		out[i] = sign(y) * (pow(256.0, abs(y)) - 1.0) / 255.0
	return out


# arr[from:to] (PoolRealArray has no subarray in Godot 3.5)
static func _slice(arr: PoolRealArray, from: int, to: int = -1) -> PoolRealArray:
	if to < 0 or to > arr.size():
		to = arr.size()
	var out := PoolRealArray()
	if from >= to:
		return out
	out.resize(to - from)
	for i in range(from, to):
		out[i - from] = arr[i]
	return out


static func rms(samples: PoolRealArray) -> float:
	if samples.size() == 0:
		return 0.0
	var s := 0.0
	for v in samples:
		s += v * v
	return sqrt(s / float(samples.size()))


# ------------------------------------------------------------------ microphone

func _ready() -> void:
	set_process(true)


func mode() -> int:
	return int(Settings.pref("voice_mode"))        # 0 push to talk, 1 open mic, 2 off


func _in_match() -> bool:
	return Net.active and Net.in_match and not Net.dedicated


# Start capturing (first use). On Android this asks for the microphone permission.
func ensure_mic() -> bool:
	if mic_ready:
		return true
	if inject_only:
		return false
	if OS.get_name() == "Android" and not ("RECORD_AUDIO" in OS.get_granted_permissions()):
		OS.request_permission("RECORD_AUDIO")
		mic_error = "Allow the microphone, then try again"
		return false
	if not ProjectSettings.get_setting("audio/enable_audio_input"):
		mic_error = "Audio input is disabled in this build"
		return false
	_bus = AudioServer.get_bus_index("VoiceMic")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "VoiceMic")
		AudioServer.set_bus_mute(_bus, true)                 # never play our own microphone back
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(_bus, _capture)
	else:
		_capture = AudioServer.get_bus_effect(_bus, 0)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "VoiceMic"
	add_child(_mic)
	_mic.play()
	mic_ready = true
	mic_error = ""
	return true


func _wants_to_talk() -> bool:
	var m := mode()
	if m == 2 or not _in_match():
		return false
	if m == 0:
		return Input.is_action_pressed("voice") or touch_talk
	return true                                              # open mic: the level gate decides


func _process(delta: float) -> void:
	_prune_speakers()
	if not _in_match() or mode() == 2:
		if talking:
			talking = false
		level = 0.0
		return
	var want := _wants_to_talk()
	if want and not mic_ready:
		ensure_mic()
	if mic_ready and _capture != null:
		var frames := _capture.get_frames_available()
		if frames > 0:
			var block := _capture.get_buffer(frames)
			_ingest(block, want)
	elif not want:
		level = 0.0
	if mode() == 0:
		talking = want and mic_ready
	# open mic: `talking` is decided in _ingest from the level


# Real microphone samples (stereo frames at the mix rate) -> 16 kHz mono -> packets.
func _ingest(block: PoolVector2Array, want: bool) -> void:
	var ratio: float = AudioServer.get_mix_rate() / float(RATE)
	var mono := _carry
	for v in block:
		mono.append((v.x + v.y) * 0.5)
	var out := PoolRealArray()
	var pos := _pos
	while pos + 1.0 < float(mono.size()):
		var i := int(pos)
		var f := pos - float(i)
		out.append(lerp(mono[i], mono[i + 1], f))
		pos += ratio
	var used := int(pos)
	_carry = _slice(mono, used)
	_pos = pos - float(used)
	level = lerp(level, min(1.0, rms(out) * 6.0), 0.5)
	if mode() == 1:
		if rms(out) > OPEN_THRESHOLD:
			_hang = HANG
		else:
			_hang = max(0.0, _hang - float(out.size()) / float(RATE))
		talking = _hang > 0.0
	if talking:
		transmit_samples(out)
	else:
		_pending = PoolRealArray()


# 16 kHz mono floats -> packets. (Also the entry point for tests with synthetic audio.)
func transmit_samples(samples: PoolRealArray) -> void:
	_pending.append_array(samples)
	while _pending.size() >= CHUNK:
		var chunk := _slice(_pending, 0, CHUNK)
		_pending = _slice(_pending, CHUNK)
		_seq = (_seq + 1) & 0xffff
		sent_packets += 1
		Net.send_voice(encode(chunk), _seq)


# ------------------------------------------------------------------ playback

# A packet from peer `from` arrived (Net validated it).
func receive(from: int, bytes: PoolByteArray, seq: int) -> void:
	if mode() == 2 or Net.dedicated:
		return
	var world = get_tree().current_scene
	var f = world.fighter_by_key(from) if world != null and world.has_method("fighter_by_key") else null
	var sp: Dictionary = speakers.get(from, {})
	if sp.empty() or not is_instance_valid(sp.player) or (f != null and sp.player.get_parent() != f and sp.get("bound") != "2d"):
		sp = _make_speaker(from, f)
		if sp.empty():
			return
	var team_mate: bool = f != null and "team" in f and world.player != null and f.team >= 0 and f.team == world.player.team
	if bool(Settings.pref("voice_team_only")) and not team_mate:
		return
	var samples := decode(bytes)
	sp.last = OS.get_ticks_msec()
	sp.level = min(1.0, rms(samples) * 6.0)
	sp.packets += 1
	var vol: float = float(Settings.pref("voice_volume"))
	if not team_mate and f != null and world.player != null:
		var d: float = f.global_transform.origin.distance_to(world.player.global_transform.origin)
		if d > MAX_HEAR:
			return
	_push(sp, samples, vol)


func _make_speaker(from: int, f) -> Dictionary:
	var old = speakers.get(from)
	if old != null and is_instance_valid(old.get("player")):
		old.player.queue_free()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.5
	var player
	var world = get_tree().current_scene
	var team_mate: bool = f != null and "team" in f and world != null and world.get("player") != null and f.team >= 0 and f.team == world.player.team
	var bound := "2d"
	if f != null and not team_mate:
		player = AudioStreamPlayer3D.new()
		player.unit_size = 10.0
		player.max_distance = MAX_HEAR
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.bus = "Master"
		f.add_child(player)
		player.translation = Vector3(0, 1.6, 0)
		bound = "3d"
	else:
		player = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
	player.stream = gen
	player.play()
	var name_s := "Player %d" % from
	if f != null and "display_name" in f:
		name_s = f.display_name
	elif Net.members.has(from):
		name_s = str(Net.members[from].get("name", "player"))
	var sp := {"gen": gen, "player": player, "playback": player.get_stream_playback(), "last": 0, "level": 0.0, "name": name_s, "packets": 0, "started": false, "bound": bound}
	speakers[from] = sp
	emit_signal("speakers_changed")
	return sp


func _push(sp: Dictionary, samples: PoolRealArray, vol: float) -> void:
	var pb: AudioStreamGeneratorPlayback = sp.playback
	if pb == null:
		return
	var free := pb.get_frames_available()
	var queued: float = (sp.gen.buffer_length * RATE - float(free)) / float(RATE)
	if queued > MAX_QUEUE:
		return                                              # far behind: drop this packet to catch up
	var frames := PoolVector2Array()
	frames.resize(samples.size())
	for i in range(samples.size()):
		var v: float = clamp(samples[i] * vol, -1.0, 1.0)
		frames[i] = Vector2(v, v)
	if free >= frames.size():
		pb.push_buffer(frames)


# Who is talking right now (names), for the HUD.
func talking_names() -> Array:
	var now := OS.get_ticks_msec()
	var out := []
	if talking:
		out.append("You")
	for id in speakers:
		var sp: Dictionary = speakers[id]
		if now - int(sp.last) < 450:
			out.append(sp.name)
	return out


func _prune_speakers() -> void:
	for id in speakers.keys():
		if not is_instance_valid(speakers[id].player):
			speakers.erase(id)
			emit_signal("speakers_changed")


func reset() -> void:
	for id in speakers:
		if is_instance_valid(speakers[id].player):
			speakers[id].player.queue_free()
	speakers.clear()
	_pending = PoolRealArray()
	talking = false

extends Reference
# Emotes: the dances and gestures on the emote wheel (hold the emote key, B by default).
#   loop   true = keeps going until you move, jump or fire; false = plays once for `length` seconds
#   music  the loop that plays from the dancer (assets/audio/emote_<id>_loop.wav when the audio agent has made it,
#          otherwise a short beat synthesised here so the dances are never silent)
# The poses themselves live in Animator._pose_emote().

const ORDER := ["boogie", "wave", "floss", "robot", "twirl", "flex", "cheer", "sit"]
const WHEEL_SIZE := 8
const DEFAULT_WHEEL := ["boogie", "wave", "floss", "robot", "twirl", "flex", "cheer", "sit"]

const LIST := {
	"boogie": {"name": "Boogie Down", "rarity": 0, "loop": true, "length": 60.0, "desc": "The classic knee-pumping dance"},
	"wave": {"name": "Hello There", "rarity": 0, "loop": false, "length": 2.6, "desc": "A friendly wave"},
	"floss": {"name": "Hip Swing", "rarity": 1, "loop": true, "length": 60.0, "desc": "Swing those hips and arms"},
	"robot": {"name": "Beep Boop", "rarity": 2, "loop": true, "length": 60.0, "desc": "Stiff, mechanical and proud of it"},
	"twirl": {"name": "Twirl", "rarity": 2, "loop": true, "length": 60.0, "desc": "Spin around with your arms out"},
	"flex": {"name": "Power Pose", "rarity": 1, "loop": false, "length": 3.6, "desc": "Show off those muscles"},
	"cheer": {"name": "Victory Hop", "rarity": 3, "loop": true, "length": 60.0, "desc": "Jump for joy"},
	"sit": {"name": "Take a Seat", "rarity": 3, "loop": true, "length": 60.0, "desc": "Sit down and chill to a lazy tune"},
}

# Music for the synthesised fallback: tempo, root note, 32 sixteenth steps of bass / lead (semitones above the root, -1 = rest),
# kick / snare / hat patterns, lead waveform.
const SONGS := {
	"boogie": {"bpm": 118, "root": 110.0, "wave": "square",
		"bass": [0, -1, 0, -1, 3, -1, 3, -1, 5, -1, 5, -1, 3, -1, 2, -1, 0, -1, 0, -1, 3, -1, 3, -1, 7, -1, 5, -1, 3, -1, 2, -1],
		"lead": [12, -1, 15, -1, 12, -1, 10, -1, 12, -1, 15, -1, 17, -1, 15, -1, 12, -1, 15, -1, 12, -1, 10, -1, 7, -1, 10, -1, 12, -1, -1, -1],
		"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "..x...x...x...x."},
	"wave": {"bpm": 100, "root": 196.0, "wave": "tri",
		"bass": [0, -1, -1, -1, 7, -1, -1, -1, 5, -1, -1, -1, 7, -1, -1, -1, 0, -1, -1, -1, 7, -1, -1, -1, 5, -1, -1, -1, 4, -1, -1, -1],
		"lead": [12, -1, 16, -1, 19, -1, 16, -1, 17, -1, 14, -1, 12, -1, -1, -1, 12, -1, 16, -1, 19, -1, 24, -1, 19, -1, 16, -1, 12, -1, -1, -1],
		"kick": "x.......x.......", "snare": "", "hat": "....x.......x..."},
	"floss": {"bpm": 128, "root": 98.0, "wave": "saw",
		"bass": [0, 0, -1, 0, -1, 0, 5, -1, 0, 0, -1, 0, -1, 0, 7, -1, 0, 0, -1, 0, -1, 0, 5, -1, 3, 3, -1, 3, -1, 2, 2, -1],
		"lead": [-1, -1, 12, -1, -1, 15, -1, -1, 17, -1, -1, 15, -1, 12, -1, -1, -1, -1, 12, -1, -1, 15, -1, -1, 19, -1, 17, -1, 15, -1, 12, -1],
		"kick": "x..xx..xx..xx..x", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."},
	"robot": {"bpm": 112, "root": 82.4, "wave": "square",
		"bass": [0, -1, 0, -1, 0, -1, 12, -1, 0, -1, 0, -1, 0, -1, 12, -1, 0, -1, 0, -1, 0, -1, 12, -1, 7, -1, 7, -1, 6, -1, 5, -1],
		"lead": [24, -1, -1, -1, 24, -1, 27, -1, 24, -1, -1, -1, 22, -1, -1, -1, 24, -1, -1, -1, 24, -1, 27, -1, 29, -1, -1, -1, 27, -1, -1, -1],
		"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.xx"},
	"twirl": {"bpm": 138, "root": 130.8, "wave": "tri",
		"bass": [0, -1, 7, -1, 0, -1, 7, -1, 5, -1, 12, -1, 5, -1, 12, -1, 3, -1, 10, -1, 3, -1, 10, -1, 7, -1, 14, -1, 7, -1, 14, -1],
		"lead": [12, 16, 19, 24, 19, 16, 12, 16, 17, 21, 24, 29, 24, 21, 17, 21, 15, 19, 22, 27, 22, 19, 15, 19, 19, 23, 26, 31, 26, 23, 19, 23],
		"kick": "x...x...x...x...", "snare": "", "hat": "..x...x...x...x."},
	"flex": {"bpm": 92, "root": 73.4, "wave": "saw",
		"bass": [0, -1, -1, 0, -1, -1, 0, -1, 3, -1, -1, 3, -1, -1, 5, -1, 0, -1, -1, 0, -1, -1, 0, -1, 7, -1, -1, 5, -1, 3, -1, -1],
		"lead": [-1, -1, -1, -1, 12, -1, -1, -1, -1, -1, -1, -1, 15, -1, -1, -1, -1, -1, -1, -1, 12, -1, -1, -1, 19, -1, 17, -1, 15, -1, -1, -1],
		"kick": "x..x..x...x..x..", "snare": "....x.......x...", "hat": ""},
	"cheer": {"bpm": 144, "root": 146.8, "wave": "square",
		"bass": [0, -1, 0, -1, 4, -1, 4, -1, 7, -1, 7, -1, 4, -1, 4, -1, 5, -1, 5, -1, 9, -1, 9, -1, 7, -1, 7, -1, 2, -1, 2, -1],
		"lead": [12, -1, 16, -1, 19, -1, 24, -1, 19, -1, 16, -1, 19, -1, 24, -1, 17, -1, 21, -1, 24, -1, 29, -1, 26, -1, 23, -1, 19, -1, -1, -1],
		"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."},
	"sit": {"bpm": 76, "root": 87.3, "wave": "tri",
		"bass": [0, -1, -1, -1, -1, -1, 7, -1, 5, -1, -1, -1, -1, -1, 3, -1, 0, -1, -1, -1, -1, -1, 7, -1, 10, -1, -1, -1, 8, -1, 7, -1],
		"lead": [-1, -1, 15, -1, -1, -1, 12, -1, -1, -1, 14, -1, -1, -1, 10, -1, -1, -1, 15, -1, -1, -1, 19, -1, -1, -1, 17, -1, 15, -1, -1, -1],
		"kick": "x.......x.......", "snare": "", "hat": "..x...x...x...x."},
}


static func is_emote(id: String) -> bool:
	return LIST.has(id)


static func index_of(id: String) -> int:
	return int(max(0, ORDER.find(id)))


static func id_at(index: int) -> String:
	return ORDER[int(clamp(index, 0, ORDER.size() - 1))]


static func length_of(id: String) -> float:
	return LIST[id].length if LIST.has(id) else 4.0


# The wheel from a saved list, topped up with defaults so it always has between 1 and WHEEL_SIZE valid entries.
static func sanitize_wheel(list) -> Array:
	var out := []
	if list is Array:
		for id in list:
			if LIST.has(str(id)) and not (str(id) in out) and out.size() < WHEEL_SIZE:
				out.append(str(id))
	if out.empty():
		out = DEFAULT_WHEEL.duplicate()
	return out


static func music_name(id: String) -> String:
	return "emote_%s_loop" % id


# The dance music: the real recording when it exists, else a synthesised loop (built once, then cached).
static func stream(id: String):
	if not Engine.has_meta("emote_streams"):
		Engine.set_meta("emote_streams", {})
	var cache: Dictionary = Engine.get_meta("emote_streams")
	if cache.has(id):
		return cache[id]
	var st = null
	var path := "res://assets/audio/%s.wav" % music_name(id)
	if ResourceLoader.exists(path):
		st = load(path)
		if st != null:
			st.loop_mode = AudioStreamSample.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.data.size() / 2) if st.format == AudioStreamSample.FORMAT_16_BITS else st.data.size()
	if st == null and SONGS.has(id):
		st = synth(SONGS[id])
	cache[id] = st
	return st


static func _osc(kind: String, phase: float) -> float:
	var ph: float = phase - floor(phase)
	match kind:
		"square":
			return 0.5 if ph < 0.5 else -0.5
		"saw":
			return (ph * 2.0 - 1.0) * 0.55
	return (abs(ph * 4.0 - 2.0) - 1.0) * 0.8        # triangle


static func synth(song: Dictionary) -> AudioStreamSample:
	var rate := 22050
	var step_len: float = 60.0 / float(song.bpm) / 4.0
	var steps := 32
	var n := int(step_len * steps * rate)
	var buf := []
	buf.resize(n)
	for i in range(n):
		buf[i] = 0.0
	var seed_v := 12345
	for s in range(steps):
		var t0 := int(s * step_len * rate)
		var len_n := int(step_len * rate)
		var bn: int = song.bass[s]
		var ln: int = song.lead[s]
		var kick: bool = String(song.kick).length() > 0 and String(song.kick)[s % 16] == "x"
		var snare: bool = String(song.snare).length() > 0 and String(song.snare)[s % 16] == "x"
		var hat: bool = String(song.hat).length() > 0 and String(song.hat)[s % 16] == "x"
		var bf: float = song.root * pow(2.0, bn / 12.0)
		var lf: float = song.root * 2.0 * pow(2.0, ln / 12.0)
		for k in range(min(len_n * 2, n - t0)):                  # notes ring a little past their step
			var i := t0 + k
			var tt := float(k) / rate
			var v := 0.0
			if bn >= 0:
				v += _osc("tri", bf * tt) * 0.45 * exp(-tt * 5.0)
			if ln >= 0:
				v += _osc(song.wave, lf * tt) * 0.20 * exp(-tt * 7.0)
			if k < len_n:
				if kick:
					v += sin(TAU * (48.0 + 110.0 * exp(-tt * 28.0)) * tt) * 0.8 * exp(-tt * 9.0)
				if snare or hat:
					seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
					var noise: float = (float(seed_v % 2000) / 1000.0 - 1.0)
					v += noise * (0.35 * exp(-tt * 18.0) if snare else 0.14 * exp(-tt * 55.0))
			buf[i] += v
	var data := PoolByteArray()
	data.resize(n * 2)
	for i in range(n):
		var x: float = clamp(buf[i] * 0.55, -1.0, 1.0)
		var q := int(x * 32000.0)
		if q < 0:
			q += 65536
		data[i * 2] = q & 255
		data[i * 2 + 1] = (q >> 8) & 255
	var st := AudioStreamSample.new()
	st.format = AudioStreamSample.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamSample.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	return st

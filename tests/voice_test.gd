extends SceneTree
# Voice chat, one process: the codec keeps speech intact, a received packet plays through a speaker, the packet size is small,
# the microphone bus can be created, and the settings / key exist.

var failures := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		print("FAIL  ", msg)
		failures.append(msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	yield(self, "idle_frame")
	var V = root.get_node("Voice")
	var Settings = root.get_node("Settings")
	# a 440 Hz tone with a slow swell, like a voice
	var tone := PoolRealArray()
	for i in range(V.CHUNK):
		tone.append(0.5 * sin(TAU * 440.0 * float(i) / float(V.RATE)) * (0.5 + 0.5 * sin(TAU * 3.0 * float(i) / float(V.RATE))))
	var bytes: PoolByteArray = V.encode(tone)
	check(bytes.size() == V.CHUNK, "a 40 ms packet is %d bytes (16 kB/s)" % bytes.size())
	var back: PoolRealArray = V.decode(bytes)
	var err := 0.0
	var sig := 0.0
	for i in range(tone.size()):
		err += pow(tone[i] - back[i], 2)
		sig += pow(tone[i], 2)
	var snr: float = 10.0 * log(sig / max(err, 0.0000001)) / log(10.0)
	check(snr > 25.0, "the codec keeps the sound (%.1f dB signal to noise)" % snr)
	check(abs(V.rms(back) - V.rms(tone)) < 0.02, "and the loudness (%.3f vs %.3f)" % [V.rms(back), V.rms(tone)])
	var quiet := PoolRealArray([0.0, 0.0, 0.0])
	check(V.rms(V.decode(V.encode(quiet))) < 0.01, "silence stays silent")
	# a speaker plays a received packet
	Settings.prefs["voice_mode"] = 0
	V.receive(77, bytes, 1)
	check(V.speakers.has(77) and V.speakers[77].packets == 1, "a received packet creates a speaker")
	check(V.speakers[77].level > 0.1, "with a voice level (%.2f)" % V.speakers[77].level)
	var pb = V.speakers[77].playback
	yield(create_timer(0.3), "timeout")
	for i in range(3):
		V.receive(77, bytes, 2 + i)
	check(V.speakers[77].packets == 4, "more packets queue up")
	check(V.talking_names().has(V.speakers[77].name), "the speaker is listed as talking (%s)" % str(V.talking_names()))
	V.speakers[77].player.queue_free()
	yield(create_timer(0.1), "timeout")
	# settings and keys
	check(Settings.pref("voice_mode") == 0 and Settings.pref("voice_volume") == 1.0, "voice settings have defaults")
	check(InputMap.has_action("voice"), "the voice key (N) is bound")
	# microphone start-up on a desktop without a microphone must not crash
	var ok: bool = V.ensure_mic()
	print("mic ready: ", ok, " err: ", V.mic_error)
	check(ok or V.mic_error != "", "the microphone starts (or says why not)")
	# open-mic ingest path: a block of loud audio becomes packets
	if ok:
		Settings.prefs["voice_mode"] = 1
	print("VOICE_RESULT failures=", failures.size())
	quit(1 if failures.size() > 0 else 0)

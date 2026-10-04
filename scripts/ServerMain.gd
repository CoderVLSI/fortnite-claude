extends Node
# Entry point of a dedicated server (run the game with --server). It opens the port, sits in a lobby, starts matches and goes
# back to the lobby afterwards. No window content is drawn: this process only simulates.
#
#   ./StormIsland.x86_64 --server --port=7777 --instance=0 --bots=30
#
# Public lobby: players press READY; the match starts when everybody is ready (or after LOBBY_WAIT seconds), bots fill the rest.
# Private room (a player asked for one with the code): only the leader's PLAY starts it.

const LOBBY_WAIT := 25.0         # seconds after the first player arrives before a public lobby starts anyway
const ALL_READY_DELAY := 3.0
const ROOM_RESERVE := 120.0      # an empty private room keeps its code this long

var _lobby_age := 0.0
var _room_idle := 0.0
var _log_t := 0.0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	var port := Net.PORT
	var instance := 0
	for a in OS.get_cmdline_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--instance="):
			instance = int(a.substr(11))
		elif a == "--zero-build":
			Settings.zero_build = true
	if "render_loop_enabled" in VisualServer:
		VisualServer.render_loop_enabled = false          # nothing is drawn on a server
	var err: String = Net.host_dedicated(port, instance)
	if err != "":
		print("SERVER ERROR: ", err)
		get_tree().quit(1)
		return
	Settings.autostart = false
	Net.set_zero_build(Settings.zero_build)
	Net.connect("match_starting", self, "_on_match_starting")
	print("SERVER listening on UDP %d (instance %d, version %s)" % [port, instance, Net.VERSION])


func _on_match_starting() -> void:
	print("SERVER match starting with %d players" % Net.members.size())
	get_tree().paused = false
	get_tree().change_scene("res://scenes/Main.tscn")


func _process(delta: float) -> void:
	if Net.in_match or not Net.dedicated:
		return
	_log_t += delta
	if _log_t > 30.0:
		_log_t = 0.0
		print("SERVER lobby: %d player(s), room '%s'" % [Net.members.size(), Net.room_code])
	if Net.members.empty():
		_lobby_age = 0.0
		if Net.room_code != "":
			_room_idle += delta
			if _room_idle > ROOM_RESERVE:
				Net.room_code = ""
				Net.room_leader = 0
				_room_idle = 0.0
		return
	_room_idle = 0.0
	_lobby_age += delta
	if Net.room_code != "" or Net.is_queueing():
		return                                    # a private room waits for its leader
	var all_ready := true
	for id in Net.members:
		if not bool(Net.members[id].get("ready", false)):
			all_ready = false
	if (all_ready and _lobby_age > ALL_READY_DELAY) or _lobby_age >= LOBBY_WAIT:
		Net.queue_up()

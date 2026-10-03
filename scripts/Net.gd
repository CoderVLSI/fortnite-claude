extends Node
# LAN / IP multiplayer (autoload "Net"). Godot's high-level multiplayer over ENet (UDP), the same on Windows, Linux and Android.
#
# Model: every player simulates their own character (movement, shooting, building) and sends it to the others, who show it as
# a "puppet". Damage on a puppet is forwarded to the peer that owns that character. The HOST also runs every bot and the storm
# timer, and sends the bots' state to the others. The world itself is generated from a shared seed so every machine builds
# the same island, loot and chests; only what changes during the match is sent as events.
#
#   Party flow:  host_game() / join_game()  ->  members list  ->  host start_match()  ->  everyone reloads the world with the
#                shared seed  ->  each peer calls world_ready()  ->  host says "go"  ->  match_go.
#
# Nothing here does anything unless `active` is true, so single-player is untouched.

signal party_changed                 # the list of players changed
signal join_failed(reason)
signal joined                        # connected to a host and accepted
signal left(reason)                  # the session ended (host left, kicked, connection lost)
signal match_starting                # the host started the match: load the world
signal match_go                      # all worlds are built: start now
signal games_found                   # LAN discovery list changed

const VERSION := "storm-island-lan-2"
const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 8
const TOTAL_FIGHTERS := 50           # humans + bots

var active := false                  # a party or a networked match exists
var is_host := false
var in_match := false
var my_id := 1
var members := {}                    # peer id -> {"name": String, "loadout": Dictionary, "ready": bool}
var match_seed := 0
var bot_count := 49
var order := []                      # peer ids in the order they take spawn points
var handler: Node = null             # the World: receives pose / events while a match runs
var sessions := {}                   # LAN discovery: ip -> {"name", "players", "port", "seen"}
var last_error := ""

var _peer: NetworkedMultiplayerENet
var _udp_out: PacketPeerUDP
var _udp_in: PacketPeerUDP
var _announce_t := 0.0
var _ready_peers := {}
var _my_name := "PLAYER"
var _my_loadout := {}
var _loot_seq := 0


func _ready() -> void:
	var tree := get_tree()
	tree.connect("network_peer_connected", self, "_on_peer_connected")
	tree.connect("network_peer_disconnected", self, "_on_peer_disconnected")
	tree.connect("connected_to_server", self, "_on_connected_to_server")
	tree.connect("connection_failed", self, "_on_connection_failed")
	tree.connect("server_disconnected", self, "_on_server_disconnected")


func _process(delta: float) -> void:
	if _udp_out != null and is_host and not in_match:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce_t = 1.5
			var pkt := ("SI|%s|%s|%d|%d" % [VERSION, _my_name, members.size(), PORT]).to_utf8()
			_udp_out.put_packet(pkt)
	if _udp_in != null:
		while _udp_in.get_available_packet_count() > 0:
			var text := _udp_in.get_packet().get_string_from_utf8()
			var ip := _udp_in.get_packet_ip()
			var parts := text.split("|")
			if parts.size() >= 5 and parts[0] == "SI" and ip != "":
				sessions[ip] = {"name": parts[2], "players": int(parts[3]), "port": int(parts[4]), "version": parts[1], "seen": OS.get_ticks_msec()}
				emit_signal("games_found")
		var changed := false
		for ip in sessions.keys():
			if OS.get_ticks_msec() - sessions[ip].seen > 6000:
				sessions.erase(ip)
				changed = true
		if changed:
			emit_signal("games_found")


# ------------------------------------------------------------------ hosting / joining

func local_addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.find(":") >= 0 or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			out.append(s)
	return out


# Returns "" on success or an error message.
func host_game(player_name: String, loadout: Dictionary, port: int = PORT) -> String:
	leave("")
	_peer = NetworkedMultiplayerENet.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		return "Could not open port %d (is the game already running?)." % port
	get_tree().network_peer = _peer
	active = true
	is_host = true
	in_match = false
	my_id = 1
	_my_name = player_name
	_my_loadout = loadout.duplicate()
	members = {1: {"name": player_name, "loadout": loadout.duplicate(), "ready": false}}
	_start_announce()
	emit_signal("party_changed")
	return ""


func join_game(ip: String, player_name: String, loadout: Dictionary, port: int = PORT) -> String:
	leave("")
	if ip.strip_edges() == "":
		return "Enter the host's IP address."
	_peer = NetworkedMultiplayerENet.new()
	var err := _peer.create_client(ip.strip_edges(), port)
	if err != OK:
		_peer = null
		return "Could not start connecting (%d)." % err
	get_tree().network_peer = _peer
	active = true
	is_host = false
	in_match = false
	_my_name = player_name
	_my_loadout = loadout.duplicate()
	return ""


func leave(reason: String = "") -> void:
	var was := active
	_stop_announce()
	stop_discovery()
	if get_tree().network_peer != null:
		get_tree().network_peer = null
	if _peer != null:
		_peer.close_connection()
		_peer = null
	active = false
	is_host = false
	in_match = false
	members = {}
	order = []
	handler = null
	_ready_peers = {}
	if was:
		emit_signal("left", reason)


func _start_announce() -> void:
	_stop_announce()
	_udp_out = PacketPeerUDP.new()
	_udp_out.set_broadcast_enabled(true)
	_udp_out.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_announce_t = 0.0


func _stop_announce() -> void:
	if _udp_out != null:
		_udp_out.close()
		_udp_out = null


func start_discovery() -> void:
	stop_discovery()
	sessions = {}
	_udp_in = PacketPeerUDP.new()
	if _udp_in.listen(DISCOVERY_PORT, "*") != OK:
		_udp_in = null


func stop_discovery() -> void:
	if _udp_in != null:
		_udp_in.close()
		_udp_in = null


# ------------------------------------------------------------------ connection callbacks

func _on_peer_connected(id: int) -> void:
	pass          # the newcomer says hello, then we add them


func _on_peer_disconnected(id: int) -> void:
	if not active:
		return
	if members.has(id):
		var nm: String = members[id].name
		members.erase(id)
		order.erase(id)
		if is_host:
			rpc("_party_update", members)
		emit_signal("party_changed")
		if in_match and handler != null and handler.has_method("net_peer_left"):
			handler.net_peer_left(id, nm)
		if is_host and in_match:
			_check_ready()


func _on_connected_to_server() -> void:
	my_id = get_tree().get_network_unique_id()
	rpc_id(1, "_hello", VERSION, _my_name, _my_loadout)


func _on_connection_failed() -> void:
	leave("")
	emit_signal("join_failed", "Could not reach the host. Check the IP address and that you are on the same network.")


func _on_server_disconnected() -> void:
	leave("The host left the game.")


remote func _hello(version: String, player_name: String, loadout: Dictionary) -> void:
	if not is_host:
		return
	var id := get_tree().get_rpc_sender_id()
	if version != VERSION:
		rpc_id(id, "_rejected", "Version mismatch: you need the same build as the host (%s)." % VERSION)
		_peer.disconnect_peer(id)
		return
	if in_match:
		rpc_id(id, "_rejected", "A match is already in progress.")
		_peer.disconnect_peer(id)
		return
	if members.size() >= MAX_PLAYERS:
		rpc_id(id, "_rejected", "The party is full.")
		_peer.disconnect_peer(id)
		return
	members[id] = {"name": player_name.substr(0, 14), "loadout": loadout, "ready": false}
	rpc("_party_update", members)
	rpc_id(id, "_accepted")
	emit_signal("party_changed")


remote func _rejected(reason: String) -> void:
	leave("")
	emit_signal("join_failed", reason)


remote func _accepted() -> void:
	emit_signal("joined")


remote func _party_update(m: Dictionary) -> void:
	members = m
	emit_signal("party_changed")


func set_loadout(loadout: Dictionary) -> void:
	_my_loadout = loadout.duplicate()
	if active and members.has(my_id):
		members[my_id].loadout = _my_loadout
		if is_host:
			rpc("_party_update", members)
		else:
			rpc_id(1, "_loadout", _my_loadout)


remote func _loadout(loadout: Dictionary) -> void:
	var id := get_tree().get_rpc_sender_id()
	if is_host and members.has(id):
		members[id].loadout = loadout
		rpc("_party_update", members)
		emit_signal("party_changed")


# ------------------------------------------------------------------ starting a match

func human_count() -> int:
	return members.size()


# Host: everyone loads the world with the same seed.
func start_match(seed_value: int = 0) -> void:
	if not is_host or in_match:
		return
	var ids := members.keys()
	ids.sort()
	var seed_v: int = seed_value if seed_value != 0 else int(randi() % 2000000000) + 1
	var bots: int = int(max(TOTAL_FIGHTERS - ids.size(), 0))
	rpc("_begin_match", seed_v, bots, ids)
	_begin_match(seed_v, bots, ids)


remote func _begin_match(seed_v: int, bots: int, ids: Array) -> void:
	match_seed = seed_v
	bot_count = bots
	order = ids.duplicate()
	in_match = true
	_ready_peers = {}
	_loot_seq = 0
	_stop_announce()
	emit_signal("match_starting")


# Every peer: my world is built.
func world_ready(world: Node) -> void:
	handler = world
	if not active:
		return
	if is_host:
		_ready_peers[1] = true
		_check_ready()
	else:
		rpc_id(1, "_peer_ready")


remote func _peer_ready() -> void:
	if is_host:
		_ready_peers[get_tree().get_rpc_sender_id()] = true
		_check_ready()


func _check_ready() -> void:
	if not is_host or not in_match:
		return
	for id in members.keys():
		if not _ready_peers.has(id):
			return
	_ready_peers = {"gone": true}
	rpc("_go")
	_go()


remote func _go() -> void:
	emit_signal("match_go")


# Back to the party screen after a match (the host keeps the party).
func end_match() -> void:
	in_match = false
	handler = null
	_ready_peers = {}
	if is_host and active:
		_start_announce()


# ------------------------------------------------------------------ gameplay traffic

func send_pose(state: Array) -> void:
	if active and in_match:
		rpc_unreliable("_pose", state)


remote func _pose(state: Array) -> void:
	if handler != null and handler.has_method("net_pose"):
		handler.net_pose(get_tree().get_rpc_sender_id(), state)


func send_bots(chunk: Array) -> void:
	if active and is_host and in_match:
		rpc_unreliable("_bots", chunk)


remote func _bots(chunk: Array) -> void:
	if handler != null and handler.has_method("net_bots"):
		handler.net_bots(chunk)


func send_vehicle(id: String, xf: Transform) -> void:
	if active and in_match:
		rpc_unreliable("_veh", id, xf)


remote func _veh(id: String, xf: Transform) -> void:
	if handler != null and handler.has_method("net_vehicle"):
		handler.net_vehicle(get_tree().get_rpc_sender_id(), id, xf)


# A reliable event for everyone else (kind: String, data: Variant).
func send_event(kind: String, data = null) -> void:
	if active and in_match:
		rpc("_event", kind, data)


func send_event_to(id: int, kind: String, data = null) -> void:
	if active and in_match and id != my_id:
		rpc_id(id, "_event", kind, data)


remote func _event(kind: String, data) -> void:
	if handler != null and handler.has_method("net_event"):
		handler.net_event(get_tree().get_rpc_sender_id(), kind, data)


# Damage dealt to a character this peer does not own: the owner applies it.
func send_damage(owner_id: int, target, amount: float, source, headshot: bool) -> void:
	if active and in_match:
		rpc_id(owner_id, "_damage", target, amount, source, headshot)


remote func _damage(target, amount: float, source, headshot: bool) -> void:
	if handler != null and handler.has_method("net_damage"):
		handler.net_damage(get_tree().get_rpc_sender_id(), target, amount, source, headshot)


# The network key of a character: a peer id (humans) or a name (bots). null for "nobody" (the storm, fall damage).
func key_of(f):
	if f != null and is_instance_valid(f) and "net_key_v" in f:
		return f.net_key_v
	return null


# A network-wide unique id for something this peer creates during the match (dropped loot, pieces, projectiles).
func new_id(prefix: String) -> String:
	_loot_seq += 1
	return "%s%d_%d" % [prefix, my_id, _loot_seq]

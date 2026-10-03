extends "res://scripts/Fighter.gd"
# Another human in a network match, seen on this machine. Their own game simulates them and sends their state; this node only
# shows it (smoothly) and lets bullets, grenades and vehicles hit it: damage is forwarded to the peer that owns the character.

var peer_id := 0
var color := Color(0.3, 0.5, 0.9)
var player_name := "PLAYER"


func _ready() -> void:
	net_owner = peer_id
	net_key_v = peer_id
	loadout = Cosmetics.sanitize(loadout)
	skin_id = loadout.skin
	setup_fighter(player_name, color)
	add_to_group("remote_players")
	connect("died", get_tree().get_nodes_in_group("world")[0], "_on_fighter_died")


func _physics_process(delta: float) -> void:
	tick_weapon(delta)
	net_smooth(delta)
	animate(delta)

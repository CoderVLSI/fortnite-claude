extends "res://scripts/Fighter.gd"
# Another human in a network match, seen on this machine. Their own game simulates them and sends their state; this node only
# shows it (smoothly) and lets bullets, grenades and vehicles hit it: damage is forwarded to the peer that owns the character.

var peer_id := 0


func setup_remote(id: int, player_name: String, lo: Dictionary, color: Color) -> void:
	peer_id = id
	net_owner = id
	net_key_v = id
	loadout = Cosmetics.sanitize(lo)
	skin_id = loadout.skin
	setup_fighter(player_name, color)
	add_to_group("remote_players")


func _physics_process(delta: float) -> void:
	tick_weapon(delta)
	net_smooth(delta)
	animate(delta)

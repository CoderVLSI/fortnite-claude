extends Reference
# Quick chat: a short list of radio lines for team-mates (opens the ShopScreen menu; the HUD calls options() / choose()).
# Online in a team mode only your team sees the line; with no teams everyone does. "Enemy there!" and "Go here" also drop a ping.

var npc_name := "Quick chat"
const LINES := [
	{"id": "ammo", "text": "I need ammo!"},
	{"id": "heal", "text": "I need healing!"},
	{"id": "enemy", "text": "Enemy there!", "ping": "enemy"},
	{"id": "follow", "text": "Follow me!"},
	{"id": "go", "text": "Go here!", "ping": "go"},
	{"id": "thanks", "text": "Thanks!"},
]


func greeting() -> String:
	return "Pick a line. Your team sees it on the feed."


func options(_by) -> Array:
	var out := []
	for l in LINES:
		out.append({"id": l.id, "label": l.text, "sub": "", "enabled": true})
	return out


func choose(id, by, hud) -> void:
	for l in LINES:
		if l.id == id:
			hud.shop.close()
			for w in by.get_tree().get_nodes_in_group("world"):
				w.send_chat(l.text, l.get("ping", ""))
			return

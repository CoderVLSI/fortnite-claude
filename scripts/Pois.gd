extends Reference
# Named points of interest. Each POI is laid out in its own frame:
#   local +X points away from the island centre, local +Z is "right" of that.
# Props: {res, at (Vector2), yaw (deg, local), y (extra height), tint, harvest, building,
#         face_center (door faces the POI middle), spin ("blades" | "dish")}
# Chests / items may be given relative to a prop: "in": index into props, and then "at" is
# in that prop's own frame (door side = +Z), otherwise "at" is POI-local.

const POIS := [
	{
		"id": "docks", "name": "SALTWORKS DOCKS", "angle": 20.0, "mode": "shore", "inland": 22.0, "zone": 34.0,
		"props": [
			{"res": "warehouse", "at": Vector2(-14, 0), "yaw": 90, "harvest": "metal", "building": true},
			{"res": "container", "at": Vector2(-3, -15), "yaw": 0, "tint": Color(0.75, 0.2, 0.15), "harvest": "metal"},
			{"res": "container", "at": Vector2(-3, -12.4), "yaw": 0, "tint": Color(0.2, 0.4, 0.7), "harvest": "metal"},
			{"res": "container", "at": Vector2(-3, -15), "y": 2.6, "yaw": 0, "tint": Color(0.9, 0.6, 0.15), "harvest": "metal"},
			{"res": "container", "at": Vector2(2, -14), "yaw": 0, "tint": Color(0.2, 0.55, 0.3), "harvest": "metal"},
			{"res": "container", "at": Vector2(-3, 14), "yaw": 90, "tint": Color(0.6, 0.2, 0.5), "harvest": "metal"},
			{"res": "container", "at": Vector2(-3, 14), "y": 2.6, "yaw": 90, "tint": Color(0.2, 0.6, 0.7), "harvest": "metal"},
			{"res": "crane", "at": Vector2(9, 11), "yaw": 90, "harvest": "metal"},
		],
		"chests": [
			{"in": 0, "at": Vector2(-6.5, -3.8), "kind": "chest"},
			{"in": 0, "at": Vector2(6.5, -3.8), "kind": "chest"},
			{"in": 0, "at": Vector2(0, -4.4), "kind": "ammo_box"},
			{"at": Vector2(12, -6), "yaw": 90, "kind": "chest"},
		],
		"items": [Vector2(0, 6), Vector2(8, 2), Vector2(14, -3), Vector2(-8, 9)],
		"pier": {"from": 16.0, "length": 34.0, "width": 5.0},
		"vehicles": [{"kind": "boat", "at": Vector2(30, 7), "yaw": 0}, {"kind": "buggy", "at": Vector2(4, 4), "yaw": 90}],
	},
	{
		"id": "lodge", "name": "PINE RIDGE LODGE", "angle": 150.0, "mode": "hill", "rmin": 74.0, "rmax": 94.0, "zone": 36.0,
		"props": [
			{"res": "lodge", "at": Vector2(0, 0), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "cabin", "at": Vector2(-1, -22), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "cabin", "at": Vector2(-1, 22), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "cabin", "at": Vector2(-19, -12), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "cabin", "at": Vector2(-19, 13), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "watchtower", "at": Vector2(16, 18), "yaw": 0, "harvest": "wood"},
			{"res": "fence", "at": Vector2(10, -26), "yaw": 0, "harvest": "wood", "decor": true},
			{"res": "fence", "at": Vector2(13, -26), "yaw": 0, "harvest": "wood", "decor": true},
			{"res": "fence", "at": Vector2(16, -26), "yaw": 0, "harvest": "wood", "decor": true},
		],
		"chests": [
			{"in": 0, "at": Vector2(-4.5, -3.2), "kind": "chest"},
			{"in": 0, "at": Vector2(4.5, -3.2), "kind": "chest"},
			{"in": 0, "at": Vector2(0, -4.0), "kind": "ammo_box"},
			{"in": 1, "at": Vector2(-1.8, -1.6), "kind": "chest"},
			{"in": 3, "at": Vector2(-1.8, -1.6), "kind": "chest"},
		],
		"items": [Vector2(2, 4), Vector2(-6, 8), Vector2(9, -8), Vector2(-10, 0)],
		"vehicles": [{"kind": "quad", "at": Vector2(12, 4), "yaw": 90}],
	},
	{
		"id": "foundry", "name": "RUSTY FOUNDRY", "angle": 215.0, "mode": "flat", "rmin": 76.0, "rmax": 96.0, "zone": 38.0,
		"props": [
			{"res": "warehouse", "at": Vector2(0, 0), "yaw": 0, "harvest": "metal", "building": true, "face_center": true},
			{"res": "chimney", "at": Vector2(-18, -14), "yaw": 0, "harvest": "metal"},
			{"res": "chimney", "at": Vector2(-18, 14), "yaw": 0, "harvest": "metal"},
			{"res": "tank", "at": Vector2(14, -16), "yaw": 0, "harvest": "metal"},
			{"res": "tank", "at": Vector2(14, 16), "yaw": 0, "harvest": "metal"},
			{"res": "container", "at": Vector2(12, 0), "yaw": 90, "tint": Color(0.7, 0.35, 0.12), "harvest": "metal"},
			{"res": "container", "at": Vector2(-22, 0), "yaw": 90, "tint": Color(0.25, 0.4, 0.55), "harvest": "metal"},
		],
		"chests": [
			{"in": 0, "at": Vector2(-6.5, -3.8), "kind": "chest"},
			{"in": 0, "at": Vector2(6.5, -3.8), "kind": "chest"},
			{"in": 0, "at": Vector2(0, -4.4), "kind": "ammo_box"},
			{"at": Vector2(8, 10), "yaw": 0, "kind": "chest"},
		],
		"items": [Vector2(4, 8), Vector2(-8, 6), Vector2(8, -6)],
		"vehicles": [{"kind": "buggy", "at": Vector2(18, 4), "yaw": 90}],
	},
	{
		"id": "farm", "name": "GOLDEN ACRES", "angle": 280.0, "mode": "flat", "rmin": 74.0, "rmax": 94.0, "zone": 38.0,
		"props": [
			{"res": "barn", "at": Vector2(0, 0), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "silo", "at": Vector2(-15, -11), "yaw": 0, "harvest": "metal"},
			{"res": "silo", "at": Vector2(-15, 0), "yaw": 0, "harvest": "metal"},
			{"res": "windmill", "at": Vector2(16, 14), "yaw": -90, "harvest": "wood", "spin": "blades"},
			{"res": "house_a", "at": Vector2(14, -8), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "haystack", "at": Vector2(9, 12), "yaw": 0, "harvest": "wood"},
			{"res": "haystack", "at": Vector2(12, 9), "yaw": 0, "harvest": "wood"},
			{"res": "haystack", "at": Vector2(-6, 16), "yaw": 0, "harvest": "wood"},
			{"res": "fence", "at": Vector2(-24, 14), "yaw": 90, "harvest": "wood", "decor": true},
			{"res": "fence", "at": Vector2(-24, 17), "yaw": 90, "harvest": "wood", "decor": true},
			{"res": "fence", "at": Vector2(-24, 20), "yaw": 90, "harvest": "wood", "decor": true},
		],
		"chests": [
			{"in": 0, "at": Vector2(-3, -5.5), "kind": "chest"},
			{"in": 0, "at": Vector2(3, -5.5), "kind": "ammo_box"},
			{"in": 4, "at": Vector2(-2.7, -2.3), "kind": "chest"},
		],
		"items": [Vector2(0, 3), Vector2(8, 4), Vector2(-9, 6)],
		"vehicles": [{"kind": "quad", "at": Vector2(6, 8), "yaw": 0}],
	},
	{
		"id": "bunker", "name": "IRON BUNKER", "angle": 330.0, "mode": "hill", "rmin": 78.0, "rmax": 98.0, "zone": 34.0,
		"props": [
			{"res": "bunker", "at": Vector2(0, 0), "yaw": 0, "harvest": "metal", "building": true, "face_center": true},
			{"res": "radar", "at": Vector2(-17, 2), "yaw": 0, "harvest": "metal", "spin": "dish"},
			{"res": "watchtower", "at": Vector2(17, 18), "yaw": 0, "harvest": "wood"},
			{"res": "watchtower", "at": Vector2(17, -18), "yaw": 0, "harvest": "wood"},
			{"res": "sandbags", "at": Vector2(7, -5), "yaw": 90, "harvest": "stone"},
			{"res": "sandbags", "at": Vector2(7, 5), "yaw": 90, "harvest": "stone"},
			{"res": "sandbags", "at": Vector2(11, 0), "yaw": 0, "harvest": "stone"},
			{"res": "crate", "at": Vector2(12, 8), "yaw": 20, "harvest": "wood"},
			{"res": "crate", "at": Vector2(13.4, 9.0), "yaw": 55, "harvest": "wood"},
			{"res": "crate", "at": Vector2(12.4, -9), "yaw": 10, "harvest": "wood"},
		],
		"chests": [
			{"in": 0, "at": Vector2(0, -2.8), "kind": "vault"},
			{"in": 0, "at": Vector2(-3.6, -2.8), "kind": "chest"},
			{"in": 0, "at": Vector2(3.6, -2.8), "kind": "ammo_box"},
			{"at": Vector2(14, 4), "yaw": 90, "kind": "ammo_box"},
		],
		"items": [Vector2(10, -2), Vector2(-9, 8)],
		"boss": {"at": Vector2(9, 3)},
		"helipad": Vector2(-8, -20),
		"vehicles": [{"kind": "buggy", "at": Vector2(-8, 12), "yaw": 0}],
	},
	{
		"id": "lighthouse", "name": "LIGHTHOUSE POINT", "angle": 85.0, "mode": "shore", "inland": 14.0, "zone": 24.0,
		"props": [
			{"res": "lighthouse", "at": Vector2(0, 0), "yaw": 0, "harvest": "stone"},
			{"res": "keeper_house", "at": Vector2(-13, 8), "yaw": 0, "harvest": "wood", "building": true, "face_center": true},
			{"res": "fence", "at": Vector2(-8, -10), "yaw": 90, "harvest": "wood", "decor": true},
			{"res": "fence", "at": Vector2(-8, -13), "yaw": 90, "harvest": "wood", "decor": true},
		],
		"chests": [
			{"in": 1, "at": Vector2(-1.5, -1.3), "kind": "chest"},
			{"at": Vector2(4, -4), "yaw": 0, "kind": "ammo_box"},
		],
		"items": [Vector2(5, 6), Vector2(-4, -6)],
		"vehicles": [{"kind": "boat", "at": Vector2(20, 9), "yaw": 0}],
	},
]

# Roads: pairs of POI ids (or "maple" for the town) drawn on the terrain and the map.
const ROADS := [
	["maple", "docks"], ["maple", "lodge"], ["maple", "foundry"], ["maple", "farm"], ["maple", "bunker"],
	["maple", "lighthouse"], ["docks", "lighthouse"], ["farm", "bunker"], ["foundry", "lodge"],
]

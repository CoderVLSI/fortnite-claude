extends Reference
# The animation clips keyed in Blender (tools/blender/generate_animations.py -> assets/models/anims.glb): slide, vault, mantle
# and the pickaxe swing. We read the imported Animation resources ourselves and hand the sampled joint rotations to the
# Animator, so the clips work on every skin and blend with the procedural walk / run cycle.

const PATH := "res://assets/models/anims.glb"


static func _db() -> Dictionary:
	if Engine.has_meta("anim_clips"):
		return Engine.get_meta("anim_clips")
	var db := {}
	if ResourceLoader.exists(PATH):
		var scene = load(PATH)
		if scene != null:
			var inst: Node = scene.instance()
			var ap = _find_player(inst)
			if ap != null:
				for name in ap.get_animation_list():
					var anim: Animation = ap.get_animation(name)
					var joints := {}
					for i in range(anim.get_track_count()):
						if anim.track_get_type(i) != Animation.TYPE_TRANSFORM:
							continue
						var path: NodePath = anim.track_get_path(i)
						joints[path.get_name(path.get_name_count() - 1)] = i
					db[name] = {"anim": anim, "joints": joints, "length": anim.length}
			inst.free()
	Engine.set_meta("anim_clips", db)
	return db


static func _find_player(n: Node):
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r = _find_player(c)
		if r != null:
			return r
	return null


static func has_clip(name: String) -> bool:
	return _db().has(name)


static func length_of(name: String) -> float:
	return _db()[name].length if _db().has(name) else 0.0


# The joints a clip drives (an upper-body clip leaves the legs to the walk cycle).
static func joints_of(name: String) -> Array:
	return _db()[name].joints.keys() if _db().has(name) else []


# Sample a clip: {joint name: Euler rotation Vector3, "_hips_y": hips height offset (only for full-body clips)}.
static func sample(name: String, time: float, hips_rest_y: float) -> Dictionary:
	var out := {}
	var db := _db()
	if not db.has(name):
		return out
	var anim: Animation = db[name].anim
	var t: float = clamp(time, 0.0, anim.length)
	for j in db[name].joints:
		var tr: Array = anim.transform_track_interpolate(db[name].joints[j], t)
		out[j] = Basis(tr[1]).get_euler()
		if j == "Hips":
			out["_hips_y"] = tr[0].y - hips_rest_y
	return out

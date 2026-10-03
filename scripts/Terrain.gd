extends Spatial
# Procedural island: noise heightmap with flattened building zones, vertex
# colours (sand / grass / rock / dirt) and a trimesh collider.

const WATER_LEVEL := 0.0

var half := 160.0
var cell := 3.0
var noise := OpenSimplexNoise.new()
var detail := OpenSimplexNoise.new()
var ridge := OpenSimplexNoise.new()
var _zones := []      # Vector3(x, z, radius)
var _zone_h := []     # flattened height per zone
var _roads := []      # [Vector2 a, Vector2 b] segments (x, z)


func setup(map_half: float, seed_value: int, cell_size: float) -> void:
	half = map_half
	cell = cell_size
	noise.seed = seed_value
	noise.octaves = 3
	noise.period = 110.0
	noise.persistence = 0.5
	detail.seed = seed_value + 99
	detail.octaves = 2
	detail.period = 22.0
	ridge.seed = seed_value + 7
	ridge.octaves = 3
	ridge.period = 85.0
	ridge.persistence = 0.5


func raw_height(x: float, z: float) -> float:
	var h := 5.0 + noise.get_noise_2d(x, z) * 13.0 + detail.get_noise_2d(x, z) * 1.6
	var radial := Vector2(x, z).length() / half
	h -= smoothstep(0.62, 1.0, radial) * 30.0   # island falloff into the sea
	# mountain ranges: ridged noise, only well away from the town and the coast
	var m: float = 1.0 - abs(ridge.get_noise_2d(x, z))
	var range_w: float = smoothstep(0.26, 0.42, radial) * (1.0 - smoothstep(0.66, 0.84, radial))
	h += pow(max(m - 0.72, 0.0) / 0.28, 1.4) * 38.0 * range_w
	return h


# Biome wedges around the island centre: (snow, lava, desert) weights 0..1. The borders wobble with noise and
# everything near the town stays grassland.
const BIOMES := [[315.0, 44.0], [232.0, 30.0], [62.0, 42.0]]    # centre angle, half-width (degrees)


func biome_weights(x: float, z: float) -> Vector3:
	var radial := smoothstep(0.24, 0.44, Vector2(x, z).length() / half)
	if radial <= 0.0:
		return Vector3.ZERO
	var ang := rad2deg(atan2(z, x)) + detail.get_noise_2d(x * 0.6, z * 0.6) * 14.0
	var w := []
	for b in BIOMES:
		var d: float = abs(fposmod(ang - b[0] + 180.0, 360.0) - 180.0)
		w.append((1.0 - smoothstep(b[1] * 0.55, b[1], d)) * radial)
	return Vector3(w[0], w[1], w[2])


func add_zone(x: float, z: float, radius: float) -> void:
	_zones.append(Vector3(x, z, radius))
	_zone_h.append(raw_height(x, z))


func add_road(a: Vector2, b: Vector2) -> void:
	_roads.append([a, b])


func road_weight(x: float, z: float) -> float:
	var best := 99.0
	var p := Vector2(x, z)
	for r in _roads:
		var a: Vector2 = r[0]
		var ab: Vector2 = r[1] - a
		var t: float = clamp((p - a).dot(ab) / max(ab.length_squared(), 0.001), 0.0, 1.0)
		best = min(best, p.distance_to(a + ab * t))
	return 1.0 - smoothstep(1.6, 3.2, best)


func zone_weight(x: float, z: float) -> float:
	var best := 0.0
	for zn in _zones:
		var d := Vector2(x - zn.x, z - zn.y).length()
		best = max(best, 1.0 - smoothstep(zn.z * 0.75, zn.z, d))
	return best


func height_at(x: float, z: float) -> float:
	var h := raw_height(x, z)
	var land := smoothstep(-4.0, 1.0, h)      # zones never raise the open sea floor into a plateau
	for i in range(_zones.size()):
		var zn: Vector3 = _zones[i]
		var d := Vector2(x - zn.x, z - zn.y).length()
		var t := (1.0 - smoothstep(zn.z * 0.75, zn.z, d)) * land
		if t > 0.0:
			h = lerp(h, _zone_h[i], t)
	return h


func is_free(x: float, z: float, radius: float) -> bool:
	for zn in _zones:
		if Vector2(x - zn.x, z - zn.y).length() < zn.z + radius:
			return false
	return true


func build() -> void:
	var n := int(ceil(half * 2.0 / cell))
	var heights := []
	for i in range(n + 1):
		var row := []
		for j in range(n + 1):
			row.append(height_at(-half + i * cell, -half + j * cell))
		heights.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		for j in range(n):
			var a := _vertex(heights, i, j, n)
			var b := _vertex(heights, i + 1, j, n)
			var c := _vertex(heights, i + 1, j + 1, n)
			var d := _vertex(heights, i, j + 1, n)
			# Godot front faces are clockwise when seen from above.
			for v in [a, b, c, a, c, d]:
				st.add_color(v[1])
				st.add_normal(v[2])
				st.add_vertex(v[0])
	var mesh := st.commit()

	var mat := SpatialMaterial.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.params_cull_mode = SpatialMaterial.CULL_BACK
	var mi := MeshInstance.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "TerrainMesh"
	add_child(mi)

	var body := StaticBody.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _vertex(heights: Array, i: int, j: int, n: int) -> Array:
	var x := -half + i * cell
	var z := -half + j * cell
	var h: float = heights[i][j]
	var hl: float = heights[max(i - 1, 0)][j]
	var hr: float = heights[min(i + 1, n)][j]
	var hd: float = heights[i][max(j - 1, 0)]
	var hu: float = heights[i][min(j + 1, n)]
	var normal := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
	var slope := 1.0 - normal.y
	var tint := detail.get_noise_2d(x * 2.3, z * 2.3) * 0.06
	var col := Color(0.33 + tint, 0.60 + tint, 0.17)       # grass
	if h < 1.4:
		col = Color(0.76, 0.66, 0.43)                       # beach sand
	elif h > 13.0:
		col = col.linear_interpolate(Color(0.42, 0.55, 0.22), 0.5)
	if h > 19.0:       # bare rock high up, snow-capped on the very tops
		col = col.linear_interpolate(Color(0.52, 0.50, 0.47), clamp((h - 19.0) / 6.0, 0.0, 1.0))
		if h > 30.0:
			col = col.linear_interpolate(Color(0.95, 0.97, 1.0), clamp((h - 30.0) / 5.0, 0.0, 1.0))
	if slope > 0.22:
		col = col.linear_interpolate(Color(0.48, 0.45, 0.40), clamp((slope - 0.22) * 5.0, 0.0, 1.0))
	var bw := biome_weights(x, z)
	if bw.x > 0.0:      # snow
		col = col.linear_interpolate(Color(0.78, 0.88, 0.96) if h < 1.4 else Color(0.93 + tint, 0.96 + tint, 1.0), bw.x)
	if bw.y > 0.0:      # lava field: dark basalt cut by glowing cracks
		var lava := Color(0.17 + tint, 0.13, 0.12)
		var crack: float = abs(detail.get_noise_2d(x * 1.3 + 40.0, z * 1.3 - 17.0))
		if crack < 0.07 and h > 1.4:
			lava = Color(1.0, 0.38 + crack * 4.0, 0.04)
		col = col.linear_interpolate(lava, bw.y)
	if bw.z > 0.0:      # desert
		col = col.linear_interpolate(Color(0.86 + tint, 0.68 + tint, 0.38), bw.z)
	if slope > 0.22:
		var rock := Color(0.48, 0.45, 0.40)
		rock = rock.linear_interpolate(Color(0.85, 0.9, 0.96), bw.x).linear_interpolate(Color(0.10, 0.08, 0.08), bw.y).linear_interpolate(Color(0.62, 0.38, 0.22), bw.z)
		col = col.linear_interpolate(rock, clamp((slope - 0.22) * 5.0, 0.0, 1.0) * max(bw.x, max(bw.y, bw.z)))
	var zw := zone_weight(x, z)
	if zw > 0.0 and h > 1.4:
		col = col.linear_interpolate(Color(0.50, 0.47, 0.33), zw * 0.65)   # packed dirt around buildings
	if not _roads.empty() and h > 1.2:
		var rw := road_weight(x, z)
		if rw > 0.0:
			col = col.linear_interpolate(Color(0.55, 0.49, 0.38), rw * 0.92)   # dirt roads
	return [Vector3(x, h, z), col, normal]

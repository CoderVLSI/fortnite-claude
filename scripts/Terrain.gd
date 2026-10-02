extends Spatial
# Procedural island: noise heightmap with flattened building zones, vertex
# colours (sand / grass / rock / dirt) and a trimesh collider.

const WATER_LEVEL := 0.0

var half := 160.0
var cell := 3.0
var noise := OpenSimplexNoise.new()
var detail := OpenSimplexNoise.new()
var _zones := []      # Vector3(x, z, radius)
var _zone_h := []     # flattened height per zone


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


func raw_height(x: float, z: float) -> float:
	var h := 5.0 + noise.get_noise_2d(x, z) * 13.0 + detail.get_noise_2d(x, z) * 1.6
	var radial := Vector2(x, z).length() / half
	h -= smoothstep(0.62, 1.0, radial) * 30.0   # island falloff into the sea
	return h


func add_zone(x: float, z: float, radius: float) -> void:
	_zones.append(Vector3(x, z, radius))
	_zone_h.append(raw_height(x, z))


func zone_weight(x: float, z: float) -> float:
	var best := 0.0
	for zn in _zones:
		var d := Vector2(x - zn.x, z - zn.y).length()
		best = max(best, 1.0 - smoothstep(zn.z * 0.75, zn.z, d))
	return best


func height_at(x: float, z: float) -> float:
	var h := raw_height(x, z)
	for i in range(_zones.size()):
		var zn: Vector3 = _zones[i]
		var d := Vector2(x - zn.x, z - zn.y).length()
		var t := 1.0 - smoothstep(zn.z * 0.75, zn.z, d)
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
	if slope > 0.22:
		col = col.linear_interpolate(Color(0.48, 0.45, 0.40), clamp((slope - 0.22) * 5.0, 0.0, 1.0))
	var zw := zone_weight(x, z)
	if zw > 0.0 and h > 1.4:
		col = col.linear_interpolate(Color(0.50, 0.47, 0.33), zw * 0.65)   # packed dirt around buildings
	return [Vector3(x, h, z), col, normal]

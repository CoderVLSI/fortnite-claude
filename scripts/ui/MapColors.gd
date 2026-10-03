extends Reference
# Terrain colours for the minimap and the big map: sea, beach, grass, the snow / lava / desert biomes and the mountains.


static func color_at(terrain, x: float, z: float) -> Color:
	var h: float = terrain.height_at(x, z)
	if h < -4.0:
		return Color(0.07, 0.25, 0.42)
	if h < 0.0:
		return Color(0.12, 0.42, 0.62)
	var b: Vector3 = terrain.biome_weights(x, z)
	var c := Color(0.40, 0.62, 0.30).linear_interpolate(Color(0.30, 0.52, 0.25), clamp(h / 9.0, 0.0, 1.0))
	if h < 1.4:
		c = Color(0.80, 0.72, 0.50)
	c = c.linear_interpolate(Color(0.92, 0.96, 1.0) if h >= 1.4 else Color(0.78, 0.88, 0.96), b.x)
	c = c.linear_interpolate(Color(0.42, 0.14, 0.10) if h >= 1.4 else Color(0.25, 0.15, 0.13), b.y)
	c = c.linear_interpolate(Color(0.90, 0.74, 0.42), b.z)
	if h > 9.0:
		c = c.linear_interpolate(Color(0.55, 0.52, 0.47), clamp((h - 9.0) / 14.0, 0.0, 0.9))
	if h > 30.0:
		c = c.linear_interpolate(Color(0.96, 0.98, 1.0), clamp((h - 30.0) / 6.0, 0.0, 1.0))
	return c


static func make_texture(terrain, n: int) -> ImageTexture:
	var img := Image.new()
	img.create(n, n, false, Image.FORMAT_RGB8)
	img.lock()
	var half: float = terrain.half
	for j in range(n):
		for i in range(n):
			img.set_pixel(i, j, color_at(terrain, -half + (float(i) + 0.5) / n * half * 2.0, -half + (float(j) + 0.5) / n * half * 2.0))
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex

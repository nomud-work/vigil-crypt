## Procedural PBR surface library. Every map is synthesised from seeded noise:
## height field -> albedo, roughness, and a Sobel-derived normal map.
## Mirrors The Ninth Vigil's AssetForge (base pattern + mid structure + micro
## detail + grime that is coupled into albedo AND roughness together).
class_name TexGen
extends RefCounted

static func _noise(seed: int, freq: float, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, oct := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	return n

## Seamless noise image -> float array in 0..1
static func _field(n: Noise, size: int) -> PackedFloat32Array:
	var img := n.get_seamless_image(size, size, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	var data := img.get_data()
	var out := PackedFloat32Array()
	out.resize(size * size)
	for i in size * size:
		out[i] = data[i] / 255.0
	return out

## Tangent-space normal map from a height field (3x3 Sobel, wraps for tiling).
static func sobel_normal(h: PackedFloat32Array, size: int, strength: float) -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	for y in size:
		var ym := ((y - 1 + size) % size) * size
		var y0 := y * size
		var yp := ((y + 1) % size) * size
		for x in size:
			var xm := (x - 1 + size) % size
			var xp := (x + 1) % size
			var dx := (h[ym + xp] + 2.0 * h[y0 + xp] + h[yp + xp]) - (h[ym + xm] + 2.0 * h[y0 + xm] + h[yp + xm])
			var dy := (h[yp + xm] + 2.0 * h[yp + x] + h[yp + xp]) - (h[ym + xm] + 2.0 * h[ym + x] + h[ym + xp])
			var n := Vector3(-dx * strength, -dy * strength, 1.0).normalized()
			var i := (y0 + x) * 3
			bytes[i] = int((n.x * 0.5 + 0.5) * 255.0)
			bytes[i + 1] = int((-n.y * 0.5 + 0.5) * 255.0) # Godot expects OpenGL-style (Y+)
			bytes[i + 2] = int((n.z * 0.5 + 0.5) * 255.0)
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _tex(bytes: PackedByteArray, size: int, fmt: int) -> ImageTexture:
	var img := Image.create_from_data(size, size, false, fmt, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0

## kind: "ashlar" (coursed wall blocks), "flag" (cellular floor slabs),
## "steel" (brushed plate), "cloth" (woven tabard), "wood"
static func make(kind: String, size: int, seed: int, tint: Color) -> StandardMaterial3D:
	var N := size * size
	var h := PackedFloat32Array(); h.resize(N)
	var alb := PackedByteArray(); alb.resize(N * 3)
	var rgh := PackedByteArray(); rgh.resize(N)
	var fine := _field(_noise(seed + 1, 0.06, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 5), size)
	var macro := _field(_noise(seed + 2, 0.008, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3), size)
	var cell: PackedFloat32Array
	var cell_id: PackedFloat32Array
	var metal := 0.0
	if kind == "flag":
		var c := _noise(seed + 3, 0.012, FastNoiseLite.TYPE_CELLULAR, 1)
		c.fractal_type = FastNoiseLite.FRACTAL_NONE
		c.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		cell = _field(c, size)
		c.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
		cell_id = _field(c, size)
	for y in size:
		for x in size:
			var i := y * size + x
			var u := float(x) / size
			var v := float(y) / size
			var f: float = fine[i]
			var m: float = macro[i]
			var height := 0.5
			var col := tint
			var rough := 0.8
			match kind:
				"ashlar":
					# 4 courses per tile, blocks 2:1, alternate courses offset by half
					var row := int(v * 4.0)
					var bu := u * 2.0 + (0.5 if row % 2 == 1 else 0.0)
					var bx := int(floor(bu)) % 2
					var fu := fposmod(bu, 1.0)
					var fv := fposmod(v * 4.0, 1.0)
					var edge: float = min(min(fu, 1.0 - fu) * 2.0, min(fv, 1.0 - fv) * 4.0)
					var mortar := smoothstep(0.0, 0.06, edge)
					var chip := smoothstep(0.03, 0.12, edge + (f - 0.5) * 0.08)
					height = mortar * (0.55 + 0.45 * chip) * (0.8 + 0.2 * f)
					var bt := _hash(bx + row * 7, row, seed) # per-block tint jitter
					col = tint * (0.78 + 0.35 * bt) * (0.8 + 0.4 * m)
					col = col.lerp(Color(0.12, 0.11, 0.1), 1.0 - mortar) # dark mortar
					rough = 0.92 - 0.1 * f
				"flag":
					var crack := smoothstep(0.0, 0.07, cell[i])
					height = crack * (0.6 + 0.4 * f)
					col = tint * (0.72 + 0.45 * cell_id[i]) * (0.75 + 0.5 * m)
					col = col.lerp(Color(0.07, 0.065, 0.06), 1.0 - crack)
					rough = 0.85 - 0.25 * (1.0 - m) # damp, smoother in low areas
				"steel":
					var s := sin((v * 160.0 + f * 6.0)) * 0.5 + 0.5 # brushed streaks
					height = 0.5 + 0.08 * s + 0.25 * (f - 0.5)
					col = tint * (0.85 + 0.15 * s)
					rough = 0.28 + 0.25 * f + 0.2 * m
					metal = 1.0
				"cloth":
					var wx := sin(u * TAU * 64.0) * 0.5 + 0.5
					var wy := sin(v * TAU * 64.0) * 0.5 + 0.5
					var weave := wx if (int(u * 64.0) + int(v * 64.0)) % 2 == 0 else wy
					height = 0.4 + 0.4 * weave + 0.2 * f
					col = tint * (0.8 + 0.25 * weave) * (0.75 + 0.5 * m)
					rough = 0.95
				"wood":
					var g := sin((u * 40.0 + f * 5.0 + m * 8.0)) * 0.5 + 0.5
					height = 0.5 + 0.3 * g
					col = tint * (0.6 + 0.5 * g)
					rough = 0.75
			# grime: settles where the surface is low and where macro noise says so;
			# darkens and roughens together (dry dust) - the coupled-wear rule.
			var grime := clampf((0.55 - height) * 1.4 + (m - 0.5) * 0.6, 0.0, 1.0)
			col = col.lerp(col * 0.45, grime)
			rough = clampf(rough + grime * 0.15, 0.0, 1.0)
			h[i] = height
			alb[i * 3] = int(clampf(col.r, 0, 1) * 255)
			alb[i * 3 + 1] = int(clampf(col.g, 0, 1) * 255)
			alb[i * 3 + 2] = int(clampf(col.b, 0, 1) * 255)
			rgh[i] = int(rough * 255)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex(alb, size, Image.FORMAT_RGB8)
	mat.normal_enabled = true
	mat.normal_texture = sobel_normal(h, size, 2.5 if kind != "steel" else 1.2)
	mat.normal_scale = 1.0
	mat.roughness_texture = _tex(rgh, size, Image.FORMAT_L8)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = 1.0
	mat.metallic = metal
	mat.metallic_specular = 0.5
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

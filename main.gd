## Vigil Crypt: a zero-asset crypt scene. Everything below is built at runtime: textures from
## noise, meshes from parametric patches, a skinned knight, shader flames, a
## fake volumetric moon shaft, and a synthesised soundtrack.
extends Node3D

const FPS := 30.0
var frame := 0
var knight: Knight
var cam: Camera3D
var torches := []
var timings := PackedFloat64Array()
var last_us := 0
var gen_ms := {}
var still_frames := {45: "still_1_wide.png", 135: "still_2_knight.png", 228: "still_3_closeup.png"}
var out_dir := "res://out/"

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var mats := {
		"flag": TexGen.make("flag", 512, 11, Color(0.42, 0.40, 0.37)),
		"ashlar": TexGen.make("ashlar", 512, 21, Color(0.50, 0.46, 0.41)),
		"steel": TexGen.make("steel", 256, 31, Color(0.62, 0.62, 0.64)),
		"mail": TexGen.make("steel", 128, 32, Color(0.22, 0.22, 0.23)),
		"cloth": TexGen.make("cloth", 256, 41, Color(0.42, 0.05, 0.04)),
		"leather": TexGen.make("wood", 128, 51, Color(0.20, 0.12, 0.07)),
		"wood": TexGen.make("wood", 128, 52, Color(0.28, 0.17, 0.09)),
	}
	mats.cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats.steel.metallic = 1.0
	mats.mail.metallic = 1.0
	gen_ms["textures"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_build_hall(mats)
	_build_torches(mats)
	_build_moon()
	gen_ms["hall"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	knight = Knight.new()
	knight.build(mats)
	add_child(knight)
	var key := OmniLight3D.new() # character key: lifts the knight off the backlit vault
	key.light_color = Color(1.0, 0.75, 0.55); key.light_energy = 0.9; key.omni_range = 4.5
	key.position = Vector3(-0.9, 2.1, 1.6)
	knight.add_child(key)
	gen_ms["knight"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_build_env()
	_build_audio()
	gen_ms["audio+env"] = Time.get_ticks_msec() - t0
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	print("GEN_MS ", gen_ms)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_update(0.0, 1.0 / FPS)

# ------------------------------------------------------------------ hall
func _build_hall(mats: Dictionary) -> void:
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 30)
	floor_mi.mesh = pm
	var fm: StandardMaterial3D = mats.flag
	fm.uv1_scale = Vector3(4.67, 10, 1) # one tile = 3 m
	floor_mi.material_override = fm
	add_child(floor_mi)
	var wm: StandardMaterial3D = mats.ashlar.duplicate()
	wm.uv1_triplanar = true
	wm.uv1_scale = Vector3(0.5, 0.5, 0.5) # one tile = 2 m (4 courses of 0.5 m)
	for x in [-6.5, 6.5]:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(1, 12, 30)
		w.mesh = bm; w.position = Vector3(x, 6, 0); w.material_override = wm
		add_child(w)
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new(); bb.size = Vector3(14, 12, 1)
	back.mesh = bb; back.position = Vector3(0, 6, -14.5); back.material_override = wm
	add_child(back)
	# fluted columns: one lathed mesh, instanced
	var col_mesh := _column_mesh(mats.ashlar)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = col_mesh
	var cols := []
	for z in range(-12, 13, 4):
		for x in [-3.5, 3.5]:
			cols.append(Vector3(x, 0, z))
	mm.instance_count = cols.size()
	for i in cols.size():
		mm.set_instance_transform(i, Transform3D(Basis().rotated(Vector3.UP, i * 0.7), cols[i]))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	add_child(mmi)
	# pointed arches with real voussoirs: arcade arches along z, ribs across x
	var vous := []
	for x in [-3.5, 3.5]:
		for z in range(-12, 12, 4):
			vous.append_array(_pointed_arch(Vector3(x, 4.25, z + 0.5), Vector3(x, 4.25, z + 3.5), 11, Vector3(0.55, 0.42, 0)))
	for z in range(-12, 13, 4):
		vous.append_array(_pointed_arch(Vector3(-3.0, 4.25, z), Vector3(3.0, 4.25, z), 19, Vector3(0.3, 0.38, 0)))
	var bmesh := BoxMesh.new(); bmesh.size = Vector3(1, 1, 1)
	var am: StandardMaterial3D = mats.ashlar.duplicate()
	am.uv1_triplanar = true; am.uv1_world_triplanar = true; am.uv1_scale = Vector3(0.5, 0.5, 0.5)
	bmesh.material = am
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = bmesh
	mm2.instance_count = vous.size()
	for i in vous.size():
		mm2.set_instance_transform(i, vous[i])
	var mmi2 := MultiMeshInstance3D.new(); mmi2.multimesh = mm2
	add_child(mmi2)
	print("COLUMNS ", cols.size(), " VOUSSOIRS ", vous.size())

func _column_mesh(stone: StandardMaterial3D) -> ArrayMesh:
	# radius profile (y, r): plinth, torus base, fluted shaft, flared capital, abacus
	var prof := [[0.0, 0.62], [0.35, 0.62], [0.37, 0.52], [0.45, 0.50], [0.55, 0.42], [0.62, 0.36],
		[3.55, 0.33], [3.70, 0.40], [3.95, 0.52], [4.02, 0.60], [4.25, 0.60]]
	var P := func(u: float, v: float) -> Vector3:
		var y := v * 4.25
		var r := 0.6
		for k in prof.size() - 1:
			if y >= prof[k][0] and y <= prof[k + 1][0]:
				var f: float = (y - prof[k][0]) / maxf(prof[k + 1][0] - prof[k][0], 1e-4)
				r = lerpf(prof[k][1], prof[k + 1][1], smoothstep(0.0, 1.0, f))
				break
		var th := u * TAU
		var flute := 1.0 - 0.07 * pow(absf(cos(th * 6.0)), 3.0) * smoothstep(0.6, 0.8, y) * (1.0 - smoothstep(3.4, 3.55, y))
		if y < 0.36 or y > 4.0: # square-ish plinth and abacus
			var sq := 1.0 / maxf(absf(cos(th)), absf(sin(th)))
			flute = lerpf(1.0, minf(sq, 1.35), 0.85)
		return Vector3(cos(th) * r * flute, y, sin(th) * r * flute)
	var st := Geo.new_st(false)
	Geo.patch(st, P, 72, 90, [], Callable(), Vector2(1.6, 2.1))
	var m := ArrayMesh.new()
	var cm: StandardMaterial3D = stone.duplicate()
	cm.uv1_scale = Vector3(1, 1, 1)
	Geo.finish(st, m, cm)
	return m

## Equilateral (two-centred) pointed arch from springing a to b: each half is an
## arc centred on the opposite springing point. Returns voussoir transforms.
func _pointed_arch(a: Vector3, b: Vector3, n: int, size: Vector3) -> Array:
	var out := []
	var span := a.distance_to(b)
	var axis := (b - a).normalized()
	var pts := []
	var steps := n * 4
	for half in [0, 1]:
		var c: Vector3 = b if half == 0 else a
		var start: Vector3 = a if half == 0 else b
		for k in steps + 1:
			var ang := (PI / 3.0) * float(k) / steps
			var dirv: Vector3 = ((start - c).normalized() * cos(ang) + Vector3.UP * sin(ang))
			pts.append([half, c + dirv * span, dirv])
	# place n voussoirs per half along each arc
	var per := int(n / 2) + 1
	for half in [0, 1]:
		for k in per:
			var f0 := float(k) / per
			var f1 := float(k + 1) / per
			var ang0 := (PI / 3.0) * f0
			var ang1 := (PI / 3.0) * f1
			var c: Vector3 = b if half == 0 else a
			var start: Vector3 = a if half == 0 else b
			var r0 := (start - c).normalized()
			var mid := (ang0 + ang1) * 0.5
			var radial := r0 * cos(mid) + Vector3.UP * sin(mid)
			var tangent := (-r0 * sin(mid) + Vector3.UP * cos(mid)).normalized()
			var side := radial.cross(tangent).normalized()
			var len := span * (ang1 - ang0) * 0.96
			var p := c + radial * (span + size.y * 0.5 - size.y * 0.5)
			var basis := Basis(side * size.x, radial * size.y, tangent * len)
			out.append(Transform3D(basis, p))
	return out

# ------------------------------------------------------------------ torches
func _build_torches(mats: Dictionary) -> void:
	var flame_sh := Shader.new(); flame_sh.code = Shaders.FLAME
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1)); grad.set_color(1, Color(1, 1, 1, 0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad; gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5); gtex.fill_to = Vector2(0.5, 0.0)
	gtex.width = 32; gtex.height = 32
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	ember_mat.vertex_color_use_as_albedo = true
	ember_mat.albedo_texture = gtex
	ember_mat.albedo_color = Color(4.0, 1.6, 0.4)
	ember_mat.no_depth_test = false
	var i := 0
	for z in [-8, 0, 8]:
		for x in [-3.5, 3.5]:
			var root := Node3D.new()
			var face: float = -signf(x)
			root.position = Vector3(x + face * 0.62, 2.35, float(z))
			add_child(root)
			var st := Geo.new_st(false)
			Geo.limb(st, Vector3(-face * 0.1, -0.25, 0), Vector3(face * 0.08, 0.15, 0), Vector2(0.03, 0.03), Vector2(0.04, 0.04), [], 0.1, 0.2, 10, 8)
			var m := ArrayMesh.new(); Geo.finish(st, m, mats.wood)
			var st2 := Geo.new_st(false)
			Geo.limb(st2, Vector3(face * 0.08, 0.10, 0), Vector3(face * 0.1, 0.24, 0), Vector2(0.05, 0.05), Vector2(0.085, 0.085), [], 0.05, 0.05, 14, 6)
			Geo.finish(st2, m, mats.mail)
			var h := MeshInstance3D.new(); h.mesh = m; root.add_child(h)
			var fl := MeshInstance3D.new()
			var q := QuadMesh.new(); q.size = Vector2(0.34, 0.62)
			fl.mesh = q
			var fm := ShaderMaterial.new(); fm.shader = flame_sh; fm.set_shader_parameter("seed", i * 3.7)
			fl.material_override = fm
			fl.position = Vector3(face * 0.1, 0.5, 0)
			root.add_child(fl)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.58, 0.26)
			l.omni_range = 8.0
			l.omni_attenuation = 1.6
			l.light_energy = 2.2
			l.position = Vector3(face * 0.25, 0.45, 0)
			root.add_child(l)
			var p := CPUParticles3D.new()
			p.amount = 18; p.lifetime = 1.8; p.preprocess = 2.0
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = 0.06
			p.direction = Vector3.UP; p.spread = 22.0
			p.gravity = Vector3(0.15, 0.5, 0); p.initial_velocity_min = 0.25; p.initial_velocity_max = 0.7
			p.scale_amount_min = 0.5; p.scale_amount_max = 1.2
			var cr := Gradient.new(); cr.set_color(0, Color(1, 0.8, 0.4, 1)); cr.set_color(1, Color(1, 0.2, 0.0, 0))
			p.color_ramp = cr
			var pq := QuadMesh.new(); pq.size = Vector2(0.035, 0.035); pq.material = ember_mat
			p.mesh = pq
			p.position = Vector3(face * 0.1, 0.45, 0)
			p.randomness = 1.0
			p.seed = 1000 + i
			p.use_fixed_seed = true
			root.add_child(p)
			torches.append([l, float(i) * 1.37])
			i += 1

func _build_moon() -> void:
	var s := SpotLight3D.new()
	s.position = Vector3(0.6, 14.0, -0.5)
	s.rotation_degrees = Vector3(-90, 0, 0)
	s.light_color = Color(0.62, 0.72, 1.0)
	s.light_energy = 3.2
	s.spot_range = 20.0
	s.spot_angle = 9.0
	s.spot_attenuation = 0.4
	s.shadow_enabled = true
	add_child(s)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35; cm.bottom_radius = 2.4; cm.height = 14.0
	cm.radial_segments = 48; cm.cap_top = false; cm.cap_bottom = false
	cone.mesh = cm
	var sh := Shader.new(); sh.code = Shaders.SHAFT
	var m := ShaderMaterial.new(); m.shader = sh
	cone.material_override = m
	cone.position = Vector3(0.6, 7.0, -0.5)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)

# ------------------------------------------------------------------ env/post
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.10, 0.14)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.08, 0.07)
	env.fog_density = 0.035
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.92
	var we := WorldEnvironment.new(); we.environment = env
	add_child(we)
	var layer := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new(); sh.code = Shaders.GRADE
	var m := ShaderMaterial.new(); m.shader = sh
	rect.material = m
	layer.add_child(rect)
	add_child(layer)

# ------------------------------------------------------------------ audio
## 9 s of 22.05 kHz mono synthesised in code: detuned-saw drone through a
## one-pole lowpass, torch crackle, footstep clanks synced to the walk cycle,
## and two comb-filter "room" echoes.
func _build_audio() -> void:
	var sr := 22050
	var n := sr * 9
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var lp := 0.0
	var steps := []
	var st := 0.275
	while st < 9.0:
		steps.append(st); st += Knight.PERIOD * 0.5
	for i in n:
		var t := float(i) / sr
		var saw := fposmod(t * 73.42, 1.0) * 2.0 - 1.0 + fposmod(t * 73.9, 1.0) * 2.0 - 1.0
		var cut := 0.02 + 0.015 * sin(t * 0.7)
		lp += (saw - lp) * cut
		var swell := smoothstep(0.0, 2.0, t) * (0.8 + 0.2 * sin(t * 0.9))
		var v := lp * 0.16 * swell + sin(TAU * 36.71 * t) * 0.10 * swell
		v += (sin(TAU * 110.0 * t) * 0.6 + sin(TAU * 174.6 * t) * 0.4) * 0.025 * (0.5 + 0.5 * sin(t * 0.45))
		buf[i] = v
	# crackle: sparse noise bursts
	var k := 0
	while k < n:
		k += int(rng.randf_range(0.02, 0.18) * sr)
		var dur := int(rng.randf_range(0.003, 0.02) * sr)
		var amp := rng.randf_range(0.03, 0.12)
		for j in dur:
			if k + j < n:
				buf[k + j] += rng.randf_range(-1, 1) * amp * exp(-6.0 * j / dur)
	# footsteps: inharmonic metal partials + low thud
	var partials := [[480.0, 7.0], [1210.0, 11.0], [2050.0, 16.0], [3310.0, 22.0]]
	for s in steps:
		var i0 := int(s * sr)
		var len := int(0.5 * sr)
		var pitch := 1.0 + rng.randf_range(-0.04, 0.04)
		for j in len:
			if i0 + j >= n: break
			var tt := float(j) / sr
			var v := 0.0
			for p in partials:
				v += sin(TAU * p[0] * pitch * tt) * exp(-p[1] * tt) * 0.05
			v += sin(TAU * 62.0 * tt) * exp(-30.0 * tt) * 0.35
			buf[i0 + j] += v
	# room: two feedback combs
	for d in [[int(0.113 * sr), 0.32], [int(0.171 * sr), 0.24]]:
		var dl: int = d[0]
		var fb: float = d[1]
		for i in range(dl, n):
			buf[i] += buf[i - dl] * fb
	var bytes := PackedByteArray(); bytes.resize(n * 2)
	var peak := 0.0
	for i in n: peak = maxf(peak, absf(buf[i]))
	var g := 0.8 / maxf(peak, 1e-6)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = bytes
	var pl := AudioStreamPlayer.new(); pl.stream = wav; pl.volume_db = -2.0
	add_child(pl)
	pl.play()

# ------------------------------------------------------------------ per frame
func _knight_pos(t: float) -> Vector3:
	return Vector3(0.25 * sin(t * 0.5), 0.0, -6.0 + 1.1 * t)

func _hermite(a: Vector3, b: Vector3, f: float) -> Vector3:
	return a.lerp(b, smoothstep(0.0, 1.0, f))

func _update(t: float, dt: float) -> void:
	var kp := _knight_pos(t)
	var ahead := _knight_pos(t + 0.1)
	knight.position = kp
	knight.rotation.y = atan2(ahead.x - kp.x, ahead.z - kp.z)
	knight.pose(t, dt)
	for tr in torches:
		var l: OmniLight3D = tr[0]
		var ph: float = tr[1]
		l.light_energy = 2.2 * (1.0 + 0.10 * sin(t * 7.3 + ph) + 0.07 * sin(t * 13.1 + ph * 2.0) + 0.05 * sin(t * 23.7 + ph * 3.0))
	# camera: three keys, smooth blends
	var k0p := Vector3(2.6, 1.5, 6.5); var k0l := Vector3(0, 2.4, -8)
	var k1p := kp + Vector3(1.9, 1.45, 2.8); var k1l := kp + Vector3(0, 1.3, 0)
	var k2p := kp + Vector3(-1.2, 0.85, 2.0); var k2l := kp + Vector3(0.2, 1.7, -1.5)
	var p: Vector3; var lk: Vector3
	if t < 4.0:
		var f := t / 4.0
		p = _hermite(k0p, k1p, f); lk = _hermite(k0l, k1l, f)
	else:
		var f := clampf((t - 4.0) / 3.6, 0.0, 1.0)
		p = _hermite(k1p, k2p, f); lk = _hermite(k1l, k2l, f)
	cam.look_at_from_position(p, lk, Vector3.UP)

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if last_us > 0:
		timings.append((now - last_us) / 1000.0)
	last_us = now
	frame += 1
	_update(frame / FPS, 1.0 / FPS)
	if still_frames.has(frame - 1):
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir + still_frames[frame - 1])
		print("STILL ", still_frames[frame - 1])
	if frame % 30 == 0:
		print("FRAME ", frame)

func _exit_tree() -> void:
	if timings.size() == 0: return
	var s: PackedFloat64Array = timings.duplicate(); s.sort()
	var tot := 0.0
	for x in s: tot += x
	print("FRAME_MS mean=%.1f median=%.1f p95=%.1f max=%.1f n=%d" % [tot / s.size(), s[s.size() / 2], s[int(s.size() * 0.95)], s[s.size() - 1], s.size()])

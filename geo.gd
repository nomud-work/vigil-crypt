## Procedural geometry kit: parametric patches -> SurfaceTool, with optional
## skin weights. Normals come from finite differences of the patch function, so
## every curved surface is shaded exactly (no faceting, no seam).
class_name Geo
extends RefCounted

## P(u, v) -> Vector3, u across/around, v along. closed_u wraps the seam.
## bones = [b0, b1]; wfn(u, v) -> weight of b1 (0 = rigid on b0).
static func patch(st: SurfaceTool, P: Callable, nu: int, nv: int, bones := [0, 0], wfn := Callable(), uvs := Vector2(1, 1), closed_u := true) -> void:
	var pos := []
	var centroid := Vector3.ZERO
	for j in nv + 1:
		for i in nu + 1:
			var p: Vector3 = P.call(float(i) / nu, float(j) / nv)
			pos.append(p)
			centroid += p
	centroid /= pos.size()
	var e := 0.002
	var base := st_count(st)
	var flip_sum := 0.0
	var norms := []
	for j in nv + 1:
		for i in nu + 1:
			var u := float(i) / nu
			var v := float(j) / nv
			var du: Vector3 = P.call(fposmod(u + e, 1.0) if closed_u else minf(u + e, 1.0), v) - P.call(fposmod(u - e, 1.0) if closed_u else maxf(u - e, 0.0), v)
			var dv: Vector3 = P.call(u, minf(v + e, 1.0)) - P.call(u, maxf(v - e, 0.0))
			var n := du.cross(dv)
			if n.length_squared() < 1e-14:
				n = pos[j * (nu + 1) + i] - centroid
			n = n.normalized()
			flip_sum += n.dot(pos[j * (nu + 1) + i] - centroid)
			norms.append(n)
	var sgn := 1.0 if flip_sum >= 0.0 or not closed_u else -1.0
	for j in nv + 1:
		for i in nu + 1:
			var k := j * (nu + 1) + i
			var u := float(i) / nu
			var v := float(j) / nv
			st.set_normal(norms[k] * sgn)
			st.set_uv(Vector2(u * uvs.x, v * uvs.y))
			var w := 0.0
			if wfn.is_valid():
				w = wfn.call(u, v)
			if bones.size() > 0:
				st.set_bones(PackedInt32Array([bones[0], bones[1], 0, 0]))
				st.set_weights(PackedFloat32Array([1.0 - w, w, 0.0, 0.0]))
			st.add_vertex(pos[k])
			_counts[st] = _counts.get(st, 0) + 1
	# winding: Godot front faces are clockwise
	for j in nv:
		for i in nu:
			var a := base + j * (nu + 1) + i
			var b := a + 1
			var c := a + (nu + 1)
			var d := c + 1
			var pa: Vector3 = pos[a - base]
			var nrm: Vector3 = norms[a - base] * sgn
			var cr: Vector3 = (pos[b - base] - pa).cross(pos[c - base] - pa)
			if cr.dot(nrm) > 0.0:
				st.add_index(a); st.add_index(c); st.add_index(b)
				st.add_index(b); st.add_index(c); st.add_index(d)
			else:
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(b); st.add_index(d); st.add_index(c)

static var _counts := {}
static func st_count(st: SurfaceTool) -> int:
	return _counts.get(st, 0)

static func frame(d: Vector3) -> Array:
	var ref := Vector3.RIGHT
	if absf(d.dot(ref)) > 0.9:
		ref = Vector3.BACK
	var e1 := (ref - d * d.dot(ref)).normalized()
	var e2 := d.cross(e1).normalized()
	return [e1, e2]

## Rounded limb / plate from a to b: elliptical section (rx, rz), radius tapers
## ra->rb, ends close with profile exponent ex (0.5 = ellipsoid, small = capsule).
static func limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: Vector2, rb: Vector2, bones := [0, 0], ex := 0.18, cap := 0.5, nu := 16, nv := 12, wfn := Callable()) -> void:
	var d := (b - a).normalized()
	var L := a.distance_to(b)
	var f := frame(d)
	var e1: Vector3 = f[0]
	var e2: Vector3 = f[1]
	var a2 := a - d * ra.x * cap
	var L2 := L + (ra.x + rb.x) * cap
	var P := func(u: float, v: float) -> Vector3:
		var th := u * TAU
		var prof := pow(maxf(4.0 * v * (1.0 - v), 0.0), ex)
		var r := ra.lerp(rb, v) * prof
		return a2 + d * (L2 * v) + e1 * (cos(th) * r.x) + e2 * (sin(th) * r.y)
	patch(st, P, nu, nv, bones, wfn, Vector2(1.0, L2 * 2.0))

static func ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, bones := [0, 0], nu := 18, nv := 12) -> void:
	var P := func(u: float, v: float) -> Vector3:
		var th := u * TAU
		var ph := v * PI
		return c + Vector3(sin(ph) * cos(th) * r.x, -cos(ph) * r.y, sin(ph) * sin(th) * r.z)
	patch(st, P, nu, nv, bones, Callable(), Vector2(2, 1))

static func finish(st: SurfaceTool, mesh: ArrayMesh, mat: Material) -> void:
	st.generate_tangents()
	st.set_material(mat)
	st.commit(mesh)
	_counts.erase(st)

static func new_st(skinned := true) -> SurfaceTool:
	var st := SurfaceTool.new()
	if skinned:
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

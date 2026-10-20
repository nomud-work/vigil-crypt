## Procedural knight: a Skeleton3D authored from a joint table (identity rest
## rotations, like The Ninth Vigil's Skeleton.js), skinned plate armour built
## from parametric patches, and a code-driven walk cycle + spring-lagged cape.
class_name Knight
extends Node3D

var sk: Skeleton3D
var B := {}
var t := 0.0
var cape_ang := 0.0
var cape_vel := 0.0
const PERIOD := 1.1

func build(mats: Dictionary) -> void:
	var J := [
		["pelvis", "", Vector3(0, 0.98, 0)],
		["spine", "pelvis", Vector3(0, 1.20, 0.01)],
		["chest", "spine", Vector3(0, 1.40, 0.0)],
		["neck", "chest", Vector3(0, 1.55, -0.01)],
		["head", "neck", Vector3(0, 1.63, 0.01)],
		["cape", "chest", Vector3(0, 1.49, -0.15)],
	]
	for s in [["L", 1.0], ["R", -1.0]]:
		var n: String = s[0]
		var x: float = s[1]
		J.append(["upperarm_" + n, "chest", Vector3(x * 0.215, 1.45, 0.0)])
		J.append(["forearm_" + n, "upperarm_" + n, Vector3(x * 0.27, 1.16, 0.02)])
		J.append(["hand_" + n, "forearm_" + n, Vector3(x * 0.30, 0.91, 0.05)])
		J.append(["thigh_" + n, "pelvis", Vector3(x * 0.10, 0.94, 0.0)])
		J.append(["shin_" + n, "thigh_" + n, Vector3(x * 0.11, 0.52, 0.02)])
		J.append(["foot_" + n, "shin_" + n, Vector3(x * 0.11, 0.10, -0.01)])
	sk = Skeleton3D.new()
	var gpos := {}
	for j in J:
		var idx := sk.add_bone(j[0])
		B[j[0]] = idx
		gpos[j[0]] = j[2]
		var ppos := Vector3.ZERO
		if j[1] != "":
			sk.set_bone_parent(idx, B[j[1]])
			ppos = gpos[j[1]]
		sk.set_bone_rest(idx, Transform3D(Basis(), j[2] - ppos))
	sk.reset_bone_poses()
	add_child(sk)

	var mesh := ArrayMesh.new()
	var steel := Geo.new_st()
	var dark := Geo.new_st()
	var cloth := Geo.new_st()
	var leather := Geo.new_st()
	var b := func(n: String) -> Array: return [B[n], B[n]]
	# torso: abdomen + breastplate (two lames) + fauld + gorget
	Geo.limb(steel, Vector3(0, 1.02, 0.0), Vector3(0, 1.30, 0.01), Vector2(0.155, 0.12), Vector2(0.17, 0.13), b.call("spine"), 0.12, 0.2)
	Geo.limb(steel, Vector3(0, 1.22, 0.01), Vector3(0, 1.53, 0.0), Vector2(0.185, 0.145), Vector2(0.2, 0.13), b.call("chest"), 0.16, 0.25)
	Geo.limb(steel, Vector3(0, 0.84, 0.0), Vector3(0, 1.04, 0.0), Vector2(0.185, 0.14), Vector2(0.16, 0.125), b.call("pelvis"), 0.1, 0.1)
	Geo.limb(leather, Vector3(0, 0.99, 0.0), Vector3(0, 1.04, 0.0), Vector2(0.172, 0.135), Vector2(0.172, 0.135), b.call("pelvis"), 0.04, 0.05)
	Geo.limb(dark, Vector3(0, 1.50, -0.01), Vector3(0, 1.62, 0.0), Vector2(0.085, 0.08), Vector2(0.07, 0.07), b.call("neck"), 0.1, 0.1)
	# great helm + visor slit + crest
	Geo.ellipsoid(steel, Vector3(0, 1.74, 0.01), Vector3(0.115, 0.145, 0.13), b.call("head"))
	Geo.limb(dark, Vector3(-0.08, 1.765, 0.105), Vector3(0.08, 1.765, 0.105), Vector2(0.012, 0.03), Vector2(0.012, 0.03), b.call("head"), 0.2, 0.1, 10, 8)
	Geo.limb(cloth, Vector3(0, 1.86, 0.09), Vector3(0, 1.80, -0.17), Vector2(0.018, 0.04), Vector2(0.01, 0.025), b.call("head"), 0.3, 0.3, 10, 10)
	for s in [["L", 1.0], ["R", -1.0]]:
		var n: String = s[0]
		var x: float = s[1]
		# layered pauldron lames
		Geo.ellipsoid(steel, Vector3(x * 0.25, 1.47, 0.0), Vector3(0.11, 0.075, 0.115), b.call("upperarm_" + n))
		Geo.ellipsoid(steel, Vector3(x * 0.265, 1.42, 0.0), Vector3(0.10, 0.065, 0.11), b.call("upperarm_" + n))
		Geo.limb(dark, Vector3(x * 0.22, 1.42, 0.0), Vector3(x * 0.27, 1.17, 0.02), Vector2(0.05, 0.05), Vector2(0.045, 0.045), b.call("upperarm_" + n))
		Geo.ellipsoid(steel, Vector3(x * 0.272, 1.16, 0.02), Vector3(0.055, 0.055, 0.06), b.call("forearm_" + n))
		Geo.limb(steel, Vector3(x * 0.27, 1.15, 0.02), Vector3(x * 0.30, 0.93, 0.05), Vector2(0.046, 0.046), Vector2(0.04, 0.04), b.call("forearm_" + n))
		Geo.ellipsoid(leather, Vector3(x * 0.305, 0.86, 0.055), Vector3(0.04, 0.07, 0.048), b.call("hand_" + n))
		# legs: cuisse, poleyn, greave, sabaton
		Geo.limb(steel, Vector3(x * 0.10, 0.92, 0.0), Vector3(x * 0.11, 0.54, 0.02), Vector2(0.085, 0.085), Vector2(0.062, 0.062), b.call("thigh_" + n))
		Geo.ellipsoid(steel, Vector3(x * 0.11, 0.52, 0.045), Vector3(0.06, 0.065, 0.06), b.call("shin_" + n))
		Geo.limb(steel, Vector3(x * 0.11, 0.50, 0.02), Vector3(x * 0.11, 0.12, -0.01), Vector2(0.058, 0.06), Vector2(0.042, 0.045), b.call("shin_" + n))
		Geo.limb(steel, Vector3(x * 0.11, 0.07, -0.05), Vector3(x * 0.11, 0.045, 0.16), Vector2(0.048, 0.04), Vector2(0.038, 0.025), b.call("foot_" + n), 0.2, 0.3)
	# tabard front + back, hanging from the chest
	var tab := func(zs: float) -> Callable:
		return func(u: float, v: float) -> Vector3:
			var w := lerpf(0.13, 0.17, v)
			var x := lerpf(-w, w, u)
			var y := lerpf(1.36, 0.60, v)
			var z := zs * (0.155 + 0.05 * v + 0.012 * sin(u * PI))
			return Vector3(x, y, z)
	Geo.patch(cloth, tab.call(1.0), 8, 10, b.call("pelvis"), Callable(), Vector2(1, 2), false)
	Geo.patch(cloth, tab.call(-1.0), 8, 10, b.call("pelvis"), Callable(), Vector2(1, 2), false)
	# cape: folded sheet; weights blend chest -> cape bone down its length
	var capeP := func(u: float, v: float) -> Vector3:
		var w := lerpf(0.21, 0.42, v)
		var x := lerpf(-w, w, u)
		var y := lerpf(1.52, 0.32, v)
		var z := -0.15 - 0.10 * v - 0.07 * sin(u * PI) * (1.0 - 0.5 * v) + 0.03 * sin(u * PI * 7.0) * v
		return Vector3(x, y, z)
	Geo.patch(cloth, capeP, 24, 16, [B["chest"], B["cape"]], func(u, v): return clampf(v * 1.4, 0.0, 1.0), Vector2(2, 3), false)
	# sword in scabbard at the left hip
	Geo.limb(leather, Vector3(0.20, 0.95, 0.08), Vector3(0.25, 0.20, -0.20), Vector2(0.03, 0.014), Vector2(0.022, 0.01), b.call("pelvis"), 0.1, 0.3, 10, 10)
	Geo.limb(steel, Vector3(0.12, 0.99, 0.1), Vector3(0.28, 0.97, 0.06), Vector2(0.012, 0.012), Vector2(0.012, 0.012), b.call("pelvis"), 0.2, 0.3, 8, 6)
	Geo.limb(leather, Vector3(0.195, 0.98, 0.09), Vector3(0.17, 1.10, 0.14), Vector2(0.014, 0.014), Vector2(0.014, 0.014), b.call("pelvis"), 0.1, 0.2, 8, 6)
	Geo.ellipsoid(steel, Vector3(0.167, 1.115, 0.145), Vector3(0.024, 0.024, 0.024), b.call("pelvis"), 10, 8)

	Geo.finish(steel, mesh, mats.steel)
	Geo.finish(dark, mesh, mats.mail)
	Geo.finish(cloth, mesh, mats.cloth)
	Geo.finish(leather, mesh, mats.leather)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = sk.create_skin_from_rest_transforms()

func rot(n: String, x: float, y := 0.0, z := 0.0) -> void:
	sk.set_bone_pose_rotation(B[n], Quaternion.from_euler(Vector3(x, y, z)))

## Walk cycle as pure functions of phase. Negative X rotation swings a limb forward.
func pose(time: float, dt: float) -> void:
	t = time
	var ph := TAU * time / PERIOD
	var s := sin(ph)
	var c := cos(ph)
	rot("thigh_L", -0.36 * s)
	rot("thigh_R", 0.36 * s)
	rot("shin_L", 0.05 + 0.75 * maxf(0.0, -c) * maxf(0.0, s * 0.5 + 0.6))
	rot("shin_R", 0.05 + 0.75 * maxf(0.0, c) * maxf(0.0, -s * 0.5 + 0.6))
	rot("foot_L", 0.2 * s * 0.5)
	rot("foot_R", -0.2 * s * 0.5)
	rot("upperarm_L", 0.28 * s, 0.0, 0.08)
	rot("upperarm_R", -0.28 * s, 0.0, -0.08)
	rot("forearm_L", -0.25 + 0.12 * s)
	rot("forearm_R", -0.25 - 0.12 * s)
	rot("pelvis", 0.0, 0.07 * s, 0.03 * c)
	rot("chest", 0.05, -0.09 * s, -0.02 * c)
	rot("head", -0.04, 0.05 * s, 0.0)
	var bob := -0.035 * absf(c) + 0.015
	sk.set_bone_pose_position(B["pelvis"], Vector3(0, 0.98 + bob, 0))
	# cape: damped spring toward a flare driven by walk speed + step impulses
	var target := 0.22 + 0.05 * sin(ph * 2.0)
	cape_vel += ((target - cape_ang) * 40.0 - cape_vel * 6.0) * dt
	cape_ang += cape_vel * dt
	rot("cape", cape_ang, 0.0, 0.03 * s)

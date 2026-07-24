class_name KernBodyBuilder
extends RefCounted
## Builds Kern's articulated body: a code-authored Skeleton3D at true
## life-size proportions (1.78 m, ~7.5 heads), smooth-skinned clothing lofts
## (tunic, sleeves, trousers), the skin of the neck, and fully sculpted rigid
## hands — five fingers with three segments each, knuckle bumps, nails, palm
## creases, and the canon glowing hand-mark on the right hand.
##
## Loft conventions (KernMeshLib): stacked lofts run TOP -> BOTTOM and swept
## tubes run root -> tip so analytic normals come out outward-facing.
## All geometry is authored in model space (character faces -Z, left = -X);
## skinned surfaces live directly under the Skeleton3D.

const ML: GDScript = preload("res://src/player/kern/kern_mesh_lib.gd")
const KM: GDScript = preload("res://src/player/kern/kern_materials.gd")

# --- Landmark heights (model space, metres) ---------------------------------
const HEIGHT_TOTAL: float = 1.78
const HIPS_Y: float = 0.98
const SPINE_Y: float = 1.13
const CHEST_Y: float = 1.30
const NECK_Y: float = 1.465
const HEAD_Y: float = 1.545          # skull-base pivot; the head builds on this
const SHOULDER_X: float = 0.185
const SHOULDER_Y: float = 1.445
const ELBOW_Y: float = 1.155
const WRIST_Y: float = 0.905
const THIGH_X: float = 0.095
const THIGH_Y: float = 0.925
const KNEE_Y: float = 0.508
const ANKLE_Y: float = 0.115
const CLOAK_A: Vector3 = Vector3(0.0, 1.425, 0.085)
const CLOAK_B: Vector3 = Vector3(0.0, 1.03, 0.135)
const CLOAK_C: Vector3 = Vector3(0.0, 0.60, 0.175)

const RING_N: int = 20               # radial segments for limbs
const TORSO_N: int = 32


## Assembles skeleton + skinned body under `parent`. Returns:
## { skeleton: Skeleton3D, bones: Dictionary[String,int],
##   head_attach / hand_l_attach / hand_r_attach / foot_l_attach /
##   foot_r_attach: BoneAttachment3D, hand_mark: MeshInstance3D }
static func build(parent: Node3D) -> Dictionary:
	var skeleton: Skeleton3D = Skeleton3D.new()
	skeleton.name = "KernSkeleton"
	parent.add_child(skeleton)
	var bones: Dictionary = _build_skeleton(skeleton)

	_build_neck(skeleton, bones)
	_build_tunic(skeleton, bones)
	_build_sleeve(skeleton, bones, false)
	_build_sleeve(skeleton, bones, true)
	_build_trouser(skeleton, bones, false)
	_build_trouser(skeleton, bones, true)

	var out: Dictionary = {"skeleton": skeleton, "bones": bones}
	out["head_attach"] = _attach(skeleton, "Head")
	out["hand_l_attach"] = _attach(skeleton, "HandL")
	out["hand_r_attach"] = _attach(skeleton, "HandR")
	out["foot_l_attach"] = _attach(skeleton, "FootL")
	out["foot_r_attach"] = _attach(skeleton, "FootR")

	var left_hand: Node3D = _build_hand(false)
	left_hand.rotation = Vector3(0.0, PI * 0.5, 0.0)
	(out["hand_l_attach"] as BoneAttachment3D).add_child(left_hand)
	var right_hand: Node3D = _build_hand(true)
	right_hand.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	(out["hand_r_attach"] as BoneAttachment3D).add_child(right_hand)
	out["hand_mark"] = right_hand.get_node_or_null("HandMark")
	return out


# --- Skeleton ---------------------------------------------------------------

static func _build_skeleton(skeleton: Skeleton3D) -> Dictionary:
	# name: [parent name, global rest position]. Rest rotations are identity
	# (bone axes = model axes) so procedural pose code stays readable.
	var defs: Array = [
		["Root", "", Vector3.ZERO],
		["Hips", "Root", Vector3(0.0, HIPS_Y, 0.005)],
		["Spine", "Hips", Vector3(0.0, SPINE_Y, 0.005)],
		["Chest", "Spine", Vector3(0.0, CHEST_Y, 0.0)],
		["Neck", "Chest", Vector3(0.0, NECK_Y, -0.005)],
		["Head", "Neck", Vector3(0.0, HEAD_Y, 0.0)],
		["ClavicleL", "Chest", Vector3(-0.045, 1.435, -0.015)],
		["UpperArmL", "ClavicleL", Vector3(-SHOULDER_X, SHOULDER_Y, -0.01)],
		["ForearmL", "UpperArmL", Vector3(-0.208, ELBOW_Y, -0.002)],
		["HandL", "ForearmL", Vector3(-0.215, WRIST_Y, -0.022)],
		["ClavicleR", "Chest", Vector3(0.045, 1.435, -0.015)],
		["UpperArmR", "ClavicleR", Vector3(SHOULDER_X, SHOULDER_Y, -0.01)],
		["ForearmR", "UpperArmR", Vector3(0.208, ELBOW_Y, -0.002)],
		["HandR", "ForearmR", Vector3(0.215, WRIST_Y, -0.022)],
		["ThighL", "Hips", Vector3(-THIGH_X, THIGH_Y, 0.005)],
		["ShinL", "ThighL", Vector3(-0.100, KNEE_Y, 0.0)],
		["FootL", "ShinL", Vector3(-0.103, ANKLE_Y, 0.012)],
		["ThighR", "Hips", Vector3(THIGH_X, THIGH_Y, 0.005)],
		["ShinR", "ThighR", Vector3(0.100, KNEE_Y, 0.0)],
		["FootR", "ShinR", Vector3(0.103, ANKLE_Y, 0.012)],
		["CloakA", "Chest", CLOAK_A],
		["CloakB", "CloakA", CLOAK_B],
		["CloakC", "CloakB", CLOAK_C],
	]
	var bones: Dictionary = {}
	var globals: Dictionary = {}
	for def in defs:
		var bone_name: String = def[0]
		var parent_name: String = def[1]
		var pos: Vector3 = def[2]
		var idx: int = skeleton.get_bone_count()
		skeleton.add_bone(bone_name)
		bones[bone_name] = idx
		globals[bone_name] = pos
		if parent_name != "":
			skeleton.set_bone_parent(idx, bones[parent_name])
			skeleton.set_bone_rest(idx, Transform3D(
				Basis.IDENTITY, pos - (globals[parent_name] as Vector3)))
		else:
			skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, pos))
	skeleton.reset_bone_poses()
	return bones


static func _attach(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	var attach: BoneAttachment3D = BoneAttachment3D.new()
	attach.name = bone_name + "Attach"
	skeleton.add_child(attach)
	attach.bone_name = bone_name
	return attach


## Skinned MeshInstance3D under the skeleton.
static func _skinned(skeleton: Skeleton3D, surface: Dictionary,
		material: Material, mesh_name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = ML.make_instance(surface, material, mesh_name)
	skeleton.add_child(mi)
	mi.skin = skeleton.create_skin_from_rest_transforms()
	return mi


# --- Neck (visible skin between collar and jaw) -----------------------------

static func _build_neck(skeleton: Skeleton3D, bones: Dictionary) -> void:
	var rings: Array = []
	# Top -> bottom. The top ring tucks under the head mesh; the bottom ring
	# hides inside the tunic collar.
	var rows: Array = [
		# [y, rx, rz, z_off, blend spec]
		[1.545, 0.0500, 0.0470, 0.000],
		[1.520, 0.0505, 0.0475, 0.000],
		[1.495, 0.0515, 0.0490, 0.002],
		[1.470, 0.0530, 0.0505, 0.004],
		[1.445, 0.0580, 0.0560, 0.006],
		[1.425, 0.0660, 0.0650, 0.008],
	]
	for row in rows:
		var y: float = row[0]
		var ring: ML.Ring = _torso_ring(y, row[1], row[2], row[2], row[3], RING_N)
		ring.v = (1.545 - y) / 0.12
		var shade: float = clampf((1.545 - y) / 0.06, 0.0, 1.0) * 0.10
		var c: Color = KM.SKIN_BASE.darkened(0.06 * (1.0 - shade) + shade * 0.16)
		c.a = 0.75  # thin-ish skin: throat picks up warm backlight
		ring.color = c
		if y >= 1.50:
			ring.bone_a = bones["Head"]
			ring.bone_b = bones["Neck"]
			ring.blend = clampf((1.545 - y) / 0.05, 0.0, 1.0)
		else:
			ring.bone_a = bones["Neck"]
			ring.bone_b = bones["Chest"]
			ring.blend = clampf((1.50 - y) / 0.08, 0.0, 1.0)
		rings.append(ring)
	var surface: Dictionary = ML.loft(rings, true, false, false, true)
	_skinned(skeleton, surface, KM.skin(), "NeckSkin")


# --- Tunic ------------------------------------------------------------------

static func _build_tunic(skeleton: Skeleton3D, bones: Dictionary) -> void:
	var rings: Array = []
	# [y, rx, rz_front, rz_back, z_off, fold ripple amp]
	# An athletic V-taper: broad chest/shoulders -> narrow waist -> flaring
	# skirt (the Link tunic line), rather than a barrel.
	var rows: Array = [
		[1.500, 0.048, 0.046, 0.048, -0.004, 0.000],   # high collar at the neck
		[1.480, 0.062, 0.056, 0.060, -0.002, 0.000],   # collar base
		[1.458, 0.092, 0.070, 0.080, 0.000, 0.000],    # trapezius slope
		[1.432, 0.136, 0.084, 0.094, 0.000, 0.000],    # deltoid cap
		[1.398, 0.148, 0.094, 0.100, 0.000, 0.001],    # broad chest top
		[1.350, 0.142, 0.100, 0.100, 0.000, 0.001],    # pecs
		[1.295, 0.129, 0.096, 0.096, 0.001, 0.001],    # lower ribs
		[1.235, 0.115, 0.090, 0.090, 0.002, 0.002],    # upper waist
		[1.175, 0.106, 0.084, 0.086, 0.003, 0.002],    # narrow waist
		[1.120, 0.110, 0.085, 0.090, 0.004, 0.003],    # waist / belt line
		[1.070, 0.121, 0.090, 0.098, 0.004, 0.003],    # hips
		[1.015, 0.134, 0.097, 0.106, 0.005, 0.002],    # under the belt
		[0.968, 0.148, 0.101, 0.112, 0.006, 0.004],    # skirt starts
		[0.922, 0.161, 0.108, 0.120, 0.006, 0.006],
		[0.882, 0.171, 0.114, 0.127, 0.007, 0.008],
		[0.850, 0.179, 0.120, 0.132, 0.007, 0.010],    # hem flare
	]
	var row_i: int = 0
	for row in rows:
		var y: float = row[0]
		var ripple: float = row[5]
		var ring: ML.Ring = _torso_ring(y, row[1], row[2], row[3], row[4],
			TORSO_N, ripple, 9.0)
		ring.v = float(row_i) / float(rows.size() - 1) * 1.8
		var c: Color = KM.TUNIC_GREEN
		if row_i == 0:
			c = KM.TUNIC_GREEN.darkened(0.25)  # rolled collar edge
		elif row_i >= rows.size() - 1:
			c = KM.TUNIC_GREEN.darkened(0.12)  # dust-darkened hem
		c.a = clampf(float(row_i - 10) / 4.0, 0.0, 1.0) * 0.5  # skirt swings
		ring.color = c
		_torso_weights(ring, y, bones)
		# Shoulder slope: drop the outer (side) vertices at the top rows so the
		# shoulders angle down to the arms instead of forming a flat shelf.
		if y >= 1.43:
			var n_pts: int = ring.points.size()
			for j in n_pts:
				var a2: float = TAU * float(j) / float(n_pts)
				var side_f: float = absf(cos(a2))  # 1 at the sides
				ring.points[j].y -= 0.072 * pow(side_f, 1.6)
		# Hem dips: the skirt bottom edge waves so it doesn't cut a laser line.
		if row_i == rows.size() - 1:
			for j in ring.points.size():
				var a: float = TAU * float(j) / float(ring.points.size())
				ring.points[j].y += sin(a * 5.0 + 0.7) * 0.008 - 0.004
		rings.append(ring)
		row_i += 1
	var surface: Dictionary = ML.loft(rings, true, false, false, true)
	# Tunic v runs 0 (collar) -> ~1.8 (hem). Gold trim at the collar and hem,
	# a little wind in the loose skirt.
	var tunic_mat: ShaderMaterial = KM.cloth(210.0, 0.018)
	KM.add_trim(tunic_mat, Vector2(0.06, 0.055), Vector2(1.70, 0.075), 14.0)
	_skinned(skeleton, surface, tunic_mat, "Tunic")

	# Cross-lacing at the collar front: the small handmade detail that reads
	# at conversation distance. Two crossed cords + three eyelet knots.
	var lace_mat: ShaderMaterial = KM.leather()
	for k in 2:
		var flip_x: float = -1.0 if k == 0 else 1.0
		var path: Array[Vector3] = ML.bezier_path(
			Vector3(0.020 * flip_x, 1.478, -0.062),
			Vector3(0.004 * flip_x, 1.462, -0.070),
			Vector3(-0.012 * flip_x, 1.447, -0.074),
			Vector3(-0.022 * flip_x, 1.432, -0.077), 8)
		var radii: PackedFloat32Array = PackedFloat32Array()
		for i in path.size():
			radii.append(0.0035)
		var lace_rings: Array = ML.tube_rings(path, radii, 8)
		for r_any in lace_rings:
			var lr: ML.Ring = r_any
			lr.color = KM.GRIP_BROWN
			lr.bone_a = bones["Chest"]
		var lace: Dictionary = ML.loft(lace_rings, true, true, true, true)
		_skinned(skeleton, lace, lace_mat, "CollarLace%d" % k)


static func _torso_ring(y: float, rx: float, rz_front: float, rz_back: float,
		z_off: float, n: int, ripple: float = 0.0, ripple_freq: float = 9.0) -> ML.Ring:
	var ring: ML.Ring = ML.Ring.new()
	ring.points.resize(n)
	for j in n:
		var a: float = TAU * float(j) / float(n)
		var front_f: float = clampf(-sin(a) * 0.5 + 0.5, 0.0, 1.0)
		var rz: float = lerpf(rz_back, rz_front, front_f)
		var m: float = 1.0
		if ripple > 0.0:
			m += sin(a * ripple_freq + y * 31.0) * ripple / maxf(rx, 0.001)
		ring.points[j] = Vector3(cos(a) * rx * m, y, sin(a) * rz * m + z_off)
	return ring


static func _torso_weights(ring: ML.Ring, y: float, bones: Dictionary) -> void:
	if y >= 1.43:
		ring.bone_a = bones["Chest"]
		ring.bone_b = bones["Neck"]
		ring.blend = clampf((y - 1.43) / 0.07, 0.0, 0.6)
	elif y >= SPINE_Y:
		ring.bone_a = bones["Spine"]
		ring.bone_b = bones["Chest"]
		ring.blend = clampf((y - SPINE_Y) / (1.43 - SPINE_Y), 0.0, 1.0)
	else:
		ring.bone_a = bones["Hips"]
		ring.bone_b = bones["Spine"]
		ring.blend = clampf((y - 0.90) / (SPINE_Y - 0.90), 0.0, 1.0)


# --- Sleeves ----------------------------------------------------------------

static func _build_sleeve(skeleton: Skeleton3D, bones: Dictionary, right: bool) -> void:
	var sx: float = 1.0 if right else -1.0
	var shoulder: Vector3 = Vector3(SHOULDER_X * sx, SHOULDER_Y + 0.018, -0.01)
	var elbow: Vector3 = Vector3(0.208 * sx, ELBOW_Y, -0.002)
	var wrist: Vector3 = Vector3(0.215 * sx, WRIST_Y + 0.01, -0.020)
	var path: Array[Vector3] = []
	var rows: int = 18
	for i in rows:
		var t: float = float(i) / float(rows - 1)
		var p: Vector3
		if t < 0.5:
			p = shoulder.lerp(elbow, t * 2.0)
		else:
			p = elbow.lerp(wrist, (t - 0.5) * 2.0)
		# Slight forward elbow set so the arm never reads hyper-extended.
		p.z -= sin(t * PI) * 0.008
		path.append(p)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in rows:
		var t: float = float(i) / float(rows - 1)
		var r: float = _sleeve_radius(t)
		# Cloth wrinkle rings bunching at the inner elbow.
		if t > 0.38 and t < 0.62:
			r += sin(t * 130.0) * 0.0022
		radii.append(r)
	var rings: Array = ML.tube_rings(path, radii, RING_N)
	var upper: int = bones["UpperArmR" if right else "UpperArmL"]
	var lower: int = bones["ForearmR" if right else "ForearmL"]
	var hand: int = bones["HandR" if right else "HandL"]
	for i in rings.size():
		var ring: ML.Ring = rings[i]
		var t: float = float(i) / float(rings.size() - 1)
		ring.v = t * 1.4
		var c: Color = KM.TUNIC_SLEEVE
		if t > 0.94:
			c = KM.TUNIC_SLEEVE.darkened(0.22)  # folded cuff edge
		c.a = 0.0
		ring.color = c
		if t < 0.40:
			ring.bone_a = upper
			ring.bone_b = lower
			ring.blend = 0.0
		elif t < 0.62:
			ring.bone_a = upper
			ring.bone_b = lower
			ring.blend = smoothstep(0.40, 0.62, t)
		elif t < 0.92:
			ring.bone_a = lower
			ring.bone_b = hand
			ring.blend = 0.0
		else:
			ring.bone_a = lower
			ring.bone_b = hand
			ring.blend = smoothstep(0.92, 1.0, t) * 0.5
	# Elbow patch: canon patched travel-wear. A contrasting oval sits over the
	# elbow rows with running stitches around it (painted into ring colors).
	for i in rings.size():
		var t: float = float(i) / float(rings.size() - 1)
		if t > 0.42 and t < 0.60:
			var ring: ML.Ring = rings[i]
			var pc: PackedColorArray = PackedColorArray()
			for j in ring.points.size():
				var a: float = TAU * float(j) / float(ring.points.size())
				# Patch faces outward/back of the elbow (+Z half in tube frame
				# is arbitrary — paint by world z > elbow z).
				var back_f: float = clampf((ring.points[j].z - (-0.01)) * 60.0, 0.0, 1.0)
				var c2: Color = KM.TUNIC_SLEEVE
				c2 = c2.lerp(KM.PATCH_TAN, back_f * 0.9)
				c2.a = 0.0
				pc.append(c2)
			ring.point_colors = pc
	var surface: Dictionary = ML.loft(rings, true, false, false, true)
	var side: String = "R" if right else "L"
	# Sleeve v runs 0 (shoulder) -> ~1.4 (cuff). Trim at the cuff; a little wind.
	var sleeve_mat: ShaderMaterial = KM.cloth(230.0, 0.010)
	KM.add_trim(sleeve_mat, Vector2(1.34, 0.055), Vector2(-1.0, 0.05), 8.0)
	_skinned(skeleton, surface, sleeve_mat, "Sleeve" + side)


static func _sleeve_radius(t: float) -> float:
	# Shoulder cap -> deltoid -> biceps -> elbow -> forearm swell -> cuff.
	# Slimmer and more tapered than before for a lean, athletic arm.
	var keys: Array = [
		[0.00, 0.0560], [0.08, 0.0525], [0.20, 0.0455], [0.34, 0.0405],
		[0.50, 0.0365], [0.60, 0.0385], [0.72, 0.0360], [0.86, 0.0320],
		[1.00, 0.0285],
	]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= float(b[0]):
			var f: float = (t - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, f))
	return 0.0335


# --- Trousers ---------------------------------------------------------------

static func _build_trouser(skeleton: Skeleton3D, bones: Dictionary, right: bool) -> void:
	var sx: float = 1.0 if right else -1.0
	var hip: Vector3 = Vector3(THIGH_X * sx, 0.940, 0.004)
	var knee: Vector3 = Vector3(0.100 * sx, KNEE_Y, -0.006)
	var cuff: Vector3 = Vector3(0.104 * sx, 0.325, 0.006)
	var rows: int = 16
	var path: Array[Vector3] = []
	for i in rows:
		var t: float = float(i) / float(rows - 1)
		var p: Vector3
		if t < 0.62:
			p = hip.lerp(knee, t / 0.62)
		else:
			p = knee.lerp(cuff, (t - 0.62) / 0.38)
		path.append(p)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in rows:
		var t: float = float(i) / float(rows - 1)
		# Slimmer leg: thigh -> knee -> calf swell -> ankle cuff.
		var keys: Array = [
			[0.00, 0.0730], [0.16, 0.0690], [0.36, 0.0610], [0.55, 0.0510],
			[0.62, 0.0485], [0.74, 0.0540], [0.88, 0.0460], [1.00, 0.0405],
		]
		var r: float = 0.05
		for k in keys.size() - 1:
			var a: Array = keys[k]
			var b: Array = keys[k + 1]
			if t <= float(b[0]):
				var f: float = (t - float(a[0])) / (float(b[0]) - float(a[0]))
				r = lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, f))
				break
		# Knee wrinkles + bunching above the boot cuff.
		if t > 0.52 and t < 0.72:
			r += sin(t * 150.0) * 0.0024
		if t > 0.88:
			r += sin(t * 180.0) * 0.0028
		radii.append(r)
	var rings: Array = ML.tube_rings(path, radii, RING_N)
	var thigh: int = bones["ThighR" if right else "ThighL"]
	var shin: int = bones["ShinR" if right else "ShinL"]
	for i in rings.size():
		var ring: ML.Ring = rings[i]
		var t: float = float(i) / float(rings.size() - 1)
		ring.v = t * 1.5
		var c: Color = KM.TROUSER_GREY
		if t > 0.94:
			c = KM.TROUSER_GREY.darkened(0.18)
		c.a = 0.0
		ring.color = c
		if t < 0.50:
			ring.bone_a = thigh
			ring.bone_b = shin
			ring.blend = 0.0
		else:
			ring.bone_a = thigh
			ring.bone_b = shin
			ring.blend = smoothstep(0.50, 0.74, t)
	var surface: Dictionary = ML.loft(rings, true, false, false, true)
	var side: String = "R" if right else "L"
	_skinned(skeleton, surface, KM.cloth(240.0, 0.0), "Trouser" + side)


# --- Hands ------------------------------------------------------------------
# Canonical frame (right hand): wrist at origin, fingers -Y, palm +Z,
# thumb -X. The left hand mirrors the surfaces across X.

static func _build_hand(right: bool) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "HandRMesh" if right else "HandLMesh"
	var grip: bool = right  # the right hand carries the sword
	var parts: Array[Dictionary] = []
	parts.append(_palm_surface())
	# Fingers: index (thumb side, -X) to pinky (+X).
	var finger_x: Array = [-0.0285, -0.0095, 0.0095, 0.0285]
	var finger_len: Array = [0.070, 0.078, 0.072, 0.058]
	var finger_r: Array = [0.0085, 0.0088, 0.0082, 0.0072]
	for f in 4:
		var curl: Vector3
		var splay: float
		if grip:
			# Tighter, uniform curl so the four fingers close into a fist around
			# the grip instead of splaying into separate ribbons.
			curl = Vector3(1.15, 1.20, 1.05)
			splay = 0.02 * (float(f) - 1.5)
		else:
			curl = Vector3(0.38 + 0.05 * float(f), 0.50, 0.34)
			splay = 0.06 * (float(f) - 1.5)
		parts.append(_finger_surface(
			Vector3(finger_x[f], -0.096, 0.004),
			finger_len[f], finger_r[f], curl, splay))
	parts.append(_thumb_surface(grip))
	var merged: Dictionary = ML.merge(parts)
	if not right:
		merged = ML.mirror_x(merged)
	var mesh_inst: MeshInstance3D = ML.make_instance(merged, KM.skin(), "HandSkin")
	root.add_child(mesh_inst)

	# Nails only read on the open hand; the sword fist tucks them away.
	if not grip:
		var nails: Dictionary = _nails_surface()
		if not right:
			nails = ML.mirror_x(nails)
		root.add_child(ML.make_instance(nails, KM.bone_white(), "Nails"))

	if right:
		root.add_child(_hand_mark())
		_add_hand_threads(root)
	return root


## Latent threads: faint glowing filaments branching from the hand-mark across
## the back of the hand and up onto the wrist — brighten with `awaken`.
static func _add_hand_threads(root: Node3D) -> void:
	var origin: Vector3 = Vector3(0.0, -0.055, -0.017)  # the mark, back of hand
	var tips: Array = [
		Vector3(-0.030, -0.015, -0.020),
		Vector3(0.028, -0.020, -0.020),
		Vector3(0.006, 0.010, -0.014),   # up toward the wrist
		Vector3(-0.014, -0.088, -0.016),  # down toward the knuckles
	]
	var idx: int = 0
	for tip_any in tips:
		var tip: Vector3 = tip_any
		var mid: Vector3 = origin.lerp(tip, 0.5) + Vector3(
			(ML.hash1(float(idx) * 3.1) - 0.5) * 0.010, 0.0,
			-0.004 - 0.004 * ML.hash1(float(idx) * 7.7))
		var path: Array[Vector3] = ML.bezier_path(origin, mid,
			mid.lerp(tip, 0.6), tip, 7)
		var radii: PackedFloat32Array = PackedFloat32Array()
		for i in path.size():
			var f: float = float(i) / float(path.size() - 1)
			radii.append(lerpf(0.0016, 0.0005, f))  # taper to nothing
		var rings: Array = ML.tube_rings(path, radii, 6)
		var surf: Dictionary = ML.loft(rings, true, true, true)
		root.add_child(ML.make_instance(surf, KM.glow(), "HandThread%d" % idx))
		idx += 1


static func _palm_surface() -> Dictionary:
	var rings: Array = []
	# Rows wrist -> knuckle line (downward ✓). Slightly wedge-shaped: broader
	# and flatter at the knuckles, rounder at the wrist.
	var rows: Array = [
		# [y, rx, rz, z_off]
		[0.010, 0.0310, 0.0210, 0.000],
		[-0.012, 0.0340, 0.0205, 0.001],
		[-0.034, 0.0375, 0.0195, 0.002],
		[-0.056, 0.0400, 0.0180, 0.003],
		[-0.076, 0.0415, 0.0165, 0.004],
		[-0.090, 0.0412, 0.0150, 0.004],
		[-0.100, 0.0390, 0.0130, 0.004],
	]
	var i: int = 0
	for row in rows:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = RING_N
		ring.points.resize(n)
		var pc: PackedColorArray = PackedColorArray()
		for j in n:
			var a: float = TAU * float(j) / float(n)
			var x: float = cos(a) * row[1]
			var z: float = sin(a) * row[2] + row[3]
			# Knuckle ridge: four bumps across the back (-Z) at the last rows.
			if i >= 5 and sin(a) < -0.3:
				z -= absf(sin(x * 110.0)) * 0.0035
			var c: Color = KM.SKIN_BASE
			# Back-of-hand tendons: slight value ridges fanning to the fingers.
			if sin(a) < -0.35 and i >= 2 and i <= 4:
				c = c.lightened(absf(sin(x * 150.0)) * 0.05)
			# Palm creases: two darker arcs across the palm side.
			if sin(a) > 0.5 and (i == 3 or i == 5):
				c = c.darkened(0.10)
			if i >= 5:
				c = c.lerp(KM.SKIN_FLUSH, 0.35)  # knuckles flush
			c.a = 0.9
			pc.append(c)
			ring.points[j] = Vector3(x, row[0], z)
		ring.point_colors = pc
		ring.v = float(i) / 6.0
		rings.append(ring)
		i += 1
	return ML.loft(rings, true, true, true)


static func _finger_surface(knuckle: Vector3, length: float, radius: float,
		curl: Vector3, splay: float) -> Dictionary:
	# Three segments (45/30/25 %) curling toward the palm (+Z): negative
	# rotations about X swing the -Y finger direction palm-ward.
	var segs: Array = [length * 0.45, length * 0.30, length * 0.25]
	var angles: Array = [curl.x, curl.y, curl.z]
	var path: Array[Vector3] = [knuckle]
	var radii: PackedFloat32Array = PackedFloat32Array([radius])
	var pos: Vector3 = knuckle
	var accum: float = 0.0
	var taper: Array = [1.0, 0.88, 0.78]
	for s in 3:
		accum += float(angles[s])
		var dir: Vector3 = Vector3(sin(splay) * 0.4, -cos(accum), sin(accum))
		dir = dir.normalized()
		var steps: int = 3
		for k in steps:
			pos += dir * (float(segs[s]) / float(steps))
			path.append(pos)
			var t_seg: float = float(k + 1) / float(steps)
			var r: float = radius * float(taper[s])
			# Joint knuckle bump at segment boundaries.
			if k == steps - 1 and s < 2:
				r *= 1.12
			if s == 2:
				r *= lerpf(1.0, 0.62, t_seg)  # fingertip round-off
			radii.append(r)
	var rings: Array = ML.tube_rings(path, radii, 10, 0.92)
	for i in rings.size():
		var ring: ML.Ring = rings[i]
		var t: float = float(i) / float(rings.size() - 1)
		ring.v = t
		var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.20 + t * 0.25)
		c.a = 0.72  # fingers are thin: backlight glows through
		ring.color = c
	return ML.loft(rings, true, false, true)


static func _thumb_surface(grip: bool) -> Dictionary:
	var root: Vector3 = Vector3(-0.030, -0.030, 0.008)
	var path: Array[Vector3] = [root]
	var radii: PackedFloat32Array = PackedFloat32Array([0.0105])
	var pos: Vector3 = root
	var dirs: Array
	if grip:
		# Wrapped over the grip: out, across the palm, closing in.
		dirs = [Vector3(-0.5, -0.55, 0.65), Vector3(0.25, -0.35, 0.9),
			Vector3(0.75, -0.1, 0.55)]
	else:
		dirs = [Vector3(-0.62, -0.62, 0.42), Vector3(-0.42, -0.72, 0.55),
			Vector3(-0.28, -0.78, 0.60)]
	var seg_len: Array = [0.030, 0.028, 0.024]
	var taper: Array = [1.0, 0.9, 0.78]
	for s in 3:
		var dir: Vector3 = (dirs[s] as Vector3).normalized()
		var steps: int = 3
		for k in steps:
			pos += dir * (float(seg_len[s]) / float(steps))
			path.append(pos)
			var r: float = 0.0105 * float(taper[s])
			if s == 2 and k == steps - 1:
				r *= 0.62
			radii.append(r)
	var rings: Array = ML.tube_rings(path, radii, 10, 0.94)
	for i in rings.size():
		var ring: ML.Ring = rings[i]
		var t: float = float(i) / float(rings.size() - 1)
		ring.v = t
		var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.15 + t * 0.25)
		c.a = 0.75
		ring.color = c
	return ML.loft(rings, true, true, true)


static func _nails_surface() -> Dictionary:
	var parts: Array[Dictionary] = []
	var finger_x: Array = [-0.0285, -0.0095, 0.0095, 0.0285]
	var finger_len: Array = [0.070, 0.078, 0.072, 0.058]
	for f in 4:
		# Approximate distal-top position for the relaxed curl used above.
		var tip: Vector3 = Vector3(
			float(finger_x[f]) + 0.06 * (float(f) - 1.5) * 0.03,
			-0.096 - float(finger_len[f]) * 0.86,
			0.030 + float(finger_len[f]) * 0.34)
		parts.append(_nail_at(tip, 0.0042))
	parts.append(_nail_at(Vector3(-0.085, -0.115, 0.052), 0.0050))  # thumb
	return ML.merge(parts)


static func _nail_at(center: Vector3, size: float) -> Dictionary:
	var rings: Array = []
	for i in 2:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 8
		ring.points.resize(n)
		var r: float = size * (1.0 if i == 0 else 0.82)
		var lift: float = -0.001 if i == 0 else 0.0016
		for j in n:
			var a: float = TAU * float(j) / float(n)
			ring.points[j] = center + Vector3(cos(a) * r, lift, sin(a) * r * 0.8 - 0.004)
		ring.v = float(i)
		ring.color = Color(0.92, 0.86, 0.78)
		rings.append(ring)
	return ML.loft(rings, true, false, true)


## The canon mark: a small perceptron sigil flush on the back of the right hand
## — an outer ring, a centre node, three input nodes wired to it, and one output
## tail. Wears the living glow material, so it's a faint ember at rest and
## blazes as `awaken` rises (near ancient machinery / knowledge charge). The
## motif echoes the project's perceptron icon.
static func _hand_mark() -> Node3D:
	var mark: Node3D = Node3D.new()
	mark.name = "HandMark"
	var mat: ShaderMaterial = KM.glow()
	var c: Vector3 = Vector3(0.0, -0.055, -0.017)  # mark centre, back of hand

	# Outer ring.
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.0100
	ring_mesh.outer_radius = 0.0122
	ring_mesh.rings = 28
	ring_mesh.ring_segments = 8
	var ring_node: MeshInstance3D = MeshInstance3D.new()
	ring_node.name = "SigilRing"
	ring_node.mesh = ring_mesh
	ring_node.material_override = mat
	ring_node.position = c
	ring_node.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	mark.add_child(ring_node)

	# Centre (output) node.
	mark.add_child(_glow_node(c + Vector3(0.0, 0.0, -0.001), 0.0028, mat, "SigilCore"))

	# Three input nodes on the nasal-left arc, each wired to the centre.
	for k in 3:
		var a: float = PI * 0.5 + (float(k) - 1.0) * 0.7
		var node_pos: Vector3 = c + Vector3(cos(a) * 0.0092, sin(a) * 0.0092, -0.001)
		mark.add_child(_glow_node(node_pos, 0.0016, mat, "SigilIn%d" % k))
		mark.add_child(_glow_edge(node_pos, c + Vector3(0.0, 0.0, -0.001), mat,
			"SigilWire%d" % k))
	# Output tail leaving the ring toward the wrist.
	mark.add_child(_glow_edge(c + Vector3(0.0, 0.0, -0.001),
		c + Vector3(0.0, 0.016, 0.0), mat, "SigilOut"))
	return mark


static func _glow_node(pos: Vector3, radius: float, mat: Material,
		node_name: String) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


## A thin glowing wire between two points; UV.y runs a->b for the flow pulse.
static func _glow_edge(a: Vector3, b: Vector3, mat: Material,
		edge_name: String) -> MeshInstance3D:
	var rings: Array = ML.tube_rings([a, b], PackedFloat32Array([0.0007, 0.0007]), 6)
	return ML.make_instance(ML.loft(rings, true, true, true), mat, edge_name)

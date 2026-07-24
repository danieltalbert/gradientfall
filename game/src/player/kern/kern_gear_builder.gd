class_name KernGearBuilder
extends RefCounted
## Kern's worn gear and kit: the patched traveller's cloak (bone-chained so it
## sways), a leather belt with iron buckle + hanging pouch, a knitted scarf,
## laced boots (built rigid on the foot BoneAttachment3D), and the traveller's
## sword — fullered blade, bronze guard, wrapped grip, sigil pommel — with a
## matching hip scabbard. The cloak is skinned to the CloakA/B/C bone chain
## from KernBodyBuilder; everything else is rigid under a bone attachment.
##
## Returns the sword pivot Node3D so the combat rig can pose it exactly like
## the old KernVisual did (SWORD_REST_POS / SWORD_REST_ROT compatible).

const ML: GDScript = preload("res://src/player/kern/kern_mesh_lib.gd")
const KM: GDScript = preload("res://src/player/kern/kern_body_builder.gd")  # reuse consts
const MAT: GDScript = preload("res://src/player/kern/kern_materials.gd")


static func build(skeleton: Skeleton3D, bones: Dictionary,
		attaches: Dictionary) -> Dictionary:
	_build_cloak(skeleton, bones)
	_build_belt(skeleton, bones)
	_build_scarf(skeleton, bones)
	_build_boot(attaches["foot_l_attach"], false)
	_build_boot(attaches["foot_r_attach"], true)
	_build_scabbard(skeleton, bones)
	# The sword rides an attachment on the character root so combat can pose it
	# in model space (same frame the legacy rig used). It is parented later by
	# the visual so it can be reached from pose code — return the node.
	return {"sword": _build_sword()}


# --- Cloak ------------------------------------------------------------------

static func _build_cloak(skeleton: Skeleton3D, bones: Dictionary) -> void:
	# A cape sheet: rows from the shoulders (CloakA) down to a frayed hem
	# (CloakC), wrapping around the back and tapering to the clasp at the
	# front collar. Columns span the back arc; the sheet is single-sided
	# thickened by two offset layers so it reads from both faces.
	var rows: int = 12
	var cols: int = 15
	var attach_top: Vector3 = KM.CLOAK_A
	# Cloak v runs 0 (shoulders) -> ~1.6 (hem). Gold border along the hem, and
	# the strongest wind on the character (it's the loosest cloth).
	var mat: ShaderMaterial = MAT.cloth(180.0, 0.038)
	MAT.add_trim(mat, Vector2(1.50, 0.075), Vector2(-1.0, 0.05), 20.0,
		Color(0.80, 0.64, 0.28), Color(0.30, 0.20, 0.13))

	var rings: Array = []
	for i in rows:
		var vt: float = float(i) / float(rows - 1)
		var ring: ML.Ring = ML.Ring.new()
		ring.points.resize(cols)
		var pc: PackedColorArray = PackedColorArray()
		# Vertical centre-line of the cloak descends and bells outward.
		var y: float = lerpf(1.44, 0.52, vt)
		var back_z: float = lerpf(0.075, 0.20, vt) + 0.02 * sin(vt * PI)
		var half_span: float = lerpf(0.155, 0.30, smoothstep(0.0, 1.0, vt))  # around the body
		for j in cols:
			var s: float = lerpf(-1.0, 1.0, float(j) / float(cols - 1))
			# Wrap the sheet around a cylinder of the torso; ends curl forward.
			var ang: float = s * (PI * 0.62)
			var wrap_r: float = lerpf(0.145, 0.235, vt)
			var x: float = sin(ang) * wrap_r
			var z: float = back_z + cos(ang) * wrap_r * 0.5
			# Folds: sinusoidal in/out along the span, deeper toward the hem.
			var fold: float = sin(s * 9.0 + vt * 2.0) * (0.004 + vt * 0.016)
			var out_n: Vector3 = Vector3(sin(ang), 0.0, cos(ang) * 0.5).normalized()
			var p: Vector3 = Vector3(x, y, z) + out_n * fold
			# Hem waves up and down (frayed, uneven).
			if i == rows - 1:
				p.y += sin(s * 7.0 + 1.3) * 0.02 - 0.012 * absf(s)
			ring.points[j] = p
			var c: Color = MAT.CLOAK_BROWN
			# Inner front edges show the warmer lining.
			if absf(s) > 0.82:
				c = c.lerp(MAT.CLOAK_LINING, smoothstep(0.82, 1.0, absf(s)) * 0.7)
			c = c.darkened(0.10 * vt)  # dusty toward the hem
			c.a = smoothstep(0.15, 1.0, vt)  # free lower cloth flutters/backlights
			pc.append(c)
		ring.point_colors = pc
		ring.v = vt * 1.6
		# Skin to the cloak bone chain by height.
		if y >= KM.CLOAK_B.y:
			ring.bone_a = bones["CloakA"]
			ring.bone_b = bones["CloakB"]
			ring.blend = clampf((KM.CLOAK_A.y - y) / (KM.CLOAK_A.y - KM.CLOAK_B.y), 0.0, 1.0)
		else:
			ring.bone_a = bones["CloakB"]
			ring.bone_b = bones["CloakC"]
			ring.blend = clampf((KM.CLOAK_B.y - y) / (KM.CLOAK_B.y - KM.CLOAK_C.y), 0.0, 1.0)
		rings.append(ring)
	# Loft NON-wrapping (open sheet); build both faces by flipping.
	var front: Dictionary = ML.loft(rings, false, false, false, true, false)
	var back: Dictionary = ML.loft(_offset_rings(rings, -0.006), false, false, false, true, true)
	var sheet: Dictionary = ML.merge([front, back])
	var mi: MeshInstance3D = ML.make_instance(sheet, mat, "Cloak")
	skeleton.add_child(mi)
	mi.skin = skeleton.create_skin_from_rest_transforms()

	_build_cloak_patches(skeleton, bones)
	_build_cloak_clasp(skeleton, bones)


static func _offset_rings(rings: Array, dz: float) -> Array:
	var out: Array = []
	for r_any in rings:
		var src: ML.Ring = r_any
		var ring: ML.Ring = ML.Ring.new()
		ring.points.resize(src.points.size())
		for i in src.points.size():
			var p: Vector3 = src.points[i]
			# Push along approximate outward (radial in XZ from the back line).
			var radial: Vector3 = Vector3(p.x, 0.0, p.z - 0.12)
			if radial.length_squared() > 0.0001:
				radial = radial.normalized()
			else:
				radial = Vector3(0, 0, 1)
			ring.points[i] = p + radial * dz
		ring.point_colors = src.point_colors.duplicate()
		ring.v = src.v
		ring.bone_a = src.bone_a
		ring.bone_b = src.bone_b
		ring.blend = src.blend
		out.append(ring)
	return out


static func _build_cloak_patches(skeleton: Skeleton3D, bones: Dictionary) -> void:
	# Two mended patches with running-stitch borders on the back of the cloak.
	var patch_specs: Array = [
		[Vector3(-0.10, 0.92, 0.19), 0.075, 0.060, MAT.PATCH_TAN, bones["CloakB"]],
		[Vector3(0.12, 0.70, 0.205), 0.065, 0.078, MAT.PATCH_GREEN, bones["CloakC"]],
	]
	var mat: ShaderMaterial = MAT.cloth(240.0, 0.0)
	var idx: int = 0
	for spec in patch_specs:
		var center: Vector3 = spec[0]
		var hw: float = spec[1]
		var hh: float = spec[2]
		var col: Color = spec[3]
		var rings: Array = []
		for i in 2:
			var ring: ML.Ring = ML.Ring.new()
			var n: int = 4
			ring.points.resize(n)
			var zoff: float = 0.004 if i == 0 else 0.0
			ring.points[0] = center + Vector3(-hw, -hh, zoff)
			ring.points[1] = center + Vector3(hw, -hh, zoff)
			ring.points[2] = center + Vector3(hw, hh, zoff)
			ring.points[3] = center + Vector3(-hw, hh, zoff)
			ring.color = col.darkened(0.08) if i == 0 else col
			ring.bone_a = spec[4]
			rings.append(ring)
		var patch: Dictionary = ML.loft(rings, true, true, true, true)
		var mi: MeshInstance3D = ML.make_instance(patch, mat, "CloakPatch%d" % idx)
		skeleton.add_child(mi)
		mi.skin = skeleton.create_skin_from_rest_transforms()

		# Running stitches: short dashes around the patch perimeter.
		var stitch: Dictionary = _stitch_border(center, hw, hh, spec[4])
		var smi: MeshInstance3D = ML.make_instance(stitch, MAT.leather(),
			"CloakStitch%d" % idx)
		skeleton.add_child(smi)
		smi.skin = skeleton.create_skin_from_rest_transforms()
		idx += 1


static func _stitch_border(center: Vector3, hw: float, hh: float, bone: int) -> Dictionary:
	var parts: Array[Dictionary] = []
	var per_side: int = 5
	for side in 4:
		for k in per_side:
			var f: float = (float(k) + 0.5) / float(per_side)
			var p: Vector3
			match side:
				0: p = center + Vector3(lerpf(-hw, hw, f), -hh * 0.92, 0.006)
				1: p = center + Vector3(hw * 0.92, lerpf(-hh, hh, f), 0.006)
				2: p = center + Vector3(lerpf(hw, -hw, f), hh * 0.92, 0.006)
				_: p = center + Vector3(-hw * 0.92, lerpf(hh, -hh, f), 0.006)
			var dash: Array[Vector3] = [
				p + Vector3(-0.006, 0.0, 0.0), p + Vector3(0.006, 0.0, 0.0)]
			if side == 1 or side == 3:
				dash = [p + Vector3(0.0, -0.006, 0.0), p + Vector3(0.0, 0.006, 0.0)]
			var radii: PackedFloat32Array = PackedFloat32Array([0.0012, 0.0012])
			var rings: Array = ML.tube_rings(dash, radii, 5)
			for r_any in rings:
				var ring: ML.Ring = r_any
				ring.color = MAT.THREAD_COLOR
				ring.bone_a = bone
			parts.append(ML.loft(rings, true, true, true, true))
	return ML.merge(parts)


static func _build_cloak_clasp(skeleton: Skeleton3D, bones: Dictionary) -> void:
	# Two small bronze discs pinning the cloak at the collar front, joined by a
	# short chain of tiny links. Rigid on the Chest bone.
	var attach: BoneAttachment3D = BoneAttachment3D.new()
	attach.name = "ClaspAttach"
	skeleton.add_child(attach)
	attach.bone_name = "Chest"
	for side in [-1.0, 1.0]:
		var disc: MeshInstance3D = MeshInstance3D.new()
		var disc_mesh: CylinderMesh = CylinderMesh.new()
		disc_mesh.top_radius = 0.016
		disc_mesh.bottom_radius = 0.016
		disc_mesh.height = 0.007
		disc_mesh.radial_segments = 14
		disc.name = "ClaspDisc%s" % ("L" if side < 0.0 else "R")
		disc.mesh = disc_mesh
		disc.material_override = MAT.metal(1.4)
		disc.transform = Transform3D(
			Basis().rotated(Vector3.RIGHT, PI * 0.5),
			_to_bone_local(skeleton, bones["Chest"], Vector3(side * 0.045, 1.452, -0.070)))
		attach.add_child(disc)
	# Chain: four little bronze bar-links spanning the gap.
	for k in 4:
		var f: float = (float(k) + 0.5) / 4.0
		var link: MeshInstance3D = _make_metal_box(
			Vector3(0.014, 0.004, 0.004), MAT.BRONZE, "ClaspLink%d" % k)
		link.transform = Transform3D(Basis(),
			_to_bone_local(skeleton, bones["Chest"],
				Vector3(lerpf(-0.032, 0.032, f), 1.452, -0.072)))
		attach.add_child(link)


static func _to_bone_local(skeleton: Skeleton3D, bone: int, model_pos: Vector3) -> Vector3:
	return skeleton.get_bone_global_rest(bone).affine_inverse() * model_pos


# --- Belt -------------------------------------------------------------------

static func _build_belt(skeleton: Skeleton3D, bones: Dictionary) -> void:
	var rings: Array = []
	var y: float = 0.995
	for i in 2:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 26
		ring.points.resize(n)
		var yy: float = y + (0.022 if i == 0 else -0.022)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			var front_f: float = clampf(-sin(a) * 0.5 + 0.5, 0.0, 1.0)
			var rx: float = 0.140
			var rz: float = lerpf(0.100, 0.096, front_f)
			ring.points[j] = Vector3(cos(a) * rx, yy, sin(a) * rz + 0.005)
		var c: Color = MAT.BELT_BROWN
		c.a = 0.15  # slightly worn edges
		ring.color = c
		ring.bone_a = bones["Hips"]
		rings.append(ring)
	var belt: Dictionary = ML.loft(rings, true, false, false, true)
	var mi: MeshInstance3D = ML.make_instance(belt, MAT.leather(), "Belt")
	skeleton.add_child(mi)
	mi.skin = skeleton.create_skin_from_rest_transforms()

	# Iron buckle at the front.
	var buckle_attach: BoneAttachment3D = BoneAttachment3D.new()
	buckle_attach.name = "BuckleAttach"
	skeleton.add_child(buckle_attach)
	buckle_attach.bone_name = "Hips"
	var buckle: MeshInstance3D = _make_metal_box(
		Vector3(0.052, 0.050, 0.014), MAT.BUCKLE_IRON, "Buckle")
	buckle.transform = Transform3D(Basis.IDENTITY,
		_to_bone_local(skeleton, bones["Hips"], Vector3(0.0, 0.995, -0.102)))
	buckle_attach.add_child(buckle)
	var prong: MeshInstance3D = _make_metal_box(
		Vector3(0.006, 0.030, 0.006), MAT.BUCKLE_IRON, "BuckleProng")
	prong.transform = Transform3D(Basis.IDENTITY,
		_to_bone_local(skeleton, bones["Hips"], Vector3(0.0, 0.995, -0.108)))
	buckle_attach.add_child(prong)

	# Hanging pouch on the left hip.
	_build_pouch(skeleton, bones)


static func _build_pouch(skeleton: Skeleton3D, bones: Dictionary) -> void:
	var rings: Array = []
	# Rounded soft bag: rows top (belt) -> bulging bottom.
	var rows: Array = [
		[1.000, 0.028, 0.020],
		[0.980, 0.036, 0.028],
		[0.958, 0.044, 0.034],
		[0.936, 0.045, 0.035],
		[0.918, 0.038, 0.030],
		[0.908, 0.020, 0.016],
	]
	var i: int = 0
	for row in rows:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 14
		ring.points.resize(n)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			ring.points[j] = Vector3(-0.118 + cos(a) * row[1], row[0],
				sin(a) * row[2] + 0.02)
		var c: Color = MAT.BOOT_BROWN.darkened(0.05)
		c.a = 0.25
		ring.color = c
		ring.bone_a = bones["Hips"]
		ring.v = float(i) / float(rows.size() - 1)
		rings.append(ring)
		i += 1
	var pouch: Dictionary = ML.loft(rings, true, true, true, true)
	var mi: MeshInstance3D = ML.make_instance(pouch, MAT.leather(), "Pouch")
	skeleton.add_child(mi)
	mi.skin = skeleton.create_skin_from_rest_transforms()
	# Flap over the top.
	var flap: MeshInstance3D = _make_leather_box(
		Vector3(0.052, 0.006, 0.040), MAT.BOOT_BROWN.darkened(0.12), "PouchFlap")
	var fa: BoneAttachment3D = BoneAttachment3D.new()
	fa.name = "PouchFlapAttach"
	skeleton.add_child(fa)
	fa.bone_name = "Hips"
	flap.transform = Transform3D(Basis().rotated(Vector3.RIGHT, 0.2),
		_to_bone_local(skeleton, bones["Hips"], Vector3(-0.118, 0.998, 0.022)))
	fa.add_child(flap)


# --- Scarf ------------------------------------------------------------------

static func _build_scarf(skeleton: Skeleton3D, bones: Dictionary) -> void:
	# A loose knitted wrap around the neck with a short tail down the chest.
	var rings: Array = []
	var rows: Array = [
		[1.470, 0.062, 0.060, 0.0],
		[1.452, 0.070, 0.068, 0.002],
		[1.436, 0.076, 0.074, 0.004],
		[1.420, 0.072, 0.072, 0.006],
	]
	var i: int = 0
	for row in rows:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 18
		ring.points.resize(n)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			var lump: float = 1.0 + sin(a * 7.0 + row[0] * 20.0) * 0.06  # knit lumps
			ring.points[j] = Vector3(cos(a) * row[1] * lump, row[0],
				sin(a) * row[2] * lump + row[3])
		var c: Color = MAT.SCARF_RED
		c.a = 0.35
		ring.color = c
		ring.bone_a = bones["Neck"]
		ring.bone_b = bones["Chest"]
		ring.blend = float(i) / float(rows.size() - 1) * 0.5
		ring.v = float(i)
		rings.append(ring)
		i += 1
	var scarf: Dictionary = ML.loft(rings, true, false, false, true)
	var mat: ShaderMaterial = MAT.cloth(120.0, 0.022)  # chunky knit, loose, windy
	var mi: MeshInstance3D = ML.make_instance(scarf, mat, "Scarf")
	skeleton.add_child(mi)
	mi.skin = skeleton.create_skin_from_rest_transforms()

	# Tail: a hanging end draped over the left chest.
	var tail_path: Array[Vector3] = ML.bezier_path(
		Vector3(-0.055, 1.430, -0.055),
		Vector3(-0.085, 1.360, -0.085),
		Vector3(-0.070, 1.280, -0.090),
		Vector3(-0.090, 1.190, -0.070), 8)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for k in tail_path.size():
		radii.append(0.030 - 0.001 * k)
	var tail_rings: Array = ML.tube_rings(tail_path, radii, 10, 0.35)
	for idx in tail_rings.size():
		var ring: ML.Ring = tail_rings[idx]
		var c: Color = MAT.SCARF_RED.darkened(0.05 + 0.1 * float(idx) / tail_rings.size())
		c.a = 0.7
		ring.color = c
		ring.bone_a = bones["Chest"]
		ring.v = float(idx) / float(tail_rings.size() - 1)
	var tail: Dictionary = ML.loft(tail_rings, true, true, true, true)
	var tmi: MeshInstance3D = ML.make_instance(tail, mat, "ScarfTail")
	skeleton.add_child(tmi)
	tmi.skin = skeleton.create_skin_from_rest_transforms()


# --- Boots ------------------------------------------------------------------

static func _build_boot(foot_attach: BoneAttachment3D, right: bool) -> void:
	var root: Node3D = Node3D.new()
	root.name = "BootR" if right else "BootL"
	# The foot bone sits at the ankle; build the boot in local space around it.
	var parts_leather: Array[Dictionary] = []
	# Ankle cuff + shaft going up.
	var shaft: Array = []
	var shaft_rows: Array = [
		[0.145, 0.052, 0.052],   # cuff top (folded over)
		[0.120, 0.048, 0.048],
		[0.090, 0.050, 0.055],
		[0.045, 0.055, 0.070],   # around the ankle
		[0.010, 0.058, 0.085],   # instep
	]
	var i: int = 0
	for row in shaft_rows:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 14
		ring.points.resize(n)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			ring.points[j] = Vector3(cos(a) * row[1], row[0], sin(a) * row[2] - 0.01)
		var c: Color = MAT.BOOT_BROWN
		if i == 0:
			c = MAT.BOOT_BROWN.lightened(0.05)  # cuff catches light
		c.a = 0.35 if i == 0 else 0.15
		ring.color = c
		ring.v = float(i) * 0.4
		shaft.append(ring)
		i += 1
	parts_leather.append(ML.loft(shaft, true, true, false))

	# Foot: instep ring swept forward to a rounded toe.
	var foot_rows: Array = []
	var foot_path: Array = [
		[0.010, -0.010, 0.058, 0.045],
		[0.006, -0.055, 0.060, 0.050],
		[0.004, -0.100, 0.058, 0.052],
		[0.006, -0.140, 0.050, 0.048],
		[0.014, -0.170, 0.036, 0.038],
		[0.026, -0.186, 0.018, 0.024],
	]
	for row in foot_path:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 14
		ring.points.resize(n)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			# Flatten the sole (bottom half squashed up).
			var y: float = sin(a)
			var sole: float = 1.0 if y > 0.0 else 0.55
			ring.points[j] = Vector3(cos(a) * row[2], row[0] + y * row[3] * sole, row[1])
		var c: Color = MAT.BOOT_BROWN.darkened(0.03)
		c.a = 0.2
		ring.color = c
		foot_rows.append(ring)
	parts_leather.append(ML.loft(foot_rows, true, false, true))

	var boot_mesh: Dictionary = ML.merge(parts_leather)
	if not right:
		boot_mesh = ML.mirror_x(boot_mesh)
	root.add_child(ML.make_instance(boot_mesh, MAT.leather(), "BootLeather"))

	# Sole slab (darker, harder).
	var sole_box: MeshInstance3D = _make_leather_box(
		Vector3(0.11, 0.020, 0.22), MAT.GRIP_BROWN, "Sole")
	sole_box.position = Vector3(0.0, -0.028, -0.085)
	root.add_child(sole_box)

	# Cross-laces up the front of the shaft, with eyelet knots at each rung.
	var lace_parts: Array[Dictionary] = []
	var rungs: int = 6
	for k in rungs:
		var yy: float = 0.022 + 0.020 * k
		var z: float = -0.076 - 0.001 * k
		for dir in [-1.0, 1.0]:
			var p0: Vector3 = Vector3(-0.021 * dir, yy, z)
			var p1: Vector3 = Vector3(0.021 * dir, yy + 0.020, z - 0.002)
			var radii: PackedFloat32Array = PackedFloat32Array([0.0024, 0.0024])
			var rr: Array = ML.tube_rings([p0, p1], radii, 6)
			for r_any in rr:
				var ring: ML.Ring = r_any
				ring.color = MAT.GRIP_BROWN
			lace_parts.append(ML.loft(rr, true, true, true))
		# Eyelet knots (little metal-ish beads) at the rung sides.
		for dir2 in [-1.0, 1.0]:
			lace_parts.append(_lace_knot(Vector3(0.021 * dir2, yy, z - 0.001)))
	var laces: Dictionary = ML.merge(lace_parts)
	if not right:
		laces = ML.mirror_x(laces)
	root.add_child(ML.make_instance(laces, MAT.leather(), "BootLaces"))

	# Ankle strap with a small buckle wrapping the shaft.
	var strap: MeshInstance3D = _make_leather_box(
		Vector3(0.115, 0.016, 0.115), MAT.BELT_BROWN, "BootStrap")
	strap.position = Vector3(0.0, 0.085, -0.006)
	root.add_child(strap)
	var strap_buckle: MeshInstance3D = _make_metal_box(
		Vector3(0.018, 0.020, 0.010), MAT.BUCKLE_IRON, "BootBuckle")
	strap_buckle.position = Vector3(0.0, 0.085, -0.066)
	root.add_child(strap_buckle)

	foot_attach.add_child(root)


static func _lace_knot(pos: Vector3) -> Dictionary:
	var rings: Array = []
	for i in 2:
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 6
		ring.points.resize(n)
		var r: float = 0.0032 * (1.0 if i == 0 else 0.7)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			ring.points[j] = pos + Vector3(cos(a) * r, sin(a) * r,
				-0.002 * float(i) - 0.001)
		ring.color = MAT.GRIP_BROWN.lightened(0.1)
		ring.v = float(i)
		rings.append(ring)
	return ML.loft(rings, true, true, true)


# --- Sword + scabbard -------------------------------------------------------

## Sword pivot compatible with the legacy rest pose so combat poses transfer.
static func _build_sword() -> Node3D:
	var sword: Node3D = Node3D.new()
	sword.name = "TravelerSword"
	var metal: ShaderMaterial = MAT.metal(2.1)

	# Blade: a lofted double-edged leaf with a central fuller and honed edges.
	var blade_rows: int = 14
	var rings: Array = []
	for i in blade_rows:
		var t: float = float(i) / float(blade_rows - 1)
		var y: float = lerpf(-0.02, 0.78, t)
		# Width tapers to the point; slight leaf swell low on the blade.
		var half_w: float = lerpf(0.030, 0.004, pow(t, 1.3)) * (1.0 + 0.15 * sin(t * PI))
		var thick: float = lerpf(0.010, 0.003, t)
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 12
		ring.points.resize(n)
		var pc: PackedColorArray = PackedColorArray()
		for j in n:
			var a: float = TAU * float(j) / float(n)
			# Diamond cross-section: fuller groove near the flats' centre.
			var cx: float = cos(a)
			var fuller: float = 1.0 - 0.45 * _bump(sin(a))  # dip on the flats
			var x: float = cx * half_w
			var z: float = sin(a) * thick * fuller
			ring.points[j] = Vector3(x, y, z)
			var c: Color = MAT.STEEL
			# Edge mask (COLOR.a) high on the extreme sides = honed bright line.
			var edge: float = smoothstep(0.85, 1.0, absf(cx))
			c.a = edge
			pc.append(c)
		ring.point_colors = pc
		ring.v = t
		rings.append(ring)
	var blade: Dictionary = ML.loft(rings, true, true, true)
	var blade_mi: MeshInstance3D = ML.make_instance(blade, metal, "Blade")
	sword.add_child(blade_mi)

	# Guard: bronze cross with slightly flared quillons.
	var guard: MeshInstance3D = _make_metal_box(
		Vector3(0.20, 0.028, 0.05), MAT.BRONZE, "Guard")
	guard.position = Vector3(0.0, -0.028, 0.0)
	guard.material_override = MAT.metal(1.6)
	sword.add_child(guard)
	for side in [-1.0, 1.0]:
		var tip: MeshInstance3D = _make_metal_box(
			Vector3(0.024, 0.024, 0.044), MAT.BRONZE, "Quillon%s" % side)
		tip.position = Vector3(side * 0.10, -0.028, 0.0)
		tip.rotation = Vector3(0.0, 0.0, side * -0.35)
		tip.material_override = MAT.metal(1.6)
		sword.add_child(tip)

	# Grip: wrapped leather cylinder with a visible spiral wrap groove.
	var grip_path: Array[Vector3] = [
		Vector3(0.0, -0.045, 0.0), Vector3(0.0, -0.150, 0.0)]
	var grip_radii: PackedFloat32Array = PackedFloat32Array([0.017, 0.016])
	var grip_rings: Array = ML.tube_rings(grip_path, grip_radii, 12)
	# Subdivide for the wrap: add mid rings so the spiral reads.
	var wrapped: Array = []
	var count: int = 10
	for i in count:
		var t: float = float(i) / float(count - 1)
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 12
		ring.points.resize(n)
		var y: float = lerpf(-0.045, -0.150, t)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			# Spiral ridge: radius pulses with (angle + t) to fake wrap turns.
			var wrap: float = 0.0012 * sin((a * 2.0 + t * 22.0))
			var r: float = 0.0165 + wrap
			ring.points[j] = Vector3(cos(a) * r, y, sin(a) * r)
		ring.color = MAT.GRIP_BROWN
		ring.v = t * 3.0
		wrapped.append(ring)
	var grip: Dictionary = ML.loft(wrapped, true, true, true)
	sword.add_child(ML.make_instance(grip, MAT.leather(), "Grip"))

	# Pommel: bronze disc bearing the glowing sigil (echo of the hand-mark).
	var pommel: SphereMesh = SphereMesh.new()
	pommel.radius = 0.022
	pommel.height = 0.036
	pommel.radial_segments = 16
	pommel.rings = 8
	var pommel_mi: MeshInstance3D = MeshInstance3D.new()
	pommel_mi.name = "Pommel"
	pommel_mi.mesh = pommel
	pommel_mi.material_override = MAT.metal(1.6)
	pommel_mi.position = Vector3(0.0, -0.168, 0.0)
	sword.add_child(pommel_mi)
	var sigil: MeshInstance3D = MeshInstance3D.new()
	var sigil_mesh: TorusMesh = TorusMesh.new()
	sigil_mesh.inner_radius = 0.006
	sigil_mesh.outer_radius = 0.010
	sigil_mesh.rings = 20
	sigil_mesh.ring_segments = 10
	sigil.name = "PommelSigil"
	sigil.mesh = sigil_mesh
	sigil.material_override = MAT.glow()
	sigil.position = Vector3(0.0, -0.168, 0.023)
	sigil.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	sword.add_child(sigil)
	return sword


static func _build_scabbard(skeleton: Skeleton3D, bones: Dictionary) -> void:
	# Sheath slung across the left hip, angled back.
	var attach: BoneAttachment3D = BoneAttachment3D.new()
	attach.name = "ScabbardAttach"
	skeleton.add_child(attach)
	attach.bone_name = "Hips"
	var root: Node3D = Node3D.new()
	root.name = "Scabbard"
	# Local transform: to the left hip, tilted so the tip trails back.
	root.transform = Transform3D(
		Basis().rotated(Vector3.FORWARD, 0.42).rotated(Vector3.RIGHT, -0.28),
		_to_bone_local(skeleton, bones["Hips"], Vector3(-0.135, 0.965, 0.045)))
	attach.add_child(root)

	var rings: Array = []
	var rows: int = 10
	for i in rows:
		var t: float = float(i) / float(rows - 1)
		var y: float = lerpf(0.06, -0.62, t)
		var half_w: float = lerpf(0.036, 0.020, smoothstep(0.7, 1.0, t))
		var thick: float = lerpf(0.020, 0.012, smoothstep(0.7, 1.0, t))
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 12
		ring.points.resize(n)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			ring.points[j] = Vector3(cos(a) * half_w, y, sin(a) * thick)
		var c: Color = MAT.SCABBARD_BROWN
		c.a = 0.15
		ring.color = c
		ring.v = t * 2.0
		rings.append(ring)
	root.add_child(ML.make_instance(ML.loft(rings, true, true, true),
		MAT.leather(), "ScabbardBody"))
	# Bronze throat + chape.
	var throat: MeshInstance3D = _make_metal_box(
		Vector3(0.078, 0.028, 0.046), MAT.BRONZE, "ScabbardThroat")
	throat.position = Vector3(0.0, 0.05, 0.0)
	throat.material_override = MAT.metal(1.4)
	root.add_child(throat)
	var chape: MeshInstance3D = _make_metal_box(
		Vector3(0.044, 0.05, 0.028), MAT.BRONZE, "ScabbardChape")
	chape.position = Vector3(0.0, -0.60, 0.0)
	chape.material_override = MAT.metal(1.4)
	root.add_child(chape)


# --- small helpers ----------------------------------------------------------

static func _bump(x: float) -> float:
	# 1 near x=0, 0 by |x|~0.5 — for the fuller groove on the blade flats.
	return clampf(1.0 - absf(x) * 2.0, 0.0, 1.0)


static func _make_metal_box(size: Vector3, color: Color, part_name: String) -> MeshInstance3D:
	return _make_box(size, color, part_name, MAT.metal(1.6), 0.6)


static func _make_leather_box(size: Vector3, color: Color, part_name: String) -> MeshInstance3D:
	return _make_box(size, color, part_name, MAT.leather(), 0.15)


static func _make_box(size: Vector3, color: Color, part_name: String,
		material: ShaderMaterial, alpha: float) -> MeshInstance3D:
	# BoxMesh has no per-vertex COLOR; paint it via a per-instance tint by
	# baking COLOR into an ArrayMesh box so the character shaders work.
	var mesh: ArrayMesh = _color_box(size, Color(color.r, color.g, color.b, alpha))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = material
	return mi


static func _color_box(size: Vector3, color: Color) -> ArrayMesh:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 6 faces, flat normals, simple UVs, uniform color.
	var faces: Array = [
		[Vector3(0, 0, 1), [Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
			Vector3(hx, hy, hz), Vector3(-hx, hy, hz)]],
		[Vector3(0, 0, -1), [Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz),
			Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz)]],
		[Vector3(1, 0, 0), [Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz),
			Vector3(hx, hy, -hz), Vector3(hx, hy, hz)]],
		[Vector3(-1, 0, 0), [Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz),
			Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz)]],
		[Vector3(0, 1, 0), [Vector3(-hx, hy, hz), Vector3(hx, hy, hz),
			Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz)]],
		[Vector3(0, -1, 0), [Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
			Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz)]],
	]
	var uvs: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for face in faces:
		var normal: Vector3 = face[0]
		var quad: Array = face[1]
		var order: Array = [0, 1, 2, 0, 2, 3]
		for oi in order:
			st.set_color(color)
			st.set_normal(normal)
			st.set_uv(uvs[oi])
			st.add_vertex(quad[oi])
	st.generate_tangents()
	return st.commit()

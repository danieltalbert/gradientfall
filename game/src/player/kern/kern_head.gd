class_name KernHead
extends Node3D
## Kern's sculpted head. A displaced latitude/longitude skull field carries
## the facial planes (brow ridge, eye sockets, nasal bridge, cheekbones,
## cheek hollows, muzzle, philtrum, chin ball, gonial jaw corners, temples,
## occiput); separate lofts add the nose (with alae + nostril shadows),
## cupid's-bow lips, ears (helix rim, concha bowl, antihelix, tragus, lobe),
## analytic eyes (corneal bulge, iris shader, upper/lower lids, lash strips,
## caruncles) and a ~55-clump layered chestnut haircut over a scalp shell.
##
## Everything is authored in model space, then shifted so this node's origin
## sits at the skull-base pivot (the Head bone) — rotate this node and the
## head moves like a head. Public animation API: set_blink(), set_gaze().

const ML: GDScript = preload("res://src/player/kern/kern_mesh_lib.gd")
const KM: GDScript = preload("res://src/player/kern/kern_materials.gd")

const CENTER_Z: float = 0.008
const EYE_T: float = 0.435          # socket latitude
const EYE_PSI: float = 0.33         # socket azimuth off the midline
const EYE_R: float = 0.0140         # eyeball radius (reads better a touch large)

var _pivot: Vector3 = Vector3.ZERO
var _eye_l: Node3D
var _eye_r: Node3D
var _upper_lid_l: Node3D
var _upper_lid_r: Node3D
var _lower_lid_l: Node3D
var _lower_lid_r: Node3D


func build(pivot: Vector3) -> void:
	_pivot = pivot
	var skin_parts: Array[Dictionary] = []
	skin_parts.append(_skull_surface())
	skin_parts.append(_nose_surface())
	skin_parts.append_array(_lip_surfaces())
	var ear: Dictionary = _ear_surface()
	skin_parts.append(ML.mirror_x(ear))   # left ear (left = -X)
	skin_parts.append(ear)                # right ear (built at +X)
	var face: Dictionary = ML.merge(skin_parts)
	_shift(face)
	add_child(ML.make_instance(face, KM.skin(), "FaceMesh"))

	var hair: Dictionary = _hair_surface()
	_shift(hair)
	add_child(ML.make_instance(hair, KM.hair(), "HairMesh"))

	var brows: Dictionary = ML.merge([_brow_surface(-1.0), _brow_surface(1.0)])
	_shift(brows)
	add_child(ML.make_instance(brows, KM.brow(), "Brows"))

	_build_eye(false)
	_build_eye(true)


## blink: 0 = open, 1 = closed. Upper lid does most of the travel, rotating its
## dome down over the aperture; the lower lid rises a little to meet it.
func set_blink(blink: float) -> void:
	var upper: float = -0.95 * blink
	var lower: float = 0.42 * blink
	_upper_lid_l.rotation.x = upper
	_upper_lid_r.rotation.x = upper
	_lower_lid_l.rotation.x = lower
	_lower_lid_r.rotation.x = lower


## Small conjugate eye rotations (radians). Both eyes track together.
func set_gaze(yaw: float, pitch: float) -> void:
	_eye_l.rotation = Vector3(pitch, yaw, 0.0)
	_eye_r.rotation = Vector3(pitch, yaw, 0.0)


func _shift(surface: Dictionary) -> void:
	ML.transform_surface(surface, Transform3D(Basis.IDENTITY, -_pivot))


# --- The skull field --------------------------------------------------------

## Base cross-section profile per latitude t (0 crown -> 1 under-jaw pole):
## [t, y, rx, rz_front, rz_back, z_off]
# Narrower cheeks and a more tapered jaw than a round head — a leaner, more
# defined hero's face.
const PROFILE: Array = [
	[0.00, 1.7720, 0.0040, 0.0040, 0.0040, 0.004],
	[0.07, 1.7625, 0.0420, 0.0460, 0.0510, 0.004],
	[0.15, 1.7455, 0.0600, 0.0660, 0.0750, 0.002],
	[0.24, 1.7185, 0.0700, 0.0800, 0.0910, 0.000],
	[0.34, 1.6890, 0.0730, 0.0870, 0.0985, 0.000],
	[0.44, 1.6595, 0.0728, 0.0835, 0.0985, 0.000],
	[0.54, 1.6315, 0.0688, 0.0850, 0.0910, 0.000],
	[0.64, 1.6050, 0.0608, 0.0835, 0.0770, -0.001],
	[0.74, 1.5820, 0.0520, 0.0810, 0.0630, -0.002],
	[0.84, 1.5610, 0.0420, 0.0740, 0.0510, -0.003],
	[0.92, 1.5480, 0.0310, 0.0600, 0.0410, -0.002],
	[0.97, 1.5430, 0.0190, 0.0400, 0.0300, 0.002],
	[1.00, 1.5400, 0.0030, 0.0050, 0.0050, 0.008],
]


func _profile_at(t: float) -> Array:
	for i in PROFILE.size() - 1:
		var a: Array = PROFILE[i]
		var b: Array = PROFILE[i + 1]
		if t <= float(b[0]):
			var f: float = smoothstep(0.0, 1.0, (t - float(a[0])) / (float(b[0]) - float(a[0])))
			var out: Array = []
			for k in range(1, 6):
				out.append(lerpf(float(a[k]), float(b[k]), f))
			return out
	return [1.5410, 0.003, 0.005, 0.005, 0.008]


static func _g(u: float) -> float:
	return exp(-u * u)


## The sculpt: base profile point at (t, psi) plus every facial feature.
## psi = azimuth from the face midline (0 front, +right/+X, pi back).
func _skull_point(t: float, psi: float) -> Vector3:
	var prof: Array = _profile_at(t)
	var y: float = prof[0]
	var rx: float = prof[1]
	var rzf: float = prof[2]
	var rzb: float = prof[3]
	var z_off: float = prof[4] + CENTER_Z
	var a: float = psi - PI * 0.5
	var front_f: float = clampf(-sin(a) * 0.5 + 0.5, 0.0, 1.0)
	var rz: float = lerpf(rzb, rzf, front_f)
	var x: float = cos(a) * rx
	var z: float = sin(a) * rz + z_off
	var p: Vector3 = Vector3(x, y, z)
	var outward: Vector3 = Vector3(x, 0.0, z - z_off)
	if outward.length_squared() < 0.000001:
		return p
	outward = outward.normalized()
	var ap: float = absf(psi)
	var d: float = 0.0
	# Brow ridge, heaviest right above each eye (sharper than before).
	d += 0.0062 * _g((t - 0.350) / 0.028) * _g(ap / 0.60) \
		* (0.5 + 0.75 * _g((ap - 0.33) / 0.16))
	# Upper orbital rim: a firm ridge on the socket's top edge.
	d += 0.0026 * _g((t - 0.392) / 0.022) * _g((ap - EYE_PSI) / 0.15)
	# Eye sockets — deeper, so the eyeball reads as set into the skull.
	d -= 0.0120 * _g((t - EYE_T) / 0.044) * _g((ap - EYE_PSI) / 0.135)
	# Upper-lid crease: a groove just above the lash line.
	d -= 0.0030 * _g((t - 0.415) / 0.016) * _g((ap - EYE_PSI) / 0.13)
	# Lower-lid / tear trough: soft valley below the inner eye.
	d -= 0.0026 * _g((t - 0.475) / 0.022) * _g((ap - EYE_PSI * 0.86) / 0.12)
	d += 0.0014 * _g((t - 0.492) / 0.014) * _g((ap - EYE_PSI) / 0.13)  # lid bag ridge
	# Nasal bridge riser between the eyes, tapering down the dorsum.
	d += 0.0044 * _g(psi / 0.070) * _g((t - 0.44) / 0.05)
	# Malar cheekbones — sharper and a touch higher.
	d += 0.0056 * _g((t - 0.520) / 0.040) * _g((ap - 0.50) / 0.14)
	# Cheek hollow beneath the bone.
	d -= 0.0030 * _g((t - 0.610) / 0.055) * _g((ap - 0.44) / 0.17)
	# Muzzle roundness (dental arch pushing the mouth area forward).
	d += 0.0046 * _g((t - 0.75) / 0.065) * _g(psi / 0.24)
	# Nasolabial fold: crease running from the nose wing toward the mouth
	# corner (approximated as a valley on the cheek beside the mouth).
	d -= 0.0030 * _g((t - 0.720) / 0.045) * _g((ap - 0.235) / 0.075)
	# Philtrum groove above the upper lip, with its two flanking ridges.
	d -= 0.0018 * _g(psi / 0.035) * _g((t - 0.725) / 0.026)
	d += 0.0009 * _g((ap - 0.055) / 0.03) * _g((t - 0.725) / 0.03)
	# Labiomental crease: horizontal groove between lower lip and chin.
	d -= 0.0024 * _g((t - 0.828) / 0.018) * _g(psi / 0.16)
	# Chin ball with a whisper of a central cleft.
	d += 0.0068 * _g((t - 0.882) / 0.044) * _g(psi / 0.15)
	d -= 0.0012 * _g(psi / 0.028) * _g((t - 0.892) / 0.038)
	# Gonial jaw corners and the jawline edge that separates face from neck.
	d += 0.0050 * _g((t - 0.72) / 0.065) * _g((ap - 0.95) / 0.17)
	d += 0.0022 * _g((t - 0.80) / 0.042) * _g((ap - 0.75) / 0.33)
	# Temple flats.
	d -= 0.0030 * _g((t - 0.30) / 0.055) * _g((ap - 0.75) / 0.15)
	# Occipital swell at the back of the skull.
	d += 0.0042 * _g((t - 0.33) / 0.10) * _g((ap - PI) / 0.5)
	# Slight dish where the ears mount (hides the ear seam).
	d -= 0.0022 * _g((t - 0.52) / 0.06) * _g((ap - 1.62) / 0.12)
	# Faint asymmetry so the face isn't mirror-perfect (reads more alive).
	d += 0.0006 * sin(psi * 3.0) * _g((t - 0.55) / 0.25)
	return p + outward * d


func _skull_normal_out(t: float, psi: float) -> Vector3:
	var p: Vector3 = _skull_point(t, psi)
	var flat: Vector3 = Vector3(p.x, 0.0, p.z - CENTER_Z)
	if flat.length_squared() < 0.000001:
		return Vector3(0.0, 1.0, 0.0)
	return flat.normalized()


func _skull_surface() -> Dictionary:
	var rows: int = 72
	var n: int = 96
	var rings: Array = []
	for i in rows:
		var t: float = float(i) / float(rows - 1)
		var ring: ML.Ring = ML.Ring.new()
		ring.points.resize(n)
		var pc: PackedColorArray = PackedColorArray()
		for j in n:
			var a: float = TAU * float(j) / float(n)
			var psi: float = wrapf(a + PI * 0.5, -PI, PI)
			ring.points[j] = _skull_point(t, psi)
			pc.append(_skin_paint(t, psi))
		ring.point_colors = pc
		ring.v = t * 1.2
		rings.append(ring)
	return ML.loft(rings, true, false, false)


func _skin_paint(t: float, psi: float) -> Color:
	var ap: float = absf(psi)
	var c: Color = KM.SKIN_BASE
	# Forehead catches a touch more light-value.
	c = c.lightened(0.03 * _g((t - 0.28) / 0.08) * _g(ap / 0.7))
	# Socket shadow tint (the eye sits in shadow — bake the ambient occlusion).
	c = c.lerp(KM.SKIN_SHADOWED, 0.60 * _g((t - EYE_T) / 0.05) * _g((ap - EYE_PSI) / 0.15))
	# Cheek flush.
	c = c.lerp(KM.SKIN_FLUSH, 0.42 * _g((t - 0.57) / 0.07) * _g((ap - 0.48) / 0.22))
	# Warmth around the mouth / chin shadow under the lip.
	c = c.lerp(KM.LIP_COLOR, 0.16 * _g((t - 0.77) / 0.05) * _g(psi / 0.22))
	# --- Baked crease occlusion: darken the valleys the sculpt now carries so
	# they read as real creases even under flat light. ---
	var ao: float = 0.0
	ao += 0.22 * _g((t - 0.415) / 0.014) * _g((ap - EYE_PSI) / 0.13)   # upper-lid crease
	ao += 0.16 * _g((t - 0.475) / 0.020) * _g((ap - EYE_PSI * 0.86) / 0.11)  # tear trough
	ao += 0.20 * _g((t - 0.720) / 0.040) * _g((ap - 0.235) / 0.070)   # nasolabial
	ao += 0.14 * _g((t - 0.828) / 0.016) * _g(psi / 0.15)             # labiomental
	ao += 0.12 * _g(psi / 0.032) * _g((t - 0.725) / 0.024)            # philtrum
	ao += 0.10 * _g((t - 0.612) / 0.05) * _g((ap - 0.44) / 0.16)      # cheek hollow
	c = c.darkened(clampf(ao, 0.0, 0.4))
	# Malar highlight: the cheekbone catches a hair more light.
	c = c.lightened(0.04 * _g((t - 0.520) / 0.035) * _g((ap - 0.50) / 0.13))
	# Under-jaw ambient shadow.
	c = c.darkened(0.12 * clampf((t - 0.90) / 0.08, 0.0, 1.0))
	# Thinness (COLOR.a): thin at nostril rims / lip edge / ear-adjacent skin.
	var thin: float = 0.85
	thin -= 0.25 * _g((t - 0.79) / 0.03) * _g(psi / 0.20)  # lips edge translucency
	c.a = clampf(thin, 0.4, 1.0)
	return c


# --- Nose -------------------------------------------------------------------

func _nose_surface() -> Dictionary:
	var nasion: Vector3 = _skull_point(0.42, 0.0) + Vector3(0.0, 0.0, 0.004)
	var tip: Vector3 = nasion + Vector3(0.0, -0.050, -0.0265)
	var axis: Vector3 = (tip - nasion).normalized()
	var rows: int = 12
	var rings: Array = []
	for i in rows:
		var t: float = float(i) / float(rows - 1)
		var center: Vector3 = nasion.lerp(tip, t)
		# Dorsum bows very slightly (a straight nose still isn't a ruler).
		center.z -= sin(t * PI) * 0.0012
		var r: float = _nose_radius(t)
		var ring: ML.Ring = ML.Ring.new()
		var seg: int = 14
		ring.points.resize(seg)
		var pc: PackedColorArray = PackedColorArray()
		# Frame perpendicular to the nose axis.
		var u: Vector3 = Vector3.RIGHT
		var w: Vector3 = axis.cross(u).normalized()
		u = w.cross(axis).normalized()
		for j in seg:
			var a: float = TAU * float(j) / float(seg)
			var rr: float = r
			# Alae wings flare sideways near the base.
			var side: float = absf(cos(a))
			rr += 0.0068 * _g((t - 0.82) / 0.10) * pow(side, 2.0)
			# Slight vertical squash: the nose is deeper than wide up top.
			var pt: Vector3 = center + u * (cos(a) * rr) + w * (sin(a) * rr * 0.86)
			ring.points[j] = pt
			var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.25 + 0.35 * t)
			# Nostril shadow on the under-side points near the base.
			if t > 0.80 and sin(a) > 0.35 and side > 0.25:
				c = c.darkened(0.55)
			c.a = 0.55  # thin cartilage: glows when backlit
			pc.append(c)
		ring.point_colors = pc
		ring.v = t
		rings.append(ring)
	return ML.loft(rings, true, false, true)


func _nose_radius(t: float) -> float:
	var keys: Array = [
		[0.00, 0.0058], [0.25, 0.0072], [0.50, 0.0085], [0.72, 0.0100],
		[0.86, 0.0108], [1.00, 0.0072],
	]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= float(b[0]):
			var f: float = (t - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, f))
	return 0.0072


# --- Lips -------------------------------------------------------------------

func _lip_surfaces() -> Array[Dictionary]:
	var cols: int = 17
	var half_angle: float = 0.30
	var out: Array[Dictionary] = []

	# Upper lip: skin edge (with cupid's bow) -> vermilion bulge -> lip line.
	var upper: Array = []
	upper.append(_lip_row(cols, half_angle, func(s: float) -> Array:
		var bow: float = 0.8 * _g((absf(s) - 0.32) / 0.22) - 0.5 * _g(s / 0.12)
		return [0.757 - 0.010 * bow, 0.0015, KM.SKIN_BASE.lerp(KM.LIP_COLOR, 0.35), 0.0]))
	upper.append(_lip_row(cols, half_angle, func(s: float) -> Array:
		var taper: float = pow(cos(s * PI * 0.5), 0.7)
		return [0.772, 0.0042 * taper, KM.LIP_COLOR, 0.33]))
	upper.append(_lip_row(cols, half_angle, func(s: float) -> Array:
		var corner_lift: float = 0.004 * _g((absf(s) - 1.0) / 0.15)
		return [0.7845 - corner_lift, 0.0016,
			Color(0.30, 0.13, 0.11), 0.66]))
	out.append(ML.loft(upper, false))

	# Lower lip: lip line -> fuller bulge -> blend into the chin.
	var lower: Array = []
	lower.append(_lip_row(cols, half_angle * 0.94, func(s: float) -> Array:
		var corner_lift: float = 0.004 * _g((absf(s) - 1.0) / 0.15)
		return [0.7865 - corner_lift, 0.0014,
			Color(0.30, 0.13, 0.11), 0.0]))
	lower.append(_lip_row(cols, half_angle * 0.88, func(s: float) -> Array:
		var taper: float = pow(cos(s * PI * 0.5), 0.7)
		return [0.803, 0.0052 * taper, KM.LIP_COLOR.lightened(0.06), 0.5]))
	lower.append(_lip_row(cols, half_angle * 0.86, func(s: float) -> Array:
		return [0.818, 0.0012, KM.SKIN_BASE.lerp(KM.LIP_COLOR, 0.22), 1.0]))
	out.append(ML.loft(lower, false))
	return out


## One lip strip row. spec(s) -> [t, push, color, v].
func _lip_row(cols: int, half_angle: float, spec: Callable) -> ML.Ring:
	var ring: ML.Ring = ML.Ring.new()
	ring.points.resize(cols)
	var pc: PackedColorArray = PackedColorArray()
	var v_row: float = 0.0
	for j in cols:
		var s: float = lerpf(-1.0, 1.0, float(j) / float(cols - 1))
		var row: Array = spec.call(s)
		var t: float = row[0]
		var push: float = row[1]
		var psi: float = s * half_angle
		var p: Vector3 = _skull_point(t, psi) + _skull_normal_out(t, psi) * push
		ring.points[j] = p
		var c: Color = row[2]
		if absf(s) > 0.9:
			c = c.darkened(0.18)  # corner pinch shadow
		c.a = 0.6
		pc.append(c)
		v_row = row[3]
	ring.point_colors = pc
	ring.v = v_row
	return ring


# --- Ears (built at +X, mirrored for the left) ------------------------------

func _ear_surface() -> Dictionary:
	# Ears mount behind the jaw hinge (roughly the coronal midline), not on the
	# cheek. psi ~1.62 sits just aft of the true side.
	var mount: Vector3 = _skull_point(0.52, 1.62)
	var parts: Array[Dictionary] = []
	# Ear-local frame: +X out from the head, backward yaw + slight outward tilt.
	var basis: Basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.UP, -0.32)
	basis = basis.rotated(Vector3.FORWARD, 0.16)
	var xf: Transform3D = Transform3D(basis, mount)

	# Outline of the auricle in the ear's own YZ plane (y up, z toward the
	# face): a long Hylian point — the upper helix pulls up-and-back to a tip,
	# the lobe stays small and rounded (Link-signature elf ear).
	var outline: Array[Vector3] = []
	var samples: int = 20
	for i in samples:
		var a: float = TAU * float(i) / float(samples)
		var s: float = sin(a)
		var ry: float = 0.030
		var rz: float = 0.016
		var y: float = s * ry
		var z: float = cos(a) * rz
		if s < -0.3:
			y *= 0.72  # small lobe
			z *= 0.78
		if s > 0.2:
			# Draw the upper helix out to a point: extend upward and back, and
			# pinch the width toward the tip.
			var up: float = smoothstep(0.2, 1.0, s)
			y += up * 0.028                 # elongate upward
			z += up * 0.014                 # and rearward (toward +z = back)
			z *= (1.0 - up * 0.55)          # pinch to a tip
		outline.append(Vector3(0.0, y + 0.002, z - 0.002))
	outline.append(outline[0])

	# Helix rim: tube around the outline, thinning toward the pointed tip.
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in outline.size():
		var a: float = TAU * float(i % samples) / float(samples)
		var s: float = sin(a)
		var r: float = 0.0046 if s < -0.3 else 0.0036
		if s > 0.4:
			r = lerpf(0.0036, 0.0018, smoothstep(0.4, 1.0, s))  # taper to tip
		radii.append(r)
	var rim_rings: Array = ML.tube_rings(outline, radii, 8)
	for r_any in rim_rings:
		var ring: ML.Ring = r_any
		var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.30)
		c.a = 0.62  # thin, but not so thin it glows lantern-orange in daylight
		ring.color = c
	parts.append(ML.loft(rim_rings, true))

	# Concha bowl: outline shrinking inward and sinking toward the head.
	var bowl: Array = []
	var scales: Array = [0.82, 0.48, 0.14]
	var sink: Array = [0.0015, -0.006, -0.011]
	for k in 3:
		var ring: ML.Ring = ML.Ring.new()
		ring.points.resize(samples)
		for i in samples:
			var p: Vector3 = outline[i]
			ring.points[i] = Vector3(float(sink[k]),
				p.y * float(scales[k]), p.z * float(scales[k]))
		var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.5).darkened(0.10 * float(k))
		c.a = 0.58
		ring.color = c
		ring.v = float(k) * 0.5
		bowl.append(ring)
	parts.append(ML.loft(bowl, true, false, true))

	# Antihelix ridge: a short bent tube inside the bowl.
	var anti_path: Array[Vector3] = [
		Vector3(0.004, -0.012, -0.010), Vector3(0.006, 0.002, -0.012),
		Vector3(0.006, 0.014, -0.006), Vector3(0.004, 0.020, 0.004),
	]
	var anti_radii: PackedFloat32Array = PackedFloat32Array([0.0028, 0.0034, 0.0032, 0.0022])
	var anti: Array = ML.tube_rings(anti_path, anti_radii, 7)
	for r_any in anti:
		var ring: ML.Ring = r_any
		var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.4)
		c.a = 0.58
		ring.color = c
	parts.append(ML.loft(anti, true, true, true))

	# Tragus nub guarding the ear canal.
	var tragus_path: Array[Vector3] = [
		Vector3(0.001, -0.004, 0.013), Vector3(0.005, -0.001, 0.010),
		Vector3(0.004, 0.003, 0.008),
	]
	var tragus_radii: PackedFloat32Array = PackedFloat32Array([0.0030, 0.0034, 0.0020])
	var tragus: Array = ML.tube_rings(tragus_path, tragus_radii, 7)
	for r_any in tragus:
		var ring: ML.Ring = r_any
		var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.35)
		c.a = 0.6
		ring.color = c
	parts.append(ML.loft(tragus, true, true, true))

	var merged: Dictionary = ML.merge(parts)
	return ML.transform_surface(merged, xf)


# --- Brows ------------------------------------------------------------------

func _brow_surface(side: float) -> Dictionary:
	var path: Array[Vector3] = []
	var samples: int = 10
	for i in samples:
		var s: float = float(i) / float(samples - 1)
		var psi: float = side * (0.130 + 0.40 * s)
		# Sit low on the brow ridge, just above the eye, arching gently.
		var t: float = 0.392 - 0.014 * _g((s - 0.40) / 0.32) + 0.010 * pow(s, 3.0)
		path.append(_skull_point(t, psi) + _skull_normal_out(t, psi) * 0.0030)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in samples:
		var s: float = float(i) / float(samples - 1)
		radii.append(lerpf(0.0026, 0.0009, pow(s, 1.2)))
	var rings: Array = ML.tube_rings(path, radii, 7, 0.5)
	for i in rings.size():
		var ring: ML.Ring = rings[i]
		ring.v = float(i) / float(rings.size() - 1)
		var mul: float = 0.9 + 0.2 * ML.hash1(float(i) * 3.7 + side)
		ring.color = Color(mul, mul, mul)
	return ML.loft(rings, true, true, true)


# --- Eyes -------------------------------------------------------------------

func _build_eye(right: bool) -> void:
	var side: float = 1.0 if right else -1.0
	var socket: Vector3 = _skull_point(EYE_T, side * EYE_PSI)
	var out_dir: Vector3 = _skull_normal_out(EYE_T, side * EYE_PSI)
	# A near-flat almond eye set flush into the socket — no protruding orb to
	# cover, so it never goes bug-eyed. The sculpted socket + lash lines frame
	# it; the sclera/iris/pupil/catchlight give it life.
	var center: Vector3 = socket - out_dir * 0.0020 - _pivot
	var fwd: Basis = Basis.IDENTITY.rotated(Vector3.UP, side * -0.06)

	var eye_root: Node3D = Node3D.new()
	eye_root.name = "EyeR" if right else "EyeL"
	eye_root.position = center
	eye_root.basis = fwd
	add_child(eye_root)
	_build_eyeball(eye_root)
	if right:
		_eye_r = eye_root
	else:
		_eye_l = eye_root

	# Upper + lower lash lines frame the almond. The upper is a thick dark
	# curve (the lid margin), the lower a fine one. Built on blink pivots so a
	# blink can drop the upper line + a skin shutter over the eye.
	var upper: Node3D = Node3D.new()
	upper.name = "UpperLid"
	upper.position = center
	upper.basis = fwd
	add_child(upper)
	upper.add_child(_lash_line(side, true))

	var lower: Node3D = Node3D.new()
	lower.name = "LowerLid"
	lower.position = center
	lower.basis = fwd
	add_child(lower)
	lower.add_child(_lash_line(side, false))
	if right:
		_upper_lid_r = upper
		_lower_lid_r = lower
	else:
		_upper_lid_l = upper
		_lower_lid_l = lower

	# Caruncle: the small pink inner-corner wedge.
	var caruncle: SphereMesh = SphereMesh.new()
	caruncle.radius = 0.0020
	caruncle.height = 0.0040
	caruncle.radial_segments = 8
	caruncle.rings = 4
	var car_node: MeshInstance3D = MeshInstance3D.new()
	car_node.name = "CaruncleR" if right else "CaruncleL"
	car_node.mesh = caruncle
	var car_mat: StandardMaterial3D = StandardMaterial3D.new()
	car_mat.albedo_color = Color(0.74, 0.40, 0.36)
	car_mat.roughness = 0.4
	car_node.material_override = car_mat
	car_node.position = center + fwd * Vector3(side * 0.0130, -0.0008, -EYE_R * 0.30)
	add_child(car_node)


## A lash / lid-margin line: a tube arc across the top (or bottom) of the almond
## eye opening, in the eye-local XY plane just proud of the sclera.
func _lash_line(side: float, upper: bool) -> MeshInstance3D:
	var hw: float = EYE_R * 1.28
	var hh: float = EYE_R * 0.66
	var samples: int = 11
	var path: Array[Vector3] = []
	for i in samples:
		var f: float = float(i) / float(samples - 1)
		var x: float = lerpf(-hw, hw, f)
		var arc: float = 1.0 - pow(x / hw, 2.0)
		var y: float
		if upper:
			y = hh * arc
			# Outer corner (away from nose) dips a touch for an almond, not round.
			y -= EYE_R * 0.12 * smoothstep(0.0, 1.0, (x * side + hw) / (2.0 * hw))
		else:
			y = -hh * 0.72 * arc
		path.append(Vector3(x, y, -EYE_R * 0.30 - EYE_R * 0.18 * arc))
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in samples:
		var f: float = float(i) / float(samples - 1)
		var taper: float = pow(1.0 - abs(f - 0.5) * 2.0, 0.4)  # thin at corners
		if upper:
			radii.append(lerpf(0.0007, 0.0016, taper))
		else:
			radii.append(lerpf(0.0004, 0.0008, taper))
	var rings: Array = ML.tube_rings(path, radii, 7, 0.7)
	for r_any in rings:
		var ring: ML.Ring = r_any
		ring.color = Color(0.13, 0.09, 0.07) if upper else Color(0.35, 0.24, 0.20)
	return ML.make_instance(ML.loft(rings, true, true, true), KM.brow(),
		"UpperLash" if upper else "LowerLash")


## The eye as simple layered meshes — the robust way stylized games build eyes,
## and immune to the UV-sphere pitfalls that made the analytic version render as
## a ring: a warm-white sclera sphere, a domed dark iris, a black pupil, and a
## bright catchlight dot. The cornea (iris/pupil/glint) faces -Z (forward).
func _build_eyeball(eye_root: Node3D) -> void:
	# Sclera: a flattened almond lens (wider than tall, shallow front-back) so
	# it seats flush in the socket. Iris fills the height; sclera shows as thin
	# crescents at the inner/outer corners — exactly a real eye.
	var sclera_mesh: SphereMesh = SphereMesh.new()
	sclera_mesh.radius = EYE_R
	sclera_mesh.height = EYE_R * 2.0
	sclera_mesh.radial_segments = 24
	sclera_mesh.rings = 14
	var sclera: MeshInstance3D = MeshInstance3D.new()
	sclera.name = "Sclera"
	sclera.mesh = sclera_mesh
	sclera.scale = Vector3(1.30, 0.66, 0.42)
	var sclera_mat: StandardMaterial3D = StandardMaterial3D.new()
	sclera_mat.albedo_color = Color(0.84, 0.81, 0.77)
	sclera_mat.roughness = 0.28
	sclera_mat.metallic_specular = 0.55
	sclera.material_override = sclera_mat
	eye_root.add_child(sclera)

	# Iris: a flat disc facing -Z (forward) wearing the iris shader — radial
	# gradient, fibres, and a gradient-hue shimmer + inner glow that swell with
	# `awaken` (his eyes light from within as the First Model surfaces).
	var iris: MeshInstance3D = _eye_disc(EYE_R * 0.60, EYE_R * 0.05,
		Color(0.20, 0.31, 0.19), -EYE_R * 0.40, "Iris")
	var iris_mat: ShaderMaterial = KM.iris()
	iris_mat.set_shader_parameter("iris_radius", EYE_R * 0.60)
	iris.material_override = iris_mat
	iris.scale = Vector3(1.0, 1.02, 1.0)
	eye_root.add_child(iris)

	# Pupil: a small near-black disc.
	var pupil: MeshInstance3D = _eye_disc(EYE_R * 0.24, EYE_R * 0.06,
		Color(0.02, 0.02, 0.03), -EYE_R * 0.46, "Pupil")
	eye_root.add_child(pupil)

	# Catchlight: a tiny bright unshaded dot up and to the nasal side of the
	# pupil — the single strongest "alive" cue.
	var glint_mesh: SphereMesh = SphereMesh.new()
	glint_mesh.radius = EYE_R * 0.13
	glint_mesh.height = EYE_R * 0.26
	glint_mesh.radial_segments = 10
	glint_mesh.rings = 6
	var glint: MeshInstance3D = MeshInstance3D.new()
	glint.name = "Catchlight"
	glint.mesh = glint_mesh
	glint.position = Vector3(-EYE_R * 0.20, EYE_R * 0.20, -EYE_R * 0.52)
	var glint_mat: StandardMaterial3D = StandardMaterial3D.new()
	glint_mat.albedo_color = Color(1.0, 1.0, 1.0)
	glint_mat.emission_enabled = true
	glint_mat.emission = Color(1.0, 1.0, 1.0)
	glint_mat.emission_energy_multiplier = 1.8
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint.material_override = glint_mat
	eye_root.add_child(glint)


## A thin cylinder disc facing -Z (forward) for the flat eye layers.
func _eye_disc(radius: float, thickness: float, color: Color, z: float,
		disc_name: String) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thickness
	mesh.radial_segments = 24
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = disc_name
	mi.mesh = mesh
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)  # axis Y -> Z, disc faces -Z
	mi.position = Vector3(0.0, 0.0, z)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.25
	mi.material_override = mat
	return mi


## Lid shell hugging the eyeball; open strip across the top (or bottom) arc.
func _lid_surface(upper: bool) -> Dictionary:
	var shell_r: float = EYE_R + 0.0016
	var rows: int = 6
	var rings: Array = []
	var theta_edge: float = 0.52 if upper else 0.58
	for i in rows:
		var f: float = float(i) / float(rows - 1)
		var theta: float = lerpf(theta_edge, 1.45, f)
		var r: float = shell_r + (0.0008 if i == 1 else 0.0)  # crease roll
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 12
		ring.points.resize(n)
		var pc: PackedColorArray = PackedColorArray()
		for j in n:
			var phi_f: float = float(j) / float(n - 1)
			var phi: float
			if upper:
				phi = lerpf(PI * 0.06, PI * 0.94, phi_f)
			else:
				phi = lerpf(PI * 1.08, PI * 1.92, phi_f)
			var ring_r: float = r * sin(theta)
			ring.points[j] = Vector3(
				cos(phi) * ring_r, sin(phi) * ring_r, -r * cos(theta))
			var c: Color
			if i == 0:
				c = Color(0.19, 0.12, 0.08) if upper else KM.SKIN_SHADOWED.darkened(0.2)
			else:
				c = KM.SKIN_BASE.darkened(0.05 if upper else 0.02)
				c = c.lerp(KM.SKIN_SHADOWED, 0.3 * f)
			c.a = 0.8
			pc.append(c)
		ring.point_colors = pc
		ring.v = f
		rings.append(ring)
	return ML.loft(rings, false)


## Lash strip along the upper lid margin, flicking out at the outer corner.
func _lash_surface(side: float) -> Dictionary:
	var shell_r: float = EYE_R + 0.0022
	var theta: float = 0.53
	var path: Array[Vector3] = []
	var samples: int = 9
	for i in samples:
		var f: float = float(i) / float(samples - 1)
		var phi: float = lerpf(PI * 0.10, PI * 0.90, f)
		var ring_r: float = shell_r * sin(theta)
		var p: Vector3 = Vector3(cos(phi) * ring_r, sin(phi) * ring_r,
			-shell_r * cos(theta))
		# Outer third lifts and flares away from the ball.
		var outer: float = _g((f - (0.0 if side > 0.0 else 1.0)) / 0.3)
		p += Vector3(side * 0.0012, 0.0008, -0.0006) * outer
		path.append(p)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in samples:
		radii.append(0.0013)
	var rings: Array = ML.tube_rings(path, radii, 6, 0.45)
	for r_any in rings:
		var ring: ML.Ring = r_any
		ring.color = Color(0.14, 0.09, 0.06)
	return ML.loft(rings, true, true, true)


# --- Hair -------------------------------------------------------------------

func _hairline_t(psi: float) -> float:
	var ap: float = absf(psi)
	# Forehead hairline high; drops past the temples and low around the back so
	# the cap of hair fully covers the skull between clumps.
	return 0.235 + 0.14 * smoothstep(0.35, 1.0, ap) + 0.34 * smoothstep(1.1, 2.9, ap)


func _hair_surface() -> Dictionary:
	var parts: Array[Dictionary] = []
	parts.append(_scalp_shell())
	# Clump layout: [t, psi, length, radius, flow] where flow steers the tip.
	# Clumps are wide and overlapping so the cut reads as a full head of hair,
	# not spikes — three staggered layers (under, mid, surface) per zone.
	var specs: Array = []
	# Fringe: parted and swept across the brow toward Kern's left (-X) so it
	# frames the face and clears the eyes instead of curtaining over them.
	for k in 16:
		var f: float = float(k) / 15.0
		var psi: float = lerpf(-0.72, 0.72, f)
		var jt: float = ML.hash1(float(k) * 7.1)
		# Strong sideways sweep, only a little drop — tips ride above the eyes.
		specs.append([0.205 + 0.03 * jt, psi,
			0.060 + 0.022 * ML.hash1(float(k) * 3.3), 0.019,
			Vector3(-1.05 - 0.15 * f, -0.42, -0.30)])
	# Upper-fringe underlayer, shorter, filling gaps at the part.
	for k in 12:
		var f: float = float(k) / 11.0
		specs.append([0.155 + 0.02 * ML.hash1(float(k) * 9.9), lerpf(-0.62, 0.62, f),
			0.045, 0.018, Vector3(-0.85 - 0.15 * f, -0.35, -0.28)])
	# Temple + over-ear sweeps, both sides, layered.
	for k in 5:
		for side in [-1.0, 1.0]:
			var psi: float = float(side) * (0.72 + 0.14 * float(k))
			specs.append([0.24 + 0.045 * float(k), psi, 0.078, 0.020,
				Vector3(float(side) * 0.40, -0.86, -0.02)])
	# Sides and back: falling flow, full coverage, shorter toward the nape.
	for k in 26:
		var f: float = float(k) / 25.0
		var psi: float = lerpf(-PI, PI, f)
		if absf(psi) < 0.88:
			continue
		specs.append([0.26 + 0.10 * ML.hash1(float(k) * 11.7), psi,
			0.070 + 0.022 * ML.hash1(float(k) * 5.9), 0.020,
			Vector3(signf(psi) * 0.22, -0.92, 0.16)])
	# Crown whorl radiating from a rear-top point — the mass on top.
	for k in 14:
		var wa: float = TAU * float(k) / 14.0
		specs.append([0.085 + 0.05 * ML.hash1(float(k) * 4.4), 0.35,
			0.078, 0.020, Vector3(cos(wa) * 0.7, -0.40, sin(wa) * 0.7)])
	# Crown cap: short clumps laid flat over the very top so no dark scalp
	# shows through the whorl centre.
	for k in 8:
		var wa: float = TAU * float(k) / 8.0
		specs.append([0.045, wrapf(0.35 + wa * 0.4, -PI, PI),
			0.055, 0.019, Vector3(cos(wa) * 0.45, -0.30, sin(wa) * 0.45 + 0.2)])
	# Nape shorts, layered.
	for k in 9:
		var psi: float = lerpf(-0.7, 0.7, float(k) / 8.0) + PI
		specs.append([0.48, wrapf(psi, -PI, PI), 0.052, 0.018,
			Vector3(0.0, -0.95, 0.28)])
	var idx: int = 0
	for spec in specs:
		parts.append(_hair_clump(spec[0], spec[1], spec[2], spec[3], spec[4], idx))
		idx += 1
	# A few finer flyaways at the crown — the unruly detail on top of the mass.
	parts.append(_hair_clump(0.06, 0.2, 0.055, 0.004, Vector3(0.3, 0.45, -0.3), 197))
	parts.append(_hair_clump(0.08, -0.4, 0.050, 0.004, Vector3(-0.3, 0.5, 0.2), 198))
	parts.append(_hair_clump(0.05, 1.6, 0.048, 0.004, Vector3(0.5, 0.4, 0.4), 199))
	return ML.merge(parts)


func _scalp_shell() -> Dictionary:
	var rows: int = 10
	var n: int = 40
	var rings: Array = []
	for i in rows:
		var f: float = float(i) / float(rows - 1)
		var ring: ML.Ring = ML.Ring.new()
		ring.points.resize(n)
		var pc: PackedColorArray = PackedColorArray()
		for j in n:
			var a: float = TAU * float(j) / float(n)
			var psi: float = wrapf(a + PI * 0.5, -PI, PI)
			var t: float = lerpf(0.015, _hairline_t(psi), f)
			var p: Vector3 = _skull_point(t, psi)
			var up_mix: float = clampf(1.0 - t * 2.2, 0.0, 1.0)
			var out: Vector3 = _skull_normal_out(t, psi)
			out = (out * (1.0 - up_mix) + Vector3.UP * up_mix).normalized()
			# Puff the cap outward for hair volume (thicker over the crown).
			var puff: float = 0.010 + 0.006 * up_mix
			ring.points[j] = p + out * puff
			var mul: float = 0.80 + 0.28 * ML.hash1(float(j) * 1.7 + float(i) * 3.1)
			pc.append(Color(mul, mul, mul))
		ring.point_colors = pc
		ring.v = f * 0.30
		rings.append(ring)
	return ML.loft(rings, true, false, false)


func _hair_clump(t_root: float, psi_root: float, length: float, radius: float,
		flow: Vector3, seed_i: int) -> Dictionary:
	var root: Vector3 = _skull_point(t_root, psi_root)
	var out: Vector3 = _skull_normal_out(t_root, psi_root)
	var up_mix: float = clampf(1.0 - t_root * 2.2, 0.0, 1.0)
	out = (out * (1.0 - up_mix) + Vector3.UP * up_mix).normalized()
	root += out * 0.003
	var dir: Vector3 = flow.normalized()
	var droop: Vector3 = Vector3(0.0, -0.014, 0.0) * (length / 0.08)
	var jx: float = (ML.hash1(float(seed_i) * 13.7) - 0.5) * 0.012
	var jz: float = (ML.hash1(float(seed_i) * 29.3) - 0.5) * 0.012
	var p0: Vector3 = root
	var p1: Vector3 = root + dir * (length * 0.35) + out * 0.012
	var p2: Vector3 = root + dir * (length * 0.75) + out * 0.004 + droop * 0.5
	var p3: Vector3 = root + dir * length + droop + Vector3(jx, 0.0, jz)
	var path: Array[Vector3] = ML.bezier_path(p0, p1, p2, p3, 7)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in path.size():
		var f: float = float(i) / float(path.size() - 1)
		radii.append(radius * (1.0 - pow(f, 1.6) * 0.92))
	var rings: Array = ML.tube_rings(path, radii, 7, 0.55)
	var mul: float = 0.88 + 0.24 * ML.hash1(float(seed_i) * 5.3)
	for i in rings.size():
		var ring: ML.Ring = rings[i]
		ring.v = float(i) / float(rings.size() - 1)
		ring.color = Color(mul, mul, mul)
	return ML.loft(rings, true, true, true)

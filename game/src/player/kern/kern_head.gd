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
const EYE_R: float = 0.0125         # eyeball radius (life-size 24 mm ball)

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


## blink: 0 = open, 1 = closed. Upper lid does most of the travel.
func set_blink(blink: float) -> void:
	var upper: float = -0.62 * blink
	var lower: float = 0.20 * blink
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
const PROFILE: Array = [
	[0.00, 1.7720, 0.0040, 0.0040, 0.0040, 0.004],
	[0.07, 1.7625, 0.0430, 0.0470, 0.0520, 0.004],
	[0.15, 1.7455, 0.0625, 0.0680, 0.0770, 0.002],
	[0.24, 1.7185, 0.0730, 0.0820, 0.0930, 0.000],
	[0.34, 1.6890, 0.0770, 0.0890, 0.1010, 0.000],
	[0.44, 1.6595, 0.0780, 0.0855, 0.1015, 0.000],
	[0.54, 1.6315, 0.0750, 0.0870, 0.0950, 0.000],
	[0.64, 1.6065, 0.0685, 0.0860, 0.0830, -0.001],
	[0.74, 1.5850, 0.0605, 0.0840, 0.0700, -0.002],
	[0.84, 1.5655, 0.0505, 0.0780, 0.0580, -0.003],
	[0.92, 1.5515, 0.0375, 0.0650, 0.0465, -0.002],
	[0.97, 1.5445, 0.0220, 0.0430, 0.0330, 0.002],
	[1.00, 1.5410, 0.0030, 0.0050, 0.0050, 0.008],
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
	# Brow ridge, heaviest right above each eye.
	d += 0.0055 * _g((t - 0.355) / 0.035) * _g(ap / 0.62) \
		* (0.55 + 0.65 * _g((ap - 0.32) / 0.18))
	# Eye sockets.
	d -= 0.0090 * _g((t - EYE_T) / 0.048) * _g((ap - EYE_PSI) / 0.145)
	# Nasal bridge riser between the eyes.
	d += 0.0040 * _g(psi / 0.075) * _g((t - 0.44) / 0.05)
	# Cheekbones.
	d += 0.0050 * _g((t - 0.53) / 0.05) * _g((ap - 0.52) / 0.16)
	# Soft cheek hollow beneath them.
	d -= 0.0025 * _g((t - 0.62) / 0.06) * _g((ap - 0.42) / 0.18)
	# Muzzle roundness (the dental arch pushing the mouth area forward).
	d += 0.0045 * _g((t - 0.75) / 0.07) * _g(psi / 0.25)
	# Philtrum groove above the upper lip.
	d -= 0.0014 * _g(psi / 0.04) * _g((t - 0.725) / 0.028)
	# Chin ball with a whisper of a central crease.
	d += 0.0062 * _g((t - 0.885) / 0.048) * _g(psi / 0.15)
	d -= 0.0010 * _g(psi / 0.03) * _g((t - 0.895) / 0.04)
	# Gonial jaw corners and the jawline edge that separates face from neck.
	d += 0.0045 * _g((t - 0.72) / 0.07) * _g((ap - 0.95) / 0.18)
	d += 0.0020 * _g((t - 0.80) / 0.045) * _g((ap - 0.75) / 0.35)
	# Temple flats.
	d -= 0.0028 * _g((t - 0.30) / 0.06) * _g((ap - 0.75) / 0.16)
	# Occipital swell at the back of the skull.
	d += 0.0040 * _g((t - 0.33) / 0.10) * _g((ap - PI) / 0.5)
	# Slight dish where the ears mount (hides the ear seam).
	d -= 0.0022 * _g((t - 0.50) / 0.06) * _g((ap - 1.42) / 0.12)
	return p + outward * d


func _skull_normal_out(t: float, psi: float) -> Vector3:
	var p: Vector3 = _skull_point(t, psi)
	var flat: Vector3 = Vector3(p.x, 0.0, p.z - CENTER_Z)
	if flat.length_squared() < 0.000001:
		return Vector3(0.0, 1.0, 0.0)
	return flat.normalized()


func _skull_surface() -> Dictionary:
	var rows: int = 46
	var n: int = 60
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
	# Socket shadow tint.
	c = c.lerp(KM.SKIN_SHADOWED, 0.55 * _g((t - EYE_T) / 0.05) * _g((ap - EYE_PSI) / 0.15))
	# Cheek flush.
	c = c.lerp(KM.SKIN_FLUSH, 0.42 * _g((t - 0.57) / 0.07) * _g((ap - 0.48) / 0.22))
	# Warmth around the mouth / chin shadow under the lip.
	c = c.lerp(KM.LIP_COLOR, 0.16 * _g((t - 0.77) / 0.05) * _g(psi / 0.22))
	c = c.darkened(0.07 * _g((t - 0.845) / 0.02) * _g(psi / 0.18))
	# Under-jaw ambient shadow.
	c = c.darkened(0.10 * clampf((t - 0.90) / 0.08, 0.0, 1.0))
	c.a = 0.85
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
	var mount: Vector3 = _skull_point(0.50, 1.42)
	var parts: Array[Dictionary] = []
	# Ear-local frame: +X out from the head, slight backward yaw + outward tilt.
	var basis: Basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.UP, -0.20)
	basis = basis.rotated(Vector3.FORWARD, 0.16)
	var xf: Transform3D = Transform3D(basis, mount)

	# Outline of the auricle in the ear's own YZ plane (y up, z toward the
	# face): a slightly pointed oval, fuller at the lobe.
	var outline: Array[Vector3] = []
	var samples: int = 16
	for i in samples:
		var a: float = TAU * float(i) / float(samples)
		var ry: float = 0.031
		var rz: float = 0.017
		var y: float = sin(a) * ry
		var z: float = cos(a) * rz
		if sin(a) < -0.3:
			y *= 0.86  # lobe sits lower and rounder
			z *= 0.80
		if sin(a) > 0.55:
			z *= 0.88  # upper helix leans back a touch
		outline.append(Vector3(0.0, y + 0.002, z - 0.002))
	outline.append(outline[0])

	# Helix rim: tube around the outline.
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in outline.size():
		var a: float = TAU * float(i % samples) / float(samples)
		radii.append(0.0048 if sin(a) < -0.3 else 0.0038)
	var rim_rings: Array = ML.tube_rings(outline, radii, 8)
	for r_any in rim_rings:
		var ring: ML.Ring = r_any
		var c: Color = KM.SKIN_BASE.lerp(KM.SKIN_FLUSH, 0.45)
		c.a = 0.30  # the thinnest skin on the body: ears glow backlit
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
		c.a = 0.35
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
		c.a = 0.35
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
		c.a = 0.4
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
		var psi: float = side * (0.115 + 0.44 * s)
		var t: float = 0.352 - 0.012 * _g((s - 0.55) / 0.35) + 0.014 * pow(s, 3.0)
		path.append(_skull_point(t, psi) + _skull_normal_out(t, psi) * 0.0038)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in samples:
		var s: float = float(i) / float(samples - 1)
		radii.append(lerpf(0.0042, 0.0014, pow(s, 1.4)))
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
	var center: Vector3 = socket - out_dir * 0.0055 - _pivot
	var fwd: Basis = Basis.IDENTITY.rotated(Vector3.UP, side * -0.07)

	var eye_root: Node3D = Node3D.new()
	eye_root.name = "EyeR" if right else "EyeL"
	eye_root.position = center
	eye_root.basis = fwd
	add_child(eye_root)
	var ball: MeshInstance3D = ML.make_instance(_eyeball_surface(), KM.eye(), "Ball")
	eye_root.add_child(ball)
	if right:
		_eye_r = eye_root
	else:
		_eye_l = eye_root

	var upper: Node3D = Node3D.new()
	upper.name = "UpperLid"
	upper.position = center
	upper.basis = fwd
	add_child(upper)
	upper.add_child(ML.make_instance(
		_lid_surface(true), KM.skin(), "UpperLidMesh"))
	upper.add_child(ML.make_instance(_lash_surface(side), KM.brow(), "Lashes"))
	var lower: Node3D = Node3D.new()
	lower.name = "LowerLid"
	lower.position = center
	lower.basis = fwd
	add_child(lower)
	lower.add_child(ML.make_instance(
		_lid_surface(false), KM.skin(), "LowerLidMesh"))
	if right:
		_upper_lid_r = upper
		_lower_lid_r = lower
	else:
		_upper_lid_l = upper
		_lower_lid_l = lower

	# Caruncle: the small pink inner-corner wedge.
	var caruncle: SphereMesh = SphereMesh.new()
	caruncle.radius = 0.0021
	caruncle.height = 0.0042
	caruncle.radial_segments = 8
	caruncle.rings = 4
	var car_node: MeshInstance3D = MeshInstance3D.new()
	car_node.name = "CaruncleR" if right else "CaruncleL"
	car_node.mesh = caruncle
	var car_mat: StandardMaterial3D = StandardMaterial3D.new()
	car_mat.albedo_color = Color(0.78, 0.42, 0.38)
	car_mat.roughness = 0.4
	car_node.material_override = car_mat
	car_node.position = center + Vector3(-side * 0.0118, -0.0012, -0.0035)
	add_child(car_node)


## Eyeball around -Z with polar UVs the eye shader expects (v = 0 at the
## pupil pole). Includes the corneal bulge that catches the wet glint.
func _eyeball_surface() -> Dictionary:
	var rings: Array = []
	var rows: int = 20
	for i in rows:
		var theta: float = lerpf(0.0, PI * 0.8, float(i) / float(rows - 1))
		var bulge: float = 1.0 + 0.055 * _g(theta / 0.32)
		var r: float = EYE_R * bulge
		var ring_r: float = r * sin(theta)
		var ring: ML.Ring = ML.Ring.new()
		var n: int = 20
		ring.points.resize(n)
		for j in n:
			var a: float = TAU * float(j) / float(n)
			ring.points[j] = Vector3(
				cos(a) * ring_r, sin(a) * ring_r, -r * cos(theta))
		ring.v = theta / PI
		ring.color = Color(1.0, 1.0, 1.0)
		rings.append(ring)
	return ML.loft(rings, true, false, true)


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
	return 0.24 + 0.08 * smoothstep(0.35, 1.0, ap) + 0.26 * smoothstep(1.2, 2.9, ap)


func _hair_surface() -> Dictionary:
	var parts: Array[Dictionary] = []
	parts.append(_scalp_shell())
	# Clump layout: [t, psi, length, radius, flow] where flow steers the tip.
	var specs: Array = []
	# Fringe: sweeps across the forehead toward Kern's left (-X).
	for k in 10:
		var f: float = float(k) / 9.0
		var psi: float = lerpf(-0.62, 0.62, f)
		specs.append([0.205 + 0.02 * ML.hash1(float(k) * 7.1), psi,
			0.095 + 0.020 * ML.hash1(float(k) * 3.3), 0.0105,
			Vector3(-0.55 - 0.2 * f, -0.72, -0.30)])
	# Temple sweeps over the ear tops.
	for k in 3:
		for side in [-1.0, 1.0]:
			var psi: float = float(side) * (0.78 + 0.17 * float(k))
			specs.append([0.28 + 0.035 * float(k), psi, 0.072, 0.0095,
				Vector3(float(side) * 0.42, -0.85, -0.05)])
	# Sides and back: falling flow, shorter toward the nape.
	for k in 16:
		var f: float = float(k) / 15.0
		var psi: float = lerpf(-PI, PI, f)
		if absf(psi) < 0.95:
			continue
		specs.append([0.30 + 0.05 * ML.hash1(float(k) * 11.7), psi,
			0.065 + 0.015 * ML.hash1(float(k) * 5.9), 0.0100,
			Vector3(signf(psi) * 0.25, -0.90, 0.18)])
	# Crown whorl radiating from a rear-top point, slightly off-centre.
	for k in 8:
		var wa: float = TAU * float(k) / 8.0
		specs.append([0.10, 0.35 + 0.0 * wa, 0.075, 0.0100,
			Vector3(cos(wa) * 0.7, -0.35, sin(wa) * 0.7)])
	# Nape shorts.
	for k in 6:
		var psi: float = lerpf(-0.6, 0.6, float(k) / 5.0) + PI
		specs.append([0.50, wrapf(psi, -PI, PI), 0.048, 0.0085,
			Vector3(0.0, -0.95, 0.30)])
	var idx: int = 0
	for spec in specs:
		parts.append(_hair_clump(spec[0], spec[1], spec[2], spec[3], spec[4], idx))
		idx += 1
	# Two thin flyaways at the crown — the unruly detail.
	parts.append(_hair_clump(0.06, 0.2, 0.055, 0.0018, Vector3(0.3, 0.45, -0.3), 97))
	parts.append(_hair_clump(0.08, -0.4, 0.048, 0.0016, Vector3(-0.3, 0.5, 0.2), 98))
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
			ring.points[j] = p + out * 0.0045
			var mul: float = 0.85 + 0.3 * ML.hash1(float(j) * 1.7 + float(i) * 3.1)
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

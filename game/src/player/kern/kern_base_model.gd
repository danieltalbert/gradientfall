class_name KernBaseModel
extends RefCounted
## Loads the imported CC0 base body mesh for Kern (see
## `assets/models/README.md` for provenance and the generation spec) and dresses
## it in the project's character shaders.
##
## This is the one non-procedural asset in the game: it supplies **only** the
## bare body + head geometry. Clothing, cloak, hair, gear, the arcane hand-mark
## and every shader and animation stay code-generated on top of it.
##
## If the file isn't present the loader reports `ok == false` and
## `kern_visual.gd` silently falls back to the fully procedural body, so the
## main line always runs (iron rule 1).

## Accepted base-mesh files, best format first. glTF is cleanest, but Godot 4
## imports FBX (ufbx) and Collada natively too — so a MakeHuman **standalone**
## export works without a Blender round-trip. First one found wins.
const MODEL_PATHS: Array[String] = [
	"res://assets/models/kern_base.glb",
	"res://assets/models/kern_base.gltf",
	"res://assets/models/kern_base.fbx",
	"res://assets/models/kern_base.dae",
]

const ML: GDScript = preload("res://src/player/kern/kern_mesh_lib.gd")
const KM: GDScript = preload("res://src/player/kern/kern_materials.gd")
# NB: not "BoneMap" — that shadows Godot's native BoneMap class.
const KBoneMap: GDScript = preload("res://src/player/kern/kern_bone_map.gd")

## Substrings that identify which imported surface is which. MPFB names its
## objects after the assets used, so match loosely and case-insensitively.
const EYE_HINTS: Array[String] = ["eye", "cornea", "iris"]
const TEETH_HINTS: Array[String] = ["teeth", "tooth", "tongue"]
const BROW_HINTS: Array[String] = ["brow", "eyelash", "lash"]


## GATE LIFTED (2026-07-29): the imported body is now the DEFAULT.
##
## It was gated off on 2026-07-24 because garments skinned to the procedural
## skeleton lost their depth test against the imported body they enclose. That
## symptom is gone, and `strip_covered_geometry()` is why — as the note in
## `kern_visual._reskin_garments_to_base()` predicted, geometry that no longer
## exists cannot contest a depth test. Re-verified across the character studio
## (front, three-quarter, side, back, cloak-back, portrait) and a walk through
## the locomotion lab: every garment renders, and foot slip on the imported
## body measures 19 mm/m against the procedural path's 23.
##
## Two things that looked like this bug and were NOT:
##   * the hero rendering bald with a hole in his face — that was
##     `COVERED_ZONES` overshooting into the head, fixed in the same session;
##   * the cloak looking semi-transparent at three-quarter view — that is the
##     sleeve loft interpenetrating the cloak sheet, and it renders identically
##     on the procedural body. A fitting problem, not a rendering one.
##
## `--no-kern-base` forces the fully procedural body back on. Kept as an escape
## hatch: this flips the look of the hero, so a session that hits trouble can
## fall back in one flag rather than reverting a commit.
static func enabled() -> bool:
	return not OS.get_cmdline_user_args().has("--no-kern-base")


## Returns:
## { ok: bool, root: Node3D, skeleton: Skeleton3D, bones: Dictionary,
##   reason: String }
static func load_into(parent: Node3D) -> Dictionary:
	var fail: Dictionary = {"ok": false, "root": null, "skeleton": null,
		"bones": {}, "reason": ""}
	if not enabled():
		fail["reason"] = "imported base body turned off by --no-kern-base; using the procedural body"
		return fail
	var model_path: String = ""
	for candidate in MODEL_PATHS:
		if ResourceLoader.exists(candidate):
			model_path = candidate
			break
	if model_path == "":
		fail["reason"] = "no base mesh at assets/models/kern_base.{glb,gltf,fbx,dae} (using procedural body)"
		return fail
	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		fail["reason"] = "%s failed to load as a PackedScene" % model_path
		return fail
	var root: Node3D = packed.instantiate() as Node3D
	if root == null:
		fail["reason"] = "%s did not instantiate a Node3D" % model_path
		return fail
	root.name = "KernBaseBody"
	# glTF characters face +Z; every code-built Kern asset faces -Z (Godot
	# forward). Turn the import around once here so both bodies agree.
	root.rotation.y = PI
	parent.add_child(root)
	_centre_horizontally(root)

	var skeleton: Skeleton3D = _find_skeleton(root)
	if skeleton == null:
		root.queue_free()
		fail["reason"] = "%s has no Skeleton3D (export with skinning on)" % model_path
		return fail

	var bones: Dictionary = KBoneMap.resolve(skeleton)
	print(KBoneMap.report(skeleton, bones))
	if not KBoneMap.is_usable(bones):
		root.queue_free()
		fail["reason"] = "base mesh rig is missing core humanoid bones"
		return fail

	_apply_materials(root, skeleton, bones)
	return {"ok": true, "root": root, "skeleton": skeleton, "bones": bones,
		"reason": ""}


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


## Swap the imported PBR materials for the project's character shaders so the
## body sits in the same light as everything else and answers to `awaken`.
static func _apply_materials(root: Node, skeleton: Skeleton3D,
		bones: Dictionary) -> void:
	for mi in _all_mesh_instances(root):
		var lower: String = mi.name.to_lower()
		if _matches(lower, EYE_HINTS) or _matches(lower, TEETH_HINTS):
			# Keep the imported materials: MakeHuman ships proper iris/teeth
			# textures with correct UVs, which beat any procedural override on
			# an imported eyeball. (Iris colour toward Kern's green is a later
			# shader pass.) Just make sure they read matte, not plastic.
			var mat: Material = mi.get_active_material(0)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).roughness = maxf(
					(mat as StandardMaterial3D).roughness, 0.35)
		elif _matches(lower, BROW_HINTS):
			mi.material_override = KM.brow()
		else:
			# The bare body: paint Kern's skin zones into vertex COLOR first
			# (the skin shader reads albedo from COLOR, which an imported mesh
			# ships all-white — the source of the "porcelain statue" look).
			_paint_skin(mi, root, skeleton, bones)
			mi.material_override = KM.skin()


# --- Skin zone painting ------------------------------------------------------
# The procedural body carries its painted zones (flush cheeks/nose/ears, lip
# colour, socket shading, per-part thickness for backlight) in vertex COLOR.
# The imported mesh ships COLOR-less, so the same zones are computed here once
# at load, anchored to the imported EYE MESH centres — real facial landmarks —
# instead of guessed heights, so any reasonable export self-calibrates.
# Painting rest-space colours into COLOR keeps the zones glued to the skin
# during animation (an object-space shader mask would swim as bones move).

static func _paint_skin(mi: MeshInstance3D, root: Node3D,
		skeleton: Skeleton3D, bones: Dictionary) -> void:
	var mesh: ArrayMesh = mi.mesh as ArrayMesh
	if mesh == null:
		return

	# -- Landmarks, all in this mesh's local space ----------------------------
	var eyes_mi: MeshInstance3D = null
	for other in _all_mesh_instances(root):
		if _matches(other.name.to_lower(), EYE_HINTS):
			eyes_mi = other
			break

	var have_face: bool = false
	var eye_l: Vector3 = Vector3.ZERO
	var eye_r: Vector3 = Vector3.ZERO
	var eye_mid: Vector3 = Vector3.ZERO
	var fwd: Vector3 = Vector3.FORWARD
	var side: Vector3 = Vector3.RIGHT
	var skull_c: Vector3 = Vector3.ZERO

	if eyes_mi != null and eyes_mi.mesh != null:
		var rel: Transform3D = _relative_transform(eyes_mi, mi)
		var aabb: AABB = eyes_mi.mesh.get_aabb()
		var centre: Vector3 = rel * aabb.get_center()
		# The eyes mesh holds both eyeballs: each ball is ~aabb height across,
		# so the ball centres sit half-a-ball in from the lateral extremes.
		var half_span: float = absf((rel.basis * aabb.size).x) * 0.5
		var ball_r: float = absf((rel.basis * aabb.size).y) * 0.5
		var lateral: Vector3 = (rel.basis * Vector3(aabb.size.x, 0.0, 0.0)).normalized()
		eye_l = centre - lateral * (half_span - ball_r)
		eye_r = centre + lateral * (half_span - ball_r)
		eye_mid = centre
		# Skull centre: average of body vertices in a band around the eye line.
		skull_c = _band_centroid(mesh, eye_mid.y - 0.05, eye_mid.y + 0.09)
		var f: Vector3 = eye_mid - skull_c
		f.y = 0.0
		if f.length() > 0.005:
			fwd = f.normalized()
			side = Vector3.UP.cross(fwd).normalized()
			have_face = true

	# Hand joints (knuckle flush + thin webbing for backlight).
	var hand_pts: Array[Vector3] = []
	var skel_rel: Transform3D = _relative_transform(skeleton, mi)
	for hand_name in ["HandL", "HandR"]:
		if bones.has(hand_name):
			hand_pts.append(skel_rel *
				skeleton.get_bone_global_rest(bones[hand_name]).origin)

	# -- Paint every surface --------------------------------------------------
	var painted: ArrayMesh = ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = PackedColorArray()
		colors.resize(verts.size())
		for i in verts.size():
			colors[i] = _skin_color_at(verts[i], have_face, eye_l, eye_r,
				eye_mid, fwd, side, skull_c, hand_pts)
		arrays[Mesh.ARRAY_COLOR] = colors
		painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		painted.surface_set_material(s, mesh.surface_get_material(s))
	mi.mesh = painted


static func _band_centroid(mesh: ArrayMesh, y_min: float, y_max: float) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = \
			mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y >= y_min and v.y <= y_max:
				sum += v
				n += 1
	return sum / float(maxi(n, 1))


## Smooth radial falloff: 1 at the centre, 0 beyond `radius`.
static func _zone(v: Vector3, centre: Vector3, radius: float) -> float:
	var d: float = v.distance_to(centre)
	return clampf(1.0 - d / radius, 0.0, 1.0)


# Painted base for the imported body: KM.SKIN_BASE desaturated and lifted a
# touch. On the procedural body the same constant was broken up by baked crease
# AO and per-ring value drift; on the smooth dense import it read flat pumpkin.
const IMPORT_SKIN_BASE: Color = Color(0.800, 0.610, 0.490)


static func _skin_color_at(v: Vector3, have_face: bool, eye_l: Vector3,
		eye_r: Vector3, eye_mid: Vector3, fwd: Vector3, side: Vector3,
		skull_c: Vector3, hand_pts: Array[Vector3]) -> Color:
	var c: Color = IMPORT_SKIN_BASE
	# Low-frequency value drift so large smooth areas don't read airbrushed.
	var drift: float = 1.0 + 0.05 * sin(v.x * 23.7 + v.y * 11.3 + v.z * 17.9) \
		* sin(v.y * 7.1 - v.z * 13.7)
	c = Color(c.r * drift, c.g * drift, c.b * drift, 1.0)
	var thickness: float = 1.0

	if have_face:
		# Eye sockets: a soft cool shadow ring seats the imported eyeballs.
		var socket: float = maxf(_zone(v, eye_l, 0.024), _zone(v, eye_r, 0.024))
		c = c.lerp(KM.SKIN_SHADOWED, socket * 0.30)
		# Nose ridge + tip warm up (blood close under the skin).
		var nose_pt: Vector3 = eye_mid - Vector3.UP * 0.036 + fwd * 0.045
		c = c.lerp(KM.SKIN_FLUSH, _zone(v, nose_pt, 0.028) * 0.55)
		# Cheeks: broad soft flush low and lateral of each eye.
		var cheek_l: Vector3 = eye_l - Vector3.UP * 0.048 + fwd * 0.012 \
			- side * 0.018
		var cheek_r: Vector3 = eye_r - Vector3.UP * 0.048 + fwd * 0.012 \
			+ side * 0.018
		var cheek: float = maxf(_zone(v, cheek_l, 0.050), _zone(v, cheek_r, 0.050))
		c = c.lerp(KM.SKIN_FLUSH, cheek * 0.20)
		# Lips.
		var lip_pt: Vector3 = eye_mid - Vector3.UP * 0.072 + fwd * 0.036
		c = c.lerp(KM.LIP_COLOR, _zone(v, lip_pt, 0.019) * 0.7)
		# Ears: lateral extremes at eye height — flushed and THIN, so the sun
		# glows through them (the skin shader reads thickness from COLOR.a).
		var lat: float = absf((v - skull_c).dot(side))
		var ear_band: float = clampf((lat - 0.058) / 0.02, 0.0, 1.0) \
			* _zone(Vector3(0.0, v.y, 0.0),
				Vector3(0.0, eye_mid.y + 0.005, 0.0), 0.045)
		c = c.lerp(KM.SKIN_FLUSH, ear_band * 0.4)
		thickness = lerpf(thickness, 0.35, ear_band)

	for hand_pt in hand_pts:
		var knuckle: float = _zone(v, hand_pt, 0.10)
		c = c.lerp(KM.SKIN_FLUSH, knuckle * 0.25)
		thickness = lerpf(thickness, 0.8, knuckle * 0.7)

	c.a = thickness
	return c


static func _matches(lower_name: String, hints: Array[String]) -> bool:
	for h in hints:
		if lower_name.contains(h):
			return true
	return false


## The glb's own origin is not guaranteed to sit under the body's centre of
## mass (MPFB pivots at the armature, and the PI flip mirrors any offset).
## Centre the TORSO over this node's origin in X/Z so the garments — which
## are lofted around the origin — wrap the imported figure. A full-AABB
## centre is wrong here: the toes reach ~17 cm forward and would drag the
## whole body backwards out of the tunic.
static func _centre_horizontally(root: Node3D) -> void:
	var lo: Vector3 = Vector3(INF, INF, INF)
	var hi: Vector3 = -Vector3(INF, INF, INF)
	for mi in _all_mesh_instances(root):
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var rel: Transform3D = _relative_transform(mi, root)
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = \
				mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = rel * v
				# Torso band only: between hips and shoulders, near midline.
				if p.y < 0.80 or p.y > 1.45 or absf(p.x) > 0.20:
					continue
				lo = lo.min(p)
				hi = hi.max(p)
	if lo.x == INF:
		return
	var centre: Vector3 = (lo + hi) * 0.5
	# NO runtime shift: the engine renders skinned geometry at the glb's own
	# coordinates and IGNORES this root's translation, so a shift here moves
	# bone attachments away from the rendered body instead of centring it.
	# The centring is baked into the glb by tools/export_kern_base.py; this
	# just verifies it and complains if the file predates that step.
	if absf(centre.x) > 0.01 or absf(centre.z) > 0.01:
		push_warning(("KernBaseModel: torso is off-centre by (%.3f, %.3f) — " +
			"re-export with tools/export_kern_base.py (it centres the torso).")
			% [centre.x, centre.z])


## Transform taking `from_node`-local points into `to_node`-local space.
## Walks plain node transforms so it works before/without being in the tree.
static func _relative_transform(from_node: Node3D, to_node: Node3D) -> Transform3D:
	return _to_ancestor(to_node).affine_inverse() * _to_ancestor(from_node)


static func _to_ancestor(node: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var walker: Node = node
	while walker is Node3D:
		t = (walker as Node3D).transform * t
		walker = walker.get_parent()
	return t


static func _all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_all_mesh_instances(child))
	return out


## Zones of the bare body that the code-built clothing covers, in the mesh's
## own bind-pose (T-pose) space: {y_min, y_max, r_min, r_max} where r is the
## horizontal distance from the body's vertical centreline. A triangle whose
## every vertex falls in a zone is dropped.
##
## This is the standard "don't render the body under the clothes" step. It also
## removes the entire class of z-fighting/occlusion bugs between the imported
## body and the garments worn over it: geometry that doesn't exist can't win a
## depth test against the tunic enclosing it.
const COVERED_ZONES: Array[Dictionary] = [
	# Torso, hips, legs and feet under tunic + trousers + boots. Runs to the
	# ground: the boots enclose the feet, so bare toes would otherwise poke
	# through the soles. r_max stops before the hands, which hang beside the
	# hips and must stay.
	# y_max stops BELOW the tunic collar's top edge (~1.50): the jaw and chin
	# sit just above it, and cutting into them opens the face and exposes the
	# teeth. Everything above this is visible neck and head.
	{"y_min": 0.0, "y_max": 1.44, "r_min": 0.0, "r_max": 0.22},
	# Deltoid and upper arm only, where the tunic's yoke sits over it.
	#
	# r_max is 0.28, NOT 0.70. On a 1.75 m figure the shoulder sits at r ~0.18,
	# the elbow at ~0.45 and the wrist at ~0.70, so a 0.70 limit deleted the
	# ENTIRE arm from shoulder to wrist. The imported hands then hung in space
	# with a visible gap between the sleeve cuff and the wrist — the single
	# most unsettling thing about the figure, and the reason he read as "not
	# connected". The sleeve is what covers the arm; the body under it only
	# needs removing where the tunic's thicker yoke would otherwise fight it.
	#
	# y_max is 1.50, NOT 1.60. `r` is the distance from the body's vertical
	# CENTRELINE, so it counts forward protrusion as well as sideways: on a
	# 1.75 m figure the nose and lips stick out to r ~0.13, which sits inside
	# this zone's r_min. At 1.60 the band therefore reached mouth height
	# (~1.56) and cut the jaw and lips clean off, leaving the teeth mesh
	# showing through the hole.
	{"y_min": 1.28, "y_max": 1.50, "r_min": 0.12, "r_max": 0.28},
	# Shoulder caps and upper chest under the tunic's yoke. Without this the
	# bare shoulders poke through the garment in-game. In the T-pose the hands
	# hang far out along X (r ~0.7), so this tight radius cannot reach them.
	#
	# y_max is 1.47, NOT 1.62. On a 1.75 m figure the shoulder caps top out
	# near 1.44; 1.62 is eye level, and a 0.33 m radius there swallows the
	# entire head from chin to eyes. That is what made the imported hero render
	# as a bald dome with a hole where his face should be — and it is why the
	# base mesh looked broken enough to be gated off, quite separately from the
	# depth bug it was gated off FOR.
	{"y_min": 1.34, "y_max": 1.47, "r_min": 0.0, "r_max": 0.33},
]


## Strip the covered geometry from the imported body. Returns triangles removed.
static func strip_covered_geometry(root: Node3D) -> int:
	var removed: int = 0
	for mi in _all_mesh_instances(root):
		if not String(mi.name).begins_with("KernBody"):
			continue  # never touch eyes/teeth
		var src: Mesh = mi.mesh
		if src == null:
			continue
		var out: ArrayMesh = ArrayMesh.new()
		for s in src.get_surface_count():
			var arrays: Array = src.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if verts.is_empty() or idx.is_empty():
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				continue
			var keep: PackedInt32Array = PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var a: Vector3 = verts[idx[t]]
				var b: Vector3 = verts[idx[t + 1]]
				var c: Vector3 = verts[idx[t + 2]]
				if _covered(a) and _covered(b) and _covered(c):
					removed += 1
					continue
				keep.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
			arrays[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat: Material = src.surface_get_material(s)
			if mat != null:
				out.surface_set_material(out.get_surface_count() - 1, mat)
		mi.mesh = out
	return removed


static func _covered(v: Vector3) -> bool:
	var r: float = Vector2(v.x, v.z).length()
	for zone in COVERED_ZONES:
		if v.y >= float(zone["y_min"]) and v.y <= float(zone["y_max"]) \
				and r >= float(zone["r_min"]) and r <= float(zone["r_max"]):
			return true
	return false


## Rows and columns in the sampled skull grid.
##
## The grid is SPHERICAL: rows step the polar angle down from the crown, columns
## sweep the azimuth. A cylindrical (height, azimuth) grid was tried first and
## is the wrong shape for this job — it degenerates at the pole, exactly where
## a bald patch shows, because every column collapses onto the same point and
## the radius there carries no direction information at all. In spherical the
## crown is just another row.
const SKULL_ROWS: int = 28
const SKULL_COLS: int = 48

## Polar angle the grid covers, radians from straight up. 2.0 rad (~115 deg)
## reaches from the crown down past the ears to the jawline.
const SKULL_MAX_THETA: float = 2.0

## Lowest point sampled as "skull", in metres.
##
## 1.52 is just above the jawline on a 1.75 m figure. At 1.44 the sample caught
## the SHOULDERS, which sit at r ~0.25, and the cap dutifully flared out to
## meet them — the hair rendered as a set of huge flat slabs around the head.
const SKULL_MIN_Y: float = 1.52

## Largest radius accepted as skull, in metres — an outlier reject, not a size
## limit. Set generously: at 0.125 it was REJECTING the real back of the head
## (which reaches ~0.12 from a slightly forward-set centre) and punching holes
## straight through the grid, which then filled from neighbours and tore the
## cap into spikes.
const SKULL_MAX_RADIUS: float = 0.180


## Measure the imported skull's actual surface and return a radius grid the
## hair can be built on.
##
## **Why this exists.** Kern's hair is authored against `kern_head.gd`'s
## SCULPTED skull — a parametric profile. The imported head is a different
## shape, so a cap built on the sculpted curve sits inside the imported one
## near the crown and the skin pushes through it. That is not fixable by
## scaling the cap: growing it drives its lower edge up and out around the
## head, exposing MORE forehead, which four tuning passes confirmed the hard
## way. The cap has to be built on the real surface.
##
## Returns `{ ok, centre: Vector3, radius: PackedFloat32Array }` where `radius`
## is a SKULL_ROWS x SKULL_COLS spherical grid indexed
## `[row * SKULL_COLS + col]`. Rows step the polar angle from 0 (straight up
## from `centre`) to `SKULL_MAX_THETA`; columns sweep azimuth `psi` from -PI to
## PI, matching `kern_head.gd`'s convention — 0 is the face midline, +X is the
## character's right, PI is the back.
static func sample_skull(root: Node3D) -> Dictionary:
	var fail: Dictionary = {"ok": false}
	var points: PackedVector3Array = PackedVector3Array()
	# Vertices must be carried into MODEL space through the real node chain:
	# the mesh's transform relative to the root, then the root's own turn (the
	# .glb is rotated PI about Y so the import faces -Z like everything else).
	#
	# Hand-negating x and z instead — on the assumption that raw vertices were
	# already model-space — double-rotated the samples and built the entire cap
	# on the BACK of the head. `strip_covered_geometry()` gets away with raw
	# vertices only because it measures `length(x, z)`, which a Y-rotation
	# leaves unchanged; azimuth is not so forgiving.
	for mi in _all_mesh_instances(root):
		if not String(mi.name).begins_with("KernBody"):
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var to_model: Transform3D = root.transform * _relative_transform(mi, root)
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = to_model * v
				if p.y >= SKULL_MIN_Y:
					points.append(p)
	if points.size() < 64:
		return fail

	# Centre from the BOUNDING BOX, not the mean. The face carries far more
	# vertices than the cranium, so a mean is dragged forward into the nose and
	# the back of the head then measures nearly twice the front.
	var lo: Vector3 = Vector3(INF, INF, INF)
	var hi: Vector3 = -Vector3(INF, INF, INF)
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	if hi.y - lo.y < 0.02:
		return fail
	# Sphere origin sits low in the cranium — roughly ear height — so the whole
	# dome lies within the polar band above it.
	var centre: Vector3 = Vector3((lo.x + hi.x) * 0.5,
		lo.y + (hi.y - lo.y) * 0.30, (lo.z + hi.z) * 0.5)

	# Max radius per cell: the cap must enclose the skull, so the OUTERMOST
	# sample in a direction is the one that matters. A mean would leave the
	# bumps poking through, which is the exact defect being fixed.
	var radius: PackedFloat32Array = PackedFloat32Array()
	radius.resize(SKULL_ROWS * SKULL_COLS)
	radius.fill(0.0)
	for p in points:
		var d: Vector3 = p - centre
		var r: float = d.length()
		if r < 0.001 or r > SKULL_MAX_RADIUS:
			continue
		var theta: float = acos(clampf(d.y / r, -1.0, 1.0))
		if theta > SKULL_MAX_THETA:
			continue
		var psi: float = atan2(d.x, -d.z)
		var row: int = clampi(int(theta / SKULL_MAX_THETA
			* float(SKULL_ROWS - 1) + 0.5), 0, SKULL_ROWS - 1)
		var col: int = clampi(int((psi + PI) / TAU * float(SKULL_COLS - 1)
			+ 0.5), 0, SKULL_COLS - 1)
		var at: int = row * SKULL_COLS + col
		if r > radius[at]:
			radius[at] = r
	_fill_empty_cells(radius)

	return {"ok": true, "centre": centre, "radius": radius}


## Any cell no vertex landed in is filled from its neighbours, so the lookup
## never returns a zero radius and collapses the cap to the centreline.
static func _fill_empty_cells(radius: PackedFloat32Array) -> void:
	for row in SKULL_ROWS:
		# Walk the ring twice so a gap can be filled from either side.
		for _pass in 2:
			for col in SKULL_COLS:
				var at: int = row * SKULL_COLS + col
				if radius[at] > 0.0:
					continue
				var prev: float = radius[row * SKULL_COLS
					+ ((col - 1 + SKULL_COLS) % SKULL_COLS)]
				var next: float = radius[row * SKULL_COLS
					+ ((col + 1) % SKULL_COLS)]
				var best: float = maxf(prev, next)
				if best > 0.0:
					radius[at] = best
	# Rows that are still entirely empty (above the crown, below the cut)
	# inherit from the nearest populated row.
	for row in SKULL_ROWS:
		var any: bool = false
		for col in SKULL_COLS:
			if radius[row * SKULL_COLS + col] > 0.0:
				any = true
				break
		if any:
			continue
		var donor: int = -1
		for other in SKULL_ROWS:
			var has: bool = false
			for col in SKULL_COLS:
				if radius[other * SKULL_COLS + col] > 0.0:
					has = true
					break
			if has and (donor < 0 or absi(other - row) < absi(donor - row)):
				donor = other
		if donor < 0:
			continue
		for col in SKULL_COLS:
			radius[row * SKULL_COLS + col] = \
				radius[donor * SKULL_COLS + col] * 0.65


## Measure the imported ARM's radius along a shoulder-elbow-wrist path.
##
## Same idea as `sample_skull()`, and for the same reason: the sleeve's radius
## profile was authored against the slimmer procedural arm, so a single uniform
## scale cannot fit it to the imported one. Scaling to clothe the forearm makes
## the bicep balloon; scaling to fit the bicep leaves the forearm bare. The arm
## has its own taper and the cloth has to follow it.
##
## `path` is the polyline in MODEL space; returns one max-radius per sample
## point. Vertices further than `SLEEVE_BAND` from the polyline are ignored, so
## the torso and the opposite arm cannot contaminate the measurement.
const SLEEVE_BAND: float = 0.13

## Largest radial distance accepted as arm, metres. Rejects torso vertices that
## fall inside the band near the shoulder.
const ARM_MAX_RADIUS: float = 0.075

## Sample index past which the arm profile may only narrow — roughly the elbow
## on an 18-sample path.
const TAPER_FROM: int = 9

static func sample_arm(root: Node3D, path: Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(path.size())
	out.fill(0.0)
	if path.size() < 2:
		return out
	for mi in _all_mesh_instances(root):
		if not String(mi.name).begins_with("KernBody"):
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var to_model: Transform3D = root.transform * _relative_transform(mi, root)
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = \
				mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = to_model * v
				# Nearest sample point on the polyline, and the distance to it.
				var best_i: int = -1
				var best_d: float = INF
				for i in path.size():
					var d: float = p.distance_to(path[i] as Vector3)
					if d < best_d:
						best_d = d
						best_i = i
				if best_i < 0 or best_d > SLEEVE_BAND:
					continue
				# Radial distance from the limb's own axis at that point.
				var axis_a: Vector3 = path[maxi(best_i - 1, 0)]
				var axis_b: Vector3 = path[mini(best_i + 1, path.size() - 1)]
				var axis: Vector3 = (axis_b - axis_a)
				if axis.length_squared() < 0.000001:
					continue
				axis = axis.normalized()
				var rel: Vector3 = p - (path[best_i] as Vector3)
				var radial: float = (rel - axis * rel.dot(axis)).length()
				# An arm is never this thick. The band alone is not enough of a
				# filter near the shoulder, where torso vertices sit well within
				# it and would report a 130 mm "arm".
				if radial > ARM_MAX_RADIUS:
					continue
				if radial > out[best_i]:
					out[best_i] = radial

	# Fill samples no vertex reached, by carrying the nearest measured value
	# forward and then backward. (The first version searched for a VALUE with
	# `find()` and used the result as an index, which is meaningless and left
	# the profile full of zeros — the tube pinched shut and rendered as spikes.)
	var carry: float = 0.0
	for i in out.size():
		if out[i] > 0.0:
			carry = out[i]
		elif carry > 0.0:
			out[i] = carry
	carry = 0.0
	for i in range(out.size() - 1, -1, -1):
		if out[i] > 0.0:
			carry = out[i]
		elif carry > 0.0:
			out[i] = carry

	# Past the forearm the profile must only ever narrow. The last samples sit
	# at the wrist, where the HAND's vertices fall inside the band and push the
	# measurement back up — 0.030 at the wrist then 0.040 and 0.075 at the
	# final two, which would flare the cuff into a bell around the hand.
	for i in range(TAPER_FROM, out.size()):
		out[i] = minf(out[i], out[i - 1])

	# One smoothing pass: a max-per-bucket profile is inherently lumpy, and
	# lumps in a sleeve read as bulges rather than as cloth.
	var smoothed: PackedFloat32Array = out.duplicate()
	for i in range(1, out.size() - 1):
		smoothed[i] = (out[i - 1] + 2.0 * out[i] + out[i + 1]) * 0.25
	return smoothed


## Print the sampled skull's radius profile down the front, side and back.
##
## Cylindrical (y, psi) sampling degenerates at the crown, where the true
## radius goes to zero and there are few vertices to land in a cell — exactly
## where a bald patch would show. Reading the numbers is faster than guessing
## at renders. Run with `-- --skulldump`.
static func dump_skull(sample: Dictionary) -> void:
	var radius: PackedFloat32Array = sample["radius"]
	print("--- skull radius profile (m), spherical ---")
	print("  row  theta   front    side    back")
	for row in SKULL_ROWS:
		var theta: float = float(row) / float(SKULL_ROWS - 1) * SKULL_MAX_THETA
		# psi 0 = front, PI/2 = right side, PI = back.
		var front: int = int((0.0 + PI) / TAU * float(SKULL_COLS - 1) + 0.5)
		var side: int = int((PI * 0.5 + PI) / TAU * float(SKULL_COLS - 1) + 0.5)
		var back: int = SKULL_COLS - 1
		print("  %3d  %.3f  %.4f  %.4f  %.4f" % [row, theta,
			radius[row * SKULL_COLS + front], radius[row * SKULL_COLS + side],
			radius[row * SKULL_COLS + back]])


## Measured height of the imported body, so the code-built gear can be scaled
## to it if the export isn't exactly the spec'd 1.75 m.
static func measure_height(root: Node3D) -> float:
	var top: float = -INF
	var bottom: float = INF
	for mi in _all_mesh_instances(root):
		var aabb: AABB = mi.get_aabb()
		var world_min: Vector3 = mi.global_transform * aabb.position
		var world_max: Vector3 = mi.global_transform * (aabb.position + aabb.size)
		top = maxf(top, maxf(world_min.y, world_max.y))
		bottom = minf(bottom, minf(world_min.y, world_max.y))
	if top <= bottom:
		return 0.0
	return top - bottom

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


## GATE (2026-07-24): the imported body loads, retargets and paints correctly,
## but skinned meshes render with broken depth in the dual-skeleton setup —
## garment fragments lose the depth test against a body they geometrically
## enclose (a no-depth-test override shows them at the correct positions;
## rigid geometry at identical coordinates renders fine). Until that engine
## interaction is cracked in the editor's frame debugger, the imported body
## is opt-in: add `--kern-base` after the `--` separator on any run (studio
## included) — by default the game ships the fully-working procedural path.
static func enabled() -> bool:
	return OS.get_cmdline_user_args().has("--kern-base")


## Returns:
## { ok: bool, root: Node3D, skeleton: Skeleton3D, bones: Dictionary,
##   reason: String }
static func load_into(parent: Node3D) -> Dictionary:
	var fail: Dictionary = {"ok": false, "root": null, "skeleton": null,
		"bones": {}, "reason": ""}
	if not enabled():
		fail["reason"] = "imported base body gated off (run with -- --kern-base); using procedural body"
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
	# Upper arms + forearms under the sleeves. In the T-pose these run out
	# along X, so they're selected by radius, not height; the hands sit beyond
	# r_max and survive.
	{"y_min": 1.28, "y_max": 1.60, "r_min": 0.12, "r_max": 0.70},
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

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


## Returns:
## { ok: bool, root: Node3D, skeleton: Skeleton3D, bones: Dictionary,
##   reason: String }
static func load_into(parent: Node3D) -> Dictionary:
	var fail: Dictionary = {"ok": false, "root": null, "skeleton": null,
		"bones": {}, "reason": ""}
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
	parent.add_child(root)

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

	_apply_materials(root)
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
static func _apply_materials(root: Node) -> void:
	for mi in _all_mesh_instances(root):
		var lower: String = mi.name.to_lower()
		if _matches(lower, EYE_HINTS):
			# The iris shader wants a disc; on an imported eyeball just give it
			# the skin-safe eye material so it reads wet and dark, and let the
			# code-built iris/catchlight overlay handle the life.
			mi.material_override = KM.iris()
		elif _matches(lower, TEETH_HINTS):
			mi.material_override = KM.bone_white()
		elif _matches(lower, BROW_HINTS):
			mi.material_override = KM.brow()
		else:
			mi.material_override = KM.skin()


static func _matches(lower_name: String, hints: Array[String]) -> bool:
	for h in hints:
		if lower_name.contains(h):
			return true
	return false


static func _all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_all_mesh_instances(child))
	return out


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

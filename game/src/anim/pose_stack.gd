class_name PoseStack
extends RefCounted
## The pose a creature is in this frame, as layered bone rotations plus a root
## offset — the buffer every animation layer writes into before anything
## touches a `Skeleton3D`.
##
## **Why quaternions and not the euler `Dictionary` the old rig used.** Euler
## triples are fine for a small oscillation, which is all the placeholder gait
## ever did. They fail the moment layers have to COMBINE: adding two euler
## vectors is not composing two rotations, so an emote that raises an arm over
## a gait that is swinging it produced a limb that skewed and gimballed instead
## of blending. Quaternions compose correctly, slerp along the short arc, and
## make "blend this whole pose 40% toward that one" a one-liner — which is
## exactly what emote blend-in/blend-out needs.
##
## **Rotation convention.** Every value is a bone's rotation RELATIVE TO ITS
## REST, in the bone's parent frame — precisely what
## `Skeleton3D.set_bone_pose_rotation()` consumes. Model-space results out of
## the IK solver must be converted with `TwoBoneIk.to_local()` before landing
## here.
##
## **Architecture.** Leaf container; depends only on `anim_math.gd`. Written by
## `gait_engine.gd` consumers, `emote_player.gd` and the combat overlay; read by
## `creature_animator.gd` when it commits to the skeleton.

## bone name -> Quaternion, relative to rest.
var rotations: Dictionary = {}

## Model-space translation applied to the whole body — the pelvis drop from
## terrain adaptation, crouch, landing absorption and emote hops all land here
## rather than moving the physics body.
var root_offset: Vector3 = Vector3.ZERO

## Extra yaw applied to the whole visual, radians. Emotes that spin use it so
## the character can turn without fighting the controller's facing logic.
var root_spin: float = 0.0


## Empty the stack for a fresh frame. Reuses the backing Dictionary so a
## per-frame pose costs no allocation after the first few frames.
func clear() -> void:
	rotations.clear()
	root_offset = Vector3.ZERO
	root_spin = 0.0


## Read a bone's rotation, identity if nothing has written it yet.
func get_rot(bone: String) -> Quaternion:
	return rotations.get(bone, Quaternion.IDENTITY)


## Overwrite a bone's rotation.
func set_rot(bone: String, rotation: Quaternion) -> void:
	rotations[bone] = rotation


## Overwrite a bone's rotation from an euler triple (radians, YXZ as Godot
## orders it). Convenience for hand-authored poses, which are far easier to
## read as "0.3 rad of pitch" than as four quaternion components.
func set_euler(bone: String, euler: Vector3) -> void:
	rotations[bone] = Quaternion.from_euler(euler)


## Compose `rotation` ON TOP of whatever is already there, in the bone's own
## local frame. This is the additive layer operation: the result is "do what
## you were doing, then this as well".
func add_rot(bone: String, rotation: Quaternion) -> void:
	rotations[bone] = get_rot(bone) * rotation


## Additive layer from an euler triple.
func add_euler(bone: String, euler: Vector3) -> void:
	add_rot(bone, Quaternion.from_euler(euler))


## Blend a bone toward `rotation` by `weight` (0 keeps the current pose, 1
## replaces it). Slerp along the short arc, so a limb never swings through the
## body to reach its target.
func blend_rot(bone: String, rotation: Quaternion, weight: float) -> void:
	var w: float = clampf(weight, 0.0, 1.0)
	if w <= 0.0:
		return
	if w >= 1.0:
		rotations[bone] = rotation
		return
	var current: Quaternion = get_rot(bone)
	rotations[bone] = current.slerp(_short(current, rotation), w)


## Blend a bone toward an euler triple by `weight`.
func blend_euler(bone: String, euler: Vector3, weight: float) -> void:
	blend_rot(bone, Quaternion.from_euler(euler), weight)


## Blend this pose toward `other` by `weight`, including the root offset and
## spin.
##
## Only bones `other` actually writes are affected — a PARTIAL blend. That is
## what makes the emote layer composable: `wave` poses one arm and the head, so
## Kern keeps walking on gait-driven legs while he waves, whereas a full-body
## dance writes every bone and therefore takes the whole body over. Blending
## unwritten bones toward rest instead would straighten the legs under every
## upper-body gesture.
func blend_toward(other: PoseStack, weight: float) -> void:
	var w: float = clampf(weight, 0.0, 1.0)
	if w <= 0.0:
		return
	for bone in other.rotations:
		blend_rot(String(bone), other.rotations[bone] as Quaternion, w)
	root_offset = root_offset.lerp(other.root_offset, w)
	root_spin = lerpf(root_spin, other.root_spin, w)


## Copy every value from `other`, replacing this pose entirely.
func copy_from(other: PoseStack) -> void:
	rotations.clear()
	for bone in other.rotations:
		rotations[bone] = other.rotations[bone]
	root_offset = other.root_offset
	root_spin = other.root_spin


## Flip `to` into `from`'s hemisphere so the slerp takes the short arc.
static func _short(from: Quaternion, to: Quaternion) -> Quaternion:
	if from.dot(to) < 0.0:
		return -to
	return to


## Mirror an euler triple from one side of the body to the other.
##
## The rig is built symmetric about the model's X axis, so a left-side pose
## becomes its right-side twin by negating the yaw and roll and keeping the
## pitch. Emotes author one arm and get the other for free — and, more
## importantly, cannot drift out of symmetry through a copy-paste typo.
static func mirror_euler(euler: Vector3) -> Vector3:
	return Vector3(euler.x, -euler.y, -euler.z)

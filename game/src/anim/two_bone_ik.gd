class_name TwoBoneIk
extends RefCounted
## Closed-form two-bone inverse kinematics for limbs (hip-knee-ankle,
## shoulder-elbow-wrist) on any creature in the game.
##
## **Why analytic and not `SkeletonIK3D`.** Godot's node-based IK is an
## iterative FABRIK solver that owns the bones it touches, runs on its own
## schedule, and can't be blended per-frame against a procedural pose. A limb
## with exactly two segments has an EXACT solution from the law of cosines — one
## square root, no iteration, no convergence error, and the result is just a
## pair of rotations we can weight against the gait pose like any other layer.
## That is the whole reason feet can be planted on terrain without the rest of
## the animation losing control of the leg.
##
## **Frames.** The solver works entirely in the creature's MODEL space (the
## space the rig is authored in: character faces -Z, up is +Y). Callers hand in
## model-space positions and get back model-space rotations, plus a helper to
## convert those into the parent-relative rotations `Skeleton3D` actually wants.
##
## **Architecture.** Leaf module; depends only on `anim_math.gd`. Consumed by
## `foot_planter.gd` (legs on ground) and `creature_animator.gd` (arms reaching).
## See `docs/ARCHITECTURE.md` § "Procedural animation".

## Never let the chain fully lock out — a perfectly straight limb has a
## singular bend plane, so the knee direction becomes undefined and pops. Real
## legs never hyperextend either, so holding back a hair is also correct.
const MAX_EXTENSION: float = 0.995

## Never let the chain fold past this fraction of its folded limit either,
## which keeps the cosine arguments inside the valid domain.
const MIN_EXTENSION: float = 1.02


## The result of a solve. All rotations are MODEL-space.
class Solution:
	extends RefCounted

	## Model-space rotation for the upper bone (thigh / upper arm).
	var upper_rotation: Quaternion = Quaternion.IDENTITY
	## Model-space rotation for the lower bone (shin / forearm).
	var lower_rotation: Quaternion = Quaternion.IDENTITY
	## Where the middle joint (knee / elbow) ended up, in model space. Useful
	## for debug draws and for pushing a knee out of terrain.
	var joint_position: Vector3 = Vector3.ZERO
	## Where the chain tip actually landed. Differs from the requested target
	## when the target was out of reach and got clamped — callers use this to
	## detect over-reach and lean the body instead of stretching the limb.
	var tip_position: Vector3 = Vector3.ZERO
	## True when the requested target was beyond the limb's reach and had to be
	## pulled in. The hip/pelvis solver responds by lowering the body.
	var clamped: bool = false


## Solve a two-bone chain.
##
## `root` is the model-space position of the upper bone's joint (hip/shoulder).
## `target` is where the chain tip (ankle/wrist) should land, in model space.
## `pole` is a model-space point the middle joint should aim toward — for a leg
## that is a point out in front of the knee, which is what stops knees from
## bending sideways or backwards.
## `upper_length` / `lower_length` are the segment lengths in metres.
## `rest_upper_dir` / `rest_lower_dir` are the UNIT directions each segment
## points in the rig's rest pose (for Kern's legs, very nearly straight down).
## Passing the true rest directions rather than assuming "down" is what lets the
## same solver drive an arm, a bird's wing, or a quadruped's foreleg.
static func solve(root: Vector3, target: Vector3, pole: Vector3,
		upper_length: float, lower_length: float,
		rest_upper_dir: Vector3, rest_lower_dir: Vector3) -> Solution:
	var result: Solution = Solution.new()
	var total_length: float = upper_length + lower_length
	var to_target: Vector3 = target - root
	var distance: float = to_target.length()

	# Degenerate target sitting exactly on the joint: fall back to the rest
	# direction so the limb keeps a defined orientation instead of NaN-ing.
	if distance < 0.00001:
		to_target = rest_upper_dir * (total_length * 0.5)
		distance = to_target.length()

	var chain_dir: float = distance
	# Clamp into the annulus the chain can actually reach. Outside it there is
	# no solution at all, and an unclamped acos() returns NaN.
	var reach_max: float = total_length * MAX_EXTENSION
	var reach_min: float = absf(upper_length - lower_length) * MIN_EXTENSION
	if chain_dir > reach_max:
		chain_dir = reach_max
		result.clamped = true
	elif chain_dir < reach_min:
		chain_dir = reach_min
		result.clamped = true

	var direction: Vector3 = to_target / distance
	var solved_target: Vector3 = root + direction * chain_dir

	# Law of cosines: the interior angle at the root between the chain axis and
	# the upper segment.
	var cos_root: float = clampf(
		(upper_length * upper_length + chain_dir * chain_dir
			- lower_length * lower_length) / (2.0 * upper_length * chain_dir),
		-1.0, 1.0)
	var root_angle: float = acos(cos_root)

	# The bend plane is spanned by the chain axis and the pole. Its normal is
	# the axis the joint rotates about.
	var to_pole: Vector3 = pole - root
	var bend_axis: Vector3 = direction.cross(to_pole)
	if bend_axis.length_squared() < 0.000001:
		# Pole is collinear with the chain (a leg reaching exactly at the pole).
		# Any perpendicular is valid; pick a stable one off the model axes so
		# the choice doesn't flicker frame to frame.
		bend_axis = direction.cross(Vector3.RIGHT)
		if bend_axis.length_squared() < 0.000001:
			bend_axis = direction.cross(Vector3.FORWARD)
	bend_axis = bend_axis.normalized()

	# Rotate the chain axis by the root angle, about the bend normal, to get the
	# upper segment's direction; the lower segment then just closes onto the tip.
	#
	# The sign is POSITIVE and that is load-bearing. Rotating about
	# `direction x to_pole` has instantaneous velocity `n x direction`, which by
	# the vector triple product equals the component of `to_pole` perpendicular
	# to the chain — i.e. positive angles swing the joint TOWARD the pole.
	# Negating it (the first version did) puts the knee on the far side of the
	# leg from the pole, which is exactly a backwards-bending knee.
	var upper_dir: Vector3 = direction.rotated(bend_axis, root_angle)
	var joint: Vector3 = root + upper_dir * upper_length
	var lower_dir: Vector3 = (solved_target - joint).normalized()

	result.joint_position = joint
	result.tip_position = solved_target
	result.upper_rotation = _swing_twist(rest_upper_dir, upper_dir, bend_axis)
	result.lower_rotation = _swing_twist(rest_lower_dir, lower_dir, bend_axis)
	return result


## Build the model-space rotation that carries `rest_dir` onto `solved_dir`
## while keeping the limb's bend plane square to `bend_axis`.
##
## A bare `rest_dir -> solved_dir` shortest-arc rotation leaves the twist about
## the bone's own axis undefined, which shows up as a shin that rolls as the leg
## swings (feet pigeon-toe in and out). Building both frames explicitly and
## taking their difference pins the twist to the bend plane, so the knee and
## ankle stay square through the whole stride.
static func _swing_twist(rest_dir: Vector3, solved_dir: Vector3,
		bend_axis: Vector3) -> Quaternion:
	var rest_frame: Basis = _frame(rest_dir, bend_axis)
	var solved_frame: Basis = _frame(solved_dir, bend_axis)
	return (solved_frame * rest_frame.inverse()).get_rotation_quaternion()


## Orthonormal frame with its Y axis along `dir` and its X axis as close to
## `bend_axis` as orthogonality allows (Gram-Schmidt).
static func _frame(dir: Vector3, bend_axis: Vector3) -> Basis:
	var y_axis: Vector3 = dir.normalized()
	var x_axis: Vector3 = bend_axis - y_axis * bend_axis.dot(y_axis)
	if x_axis.length_squared() < 0.000001:
		# bend_axis parallel to the bone: choose any stable perpendicular.
		x_axis = y_axis.cross(Vector3.FORWARD)
		if x_axis.length_squared() < 0.000001:
			x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis)
	return Basis(x_axis, y_axis, z_axis)


## Convert a MODEL-space bone rotation into the parent-relative rotation that
## `Skeleton3D.set_bone_pose_rotation()` expects.
##
## Godot stores a bone pose relative to its parent's pose, so a chain composes:
## model(child) = model(parent) * local(child). Inverting that is the last step
## of every IK write, and forgetting it is the classic "the knee rotates twice
## as far as it should" bug.
static func to_local(model_rotation: Quaternion,
		parent_model_rotation: Quaternion) -> Quaternion:
	return parent_model_rotation.inverse() * model_rotation


## Measured length between two model-space rest positions — small helper so rigs
## can derive their segment lengths from the skeleton instead of hard-coding
## numbers that drift when the body is re-proportioned.
static func segment_length(from_rest: Vector3, to_rest: Vector3) -> float:
	return from_rest.distance_to(to_rest)

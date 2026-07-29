class_name LocomotionProfile
extends RefCounted
## Everything the animation system needs to know about one creature's BODY:
## measured limb lengths, joint rest positions, and the set of gaits it can use.
##
## **Measured, not typed in.** Almost every field is read off the creature's
## actual `Skeleton3D` rest pose at bind time rather than hard-coded. Kern's
## proportions have already been re-tuned several times across the project's
## life, and every hand-copied "thigh is 0.417 m" constant is a bug waiting for
## the next re-proportion. Measuring also means a wolf, a villager and a boss
## all configure themselves from their own rig with no new code.
##
## **Scaling the gait set.** Stride length and step height are governed by leg
## length in real animals (dynamic similarity — the Froude number). So the human
## presets in `gait_profile.gd` are authored for Kern's 0.81 m leg and then
## scaled by the measured ratio, which gives a short villager a believably
## shorter, quicker stride for free instead of making them moonwalk.
##
## **Architecture.** Depends on `gait_profile.gd`. Built once per creature by
## `creature_animator.gd`. See `docs/ARCHITECTURE.md` § "Procedural animation".

## Leg length the human gait presets were authored against, metres: the
## hip-to-ankle distance of the real 1.78 m adult whose gait-lab figures the
## presets came from.
##
## This is deliberately NOT Kern's own leg length. Kern's rig puts his ankle
## joint about 4 cm higher than a real one, so his usable leg is ~7% shorter
## than the anatomy the stride numbers assume — and a stride authored for a
## longer leg is exactly what forces an IK solver to over-reach. Anchoring the
## presets to real anatomy makes `rescale_gaits()` shorten his stride to suit,
## and does the same automatically for any creature built to any size.
const REFERENCE_LEG: float = 0.870

## Fraction of full leg extension the IK is allowed to use. Keeps the knee off
## its singular straight-locked position and matches real legs, which never
## fully extend under load.
const USABLE_REACH: float = 0.985

## Deepest the hip may sit below its rest height while simply walking, as a
## fraction of leg length. Sets the ceiling on stride length via
## `max_reachable_stride()`.
const MAX_STANCE_CROUCH: float = 0.085


## Measured hip (thigh joint) rest position per side, model space. Index 0 is
## left, 1 is right — the same indexing the gait and planter use throughout.
var hip_rest: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

## Measured thigh and shin lengths, metres.
var thigh_length: float = 0.417
var shin_length: float = 0.393

## Rest direction of the thigh and shin bones in model space — handed to the IK
## so it works on rigs whose limbs do not hang exactly straight down.
var thigh_rest_dir: Vector3 = Vector3.DOWN
var shin_rest_dir: Vector3 = Vector3.DOWN

## Rest height of the ankle joint above the creature's origin, metres. Foot
## targets are authored relative to this.
var ankle_rest_y: float = 0.115

## Half the distance between the hips, metres. Sets the stance width.
var hip_half_width: float = 0.095

## Rest height of the pelvis above the origin, metres.
var pelvis_rest_y: float = 0.98

## Full rest position of the pelvis bone, model space.
##
## The leg IK rotates the hip joints about this exact point, and `Skeleton3D`
## composes the real bone chain about it too. Approximating it as
## `(0, pelvis_rest_y, 0)` looks harmless but drops the rig's 5 mm forward
## offset, so the solver and the skeleton disagreed about where the thigh joint
## ended up and every planted foot missed its target by that much — which shows
## up as slip, because the miss changes as the pelvis rotates.
var pelvis_rest: Vector3 = Vector3(0.0, 0.98, 0.0)

## Overall height, metres — used for scale-relative tuning.
var height: float = 1.78

## Gait set, blended by speed.
var idle: GaitProfile = GaitProfile.human_idle()
var walk: GaitProfile = GaitProfile.human_walk()
var jog: GaitProfile = GaitProfile.human_jog()
var run: GaitProfile = GaitProfile.human_run()
var sprint: GaitProfile = GaitProfile.human_sprint()
var crouch_idle: GaitProfile = GaitProfile.human_crouch_idle()
var crouch_walk: GaitProfile = GaitProfile.human_crouch_walk()

## Scratch profile reused by `blend_for_speed` so the per-frame path allocates
## nothing. Never read it directly — it holds an intermediate blend.
var _crouch_scratch: GaitProfile = GaitProfile.new()


## Usable hip-to-ankle reach, metres — the IK target distance ceiling and the
## number `foot_planter.gd` uses to decide when the pelvis must drop.
func leg_reach() -> float:
	return (thigh_length + shin_length) * USABLE_REACH


## Full leg length, metres.
func leg_length() -> float:
	return thigh_length + shin_length


## Build a profile by measuring a real skeleton.
##
## `bones` maps the animation's bone names to indices (the dictionary
## `kern_body_builder.gd` returns). Bones that are missing leave their defaults
## in place, so a partial rig degrades instead of erroring.
static func from_skeleton(skeleton: Skeleton3D, bones: Dictionary,
		total_height: float) -> LocomotionProfile:
	var p: LocomotionProfile = LocomotionProfile.new()
	p.height = total_height

	var thigh_l: Vector3 = _rest_origin(skeleton, bones, "ThighL")
	var thigh_r: Vector3 = _rest_origin(skeleton, bones, "ThighR")
	var shin_l: Vector3 = _rest_origin(skeleton, bones, "ShinL")
	var foot_l: Vector3 = _rest_origin(skeleton, bones, "FootL")
	var hips: Vector3 = _rest_origin(skeleton, bones, "Hips")

	if thigh_l != Vector3.INF and thigh_r != Vector3.INF:
		p.hip_rest = [thigh_l, thigh_r]
		p.hip_half_width = absf(thigh_r.x - thigh_l.x) * 0.5
	if thigh_l != Vector3.INF and shin_l != Vector3.INF:
		p.thigh_length = thigh_l.distance_to(shin_l)
		p.thigh_rest_dir = (shin_l - thigh_l).normalized()
	if shin_l != Vector3.INF and foot_l != Vector3.INF:
		p.shin_length = shin_l.distance_to(foot_l)
		p.shin_rest_dir = (foot_l - shin_l).normalized()
	if foot_l != Vector3.INF:
		p.ankle_rest_y = foot_l.y
	if hips != Vector3.INF:
		p.pelvis_rest_y = hips.y
		p.pelvis_rest = hips

	p.rescale_gaits()
	return p


## Rescale every gait in the set from the reference human leg onto this
## creature's measured leg.
##
## Stride and step height scale linearly with leg length; SPEED scales with its
## square root, because gravity-driven gaits obey dynamic similarity (a pendulum
## twice as long swings only sqrt(2) times slower). Duty factors, lean angles
## and joint amplitudes are dimensionless and are left alone.
func rescale_gaits() -> void:
	var ratio: float = leg_length() / REFERENCE_LEG
	# No early-out when the ratio is 1: the stride cap below must run for every
	# creature, including one that happens to match the reference exactly.
	var speed_ratio: float = sqrt(ratio)
	for entry in [idle, walk, jog, run, sprint, crouch_idle, crouch_walk]:
		var g: GaitProfile = entry
		g.speed *= speed_ratio
		g.stride *= ratio
		g.step_height *= ratio
		g.pelvis_bob *= ratio
		g.pelvis_sway *= ratio
		g.pelvis_drop *= ratio
		g.knee_pole_ahead *= ratio
		g.stride = minf(g.stride, max_reachable_stride(g))


## The longest stride this creature can take without crouching more than
## `MAX_STANCE_CROUCH` of its leg length.
##
## A stride is not a free parameter: reaching further forward with a fixed-length
## leg can only be paid for by lowering the hip, and past a few percent that
## stops reading as "striding out" and starts reading as "sneaking". Rather than
## let a too-long stride quietly sink the character (which is exactly what a
## first pass here did — Kern walked in a 16 cm squat), the stride is clamped to
## what the leg can actually do and the cadence rises to keep the speed.
func max_reachable_stride(gait: GaitProfile) -> float:
	var rest_height: float = hip_rest[0].y - ankle_rest_y
	# Faster gaits are allowed to sit lower, because runners genuinely do: the
	# profile's own `pelvis_drop` is added to the standing allowance rather than
	# holding every gait to a walk's posture. Budgeting the pelvis BOB in here
	# as well was tried and is wrong — it collapsed the run stride to 0.86 m,
	# which at 5.6 m/s is 780 steps a minute, i.e. a scurry.
	var usable: float = rest_height \
		- (leg_length() * MAX_STANCE_CROUCH + gait.pelvis_drop)
	var reach: float = leg_reach()
	if usable >= reach:
		return gait.stride
	var reach_out: float = sqrt(reach * reach - usable * usable)
	var duty: float = clampf(gait.duty, 0.05, 0.95)
	return (reach_out + gait.heel_lever) * 2.0 / duty


## Choose and blend the gait for a given ground speed, writing the result into
## `out` so the per-frame path allocates nothing.
##
## `crouch` (0..1) cross-fades the whole result toward the crouched gaits, so a
## character can be half-crouched at a jog and still look coherent.
func blend_for_speed(out: GaitProfile, speed: float, crouch: float) -> void:
	_blend_upright(out, speed)
	var c: float = clampf(crouch, 0.0, 1.0)
	if c <= 0.001:
		return
	var crouch_t: float = clampf(speed / maxf(crouch_walk.speed, 0.01), 0.0, 1.0)
	GaitProfile.blend_into(_crouch_scratch, crouch_idle, crouch_walk, crouch_t)
	GaitProfile.blend_into(out, out, _crouch_scratch, c)


## Blend across the upright gait ladder by speed.
func _blend_upright(out: GaitProfile, speed: float) -> void:
	if speed <= idle.speed:
		out.copy_from(idle)
	elif speed < walk.speed:
		GaitProfile.blend_into(out, idle, walk,
			(speed - idle.speed) / maxf(walk.speed - idle.speed, 0.01))
	elif speed < jog.speed:
		GaitProfile.blend_into(out, walk, jog,
			(speed - walk.speed) / maxf(jog.speed - walk.speed, 0.01))
	elif speed < run.speed:
		GaitProfile.blend_into(out, jog, run,
			(speed - jog.speed) / maxf(run.speed - jog.speed, 0.01))
	elif speed < sprint.speed:
		GaitProfile.blend_into(out, run, sprint,
			(speed - run.speed) / maxf(sprint.speed - run.speed, 0.01))
	else:
		out.copy_from(sprint)


## A bone's global rest origin, or `Vector3.INF` when the rig lacks that bone.
static func _rest_origin(skeleton: Skeleton3D, bones: Dictionary,
		bone_name: String) -> Vector3:
	var idx: int = bones.get(bone_name, -1)
	if idx < 0:
		return Vector3.INF
	return skeleton.get_bone_global_rest(idx).origin

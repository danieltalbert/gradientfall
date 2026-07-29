class_name CreatureAnimator
extends RefCounted
## Drives one legged creature's whole body from its physics state: gait, foot
## planting, terrain adaptation, air and landing behaviour, body lean, idle
## life and emotes, composited into a single `PoseStack` per frame.
##
## **What it is for.** This is the piece that makes the framework reusable.
## `kern_visual.gd` used to own ~200 lines of hand-tuned sine waves that only
## Kern could ever use; everything general has moved here, so a villager, a
## wolf or a boss gets the same distance-phased gait, ground-locked feet, slope
## adaptation and momentum lean by constructing one of these against its own
## skeleton. What stays in the character's own script is only what is genuinely
## its own — Kern's cloak, sword, arcane glow and combat poses.
##
## **Frame order** (each step depends on the last, so the order is load-bearing):
##   1. measure real displacement -> advance the distance-phased gait
##   2. choose and blend the gait profile for the current speed and crouch
##   3. place the pelvis (terrain drop, crouch, bob, landing absorption, lean)
##   4. project ideal foot targets into the world, probe the ground, plant them
##   5. solve both legs with analytic IK back onto those planted targets
##   6. layer torso, arms, head, idle life
##   7. cross-fade the airborne pose, then composite any emote on top
##
## **Architecture.** Depends on every other module in `src/anim/`; owns no
## nodes. Its output is a `PoseStack` that the caller commits to whatever
## skeletons it has — which is what lets `kern_visual.gd` keep driving both its
## procedural rig and the imported base-mesh rig from one animation.
## See `docs/ARCHITECTURE.md` § "Procedural animation".

const AM: GDScript = preload("res://src/anim/anim_math.gd")

## Half-life for the speed used to pick a gait. Long enough that a stutter in
## the input does not flick the character between gaits, short enough that
## breaking into a run still reads as immediate.
const SPEED_HALF_LIFE: float = 0.10

## Half-life for the airborne cross-fade.
const AIR_HALF_LIFE: float = 0.07

## Ground speed at which locomotion reaches full amplitude, m/s.
const FULL_STRIDE_SPEED: float = 0.75

## Vertical speed treated as a maximum-impact landing, m/s.
const HARD_LANDING_SPEED: float = 12.0

## Deepest the pelvis dips absorbing a landing, metres.
const MAX_LANDING_DIP: float = 0.30

## Deepest the pelvis will drop to keep a downhill foot reachable, metres.
const MAX_TERRAIN_DROP: float = 0.42

## Distance below the feet at which a falling creature starts reaching for the
## ground, metres. Landing anticipation is a large part of why a real jump
## reads as controlled rather than as a dropped puppet.
const LANDING_REACH_DISTANCE: float = 1.30


## Measured body configuration and gait set.
var profile: LocomotionProfile

## The distance-phased cycle.
var gait: GaitEngine = GaitEngine.new()

## Ground probing and plant locking.
var planter: FootPlanter = FootPlanter.new()

## Emote playback.
var emotes: EmotePlayer = EmotePlayer.new()

## The composited pose for this frame.
var pose: PoseStack = PoseStack.new()

## Blended gait profile for this frame — exposed so debug overlays and the
## locomotion lab can report which gait is actually active.
var active_gait: GaitProfile = GaitProfile.new()

## Smoothed ground speed, m/s.
var speed_smooth: float = 0.0

## How airborne the creature is, 0..1.
var air_blend: float = 0.0

## Resolved ground state per foot from this frame, for callers that want to
## spawn dust, play footstep audio or trample grass.
var feet: Array = []

## Diagnostics for the locomotion lab: how far the IK's own solution fell short
## of the requested target this frame (metres, worst foot), and whether it had
## to clamp. Distinguishes "the leg could not reach" from "the leg reached but
## the skeleton ended up somewhere else", which look identical from outside and
## have completely different fixes.
var ik_tip_error: float = 0.0
var ik_clamped: bool = false

## World-space ankle position the IK was ASKED for, and the one it actually
## solved, per foot. The locomotion lab compares both against the rendered bone
## to tell apart three different failures that look identical from outside: a
## wrong target, a solver that fell short, and a solution that something later
## in the frame overwrote.
var ik_target_world: Array = [Vector3.ZERO, Vector3.ZERO]
var ik_solved_world: Array = [Vector3.ZERO, Vector3.ZERO]

var _visual: Node3D
var _body: Node3D
var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _prev_position: Vector3 = Vector3.ZERO
var _have_prev: bool = false
var _model_to_world: Transform3D = Transform3D.IDENTITY
var _world_to_model: Transform3D = Transform3D.IDENTITY

# Secondary motion springs.
var _lean: AnimMath.Spring3 = AnimMath.Spring3.new(Vector3.ZERO, 0.13)
var _landing_dip: AnimMath.Spring1 = AnimMath.Spring1.new(0.0, 0.11)
var _crouch_smooth: AnimMath.Spring1 = AnimMath.Spring1.new(0.0, 0.09)
var _head_look: AnimMath.Spring3 = AnimMath.Spring3.new(Vector3.ZERO, 0.16)
## Where the head is being asked to look, as (pitch, yaw, 0) in radians.
## `look_at_world()` writes it; the spring eases toward it every frame so a
## target that appears suddenly does not snap the neck.
var _look_target: Vector3 = Vector3.ZERO
var _prev_velocity: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0

# Idle life.
var _idle_time: float = 0.0
var _fidget_countdown: float = 5.0
var _fidget_id: int = -1
var _fidget_time: float = 0.0

## Set true by `notify_landing()`; consumed on the next tick.
var _pending_impact: float = 0.0


## Bind to a creature. `visual` is the node the animation rotates to face
## travel, `body` is the physics body whose displacement drives the gait,
## `skeleton` and `bones` are the rig, `height` is the creature's height in
## metres, and `exclude` are collider RIDs the ground probes must ignore
## (always at least the creature's own body).
func bind(visual: Node3D, body: Node3D, skeleton: Skeleton3D,
		bones: Dictionary, height: float, collision_mask: int,
		exclude: Array[RID]) -> void:
	_visual = visual
	_body = body
	_skeleton = skeleton
	_bones = bones
	profile = LocomotionProfile.from_skeleton(skeleton, bones, height)
	# The rocker geometry rotates the foot about a point on the GROUND, so the
	# gait needs to know how high the ankle rides above the sole.
	gait.set_ankle_height(profile.ankle_rest_y)
	planter.setup(visual, collision_mask, exclude)
	active_gait.copy_from(profile.idle)
	_prev_position = body.global_position
	_have_prev = true
	_prev_yaw = visual.rotation.y


## Tell the animator the creature just landed at `impact_speed` m/s downward,
## so it can absorb the landing with the knees and pelvis.
func notify_landing(impact_speed: float) -> void:
	_pending_impact = maxf(_pending_impact, absf(impact_speed))


## Reset all continuous state — call on teleport, respawn and scene changes so
## springs and plant locks do not drag the body back toward where it was.
func teleported() -> void:
	gait.reset()
	planter.reset()
	_lean.reset(Vector3.ZERO)
	_landing_dip.reset(0.0)
	_head_look.reset(Vector3.ZERO)
	_have_prev = false
	air_blend = 0.0


## Build this frame's pose. `velocity` and `on_floor` come from the physics
## body; `crouch` is 0..1. Returns the composited pose.
func tick(delta: float, velocity: Vector3, on_floor: bool,
		crouch: float) -> PoseStack:
	if _visual == null or _skeleton == null:
		return pose
	_update_transforms()
	var travelled: float = _measure_travel()

	var ground_speed: float = Vector2(velocity.x, velocity.z).length()
	speed_smooth = AM.damp(speed_smooth, ground_speed, SPEED_HALF_LIFE, delta)
	var crouch_amount: float = _crouch_smooth.step(clampf(crouch, 0.0, 1.0), delta)

	profile.blend_for_speed(active_gait, speed_smooth, crouch_amount)
	# Only ground contact advances the cycle: a creature in mid-air is not
	# taking steps, and letting flight advance the phase makes the legs windmill.
	gait.advance(travelled * (1.0 - air_blend), active_gait, delta)

	air_blend = AM.damp(air_blend, 0.0 if on_floor else 1.0,
		AIR_HALF_LIFE, delta)
	_idle_time += delta

	pose.clear()

	var body_phase: GaitEngine.BodyPhase = gait.body_phase(active_gait)
	var stride_weight: float = AM.smoothstep01(
		speed_smooth / FULL_STRIDE_SPEED) * (1.0 - air_blend)

	_update_lean(delta, velocity, ground_speed)
	var pelvis_offset: Vector3 = _place_pelvis(delta, body_phase, stride_weight,
		crouch_amount, on_floor)
	_solve_legs(delta, pelvis_offset, body_phase, stride_weight)
	_pose_torso(body_phase, stride_weight, crouch_amount)
	_pose_arms(stride_weight, crouch_amount)
	_pose_head(body_phase, stride_weight, delta)
	_idle_life(delta, stride_weight, crouch_amount)
	_air_pose(velocity)

	emotes.tick(delta)
	if emotes.weight() > 0.001:
		pose.blend_toward(emotes.pose, emotes.weight())
		# A full-body emote has taken the legs off the gait, so the feet are no
		# longer gait-planted: clear the stance flags. Everything downstream
		# keys off them — footstep audio, dust, grass trample, the locomotion
		# bench — and none of it should fire walking cues out of a dance.
		if emotes.overrides_legs() and emotes.weight() > 0.5:
			for entry in feet:
				(entry as FootPlanter.FootGround).stance = false
	return pose


# --- Frames and travel -------------------------------------------------------

## Rebuild the model<->world transforms for this frame.
##
## Deliberately reconstructed from the body position and the visual's yaw
## rather than read from `_visual.global_transform`: the visual node also
## carries the jump/land squash SCALE, and feeding a non-uniform scale into the
## foot IK would stretch every target off the ground.
func _update_transforms() -> void:
	var yaw: float = _visual.rotation.y
	var body_basis: Basis = _body.global_transform.basis.orthonormalized()
	_model_to_world = Transform3D(body_basis * Basis(Vector3.UP, yaw),
		_body.global_position)
	_world_to_model = _model_to_world.affine_inverse()


## Ground distance covered since the last frame, signed along the facing.
##
## Measured from the body's ACTUAL displacement, not from `velocity * delta`:
## the two disagree whenever `move_and_slide` clips a wall or rides a slope, and
## the gait must follow the ground the body really covered or the feet slip
## exactly in the moments a player is most likely to notice.
func _measure_travel() -> float:
	var position: Vector3 = _body.global_position
	if not _have_prev:
		_prev_position = position
		_have_prev = true
		return 0.0
	var displacement: Vector3 = position - _prev_position
	_prev_position = position
	displacement.y = 0.0
	var forward: Vector3 = -_model_to_world.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return displacement.length()
	return displacement.dot(forward.normalized())


# --- Lean --------------------------------------------------------------------

## Momentum lean: the body tips into acceleration and banks into turns.
##
## This is cheap and disproportionately convincing. A character that changes
## direction with a perfectly upright torso reads as weightless no matter how
## good the footwork is, because real mass has to be thrown before it moves.
func _update_lean(delta: float, velocity: Vector3, ground_speed: float) -> void:
	var acceleration: Vector3 = (velocity - _prev_velocity) / maxf(delta, 0.0001)
	_prev_velocity = velocity
	acceleration.y = 0.0

	var local_accel: Vector3 = _world_to_model.basis * acceleration
	# Forward lean from longitudinal acceleration (-Z is forward).
	var lean_forward: float = clampf(-local_accel.z * 0.010, -0.22, 0.28)
	# Bank from turn rate scaled by speed: standing still and spinning should
	# not throw the body over, but carving at a run should.
	var yaw_rate: float = wrapf(_visual.rotation.y - _prev_yaw, -PI, PI) \
		/ maxf(delta, 0.0001)
	_prev_yaw = _visual.rotation.y
	var bank: float = clampf(yaw_rate * ground_speed * 0.016, -0.20, 0.20)
	_lean.step(Vector3(lean_forward, 0.0, bank), delta)


# --- Pelvis ------------------------------------------------------------------

## Position the pelvis: gait bob and sway, crouch depth, landing absorption and
## the terrain drop that keeps a downhill foot reachable. Returns the model-
## space offset, which the leg IK then solves against.
func _place_pelvis(delta: float, body_phase: GaitEngine.BodyPhase,
		stride_weight: float, crouch_amount: float,
		on_floor: bool) -> Vector3:
	# Landing absorption: convert the impact into a dip the spring recovers.
	if _pending_impact > 0.0:
		var severity: float = clampf(_pending_impact / HARD_LANDING_SPEED,
			0.0, 1.0)
		_landing_dip.value -= MAX_LANDING_DIP * severity
		_pending_impact = 0.0
	_landing_dip.step(0.0, delta)

	var crouch_drop: float = -active_gait.pelvis_drop * crouch_amount
	var bob: float = body_phase.bob * stride_weight
	var sway: float = body_phase.sway * stride_weight
	var terrain: float = planter.pelvis_offset if on_floor else 0.0
	# Blend from the standing flex to the gait's own stance depth. Never zero:
	# Kern's rest pose puts the hip at EXACTLY leg length above the ankle, so
	# with no flex at all he stands with locked, dead-straight knees, the IK
	# sits on its singular fully-extended configuration, and every idle frame
	# clamps. A centimetre of flex fixes the look and the maths together.
	var gait_drop: float = lerpf(_standing_flex(), _gait_stance_drop(),
		stride_weight)

	# One offset, published on the pose so the caller can translate the pelvis
	# bone with it, and returned so the leg IK solves against the same number.
	# Splitting them was how an earlier pass ended up with legs that solved for
	# a pelvis position the mesh was not actually at.
	var offset: Vector3 = Vector3(sway,
		bob + crouch_drop + terrain + gait_drop + _landing_dip.value, 0.0)
	pose.root_offset = offset
	return offset


## Baseline knee flex while standing still, as a pelvis drop in metres
## (negative).
##
## Small numbers go a long way here: the hip-height-to-knee-angle relationship
## is a cosine near full extension, so lowering Kern's pelvis by one centimetre
## already bends the knee about 16° — comfortably "standing relaxed" rather than
## "locked at attention".
func _standing_flex() -> float:
	return -profile.leg_length() * 0.012


## Rest height of the thigh joint above the ankle joint, metres — the leg's
## own vertical span, and the reference every stance-depth calculation uses.
func _hip_rest_height() -> float:
	return profile.hip_rest[0].y - profile.ankle_rest_y


## How far the pelvis must sit below its rest height for this gait's stride to
## be reachable, in metres (never positive).
##
## Kern's rest pose puts the hip at EXACTLY leg-length above the ankle — legs
## dead straight — so at rest height the legs cannot reach forward at all
## without the IK clamping. Real bodies carry a permanent stance flexion, and
## the faster the gait the deeper it gets, which is why sprinters run low.
## Deriving it from the actual stride rather than hard-coding a crouch means
## every creature, at every speed, sits exactly as low as its own geometry
## needs and no lower.
func _gait_stance_drop() -> float:
	var duty: float = clampf(active_gait.duty, 0.05, 0.95)
	# The furthest the ankle gets from directly under the hip. The heel rocker
	# pulls the heel-strike position slightly back toward the body, so the
	# reach the leg actually has to make is a little less than the raw stride.
	var reach_out: float = maxf(0.0, active_gait.stride * duty * 0.5
		- active_gait.heel_lever)
	var leg: float = profile.leg_reach()
	if reach_out >= leg:
		return -(profile.pelvis_rest_y - profile.ankle_rest_y) * 0.35
	# Pythagoras: the vertical the leg has left once it has reached that far.
	var usable_height: float = sqrt(leg * leg - reach_out * reach_out)
	# Measured from the THIGH JOINT, which is what the leg actually hangs from
	# — not from the pelvis bone, which sits 5.5 cm higher on this rig. Using
	# the pelvis made the solver believe the legs were longer than they are and
	# crouched Kern that much deeper than the geometry ever required.
	#
	# The pelvis bob is subtracted as headroom: the hip spends half of every
	# step ABOVE its mean height, and sizing the stance for the mean leaves the
	# leg over-reaching on exactly those frames. That is most of why the fast
	# gaits clamped their IK far more often than the walk did.
	return minf(0.0, usable_height - _hip_rest_height()
		- active_gait.pelvis_bob)


# --- Legs --------------------------------------------------------------------

## Place both feet on the world and solve the legs onto them.
func _solve_legs(delta: float, pelvis_offset: Vector3,
		body_phase: GaitEngine.BodyPhase, stride_weight: float) -> void:
	# Pelvis rotation, which carries the hip joints with it.
	var pelvis_rotation: Quaternion = Quaternion.from_euler(Vector3(
		-active_gait.torso_lean * stride_weight * 0.25 + _lean.value.x * 0.30,
		body_phase.pelvis_yaw * stride_weight,
		body_phase.pelvis_roll * stride_weight + _lean.value.z * 0.35))
	pose.set_rot("Hips", pelvis_rotation)

	# The exact bone origin the skeleton itself rotates the hips about.
	var pivot: Vector3 = profile.pelvis_rest
	var resolved: Array = []
	var targets: Array = []

	for index in 2:
		var foot: GaitEngine.FootPhase = gait.foot_phase(index, active_gait)
		var lateral: float = GaitEngine.stance_lateral(index,
			profile.hip_half_width)
		# The planter is given the foot's ANCHOR — where the ankle would be with
		# the sole flat — because that is the point which is genuinely
		# stationary for the whole stance. The ankle's own rocker displacement
		# is added back afterwards, so the lock never has to fight the roll.
		# Model space: forward is -Z, so the gait's forward `along` is -Z.
		var anchor_model: Vector3 = Vector3(
			lateral,
			profile.ankle_rest_y,
			-foot.anchor_along * stride_weight)
		var anchor_world: Vector3 = _model_to_world * anchor_model
		var ground: FootPlanter.FootGround = planter.resolve(index, anchor_world,
			foot.contact * (1.0 - air_blend), delta, profile.ankle_rest_y,
			0.0, foot.flat * (1.0 - air_blend))
		# Ride the ankle off the resolved anchor by the rocker offset (and, in
		# swing, by the whole swing arc).
		var rocker: Vector3 = Vector3(0.0, foot.lift,
			-(foot.along - foot.anchor_along)) * stride_weight
		ground.world_position += _model_to_world.basis * rocker
		ground.stance = foot.stance and air_blend < 0.5
		resolved.append(ground)
		targets.append(foot)
	feet = resolved

	# Drop the pelvis if either planted foot is out of reach downhill.
	var hip_world_y: float = (_model_to_world * (pivot + pelvis_offset)).y
	planter.update_pelvis(hip_world_y, resolved, profile.leg_reach(),
		MAX_TERRAIN_DROP, delta)

	for index in 2:
		var ground: FootPlanter.FootGround = resolved[index]
		var foot: GaitEngine.FootPhase = targets[index]
		var hip_model: Vector3 = pelvis_rotation * (profile.hip_rest[index]
			- pivot) + pivot + pelvis_offset
		var target_model: Vector3 = _world_to_model * ground.world_position
		# In the air the ground is meaningless; fall back to the gait's ideal so
		# the cross-fade into the air pose starts from something sensible.
		if air_blend > 0.001:
			var ideal_model: Vector3 = Vector3(
				GaitEngine.stance_lateral(index, profile.hip_half_width),
				profile.ankle_rest_y,
				-foot.along * stride_weight)
			target_model = target_model.lerp(ideal_model, air_blend)

		# Pole out in front of the knee so it always bends forward. Riding the
		# hip means the pole turns with the leg instead of dragging the knee
		# toward a fixed world point when the body rotates.
		var pole: Vector3 = hip_model + Vector3(0.0, -profile.thigh_length * 0.5,
			-active_gait.knee_pole_ahead)

		var solution: TwoBoneIk.Solution = TwoBoneIk.solve(hip_model,
			target_model, pole, profile.thigh_length, profile.shin_length,
			profile.thigh_rest_dir, profile.shin_rest_dir)
		if index == 0:
			ik_tip_error = 0.0
			ik_clamped = false
		ik_tip_error = maxf(ik_tip_error,
			solution.tip_position.distance_to(target_model))
		ik_clamped = ik_clamped or solution.clamped
		ik_target_world[index] = _model_to_world * target_model
		ik_solved_world[index] = _model_to_world * solution.tip_position

		var suffix: String = "R" if index == 1 else "L"
		var thigh_model: Quaternion = solution.upper_rotation
		var shin_model: Quaternion = solution.lower_rotation
		pose.set_rot("Thigh" + suffix,
			TwoBoneIk.to_local(thigh_model, pelvis_rotation))
		pose.set_rot("Shin" + suffix,
			TwoBoneIk.to_local(shin_model, thigh_model))

		# Ankle: the gait's heel-to-toe roll, then conform to the surface.
		var ankle_model: Quaternion = Quaternion.from_euler(
			Vector3(foot.roll * stride_weight, 0.0, 0.0))
		if ground.found and ground.contact > 0.01:
			var normal_model: Vector3 = _world_to_model.basis * ground.normal
			ankle_model = FootPlanter.align_to_surface(Vector3.UP, normal_model,
				ground.contact * (1.0 - air_blend)) * ankle_model
		pose.set_rot("Foot" + suffix,
			TwoBoneIk.to_local(ankle_model, shin_model))


# --- Torso, arms, head -------------------------------------------------------

## Spine chain: forward lean, counter-rotation against the pelvis, momentum
## lean. The spine bones point UP, so a forward lean is a NEGATIVE X rotation.
func _pose_torso(body_phase: GaitEngine.BodyPhase, stride_weight: float,
		crouch_amount: float) -> void:
	var lean: float = active_gait.torso_lean * stride_weight \
		+ _lean.value.x * 0.55
	var crouch_lean: float = 0.22 * crouch_amount
	pose.set_euler("Spine", Vector3(
		-(lean * 0.42 + crouch_lean * 0.4),
		body_phase.chest_yaw * 0.45 * stride_weight,
		(body_phase.chest_roll * 0.5 + _lean.value.z * 0.30) * stride_weight))
	pose.set_euler("Chest", Vector3(
		-(lean * 0.48 + crouch_lean * 0.5),
		body_phase.chest_yaw * 0.55 * stride_weight,
		(body_phase.chest_roll * 0.5 + _lean.value.z * 0.35) * stride_weight))


## Arms: counter-swing against the legs, with the elbow flexing on the forward
## half of the swing the way a real arm does.
func _pose_arms(stride_weight: float, crouch_amount: float) -> void:
	for index in 2:
		var right: bool = index == 1
		var suffix: String = "R" if right else "L"
		var side: float = 1.0 if right else -1.0
		# The arm opposes the SAME-side leg, so it reads off that foot's cycle
		# shifted half a turn.
		var cycle: float = fposmod(gait.phase + (0.5 if right else 0.0), 1.0)
		var swing: float = cos(cycle * TAU)
		var pitch: float = -active_gait.arm_swing * swing * stride_weight
		var abduct: float = (active_gait.arm_lift * stride_weight + 0.12
			* crouch_amount + 0.14) * side
		# Elbow closes as the hand comes forward.
		var elbow: float = active_gait.elbow_bend * stride_weight \
			+ active_gait.elbow_swing * maxf(0.0, -swing) * stride_weight \
			+ 0.18 + 0.35 * crouch_amount
		pose.set_euler("UpperArm" + suffix, Vector3(pitch, 0.0, abduct))
		pose.set_euler("Forearm" + suffix, Vector3(elbow, 0.10 * side, 0.0))
		pose.set_euler("Clavicle" + suffix, Vector3(
			-0.05 * active_gait.arm_swing * swing * stride_weight, 0.0,
			0.05 * side))


## Head: counter-rotate against the shoulders to hold the gaze level, plus the
## small residual bob real heads never quite remove, plus the look target.
func _pose_head(body_phase: GaitEngine.BodyPhase, stride_weight: float,
		delta: float) -> void:
	var stabilise: float = -body_phase.chest_yaw * 0.55 * stride_weight
	# Anticipation: the head leads a turn slightly, because people look where
	# they are going before they get there. Added to any explicit look target
	# rather than replacing it, so an NPC can hold eye contact while walking.
	var anticipation: Vector3 = Vector3.ZERO
	if speed_smooth > 0.4:
		var local_velocity: Vector3 = _world_to_model.basis * _prev_velocity
		anticipation = Vector3(0.0,
			clampf(-local_velocity.x * 0.045, -0.22, 0.22), 0.0)
	var look: Vector3 = _head_look.step(_look_target + anticipation, delta)
	pose.set_euler("Neck", Vector3(
		-body_phase.head_pitch * stride_weight - look.x * 0.45,
		stabilise * 0.5 + look.y * 0.45, 0.0))
	pose.set_euler("Head", Vector3(
		-body_phase.head_pitch * 0.5 * stride_weight - look.x * 0.55,
		stabilise * 0.5 + look.y * 0.55, 0.0))


## Point the head at a world position; pass `Vector3.INF` to release it and let
## the neck ease back to neutral. Used for NPC conversation, boss telegraphs
## and Bit's chatter — the head turning to acknowledge things is most of what
## separates a character from a prop.
func look_at_world(target: Vector3) -> void:
	if target == Vector3.INF:
		_look_target = Vector3.ZERO
		return
	var local: Vector3 = _world_to_model * target
	var flat: float = Vector2(local.x, local.z).length()
	# x of the look vector is pitch (positive looks up), y is yaw.
	_look_target = Vector3(
		clampf(atan2(local.y - profile.height * 0.85, maxf(flat, 0.01)),
			-0.45, 0.45),
		clampf(atan2(-local.x, -local.z), -0.85, 0.85), 0.0)


# --- Idle life ---------------------------------------------------------------

## Breathing, weight shift and occasional fidgets, all scaled by how still the
## creature is. Without the fidget scheduler an idle character loops a two-
## second breath forever, which the eye picks up within about ten seconds.
func _idle_life(delta: float, stride_weight: float,
		crouch_amount: float) -> void:
	var calm: float = (1.0 - stride_weight) * (1.0 - air_blend)
	if calm <= 0.001:
		_fidget_countdown = randf_range(5.0, 11.0)
		_fidget_id = -1
		return

	# Breathing: the chest opens and the shoulders rise a little on the inhale.
	var breath: float = sin(_idle_time * 1.45)
	var breath_amount: float = calm * (1.0 - 0.4 * crouch_amount)
	pose.add_euler("Chest", Vector3(-breath * 0.016 * breath_amount, 0.0, 0.0))
	pose.add_euler("Spine", Vector3(breath * 0.009 * breath_amount, 0.0, 0.0))
	pose.add_euler("ClavicleL", Vector3(0.0, 0.0, -breath * 0.020 * breath_amount))
	pose.add_euler("ClavicleR", Vector3(0.0, 0.0, breath * 0.020 * breath_amount))

	# Slow weight shift from foot to foot, and the arms drift with it.
	var shift: float = sin(_idle_time * 0.42)
	pose.add_euler("Hips", Vector3(0.0, 0.0, shift * 0.035 * calm))
	pose.add_euler("UpperArmL", Vector3(sin(_idle_time * 0.9) * 0.022 * calm,
		0.0, -shift * 0.020 * calm))
	pose.add_euler("UpperArmR", Vector3(sin(_idle_time * 0.9 + 0.7) * 0.022
		* calm, 0.0, shift * 0.020 * calm))
	pose.add_euler("Neck", Vector3(sin(_idle_time * 0.61) * 0.020 * calm,
		sin(_idle_time * 0.37) * 0.045 * calm, 0.0))

	_tick_fidget(delta, calm)


## Schedule and play short additive idle actions so a standing character keeps
## producing new motion instead of looping one breath cycle.
func _tick_fidget(delta: float, calm: float) -> void:
	if _fidget_id < 0:
		_fidget_countdown -= delta
		if _fidget_countdown <= 0.0:
			_fidget_id = randi() % 4
			_fidget_time = 0.0
		return

	_fidget_time += delta
	var duration: float = 2.4
	if _fidget_time >= duration:
		_fidget_id = -1
		_fidget_countdown = randf_range(6.0, 13.0)
		return

	# A bell envelope so every fidget eases in and out of the idle pose.
	var envelope: float = AM.bell01(_fidget_time / duration) * calm
	match _fidget_id:
		0:  # Roll the shoulders back.
			pose.add_euler("ClavicleL", Vector3(0.0, 0.0, -0.10 * envelope))
			pose.add_euler("ClavicleR", Vector3(0.0, 0.0, 0.10 * envelope))
			pose.add_euler("Chest", Vector3(-0.05 * envelope, 0.0, 0.0))
		1:  # Glance around.
			pose.add_euler("Neck", Vector3(0.05 * envelope, 0.34 * envelope, 0.0))
			pose.add_euler("Head", Vector3(0.03 * envelope, 0.22 * envelope, 0.0))
		2:  # Shift weight onto the other hip.
			pose.add_euler("Hips", Vector3(0.0, 0.0, -0.07 * envelope))
			pose.add_euler("Spine", Vector3(0.0, 0.0, 0.035 * envelope))
		3:  # Flex the sword hand and settle the shoulder.
			pose.add_euler("ForearmR", Vector3(0.20 * envelope, 0.0, 0.0))
			pose.add_euler("UpperArmR", Vector3(-0.09 * envelope, 0.0,
				0.05 * envelope))


# --- Air ---------------------------------------------------------------------

## Cross-fade toward an airborne pose: knees tuck on the way up, then the legs
## reach for the ground as it approaches. The reach is the part that reads —
## a falling character whose legs hang slack looks unconscious.
func _air_pose(velocity: Vector3) -> void:
	if air_blend <= 0.001:
		return
	var rising: float = AM.remap01(velocity.y, 0.0, 6.0)
	var falling: float = AM.remap01(-velocity.y, 1.0, 9.0)

	# How close the ground is, so the legs extend into the landing.
	var reach: float = 0.0
	if velocity.y < 0.0 and not feet.is_empty():
		var lowest: float = 999.0
		for entry in feet:
			var ground: FootPlanter.FootGround = entry
			if ground.found:
				lowest = minf(lowest, (_model_to_world * Vector3(
					0.0, profile.ankle_rest_y, 0.0)).y - ground.world_position.y)
		if lowest < 900.0:
			reach = 1.0 - AM.remap01(lowest, 0.0, LANDING_REACH_DISTANCE)

	var tuck: float = maxf(rising, falling * (1.0 - reach))
	var weight: float = air_blend

	# Trailing leg tucks harder than the leading one, which keeps the silhouette
	# asymmetric — symmetric air poses read as a mannequin dropped from a crane.
	pose.blend_euler("ThighL", Vector3(0.62 * tuck + 0.30 * reach, 0.0, 0.04),
		weight)
	pose.blend_euler("ThighR", Vector3(0.34 * tuck + 0.42 * reach, 0.0, -0.04),
		weight)
	pose.blend_euler("ShinL", Vector3(-(1.15 * tuck + 0.16), 0.0, 0.0), weight)
	pose.blend_euler("ShinR", Vector3(-(0.78 * tuck + 0.16), 0.0, 0.0), weight)
	pose.blend_euler("FootL", Vector3(0.22 * tuck - 0.18 * reach, 0.0, 0.0),
		weight)
	pose.blend_euler("FootR", Vector3(0.18 * tuck - 0.18 * reach, 0.0, 0.0),
		weight)
	# Arms lift and open for balance, more so the faster the fall.
	pose.blend_euler("UpperArmL", Vector3(-0.45 * tuck - 0.30 * falling, 0.0,
		-(0.30 + 0.25 * falling)), weight)
	pose.blend_euler("UpperArmR", Vector3(-0.45 * tuck - 0.30 * falling, 0.0,
		0.30 + 0.25 * falling), weight)
	pose.blend_euler("ForearmL", Vector3(0.55 + 0.30 * falling, 0.0, 0.0), weight)
	pose.blend_euler("ForearmR", Vector3(0.55 + 0.30 * falling, 0.0, 0.0), weight)
	pose.blend_euler("Spine", Vector3(-0.10 * falling + 0.12 * rising, 0.0, 0.0),
		weight)
	pose.blend_euler("Chest", Vector3(-0.12 * falling + 0.10 * rising, 0.0, 0.0),
		weight)

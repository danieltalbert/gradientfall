class_name GaitEngine
extends RefCounted
## Turns "how far has this creature travelled" into "where are its feet" —
## the distance-phased gait cycle at the centre of Gradientfall's animation.
##
## **The one idea that matters.** The old Kern animation advanced its cycle with
## `phase += delta * rate`: the legs cycled on a TIMER while the body moved at
## whatever speed it happened to be moving. The two are unrelated, so the feet
## skated across the ground — the single loudest tell that a character is not
## really walking. Here the cycle is advanced by DISTANCE TRAVELLED instead:
##
##     phase += distance_this_frame / stride_length
##
## Because a planted foot's body-relative position then retreats at exactly the
## speed the body advances, the foot holds still in WORLD space for the whole
## stance. Foot slip goes to zero by construction, at every speed, during
## acceleration, and through gait changes — not as a tuned approximation but as
## an algebraic identity. Everything else in this class is detail on top.
##
## **Cycle convention.** One cycle is TWO steps (left then right), so the right
## foot runs half a cycle behind the left. Within a foot's cycle, `[0, duty)` is
## stance (planted, retreating) and `[duty, 1)` is swing (lifted, reaching).
##
## **Architecture.** Depends on `anim_math.gd` and `gait_profile.gd`; owns no
## nodes and touches no skeleton, so it is testable in isolation and reusable by
## bipeds, quadrupeds (four instances, phase-offset) and the locomotion lab.
## Consumed by `creature_animator.gd`. See `docs/ARCHITECTURE.md`.

const AM: GDScript = preload("res://src/anim/anim_math.gd")

## Fraction of the cycle over which contact weight ramps at each stance edge.
## A hard 0/1 switch pops the IK; this rolls the foot on and off the ground.
const CONTACT_BLEND: float = 0.06

## Below this stride the phase integrator would divide by ~zero and spin.
const MIN_STRIDE: float = 0.05

## Where in the stance the foot is FLAT on the ground, as a fraction of stance.
## Before `FLAT_START` the body is pivoting over the heel; after `FLAT_END` it
## is rolling over the toe. Only the flat window is held perfectly still — the
## pivots are supposed to move the ankle, and forcing them still is what makes
## a walk look like it is on stilts.
const FLAT_START: float = 0.32
const FLAT_END: float = 0.72


## Per-foot state for one frame. Positions are in the creature's MODEL space
## (character faces -Z), relative to the foot's neutral standing spot.
class FootPhase:
	extends RefCounted

	## This foot's position in the cycle, 0..1.
	var cycle: float = 0.0
	## True while the foot is planted.
	var stance: bool = true
	## Progress through the stance, 0..1. Meaningless while swinging.
	var stance_t: float = 0.0
	## Progress through the swing, 0..1. Meaningless while planted.
	var swing_t: float = 0.0
	## Longitudinal offset of the ANKLE from the neutral spot, metres. Positive
	## is FORWARD along travel.
	var along: float = 0.0
	## Longitudinal offset of the foot's ANCHOR — where the ankle would be if
	## the foot were flat. This is the quantity that retreats perfectly linearly
	## during stance and therefore the one the world plant-lock holds; the ankle
	## itself is allowed to move off it as the foot rocks.
	var anchor_along: float = 0.0
	## Clearance above the plant height, metres. Zero through the whole stance.
	var lift: float = 0.0
	## Ankle pitch, radians. Positive is toes-up (heel-strike, swing clearance).
	var roll: float = 0.0
	## How planted the foot is, 0..1, ramped at the stance edges. Drives how
	## strongly foot IK pins this foot to the ground.
	var contact: float = 1.0
	## How FLAT the foot is on the ground, 0..1 — full only through the middle
	## of the stance. The world plant-lock uses this rather than `contact`,
	## because during the heel and toe pivots the ankle is supposed to travel.
	var flat: float = 1.0


## Whole-body oscillation for one frame, in metres and radians.
class BodyPhase:
	extends RefCounted

	## Vertical pelvis offset, metres. Positive is up.
	var bob: float = 0.0
	## Lateral pelvis offset, metres. Positive is the creature's right.
	var sway: float = 0.0
	## Transverse pelvic rotation, radians.
	var pelvis_yaw: float = 0.0
	## Frontal-plane pelvic roll, radians.
	var pelvis_roll: float = 0.0
	## Shoulder-girdle counter-rotation, radians — already lagged behind the
	## pelvis by the profile's `spine_lag`.
	var chest_yaw: float = 0.0
	## Shoulder-girdle roll, radians.
	var chest_roll: float = 0.0
	## Residual head pitch, radians.
	var head_pitch: float = 0.0


## Position in the cycle, 0..1. Persisted across frames; this is the only
## integrator state the gait has.
var phase: float = 0.0

## Cycles per second, derived last frame. Exposed for footstep audio and for
## the locomotion lab's cadence check.
var cadence: float = 0.0

## Height of the ankle joint above the sole, metres. Set once from the measured
## rig; the rocker geometry needs it because the foot rotates about a point on
## the GROUND, not about the ankle.
var _ankle_height: float = 0.115


## Tell the engine how high the ankle joint rides above the sole. Called once
## when the creature's `LocomotionProfile` is measured.
func set_ankle_height(height: float) -> void:
	_ankle_height = maxf(0.01, height)

## Stance flags from the previous frame, used to fire `just_planted`.
var _was_stance: Array[bool] = [true, true]
var _planted_this_frame: Array[bool] = [false, false]


## Advance the cycle by the ground distance covered this frame.
##
## `signed_distance` is metres travelled ALONG the facing direction — negative
## when backing up, which plays the cycle in reverse so a backpedal reads as a
## backpedal rather than a forward walk sliding backwards.
func advance(signed_distance: float, profile: GaitProfile, delta: float) -> void:
	var stride: float = maxf(profile.stride, MIN_STRIDE)
	var cycles: float = signed_distance / stride
	phase = fposmod(phase + cycles, 1.0)
	cadence = cycles / maxf(delta, 0.00001)
	for i in 2:
		var now_stance: bool = _stance_at(_foot_cycle(i), profile)
		_planted_this_frame[i] = now_stance and not _was_stance[i]
		_was_stance[i] = now_stance


## True on the single frame foot `index` (0 left, 1 right) touched down.
## Footstep audio, dust puffs and grass rustle hang off this.
func just_planted(index: int) -> bool:
	return _planted_this_frame[index]


## Reset to a clean standing phase — call on spawn, teleport and respawn so a
## creature does not resume mid-stride somewhere else in the world.
func reset() -> void:
	phase = 0.0
	cadence = 0.0
	_was_stance = [true, true]
	_planted_this_frame = [false, false]


## This foot's own position in the cycle. The right foot trails the left by
## half a cycle — that offset IS the alternation.
func _foot_cycle(index: int) -> float:
	return fposmod(phase + (0.5 if index == 1 else 0.0), 1.0)


func _stance_at(cycle: float, profile: GaitProfile) -> bool:
	return cycle < clampf(profile.duty, 0.05, 0.95)


## Full state for foot `index` (0 left, 1 right) under `profile`.
func foot_phase(index: int, profile: GaitProfile) -> FootPhase:
	var out: FootPhase = FootPhase.new()
	var duty: float = clampf(profile.duty, 0.05, 0.95)
	var cycle: float = _foot_cycle(index)
	out.cycle = cycle

	# Half the ground a single stance covers. The foot travels from +amplitude
	# (just landed, out front) to -amplitude (about to leave, trailing behind),
	# and the total 2*amplitude equals exactly the distance the body advances
	# during that stance — which is why the foot holds still in world space.
	var amplitude: float = profile.stride * duty * 0.5

	if cycle < duty:
		out.stance = true
		out.stance_t = cycle / duty
		# The ANCHOR retreats perfectly linearly: the body advances linearly
		# through the stance, so this one line is the no-sliding guarantee.
		# Do not ease it.
		out.anchor_along = amplitude - 2.0 * amplitude * out.stance_t
		out.roll = _stance_roll(out.stance_t, profile.foot_roll)
		# The ankle then rides off the anchor exactly as far as rocking the
		# rigid foot about its planted end demands.
		var rocker: Vector2 = _rocker_offset(out.stance_t, out.roll, profile)
		out.along = out.anchor_along + rocker.x
		out.lift = rocker.y
		out.contact = 1.0
		out.flat = _flat_weight(out.stance_t)
	else:
		out.stance = false
		out.flat = 0.0
		out.swing_t = (cycle - duty) / (1.0 - duty)
		# The swing eases: the foot unloads, accelerates past the body, then
		# decelerates into the landing. Smootherstep's zero acceleration at both
		# ends is what keeps toe-off and heel-strike from twitching.
		var eased: float = AM.smootherstep01(out.swing_t)
		# A touch of reach past the landing spot, pulled back before contact.
		var reach: float = profile.step_overshoot * amplitude \
			* sin(clampf(out.swing_t, 0.0, 1.0) * PI) \
			* AM.smoothstep01(out.swing_t * 2.0)
		# Start the swing exactly where the toe-off rocker left the ankle and
		# finish exactly where the heel-strike rocker wants it. Interpolating
		# between bare anchor positions instead leaves a ~4 cm jump at both ends
		# of every swing, which reads as the foot flicking.
		var leave: Vector2 = _rocker_offset(1.0, -profile.foot_roll * 0.85,
			profile)
		var land: Vector2 = _rocker_offset(0.0, profile.foot_roll, profile)
		out.along = lerpf(-amplitude + leave.x, amplitude + land.x, eased) \
			+ reach
		out.lift = lerpf(leave.y, land.y, eased) + profile.step_height \
			* AM.skewed_bell01(out.swing_t, profile.step_peak)
		out.roll = _swing_roll(out.swing_t, profile.foot_roll)
		out.contact = 0.0
		# In swing there is no planted anchor, so the probe simply follows the
		# foot — that is what makes it find the next stair tread rather than
		# the ground under the body.
		out.anchor_along = out.along

	out.contact = _contact_weight(cycle, duty)
	return out


## Where the ankle sits relative to the foot's flat anchor, as (forward, up) in
## metres, given how far through the stance we are and the current ankle roll.
##
## This is exact rigid-body geometry, not an approximation. The foot is a rigid
## lever of known length; while the toes are up it is rotating about the heel,
## while the heel is up it is rotating about the toe, and in between it is flat.
## Rotating the ankle about whichever end is planted gives the ankle's
## displacement in closed form — so the planted end does not move by so much as
## a millimetre, at any speed, on any slope, for any roll amplitude.
##
## Getting this from geometry rather than from a tuned ratio is what took foot
## slip from "small on average" to "zero by construction": a fudge factor and
## the ankle-roll curve animated on top of it are two different descriptions of
## the same foot, and they were quietly disagreeing every frame.
func _rocker_offset(t: float, roll: float, profile: GaitProfile) -> Vector2:
	if t >= FLAT_START and t <= FLAT_END:
		return Vector2.ZERO
	var sin_r: float = sin(roll)
	var cos_r: float = cos(roll)
	if t < FLAT_START:
		# Rocking over the heel, which sits `heel_lever` BEHIND the ankle and
		# `ankle_rest` below it. Displacement is where the ankle ends up after
		# rotating about that fixed point, minus where it sits when flat.
		var lever: float = profile.heel_lever
		return Vector2(
			lever * cos_r - _ankle_height * sin_r - lever,
			lever * sin_r + _ankle_height * cos_r - _ankle_height)
	# Rocking over the toe, `toe_lever` AHEAD of the ankle.
	var toe: float = profile.toe_lever
	return Vector2(
		-toe * cos_r - _ankle_height * sin_r + toe,
		-toe * sin_r + _ankle_height * cos_r - _ankle_height)


## 1 through the flat middle of the stance, easing to 0 across both pivots.
func _flat_weight(t: float) -> float:
	if t < FLAT_START:
		return AM.smoothstep01(t / FLAT_START)
	if t > FLAT_END:
		return AM.smoothstep01((1.0 - t) / maxf(1.0 - FLAT_END, 0.0001))
	return 1.0


## Ankle pitch through the stance: lands toes-up on the heel, rolls flat under
## bodyweight, then drives toes-down through toe-off.
##
## The flat window here is exactly `FLAT_START..FLAT_END`, the same window the
## plant-lock uses. Keeping them aligned is not cosmetic: if the foot is still
## pitched while the lock says "flat", the lock pins a foot that is physically
## mid-pivot and the ankle drags; if it goes flat early, the foot skates before
## the lock engages.
func _stance_roll(t: float, range_rad: float) -> float:
	if t < FLAT_START:
		return range_rad * (1.0 - AM.smoothstep01(t / FLAT_START))
	if t <= FLAT_END:
		return 0.0
	var push: float = AM.smoothstep01((t - FLAT_END) / maxf(1.0 - FLAT_END, 0.0001))
	return -range_rad * 0.85 * push


## Ankle pitch through the swing: stays toes-down out of toe-off, dorsiflexes
## to clear the ground, then presents the heel for the next strike.
func _swing_roll(t: float, range_rad: float) -> float:
	var clear: float = AM.bell01(clampf(t / 0.7, 0.0, 1.0)) * range_rad * 0.55
	var present: float = AM.smoothstep01(AM.remap01(t, 0.6, 1.0)) * range_rad
	var leaving: float = -range_rad * 0.85 * (1.0 - AM.smoothstep01(t / 0.25))
	return leaving + clear + present


## Ramp the contact weight in and out at the stance edges so foot IK engages
## and releases smoothly instead of snapping the leg on the plant frame.
func _contact_weight(cycle: float, duty: float) -> float:
	var blend: float = minf(CONTACT_BLEND, duty * 0.45)
	if cycle >= duty:
		# In swing — but ramp back up as we approach the next heel-strike.
		var to_landing: float = 1.0 - cycle
		return AM.smoothstep01(1.0 - to_landing / maxf(blend, 0.0001)) \
			if to_landing < blend else 0.0
	if cycle < blend:
		return AM.smoothstep01(cycle / blend)
	if cycle > duty - blend:
		return AM.smoothstep01((duty - cycle) / blend)
	return 1.0


## Whole-body oscillation for this frame.
func body_phase(profile: GaitProfile) -> BodyPhase:
	var out: BodyPhase = BodyPhase.new()
	var turns: float = phase * TAU

	# Bob runs at TWICE the cycle rate — the body rises and falls once per step,
	# not once per stride. `pelvis_bob_phase` flips it between the walk's vault
	# (highest at midstance) and the run's compression (lowest at midstance).
	out.bob = profile.pelvis_bob \
		* cos(2.0 * (turns - profile.pelvis_bob_phase * TAU))

	# Sway, pelvic yaw and roll all run at the CYCLE rate — one full left-right
	# excursion per stride, weight shifting onto each foot in turn.
	out.sway = profile.pelvis_sway * sin(turns)
	out.pelvis_yaw = profile.pelvis_yaw * sin(turns)
	out.pelvis_roll = profile.pelvis_roll * sin(turns)

	# The shoulder girdle counter-rotates AND lags: the spine is elastic, so
	# the chest arrives after the pelvis. Matching phases would make the torso
	# read as one rigid block, which is the classic amateur-rig look.
	var lagged: float = turns - profile.spine_lag * TAU
	out.chest_yaw = -profile.chest_counter * sin(lagged)
	out.chest_roll = -profile.pelvis_roll * 0.35 * sin(lagged)
	out.head_pitch = profile.head_bob * cos(2.0 * turns)
	return out


## Neutral standing width for foot `index`, as a signed lateral offset in
## metres given the creature's hip half-width. Feet track slightly inboard of
## the hips, which is how humans actually stand and walk.
static func stance_lateral(index: int, hip_half_width: float) -> float:
	var side: float = -1.0 if index == 0 else 1.0
	return side * hip_half_width * 0.82

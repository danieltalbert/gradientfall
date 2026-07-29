class_name AnimMath
extends RefCounted
## Frame-rate-independent smoothing, spring integrators and easing curves shared
## by every creature animator in Gradientfall.
##
## **Why this module exists.** `lerp(a, b, rate * delta)` — the idiom the old
## Kern animation used throughout — is frame-rate dependent: a 30 fps machine
## and a 144 fps machine close the gap at different real-world speeds, so the
## same character reads "floaty" on one and "snappy" on another. Every routine
## here is instead expressed as a HALF-LIFE (seconds to close half the remaining
## gap) and integrated exactly, so the motion is identical at any timestep.
##
## **Architecture.** Leaf utility module — depends on nothing, allocates nothing
## in its static functions (they run per-bone, per-frame). Imported by
## `gait_engine.gd`, `foot_planter.gd`, `emote_player.gd` and
## `creature_animator.gd`. See `docs/ARCHITECTURE.md` § "Procedural animation".

## ln(2), the constant that turns a half-life into an exponential rate.
const LN2: float = 0.6931471805599453

## Half-lives below this are treated as "snap instantly" — guards the division
## in every damp routine against a zero/negative half-life.
const MIN_HALF_LIFE: float = 0.00001


# --- Exponential damping (frame-rate independent) ---------------------------

## Ease `current` toward `target`, closing half the remaining gap every
## `half_life` seconds. Exact at any `delta`: the closed-form solution of
## dx/dt = -k(x - target), so 4 small steps land exactly where 1 big step does.
static func damp(current: float, target: float, half_life: float,
		delta: float) -> float:
	if half_life <= MIN_HALF_LIFE:
		return target
	return target + (current - target) * exp(-LN2 * delta / half_life)


## Vector3 form of `damp` — each axis converges independently.
static func damp_vec3(current: Vector3, target: Vector3, half_life: float,
		delta: float) -> Vector3:
	if half_life <= MIN_HALF_LIFE:
		return target
	var k: float = exp(-LN2 * delta / half_life)
	return target + (current - target) * k


## Vector2 form of `damp`.
static func damp_vec2(current: Vector2, target: Vector2, half_life: float,
		delta: float) -> Vector2:
	if half_life <= MIN_HALF_LIFE:
		return target
	var k: float = exp(-LN2 * delta / half_life)
	return target + (current - target) * k


## Angular form of `damp` — takes the short way around the circle, so a
## character turning past ±PI never spins the long way to get back.
static func damp_angle(current: float, target: float, half_life: float,
		delta: float) -> float:
	if half_life <= MIN_HALF_LIFE:
		return target
	var difference: float = wrapf(target - current, -PI, PI)
	return current + difference * (1.0 - exp(-LN2 * delta / half_life))


## Quaternion form of `damp`, along the shortest arc. Used for bone rotations
## where euler damping would gimbal or take a visibly wrong path.
static func damp_quat(current: Quaternion, target: Quaternion,
		half_life: float, delta: float) -> Quaternion:
	if half_life <= MIN_HALF_LIFE:
		return target
	var weight: float = 1.0 - exp(-LN2 * delta / half_life)
	return current.slerp(_shortest(current, target), weight)


## Flip `to` into the same hemisphere as `from` so slerp takes the short arc.
## Without this a quaternion and its negation — the same rotation — interpolate
## the long way round, which reads as a limb swinging through the body.
static func _shortest(from: Quaternion, to: Quaternion) -> Quaternion:
	if from.dot(to) < 0.0:
		return -to
	return to


# --- Easing ------------------------------------------------------------------

## Hermite smoothstep on an already-normalised 0..1 input. Zero first
## derivative at both ends — the workhorse for blending pose layers in and out.
static func smoothstep01(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Perlin's smootherstep: zero FIRST AND SECOND derivative at both ends. Used
## for the foot swing arc, where a smoothstep's non-zero acceleration at
## lift-off still reads as a mechanical twitch.
static func smootherstep01(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## A 0 -> 1 -> 0 bell over t in 0..1, flat at both ends. The foot-lift and
## breath curves ride on this.
static func bell01(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return 0.5 - 0.5 * cos(x * TAU)


## Bell with an adjustable peak position: `peak` in 0..1 says where the maximum
## lands. Real foot lift peaks EARLY in the swing (toe-off is explosive, the
## reach to heel-strike is a long glide), which a symmetric bell can't express.
static func skewed_bell01(t: float, peak: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	var p: float = clampf(peak, 0.02, 0.98)
	if x < p:
		return bell01(0.5 * x / p)
	return bell01(0.5 + 0.5 * (x - p) / (1.0 - p))


## Signed power curve that keeps the sign of `v` — sharpens or softens a
## -1..1 oscillation without breaking its symmetry. `power` > 1 flattens the
## middle (a snappier, more "held" extreme), < 1 rounds it.
static func signed_pow(v: float, power: float) -> float:
	return signf(v) * pow(absf(v), power)


## Remap `v` from [from_min, from_max] onto [to_min, to_max], clamped. The
## gait code uses this constantly to turn a speed into a blend weight.
static func remap01(v: float, from_min: float, from_max: float) -> float:
	if absf(from_max - from_min) < 0.000001:
		return 0.0
	return clampf((v - from_min) / (from_max - from_min), 0.0, 1.0)


# --- Springs -----------------------------------------------------------------

## A critically-damped spring in one dimension, integrated exactly.
##
## Unlike `damp`, a spring carries VELOCITY, so it overshoots-and-settles the
## way real mass on a tendon does. That is what makes an arm swing feel like an
## arm and not like a value being interpolated. Critically damped (no
## oscillation) is the default because oscillating limbs read as rubber; the
## `stiffness_scale` lets a caller trade settle time for looseness.
class Spring1:
	extends RefCounted

	## Current value.
	var value: float = 0.0
	## Current rate of change, in units/second. Carried across frames — this is
	## the whole point of a spring over a damp.
	var velocity: float = 0.0
	## Seconds to close half the gap. Smaller = stiffer.
	var half_life: float = 0.08

	## Local copies of the outer constants — an inner class cannot reliably
	## reach its own file's `class_name` during parse, and duplicating two
	## numbers is cheaper than a resolution order that breaks on a cold import.
	const EPSILON: float = 0.00001
	const LN2: float = 0.6931471805599453

	func _init(initial: float = 0.0, initial_half_life: float = 0.08) -> void:
		value = initial
		half_life = initial_half_life

	## Advance toward `target` by `delta` seconds and return the new value.
	## Exact integration of a critically-damped second-order system (the
	## standard "spring_damper_exact" formulation).
	func step(target: float, delta: float) -> float:
		if half_life <= EPSILON:
			value = target
			velocity = 0.0
			return value
		# Convert half-life to the critical-damping eigenvalue. The 2x is
		# because a critically-damped system has a repeated root, so its
		# envelope decays as (1 + y*t)*exp(-y*t), not plain exp(-y*t).
		var y: float = 2.0 * LN2 / half_life
		var offset: float = value - target
		var combined: float = velocity + offset * y
		var decay: float = exp(-y * delta)
		value = target + decay * (offset + combined * delta)
		velocity = decay * (velocity - combined * y * delta)
		return value

	## Jump to a value with no motion — use on teleports/respawns so the spring
	## does not fling the limb across the world catching up.
	func reset(to_value: float) -> void:
		value = to_value
		velocity = 0.0


## Three-dimensional critically-damped spring. Same integrator as `Spring1`,
## run per axis. Used for the pelvis offset, cloak swing and head lag.
class Spring3:
	extends RefCounted

	## Current value.
	var value: Vector3 = Vector3.ZERO
	## Current rate of change, in units/second.
	var velocity: Vector3 = Vector3.ZERO
	## Seconds to close half the gap. Smaller = stiffer.
	var half_life: float = 0.08

	## See the note on `Spring1` — inner classes keep their own copies.
	const EPSILON: float = 0.00001
	const LN2: float = 0.6931471805599453

	func _init(initial: Vector3 = Vector3.ZERO,
			initial_half_life: float = 0.08) -> void:
		value = initial
		half_life = initial_half_life

	## Advance toward `target` by `delta` seconds and return the new value.
	func step(target: Vector3, delta: float) -> Vector3:
		if half_life <= EPSILON:
			value = target
			velocity = Vector3.ZERO
			return value
		var y: float = 2.0 * LN2 / half_life
		var offset: Vector3 = value - target
		var combined: Vector3 = velocity + offset * y
		var decay: float = exp(-y * delta)
		value = target + decay * (offset + combined * delta)
		velocity = decay * (velocity - combined * y * delta)
		return value

	## Jump to a value with no motion.
	func reset(to_value: Vector3) -> void:
		value = to_value
		velocity = Vector3.ZERO

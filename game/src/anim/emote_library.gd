class_name EmoteLibrary
extends RefCounted
## Every emote and dance in Gradientfall, authored procedurally as functions of
## time rather than as keyframed clips.
##
## **Why procedural.** The project generates all assets in code (CLAUDE.md
## § Conventions), so there is no animation-import path to hang a dance on. It
## turns out to be the better fit anyway: a dance is mostly oscillators —
## phase-shifted limbs, held beats, body rolls — and writing `sin(beat * TAU)`
## is both shorter and more editable than baking sixty keyframes of the same
## curve. Emotes also inherit the rig's units, so re-proportioning the body
## does not desynchronise them.
##
## **Canon.** The dances are named out of the world's own vocabulary — a
## gradient descent, a dropout, an overfit — rather than borrowed from
## elsewhere. They read as Gradientfall's, and the joke lands for the audience
## the game is actually about.
##
## **Rotation conventions on this rig** (verified against
## `kern_body_builder.gd`'s rest skeleton, where every limb bone hangs DOWN and
## the spine chain points UP):
##   * UpperArm/Thigh +X  -> swings the limb FORWARD (flexion).
##   * Forearm +X         -> elbow flexion (hand comes up and forward).
##   * Shin -X            -> knee flexion. POSITIVE X hyperextends the knee,
##                           which is how the placeholder gait ended up bending
##                           Kern's knees backwards; `_leg()` takes flexion as a
##                           positive number and applies the sign itself so no
##                           emote can repeat that mistake.
##   * Spine/Chest/Neck -X -> leans/looks FORWARD (the chain points up, so the
##                           sign is inverted from the limbs).
##   * Abduction (limb out to the side) is +Z on the right, -Z on the left;
##     `_arm()`/`_leg()` take a side flag and handle the mirroring.
##
## **Architecture.** Pure functions plus a metadata table; depends on
## `anim_math.gd` and `pose_stack.gd`. Driven by `emote_player.gd`, which owns
## timing and blending. See `docs/ARCHITECTURE.md` § "Procedural animation".

const AM: GDScript = preload("res://src/anim/anim_math.gd")


## Metadata for one emote. The pose itself lives in `evaluate()`.
class EmoteDef:
	extends RefCounted

	## Stable id, used by input bindings, saves and the emote wheel.
	var id: String = ""
	## Name shown in the emote wheel.
	var display_name: String = ""
	## Seconds for one pass. For looping emotes this is the loop length.
	var duration: float = 2.0
	## Whether the emote repeats until cancelled.
	var loops: bool = false
	## Seconds to ease in and out. Long enough to read as a transition, short
	## enough that the emote still feels responsive to the button.
	var blend_in: float = 0.22
	var blend_out: float = 0.28
	## True if the emote poses the legs, in which case the animator hands the
	## legs over and stops planting the feet with IK.
	var overrides_legs: bool = true
	## True if the player is pinned in place while it plays.
	var locks_movement: bool = true
	## Category, for grouping in the wheel: "dance" or "gesture".
	var category: String = "gesture"


## Ordered emote table. Order is the emote wheel's order.
static func defs() -> Array:
	var out: Array = []
	out.append(_def("wave", "Wave", 2.2, false, "gesture", false, false))
	out.append(_def("cheer", "Cheer", 2.0, false, "gesture", true, true))
	out.append(_def("bow", "Bow", 2.6, false, "gesture", true, true))
	out.append(_def("point", "Point", 1.8, false, "gesture", false, false))
	out.append(_def("salute", "Salute", 1.9, false, "gesture", false, false))
	out.append(_def("think", "Ponder", 3.4, true, "gesture", false, true))
	out.append(_def("stretch", "Stretch", 3.2, false, "gesture", true, true))
	out.append(_def("sit", "Sit", 2.8, true, "gesture", true, true))
	out.append(_def("gradient_descent", "Gradient Descent", 2.4, true, "dance", true, true))
	out.append(_def("backprop", "The Backprop", 1.6, true, "dance", true, true))
	out.append(_def("overfit", "Overfit", 2.0, true, "dance", true, true))
	out.append(_def("dropout", "Dropout", 2.4, true, "dance", true, true))
	out.append(_def("convergence", "Convergence", 3.0, true, "dance", true, true))
	out.append(_def("weight_shuffle", "Weight Shuffle", 1.4, true, "dance", true, true))
	out.append(_def("epoch_step", "Epoch Step", 2.0, true, "dance", true, true))
	out.append(_def("softmax", "Softmax", 2.8, true, "dance", true, true))
	return out


static func _def(id: String, display_name: String, duration: float,
		loops: bool, category: String, overrides_legs: bool,
		locks_movement: bool) -> EmoteDef:
	var d: EmoteDef = EmoteDef.new()
	d.id = id
	d.display_name = display_name
	d.duration = duration
	d.loops = loops
	d.category = category
	d.overrides_legs = overrides_legs
	d.locks_movement = locks_movement
	return d


## Look one up by id, or null.
static func find(id: String) -> EmoteDef:
	for entry in defs():
		var d: EmoteDef = entry
		if d.id == id:
			return d
	return null


## Write emote `id` into `pose`.
##
## `t` is seconds since the emote started; `beat` is the normalised position in
## the current pass, 0..1 (wrapping for looping emotes). Splitting the two lets
## an emote use `beat` for its cyclic content and `t` for one-shot ramps.
static func evaluate(id: String, pose: PoseStack, t: float,
		beat: float) -> void:
	match id:
		"wave": _wave(pose, beat)
		"cheer": _cheer(pose, beat)
		"bow": _bow(pose, beat)
		"point": _point(pose, beat)
		"salute": _salute(pose, beat)
		"think": _think(pose, beat)
		"stretch": _stretch(pose, beat)
		"sit": _sit(pose, t, beat)
		"gradient_descent": _gradient_descent(pose, beat)
		"backprop": _backprop(pose, beat)
		"overfit": _overfit(pose, beat)
		"dropout": _dropout(pose, beat)
		"convergence": _convergence(pose, t, beat)
		"weight_shuffle": _weight_shuffle(pose, beat)
		"epoch_step": _epoch_step(pose, beat)
		"softmax": _softmax(pose, beat)
		_: pass


# --- Pose helpers ------------------------------------------------------------

## Pose one arm. `pitch` is forward flexion, `abduct` lifts the arm away from
## the body (sign handled per side), `twist` rotates about the bone, `elbow` is
## flexion. Radians throughout.
static func _arm(pose: PoseStack, right: bool, pitch: float, abduct: float,
		twist: float, elbow: float) -> void:
	var side: float = 1.0 if right else -1.0
	var suffix: String = "R" if right else "L"
	pose.set_euler("UpperArm" + suffix,
		Vector3(pitch, twist * side, abduct * side))
	pose.set_euler("Forearm" + suffix, Vector3(elbow, 0.0, 0.0))


## Pose one leg. `hip_pitch` swings the thigh forward, `abduct` opens the leg
## outward, `knee` is FLEXION as a positive number (the negation that a real
## knee needs is applied here, once, so callers cannot get it backwards).
static func _leg(pose: PoseStack, right: bool, hip_pitch: float,
		abduct: float, knee: float, ankle: float = 0.0) -> void:
	var side: float = 1.0 if right else -1.0
	var suffix: String = "R" if right else "L"
	pose.set_euler("Thigh" + suffix, Vector3(hip_pitch, 0.0, abduct * side))
	pose.set_euler("Shin" + suffix, Vector3(-absf(knee), 0.0, 0.0))
	pose.set_euler("Foot" + suffix, Vector3(ankle, 0.0, 0.0))


## Pose the spine chain. All three take FORWARD lean as a positive number and
## invert internally, because the spine bones point up.
static func _torso(pose: PoseStack, lean: float, twist: float,
		roll: float) -> void:
	pose.set_euler("Hips", Vector3(-lean * 0.25, twist * 0.45, roll * 0.5))
	pose.set_euler("Spine", Vector3(-lean * 0.35, twist * 0.25, roll * 0.3))
	pose.set_euler("Chest", Vector3(-lean * 0.40, twist * 0.30, roll * 0.2))


## Pose the head. `pitch` positive looks DOWN.
static func _head(pose: PoseStack, pitch: float, yaw: float,
		tilt: float) -> void:
	pose.set_euler("Neck", Vector3(-pitch * 0.5, yaw * 0.5, tilt * 0.5))
	pose.set_euler("Head", Vector3(-pitch * 0.5, yaw * 0.5, tilt * 0.5))


## Square wave with softened edges — the "held then snapped" timing that makes
## robotic and hip-hop styled dances read as choreography rather than as a sine.
static func _snap(beat: float, sharpness: float = 8.0) -> float:
	return tanh(sin(beat * TAU) * sharpness)


# --- Gestures ----------------------------------------------------------------

## An open-handed wave: arm up and out, forearm oscillating from the elbow.
static func _wave(pose: PoseStack, beat: float) -> void:
	var raise: float = AM.bell01(clampf(beat * 1.15, 0.0, 1.0))
	var flap: float = sin(beat * TAU * 3.0)
	_arm(pose, true, -0.35 * raise, 1.15 * raise, 0.0,
		(0.95 + 0.30 * flap) * raise)
	_arm(pose, false, 0.0, 0.10, 0.0, 0.22)
	_torso(pose, 0.02, -0.06 * raise, 0.0)
	_head(pose, -0.05 * raise, 0.10 * raise, 0.06 * flap * raise)


## Both arms thrown up, with a small hop's worth of body rise.
static func _cheer(pose: PoseStack, beat: float) -> void:
	var up: float = AM.bell01(clampf(beat * 1.2, 0.0, 1.0))
	var pump: float = sin(beat * TAU * 2.0) * up
	_arm(pose, true, -1.95 * up - 0.15 * pump, 0.42 * up, 0.0, 0.30 * up)
	_arm(pose, false, -1.95 * up + 0.15 * pump, 0.42 * up, 0.0, 0.30 * up)
	_leg(pose, true, 0.05 * up, 0.03, 0.16 * up)
	_leg(pose, false, 0.05 * up, 0.03, 0.16 * up)
	_torso(pose, -0.18 * up, 0.0, 0.0)
	_head(pose, -0.22 * up, 0.0, 0.0)
	pose.root_offset = Vector3(0.0, 0.06 * up, 0.0)


## A formal bow from the waist, one arm across the chest.
static func _bow(pose: PoseStack, beat: float) -> void:
	var depth: float = AM.bell01(clampf(beat * 1.1, 0.0, 1.0))
	_torso(pose, 1.05 * depth, 0.0, 0.0)
	_head(pose, 0.35 * depth, 0.0, 0.0)
	_arm(pose, true, -0.45 * depth, -0.25 * depth, 0.0, 1.35 * depth)
	_arm(pose, false, 0.30 * depth, 0.30 * depth, 0.0, 0.18)
	_leg(pose, true, 0.0, 0.02, 0.06 * depth)
	_leg(pose, false, -0.10 * depth, 0.05, 0.10 * depth)
	pose.root_offset = Vector3(0.0, -0.05 * depth, 0.0)


## Point straight ahead, weight shifting onto the front foot.
static func _point(pose: PoseStack, beat: float) -> void:
	var out: float = AM.bell01(clampf(beat * 1.25, 0.0, 1.0))
	_arm(pose, true, -1.48 * out, 0.10 * out, 0.0, 0.08 * out)
	_arm(pose, false, 0.05, 0.08, 0.0, 0.24)
	_torso(pose, 0.06 * out, -0.16 * out, 0.0)
	_head(pose, -0.02 * out, 0.06 * out, 0.0)
	pose.root_offset = Vector3(0.0, 0.0, -0.04 * out)


## Crisp salute — hand to brow, held, released.
static func _salute(pose: PoseStack, beat: float) -> void:
	var up: float = AM.smoothstep01(clampf(beat * 4.0, 0.0, 1.0)) \
		* (1.0 - AM.smoothstep01(AM.remap01(beat, 0.78, 1.0)))
	_arm(pose, true, -0.55 * up, 0.62 * up, 0.0, 2.05 * up)
	_arm(pose, false, 0.0, 0.05, 0.0, 0.18)
	_leg(pose, true, 0.0, 0.0, 0.04)
	_leg(pose, false, 0.0, 0.0, 0.04)
	_torso(pose, -0.06 * up, 0.0, 0.0)
	_head(pose, -0.06 * up, 0.0, 0.0)


## Hand to chin, weight on one hip, slow head drift. Loops.
static func _think(pose: PoseStack, beat: float) -> void:
	var drift: float = sin(beat * TAU)
	_arm(pose, true, -0.62, 0.18, 0.0, 2.15 + 0.06 * drift)
	_arm(pose, false, 0.10, 0.02, 0.0, 0.85)
	_torso(pose, 0.10, 0.05 * drift, 0.10)
	_head(pose, 0.10 + 0.05 * drift, 0.12 * drift, 0.10)
	_leg(pose, true, -0.04, 0.03, 0.10)
	_leg(pose, false, 0.02, 0.06, 0.22)
	pose.root_offset = Vector3(0.03, -0.02, 0.0)


## An overhead stretch with a yawning arch, then release.
static func _stretch(pose: PoseStack, beat: float) -> void:
	var arch: float = AM.bell01(clampf(beat * 1.1, 0.0, 1.0))
	var twist: float = sin(beat * TAU) * 0.12
	_arm(pose, true, -2.25 * arch, 0.30 * arch, 0.0, 0.35 * arch)
	_arm(pose, false, -2.25 * arch, 0.30 * arch, 0.0, 0.35 * arch)
	_torso(pose, -0.30 * arch, twist, 0.0)
	_head(pose, -0.28 * arch, twist * 0.5, 0.0)
	_leg(pose, true, 0.0, 0.04, 0.05)
	_leg(pose, false, 0.0, 0.04, 0.05)
	pose.root_offset = Vector3(0.0, 0.045 * arch, 0.0)


## Sit cross-legged on the ground, with a slow breathing sway. Loops; `t`
## drives the one-time descent so the loop does not re-play it.
static func _sit(pose: PoseStack, t: float, beat: float) -> void:
	var down: float = AM.smoothstep01(clampf(t / 0.8, 0.0, 1.0))
	var sway: float = sin(beat * TAU) * 0.03
	_leg(pose, true, 1.15 * down, 0.55 * down, 2.15 * down)
	_leg(pose, false, 1.15 * down, 0.55 * down, 2.15 * down)
	_arm(pose, true, 0.30 * down, 0.16 * down, 0.0, 0.70 * down)
	_arm(pose, false, 0.30 * down, 0.16 * down, 0.0, 0.70 * down)
	_torso(pose, (0.16 + sway) * down, 0.0, 0.0)
	_head(pose, (0.06 + sway) * down, sway * 2.0, 0.0)
	# Drop to the floor: the hips end up roughly a knee-height below standing.
	pose.root_offset = Vector3(0.0, -0.62 * down, 0.0)


# --- Dances ------------------------------------------------------------------

## **Gradient Descent** — a staircase shuffle that steps the body down in
## discrete drops and springs back to the top, the shape of the algorithm.
static func _gradient_descent(pose: PoseStack, beat: float) -> void:
	# Four descending steps, then a reset leap back to the start.
	var steps: float = 4.0
	var descending: float = clampf(beat / 0.82, 0.0, 1.0)
	var stair: float = floor(descending * steps) / steps
	var reset: float = AM.smoothstep01(AM.remap01(beat, 0.82, 1.0))
	var height: float = lerpf(-stair * 0.20, 0.0, reset)
	var step_beat: float = fposmod(descending * steps, 1.0)
	var lead: float = sin(step_beat * TAU)

	_leg(pose, true, 0.22 * lead, 0.06, 0.30 + 0.28 * maxf(0.0, lead))
	_leg(pose, false, -0.22 * lead, 0.06, 0.30 + 0.28 * maxf(0.0, -lead))
	# Arms chop downward on each step, like marking off a descent.
	_arm(pose, true, -0.85 + 0.55 * lead, 0.30, 0.0, 1.25)
	_arm(pose, false, -0.85 - 0.55 * lead, 0.30, 0.0, 1.25)
	_torso(pose, 0.22 + 0.10 * reset, 0.10 * lead, 0.0)
	_head(pose, 0.12 - 0.30 * reset, 0.0, 0.0)
	pose.root_offset = Vector3(0.0, height + 0.06 * reset, 0.0)


## **The Backprop** — a running man travelling the wrong way, error signal
## chasing itself back through the layers.
static func _backprop(pose: PoseStack, beat: float) -> void:
	var drive: float = sin(beat * TAU)
	var opposite: float = sin(beat * TAU + PI)
	# One knee drives up while the other slides back — the running-man shape.
	_leg(pose, true, 0.85 * maxf(0.0, drive), 0.04,
		0.30 + 1.05 * maxf(0.0, drive), -0.25 * minf(0.0, drive))
	_leg(pose, false, 0.85 * maxf(0.0, opposite), 0.04,
		0.30 + 1.05 * maxf(0.0, opposite), -0.25 * minf(0.0, opposite))
	_arm(pose, true, 0.75 * opposite, 0.14, 0.0, 1.35)
	_arm(pose, false, 0.75 * drive, 0.14, 0.0, 1.35)
	_torso(pose, 0.16, -0.14 * drive, 0.0)
	_head(pose, 0.04, -0.10 * drive, 0.0)
	pose.root_offset = Vector3(0.0, 0.035 * absf(drive), 0.0)


## **Overfit** — the robot: every joint lands exactly on the beat and holds,
## fitting the training data far too precisely.
static func _overfit(pose: PoseStack, beat: float) -> void:
	# Quantise the beat to eighths and snap between them: the "too precise" read.
	var quantised: float = floor(beat * 8.0) / 8.0
	var snap: float = _snap(quantised, 12.0)
	var alt: float = _snap(quantised + 0.25, 12.0)
	_arm(pose, true, -1.55 - 0.65 * snap, 0.90 + 0.55 * alt, 0.0,
		1.70 + 0.60 * snap)
	_arm(pose, false, -1.55 + 0.65 * snap, 0.90 - 0.55 * alt, 0.0,
		1.70 - 0.60 * snap)
	_leg(pose, true, 0.10 + 0.10 * snap, 0.12 + 0.10 * snap, 0.30)
	_leg(pose, false, 0.10 - 0.10 * snap, 0.12 - 0.10 * snap, 0.30)
	_torso(pose, 0.10, 0.40 * alt, 0.24 * snap)
	_head(pose, 0.0, 0.50 * snap, 0.28 * alt)
	pose.root_offset = Vector3(0.05 * snap, 0.0, 0.0)


## **Dropout** — dancing full-out, then random limbs cut to zero for a beat and
## come back. The units keep dropping out.
static func _dropout(pose: PoseStack, beat: float) -> void:
	var swing: float = sin(beat * TAU * 2.0)
	var bounce: float = absf(sin(beat * TAU * 2.0))
	# Deterministic per-quarter-beat mask, so the "randomness" is identical on
	# every machine and every replay — a dance that desyncs is not a dance.
	var slot: int = int(beat * 8.0) % 8
	var arm_r: float = 0.0 if slot == 1 or slot == 5 else 1.0
	var arm_l: float = 0.0 if slot == 3 or slot == 6 else 1.0
	var leg_gate: float = 0.0 if slot == 7 else 1.0

	_arm(pose, true, (-1.75 + 1.15 * swing) * arm_r, 1.15 * arm_r, 0.0,
		1.35 * arm_r + 0.30)
	_arm(pose, false, (-1.75 - 1.15 * swing) * arm_l, 1.15 * arm_l, 0.0,
		1.35 * arm_l + 0.30)
	_leg(pose, true, 0.42 * swing * leg_gate, 0.16,
		0.35 + 0.80 * bounce * leg_gate)
	_leg(pose, false, -0.42 * swing * leg_gate, 0.16,
		0.35 + 0.80 * bounce * leg_gate)
	_torso(pose, 0.24, 0.46 * swing, 0.34 * swing)
	_head(pose, 0.12 - 0.30 * bounce, 0.38 * swing, 0.0)
	pose.root_offset = Vector3(0.0, -0.13 * bounce, 0.0)


## **Convergence** — a wide spin that decays into a still, centred pose, then
## opens out again. Slower and more graceful than the rest.
static func _convergence(pose: PoseStack, _t: float, beat: float) -> void:
	# Amplitude decays across the loop and re-expands at the end: the classic
	# damped-oscillation shape, danced.
	var envelope: float = exp(-3.2 * beat) + AM.smoothstep01(
		AM.remap01(beat, 0.85, 1.0))
	var swirl: float = sin(beat * TAU * 3.0) * envelope
	_arm(pose, true, -0.95 - 0.55 * swirl, 0.95 * envelope, 0.30 * swirl, 0.55)
	_arm(pose, false, -0.95 + 0.55 * swirl, 0.95 * envelope, -0.30 * swirl, 0.55)
	_leg(pose, true, 0.12 * swirl, 0.10 * envelope, 0.22 + 0.20 * envelope)
	_leg(pose, false, -0.12 * swirl, 0.10 * envelope, 0.22 + 0.20 * envelope)
	_torso(pose, 0.10, 0.30 * swirl, 0.18 * swirl)
	_head(pose, 0.0, 0.35 * swirl, 0.10 * swirl)
	# The whole body rotates, winding down toward a settled heading.
	pose.root_spin = swirl * 0.85
	pose.root_offset = Vector3(0.0, 0.03 * envelope * absf(swirl), 0.0)


## **Weight Shuffle** — hips hard one way, arms swinging hard the other, both
## arms sweeping across the body on every beat. The party dance of Bootstrap.
##
## Amplitudes here are deliberately LARGE. The first pass at these dances used
## the same restrained numbers as the locomotion layer — a fifth of a radian
## here and there — and the result read as a man shifting his weight
## uncomfortably rather than dancing. An emote is a performance: it has to be
## legible from across a field, at a glance, over a cloak.
static func _weight_shuffle(pose: PoseStack, beat: float) -> void:
	var hips: float = sin(beat * TAU)
	var arms: float = sin(beat * TAU + PI)
	var cross: float = absf(arms)
	var bounce: float = absf(sin(beat * TAU * 2.0))
	_arm(pose, true, -1.15 + 0.85 * arms, 1.20 - 1.05 * cross, 0.0,
		0.70 + 1.35 * cross)
	_arm(pose, false, -1.15 - 0.85 * arms, 1.20 - 1.05 * cross, 0.0,
		0.70 + 1.35 * cross)
	_leg(pose, true, 0.34 * hips, 0.16, 0.42 + 0.46 * maxf(0.0, hips))
	_leg(pose, false, -0.34 * hips, 0.16, 0.42 + 0.46 * maxf(0.0, -hips))
	_torso(pose, 0.20, -0.62 * hips, 0.48 * hips)
	_head(pose, 0.06, -0.34 * hips, 0.26 * hips)
	pose.root_offset = Vector3(0.13 * hips, -0.10 * bounce, 0.0)


## **Epoch Step** — a two-step with a clap on the turn of each epoch.
static func _epoch_step(pose: PoseStack, beat: float) -> void:
	var step: float = sin(beat * TAU)
	# Clap lands on the half beat; hands come together sharply and part slowly.
	var clap_phase: float = fposmod(beat * 2.0, 1.0)
	var clap: float = 1.0 - AM.smoothstep01(clampf(clap_phase / 0.35, 0.0, 1.0))
	_arm(pose, true, -1.35, 1.05 - 0.92 * clap, 0.0, 1.45 + 0.40 * clap)
	_arm(pose, false, -1.35, 1.05 - 0.92 * clap, 0.0, 1.45 + 0.40 * clap)
	_leg(pose, true, 0.52 * step, 0.13, 0.32 + 0.62 * maxf(0.0, step))
	_leg(pose, false, -0.52 * step, 0.13, 0.32 + 0.62 * maxf(0.0, -step))
	_torso(pose, 0.18, 0.34 * step, 0.26 * step)
	_head(pose, -0.10, 0.26 * step, 0.0)
	pose.root_offset = Vector3(0.07 * step, 0.06 * clap, 0.0)


## **Softmax** — a smooth full-body wave travelling shoulder to shoulder, every
## joint sharing the motion rather than any one taking it all.
static func _softmax(pose: PoseStack, beat: float) -> void:
	# One travelling wave, each segment further down the chain lagging further.
	var wave: float = sin(beat * TAU)
	var lag1: float = sin(beat * TAU - 0.55)
	var lag2: float = sin(beat * TAU - 1.10)
	var lag3: float = sin(beat * TAU - 1.65)
	_arm(pose, true, -0.55 + 0.35 * wave, 1.05 + 0.25 * wave, 0.0,
		0.75 + 0.45 * lag1)
	_arm(pose, false, -0.55 - 0.35 * wave, 1.05 - 0.25 * wave, 0.0,
		0.75 + 0.45 * lag2)
	_leg(pose, true, 0.08 * lag3, 0.08, 0.28 + 0.14 * maxf(0.0, lag3))
	_leg(pose, false, -0.08 * lag3, 0.08, 0.28 + 0.14 * maxf(0.0, -lag3))
	pose.set_euler("Hips", Vector3(-0.06, 0.14 * wave, 0.16 * wave))
	pose.set_euler("Spine", Vector3(-0.10 * lag1, 0.10 * lag1, 0.12 * lag1))
	pose.set_euler("Chest", Vector3(-0.12 * lag2, 0.12 * lag2, 0.10 * lag2))
	_head(pose, 0.06 * lag3, 0.14 * lag3, 0.12 * lag3)
	pose.root_offset = Vector3(0.03 * wave, 0.02 * absf(lag2), 0.0)

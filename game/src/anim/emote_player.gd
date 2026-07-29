class_name EmotePlayer
extends RefCounted
## Timing and blending for emotes: which one is playing, how far through it is,
## and how strongly it currently overrides the creature's locomotion.
##
## **Separation of concerns.** `emote_library.gd` answers "what pose is this
## dance at beat 0.4"; this class answers "which dance, how long has it run, and
## how much of the body does it own right now". Keeping them apart means the
## library stays a table of pure functions — trivially testable and safe to hot-
## edit — while all the stateful awkwardness (blend ramps, one-shot completion,
## cancel-on-move) lives in exactly one place.
##
## **Blending out matters as much as blending in.** An emote that snaps off the
## instant the player touches a stick looks worse than one that never played.
## The player keeps evaluating a stopped emote at its final beat while the
## weight ramps down, so Kern eases back into his stride instead of teleporting
## into it.
##
## **Architecture.** Depends on `anim_math.gd`, `pose_stack.gd` and
## `emote_library.gd`; owns no nodes. Driven by `creature_animator.gd`, which
## composites `pose()` over the locomotion pose at `weight()`.

const AM: GDScript = preload("res://src/anim/anim_math.gd")

## The emote currently playing (or blending out), null when idle.
var current: EmoteLibrary.EmoteDef = null

## Scratch pose the library writes into each frame.
var pose: PoseStack = PoseStack.new()

var _elapsed: float = 0.0
var _weight: float = 0.0
var _stopping: bool = false


## Start emote `id`. Returns false if the id is unknown. Re-issuing the emote
## that is already playing restarts it, which is what a second button press
## should do.
func play(id: String) -> bool:
	var def: EmoteLibrary.EmoteDef = EmoteLibrary.find(id)
	if def == null:
		return false
	current = def
	_elapsed = 0.0
	_stopping = false
	return true


## Begin blending out. The emote keeps posing at its last beat until the weight
## reaches zero, then clears itself.
func stop() -> void:
	if current != null:
		_stopping = true


## Drop the emote instantly with no blend — for cutscenes, death and teleports,
## where a graceful exit would be wrong.
func cancel() -> void:
	current = null
	_stopping = false
	_elapsed = 0.0
	_weight = 0.0
	pose.clear()


## True while an emote owns any part of the body.
func is_active() -> bool:
	return current != null or _weight > 0.001


## True while an emote is playing forward (not already blending out) — the
## test the controller uses to decide whether to pin the player in place.
func is_playing() -> bool:
	return current != null and not _stopping


## How much of the body the emote currently owns, 0..1.
func weight() -> float:
	return _weight


## True if the active emote poses the legs, so the animator should hand them
## over and stop planting feet with IK.
func overrides_legs() -> bool:
	return current != null and current.overrides_legs


## True if the active emote pins the player in place.
func locks_movement() -> bool:
	return is_playing() and current.locks_movement


## Advance timing, evaluate the pose, and update the blend weight.
func tick(delta: float) -> void:
	if current == null:
		_weight = maxf(0.0, _weight - delta * 4.0)
		if _weight <= 0.001:
			pose.clear()
		return

	_elapsed += delta
	var beat: float = 0.0
	if current.loops:
		beat = fposmod(_elapsed / maxf(current.duration, 0.01), 1.0)
	else:
		beat = clampf(_elapsed / maxf(current.duration, 0.01), 0.0, 1.0)
		# A one-shot that has run its course starts blending out on its own.
		if _elapsed >= current.duration:
			_stopping = true

	# Weight ramps in over blend_in and out over blend_out, both frame-rate
	# independent (a fixed per-frame step would blend faster at high fps).
	var target: float = 0.0 if _stopping else 1.0
	var ramp: float = current.blend_out if _stopping else current.blend_in
	_weight = move_toward(_weight, target, delta / maxf(ramp, 0.01))

	pose.clear()
	EmoteLibrary.evaluate(current.id, pose, _elapsed, beat)

	if _stopping and _weight <= 0.001:
		current = null
		_stopping = false
		_elapsed = 0.0
		pose.clear()

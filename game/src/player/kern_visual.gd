class_name KernVisual
extends Node3D
## Kern's character rig: a code-built, skinned, life-sized hero (1.78 m) with a
## sculpted head, five-fingered hands, and layered travel-gear — assembled from
## the kern/ builder modules and animated procedurally here.
##
## Public API is unchanged from the placeholder version so the rest of the game
## keeps working untouched:
##   * this Node3D is rotated (`rotation.y`) to face travel, scaled for the
##     jump/land squash, and hidden on the come-apart — all still valid, since
##     the skeleton + head are its children.
##   * pose_attack(phase) / pose_guard(active) / combat_release() are the exact
##     hooks PlayerCombat drives; they now choreograph the arm+sword on the
##     skeleton instead of a floating primitive.
##
## Animation is layered: a locomotion base (gait, torso counter-rotation, head
## carriage) is computed every frame, then combat can override the sword arm,
## and idle life (breathing, weight-shift, blinks, saccades) plays on top.

const BodyBuilder: GDScript = preload("res://src/player/kern/kern_body_builder.gd")
const GearBuilder: GDScript = preload("res://src/player/kern/kern_gear_builder.gd")
const HeadScene: GDScript = preload("res://src/player/kern/kern_head.gd")

# Sword carry pose in the right-hand frame (grip seated in the curled fingers,
# blade up and angled back — a traveller's ready-but-relaxed hold).
const SWORD_REST_POS: Vector3 = Vector3(0.0, 0.02, 0.0)
const SWORD_REST_ROT: Vector3 = Vector3(-0.35, 0.0, 0.28)

# Neutral joint offsets (radians) layered under all animation so the arms hang
# with a little life instead of dead-vertical.
const NEUTRAL: Dictionary = {
	"UpperArmL": Vector3(0.10, 0.0, 0.14),
	"UpperArmR": Vector3(0.10, 0.0, -0.14),
	"ForearmL": Vector3(0.18, 0.10, 0.0),
	"ForearmR": Vector3(0.18, -0.10, 0.0),
	"ClavicleL": Vector3(0.0, 0.0, 0.05),
	"ClavicleR": Vector3(0.0, 0.0, -0.05),
}

enum Combat { NONE, ATTACK, GUARD }

var _body: CharacterBody3D
var _skeleton: Skeleton3D
var _bones: Dictionary
var _head: KernHead
var _sword: Node3D

var _phase: float = 0.0          # gait cycle
var _idle_t: float = 0.0
var _speed_smooth: float = 0.0

# Combat overlay.
var _combat: int = Combat.NONE
var _attack_phase: float = 0.0
var _combat_blend: float = 0.0   # eases the sword arm in/out of combat

# Head / eye life.
var _blink: float = 0.0
var _blink_cd: float = 2.0
var _blinking: bool = false
var _blink_t: float = 0.0
var _gaze: Vector2 = Vector2.ZERO
var _gaze_target: Vector2 = Vector2.ZERO
var _saccade_cd: float = 1.2
var _head_look: Vector2 = Vector2.ZERO

# Cloak spring (lags Kern's motion so it swings and settles).
var _cloak_swing: float = 0.0
var _cloak_vel: float = 0.0
var _prev_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	var body_data: Dictionary = BodyBuilder.build(self)
	_skeleton = body_data["skeleton"]
	_bones = body_data["bones"]

	_head = HeadScene.new()
	_head.name = "Head"
	(body_data["head_attach"] as BoneAttachment3D).add_child(_head)
	_head.build(_head_pivot())

	var gear: Dictionary = GearBuilder.build(_skeleton, _bones, body_data)
	_sword = gear["sword"]
	# The sword rides the right hand so combat poses move it for free.
	var hand_attach: BoneAttachment3D = body_data["hand_r_attach"]
	hand_attach.add_child(_sword)
	_sword.position = SWORD_REST_POS
	_sword.rotation = SWORD_REST_ROT

	if _body != null:
		_prev_pos = _body.global_position


## The head bone's global rest position — kern_head builds around this so its
## own origin lands on the pivot and it rotates like a real head.
func _head_pivot() -> Vector3:
	var idx: int = _bones["Head"]
	return _skeleton.get_bone_global_rest(idx).origin


func _process(delta: float) -> void:
	if _body == null or _skeleton == null:
		return
	var speed: float = Vector2(_body.velocity.x, _body.velocity.z).length()
	_speed_smooth = lerpf(_speed_smooth, speed, 1.0 - exp(-8.0 * delta))
	var moving: float = smoothstep(0.12, 2.2, _speed_smooth)
	_phase += delta * lerpf(2.6, 9.0, clampf(_speed_smooth / 7.5, 0.0, 1.0))
	_idle_t += delta

	var pose: Dictionary = {}
	_locomotion(pose, moving)
	_idle_life(pose, delta, moving)

	# Combat overlay on the right arm + sword.
	var want_combat: float = 1.0 if _combat != Combat.NONE else 0.0
	_combat_blend = lerpf(_combat_blend, want_combat, 1.0 - exp(-16.0 * delta))
	if _combat_blend > 0.001:
		_apply_combat(pose)

	_commit(pose)
	_animate_cloak(delta, moving)
	_animate_head_extras(delta, moving)


# --- Locomotion -------------------------------------------------------------

func _locomotion(pose: Dictionary, moving: float) -> void:
	var s: float = sin(_phase)
	var c: float = cos(_phase)
	var leg_amp: float = 0.62 * moving
	var arm_amp: float = 0.52 * moving

	# Legs: thighs swing opposite; knees flex on the lifting (rear) swing.
	pose["ThighL"] = Vector3(s * leg_amp, 0.0, 0.0)
	pose["ThighR"] = Vector3(-s * leg_amp, 0.0, 0.0)
	pose["ShinL"] = Vector3(maxf(0.0, -s) * 1.05 * moving + 0.05, 0.0, 0.0)
	pose["ShinR"] = Vector3(maxf(0.0, s) * 1.05 * moving + 0.05, 0.0, 0.0)
	# Ankles keep the feet roughly level through the stride.
	pose["FootL"] = Vector3(-s * 0.28 * moving, 0.0, 0.0)
	pose["FootR"] = Vector3(s * 0.28 * moving, 0.0, 0.0)

	# Arms counter-swing to the legs (right arm yields to combat later).
	pose["UpperArmL"] = _n("UpperArmL") + Vector3(-s * arm_amp, 0.0, 0.0)
	pose["UpperArmR"] = _n("UpperArmR") + Vector3(s * arm_amp, 0.0, 0.0)
	pose["ForearmL"] = _n("ForearmL") + Vector3(maxf(0.0, s) * 0.5 * moving, 0.0, 0.0)
	pose["ForearmR"] = _n("ForearmR") + Vector3(maxf(0.0, -s) * 0.5 * moving, 0.0, 0.0)

	# Torso counter-rotation + bob; hips lead, chest trails (spinal delay).
	pose["Hips"] = Vector3(0.02 * moving, -s * 0.10 * moving, c * 0.05 * moving)
	pose["Spine"] = Vector3(0.03 * moving, s * 0.05 * moving, 0.0)
	pose["Chest"] = Vector3(0.02 * moving, s * 0.10 * moving, 0.0)
	# Head stays level against the shoulder counter-rotation.
	pose["Neck"] = Vector3(-0.02 * moving, -s * 0.06 * moving, 0.0)

	# Airborne: tuck the legs a touch and lift the arms for balance.
	if _body != null and not _body.is_on_floor():
		var air: float = clampf(-_body.velocity.y * 0.02 + 0.3, 0.0, 1.0)
		pose["ThighL"] = Vector3(0.5 * air, 0.0, 0.05)
		pose["ThighR"] = Vector3(0.35 * air, 0.0, -0.05)
		pose["ShinL"] = Vector3(0.8 * air, 0.0, 0.0)
		pose["ShinR"] = Vector3(0.6 * air, 0.0, 0.0)
		pose["UpperArmL"] = _n("UpperArmL") + Vector3(-0.4 * air, 0.0, 0.15)
		pose["UpperArmR"] = _n("UpperArmR") + Vector3(-0.4 * air, 0.0, -0.15)


func _n(bone_name: String) -> Vector3:
	return NEUTRAL.get(bone_name, Vector3.ZERO)


# --- Idle life --------------------------------------------------------------

func _idle_life(pose: Dictionary, _delta: float, moving: float) -> void:
	var calm: float = 1.0 - moving
	# Breathing: chest rises/opens on a slow cycle when standing.
	var breath: float = sin(_idle_t * 1.5)
	var chest: Vector3 = pose.get("Chest", Vector3.ZERO)
	pose["Chest"] = chest + Vector3(-breath * 0.02 * calm, 0.0, 0.0)
	var spine: Vector3 = pose.get("Spine", Vector3.ZERO)
	pose["Spine"] = spine + Vector3(breath * 0.012 * calm, 0.0, 0.0)
	# Slow weight-shift from foot to foot while idle.
	var shift: float = sin(_idle_t * 0.55)
	var hips: Vector3 = pose.get("Hips", Vector3.ZERO)
	pose["Hips"] = hips + Vector3(0.0, 0.0, shift * 0.05 * calm)
	# Gentle idle sway of the arms so they never freeze solid.
	var la: Vector3 = pose.get("UpperArmL", _n("UpperArmL"))
	var ra: Vector3 = pose.get("UpperArmR", _n("UpperArmR"))
	pose["UpperArmL"] = la + Vector3(sin(_idle_t * 1.1) * 0.02 * calm, 0.0, 0.0)
	pose["UpperArmR"] = ra + Vector3(sin(_idle_t * 1.1 + 0.5) * 0.02 * calm, 0.0, 0.0)
	# Head carriage: a slow living drift plus a look toward travel.
	var neck: Vector3 = pose.get("Neck", Vector3.ZERO)
	pose["Neck"] = neck + Vector3(
		_head_look.y + sin(_idle_t * 0.7) * 0.03 * calm,
		_head_look.x + sin(_idle_t * 0.43) * 0.05 * calm, 0.0)


# --- Combat overlay ---------------------------------------------------------

func _apply_combat(pose: Dictionary) -> void:
	var arm: Vector3
	var fore: Vector3
	var clav: Vector3 = _n("ClavicleR")
	if _combat == Combat.GUARD:
		# Sword raised across the body, elbow tucked, shoulder squared.
		arm = Vector3(-0.55, 0.35, -0.35)
		fore = Vector3(1.15, -0.55, 0.0)
		clav = Vector3(0.0, -0.10, -0.12)
	else:
		var p: float = _attack_phase
		if p < 0.30:
			# Wind-up: sword rises up and back over the shoulder.
			var t: float = p / 0.30
			arm = Vector3(-1.7, -0.35, -0.30).lerp(Vector3(-2.15, -0.55, -0.15), t)
			fore = Vector3(1.4, -0.2, 0.0).lerp(Vector3(1.9, -0.1, 0.0), t)
		elif p < 0.62:
			# Strike: a diagonal downward sweep across the front.
			var e: float = smoothstep(0.0, 1.0, (p - 0.30) / 0.32)
			arm = Vector3(-2.15, -0.55, -0.15).lerp(Vector3(0.55, 0.55, 0.30), e)
			fore = Vector3(1.9, -0.1, 0.0).lerp(Vector3(0.25, 0.1, 0.0), e)
			clav = _n("ClavicleR").lerp(Vector3(0.05, 0.18, -0.05), e)
		else:
			# Recover back toward the ready carry.
			var e2: float = smoothstep(0.0, 1.0, (p - 0.62) / 0.38)
			arm = Vector3(0.55, 0.55, 0.30).lerp(_n("UpperArmR"), e2)
			fore = Vector3(0.25, 0.1, 0.0).lerp(_n("ForearmR"), e2)
	# Blend from whatever locomotion had the arm doing into the combat pose.
	var b: float = _combat_blend
	pose["UpperArmR"] = (pose.get("UpperArmR", _n("UpperArmR")) as Vector3).lerp(arm, b)
	pose["ForearmR"] = (pose.get("ForearmR", _n("ForearmR")) as Vector3).lerp(fore, b)
	pose["ClavicleR"] = (pose.get("ClavicleR", _n("ClavicleR")) as Vector3).lerp(clav, b)
	# A little whole-body commitment: torso twists into the swing.
	if _combat == Combat.ATTACK:
		var twist: float = sin(clampf(_attack_phase / 0.62, 0.0, 1.0) * PI) * 0.18 * b
		var chest: Vector3 = pose.get("Chest", Vector3.ZERO)
		pose["Chest"] = chest + Vector3(0.0, twist, 0.0)


# --- Commit -----------------------------------------------------------------

func _commit(pose: Dictionary) -> void:
	# Ensure every neutral-offset bone is written even if animation skipped it.
	for bone_name in NEUTRAL:
		if not pose.has(bone_name):
			pose[bone_name] = _n(bone_name)
	for bone_name in pose:
		var idx: int = _bones.get(bone_name, -1)
		if idx < 0:
			continue
		_skeleton.set_bone_pose_rotation(idx, Quaternion.from_euler(pose[bone_name]))


# --- Cloak ------------------------------------------------------------------

func _animate_cloak(delta: float, moving: float) -> void:
	if _body == null:
		return
	# Local forward speed drives a lagged swing (spring toward a rest angle).
	var vel: Vector3 = (_body.global_position - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = _body.global_position
	var local_fwd: Vector3 = global_transform.basis.inverse() * vel
	var target: float = clampf(-local_fwd.z * 0.06, -0.6, 0.6) + 0.12
	# Critically-damped-ish spring.
	var stiffness: float = 90.0
	var damping: float = 14.0
	var accel: float = (target - _cloak_swing) * stiffness - _cloak_vel * damping
	_cloak_vel += accel * delta
	_cloak_swing += _cloak_vel * delta
	var flutter: float = sin(_idle_t * 6.0) * (0.02 + moving * 0.05)
	# Distribute the swing down the chain, each bone trailing a bit more.
	_set_cloak_bone("CloakA", _cloak_swing * 0.6 + flutter * 0.4)
	_set_cloak_bone("CloakB", _cloak_swing * 1.0 + flutter * 0.7)
	_set_cloak_bone("CloakC", _cloak_swing * 1.35 + flutter)


func _set_cloak_bone(bone_name: String, pitch: float) -> void:
	var idx: int = _bones.get(bone_name, -1)
	if idx < 0:
		return
	var sway: float = sin(_idle_t * 1.7 + idx) * 0.03
	_skeleton.set_bone_pose_rotation(idx, Quaternion.from_euler(Vector3(pitch, sway, 0.0)))


# --- Head extras: blink, saccades, look-ahead -------------------------------

func _animate_head_extras(delta: float, moving: float) -> void:
	if _head == null:
		return
	# Blink scheduler.
	if _blinking:
		_blink_t += delta
		var half: float = 0.06
		if _blink_t < half:
			_blink = _blink_t / half
		elif _blink_t < half * 2.0:
			_blink = 1.0 - (_blink_t - half) / half
		else:
			_blink = 0.0
			_blinking = false
			_blink_cd = randf_range(2.2, 5.5)
	else:
		_blink_cd -= delta
		if _blink_cd <= 0.0:
			_blinking = true
			_blink_t = 0.0
	_head.set_blink(_blink)

	# Saccades: dart the eyes to a new small target now and then; between darts
	# the gaze eases and micro-jitters (fixational drift).
	_saccade_cd -= delta
	if _saccade_cd <= 0.0:
		_gaze_target = Vector2(randf_range(-0.28, 0.28), randf_range(-0.14, 0.14))
		_saccade_cd = randf_range(0.7, 2.4)
	_gaze = _gaze.lerp(_gaze_target, 1.0 - exp(-22.0 * delta))
	var jitter: Vector2 = Vector2(sin(_idle_t * 31.0), cos(_idle_t * 27.0)) * 0.006
	_head.set_gaze(_gaze.x + jitter.x, _gaze.y + jitter.y)

	# Look slightly toward travel direction (anticipation).
	var look_target: Vector2 = Vector2.ZERO
	if moving > 0.1 and _body != null:
		var lf: Vector3 = global_transform.basis.inverse() * Vector3(
			_body.velocity.x, 0.0, _body.velocity.z)
		look_target = Vector2(clampf(-lf.x * 0.03, -0.18, 0.18), 0.0)
	_head_look = _head_look.lerp(look_target, 1.0 - exp(-6.0 * delta))


# --- Combat pose API (unchanged signatures; PlayerCombat drives these) -------

func pose_attack(phase: float) -> void:
	_combat = Combat.ATTACK
	_attack_phase = clampf(phase, 0.0, 1.0)


func pose_guard(active: bool) -> void:
	_combat = Combat.GUARD if active else Combat.NONE


func combat_release() -> void:
	_combat = Combat.NONE

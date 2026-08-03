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
## **Animation.** Since the movement pass, the general work is done by
## `CreatureAnimator` (see `src/anim/`): a distance-phased gait, foot IK planted
## on the real collision world, terrain-adaptive pelvis, momentum lean, air and
## landing behaviour, idle fidgets and emotes. What stays here is what is
## genuinely Kern's own — the cloak spring, the sculpted head's blinks and
## saccades, the arcane awaken glow and the sword-arm combat overlay — plus the
## commit step, which is Kern-specific because he is the only character in the
## game driving TWO skeletons (his procedural rig and, when enabled, the
## imported base-mesh rig) from one pose.
##
## Layer order per frame: animator (locomotion + idle + emote) -> combat
## override on the sword arm -> commit to both skeletons -> cloak, head and
## glow, which read the committed pose rather than contributing to it.

const BodyBuilder: GDScript = preload("res://src/player/kern/kern_body_builder.gd")
const GearBuilder: GDScript = preload("res://src/player/kern/kern_gear_builder.gd")
const HeadScene: GDScript = preload("res://src/player/kern/kern_head.gd")
const KM: GDScript = preload("res://src/player/kern/kern_materials.gd")
const BaseModel: GDScript = preload("res://src/player/kern/kern_base_model.gd")

## Kern's height in metres — the animator measures everything else off the rig,
## but scale-relative tuning needs the one number the body was authored to.
const BODY_HEIGHT: float = 1.78

## Cloth clearance for sleeves built on the imported arm.
##
## The radius profile in `kern_body_builder.gd` was measured against the
## procedural arm, which is slimmer than the MPFB one; at 1.0 the imported
## forearm pushes straight through the cloth. This is the only knob that
## legitimately fixes that, and only NOW that the sleeve is finally built
## around the same limb — while the two were 133 mm apart, no radius could.
const IMPORTED_SLEEVE_SCALE: float = 1.32

## Cloth standoff from the measured arm surface, metres. Tapers toward the cuff
## inside `build_sleeve_on()` so the sleeve closes on the wrist rather than
## flaring into a bell.
const SLEEVE_CLEARANCE: float = 0.013

## How far down the arm the sleeve runs, 0 at the shoulder and 1 at the wrist.
##
## Deliberately a SHORT sleeve. A full-length one was pursued across half a
## dozen passes and does not hold: the cloth is skinned rigidly to two bones
## while the imported body uses MPFB's smooth multi-bone weights, so under the
## 86-degree shoulder fold the deltoid swells past any clearance that does not
## also balloon the sleeve off the shoulder entirely. Ending it above the elbow
## with a hem reads as a deliberate garment rather than a truncated one, and
## the bare forearm is the same skin the hands already show.
const SLEEVE_END: float = 0.34

## The First Model showing through: 0 = ordinary disguised traveller, 1 = fully
## lit. A faint rest ember, rising with the knowledge-charge meter (and, later,
## machinery proximity / hallucination zones). Set >= 0 to force a level
## (the character studio uses this to render rest vs charged).
const AWAKEN_REST: float = 0.12
var awaken_override: float = -1.0
var _awaken: float = AWAKEN_REST
var _charge01: float = 0.0

# Sword carry pose in the right-hand frame (grip seated in the curled fingers,
# blade up and canted out to the side + forward so it clears Kern's face — a
# traveller's ready-but-relaxed hold rather than a ceremonial vertical salute).
const SWORD_REST_POS: Vector3 = Vector3(0.02, 0.02, 0.0)
const SWORD_REST_ROT: Vector3 = Vector3(-0.5, 0.0, 0.5)

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

# Imported CC0 base body (null until the .glb is dropped in).
var _base_root: Node3D
var _base_skeleton: Skeleton3D
var _base_bones: Dictionary = {}
# Retarget cache per mapped bone: our pose eulers are MODEL-space rotations
# (the procedural rig's rest rotations are identity by construction), but the
# imported rig's bones carry real rest orientations. For each bone we keep its
# local rest rotation and its global rest basis so a model-space delta can be
# re-expressed in that bone's frame:  pose = rest_local * (Gᵀ · delta · G).
var _base_retarget: Dictionary = {}
var _head: KernHead
var _sword: Node3D

## The shared procedural-animation driver. Public so the dev locomotion lab can
## read its per-frame foot/gait state without a back-channel.
var animator: CreatureAnimator = CreatureAnimator.new()

var _idle_t: float = 0.0
var _hips_rest: Vector3 = Vector3.ZERO
## Frames left before `--armdump` reports; lets the pose settle first.
var _armdump_countdown: int = 0
## Tween for the cartoon squash/stretch accent on jumps and heavy landings.
var _scale_tween: Tween

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

# Cloak spring (lags Kern's motion so it swings and settles).
var _cloak_swing: float = 0.0
var _cloak_vel: float = 0.0
var _prev_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	_body = get_parent() as CharacterBody3D

	# If the imported CC0 base body mesh is present (assets/models/README.md),
	# report that it loaded and hand its rig to the animation via the bone map.
	# Fitting the code-built gear onto it is the next pass — until then the
	# procedural body stays the active path so the main line always runs.
	# Build the procedural rig FIRST, then load the imported body. With the
	# import loaded first, every mesh skinned to the procedural skeleton
	# rendered displaced (swallowed by the body) — two Skeleton3D siblings
	# interact badly in the skinning path depending on creation order.
	var body_data: Dictionary = BodyBuilder.build(self)
	_skeleton = body_data["skeleton"]
	_bones = body_data["bones"]

	var base: Dictionary = BaseModel.load_into(self)
	if base["ok"]:
		_base_root = base["root"]
		_base_skeleton = base["skeleton"]
		_base_bones = base["bones"]
		_cache_retarget()
		print("KernVisual: base mesh loaded (%.2f m), driving %d bones." % [
			BaseModel.measure_height(_base_root), _base_retarget.size()])
	elif String(base["reason"]) != "":
		print("KernVisual: ", base["reason"])

	_head = HeadScene.new()
	_head.name = "Head"
	# Mount the head on whichever skeleton actually carries the skull.
	#
	# With the imported body active the visible cranium is driven by the
	# IMPORTED head bone, while this node was always parented to the procedural
	# one. Any divergence between them slides the hair off the head — the same
	# failure that put Kern's arms outside his sleeves. Mounting on the bone
	# that owns the geometry removes the possibility entirely.
	var head_pivot: Vector3 = _head_pivot()
	var imported_head: int = _base_bones.get("Head", -1) if _base_skeleton != null else -1
	if imported_head >= 0:
		var attach: BoneAttachment3D = BoneAttachment3D.new()
		attach.name = "ImportedHeadAttach"
		_base_skeleton.add_child(attach)
		attach.bone_name = _base_skeleton.get_bone_name(imported_head)
		attach.add_child(_head)
		# The head's geometry is authored in MODEL space and shifted by its
		# pivot, so the pivot has to be the imported bone's model-space rest.
		var skel_in_model: Transform3D = global_transform.affine_inverse() \
			* _base_skeleton.global_transform
		var head_rest: Transform3D = skel_in_model \
			* _base_skeleton.get_bone_global_rest(imported_head)
		head_pivot = head_rest.origin
		# Cancel the bone's rest ROTATION. The procedural rig is built with
		# identity rest rotations, so a BoneAttachment on it hands children a
		# clean model-space frame; an imported MPFB rig orients every bone, and
		# that rotation was tipping the entire head assembly forward and down
		# the face — which is why the hair rooted at eye level and curtained
		# over the eyes no matter how the hairline was tuned.
		_head.transform = Transform3D(head_rest.basis.orthonormalized().inverse(),
			Vector3.ZERO)
		print("KernVisual: head mounted on the imported skull bone at %s" % [
			str(head_pivot)])
	else:
		(body_data["head_attach"] as BoneAttachment3D).add_child(_head)
	# Measure the imported skull BEFORE building, so the hair cap is lofted on
	# the real head's surface instead of the sculpted profile it was authored
	# against. Without this the cap sinks inside the imported cranium and skin
	# pushes through at the crown, which no amount of scaling fixes.
	if _base_root != null:
		var skull: Dictionary = BaseModel.sample_skull(_base_root)
		if skull.get("ok", false):
			_head.set_skull_sample(skull)
			print("KernVisual: skull sampled for hair fit (centre %s)" % [
				str(skull["centre"])])
			if OS.get_cmdline_user_args().has("--skulldump"):
				BaseModel.dump_skull(skull)
	_head.build(head_pivot)

	# With the imported body live, the procedural SKIN becomes a duplicate —
	# hide it (face/eyes, neck, hands, nails). Garments, boots, cloak, sword,
	# hair and the hand-mark stay: they are the code-built layer worn on top.
	if _base_skeleton != null:
		_retire_procedural_skin(body_data)

	var gear: Dictionary = GearBuilder.build(_skeleton, _bones, body_data)
	_sword = gear["sword"]
	_build_shards()
	# The sword rides the right hand so combat poses move it for free.
	var hand_attach: BoneAttachment3D = body_data["hand_r_attach"]
	hand_attach.add_child(_sword)
	_sword.position = SWORD_REST_POS
	_sword.rotation = SWORD_REST_ROT

	# Move the torso/limb garments onto the imported skeleton. Anything
	# skinned to the procedural skeleton renders displaced when the imported
	# body is present (an engine-level skinning conflict between the two
	# Skeleton3D siblings: the tunic's fragments lose the depth test against
	# a body they geometrically enclose, while rigid geometry at the same
	# coordinates wins it). The imported skeleton's skinning provably renders
	# true, so the garments ride it; the retargeted pose already drives it
	# with the same animation. Runs after GearBuilder so belt/scarf move too.
	if _base_skeleton != null:
		_reskin_garments_to_base()
		_rebuild_sleeves_on_import()

	if _body != null:
		_prev_pos = _body.global_position

	# Hand the rig to the shared animator. Ground probes look at layer 1 (the
	# world) and must skip Kern's own capsule, or every step lands on himself.
	_hips_rest = _skeleton.get_bone_rest(_bones["Hips"]).origin
	if _body != null:
		animator.bind(self, _body, _skeleton, _bones, BODY_HEIGHT, 1,
			[_body.get_rid()] as Array[RID])

	# Arm alignment is dumped from `_physics_process`, not here: in `_ready` the
	# imported skeleton is still in its exported T-pose and the numbers just
	# report that, which is exactly how the first run of this diagnostic
	# produced a "0.68 m gap" that meant nothing.
	if OS.get_cmdline_user_args().has("--armdump"):
		_armdump_countdown = 12

	# The magic answers to the knowledge-charge meter (Combat v1 owns it).
	if EventBus.knowledge_charge_changed and not \
			EventBus.knowledge_charge_changed.is_connected(_on_charge_changed):
		EventBus.knowledge_charge_changed.connect(_on_charge_changed)
	KM.set_awaken(_awaken)


## Rebuild both sleeves around the IMPORTED arm and skin them to it.
##
## The procedural sleeves are hidden rather than deleted, so `--no-kern-base`
## still ships the original garment untouched. See `build_sleeve_on()` for why
## this is necessary: the two arms are 47-133 mm apart once posed, so a sleeve
## built on one simply cannot clothe the other.
func _rebuild_sleeves_on_import() -> void:
	var needed: Array[String] = ["UpperArmL", "ForearmL", "HandL",
		"UpperArmR", "ForearmR", "HandR"]
	for bone_name in needed:
		if not _base_bones.has(bone_name):
			return
	for right in [false, true]:
		var suffix: String = "R" if right else "L"
		var old: Node3D = _skeleton.get_node_or_null("Sleeve" + suffix)
		if old != null:
			old.visible = false
		var upper: int = _base_bones["UpperArm" + suffix]
		var lower: int = _base_bones["Forearm" + suffix]
		var hand: int = _base_bones["Hand" + suffix]
		# Authored in the skeleton's OWN space and in its REST (T) pose.
		#
		# Both matter. The mesh is parented to the Skeleton3D, so model-space
		# coordinates put it metres away — the first attempt hung two green
		# tubes out sideways at head height. And a skin from rest transforms
		# binds the mesh as it is at REST, so pre-folding the arm down would
		# have the animation fold it a second time.
		var shoulder: Vector3 = _base_skeleton.get_bone_global_rest(upper).origin
		var elbow: Vector3 = _base_skeleton.get_bone_global_rest(lower).origin
		var wrist: Vector3 = _base_skeleton.get_bone_global_rest(hand).origin
		# Measure the arm this sleeve has to cover, in the space the vertices
		# live in, and build the cloth as that profile plus clearance. A single
		# uniform scale cannot do it: sized to clothe the forearm the bicep
		# balloons, sized for the bicep the forearm stays bare.
		var skel_in_model: Transform3D = global_transform.affine_inverse() \
			* _base_skeleton.global_transform
		var model_path: Array = []
		for i in 18:
			var t: float = float(i) / 17.0
			var p: Vector3 = shoulder.lerp(elbow, t * 2.0) if t < 0.5 \
				else elbow.lerp(wrist, (t - 0.5) * 2.0)
			model_path.append(skel_in_model * p)
		var measured: PackedFloat32Array = BaseModel.sample_arm(_base_root,
			model_path)
		if OS.get_cmdline_user_args().has("--armdump") and not right:
			var text: String = ""
			for r in measured:
				text += "%.3f " % r
			print("KernVisual: measured left arm radii: ", text)
		BodyBuilder.build_sleeve_on(_base_skeleton,
			{"upper": upper, "lower": lower, "hand": hand},
			shoulder, elbow, wrist, right, IMPORTED_SLEEVE_SCALE,
			measured, SLEEVE_CLEARANCE, SLEEVE_END)


## Print where the procedural arm bones sit versus the imported ones, in model
## space, after the rest fix.
##
## The sleeve is skinned to the PROCEDURAL arm while the visible flesh is the
## IMPORTED one, so any divergence between them shows as bare skin rendering
## over the cloth. That symptom has now been misattributed twice — once to
## sleeve width, once to the covered-geometry stripper — so it gets measured
## rather than guessed at. Run with `-- --armdump`.
func _dump_arm_alignment() -> void:
	if _base_skeleton == null:
		print("KernVisual: --armdump needs the imported body")
		return
	var skel_in_model: Transform3D = global_transform.affine_inverse() \
		* _base_skeleton.global_transform
	print("--- arm alignment (model space) ---")
	print("  bone          procedural            imported             gap")
	for bone_name in ["UpperArmL", "ForearmL", "HandL"]:
		var pi_idx: int = _bones.get(bone_name, -1)
		var rt: Dictionary = _base_retarget.get(bone_name, {})
		if pi_idx < 0 or rt.is_empty():
			continue
		var proc: Vector3 = _skeleton.get_bone_global_pose(pi_idx).origin
		var imp: Vector3 = skel_in_model \
			* _base_skeleton.get_bone_global_pose(rt["idx"]).origin
		print("  %-12s %s  %s  %.4f" % [bone_name, str(proc), str(imp),
			proc.distance_to(imp)])


func _on_charge_changed(fraction: float) -> void:
	_charge01 = clampf(fraction, 0.0, 1.0)
	_charge01 = clampf(fraction, 0.0, 1.0)


## The head bone's global rest position — kern_head builds around this so its
## own origin lands on the pivot and it rotates like a real head.
func _head_pivot() -> Vector3:
	var idx: int = _bones["Head"]
	return _skeleton.get_bone_global_rest(idx).origin


## Animation runs on the PHYSICS tick, not the render tick.
##
## Everything the locomotion reads is physics state: the body's velocity, its
## floor contact, the distance it actually moved, and the raycasts the feet are
## planted with. On the render tick those are stale by up to a frame, and — far
## worse — `_measure_travel()` sees zero displacement on render frames where
## physics did not tick, so on any machine rendering faster than 60 Hz the gait
## advanced in bursts and the legs stuttered. Driving it here keeps the gait,
## the ground probes and the body in exact lockstep.
func _physics_process(delta: float) -> void:
	if _body == null or _skeleton == null:
		return
	_idle_t += delta

	# The shared animator owns locomotion, foot planting, idle life and emotes.
	var pose: PoseStack = animator.tick(delta, _body.velocity,
		_body.is_on_floor(), _crouch_amount())
	var moving: float = clampf(animator.speed_smooth / 2.2, 0.0, 1.0)

	# Combat overlay on the right arm + sword, on top of everything else.
	var want_combat: float = 1.0 if _combat != Combat.NONE else 0.0
	_combat_blend = lerpf(_combat_blend, want_combat, 1.0 - exp(-16.0 * delta))
	if _combat_blend > 0.001:
		_apply_combat(pose)

	_commit(pose)
	if _armdump_countdown > 0:
		_armdump_countdown -= 1
		if _armdump_countdown == 0:
			_dump_arm_alignment()
	_animate_cloak(delta, moving)
	_animate_head_extras(delta, moving)
	_drive_awaken(delta)


## How crouched the body is. Read from the controller when there is one so the
## capsule and the pose can never disagree; the character studio has no
## controller, hence the fallback.
func _crouch_amount() -> float:
	if _body != null and _body.has_method("crouch_amount"):
		return float(_body.call("crouch_amount"))
	return 0.0


# --- Public hooks the controller and dev tools drive ------------------------

## Absorb a landing of `impact_speed` m/s with the knees and pelvis.
func notify_landing(impact_speed: float) -> void:
	animator.notify_landing(impact_speed)
	# Keep the old visual squash as a light accent on top of the real absorption.
	if impact_speed > 4.0:
		_play_scale(Vector3(1.08, 0.90, 1.08))


## Cartoon stretch accent on the take-off frame of a jump.
func notify_jump() -> void:
	_play_scale(Vector3(0.94, 1.08, 0.94))


## Start an emote by id (see `emote_library.gd`). Returns false if unknown.
func play_emote(id: String) -> bool:
	return animator.emotes.play(id)


## Begin blending the current emote out.
func stop_emote() -> void:
	animator.emotes.stop()


## True while an emote is pinning the player in place.
func emote_locks_movement() -> bool:
	return animator.emotes.locks_movement()


## True while any emote owns part of the body.
func emote_active() -> bool:
	return animator.emotes.is_active()


## Reset every continuous animation state after a teleport or respawn.
func teleported() -> void:
	animator.teleported()


## Visual-only squash/stretch accent, retained from the original feel pass for
## jumps and heavy landings. The real weight now comes from the animator's
## pelvis absorption; this is the cartoon garnish on top.
func _play_scale(from_scale: Vector3) -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	scale = from_scale
	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_BACK)
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector3.ONE, 0.18)


## Ease the arcane glow toward its target and push it to every magical material.
func _drive_awaken(delta: float) -> void:
	var target: float = awaken_override
	if target < 0.0:
		target = maxf(AWAKEN_REST, _charge01)
	_awaken = lerpf(_awaken, target, 1.0 - exp(-4.0 * delta))
	KM.set_awaken(_awaken)
	_orbit_shards(delta)


# --- Orbiting data-shards (charged VFX) -------------------------------------

const SHARD_COUNT: int = 11

var _shards: Array = []
var _shard_t: float = 0.0


func _build_shards() -> void:
	var mesh: PrismMesh = PrismMesh.new()
	mesh.size = Vector3(0.03, 0.11, 0.03)
	for i in SHARD_COUNT:
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.name = "DataShard%d" % i
		shard.mesh = mesh
		shard.material_override = KM.glow()
		shard.visible = false
		add_child(shard)
		_shards.append(shard)


func _orbit_shards(delta: float) -> void:
	_shard_t += delta
	var show: float = smoothstep(0.25, 0.6, _awaken)  # shards appear only when charged
	for i in _shards.size():
		var shard: MeshInstance3D = _shards[i]
		if show <= 0.001:
			shard.visible = false
			continue
		shard.visible = true
		var f: float = float(i) / float(SHARD_COUNT)
		var ang: float = f * TAU + _shard_t * (0.8 + 0.5 * f)
		var radius: float = 0.42 + 0.18 * sin(_shard_t * 0.7 + f * 6.0)
		var height: float = 0.65 + 1.05 * f + 0.06 * sin(_shard_t * 2.0 + f * 10.0)
		shard.position = Vector3(cos(ang) * radius, height, sin(ang) * radius)
		shard.rotation = Vector3(_shard_t * 1.4 + f, _shard_t * 1.1, _shard_t * 0.9 + f)
		var s: float = show * (0.6 + 0.4 * sin(_shard_t * 3.0 + f * 8.0))
		shard.scale = Vector3(s, s, s)


func _n(bone_name: String) -> Vector3:
	return NEUTRAL.get(bone_name, Vector3.ZERO)


# --- Combat overlay ---------------------------------------------------------

## Choreograph the sword arm over whatever the animator produced.
##
## Still hand-authored rather than moved into the framework: a sword combo is
## Kern's, not every creature's, and it is the one layer that has to stay in
## exact sync with `player_combat.gd`'s hit windows.
func _apply_combat(pose: PoseStack) -> void:
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
	pose.blend_euler("UpperArmR", arm, b)
	pose.blend_euler("ForearmR", fore, b)
	pose.blend_euler("ClavicleR", clav, b)
	# A little whole-body commitment: torso twists into the swing.
	if _combat == Combat.ATTACK:
		var twist: float = sin(clampf(_attack_phase / 0.62, 0.0, 1.0) * PI) * 0.18 * b
		pose.add_euler("Chest", Vector3(0.0, twist, 0.0))


# --- Commit -----------------------------------------------------------------

## Write the frame's pose onto both skeletons.
##
## Kern is the only character driving two rigs from one animation (his
## code-built skeleton, plus the imported base-mesh rig when `--kern-base` is
## on), which is why the commit lives here and not in the shared framework.
func _commit(pose: PoseStack) -> void:
	# Ensure every neutral-offset bone is written even if animation skipped it.
	for bone_name in NEUTRAL:
		if not pose.rotations.has(bone_name):
			pose.set_euler(String(bone_name), _n(bone_name))

	# The pelvis translation carries the whole body: terrain drop, crouch
	# depth, gait bob and sway, landing absorption and emote hops all arrive as
	# this one offset. It must be applied as a bone POSITION — the leg IK has
	# already solved against it, so rotating instead would leave the feet
	# solving for a pelvis the mesh is not at.
	var hips_idx: int = _bones.get("Hips", -1)
	if hips_idx >= 0:
		_skeleton.set_bone_pose_position(hips_idx, _hips_rest + pose.root_offset)

	# Emote spins turn the rig itself rather than the controller's facing, so a
	# dance can rotate without the character-controller fighting it back.
	_skeleton.rotation.y = pose.root_spin

	for bone_name in pose.rotations:
		var rotation: Quaternion = pose.rotations[bone_name]
		var idx: int = _bones.get(bone_name, -1)
		if idx >= 0:
			_skeleton.set_bone_pose_rotation(idx, rotation)
		# Same pose onto the imported skeleton, re-expressed per bone frame.
		# The rest fix (T-pose -> hanging arms) applies first, then the frame's
		# animation delta on top, both in model space.
		var rt: Dictionary = _base_retarget.get(bone_name, {})
		if not rt.is_empty():
			var delta: Basis = Basis(rotation) * (rt["fix"] as Basis)
			var local_delta: Basis = (rt["g_inv"] as Basis) * delta \
				* (rt["g"] as Basis)
			_base_skeleton.set_bone_pose_rotation(rt["idx"],
				(rt["rest"] as Quaternion) * local_delta.get_rotation_quaternion())


## Static model-space pre-rotations composed UNDER the animation deltas.
## Our pose eulers are authored against the procedural rig, whose REST already
## hangs the arms at Kern's sides; the imported rig rests in a T-pose, so its
## upper arms first need rotating from "straight out" down to the hanging
## stance the animation assumes. (Model space: +Z rotation drops the left arm,
## -Z the right.)
const BASE_REST_FIX: Dictionary = {
	# z: drop from T to hanging; x: pitch the hang slightly FORWARD (the MPFB
	# shoulder joint sits back at the scapula, so a straight drop reads as
	# hands-clasped-behind); forearms take a small natural elbow bend.
	#
	# z is 1.51 rad, NOT 1.30. A full T-to-vertical drop is PI/2 = 1.571, and
	# the procedural rig this must line up with hangs its arms 3 degrees off
	# vertical (shoulder x 0.185 -> wrist x 0.215 over a 0.55 m drop), so the
	# match is 1.51. At 1.30 the imported arm hung nearly 16 degrees out from
	# vertical and its wrist landed ~11 cm outboard of the sleeve's — so the
	# arm crossed straight out through the sleeve wall partway down, and bare
	# skin rendered over the cloth from the bicep to the cuff.
	#
	# That looked exactly like a sleeve that was too tight, and it was tuned as
	# one twice. It is not: inflating the sleeve to a 95 mm billowing tube
	# still let the arm break through the middle, which is what finally proved
	# the two limbs were not concentric at all.
	"UpperArmL": Vector3(0.06, 0.0, 1.51),
	"UpperArmR": Vector3(0.06, 0.0, -1.51),
	"ForearmL": Vector3(0.10, 0.0, 0.10),
	"ForearmR": Vector3(0.10, 0.0, -0.10),
}


## Build the per-bone conversion table between our model-space pose deltas and
## the imported rig's bone frames (see `_base_retarget` above).
func _cache_retarget() -> void:
	_base_retarget.clear()
	# The .glb root is turned PI to face -Z, so a bone's frame in MODEL space
	# is root_basis * its skeleton-space global rest.
	var root_basis: Basis = _base_root.transform.basis
	for bone_name in _base_bones:
		var idx: int = _base_bones[bone_name]
		var g: Basis = root_basis * _base_skeleton.get_bone_global_rest(idx).basis
		_base_retarget[bone_name] = {
			"idx": idx,
			"rest": _base_skeleton.get_bone_rest(idx).basis.get_rotation_quaternion(),
			"g": g,
			"g_inv": g.inverse(),
			"fix": Basis.from_euler(BASE_REST_FIX.get(bone_name, Vector3.ZERO)),
		}
	_relax_fingers()


## The animation layer never drives finger bones, so without this the imported
## hands hold the exported T-pose splay forever. A soft static curl reads as a
## relaxed hand at rest AND around the sword grip. Set once; nothing else
## writes these bones.
func _relax_fingers() -> void:
	for idx in _base_skeleton.get_bone_count():
		var lower: String = String(_base_skeleton.get_bone_name(idx)).to_lower()
		var curl: float = 0.0
		if lower.contains("thumb"):
			curl = 0.10
		elif lower.contains("index") or lower.contains("middle") \
				or lower.contains("ring") or lower.contains("pinky"):
			curl = 0.28
		if curl <= 0.0:
			continue
		var rest: Quaternion = \
			_base_skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
		# MPFB finger bones flex around their local X (verified on renders).
		_base_skeleton.set_bone_pose_rotation(idx,
			rest * Quaternion(Vector3.RIGHT, curl))


## Garment meshes that move from the procedural skeleton onto the imported
## one. The cloak family stays: its bones (CloakA/B/C) exist only on the
## procedural rig, and it renders correctly there.
## Garment meshes that move from the procedural skeleton onto the imported
## rig. The cloak family stays: its bones (CloakA/B/C) exist only on the
## procedural rig, and it renders correctly there.
## Each garment mounts RIGID on a BoneAttachment3D of the imported skeleton.
## Skinned meshes on this project's dual-skeleton setup render with broken
## depth (fragments lose the depth test everywhere; a no-depth-test override
## shows them at the correct positions) while rigid geometry provably renders
## true, so rigid mounting is the working path. Cost: garments follow one
## joint each instead of blending - fine at idle/walk torso lean, stiff on
## big limb swings. Proper skinning is a follow-up (isolate the engine bug).
const RESKIN_GARMENTS: Dictionary = {
	"Tunic": "Chest", "Belt": "Hips", "Scarf": "Neck", "ScarfTail": "Neck",
	"Pouch": "Hips", "SleeveL": "UpperArmL", "SleeveR": "UpperArmR",
	"TrouserL": "Hips", "TrouserR": "Hips",
}


## Rigid-mounting garments to the imported rig was a WORKAROUND for the
## dual-skeleton depth bug: garments enclosed by the bare imported body lost the
## depth test against it. `strip_covered_geometry` now deletes that body
## geometry outright, so the contested surface no longer exists — and rigid
## mounting costs real quality (a rigid cloak reads as a flat slab and sleeves
## as boards, because `skin = null` stops them deforming with the pose).
## So: strip only, and leave the garments skinned to the procedural skeleton
## that authored them, which the animation already drives.
const RIGID_MOUNT_GARMENTS: bool = false


func _reskin_garments_to_base() -> void:
	if not RIGID_MOUNT_GARMENTS:
		var stripped_only: int = BaseModel.strip_covered_geometry(_base_root)
		print("KernVisual: garments left skinned (deforming); %d covered body tris stripped" % stripped_only)
		return
	# Pose the imported skeleton in the neutral stance FIRST: the mount solve
	# below uses the bone pose the garment was authored around (arms hanging),
	# not the T-pose rest — otherwise the runtime pose carries each garment
	# through the T-to-hang delta a second time (sleeves stick out sideways).
	var neutral: PoseStack = PoseStack.new()
	for bone_name in NEUTRAL:
		neutral.set_euler(String(bone_name), _n(bone_name))
	_commit(neutral)
	var moved: int = 0
	for garment_name in RESKIN_GARMENTS:
		var mi: MeshInstance3D = _skeleton.get_node_or_null(garment_name)
		if mi == null:
			continue
		var bone_name: String = RESKIN_GARMENTS[garment_name]
		var bone_idx: int = _base_bones.get(bone_name, -1)
		if bone_idx < 0:
			continue
		var attach: BoneAttachment3D = BoneAttachment3D.new()
		attach.name = garment_name + "Mount"
		_base_skeleton.add_child(attach)
		attach.bone_name = _base_skeleton.get_bone_name(bone_idx)
		# The mesh is authored in this node's (model) space; the attachment ends
		# up at (skeleton-in-model) * bone_pose. Derive the skeleton's transform
		# relative to us from the real node chain — a glTF nests the Skeleton3D
		# under intermediate scene/armature nodes that each carry a transform,
		# so `_base_root.transform` alone is NOT that chain and leaves every
		# garment offset. Going through global_transform captures the whole
		# chain, and dividing by our own cancels any world/studio rotation.
		var bone_pose: Transform3D = _base_skeleton.get_bone_global_pose(bone_idx)
		var skel_in_model: Transform3D = global_transform.affine_inverse() \
			* _base_skeleton.global_transform
		var mount_in_model: Transform3D = skel_in_model * bone_pose
		mi.get_parent().remove_child(mi)
		attach.add_child(mi)
		mi.skin = null
		mi.transform = mount_in_model.affine_inverse()
		moved += 1
	# Delete the bare body under the clothing. Without this the nude body draws
	# over the garments enclosing it; with it there is simply no hidden surface
	# to contest, which is how clothed characters are normally built.
	var stripped: int = BaseModel.strip_covered_geometry(_base_root)
	print("KernVisual: %d garments mounted, %d covered body tris stripped" % [
		moved, stripped])



## Hide the procedural skin that the imported body replaces. The garments,
## boots, cloak, scarf, sword, hair, brows and hand-mark all stay — they are
## the code-built layer the GDD amendment kept.
func _retire_procedural_skin(body_data: Dictionary) -> void:
	var neck: Node3D = _skeleton.get_node_or_null("NeckSkin")
	if neck != null:
		neck.visible = false
	for attach_key in ["hand_l_attach", "hand_r_attach"]:
		var attach: BoneAttachment3D = body_data[attach_key]
		for hand_root in attach.get_children():
			for part in (hand_root as Node3D).get_children():
				# Keep the arcane layer: HandMark, HandThread%d, SigilRing.
				var keep: bool = part.name == "HandMark" \
					or String(part.name).begins_with("HandThread") \
					or part.name == "SigilRing"
				if not keep and part is Node3D:
					(part as Node3D).visible = false
	if _head != null:
		_head.retire_skin_for_import()


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
	# Rest with the lids relaxed (covering the top sliver of the iris) rather
	# than wide-eyed; a blink still closes them fully.
	_head.set_blink(0.06 + _blink * 0.94)

	# Saccades: dart the eyes to a new small target now and then; between darts
	# the gaze eases and micro-jitters (fixational drift).
	_saccade_cd -= delta
	if _saccade_cd <= 0.0:
		_gaze_target = Vector2(randf_range(-0.28, 0.28), randf_range(-0.14, 0.14))
		_saccade_cd = randf_range(0.7, 2.4)
	_gaze = _gaze.lerp(_gaze_target, 1.0 - exp(-22.0 * delta))
	var jitter: Vector2 = Vector2(sin(_idle_t * 31.0), cos(_idle_t * 27.0)) * 0.006
	_head.set_gaze(_gaze.x + jitter.x, _gaze.y + jitter.y)
	# The neck's own turn toward travel now comes from the animator's
	# anticipation term, so nothing more is needed here — the eyes lead, the
	# neck follows, which is the order a real head does it in.


# --- Combat pose API (unchanged signatures; PlayerCombat drives these) -------

func pose_attack(phase: float) -> void:
	_combat = Combat.ATTACK
	_attack_phase = clampf(phase, 0.0, 1.0)


func pose_guard(active: bool) -> void:
	_combat = Combat.GUARD if active else Combat.NONE


func combat_release() -> void:
	_combat = Combat.NONE

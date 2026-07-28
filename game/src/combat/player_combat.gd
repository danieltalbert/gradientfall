class_name PlayerCombat
extends Node
## Kern's sword kit — Phase 1 milestone 6 (Combat v1).
##
## Runs as a child of the Player and is driven once per physics frame by
## player.gd calling tick(); it never calls move itself, it only reports what
## it wants (a movement scale, an optional dodge velocity, a facing to lock)
## and the controller obeys. Kept out of player.gd so locomotion stays legible.
##
## Contents: a 3-hit light combo with a forgiving buffer window, a roll-dodge
## with i-frames, a hold-block with a tight parry window, and a "focus" special
## that spends a knowledge charge for a shard-nova. The charge SOURCE is the
## next milestone's job (an in-combat quiz) — this file only exposes add_charge()
## and listens on EventBus.quiz_answered, plus a dev fill key for unseen-build
## verification. All tunables are consts up top: the numbers are the feel.

enum Atk { READY, WINDUP, ACTIVE, RECOVER }

# Combo timing (seconds) and per-hit payload.
const WINDUP_TIME: float = 0.09
const ACTIVE_TIME: float = 0.13
const RECOVER_TIME: Array[float] = [0.24, 0.24, 0.44]  # 3rd hit commits
const COMBO_BUFFER: float = 0.42     # press within this to chain the next swing
const HIT_DAMAGE: Array[float] = [0.5, 0.5, 0.85]
const HIT_KNOCKBACK: Array[float] = [4.0, 4.5, 7.5]
const HITSTOP_TIME: float = 0.06
const HITSTOP_SCALE: float = 0.05

# Reach.
const SWORD_REACH: float = 1.65
const SWORD_LIFT: float = 0.9
const SOFT_TARGET_RANGE: float = 4.6

# Dodge.
const DODGE_SPEED: float = 12.0
const DODGE_TIME: float = 0.30
const DODGE_IFRAMES: float = 0.22
const DODGE_COOLDOWN: float = 0.45

# Block / parry.
const BLOCK_MOVE_SCALE: float = 0.35
const PARRY_WINDOW: float = 0.18
const BLOCK_CHIP: float = 0.25       # fraction of damage that leaks through a block
const BLOCK_FRONT_DOT: float = 0.1   # how frontal a blow must be to be guarded

# Focus / knowledge charge.
const CHARGE_PER_QUIZ: float = 0.34
const SPECIAL_DAMAGE: float = 1.6
const SPECIAL_RADIUS: float = 4.6
const SPECIAL_KNOCKBACK: float = 10.0

# Knowledge channel (milestone 7): while Kern and Bit combine power through
# the quiz card, the world crawls and Kern is untouchable (Danny's call:
# live fight, but slow-mo + safe while focusing).
const CHANNEL_TIME_SCALE: float = 0.15

# --- Outputs read by player.gd after tick() ---
var move_scale: float = 1.0
var use_velocity_override: bool = false
var velocity_override: Vector3 = Vector3.ZERO
var lock_facing: bool = false
var facing_yaw: float = 0.0

var _player: CharacterBody3D
var _visual: Node       # KernVisual
var _rig: Node3D        # CameraRig
var _health: Health

var _atk: int = Atk.READY
var _atk_time: float = 0.0
var _combo: int = 0
var _queued: bool = false
var _attack_yaw: float = 0.0
var _swing_hits: Dictionary = {}

var _dodge_left: float = 0.0
var _dodge_cd: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD

var _blocking: bool = false
var _block_time: float = 0.0

var _charge: float = 0.0
var _last_charge_sent: float = -1.0
var _channeling: bool = false

var _hitbox: Area3D
var _in_hitstop: bool = false


func setup(player: CharacterBody3D, visual: Node, rig: Node3D, health: Health) -> void:
	_player = player
	_visual = visual
	_rig = rig
	_health = health
	_build_hitbox()
	if not EventBus.quiz_answered.is_connected(_on_quiz_answered):
		EventBus.quiz_answered.connect(_on_quiz_answered)
	if not EventBus.knowledge_channel_started.is_connected(_on_channel_started):
		EventBus.knowledge_channel_started.connect(_on_channel_started)
	if not EventBus.knowledge_channel_ended.is_connected(_on_channel_ended):
		EventBus.knowledge_channel_ended.connect(_on_channel_ended)
	_emit_charge()


func _build_hitbox() -> void:
	_hitbox = Area3D.new()
	_hitbox.name = "SwordHitbox"
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = CombatLayers.ENEMY
	_hitbox.monitoring = false
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.5, 1.2, SWORD_REACH)
	shape.shape = box
	_hitbox.add_child(shape)
	_player.get_parent().add_child.call_deferred(_hitbox)


# --- Frame tick --------------------------------------------------------------

func tick(delta: float) -> void:
	_reset_outputs()
	_dodge_cd = maxf(0.0, _dodge_cd - delta)

	_read_special()
	if _channeling:
		# Kern stands braced, focusing with Bit; the prompt owns all input.
		move_scale = 0.0
		_update_hitbox()
		if _visual != null and _visual.has_method(&"pose_guard"):
			_visual.pose_guard(true)
		return
	_read_dodge()

	if _dodge_left > 0.0:
		_advance_dodge(delta)
	else:
		_advance_block(delta)
		_advance_attack(delta)

	_update_hitbox()
	_drive_visual()


func _reset_outputs() -> void:
	move_scale = 1.0
	use_velocity_override = false
	lock_facing = false


# --- Dodge -------------------------------------------------------------------

func _read_dodge() -> void:
	if Input.is_action_just_pressed(&"dodge") and _dodge_left <= 0.0 and _dodge_cd <= 0.0:
		_start_dodge()


func _start_dodge() -> void:
	# Cancel any swing; a roll always beats a commitment (Souls-ish generosity).
	_cancel_swing()
	_blocking = false
	_dodge_left = DODGE_TIME
	_dodge_cd = DODGE_COOLDOWN + DODGE_TIME
	_health.set_external_invuln(true)
	var dir: Vector3 = _input_world_dir()
	if dir.length_squared() < 0.01:
		# No stick input: dive backward from the camera (a retreat).
		dir = -_aim_forward()
	_dodge_dir = dir.normalized()
	facing_yaw = atan2(-_dodge_dir.x, -_dodge_dir.z)


func _advance_dodge(delta: float) -> void:
	_dodge_left -= delta
	var t: float = 1.0 - clampf(_dodge_left / DODGE_TIME, 0.0, 1.0)
	# Ease out so the roll lands rather than skids.
	var speed: float = DODGE_SPEED * (1.0 - smoothstep(0.55, 1.0, t))
	velocity_override = _dodge_dir * speed
	use_velocity_override = true
	lock_facing = true
	if _dodge_left <= DODGE_TIME - DODGE_IFRAMES:
		_health.set_external_invuln(false)
	if _dodge_left <= 0.0:
		_health.set_external_invuln(false)


# --- Block / parry -----------------------------------------------------------

func _advance_block(delta: float) -> void:
	var want: bool = Input.is_action_pressed(&"block") and _atk == Atk.READY
	if want and not _blocking:
		_blocking = true
		_block_time = 0.0
	elif not want:
		_blocking = false
	if _blocking:
		_block_time += delta
		move_scale = BLOCK_MOVE_SCALE
		lock_facing = true
		facing_yaw = _aim_yaw()


func block_active() -> bool:
	return _blocking


func parry_active() -> bool:
	return _blocking and _block_time <= PARRY_WINDOW


## Called by player.apply_hit when a blow is guarded. Returns the damage mult.
func on_blocked(from_position: Vector3) -> float:
	# `to` points player→source; the guard faces _aim_forward(). A blow is
	# covered when its source sits in front of that facing (dot > 0).
	var to: Vector3 = from_position - _player.global_position
	to.y = 0.0
	var frontal: bool = to.normalized().dot(_aim_forward()) > BLOCK_FRONT_DOT
	if not frontal:
		return 1.0  # hit from the side/back — the guard doesn't cover it
	if parry_active():
		_on_parry()
		return 0.0
	EventBus.combat_shake.emit(0.08)
	return BLOCK_CHIP


func _on_parry() -> void:
	EventBus.combat_shake.emit(0.18)
	_hitstop(0.08, 0.04)
	add_charge(CHARGE_PER_QUIZ * 0.5)  # a clean parry rewards a sliver of focus


# --- Attack combo ------------------------------------------------------------

func _advance_attack(delta: float) -> void:
	if Input.is_action_just_pressed(&"attack") and not _blocking:
		if _atk == Atk.READY:
			_start_swing(0)
		elif _combo < HIT_DAMAGE.size() - 1 and _atk_time_left_in_chain_window():
			_queued = true

	if _atk == Atk.READY:
		return

	_atk_time += delta
	match _atk:
		Atk.WINDUP:
			lock_facing = true
			move_scale = 0.0
			if _atk_time >= WINDUP_TIME:
				_enter_active()
		Atk.ACTIVE:
			lock_facing = true
			move_scale = 0.0
			if _atk_time >= ACTIVE_TIME:
				_enter_recover()
		Atk.RECOVER:
			move_scale = 0.15
			if _atk_time >= RECOVER_TIME[_combo]:
				if _queued and _combo < HIT_DAMAGE.size() - 1:
					_start_swing(_combo + 1)
				else:
					_end_combo()


func _atk_time_left_in_chain_window() -> bool:
	# Allow queuing during ACTIVE and the first part of RECOVER.
	if _atk == Atk.ACTIVE:
		return true
	if _atk == Atk.RECOVER:
		return _atk_time <= COMBO_BUFFER
	return false


func _start_swing(index: int) -> void:
	_combo = index
	_queued = false
	_atk = Atk.WINDUP
	_atk_time = 0.0
	_swing_hits.clear()
	_attack_yaw = _pick_attack_yaw()
	facing_yaw = _attack_yaw
	lock_facing = true


func _enter_active() -> void:
	_atk = Atk.ACTIVE
	_atk_time = 0.0
	if _hitbox != null:
		_hitbox.monitoring = true


func _enter_recover() -> void:
	_atk = Atk.RECOVER
	_atk_time = 0.0
	if _hitbox != null:
		_hitbox.monitoring = false


func _end_combo() -> void:
	_atk = Atk.READY
	_atk_time = 0.0
	_combo = 0
	_queued = false


func _cancel_swing() -> void:
	if _hitbox != null:
		_hitbox.monitoring = false
	_atk = Atk.READY
	_atk_time = 0.0
	_queued = false


func _pick_attack_yaw() -> float:
	var target: Node3D = _nearest_target_in_front()
	if target != null:
		var to: Vector3 = target.global_position - _player.global_position
		return atan2(-to.x, -to.z)
	# No lock-on: swing where the stick points, else where the camera looks.
	var dir: Vector3 = _input_world_dir()
	if dir.length_squared() > 0.01:
		return atan2(-dir.x, -dir.z)
	return _aim_yaw()


func _nearest_target_in_front() -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	var fwd: Vector3 = _aim_forward()
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var e: Node3D = node as Node3D
		if e == null:
			continue
		var to: Vector3 = e.global_position - _player.global_position
		to.y = 0.0
		var d: float = to.length()
		if d > SOFT_TARGET_RANGE or d < 0.05:
			continue
		if to.normalized().dot(fwd) < 0.15:
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


# --- Hit resolution ----------------------------------------------------------

func _update_hitbox() -> void:
	if _hitbox == null or not _hitbox.is_inside_tree():
		return  # added via call_deferred — may not be in the tree on the first tick
	var fwd: Vector3 = _forward_from_yaw(_attack_yaw)
	_hitbox.global_position = _player.global_position + Vector3(0.0, SWORD_LIFT, 0.0) + fwd * (SWORD_REACH * 0.5)
	_hitbox.global_rotation = Vector3(0.0, _attack_yaw, 0.0)
	if _atk != Atk.ACTIVE:
		return
	for body: Node3D in _hitbox.get_overlapping_bodies():
		if body == null or not body.is_in_group(&"enemy"):
			continue
		var id: int = body.get_instance_id()
		if _swing_hits.has(id) or not body.has_method(&"apply_hit"):
			continue
		_swing_hits[id] = true
		body.apply_hit(HIT_DAMAGE[_combo], _player.global_position, HIT_KNOCKBACK[_combo])
		_hitstop(HITSTOP_TIME, HITSTOP_SCALE)
		EventBus.combat_shake.emit(0.14 + 0.06 * float(_combo))


# --- Special (focus) ---------------------------------------------------------

func _read_special() -> void:
	if Input.is_action_just_pressed(&"debug_charge"):
		add_charge(1.0)  # dev-only: verify the special without the quiz system
	if _channeling:
		return  # the KnowledgePrompt owns the special key until the card closes
	if Input.is_action_just_pressed(&"special"):
		if _charge >= 1.0:
			_try_special()
		elif _atk == Atk.READY and _dodge_left <= 0.0 and not _blocking:
			# Part-full meter: the strike must be CAST — call the channel
			# (Kern + Bit combine power through questions; milestone 7).
			EventBus.knowledge_channel_requested.emit()


func _try_special() -> void:
	if _charge < 1.0 or _atk != Atk.READY or _dodge_left > 0.0:
		return
	_charge = 0.0
	_emit_charge()
	var origin: Vector3 = _player.global_position
	DamageShards.burst(get_tree().current_scene, origin + Vector3(0.0, 0.9, 0.0),
		Color(1.0, 0.85, 0.35), 34, 7.5, 3.0, 1.6)
	EventBus.combat_shake.emit(0.4)
	_hitstop(0.09, 0.05)
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var e: Node3D = node as Node3D
		if e == null or not e.has_method(&"apply_hit"):
			continue
		if e.global_position.distance_to(origin) <= SPECIAL_RADIUS:
			e.apply_hit(SPECIAL_DAMAGE, origin, SPECIAL_KNOCKBACK)


func add_charge(amount: float) -> void:
	_charge = clampf(_charge + amount, 0.0, 1.0)
	_emit_charge()


func _on_quiz_answered(_quiz_id: String, correct: bool) -> void:
	if correct:
		add_charge(CHARGE_PER_QUIZ)


# --- Knowledge channel (milestone 7) -----------------------------------------

func _on_channel_started() -> void:
	_cancel_swing()
	_blocking = false
	_channeling = true
	_health.set_external_invuln(true)
	Engine.time_scale = CHANNEL_TIME_SCALE


func _on_channel_ended(completed: bool) -> void:
	if not _channeling:
		return
	_channeling = false
	_health.set_external_invuln(false)
	if not _in_hitstop:
		Engine.time_scale = 1.0
	if completed:
		# The channel's climax: the combined Kern+Bit strike fires itself.
		_try_special()


func _emit_charge() -> void:
	if not is_equal_approx(_charge, _last_charge_sent):
		_last_charge_sent = _charge
		EventBus.knowledge_charge_changed.emit(_charge)


# --- Visual drive ------------------------------------------------------------

func _drive_visual() -> void:
	if _visual == null:
		return
	if _blocking and _visual.has_method(&"pose_guard"):
		_visual.pose_guard(true)
		return
	if _atk != Atk.READY and _visual.has_method(&"pose_attack"):
		var total: float = WINDUP_TIME + ACTIVE_TIME + RECOVER_TIME[_combo]
		var elapsed: float = _atk_time
		if _atk == Atk.ACTIVE:
			elapsed += WINDUP_TIME
		elif _atk == Atk.RECOVER:
			elapsed += WINDUP_TIME + ACTIVE_TIME
		_visual.pose_attack(clampf(elapsed / total, 0.0, 1.0))
		return
	if _visual.has_method(&"combat_release"):
		_visual.combat_release()


# --- Small helpers -----------------------------------------------------------

func is_busy() -> bool:
	return _atk != Atk.READY or _dodge_left > 0.0 or _channeling


func blocks_jump() -> bool:
	return _dodge_left > 0.0 or _atk == Atk.WINDUP or _atk == Atk.ACTIVE or _channeling


func _input_world_dir() -> Vector3:
	var iv: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if iv.length_squared() < 0.01:
		return Vector3.ZERO
	var b: Basis = _rig.global_transform.basis
	var fwd: Vector3 = -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = b.x
	right.y = 0.0
	right = right.normalized()
	return (right * iv.x - fwd * iv.y).normalized()


func _aim_forward() -> Vector3:
	var f: Vector3 = -_rig.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Vector3.FORWARD
	return f.normalized()


func _aim_yaw() -> float:
	var f: Vector3 = _aim_forward()
	return atan2(-f.x, -f.z)


func _forward_from_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _hitstop(duration: float, scale: float) -> void:
	if _in_hitstop:
		return
	_in_hitstop = true
	Engine.time_scale = scale
	var timer: SceneTreeTimer = get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(_end_hitstop)


func _end_hitstop() -> void:
	# A hitstop that overlaps the knowledge channel must hand back the
	# channel's slow-mo, not full speed.
	Engine.time_scale = CHANNEL_TIME_SCALE if _channeling else 1.0
	_in_hitstop = false

class_name Player
extends CharacterBody3D
## Kern's third-person character controller — Phase 1 milestone 2.
##
## Feel targets (the "feel pass"): responsive starts (high ground accel),
## no ice on stop (decel above accel), a BOTW-ish jump arc (floatier rise,
## heavier fall, early-release cut), coyote time + a jump buffer so hops
## never feel stolen, camera-relative movement, the body turning smoothly
## toward travel direction, and a visual-only squash/stretch on jump/land.
## All tunables are consts up top — the numbers ARE the feel pass.

const WALK_SPEED: float = 4.0
const RUN_SPEED: float = 7.5
const GROUND_ACCEL: float = 30.0
const GROUND_DECEL: float = 42.0
const AIR_ACCEL: float = 12.0
const JUMP_VELOCITY: float = 8.5  # ~1.5 m apex with RISE_GRAVITY
const RISE_GRAVITY: float = 24.0
const FALL_GRAVITY: float = 34.0
const MAX_FALL_SPEED: float = 40.0
const JUMP_CUT_FACTOR: float = 0.45  # early release trims the arc
const COYOTE_TIME: float = 0.12
const JUMP_BUFFER: float = 0.15
const TURN_SPEED: float = 12.0
const SQUASH_MIN_AIR_TIME: float = 0.2  # no squash for curb-sized drops

var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _air_time: float = 0.0
var _was_on_floor: bool = true
var _scale_tween: Tween

@onready var _visual: Node3D = $Visual
@onready var _rig: CameraRig = $CameraRig


func _ready() -> void:
	InputSetup.ensure()
	_rig.setup(self)
	EventBus.player_spawned.emit(self)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_apply_gravity(delta)
	_handle_jump()
	_handle_move(delta)
	move_and_slide()
	_handle_landing()
	_was_on_floor = is_on_floor()


func _tick_timers(delta: float) -> void:
	_coyote_left = maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if is_on_floor():
		_coyote_left = COYOTE_TIME
		_air_time = 0.0
	else:
		_air_time += delta
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = JUMP_BUFFER


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity: float = RISE_GRAVITY if velocity.y > 0.0 else FALL_GRAVITY
	velocity.y = maxf(velocity.y - gravity * delta, -MAX_FALL_SPEED)


func _handle_jump() -> void:
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_play_scale(Vector3(0.92, 1.1, 0.92))
	if velocity.y > 0.0 and Input.is_action_just_released(&"jump"):
		velocity.y *= JUMP_CUT_FACTOR


func _handle_move(delta: float) -> void:
	var input_vec: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	var cam_basis: Basis = _rig.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var dir: Vector3 = right * input_vec.x - forward * input_vec.y
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	var top_speed: float = RUN_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED
	var target: Vector2 = Vector2(dir.x, dir.z) * top_speed
	var horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	var accel: float = GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	if is_on_floor() and target.length_squared() < horizontal.length_squared():
		accel = GROUND_DECEL
	horizontal = horizontal.move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	if dir.length_squared() > 0.0001:
		# Model forward is -Z (Godot convention), hence the negations.
		var target_yaw: float = atan2(-dir.x, -dir.z)
		_visual.rotation.y = lerp_angle(
			_visual.rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta)
		)


func _handle_landing() -> void:
	if is_on_floor() and not _was_on_floor and _air_time > SQUASH_MIN_AIR_TIME:
		_play_scale(Vector3(1.12, 0.85, 1.12))


func _play_scale(from_scale: Vector3) -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	_visual.scale = from_scale
	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_BACK)
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(_visual, "scale", Vector3.ONE, 0.18)

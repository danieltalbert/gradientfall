class_name CameraRig
extends Node3D
## Third-person orbit camera: yaw on this node, pitch on the SpringArm3D.
##
## The rig is top_level — it follows the player by position (smoothed) and
## never inherits the body's rotation, so the camera stays put while Kern
## turns. The spring arm shortens through geometry (never clips walls),
## excluding the player's own collider. Subtle FOV widening while sprinting.
##
## Lives inside player.tscn as a top_level child; `setup()` is called by
## player.gd on ready to bind the body it follows. Its own children are
## SpringArm3D (pitch + wall collision) and SpringArm3D/Camera3D (the shake
## offset is applied to the camera, so shake never fights the arm's
## collision). Consumes the cam_left/right/up/down actions bound in
## input_setup.gd and listens on EventBus.combat_shake for hit feedback.
## Angles are radians, distances meters, speeds meters/second.

## Radians of yaw/pitch per pixel of mouse movement.
const MOUSE_SENSITIVITY: float = 0.003
const STICK_SENSITIVITY: float = 2.6  # radians/second at full deflection
## Pitch clamp: about -63° (looking down) to +29° (looking up). The floor is
## deeper than the ceiling because the third-person framing looks downward.
const PITCH_MIN: float = -1.1
const PITCH_MAX: float = 0.5
## Height (m) above the player's origin that the rig tracks — roughly Kern's
## shoulder line rather than his feet.
const FOLLOW_HEIGHT: float = 1.65
## Follow stiffness (1/s) for the exponential position smoothing.
const FOLLOW_SPEED: float = 14.0
## Field of view (degrees) at rest and while sprinting, and the blend rate
## (1/s) between them.
const FOV_BASE: float = 64.0
const FOV_SPRINT: float = 72.0
const FOV_LERP: float = 5.0
const SPRINT_FOV_THRESHOLD: float = 5.5  # between walk and run top speed
const SHAKE_DECAY: float = 1.9           # trauma units/second
const SHAKE_MAX_POS: float = 0.28        # metres of camera kick at full trauma
const SHAKE_MAX_ROLL: float = 0.06       # radians of roll at full trauma

## The followed body, bound by `setup()`; until then the rig only orbits.
var _target: CharacterBody3D
## Current pitch (radians), kept here rather than read back off the arm.
## Starts slightly downward for the default over-the-shoulder framing.
var _pitch: float = -0.20
## Screen-shake energy in [0, 1]; decays every frame once nonzero.
var _trauma: float = 0.0

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D


## Apply the starting pitch and subscribe to combat shake events.
func _ready() -> void:
	_arm.rotation.x = _pitch
	EventBus.combat_shake.connect(_on_combat_shake)


## Bind the body to follow, snap to it so frame one is framed correctly, and
## capture the mouse. Excluding the target's RID keeps the spring arm from
## treating Kern's own collider as a wall and slamming the camera into him.
func setup(target: CharacterBody3D) -> void:
	_target = target
	_arm.add_excluded_object(target.get_rid())
	global_position = target.global_position + Vector3(0.0, FOLLOW_HEIGHT, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Mouse look plus cursor capture handling: Escape releases the cursor and
## any click recaptures it. Look is only applied while captured, so dragging
## over a released cursor never spins the camera.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: InputEventMouseMotion = event
			_apply_look(
				-motion.relative.x * MOUSE_SENSITIVITY,
				-motion.relative.y * MOUSE_SENSITIVITY
			)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Per-frame rig update: gamepad look (frame-rate independent, unlike the
## mouse's per-pixel deltas), smoothed follow toward the target's shoulder
## point, sprint FOV blend, then shake. The lerp weights are clamped to 1.0
## so a long frame can overshoot into instability.
func _process(delta: float) -> void:
	var stick: Vector2 = Input.get_vector(
		&"cam_left", &"cam_right", &"cam_up", &"cam_down"
	)
	if stick.length_squared() > 0.0:
		_apply_look(
			-stick.x * STICK_SENSITIVITY * delta,
			-stick.y * STICK_SENSITIVITY * delta
		)
	if _target == null:
		return
	global_position = global_position.lerp(
		_target.global_position + Vector3(0.0, FOLLOW_HEIGHT, 0.0),
		minf(1.0, FOLLOW_SPEED * delta)
	)
	var ground_speed: float = Vector2(_target.velocity.x, _target.velocity.z).length()
	var fov_target: float = FOV_SPRINT if ground_speed > SPRINT_FOV_THRESHOLD else FOV_BASE
	_camera.fov = lerpf(_camera.fov, fov_target, minf(1.0, FOV_LERP * delta))
	_apply_shake(delta)


## EventBus.combat_shake handler: add `amount` of trauma, saturating at 1.0
## so a flurry of hits can't stack into an unreadable screen.
func _on_combat_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Trauma-based shake (offsets the camera, not the arm, so wall collision is
## unaffected). Trauma decays linearly while the applied displacement uses
## trauma² — the shake fades out fast and then lingers faintly, which reads
## better than a straight ramp. Zero trauma resets the offset exactly.
func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		_camera.position = Vector3.ZERO
		_camera.rotation.z = 0.0
		return
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	var s: float = _trauma * _trauma  # perceptually nicer falloff
	_camera.position = Vector3(
		randf_range(-1.0, 1.0) * SHAKE_MAX_POS * s,
		randf_range(-1.0, 1.0) * SHAKE_MAX_POS * s,
		0.0)
	_camera.rotation.z = randf_range(-1.0, 1.0) * SHAKE_MAX_ROLL * s


## Shared look application for both mouse and stick input: yaw turns this
## node freely (no clamp — the orbit is continuous), pitch is clamped and
## written to the spring arm.
func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	rotation.y += yaw_delta
	_pitch = clampf(_pitch + pitch_delta, PITCH_MIN, PITCH_MAX)
	_arm.rotation.x = _pitch

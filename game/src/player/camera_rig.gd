class_name CameraRig
extends Node3D
## Third-person orbit camera: yaw on this node, pitch on the SpringArm3D.
##
## The rig is top_level — it follows the player by position (smoothed) and
## never inherits the body's rotation, so the camera stays put while Kern
## turns. The spring arm shortens through geometry (never clips walls),
## excluding the player's own collider. Subtle FOV widening while sprinting.

const MOUSE_SENSITIVITY: float = 0.003
const STICK_SENSITIVITY: float = 2.6  # radians/second at full deflection
const PITCH_MIN: float = -1.1
const PITCH_MAX: float = 0.5
const FOLLOW_HEIGHT: float = 1.5
const FOLLOW_SPEED: float = 14.0
const FOV_BASE: float = 70.0
const FOV_SPRINT: float = 78.0
const FOV_LERP: float = 5.0
const SPRINT_FOV_THRESHOLD: float = 5.5  # between walk and run top speed

var _target: CharacterBody3D
var _pitch: float = -0.25

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	_arm.rotation.x = _pitch


func setup(target: CharacterBody3D) -> void:
	_target = target
	_arm.add_excluded_object(target.get_rid())
	global_position = target.global_position + Vector3(0.0, FOLLOW_HEIGHT, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	rotation.y += yaw_delta
	_pitch = clampf(_pitch + pitch_delta, PITCH_MIN, PITCH_MAX)
	_arm.rotation.x = _pitch

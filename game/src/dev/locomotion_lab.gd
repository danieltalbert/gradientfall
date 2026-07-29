extends Node3D
## Dev-only instrumented test bench for Kern's movement — the measuring
## instrument the locomotion work is tuned against.
##
## **Why measure instead of eyeballing.** "Smoother" and "more real" are not
## quantities you can iterate on by looking at screenshots; by the fifth pass
## nobody can remember whether the feet slid more or less than they did in the
## second. So this scene builds a controlled obstacle course, drives the REAL
## player controller through a scripted movement program with synthetic input,
## and samples hard numbers every physics frame:
##
##   * **foot slip** — how far a foot that is supposed to be planted actually
##     slides through the world. The headline number; on a correct
##     distance-phased gait it is near zero at every speed.
##   * **ground error** — how far each planted foot floats above or sinks below
##     the real collision surface.
##   * **knee direction** — signed, so a rig bending its knees backwards is
##     caught by the harness instead of by a player.
##   * **pose jerk** — the largest single-frame bone rotation, which is how
##     pops, snaps and unblended state changes show up numerically.
##   * **body jerk** — third derivative of position; controller smoothness.
##
## Results are printed as a per-segment table and written as JSON so successive
## runs can be diffed. When run with a real display it also saves a contact
## sheet of frames, because numbers cannot tell you whether a pose is dignified.
##
## Run:
##   godot --headless --path game res://scenes/dev/locomotion_lab.tscn -- \
##       --out=C:/abs/dir
## Optional: `--shots` also saves PNG frames (needs a real display, not
## --headless), `--segment=run` restricts the program to one named segment.
##
## Architecture: dev-only harness, never shipped and referenced by nothing in
## the game. Drives `player.gd` through the same `Input` singleton a human uses,
## so it exercises the shipping code path rather than a test double.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

## Physics frames to let the rig settle before sampling starts.
const WARMUP_FRAMES: int = 30

## A foot is treated as "should be planted" above this contact weight.
const PLANTED_THRESHOLD: float = 0.55

## Foot dimensions used to locate the instantaneous ground-contact point:
## metres from the ankle joint back to the heel and forward to the toe.
## Approximately a 0.22 m foot, which is right for a 1.78 m figure.
const HEEL_BEHIND: float = 0.06
const TOE_AHEAD: float = 0.16

## Foot pitch, in radians, beyond which the load is treated as being on the
## heel or the toe rather than spread across a flat sole (~1.7°).
##
## Deliberately tiny. A rigid foot is either flat or pivoting; there is no wide
## middle band. An earlier 0.12 rad threshold called the last third of the heel
## rocker "flat", so the harness measured the ankle at a moment the ankle is
## SUPPOSED to be travelling, and reported honest foot-roll as ~90 mm/m of slip.
const FLAT_PITCH_EPSILON: float = 0.03

## Frames between saved screenshots when `--shots` is on.
const SHOT_INTERVAL: int = 24

## Hard ceiling on physics frames for a whole run, after which the harness
## reports and exits regardless. The full program is about 4,400 frames.
const MAX_FRAMES: int = 12000

## Physics frames after each teleport during which the segment is DRIVEN but
## not SAMPLED.
##
## Sized off the SLOWEST continuous state in the animator, not off "looks like
## enough". The airborne cross-fade has a 0.07 s half-life and every teleport
## re-triggers it, so it needs roughly ten half-lives to become negligible;
## until it does, `_air_pose` is still blending the legs away from the IK
## solution and every foot measurement is really a measurement of the teleport.
## At 20 frames that transient was leaking into the samples and inflating
## reported foot slip several times over.
const SETTLE_FRAMES: int = 60


## One step of the scripted movement program.
class Segment:
	extends RefCounted

	## Name used in the report.
	var name: String = ""
	## Seconds to hold this segment.
	var duration: float = 2.0
	## Held actions -> analog strength.
	var actions: Dictionary = {}
	## Camera heading in radians, which is what makes movement input
	## directional (the controller is camera-relative).
	var heading: float = 0.0
	## Radians/second the camera turns during the segment — how the harness
	## exercises turning without a human on a stick.
	var heading_rate: float = 0.0
	## Emote to fire on entry, empty for none.
	var emote: String = ""
	## Fire a jump every `jump_period` seconds; 0 disables.
	var jump_period: float = 0.0
	## Where to teleport the player before the segment starts.
	##
	## Segments are deliberately INDEPENDENT: each one is placed on the terrain
	## feature it is meant to test rather than inheriting wherever the previous
	## segment happened to end up. The first version of this harness let the
	## player drift across the course and produced numbers that were mostly a
	## report on which obstacle it had wandered into.
	var start: Vector3 = Vector3(0.0, 0.6, 30.0)


## Accumulated measurements for one segment.
class SegmentStats:
	extends RefCounted

	var name: String = ""
	var frames: int = 0
	var distance: float = 0.0
	var slip_total: float = 0.0
	var slip_max: float = 0.0
	var planted_frames: int = 0
	var ground_error_total: float = 0.0
	var ground_error_max: float = 0.0
	var pose_jerk_max: float = 0.0
	var body_jerk_total: float = 0.0
	var knee_backward_frames: int = 0
	## How far the rendered ankle ends up from the target the planter asked
	## for. Non-zero means the IK could not reach and clamped — which is a
	## different failure from sliding, and the two are easy to confuse because
	## a clamped foot drifts as the hip moves.
	var ik_error_total: float = 0.0
	var ik_error_max: float = 0.0
	var ik_samples: int = 0
	## Slip split by which part of the foot was bearing load: heel / flat sole /
	## toe. Splitting it is what tells you WHICH model is wrong — a flat-sole
	## figure means the plant lock is failing, a heel or toe figure means the
	## rocker geometry disagrees with the ankle roll being animated.
	var slip_by_regime: Array[float] = [0.0, 0.0, 0.0]
	var speed_total: float = 0.0
	var head_y_min: float = 1e9
	var head_y_max: float = -1e9

	## Millimetres of slip per metre travelled — the scale-free headline
	## number, so a fast segment is not flattered by covering more ground.
	func slip_per_metre_mm() -> float:
		if distance < 0.01:
			return 0.0
		return (slip_total / distance) * 1000.0

	func mean_ground_error_mm() -> float:
		if planted_frames == 0:
			return 0.0
		return (ground_error_total / float(planted_frames)) * 1000.0

	func mean_speed() -> float:
		if frames == 0:
			return 0.0
		return speed_total / float(frames)

	func mean_body_jerk() -> float:
		if frames == 0:
			return 0.0
		return body_jerk_total / float(frames)

	func mean_ik_error_mm() -> float:
		if ik_samples == 0:
			return 0.0
		return (ik_error_total / float(ik_samples)) * 1000.0


var _player: CharacterBody3D
var _visual: Node3D
var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _rig: Node3D

var _segments: Array = []
var _stats: Array = []
var _index: int = 0
var _elapsed: float = 0.0
var _warmup: int = 0
var _heading: float = 0.0
var _jump_timer: float = 0.0
var _held: Dictionary = {}
var _settle: int = 0
var _entered: bool = false
var _ankle_rest_y: float = 0.115
var _solver_shortfall_mm: float = 0.0
var _solver_clamped_frames: int = 0
var _solver_samples: int = 0
var _total_frames: int = 0
## `--trace` prints the raw target-versus-result numbers for one foot. Summary
## statistics can only tell you a discrepancy exists; this tells you its shape.
var _tracing: bool = false
var _trace_left: int = 24

var _prev_foot_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _prev_regime: Array[int] = [1, 1]
var _have_prev_foot: bool = false
var _prev_bone_rotations: Dictionary = {}
var _prev_velocity: Vector3 = Vector3.ZERO
var _prev_accel: Vector3 = Vector3.ZERO
var _prev_position: Vector3 = Vector3.ZERO

var _out_dir: String = ""
var _want_shots: bool = false
var _shot_counter: int = 0
var _shots_saved: int = 0
var _camera: Camera3D
var _finished: bool = false


func _ready() -> void:
	_out_dir = _arg("--out=")
	_want_shots = OS.get_cmdline_user_args().has("--shots")
	_tracing = OS.get_cmdline_user_args().has("--trace")
	InputSetup.ensure()
	_build_stage()
	_spawn_player()
	_build_program()
	set_physics_process(true)


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.get_slice("=", 1)
	return ""


# --- Stage -------------------------------------------------------------------

## Build the obstacle course: a long flat run, a ramp up, a ramp down, a stair
## flight and a bumpy patch. Every surface is on collision layer 1, which is
## what the player's mask and the foot probes look for.
## Build the course as four SEPARATE zones side by side along X, each a clean
## platform with one terrain feature on it. Segments teleport to the zone they
## need, so no test can contaminate the next one.
##   x =   0  flat
##   x =  60  ramps (up and down)
##   x = 120  stairs
##   x = 180  bumpy
func _build_stage() -> void:
	# Zone A: flat. Long enough for a 4-second sprint with room to spare.
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(30.0, 1.0, 120.0))

	# Zone B: ramps. A gentle 12 degrees up and a steeper 22 down, each with a
	# flat run-up so the character arrives at speed rather than from standstill.
	_add_box(Vector3(60.0, -0.5, 20.0), Vector3(30.0, 1.0, 40.0))
	_add_ramp(Vector3(60.0, 0.52, -6.0), Vector3(16.0, 1.0, 26.0),
		deg_to_rad(12.0))
	_add_box(Vector3(60.0, 2.14, -28.0), Vector3(30.0, 1.0, 20.0))
	_add_ramp(Vector3(60.0, 1.42, -46.0), Vector3(16.0, 1.0, 20.0),
		-deg_to_rad(22.0))

	# Zone C: an eight-step flight of 0.16 m risers — the foot-IK torture test.
	_add_box(Vector3(120.0, -0.5, 20.0), Vector3(30.0, 1.0, 40.0))
	for i in 8:
		var rise: float = float(i + 1) * 0.16
		_add_box(Vector3(120.0, rise * 0.5 - 0.5, -1.0 - float(i) * 0.42),
			Vector3(12.0, rise + 1.0, 0.42))
	_add_box(Vector3(120.0, 0.78, -12.0), Vector3(30.0, 1.0, 18.0))

	# Zone D: bumpy ground — low random rises that never let both feet share a
	# height, which is what forces the pelvis and ankles to work independently.
	_add_box(Vector3(180.0, -0.5, 0.0), Vector3(30.0, 1.0, 90.0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260729
	for i in 90:
		var x: float = 180.0 + rng.randf_range(-8.0, 8.0)
		var z: float = rng.randf_range(-34.0, 34.0)
		_add_box(Vector3(x, rng.randf_range(-0.02, 0.09), z),
			Vector3(rng.randf_range(0.7, 2.0), 0.22, rng.randf_range(0.7, 2.0)))

	_add_stripes()

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)

	# Observer camera. The player's own rig is frozen for the test, so without
	# this every screenshot is a photograph of the spawn point.
	_camera = Camera3D.new()
	_camera.name = "LabCamera"
	_camera.fov = 42.0
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.22, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.55, 0.65)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_camera.environment = env
	add_child(_camera)
	_camera.current = true


## Paint half-metre reference stripes along every walking surface.
##
## Foot slip of a centimetre or two is genuinely hard to see against blank
## ground, and it is exactly what the eye picks up as "wrong" in motion. Against
## a fixed stripe the contact point either holds a line or it does not, so a
## screenshot pair answers the question the metrics can only summarise.
func _add_stripes() -> void:
	var zones: Array[float] = [0.0, 60.0, 120.0, 180.0]
	for zone_x in zones:
		for i in 260:
			if i % 2 == 1:
				continue
			var z: float = -60.0 + float(i) * 0.5
			var stripe: MeshInstance3D = MeshInstance3D.new()
			var plane: BoxMesh = BoxMesh.new()
			plane.size = Vector3(9.0, 0.01, 0.5)
			stripe.mesh = plane
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color(0.42, 0.45, 0.52)
			mat.roughness = 0.95
			stripe.material_override = mat
			stripe.position = Vector3(zone_x, 0.006, z)
			add_child(stripe)


## A static box collider plus matching mesh, centred at `centre`.
func _add_box(centre: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	body.add_child(mesh)
	body.position = centre
	add_child(body)


## A box rotated about X to make a walkable ramp.
func _add_ramp(centre: Vector3, size: Vector3, pitch: float) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	body.add_child(mesh)
	body.position = centre
	body.rotation.x = pitch
	add_child(body)


func _spawn_player() -> void:
	_player = PlayerScene.instantiate() as CharacterBody3D
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.4, 30.0)
	_visual = _player.get_node_or_null("Visual")
	_rig = _player.get_node_or_null("CameraRig")
	# The rig captures the mouse on setup; the lab drives its heading directly
	# and watches through its own camera instead.
	if _rig != null:
		_rig.set_process(false)
		var player_camera: Camera3D = _player.get_node_or_null(
			"CameraRig/SpringArm3D/Camera3D")
		if player_camera != null:
			player_camera.current = false
	# `--nocloak` hides the cloak and tunic skirt. They are most of Kern's
	# silhouette and they hang over exactly the joints this harness exists to
	# inspect, so gait work is done with them off and posture work with them on.
	if _visual != null and OS.get_cmdline_user_args().has("--nocloak"):
		for path in ["KernSkeleton/Cloak", "KernSkeleton/CloakTrim",
				"KernSkeleton/Tunic", "KernSkeleton/ScarfTail"]:
			var part: Node3D = _visual.get_node_or_null(path)
			if part != null:
				part.visible = false
	if _visual != null:
		_skeleton = _visual.get_node_or_null("KernSkeleton")
		if _skeleton != null:
			_bones = _collect_bones(_skeleton)
			# Rest height of the ankle joint above the sole — the zero point
			# every ground-error measurement is taken against.
			var ankle: int = _bones.get("FootL", -1)
			if ankle >= 0:
				_ankle_rest_y = _skeleton.get_bone_global_rest(ankle).origin.y
	_prev_position = _player.global_position


## Map the bone names the metrics need to their skeleton indices.
func _collect_bones(skeleton: Skeleton3D) -> Dictionary:
	var out: Dictionary = {}
	for i in skeleton.get_bone_count():
		out[String(skeleton.get_bone_name(i))] = i
	return out


# --- Program -----------------------------------------------------------------

## The scripted movement program. Each segment isolates one thing that can go
## wrong, so a regression shows up in a named row rather than as a worse
## average.
func _build_program() -> void:
	var only: String = _arg("--segment=")
	# Zone origins. Movement input with heading 0 travels toward -Z, so each
	# segment starts at the +Z end of its zone and runs the length of it.
	# Start heights sit just clear of each surface. Dropping the character in
	# from height makes every segment begin with a landing, which is its own
	# transient and not what most of these segments are testing.
	var flat: Vector3 = Vector3(0.0, 0.06, 45.0)
	var ramps: Vector3 = Vector3(60.0, 0.06, 34.0)
	var stairs: Vector3 = Vector3(120.0, 0.06, 32.0)
	var bumps: Vector3 = Vector3(180.0, 0.28, 34.0)

	var all: Array = []
	all.append(_seg("idle", 2.5, {}, flat))
	all.append(_seg("walk_start", 2.5, {"move_forward": 0.35}, flat))
	all.append(_seg("walk_steady", 3.5, {"move_forward": 0.35}, flat))
	all.append(_seg("jog", 3.5, {"move_forward": 0.65}, flat))
	all.append(_seg("run", 3.5, {"move_forward": 1.0}, flat))
	all.append(_seg("sprint", 3.5, {"move_forward": 1.0, "sprint": 1.0}, flat))
	var turning: Segment = _seg("run_turning", 4.0, {"move_forward": 1.0}, flat)
	turning.heading_rate = 0.7
	all.append(turning)
	all.append(_seg("hard_stop", 2.5, {}, flat))
	var hop: Segment = _seg("jump_flat", 4.5, {"move_forward": 0.6}, flat)
	hop.jump_period = 1.3
	all.append(hop)
	all.append(_seg("bumpy", 5.0, {"move_forward": 0.6}, bumps))
	all.append(_seg("stairs_up", 5.0, {"move_forward": 0.5}, stairs))
	all.append(_seg("slope_up", 5.0, {"move_forward": 0.7}, ramps))
	all.append(_seg("slope_down", 5.0, {"move_forward": 0.7},
		Vector3(60.0, 2.70, -22.0)))
	all.append(_seg("crouch_walk", 4.0, {"move_forward": 0.6, "crouch": 1.0},
		flat))
	all.append(_seg("crouch_idle", 2.5, {"crouch": 1.0}, flat))
	var spin: Segment = _seg("turn_in_place", 3.0, {}, flat)
	spin.heading_rate = 2.0
	all.append(spin)
	all.append(_seg("strafe", 3.0, {"move_right": 0.7}, flat))
	all.append(_seg("backpedal", 3.0, {"move_back": 0.5}, flat))
	var dance: Segment = _seg("emote_dance", 4.5, {}, flat)
	dance.emote = "weight_shuffle"
	all.append(dance)
	all.append(_seg("idle_settle", 4.0, {}, flat))

	for entry in all:
		var s: Segment = entry
		if only == "" or s.name == only:
			_segments.append(s)
			var stat: SegmentStats = SegmentStats.new()
			stat.name = s.name
			_stats.append(stat)


func _seg(name: String, duration: float, actions: Dictionary,
		start: Vector3) -> Segment:
	var s: Segment = Segment.new()
	s.name = name
	s.duration = duration
	s.actions = actions
	s.start = start
	return s


# --- Drive + sample ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _finished:
		return
	# Watchdog. A harness that can hang is worse than no harness: it burns a
	# whole run before anyone notices, and the failure looks like a slow test
	# rather than a bug. Past the budget it reports what it has and exits.
	_total_frames += 1
	if _total_frames > MAX_FRAMES:
		push_warning("LocomotionLab: frame budget exhausted at segment %d/%d" % [
			_index, _segments.size()])
		_finish()
		return
	if _warmup < WARMUP_FRAMES:
		_warmup += 1
		_prev_position = _player.global_position
		return
	if _index >= _segments.size():
		_finish()
		return

	var segment: Segment = _segments[_index]
	# An explicit flag, not `_elapsed == 0.0`: the settle window holds elapsed
	# at zero, so testing elapsed re-entered (and re-teleported) the segment
	# every frame and the program never advanced.
	if not _entered:
		_entered = true
		_enter_segment(segment)
	_drive(segment, delta)
	if _settle > 0:
		# Settling: hold the input but throw the measurements away.
		_settle -= 1
		_prev_position = _player.global_position
		return
	_sample(_stats[_index], delta)

	_elapsed += delta
	if _elapsed >= segment.duration:
		_release_all()
		_elapsed = 0.0
		_index += 1
		_entered = false

	if _want_shots:
		_track_camera()
		_shot_counter += 1
		if _shot_counter % _shot_interval() == 0:
			_save_shot(segment.name)


## Frames between screenshots. `--shotevery=N` tightens it to inspect a single
## stance frame by frame, which is how a planted foot is checked against the
## ground stripes.
func _shot_interval() -> int:
	var override: String = _arg("--shotevery=")
	if override != "":
		return maxi(1, int(override.to_int()))
	return SHOT_INTERVAL


## Follow the player from the side at knee height — the view that actually
## shows whether feet are planting or skating. `--shotmode=full` pulls back to
## frame the whole body for judging posture and emotes instead.
func _track_camera() -> void:
	if _camera == null or _player == null:
		return
	var focus: Vector3 = _player.global_position
	if _arg("--shotmode=") == "full":
		_camera.fov = 40.0
		_camera.global_position = focus + Vector3(3.6, 1.15, 0.9)
		_camera.look_at(focus + Vector3(0.0, 0.95, 0.0))
	else:
		_camera.fov = 34.0
		_camera.global_position = focus + Vector3(2.6, 0.62, 0.35)
		_camera.look_at(focus + Vector3(0.0, 0.42, 0.0))


## Teleport onto this segment's terrain feature, clear every continuous
## animation state, and let the body settle before sampling resumes.
func _enter_segment(segment: Segment) -> void:
	_heading = segment.heading
	_jump_timer = 0.0
	_player.global_position = segment.start
	_player.velocity = Vector3.ZERO
	if _visual != null and _visual.has_method("teleported"):
		_visual.call("teleported")
	if _visual != null and _visual.has_method("stop_emote"):
		_visual.call("stop_emote")
	# Springs, plant locks and the previous-frame caches all have to be
	# discarded or the first frames of every segment measure the teleport.
	_have_prev_foot = false
	_prev_bone_rotations.clear()
	_prev_velocity = Vector3.ZERO
	_prev_accel = Vector3.ZERO
	_prev_position = segment.start
	_settle = SETTLE_FRAMES
	if segment.emote != "" and _visual != null and _visual.has_method("play_emote"):
		_visual.call("play_emote", segment.emote)


## Hold the segment's actions through the `Input` singleton — the same path a
## real keyboard takes, so the harness cannot accidentally test a code path the
## player never reaches.
func _drive(segment: Segment, delta: float) -> void:
	_heading += segment.heading_rate * delta
	if _rig != null:
		_rig.rotation.y = _heading
	for action in segment.actions:
		var name: StringName = StringName(action)
		if InputMap.has_action(name):
			Input.action_press(name, float(segment.actions[action]))
			_held[name] = true
	if segment.jump_period > 0.0:
		_jump_timer += delta
		if _jump_timer >= segment.jump_period:
			_jump_timer = 0.0
			Input.action_press(&"jump")
			_held[&"jump"] = true
		elif _jump_timer > 0.1 and Input.is_action_pressed(&"jump"):
			Input.action_release(&"jump")


func _release_all() -> void:
	for action in _held:
		Input.action_release(action as StringName)
	_held.clear()


## Take every measurement for this frame.
func _sample(stats: SegmentStats, delta: float) -> void:
	stats.frames += 1
	var position: Vector3 = _player.global_position
	var travelled: Vector3 = position - _prev_position
	_prev_position = position
	travelled.y = 0.0
	stats.distance += travelled.length()
	stats.speed_total += Vector2(_player.velocity.x, _player.velocity.z).length()

	# Body jerk: third derivative, the standard smoothness measure.
	var velocity: Vector3 = _player.velocity
	var accel: Vector3 = (velocity - _prev_velocity) / maxf(delta, 0.0001)
	var jerk: Vector3 = (accel - _prev_accel) / maxf(delta, 0.0001)
	_prev_velocity = velocity
	_prev_accel = accel
	stats.body_jerk_total += jerk.length()

	if _skeleton == null:
		return

	var animator: Object = _visual.get("animator") if _visual != null else null
	if animator != null:
		_solver_samples += 1
		var shortfall: float = float(animator.get("ik_tip_error"))
		_solver_shortfall_mm += (shortfall * 1000.0 - _solver_shortfall_mm) \
			/ float(_solver_samples)
		if bool(animator.get("ik_clamped")):
			_solver_clamped_frames += 1
	# `stance`, not `contact`: contact ramps up before touchdown so the IK eases
	# in, so it is true for the last few frames of a swing while the foot is
	# still travelling at full speed. Measuring slip on `contact` counted that
	# honest swing motion as sliding and inflated every figure this harness
	# produced by roughly a factor of three.
	var planted: Array[bool] = [false, false]
	var wanted: Array = [Vector3.ZERO, Vector3.ZERO]
	var have_wanted: bool = false
	if animator != null and animator.get("feet") != null:
		var feet: Array = animator.get("feet")
		have_wanted = feet.size() >= 2
		for i in mini(feet.size(), 2):
			planted[i] = bool((feet[i] as Object).get("stance"))
			wanted[i] = (feet[i] as Object).get("world_position")

	# --- Foot slip and ground error ---
	# Slip is measured at the INSTANTANEOUS GROUND-CONTACT POINT, over the whole
	# stance. That point is the heel while the toes are up, the toe once the
	# heel has lifted, and the middle of the sole in between — and for a foot
	# that is correctly pivoting rather than sliding, it is stationary in all
	# three cases. Measuring the sole's centre instead (as the first version
	# did) reports honest heel-and-toe roll as slip, which made a crouch-walk
	# with almost no roll look ten times worse than a normal walk.
	for i in 2:
		var bone_name: String = "FootR" if i == 1 else "FootL"
		var idx: int = _bones.get(bone_name, -1)
		if idx < 0:
			continue
		var foot_transform: Transform3D = _skeleton.global_transform \
			* _skeleton.get_bone_global_pose(idx)
		var ankle_world: Vector3 = foot_transform.origin
		# Did the leg actually reach where it was told to stand? Compared
		# against the solver's OWN reported shortfall below, this says whether
		# the gap is the IK giving up or the skeleton not landing on the
		# solution the IK returned.
		if have_wanted and planted[i]:
			var reach_miss: float = ankle_world.distance_to(wanted[i])
			stats.ik_error_total += reach_miss
			stats.ik_error_max = maxf(stats.ik_error_max, reach_miss)
			stats.ik_samples += 1
		var probe: Dictionary = _ground_probe(ankle_world)
		var regime: int = _contact_regime(foot_transform, probe["normal"])
		var contact_world: Vector3 = foot_transform \
			* _regime_point_local(regime)
		if _tracing and i == 0 and _trace_left > 0 and planted[i]:
			_trace_left -= 1
			var heel_pt: Vector3 = foot_transform * Vector3(0.0, -_ankle_rest_y,
				HEEL_BEHIND)
			var toe_pt: Vector3 = foot_transform * Vector3(0.0, -_ankle_rest_y,
				-TOE_AHEAD)
			var fwd: Vector3 = -foot_transform.basis.z.normalized()
			var asked: Vector3 = (animator.get("ik_target_world") as Array)[i]
			var got: Vector3 = (animator.get("ik_solved_world") as Array)[i]
			print("TRACE bone=(%.4f,%.4f) asked=(%.4f,%.4f) solved=(%.4f,%.4f) planter=(%.4f,%.4f)" % [
				ankle_world.z, ankle_world.y, asked.z, asked.y,
				got.z, got.y, wanted[i].z, wanted[i].y])
		# Only compare within a single regime. Across a heel-to-toe changeover
		# the sampled point legitimately moves to the other end of the foot,
		# and counting that would report a 220 mm teleport every stride.
		var comparable: bool = _have_prev_foot and regime == _prev_regime[i]
		if comparable and planted[i]:
			var drift: Vector3 = contact_world - _prev_foot_world[i]
			drift.y = 0.0
			var slip: float = drift.length()
			stats.slip_total += slip
			stats.slip_max = maxf(stats.slip_max, slip)
			stats.slip_by_regime[regime] += slip
			stats.planted_frames += 1
			# Ground error: how far the sole sits off the real surface.
			var error: float = (ankle_world.y - float(probe["y"])) - _ankle_rest_y
			stats.ground_error_total += absf(error)
			stats.ground_error_max = maxf(stats.ground_error_max, absf(error))
		_prev_foot_world[i] = contact_world
		_prev_regime[i] = regime
	_have_prev_foot = true

	# --- Knee direction: the knee must sit FORWARD of the hip-ankle line ---
	for i in 2:
		var suffix: String = "R" if i == 1 else "L"
		var hip: int = _bones.get("Thigh" + suffix, -1)
		var knee: int = _bones.get("Shin" + suffix, -1)
		var ankle: int = _bones.get("Foot" + suffix, -1)
		if hip < 0 or knee < 0 or ankle < 0:
			continue
		var hip_p: Vector3 = _skeleton.get_bone_global_pose(hip).origin
		var knee_p: Vector3 = _skeleton.get_bone_global_pose(knee).origin
		var ankle_p: Vector3 = _skeleton.get_bone_global_pose(ankle).origin
		# Project the knee onto the straight hip-to-ankle line and look at which
		# side it bulges to. Model forward is -Z, so a correct knee sits at
		# NEGATIVE Z of that line and a hyperextended one at positive Z.
		# (Comparing against the midpoint instead, as the first version did,
		# just measures the leg's overall pitch and flags a perfectly good
		# stance leg.)
		var axis: Vector3 = ankle_p - hip_p
		var along: float = 0.5
		if axis.length_squared() > 0.000001:
			along = clampf((knee_p - hip_p).dot(axis) / axis.length_squared(),
				0.0, 1.0)
		var on_line: Vector3 = hip_p + axis * along
		# 4 mm of tolerance: a near-straight leg has no meaningful bend side.
		if knee_p.z - on_line.z > 0.004:
			stats.knee_backward_frames += 1

	# --- Pose jerk: the largest single-frame bone rotation ---
	var worst: float = 0.0
	for bone_name in _bones:
		var idx: int = _bones[bone_name]
		var rotation: Quaternion = _skeleton.get_bone_pose_rotation(idx)
		if _prev_bone_rotations.has(bone_name):
			var previous: Quaternion = _prev_bone_rotations[bone_name]
			var angle: float = previous.angle_to(rotation) / maxf(delta, 0.0001)
			worst = maxf(worst, angle)
		_prev_bone_rotations[bone_name] = rotation
	stats.pose_jerk_max = maxf(stats.pose_jerk_max, worst)

	# --- Head height envelope: the camera-visible bob ---
	var head_idx: int = _bones.get("Head", -1)
	if head_idx >= 0:
		var head_y: float = (_skeleton.global_transform
			* _skeleton.get_bone_global_pose(head_idx).origin).y - position.y
		stats.head_y_min = minf(stats.head_y_min, head_y)
		stats.head_y_max = maxf(stats.head_y_max, head_y)


## Which part of the foot is bearing the load right now: 0 heel, 1 whole sole,
## 2 toe. Read from the rendered bone basis, so the harness stays an
## independent check on the animation rather than a restatement of it.
## `surface_normal` is the normal of the ground under the foot. Pitch is
## measured against THAT, not against world up: on a ramp a foot lying flat on
## the slope is still flat, and testing it against world up would classify
## every downhill step as a toe-strike.
func _contact_regime(foot_transform: Transform3D,
		surface_normal: Vector3) -> int:
	# Model forward is -Z; a positive component along the surface normal means
	# the toes are raised off the surface.
	var forward: Vector3 = -foot_transform.basis.z.normalized()
	var pitch: float = asin(clampf(forward.dot(surface_normal.normalized()),
		-1.0, 1.0))
	if pitch > FLAT_PITCH_EPSILON:
		return 0
	if pitch < -FLAT_PITCH_EPSILON:
		return 2
	return 1


## The point that must hold still in each regime, in the FOOT bone's local
## frame: the heel while the toes are up, the toe once the heel has lifted, and
## the ankle itself while the sole is flat (a flat foot must not move at all).
##
## Measuring the right point per regime is essential. A single fixed sample
## point reports the foot's honest heel-and-toe rocker as sliding, and a sample
## that slides continuously between heel and toe reports the changeover as a
## 200 mm teleport — both of which this harness did before, and both of which
## sent the tuning after problems the animation did not have.
func _regime_point_local(regime: int) -> Vector3:
	match regime:
		0: return Vector3(0.0, -_ankle_rest_y, HEEL_BEHIND)
		2: return Vector3(0.0, -_ankle_rest_y, -TOE_AHEAD)
		_: return Vector3.ZERO


## Height and normal of the collision surface beneath a point. One probe per
## foot per frame feeds both the ground-error measurement and the contact-regime
## test, which need the same surface.
func _ground_probe(foot_world: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		foot_world + Vector3.UP * 1.0, foot_world + Vector3.DOWN * 1.5)
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {"y": foot_world.y - _ankle_rest_y, "normal": Vector3.UP}
	return {"y": (hit["position"] as Vector3).y,
		"normal": (hit["normal"] as Vector3).normalized()}


func _save_shot(label: String) -> void:
	if _out_dir == "":
		return
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		return
	_shots_saved += 1
	image.save_png(_out_dir.path_join("frame_%03d_%s.png" % [_shots_saved, label]))


# --- Report ------------------------------------------------------------------

func _finish() -> void:
	_finished = true
	_release_all()
	_print_table()
	_write_json()
	get_tree().quit()


func _print_table() -> void:
	print("")
	print("=== LOCOMOTION LAB ===")
	print("%-16s %7s %9s %9s %9s %8s %8s %8s %7s" % ["segment", "speed",
		"slip/m mm", "slipmax mm", "grounderr", "ikerr mm", "posejerk",
		"bodyjerk", "kneebk"])
	var totals: Dictionary = {"slip": 0.0, "distance": 0.0, "knee": 0,
		"ground": 0.0, "planted": 0, "jerk": 0.0}
	for entry in _stats:
		var s: SegmentStats = entry
		print("%-16s %7.2f %9.2f %10.2f %9.2f %8.2f %8.1f %8.0f %7d" % [
			s.name, s.mean_speed(), s.slip_per_metre_mm(), s.slip_max * 1000.0,
			s.mean_ground_error_mm(), s.mean_ik_error_mm(), s.pose_jerk_max,
			s.mean_body_jerk(), s.knee_backward_frames])
		totals["slip"] = float(totals["slip"]) + s.slip_total
		totals["distance"] = float(totals["distance"]) + s.distance
		totals["knee"] = int(totals["knee"]) + s.knee_backward_frames
		totals["ground"] = float(totals["ground"]) + s.ground_error_total
		totals["planted"] = int(totals["planted"]) + s.planted_frames
		totals["jerk"] = maxf(float(totals["jerk"]), s.pose_jerk_max)
	var overall_slip: float = 0.0
	if float(totals["distance"]) > 0.01:
		overall_slip = float(totals["slip"]) / float(totals["distance"]) * 1000.0
	var overall_ground: float = 0.0
	if int(totals["planted"]) > 0:
		overall_ground = float(totals["ground"]) / float(totals["planted"]) * 1000.0
	# Where the slip actually happens, summed across the whole run.
	var heel: float = 0.0
	var flat: float = 0.0
	var toe: float = 0.0
	for entry in _stats:
		var s: SegmentStats = entry
		heel += s.slip_by_regime[0]
		flat += s.slip_by_regime[1]
		toe += s.slip_by_regime[2]
	print("")
	print("slip by contact: heel %.3f m | flat sole %.3f m | toe %.3f m" % [
		heel, flat, toe])
	print("solver shortfall: %.2f mm mean, clamped on %.1f%% of frames" % [
		_solver_shortfall_mm, 100.0 * _solver_clamped_frames
			/ maxf(1.0, float(_solver_samples))])
	print("OVERALL slip %.2f mm/m | ground error %.2f mm | worst pose jerk %.1f rad/s | backward-knee frames %d" % [
		overall_slip, overall_ground, float(totals["jerk"]), int(totals["knee"])])
	print("======================")


func _write_json() -> void:
	if _out_dir == "":
		return
	var rows: Array = []
	for entry in _stats:
		var s: SegmentStats = entry
		rows.append({
			"segment": s.name,
			"frames": s.frames,
			"distance_m": s.distance,
			"mean_speed": s.mean_speed(),
			"slip_per_metre_mm": s.slip_per_metre_mm(),
			"slip_max_mm": s.slip_max * 1000.0,
			"ground_error_mean_mm": s.mean_ground_error_mm(),
			"ground_error_max_mm": s.ground_error_max * 1000.0,
			"pose_jerk_max": s.pose_jerk_max,
			"body_jerk_mean": s.mean_body_jerk(),
			"knee_backward_frames": s.knee_backward_frames,
			"head_bob_mm": (s.head_y_max - s.head_y_min) * 1000.0
				if s.head_y_max > -1e8 else 0.0,
		})
	var file: FileAccess = FileAccess.open(
		_out_dir.path_join("locomotion_metrics.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"segments": rows}, "  "))
		file.close()
		print("LocomotionLab: wrote ", _out_dir.path_join("locomotion_metrics.json"))

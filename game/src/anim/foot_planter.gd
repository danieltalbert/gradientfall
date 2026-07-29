class_name FootPlanter
extends RefCounted
## Puts a creature's feet on the actual ground: per-foot terrain probes, a world
## plant-lock that survives the body turning, ankle alignment to the surface
## normal, and the pelvis drop that keeps both legs inside their reach.
##
## **Why this exists.** `gait_engine.gd` guarantees a planted foot holds still
## relative to the BODY, which removes foot slip on flat ground. It knows
## nothing about the world: on Datasedge Meadows' heightmap the same perfect
## stride still floats a foot over a dip and buries one in a rise. This class
## closes that gap by raycasting the real collision world under each foot and
## correcting the gait's ideal target onto the surface it finds.
##
## **The plant lock.** Once a foot touches down its WORLD position is recorded
## and held for the rest of the stance. That is stricter than the gait alone:
## it also kills the slip that appears when the body rotates under a planted
## foot (turning on the spot used to drag both feet sideways through the
## ground). The lock has a leash — beyond `MAX_LEASH` metres the foot gives up
## and slides to the new spot, which is exactly the scuffing pivot a person
## makes when they spin in place, so the failure mode is itself correct.
##
## **Architecture.** Needs a node for its physics-space handle but owns no
## nodes; depends on `anim_math.gd` and `gait_engine.gd`. Consumed by
## `creature_animator.gd`, and reusable by any legged creature — a quadruped
## makes four instances. See `docs/ARCHITECTURE.md` § "Procedural animation".

const AM: GDScript = preload("res://src/anim/anim_math.gd")

## How far above the ideal foot position the probe ray starts, metres. Must
## clear the tallest step the creature can walk up.
const PROBE_UP: float = 0.85

## How far below it the probe ray reaches, metres. Sets how deep a hole the
## foot will still try to reach into before giving up and staying airborne.
const PROBE_DOWN: float = 1.25

## Metres a locked foot may be dragged before it releases and re-plants.
const MAX_LEASH: float = 0.42

## Half-life for the pelvis following the terrain, seconds. Slower than the
## feet on purpose: the hips of a person walking over rough ground lag the
## ankles, and matching them exactly makes the whole body jitter.
const PELVIS_HALF_LIFE: float = 0.085

## Half-life for a foot's ground height easing while airborne — stops a foot
## from snapping when it swings out over a cliff edge.
const AIR_HALF_LIFE: float = 0.06

## Steepest surface (radians from horizontal) the ankle will still align to.
## Beyond this the foot keeps a level-ish pose rather than standing on edge.
const MAX_ALIGN_ANGLE: float = 0.72


## Everything known about one foot this frame.
class FootGround:
	extends RefCounted

	## True when the probe found a surface at all.
	var found: bool = false
	## World position the foot should occupy, after probing and locking.
	var world_position: Vector3 = Vector3.ZERO
	## Surface normal under the foot, world space.
	var normal: Vector3 = Vector3.UP
	## Height of the surface under the foot, world space.
	var ground_y: float = 0.0
	## How planted this foot is, 0..1 — copied through from the gait so the IK
	## and the ankle alignment fade together.
	var contact: float = 0.0
	## True while the world lock is holding this foot in place.
	var locked: bool = false
	## True while this foot is in STANCE — genuinely bearing load on the ground.
	##
	## Distinct from `contact`, which deliberately ramps up during the last
	## fraction of the swing so that foot IK and surface alignment ease in
	## before touchdown rather than snapping on. Anything asking "is this foot
	## planted right now" — footstep audio, dust, slip measurement — must use
	## THIS, not `contact`, or it fires while the foot is still travelling.
	var stance: bool = false


## Per-foot persistent state.
var _lock_position: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _locked: Array[bool] = [false, false]
var _ground_y: Array[float] = [0.0, 0.0]
var _normal: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _ground_valid: Array[bool] = [false, false]

## Smoothed pelvis vertical correction, metres (never positive — the pelvis
## only ever drops to keep the lower foot reachable).
var pelvis_offset: float = 0.0

var _space: PhysicsDirectSpaceState3D
var _mask: int = 1
var _exclude: Array[RID] = []


## Bind to a physics world. `owner_node` supplies the space; `collision_mask`
## should be the world/terrain layer; `exclude` keeps the creature's own
## collider from being probed (otherwise every foot lands on the capsule).
func setup(owner_node: Node3D, collision_mask: int,
		exclude: Array[RID]) -> void:
	_space = owner_node.get_world_3d().direct_space_state
	_mask = collision_mask
	_exclude = exclude


## Drop the lock and the smoothing — call on teleport/respawn so the feet do
## not stretch back toward wherever the creature used to be standing.
func reset() -> void:
	_locked = [false, false]
	_ground_valid = [false, false]
	pelvis_offset = 0.0


## Probe and resolve one foot.
##
## `index` is 0 (left) or 1 (right). `ideal_world` is where the gait wants the
## ANKLE JOINT, already in world space. `contact` is the gait's contact weight.
## `sole_offset` is how far the ankle joint sits above the sole of the foot in
## metres — without it the solver drives the ankle onto the surface and buries
## the whole foot in the ground. `lift` is the gait's requested clearance above
## the surface. Returns the resolved ground state.
func resolve(index: int, ideal_world: Vector3, contact: float, delta: float,
		sole_offset: float, lift: float, flat: float) -> FootGround:
	var out: FootGround = FootGround.new()
	out.contact = contact

	if _space == null:
		out.world_position = ideal_world
		return out

	# Probe straight down through the ideal position.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ideal_world + Vector3.UP * PROBE_UP,
		ideal_world + Vector3.DOWN * PROBE_DOWN)
	query.collision_mask = _mask
	query.exclude = _exclude
	var hit: Dictionary = _space.intersect_ray(query)

	if hit.is_empty():
		# Nothing under the foot (a ledge, a gap). Keep the last known height
		# and let the foot hang at the gait's ideal — the air pose owns it.
		out.found = false
		_ground_valid[index] = false
		out.ground_y = _ground_y[index]
		out.normal = _normal[index]
	else:
		out.found = true
		_ground_valid[index] = true
		var hit_y: float = (hit["position"] as Vector3).y
		# Ease the sampled height while the foot is in the air so swinging out
		# over a step change does not snap the ankle.
		_ground_y[index] = AM.damp(_ground_y[index], hit_y,
			AIR_HALF_LIFE * (1.0 - contact), delta) if contact < 0.999 else hit_y
		_normal[index] = AM.damp_vec3(_normal[index],
			(hit["normal"] as Vector3).normalized(), 0.06, delta).normalized()
		out.ground_y = _ground_y[index]
		out.normal = _normal[index]

	# The ankle rides `sole_offset` above the surface (so the SOLE touches it),
	# plus whatever swing clearance the gait asked for.
	var target: Vector3 = ideal_world
	if _ground_valid[index]:
		target.y = out.ground_y + sole_offset + maxf(0.0, lift)

	# --- Plant lock ---------------------------------------------------------
	# Keyed on FLATNESS, not contact. During the heel and toe pivots the ankle
	# is meant to travel through the world, so locking it there would fight the
	# gait and stiffen the roll into a stilt-walk. Only the flat-foot middle of
	# the stance is genuinely pinned.
	if flat > 0.02:
		if not _locked[index]:
			_locked[index] = true
			_lock_position[index] = target
		else:
			# Leash: a foot dragged too far gives up and re-plants, which is the
			# scuff a person makes pivoting on the spot.
			var drift: Vector3 = target - _lock_position[index]
			drift.y = 0.0
			if drift.length() > MAX_LEASH:
				_lock_position[index] += drift.normalized() \
					* (drift.length() - MAX_LEASH)
			# Vertical always tracks the surface, so a foot planted on a moving
			# or deforming surface does not sink into it.
			_lock_position[index].y = target.y
		out.world_position = target.lerp(_lock_position[index], flat)
		out.locked = flat > 0.5
	else:
		_locked[index] = false
		out.world_position = target
		out.locked = false

	return out


## Ankle alignment for a planted foot, as a model-space rotation to compose
## onto the gait's ankle pose.
##
## `up_model` is the creature's own up axis expressed in model space (normally
## +Y) and `normal_model` is the surface normal brought into the same space.
## The rotation is scaled by contact so a foot only conforms while it is
## actually on the ground, and capped at `MAX_ALIGN_ANGLE` so a foot near a
## cliff face does not stand vertically.
static func align_to_surface(up_model: Vector3, normal_model: Vector3,
		contact: float) -> Quaternion:
	var from: Vector3 = up_model.normalized()
	var to: Vector3 = normal_model.normalized()
	var dot: float = clampf(from.dot(to), -1.0, 1.0)
	var angle: float = acos(dot)
	if angle < 0.0005 or contact <= 0.001:
		return Quaternion.IDENTITY
	angle = minf(angle, MAX_ALIGN_ANGLE) * clampf(contact, 0.0, 1.0)
	var axis: Vector3 = from.cross(to)
	if axis.length_squared() < 0.000001:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), angle)


## How far the pelvis must drop so BOTH feet stay inside their legs' reach.
##
## `hip_world_y` is where the hip joint currently sits, `feet` are the resolved
## foot states, and `leg_reach` is the usable hip-to-ankle length (already
## shortened so the knee never locks straight). The result is smoothed and
## clamped to `max_drop`, and is never positive — a creature lifts its body by
## straightening its legs, not by floating upward.
func update_pelvis(hip_world_y: float, feet: Array, leg_reach: float,
		max_drop: float, delta: float) -> float:
	var needed: float = 0.0
	for entry in feet:
		var ground: FootGround = entry
		if not ground.found or ground.contact <= 0.01:
			continue
		# How far below the hip this foot sits, versus how far the leg reaches.
		var drop_to_foot: float = hip_world_y - ground.world_position.y
		var excess: float = drop_to_foot - leg_reach
		if excess > 0.0:
			needed = minf(needed, -excess)
	needed = maxf(needed, -absf(max_drop))
	pelvis_offset = AM.damp(pelvis_offset, needed, PELVIS_HALF_LIFE, delta)
	return pelvis_offset

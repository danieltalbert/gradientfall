class_name TreeClimb
extends Node
## Kern climbing trees.
##
## Danny, 2026-08-03: "Kern should be able to climb some of them." *Some* is the
## operative word — a meadow where every sapling is a ladder is a meadow with no
## decisions in it. Only trunks tall and thick enough to be worth the trip are
## marked climbable when the copses are planted (see `MeadowFlora._plant_copses`),
## which makes reaching a particular canopy a small piece of route-finding
## rather than a button that always works.
##
## How it plays: walk up to a marked trunk, press the interact key, and Kern
## takes hold. Forward and back run him up and down; left and right carry him
## around the trunk, so he can round it to reach a bough on the far side. Jump
## lets go with a shove outward — the only exit, and deliberately committal.
##
## Where it sits: a child component of `Player`, ticked from its
## `_physics_process` alongside `Swimmer`, and checked FIRST — a tree in a pond
## should be a tree, not a swim.
##
## Physics while climbing is authored rather than simulated: the body is placed
## on a cylinder around the trunk each frame. Trying to do this with forces
## against a capsule collider is how climbing systems end up jittering.

## Vertical climb rate, m/s. Slower than a walk — climbing is work, and the pace
## is most of what sells the height when Kern finally looks down.
const CLIMB_SPEED: float = 1.75
## How fast Kern circles the trunk, radians/s.
const ORBIT_SPEED: float = 1.5
## Gap held between the trunk surface and Kern's centre, metres.
const HUG_GAP: float = 0.34
## How close he must be to a trunk to take hold, metres, measured horizontally
## from the trunk's axis.
const REACH: float = 1.5
## How squarely he must be facing the trunk to grab it. 0.35 is generous —
## about 70 degrees off dead-on — because fighting the camera to grab a tree is
## nobody's idea of fun.
const FACING_DOT: float = 0.35
## Where the climb stops: this far below the first boughs, so Kern ends up
## standing in the crown rather than clipping through it.
const TOP_MARGIN: float = 0.55
## Push-off when he lets go.
const LEAP_OUT: float = 3.4
const LEAP_UP: float = 3.9

signal climb_changed(climbing: bool)

## True while Kern is on a trunk.
var is_climbing: bool = false

var _player: CharacterBody3D
## The tree currently held, or null.
var _tree: Node3D
var _base: Vector3 = Vector3.ZERO
var _radius: float = 0.5
var _top: float = 0.0
## Height up the trunk, metres, and the angle around it, radians.
var _height: float = 0.0
var _angle: float = 0.0
var _told_once: bool = false


func setup(player: CharacterBody3D) -> void:
	_player = player


## Advance the climb. Returns true if it took over movement this frame, in which
## case the controller must not apply gravity or ground steering.
func tick(delta: float, wish_forward: float, wish_side: float) -> bool:
	if _player == null:
		return false

	if not is_climbing:
		if Input.is_action_just_pressed(&"interact"):
			var found: Node3D = _reachable_tree()
			if found != null:
				_grab(found)
				return true
		return false

	if _tree == null or not is_instance_valid(_tree):
		_release(false)          # the tree went away under him
		return false

	if Input.is_action_just_pressed(&"jump"):
		_release(true)
		return false

	_height = clampf(_height + wish_forward * CLIMB_SPEED * delta, 0.0, _top)
	_angle = wrapf(_angle - wish_side * ORBIT_SPEED * delta, -PI, PI)

	# Sliding back down off the bottom is a dismount, not a stop — otherwise
	# Kern stands at ground level still hugging the tree, which reads as stuck.
	if _height <= 0.001 and wish_forward < 0.0:
		_release(false)
		return false

	var out: Vector3 = Vector3(cos(_angle), 0.0, sin(_angle))
	_player.global_position = _base + Vector3.UP * _height + out * (_radius + HUG_GAP)
	_player.velocity = Vector3.ZERO
	# Face the trunk: model forward is -Z, so looking along -out is atan2(out.x,
	# out.z). The body carries its own yaw (it is set once at spawn and never
	# again — all steering happens on the Visual child), so the body's rotation
	# has to come back out or Kern hugs the tree facing sideways.
	_player.get_node("Visual").rotation.y = atan2(out.x, out.z) - _player.rotation.y
	return true


## The nearest climbable trunk Kern is close enough to and facing, or null.
func _reachable_tree() -> Node3D:
	var best: Node3D = null
	var best_distance: float = REACH
	var here: Vector3 = _player.global_position
	var facing: Vector3 = -_player.get_node("Visual").global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		return null
	facing = facing.normalized()

	for node in _player.get_tree().get_nodes_in_group(&"climbable"):
		var tree: Node3D = node as Node3D
		if tree == null:
			continue
		var to_tree: Vector3 = tree.global_position - here
		# Only the horizontal gap matters; a trunk is a vertical line.
		var flat: Vector3 = Vector3(to_tree.x, 0.0, to_tree.z)
		var gap: float = flat.length() - float(tree.get_meta("climb_radius", 0.5))
		if gap > best_distance or gap < -0.6:
			continue
		if flat.length_squared() < 0.001:
			continue
		if facing.dot(flat.normalized()) < FACING_DOT:
			continue
		best_distance = gap
		best = tree
	return best


func _grab(tree: Node3D) -> void:
	_tree = tree
	_radius = float(tree.get_meta("climb_radius", 0.5))
	_top = maxf(0.6, float(tree.get_meta("climb_height", 3.0)) - TOP_MARGIN)
	_base = tree.global_position
	var to_kern: Vector3 = _player.global_position - _base
	_angle = atan2(to_kern.z, to_kern.x)
	# Start a little off the ground so the first press already reads as progress.
	_height = clampf(_player.global_position.y - _base.y + 0.35, 0.35, _top)
	is_climbing = true
	_player.velocity = Vector3.ZERO
	climb_changed.emit(true)
	if not _told_once:
		_told_once = true
		EventBus.bit_spoke.emit(
			"Up we go! Mind you, I could have just flown. I am only saying.", "reaction")


func _release(leaping: bool) -> void:
	if not is_climbing:
		return
	is_climbing = false
	if leaping and _player != null:
		var out: Vector3 = Vector3(cos(_angle), 0.0, sin(_angle))
		_player.velocity = out * LEAP_OUT + Vector3.UP * LEAP_UP
	_tree = null
	climb_changed.emit(false)

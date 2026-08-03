class_name Swimmer
extends Node
## Kern in water — floating, stroking, and **the Deep**.
##
## Danny's rule (2026-08-03): Kern may swim anywhere, but open water outside a
## named safe zone slowly costs hearts, so the player is pulled back toward
## land. It is not a wall and not a drowning timer: a full-health Kern gets
## roughly forty seconds of open sea, which is enough to gamble on something he
## can see and not enough to cross to it. That is how the GDD's "no hard gates"
## pillar survives having an ocean — the sea is a *soft* gate made of danger,
## exactly like a high-tier monster is.
##
## Which water is safe comes from `WorldAtlas.SAFE_WATER` — the Convolution
## shelf and its islands, the Kernel Reef, Window Flats, the Old Millpond, and
## the Ledger's canal in the capital. Adding more is one entry in that table,
## never a change here.
##
## **What Kern can actually reach today:** only the Old Millpond, which is safe
## water. The sea exists as a border vista, not as geometry, so the Deep's drain
## cannot yet be triggered by walking into it — it is exercised headlessly by
## `src/dev/atlas_audit.gd` instead. The moment the coast is built, this works
## with no changes.
##
## Where it sits: a child component of `Player`, ticked from its
## `_physics_process` like `PlayerCombat`. It owns the decision ("is he
## swimming, is this the Deep") and the consequences (buoyancy target, drain,
## Bit's reaction); the controller owns the capsule.

## Stroke speed, m/s. Deliberately below a jog: swimming should feel like a
## commitment, and the walk back around a lake should look attractive.
const SWIM_SPEED: float = 2.35
## How fast the stroke accelerates and decays in water, m/s^2. Water has no
## grip, so both are far lower than on the ground.
const SWIM_ACCEL: float = 6.0
const SWIM_DECEL: float = 3.2

## Submersion at which Kern stops wading and starts swimming, metres measured
## from his feet. Chest-deep: below this he is walking in water.
const SWIM_ENTER_DEPTH: float = 1.15
## Submersion at which he can stand up again. Lower than SWIM_ENTER_DEPTH so
## the state does not flutter on a wave or a slope.
const SWIM_EXIT_DEPTH: float = 0.85
## Where the feet settle relative to the surface while floating. Kern rides with
## his shoulders out, which is what makes the surface readable from behind.
const FLOAT_DEPTH: float = 1.30
## Buoyancy stiffness, per second. Firm enough to surface a jump-in quickly,
## soft enough not to pop.
const BUOYANCY: float = 5.5
## Terminal sink/rise speed in water, m/s — water damps everything.
const WATER_DAMP: float = 4.5
## Held crouch dives; this is how fast, m/s.
const DIVE_SPEED: float = 2.2

## Hearts are applied in whole ticks rather than continuously, because
## `Health.apply()` opens an i-frame window on every hit. One second is longer
## than Kern's 0.5 s window, so every tick lands.
const DRAIN_TICK: float = 1.0

signal swim_changed(swimming: bool)
signal deep_changed(in_deep: bool)

## True while Kern is off the bottom and stroking.
var is_swimming: bool = false
## True while he is in unsafe open water and the drain is either counting down
## or already running.
var in_deep: bool = false

var _player: CharacterBody3D
var _terrain: MeadowTerrain
var _deep_time: float = 0.0
var _drain_time: float = 0.0
var _warned: bool = false


## Bind to the player and the terrain that answers water questions. The terrain
## is optional so a swimmer on a region with no water yet simply never fires.
func setup(player: CharacterBody3D, terrain: MeadowTerrain) -> void:
	_player = player
	_terrain = terrain


## Advance the swim state. Returns true if the swimmer took over movement this
## frame, in which case the controller must not apply its own gravity or ground
## steering.
func tick(delta: float, wish: Vector3, wish_strength: float) -> bool:
	if _player == null or _terrain == null:
		return false

	var surface: float = _surface_at(_player.global_position)
	var submersion: float = surface - _player.global_position.y
	var threshold: float = SWIM_EXIT_DEPTH if is_swimming else SWIM_ENTER_DEPTH
	var wants_swim: bool = submersion > threshold

	if wants_swim != is_swimming:
		is_swimming = wants_swim
		swim_changed.emit(is_swimming)
		if is_swimming:
			_announce_entry()
		else:
			_leave_deep()

	if not is_swimming:
		return false

	_stroke(delta, surface, wish, wish_strength)
	_tick_deep(delta)
	return true


## The water surface height at a world position, or a value far below the world
## when there is no water there. One place asks the terrain; everything else
## asks this.
func _surface_at(at: Vector3) -> float:
	if _terrain.is_deep_water(at.x, at.z):
		return _terrain.water_level
	return -1000.0


## Float toward the surface and stroke horizontally. Buoyancy is a critically
## damped pull rather than a hard snap, so entering the water from a height
## sinks convincingly before he bobs back up.
func _stroke(delta: float, surface: float, wish: Vector3, wish_strength: float) -> void:
	var target_y: float = surface - FLOAT_DEPTH
	var lift: float = (target_y - _player.global_position.y) * BUOYANCY
	if Input.is_action_pressed(&"crouch"):
		lift = -DIVE_SPEED           # hold crouch to duck under
	_player.velocity.y = clampf(lift, -WATER_DAMP, WATER_DAMP)

	var horizontal: Vector2 = Vector2(_player.velocity.x, _player.velocity.z)
	var target: Vector2 = Vector2(wish.x, wish.z) * SWIM_SPEED * wish_strength
	var rate: float = SWIM_ACCEL if wish_strength > 0.05 else SWIM_DECEL
	horizontal = horizontal.move_toward(target, rate * delta)
	_player.velocity.x = horizontal.x
	_player.velocity.z = horizontal.y


## The Deep: count the grace, then bleed hearts on a steady tick.
func _tick_deep(delta: float) -> void:
	var km: Vector2 = WorldAtlas.local_to_km(
		&"datasedge_meadows", _player.global_position.x, _player.global_position.z)
	var unsafe: bool = not WorldAtlas.is_safe_water(km)
	if not unsafe:
		_leave_deep()
		return

	if not in_deep:
		in_deep = true
		deep_changed.emit(true)

	_deep_time += delta
	if _deep_time < WorldAtlas.DEEP_GRACE_SEC:
		return

	# The warning fires once, the moment the grace runs out, so crossing a river
	# mouth never triggers it and committing to open water always does.
	if not _warned:
		_warned = true
		EventBus.bit_spoke.emit(
			"Kern — KERN. This is open water and it does not like us. Back to the shore, "
			+ "please, while there is still a shore to go back to.", "warning")

	_drain_time += delta
	while _drain_time >= DRAIN_TICK:
		_drain_time -= DRAIN_TICK
		var health: Health = _player.get_node_or_null("Health") as Health
		if health != null:
			health.apply(WorldAtlas.DEEP_DRAIN_PER_SEC * DRAIN_TICK,
					_player.global_position)


func _leave_deep() -> void:
	if in_deep:
		in_deep = false
		deep_changed.emit(false)
	_deep_time = 0.0
	_drain_time = 0.0
	_warned = false


## Bit says something on entry — he is canonically afraid of deep water, so this
## costs nothing to justify and it tells the player the state changed.
func _announce_entry() -> void:
	var km: Vector2 = WorldAtlas.local_to_km(
		&"datasedge_meadows", _player.global_position.x, _player.global_position.z)
	var zone: Dictionary = WorldAtlas.safe_water_at(km)
	if zone.is_empty():
		return
	EventBus.bit_spoke.emit(
		"You are IN it. In %s. Voluntarily." % zone["name"], "reaction")

class_name Player
extends CharacterBody3D
## Kern's third-person character controller — Phase 1 milestone 2, rebuilt in
## the movement pass.
##
## **Feel targets.** Analog speed with no gait thresholds (the stick's
## deflection IS the speed, and walk/jog/run/sprint blend continuously),
## responsive starts, no ice on stop, a BOTW-ish jump arc (floatier rise,
## heavier fall, early-release cut), coyote time and a jump buffer so hops are
## never stolen, camera-relative movement, turning that costs speed the way
## real momentum does, slope-aware pace, and step-up over small ledges.
##
## **What moved out.** The old version faked weight with a squash/stretch tween
## on the visual. The body's actual behaviour — landing absorption, crouch
## depth, momentum lean — now lives in `creature_animator.gd` and is driven by
## real physics state, so this script's job is only to decide where the capsule
## goes. It reports events (`notify_landing`) rather than posing anything.
##
## All tunables are consts up top — the numbers ARE the feel pass.

## Ground speeds, m/s. The controller interpolates freely between them rather
## than snapping between modes, so there is no walk/run threshold to feel.
const WALK_SPEED: float = 1.65
const JOG_SPEED: float = 3.60
const RUN_SPEED: float = 5.60
const SPRINT_SPEED: float = 7.60
const CROUCH_SPEED: float = 1.70

## Acceleration is expressed as the time to reach top speed, which keeps the
## feel identical when the speeds are retuned.
const GROUND_ACCEL: float = 26.0
const GROUND_DECEL: float = 34.0
const AIR_ACCEL: float = 11.0
## Braking when the stick points against current travel — a hard cut, so
## reversing is crisp instead of a long skid.
const TURN_BRAKE: float = 46.0

const JUMP_VELOCITY: float = 7.4   # ~1.15 m apex with RISE_GRAVITY
const RISE_GRAVITY: float = 24.0
const FALL_GRAVITY: float = 34.0
const MAX_FALL_SPEED: float = 40.0
const JUMP_CUT_FACTOR: float = 0.45  # early release trims the arc
const COYOTE_TIME: float = 0.12
const JUMP_BUFFER: float = 0.15

## Turning. Rate falls off with speed: a sprint carves, a walk pivots.
const TURN_SPEED_STILL: float = 16.0
const TURN_SPEED_FAST: float = 6.5
## How much of top speed a hard direction change costs, 0..1. Momentum should
## be spent to change heading, or the character reads as weightless.
const TURN_SPEED_COST: float = 0.42

## Slopes. Climbing costs pace, descending gives a little back.
const SLOPE_UPHILL_PENALTY: float = 0.55   # fraction lost at max walkable angle
const SLOPE_DOWNHILL_BONUS: float = 0.16
const MAX_CLIMB_ANGLE: float = 0.87        # ~50 degrees; matches floor_max_angle

## Steps up to this height are climbed without a jump.
const STEP_HEIGHT: float = 0.42

## Crouch blend rate, per second.
const CROUCH_RATE: float = 6.0
## Standing and crouched capsule heights, metres.
const STAND_HEIGHT: float = 1.70
const CROUCH_HEIGHT: float = 1.05

const SQUASH_MIN_AIR_TIME: float = 0.2  # no squash for curb-sized drops
const KNOCKBACK_DECAY: float = 7.0
const DOWNED_TIME: float = 1.4          # come-apart -> reform beat
const REFORM_IFRAMES: float = 1.6

var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _air_time: float = 0.0
var _was_on_floor: bool = true
var _knockback: Vector3 = Vector3.ZERO
var _downed: bool = false

## 0 standing, 1 fully crouched. Blended, so half-crouch is a real state.
var _crouch: float = 0.0
## True while something overhead prevents standing back up.
var _crouch_blocked: bool = false
## Downward speed on the frame of the last landing, m/s — handed to the
## animator so the knees absorb proportionally.
var _land_impact: float = 0.0

## The radial emote picker, built on first use.
var _emote_wheel: EmoteWheel

## Water. Built here, bound to a terrain by `setup_water()` — until then it
## simply never reports swimming, which is the right behaviour for a region
## that has no water in it yet.
var _swimmer: Swimmer

## Tree climbing. Checked BEFORE the swimmer — a tree standing in water is a
## tree, not a swim.
var _climb: TreeClimb

@onready var _visual: Node3D = $Visual
@onready var _rig: CameraRig = $CameraRig
@onready var _health: Health = $Health
@onready var _combat: PlayerCombat = $Combat
@onready var _collider: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	InputSetup.ensure()
	_rig.setup(self)
	add_to_group(&"player")
	add_to_group(&"hittable")
	_health.invuln_after_hit = 0.5
	_health.setup(float(GameState.hearts_max), true)
	_health.changed.connect(_on_health_changed)
	_health.died.connect(_on_health_died)
	_combat.setup(self, _visual, _rig, _health)
	# Let the body ride up small ledges instead of stopping dead on them. Godot
	# resolves this inside move_and_slide, so it costs nothing per frame and
	# removes the single most common "the world snagged me" complaint.
	floor_max_angle = MAX_CLIMB_ANGLE
	floor_snap_length = STEP_HEIGHT
	floor_block_on_wall = false
	_swimmer = Swimmer.new()
	_swimmer.name = "Swimmer"
	add_child(_swimmer)
	_climb = TreeClimb.new()
	_climb.name = "TreeClimb"
	add_child(_climb)
	_climb.setup(self)
	EventBus.player_spawned.emit(self)


## Hand the swimmer the terrain that answers "is there water here". Called by
## main.gd once the world exists; without it Kern simply never swims.
func setup_water(terrain: MeadowTerrain) -> void:
	_swimmer.setup(self, terrain)


## True while Kern is off the bottom and stroking — read by the animator and by
## anything that must not run on land rules.
func is_swimming() -> bool:
	return _swimmer != null and _swimmer.is_swimming


## Re-announce hearts so a HUD created after us (main.gd) shows the right value.
func broadcast_hearts() -> void:
	EventBus.player_hearts_changed.emit(_health.current, _health.max_hearts)


func _on_health_changed(current: float, max_hearts: float) -> void:
	EventBus.player_hearts_changed.emit(current, max_hearts)


## How crouched the body is, 0..1 — read by the animator every frame.
func crouch_amount() -> float:
	return _crouch


func _physics_process(delta: float) -> void:
	# The grass field parts around Kern (grass_field.gdshader trample).
	RenderingServer.global_shader_parameter_set(&"gf_player_pos", global_position)
	if _downed:
		_apply_gravity(delta)
		var h: Vector2 = Vector2(velocity.x, velocity.z).move_toward(
			Vector2.ZERO, GROUND_DECEL * delta)
		velocity.x = h.x
		velocity.z = h.y
		move_and_slide()
		return
	_combat.tick(delta)
	_tick_emotes()
	_tick_timers(delta)
	_tick_crouch(delta)
	# Water takes over entirely when it applies: no gravity, no jump, no ground
	# steering. Buoyancy and the stroke are the swimmer's job, and it reports
	# whether it claimed the frame.
	var wish: Array = _wish_vector()
	# Climbing first: it authors the body's position outright, so nothing else
	# may touch velocity on a frame it claims.
	if _climb != null:
		var raw: Vector2 = Input.get_vector(&"move_left", &"move_right",
				&"move_forward", &"move_back")
		if _climb.tick(delta, -raw.y, raw.x):
			return
	if _swimmer != null and _swimmer.tick(delta, wish[0], wish[1]):
		if float(wish[1]) > 0.02:
			var swim_dir: Vector3 = wish[0]
			_face_yaw(atan2(-swim_dir.x, -swim_dir.z), delta)
		move_and_slide()
		_was_on_floor = is_on_floor()
		return
	_apply_gravity(delta)
	if not _combat.blocks_jump():
		_handle_jump()
	_handle_move(delta)
	_apply_knockback(delta)
	move_and_slide()
	_handle_landing()
	_was_on_floor = is_on_floor()


func _apply_knockback(delta: float) -> void:
	if _knockback.length_squared() < 0.0001:
		return
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-KNOCKBACK_DECAY * delta))


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


## Blend the crouch, resize the capsule, and refuse to stand up under a ceiling.
##
## The capsule is shortened from the TOP (its centre drops by half the height
## lost) so crouching never pushes the feet through the floor — resizing about
## the centre is the classic way a crouch ends up levitating the character.
func _tick_crouch(delta: float) -> void:
	var wants: bool = Input.is_action_pressed(&"crouch") and is_on_floor()
	_crouch_blocked = false
	if not wants and _crouch > 0.01 and _ceiling_blocked():
		# Held down by geometry: stay crouched rather than clipping through it.
		wants = true
		_crouch_blocked = true
	_crouch = move_toward(_crouch, 1.0 if wants else 0.0, CROUCH_RATE * delta)

	var capsule: CapsuleShape3D = _collider.shape as CapsuleShape3D
	if capsule != null:
		var height: float = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch)
		capsule.height = height
		_collider.position.y = height * 0.5


## True if there is not enough headroom to stand back up.
func _ceiling_blocked() -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.2,
		global_position + Vector3.UP * (STAND_HEIGHT + 0.12))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity: float = RISE_GRAVITY if velocity.y > 0.0 else FALL_GRAVITY
	velocity.y = maxf(velocity.y - gravity * delta, -MAX_FALL_SPEED)


func _handle_jump() -> void:
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		# Crouched jumps are shorter — the legs are already loaded.
		velocity.y = JUMP_VELOCITY * lerpf(1.0, 0.78, _crouch)
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		if _visual.has_method("notify_jump"):
			_visual.call("notify_jump")
	if velocity.y > 0.0 and Input.is_action_just_released(&"jump"):
		velocity.y *= JUMP_CUT_FACTOR


## Decide this frame's horizontal velocity and facing.
func _handle_move(delta: float) -> void:
	# A dodge roll drives velocity directly; skip normal steering this frame.
	if _combat.use_velocity_override:
		var ov: Vector3 = _combat.velocity_override
		velocity.x = ov.x
		velocity.z = ov.z
		_face_yaw(_combat.facing_yaw, delta)
		return

	# An emote that locks movement pins the body but still lets gravity run.
	if _emote_locks_movement():
		var damped: Vector2 = Vector2(velocity.x, velocity.z).move_toward(
			Vector2.ZERO, GROUND_DECEL * delta)
		velocity.x = damped.x
		velocity.z = damped.y
		return

	var wish: Array = _wish_vector()
	var dir: Vector3 = wish[0]
	var input_strength: float = wish[1]

	var top_speed: float = _target_speed(input_strength) * _combat.move_scale
	top_speed *= _slope_factor(dir)

	var horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	var target: Vector2 = Vector2(dir.x, dir.z) * top_speed

	# Turning costs momentum: the sharper the direction change, the more speed
	# is scrubbed. Without this a character can reverse at full pace, which
	# reads as frictionless no matter how good the animation is.
	if is_on_floor() and horizontal.length() > 0.5 and input_strength > 0.1:
		var alignment: float = horizontal.normalized().dot(target.normalized())
		if alignment < 0.999:
			var cost: float = (1.0 - alignment) * 0.5 * TURN_SPEED_COST
			target *= 1.0 - cost

	var accel: float = AIR_ACCEL
	if is_on_floor():
		if input_strength < 0.05:
			accel = GROUND_DECEL
		elif target.dot(horizontal) < 0.0:
			accel = TURN_BRAKE
		elif target.length_squared() < horizontal.length_squared():
			accel = GROUND_DECEL
		else:
			accel = GROUND_ACCEL
	horizontal = horizontal.move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	if _combat.lock_facing:
		# Face the swing/guard/aim direction chosen by combat.
		_face_yaw(_combat.facing_yaw, delta, 1.4)
	elif input_strength > 0.02:
		# Model forward is -Z (Godot convention), hence the negations.
		_face_yaw(atan2(-dir.x, -dir.z), delta)


## The steering the player is asking for, camera-relative, as
## `[Vector3 direction, float strength]`.
##
## Extracted so the swimmer and the ground controller read the SAME intent. When
## they each computed it, a fix to one silently left the other steering by an
## older rule.
func _wish_vector() -> Array:
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
	var strength: float = clampf(dir.length(), 0.0, 1.0)
	if strength > 0.0001:
		dir = dir / strength
	return [dir, strength]


## Top speed for the current input strength and modifiers.
##
## Stick deflection maps CONTINUOUSLY onto the speed ladder, so a gentle push is
## a genuine walk rather than a walk-speed cap the animation has to pretend
## about. Sprint extends the ladder's top rather than replacing it.
func _target_speed(input_strength: float) -> float:
	if _crouch > 0.5:
		return CROUCH_SPEED * input_strength
	if Input.is_action_pressed(&"walk"):
		return WALK_SPEED * input_strength
	var ceiling: float = SPRINT_SPEED if Input.is_action_pressed(&"sprint") \
		else RUN_SPEED
	# Below half deflection the ladder runs walk -> jog; above it, jog -> ceiling.
	if input_strength <= 0.5:
		return lerpf(0.0, JOG_SPEED, input_strength * 2.0)
	return lerpf(JOG_SPEED, ceiling, (input_strength - 0.5) * 2.0)


## Pace multiplier for the slope being walked into.
##
## Uses the dot of travel direction against the floor normal, so it responds to
## the slope actually being CLIMBED rather than to the ground's steepness in
## the abstract — traversing a hillside sideways correctly costs nothing.
func _slope_factor(direction: Vector3) -> float:
	if not is_on_floor() or direction.length_squared() < 0.0001:
		return 1.0
	var normal: Vector3 = get_floor_normal()
	# Positive when moving uphill, negative downhill.
	var climb: float = -direction.normalized().dot(normal)
	var steepness: float = clampf(acos(clampf(normal.y, -1.0, 1.0))
		/ MAX_CLIMB_ANGLE, 0.0, 1.0)
	if climb > 0.0:
		return 1.0 - SLOPE_UPHILL_PENALTY * steepness * climb
	return 1.0 + SLOPE_DOWNHILL_BONUS * steepness * -climb


## Turn toward `yaw`, faster when slow and slower when fast, frame-rate
## independently. A sprinting character that can pivot instantly reads as
## having no mass; one that always turns slowly is infuriating to steer.
func _face_yaw(yaw: float, delta: float, rate_mul: float = 1.0) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var rate: float = lerpf(TURN_SPEED_STILL, TURN_SPEED_FAST,
		clampf(speed / SPRINT_SPEED, 0.0, 1.0)) * rate_mul
	var difference: float = wrapf(yaw - _visual.rotation.y, -PI, PI)
	_visual.rotation.y += difference * (1.0 - exp(-rate * delta))


## Detect touchdown and hand the impact to the animator.
func _handle_landing() -> void:
	if is_on_floor() and not _was_on_floor:
		if _air_time > SQUASH_MIN_AIR_TIME and _visual.has_method("notify_landing"):
			_visual.call("notify_landing", absf(_land_impact))
	if not is_on_floor():
		_land_impact = velocity.y


## Open the emote wheel while the key is held, perform on release, and cancel a
## running emote the moment the player asks to move again.
##
## Cancel-on-input is the rule that keeps emotes from ever feeling like a trap:
## whatever Kern is in the middle of, a nudge of the stick returns control
## immediately and the emote blends out rather than having to finish.
func _tick_emotes() -> void:
	if _emote_wheel == null:
		_emote_wheel = EmoteWheel.build(self)
		_emote_wheel.chosen.connect(_on_emote_chosen)

	if Input.is_action_just_pressed(&"emote_wheel"):
		_emote_wheel.open()
	elif Input.is_action_just_released(&"emote_wheel"):
		_emote_wheel.close()

	if _emote_wheel.is_open():
		return
	# Any movement, jump or combat intent releases a playing emote.
	var wants_out: bool = Input.get_vector(&"move_left", &"move_right",
		&"move_forward", &"move_back").length() > 0.15 \
		or Input.is_action_just_pressed(&"jump") \
		or Input.is_action_just_pressed(&"attack") \
		or Input.is_action_just_pressed(&"dodge")
	if wants_out and _visual.has_method("emote_active") \
			and bool(_visual.call("emote_active")):
		_visual.call("stop_emote")


func _on_emote_chosen(emote_id: String) -> void:
	if emote_id == "" or _visual == null:
		return
	if _visual.has_method("play_emote"):
		_visual.call("play_emote", emote_id)


## True while an emote is holding the player in place.
func _emote_locks_movement() -> bool:
	return _visual != null and _visual.has_method("emote_locks_movement") \
		and bool(_visual.call("emote_locks_movement"))


# --- Taking damage (group "hittable"; called by enemy melee & projectiles) ---

func apply_hit(amount: float, from_position: Vector3, knockback: float) -> void:
	if _downed or _health.is_invulnerable():
		return
	var dmg: float = amount
	if _combat.block_active():
		dmg = amount * _combat.on_blocked(from_position)
		if dmg <= 0.0:
			return  # fully parried or guarded head-on
	if not _health.apply(dmg, from_position):
		return
	var away: Vector3 = global_position - from_position
	away.y = 0.0
	if away.length() > 0.01:
		_knockback = away.normalized() * knockback
	EventBus.player_hit.emit(dmg)
	EventBus.combat_shake.emit(0.16)


func _on_health_died() -> void:
	if _downed:
		return
	# All-ages: Kern doesn't die, he comes apart and reforms (GDD tone).
	_downed = true
	_knockback = Vector3.ZERO
	EventBus.player_died.emit()
	EventBus.combat_shake.emit(0.45)
	DamageShards.burst(get_tree().current_scene, global_position + Vector3(0.0, 0.9, 0.0),
		Color(0.62, 0.82, 1.0), 26, 5.0, 2.6, 1.2)
	_visual.visible = false
	get_tree().create_timer(DOWNED_TIME).timeout.connect(_reform)


func _reform() -> void:
	_health.refill()
	_health.grant_iframes(REFORM_IFRAMES)
	_visual.visible = true
	_visual.scale = Vector3.ONE
	_downed = false
	if _visual.has_method("teleported"):
		_visual.call("teleported")
	EventBus.player_reformed.emit()

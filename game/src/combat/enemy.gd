class_name Enemy
extends CharacterBody3D
## A data-driven monster. Fed a content entry (ContentDB monster dict) or a
## hand-built sparring config, it reads `behavior`, `hearts`, and `attack` and
## runs the matching brain:
##   * melee / swarm — close in, telegraph, lunge-strike, recover
##   * ranged        — hold distance, telegraph, fire a data-bolt
##   * dummy         — never attacks; a safe target that reforms after it falls
##
## Death is the canon dissolve: a shard burst, a drop roll against the entry's
## table (routed through GameState + EventBus so quests/HUD react), and — for
## content monsters — the spawner is free to repopulate. No gore, ever.
##
## GDD §10 visible surface: NO Godot in this build env, so this is UNSEEN — a
## live session must watch a real fight before the milestone box ticks clean.
##
## Built entirely in code — there is no enemy scene. `Enemy.spawn()` is the
## only entry point; MonsterSpawner calls it with either a ContentDB monster
## dict or a hand-built sparring config, and `_ready()` assembles the
## collider, EnemyVisual, Health, and melee hitbox from that config. Emits
## EventBus.enemy_hit, enemy_defeated, and combat_shake; drops route through
## GameState.add_item. Kern's sword and special call `apply_hit()`. Joins the
## "enemy" and "hittable" groups and finds the player via the "player" group.
## Units: meters, seconds, meters/second; hearts are floats (0.5 = a half
## heart). Rotation follows Godot's -Z forward convention.

## The AI brain's states. STAGGER interrupts an attack on a hit; DEAD is
## terminal for content monsters, while dummies pass through REFORM back to
## IDLE so the proving ground never empties.
enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD, REFORM }

## Downward acceleration (m/s²) — deliberately heavier than real gravity, a
## standard platformer trick for snappy, non-floaty falls.
const GRAVITY: float = 22.0
## Distance (m) at which an idle monster notices Kern, and the distance at
## which it gives up and returns to wandering. The gap between them is
## hysteresis: without it a monster hovering at the edge would flicker
## between chasing and idling every frame.
const AGGRO_RADIUS: float = 14.0
const LEASH_RADIUS: float = 24.0
## Horizontal acceleration (m/s²) toward the steering target, and the yaw
## turn rate (1/s) used to face a direction.
const CHASE_ACCEL: float = 12.0
const TURN_SPEED: float = 9.0
## Seconds the melee hitbox stays live during a lunge, and how long a
## monster is stunned after being hit.
const STRIKE_TIME: float = 0.18
const STAGGER_TIME: float = 0.26
## Exponential decay rate (1/s) of knockback velocity.
const KNOCKBACK_DECAY: float = 6.0
## Idle wander: seconds between new destinations and the maximum radius (m)
## a monster strays from its spawn anchor.
const WANDER_INTERVAL: float = 3.5
const WANDER_RADIUS: float = 6.0
## Ranged kiting band (m): a ranged monster advances beyond PREFERRED,
## backs off inside MIN, and fires while in between.
const RANGED_PREFERRED: float = 10.0
const RANGED_MIN: float = 6.0
## Data-bolt travel speed (m/s).
const PROJECTILE_SPEED: float = 13.0
## Seconds a felled sparring dummy stays down before reforming.
const REFORM_DELAY: float = 3.0
## Seconds the death shrink tween runs before the node frees itself.
const DEATH_SHRINK: float = 0.16

# Per-behavior feel (speed, reach, wind-up, recovery).
const TUNING: Dictionary = {
	"swarm": {"speed": 4.4, "reach": 1.5, "windup": 0.28, "recover": 0.5, "lunge": 6.0},
	"melee": {"speed": 3.3, "reach": 1.9, "windup": 0.44, "recover": 0.66, "lunge": 6.5},
	"ranged": {"speed": 2.7, "reach": RANGED_PREFERRED, "windup": 0.52, "recover": 0.9, "lunge": 0.0},
	"dummy": {"speed": 0.0, "reach": 0.0, "windup": 0.0, "recover": 0.0, "lunge": 0.0},
}

## Content ID (`mon_…`) this monster was built from; empty for the sparring
## rigs, which is how the spawner tells real content from the proving ground.
var monster_id: String = ""
var display_name: String = "Monster"
## Which brain runs: "melee", "ranged", "swarm", or "dummy". Other schema
## behaviors (ambush, flying, tank, caster) validate but fall back to swarm.
var behavior: String = "swarm"
## Damage per landed hit, in hearts.
var attack_damage: float = 0.5
## Optional rare appearance variant, passed through to EnemyVisual.
var variant: String = ""

## The raw config dict this monster was spawned from.
var _cfg: Dictionary = {}
## The TUNING row for `behavior`, resolved once in `_apply_config()`.
var _tune: Dictionary = TUNING["swarm"]
var _state: int = State.IDLE
## Seconds in the current state — counts up everywhere except REFORM, where
## it counts down as a timer.
var _state_time: float = 0.0
var _player: Node3D
## World position at spawn; the anchor idle wandering orbits.
var _spawn_pos: Vector3
## Decaying velocity added on top of AI intent after being struck.
var _knockback: Vector3 = Vector3.ZERO
var _wander_left: float = 0.0
var _wander_target: Vector3
var _hit_ids: Dictionary = {}   ## bodies already struck this swing

var _health: Health
var _visual: EnemyVisual
var _melee_hitbox: Area3D
var _melee_shape: CollisionShape3D


## Create a monster from `cfg` (a ContentDB monster dict or a sparring
## config) and parent it to `host`. The only supported way to build one —
## the config must be set before the node enters the tree, since `_ready()`
## reads it to assemble the body.
static func spawn(host: Node, cfg: Dictionary, position: Vector3) -> Enemy:
	var e: Enemy = Enemy.new()
	e._cfg = cfg
	# Place BEFORE entering the tree so _ready() captures the right spawn anchor.
	# (Spawn roots sit at the origin, so this local position is also world.)
	e.position = position
	host.add_child(e)
	return e


func _ready() -> void:
	add_to_group(&"enemy")
	add_to_group(&"hittable")
	_apply_config()
	_build_body()
	_build_visual()
	_build_health()
	_build_melee_hitbox()
	_spawn_pos = global_position
	_wander_target = global_position
	_state = State.IDLE


## Read the config into typed fields and resolve the behavior tuning row.
## An unforced variant has a 6% chance of being rolled from the entry's
## list, so rare-looking monsters stay rare.
func _apply_config() -> void:
	monster_id = str(_cfg.get("id", ""))
	display_name = str(_cfg.get("name", "Monster"))
	behavior = str(_cfg.get("behavior", "swarm"))
	attack_damage = float(_cfg.get("attack", 0.5))
	var variants: Array = _cfg.get("variants", [])
	variant = str(_cfg.get("variant", ""))  # spawner may force a specific variant
	if variant == "" and variants.size() > 0 and randf() < 0.06:
		variant = str(variants[randi() % variants.size()])
	_tune = TUNING.get(behavior, TUNING["swarm"])


## Physics body: on the ENEMY layer, colliding only with WORLD geometry.
## Deliberately not masking PLAYER or other enemies — monsters pass through
## each other and through Kern rather than shoving him around, which keeps
## swarms readable. Damage is dealt by the separate melee hitbox Area3D.
func _build_body() -> void:
	collision_layer = CombatLayers.ENEMY
	collision_mask = CombatLayers.WORLD
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.0 if behavior != "dummy" else 1.6
	shape.shape = cap
	shape.position = Vector3(0.0, cap.height * 0.5, 0.0)
	add_child(shape)


## Attach the code-built cel-shaded body, sized by the entry's tier and
## tinted by behavior so a player can read a monster's role at a glance.
func _build_visual() -> void:
	_visual = EnemyVisual.new()
	add_child(_visual)
	var base: Color = _base_color()
	_visual.setup(behavior, base, base.lerp(Color(1, 1, 1), 0.35), _size_for_tier(), variant)


## Hearts pool from the entry (default 1.5). The i-frame window is only
## 50 ms — just enough to stop one sword swing registering twice, without
## giving monsters the generous mercy window the player gets.
func _build_health() -> void:
	_health = Health.new()
	_health.invuln_after_hit = 0.05
	add_child(_health)
	_health.setup(float(_cfg.get("hearts", 1.5)), true)
	_health.died.connect(_on_died)


## Build the swing hitbox for behaviors that strike in melee. It sits in
## front of the monster (negative Z is forward), spans its reach plus a
## little slack, and stays `monitoring = false` except during STRIKE — so
## the box only exists as a threat for the 0.18 s of the actual swing.
func _build_melee_hitbox() -> void:
	if behavior == "ranged" or behavior == "dummy":
		return
	_melee_hitbox = Area3D.new()
	_melee_hitbox.collision_layer = 0
	_melee_hitbox.collision_mask = CombatLayers.PLAYER
	_melee_hitbox.monitoring = false
	_melee_shape = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.1, 1.2, float(_tune["reach"]) + 0.4)
	_melee_shape.shape = box
	_melee_shape.position = Vector3(0.0, 0.7, -(float(_tune["reach"]) * 0.5))
	_melee_hitbox.add_child(_melee_shape)
	_melee_hitbox.body_entered.connect(_on_melee_body_entered)
	add_child(_melee_hitbox)


# --- Main loop ---------------------------------------------------------------

## The AI tick: gravity, then the state machine, then knockback and motion.
## DEAD returns immediately (the node is mid-shrink or awaiting free) and
## REFORM only runs its countdown, so a downed monster costs nothing.
func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _state == State.REFORM:
		_state_time -= delta
		if _state_time <= 0.0:
			_finish_reform()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		# Keep a sliver of downward velocity while grounded so move_and_slide
		# reliably reports floor contact on slopes.
		velocity.y = maxf(velocity.y, -0.1)

	_ensure_player()
	var to_player: Vector3 = Vector3.ZERO
	# Horizontal distance only — a monster on a slope below Kern should
	# still consider him in reach. INF while no player exists, which parks
	# every brain in its "too far" branch.
	var dist: float = INF
	if _player != null:
		to_player = _player.global_position - global_position
		dist = Vector2(to_player.x, to_player.z).length()

	_state_time += delta
	match _state:
		State.IDLE:
			_do_idle(delta, dist)
		State.CHASE:
			_do_chase(delta, to_player, dist)
		State.WINDUP:
			_do_windup(delta, to_player, dist)
		State.STRIKE:
			_do_strike(delta)
		State.RECOVER:
			_do_recover(delta, dist)
		State.STAGGER:
			_do_stagger(delta)

	# Knockback rides on top of intent, decaying smoothly.
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-KNOCKBACK_DECAY * delta))
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	move_and_slide()


## IDLE: watch for Kern entering aggro range, otherwise amble between
## random points around the spawn anchor at 40% speed.
func _do_idle(delta: float, dist: float) -> void:
	if dist <= AGGRO_RADIUS:
		_set_state(State.CHASE)
		return
	# Gentle wander around the spawn anchor.
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = randf_range(WANDER_INTERVAL, WANDER_INTERVAL * 1.8)
		var a: float = randf() * TAU
		_wander_target = _spawn_pos + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, WANDER_RADIUS)
	var to: Vector3 = _wander_target - global_position
	to.y = 0.0
	if to.length() > 0.6:
		_steer(to.normalized() * float(_tune["speed"]) * 0.4, delta)
		_face(to, delta)
	else:
		_steer(Vector3.ZERO, delta)


## CHASE: close to attack position, or break off past the leash. Ranged
## monsters kite to hold their band and fire from it; melee and swarm
## monsters run straight in and wind up once inside reach.
func _do_chase(delta: float, to_player: Vector3, dist: float) -> void:
	if _player == null or dist > LEASH_RADIUS:
		_set_state(State.IDLE)
		return
	_face(to_player, delta)
	var flat: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	if behavior == "ranged":
		# Kite: hold the preferred band.
		if dist > RANGED_PREFERRED + 1.0:
			_steer(flat.normalized() * float(_tune["speed"]), delta)
		elif dist < RANGED_MIN:
			_steer(-flat.normalized() * float(_tune["speed"]), delta)
		else:
			_steer(Vector3.ZERO, delta)
			_set_state(State.WINDUP)
	else:
		if dist <= float(_tune["reach"]):
			_steer(Vector3.ZERO, delta)
			_set_state(State.WINDUP)
		else:
			_steer(flat.normalized() * float(_tune["speed"]), delta)


## WINDUP: the telegraph. The monster plants, keeps tracking Kern, and
## EnemyVisual glows from 0 to 1 across the behavior's wind-up time — the
## player's cue to dodge or parry. Ranged monsters fire and recover; melee
## and swarm commit to a lunge.
func _do_windup(delta: float, to_player: Vector3, _dist: float) -> void:
	_face(to_player, delta)
	_steer(Vector3.ZERO, delta)
	if _visual != null:
		_visual.set_telegraph(clampf(_state_time / float(_tune["windup"]), 0.0, 1.0))
	if _state_time >= float(_tune["windup"]):
		if _visual != null:
			_visual.set_telegraph(0.0)
		if behavior == "ranged":
			_fire_projectile(to_player)
			_set_state(State.RECOVER)
		else:
			_begin_strike()


## STRIKE: the committed lunge. Facing is locked (no tracking here, so a
## well-timed dodge always beats the swing) and the hitbox is live.
func _do_strike(delta: float) -> void:
	# Lunge forward along facing while the hitbox is live.
	var fwd: Vector3 = -global_transform.basis.z
	# High acceleration override (40 vs 12 m/s²) so the lunge is an
	# explosive burst rather than a gradual run-up.
	_steer(Vector3(fwd.x, 0.0, fwd.z).normalized() * float(_tune["lunge"]), delta, 40.0)
	if _state_time >= STRIKE_TIME:
		_end_strike()
		_set_state(State.RECOVER)


## RECOVER: the punish window. The monster stands still for its recovery
## time — this is when Kern gets his hits in — then re-engages or gives up.
func _do_recover(delta: float, dist: float) -> void:
	_steer(Vector3.ZERO, delta)
	if _state_time >= float(_tune["recover"]):
		_set_state(State.CHASE if dist <= LEASH_RADIUS else State.IDLE)


## STAGGER: brief hitstun after taking damage, then straight back to chase.
func _do_stagger(delta: float) -> void:
	_steer(Vector3.ZERO, delta)
	if _state_time >= STAGGER_TIME:
		_set_state(State.CHASE)


## Enter a State, resetting the state clock every brain reads.
func _set_state(next: int) -> void:
	_state = next
	_state_time = 0.0


# --- Striking ----------------------------------------------------------------

## Open the swing: clear the per-swing hit register (so this lunge can land
## once on each body), arm the hitbox, and pop the visual.
func _begin_strike() -> void:
	_hit_ids.clear()
	if _melee_hitbox != null:
		_melee_hitbox.monitoring = true
	if _visual != null:
		_visual.flash()  # brief pop on the swing start
	_set_state(State.STRIKE)


## Disarm the hitbox. Also called on stagger and death, so an interrupted
## monster can never leave a live hitbox behind.
func _end_strike() -> void:
	if _melee_hitbox != null:
		_melee_hitbox.monitoring = false


## Hitbox contact handler. Guards three ways before dealing damage: the
## swing must still be live, the body must not already be in this swing's
## hit register, and it must be the player with an `apply_hit` method.
func _on_melee_body_entered(body: Node) -> void:
	if _state != State.STRIKE:
		return
	if _hit_ids.has(body.get_instance_id()):
		return
	if body.is_in_group(&"player") and body.has_method(&"apply_hit"):
		_hit_ids[body.get_instance_id()] = true
		body.apply_hit(attack_damage, global_position, 5.0)


## Launch a data-bolt from roughly the monster's head toward Kern's chest
## (not his origin at ground level, which would send bolts into the dirt).
## The bolt is aimed where he stands at release — it does not lead him, so
## sidestepping works. Parented to the current scene, not to this monster,
## so bolts survive their shooter's death.
func _fire_projectile(to_player: Vector3) -> void:
	if _player == null:
		return
	var origin: Vector3 = global_position + Vector3(0.0, _visual.height * 0.85 if _visual != null else 0.9, 0.0)
	var target: Vector3 = _player.global_position + Vector3(0.0, 0.9, 0.0)
	var dir: Vector3 = (target - origin).normalized()
	Projectile.spawn(get_tree().current_scene, origin, dir, PROJECTILE_SPEED, attack_damage, _base_color().lerp(Color(0.8, 0.4, 1.0), 0.6))
	if _visual != null:
		_visual.flash()


# --- Taking hits -------------------------------------------------------------

## Called by Kern's sword hitbox and by his charged special.
##
## `amount` is damage in hearts, `from_position` is the world point the blow
## came from (used for both the i-frame check and the knockback direction),
## and `knockback` is the impulse in m/s. Returns early if the monster is
## already down or Health rejects the hit (still in i-frames). A surviving
## monster is knocked out of whatever it was doing into STAGGER, so a
## well-timed hit interrupts a wind-up.
func apply_hit(amount: float, from_position: Vector3, knockback: float) -> void:
	if _state == State.DEAD or _state == State.REFORM:
		return
	if not _health.apply(amount, from_position):
		return
	if _visual != null:
		_visual.flash()
	var away: Vector3 = global_position - from_position
	away.y = 0.0
	if away.length() > 0.01:
		_knockback = away.normalized() * knockback
	var hit_at: Vector3 = global_position + Vector3(0.0, (_visual.height * 0.6) if _visual != null else 0.6, 0.0)
	DamageShards.burst(get_tree().current_scene, hit_at, _base_color(), 8, 3.2, 1.6, 0.8)
	EventBus.enemy_hit.emit(monster_id, _health.current)
	EventBus.combat_shake.emit(0.12)
	if not _health.is_dead():
		_end_strike()
		_set_state(State.STAGGER)


## Health.died handler — the canon dissolve. Clears collision so the corpse
## can't block anyone, bursts a large shard cloud, announces the kill on the
## EventBus for quests and the HUD, rolls drops, and then either reforms (a
## sparring dummy) or shrinks away and frees itself (a real monster).
func _on_died() -> void:
	_end_strike()
	_state = State.DEAD
	collision_layer = 0
	if _melee_hitbox != null:
		_melee_hitbox.monitoring = false
	var center: Vector3 = global_position + Vector3(0.0, (_visual.height * 0.55) if _visual != null else 0.6, 0.0)
	DamageShards.burst(get_tree().current_scene, center, _base_color(), 22, 5.5, 2.6, 1.3)
	EventBus.enemy_defeated.emit(monster_id, global_position)
	EventBus.combat_shake.emit(0.22)
	_roll_drops()
	if behavior == "dummy":
		_begin_reform()
	else:
		_shrink_and_free()


## Roll the entry's drop table, each line an independent chance in [0, 1].
## Malformed rows are skipped rather than raising — content is validated
## upstream, and a bad drop should never crash a fight.
func _roll_drops() -> void:
	var drops: Array = _cfg.get("drops", [])
	for d: Variant in drops:
		if not (d is Dictionary):
			continue
		var item_id: String = str((d as Dictionary).get("item_id", ""))
		var chance: float = float((d as Dictionary).get("chance", 0.0))
		if item_id != "" and randf() < chance:
			GameState.add_item(item_id, 1)  # emits EventBus.item_acquired


## Collapse the visual to nothing over DEATH_SHRINK seconds, then free the
## node. The tween is what lets the shard burst read before the body goes.
func _shrink_and_free() -> void:
	if _visual != null:
		var tw: Tween = create_tween()
		tw.tween_property(_visual, "scale", Vector3.ONE * 0.01, DEATH_SHRINK)
		tw.tween_callback(queue_free)
	else:
		queue_free()


## Dummies only: hide and start the reform countdown. `_state_time` is used
## as a descending timer here rather than an ascending clock.
func _begin_reform() -> void:
	if _visual != null:
		_visual.visible = false
	_state = State.REFORM
	_state_time = REFORM_DELAY


## Restore a dummy to full: hearts, visibility, scale (undoing any shrink),
## collision layer, and cleared knockback, back to IDLE ready to be hit again.
func _finish_reform() -> void:
	_health.refill()
	if _visual != null:
		_visual.visible = true
		_visual.scale = Vector3.ONE
	collision_layer = CombatLayers.ENEMY
	_knockback = Vector3.ZERO
	_set_state(State.IDLE)


# --- Helpers -----------------------------------------------------------------

## Ease horizontal velocity toward `desired` (m/s) at `accel` m/s². Vertical
## velocity is left alone so gravity keeps working. Passing Vector3.ZERO is
## how brains brake to a stop.
func _steer(desired: Vector3, delta: float, accel: float = CHASE_ACCEL) -> void:
	var horiz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	horiz = horiz.move_toward(Vector3(desired.x, 0.0, desired.z), accel * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z


## Turn to face `dir` (world space, Y ignored) at TURN_SPEED. Near-zero
## directions are ignored so the monster holds its heading instead of
## snapping to an arbitrary yaw. Uses lerp_angle, which takes the short way
## around and never spins the long way past ±π.
func _face(dir: Vector3, delta: float) -> void:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0004:
		return
	# Negated because Godot's forward is -Z: this yields the yaw whose
	# forward axis points along `flat`.
	var target_yaw: float = atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))


## Re-resolve the player each tick if the reference is missing or stale.
## Group lookup rather than a hard path keeps monsters spawnable into any
## scene, including ones with no player at all.
func _ensure_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D


## Silhouette color per behavior — red-ish melee, violet ranged, wood-toned
## dummy, green swarm. Also tints hit shards and death bursts, so the read
## stays consistent from first glance to dissolve.
func _base_color() -> Color:
	match behavior:
		"melee":
			return Color(0.62, 0.28, 0.34)
		"ranged":
			return Color(0.45, 0.35, 0.7)
		"dummy":
			return Color(0.55, 0.42, 0.24)
		_:
			return Color(0.4, 0.62, 0.5)


## Visual scale multiplier from the entry's tier, so an elite reads as a
## threat before it moves. Unknown tiers fall through to fodder.
func _size_for_tier() -> float:
	match str(_cfg.get("tier", "fodder")):
		"elite":
			return 1.4
		"standard":
			return 1.1
		_:
			return 0.85

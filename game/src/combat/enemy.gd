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

enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD, REFORM }

const GRAVITY: float = 22.0
const AGGRO_RADIUS: float = 14.0
const LEASH_RADIUS: float = 24.0
const CHASE_ACCEL: float = 12.0
const TURN_SPEED: float = 9.0
const STRIKE_TIME: float = 0.18
const STAGGER_TIME: float = 0.26
const KNOCKBACK_DECAY: float = 6.0
const WANDER_INTERVAL: float = 3.5
const WANDER_RADIUS: float = 6.0
const RANGED_PREFERRED: float = 10.0
const RANGED_MIN: float = 6.0
const PROJECTILE_SPEED: float = 13.0
const REFORM_DELAY: float = 3.0
const DEATH_SHRINK: float = 0.16

# Per-behavior feel (speed, reach, wind-up, recovery).
const TUNING: Dictionary = {
	"swarm": {"speed": 4.4, "reach": 1.5, "windup": 0.28, "recover": 0.5, "lunge": 6.0},
	"melee": {"speed": 3.3, "reach": 1.9, "windup": 0.44, "recover": 0.66, "lunge": 6.5},
	"ranged": {"speed": 2.7, "reach": RANGED_PREFERRED, "windup": 0.52, "recover": 0.9, "lunge": 0.0},
	"dummy": {"speed": 0.0, "reach": 0.0, "windup": 0.0, "recover": 0.0, "lunge": 0.0},
}

var monster_id: String = ""
var display_name: String = "Monster"
var behavior: String = "swarm"
var attack_damage: float = 0.5
var variant: String = ""

var _cfg: Dictionary = {}
var _tune: Dictionary = TUNING["swarm"]
var _state: int = State.IDLE
var _state_time: float = 0.0
var _player: Node3D
var _spawn_pos: Vector3
var _knockback: Vector3 = Vector3.ZERO
var _wander_left: float = 0.0
var _wander_target: Vector3
var _hit_ids: Dictionary = {}   ## bodies already struck this swing

var _health: Health
var _visual: EnemyVisual
var _melee_hitbox: Area3D
var _melee_shape: CollisionShape3D


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


func _build_visual() -> void:
	_visual = EnemyVisual.new()
	add_child(_visual)
	var base: Color = _base_color()
	_visual.setup(behavior, base, base.lerp(Color(1, 1, 1), 0.35), _size_for_tier(), variant)


func _build_health() -> void:
	_health = Health.new()
	_health.invuln_after_hit = 0.05
	add_child(_health)
	_health.setup(float(_cfg.get("hearts", 1.5)), true)
	_health.died.connect(_on_died)


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
		velocity.y = maxf(velocity.y, -0.1)

	_ensure_player()
	var to_player: Vector3 = Vector3.ZERO
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


func _do_strike(delta: float) -> void:
	# Lunge forward along facing while the hitbox is live.
	var fwd: Vector3 = -global_transform.basis.z
	_steer(Vector3(fwd.x, 0.0, fwd.z).normalized() * float(_tune["lunge"]), delta, 40.0)
	if _state_time >= STRIKE_TIME:
		_end_strike()
		_set_state(State.RECOVER)


func _do_recover(delta: float, dist: float) -> void:
	_steer(Vector3.ZERO, delta)
	if _state_time >= float(_tune["recover"]):
		_set_state(State.CHASE if dist <= LEASH_RADIUS else State.IDLE)


func _do_stagger(delta: float) -> void:
	_steer(Vector3.ZERO, delta)
	if _state_time >= STAGGER_TIME:
		_set_state(State.CHASE)


func _set_state(next: int) -> void:
	_state = next
	_state_time = 0.0


# --- Striking ----------------------------------------------------------------

func _begin_strike() -> void:
	_hit_ids.clear()
	if _melee_hitbox != null:
		_melee_hitbox.monitoring = true
	if _visual != null:
		_visual.flash()  # brief pop on the swing start
	_set_state(State.STRIKE)


func _end_strike() -> void:
	if _melee_hitbox != null:
		_melee_hitbox.monitoring = false


func _on_melee_body_entered(body: Node) -> void:
	if _state != State.STRIKE:
		return
	if _hit_ids.has(body.get_instance_id()):
		return
	if body.is_in_group(&"player") and body.has_method(&"apply_hit"):
		_hit_ids[body.get_instance_id()] = true
		body.apply_hit(attack_damage, global_position, 5.0)


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


func _roll_drops() -> void:
	var drops: Array = _cfg.get("drops", [])
	for d: Variant in drops:
		if not (d is Dictionary):
			continue
		var item_id: String = str((d as Dictionary).get("item_id", ""))
		var chance: float = float((d as Dictionary).get("chance", 0.0))
		if item_id != "" and randf() < chance:
			GameState.add_item(item_id, 1)  # emits EventBus.item_acquired


func _shrink_and_free() -> void:
	if _visual != null:
		var tw: Tween = create_tween()
		tw.tween_property(_visual, "scale", Vector3.ONE * 0.01, DEATH_SHRINK)
		tw.tween_callback(queue_free)
	else:
		queue_free()


func _begin_reform() -> void:
	if _visual != null:
		_visual.visible = false
	_state = State.REFORM
	_state_time = REFORM_DELAY


func _finish_reform() -> void:
	_health.refill()
	if _visual != null:
		_visual.visible = true
		_visual.scale = Vector3.ONE
	collision_layer = CombatLayers.ENEMY
	_knockback = Vector3.ZERO
	_set_state(State.IDLE)


# --- Helpers -----------------------------------------------------------------

func _steer(desired: Vector3, delta: float, accel: float = CHASE_ACCEL) -> void:
	var horiz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	horiz = horiz.move_toward(Vector3(desired.x, 0.0, desired.z), accel * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z


func _face(dir: Vector3, delta: float) -> void:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0004:
		return
	var target_yaw: float = atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))


func _ensure_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D


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

func _size_for_tier() -> float:
	match str(_cfg.get("tier", "fodder")):
		"elite":
			return 1.4
		"standard":
			return 1.1
		_:
			return 0.85

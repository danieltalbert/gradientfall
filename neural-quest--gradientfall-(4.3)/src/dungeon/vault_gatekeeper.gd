class_name VaultGatekeeper
extends CharacterBody3D
## The Gatekeeper — the Perceptron Vault's mini-boss, and the last cell of its
## 2-3-1 network (WORLDBOOK, Datasedge Meadows: "sums what hits it; overload
## it").
##
## It is the only enemy in the game with no hearts. It has a CHARGE, and the
## fight is a race to push that charge over its threshold before it leaks
## away. Everything that reaches the Gatekeeper is summed:
##
## * Kern's sword — a fixed step per landed swing, regardless of combo damage
## * the vault itself — a steady feed while the three hidden chambers are
##   tuned so the output cell fires (see PerceptronVault.solve())
## * its own leak — a constant drain that never stops
##
## The catch is its POLARITY. It alternates between drawing (gold) and
## refusing (blue), telegraphed a beat ahead by color and by a wind-up flare.
## Strike it while it is blue and the blow SUBTRACTS. So the fight teaches the
## sign of a weight with the only argument that really lands: hitting the
## thing at the wrong moment undoes your work.
##
## The two routes are both intended, per GDD §3's open-world contract. Solve
## the vault first and the network does most of the pushing while you dodge;
## walk in with the chambers dark and you must out-hit the leak by hand, which
## is hard and entirely legitimate.
##
## Where it sits: built in code by PerceptronVault when Kern first enters the
## output chamber, and never field-spawned (MonsterSpawner skips the
## `dungeon_boss` tier by design). It wears the same strikeable costume as
## every enemy — ENEMY collision layer, "enemy" group, `apply_hit()` — so
## Kern's existing sword kit works on it unchanged, with no edits to any
## combat script. Emits EventBus.enemy_defeated, combat_shake, and
## enemy_hit (with charge in place of hearts, documented at the emit).
##
## Units: meters, seconds, charge points. Charge is unitless and only ever
## compared against `threshold`.

## Emitted when the charge crosses the threshold and the cell fires. The
## vault listens and opens the output gate.
signal overloaded()

## The charge that fires it. Tuned so the solved-vault route takes roughly
## six seconds of survival and the sword-only route takes about ten landed
## swings without a slip — a real fight either way.
const THRESHOLD: float = 12.0
## Charge added by one landed sword strike while drawing (and removed while
## refusing). Deliberately flat: the fight is about timing, not about which
## combo step landed.
const STRIKE_CHARGE: float = 1.2
## Charge lost per second, always. This is what makes hesitation cost.
const LEAK_PER_SECOND: float = 0.55
## Charge per second fed by the vault while the output cell fires.
const NETWORK_FEED: float = 2.6

## Seconds spent drawing (gold) and refusing (blue).
const DRAW_TIME: float = 6.0
const REFUSE_TIME: float = 3.5
## Seconds of colour warning before a polarity flip. The tell has to lead the
## change or the fight is a coin toss.
const FLIP_TELEGRAPH: float = 0.9

## Seconds between bolt volleys in each polarity. It presses harder while
## refusing, so backing off is a real choice rather than a free rest.
const VOLLEY_DRAW: float = 2.2
const VOLLEY_REFUSE: float = 1.4
const BOLTS_PER_VOLLEY: int = 5
const BOLT_SPEED: float = 11.0
const BOLT_DAMAGE: float = 0.5

## Body proportions, meters.
const BODY_HEIGHT: float = 3.4
const BODY_WIDTH: float = 2.2
const CORE_HEIGHT: float = 2.4
## How far it drifts above the floor, and its hover bob.
const HOVER_HEIGHT: float = 1.1
const BOB_AMPLITUDE: float = 0.22
const BOB_SPEED: float = 1.15
## Yaw turn rate (1/s) while tracking Kern.
const TURN_SPEED: float = 2.2

## Content id, so drops and the defeat signal route through the pipeline the
## same way every other monster does.
var monster_id: String = "mon_the_gatekeeper"
## Live charge, 0..THRESHOLD. Never allowed below zero — a refused blow can
## undo progress but can never put the player in debt.
var charge: float = 0.0
## True while the vault's output cell is firing into it.
var network_feeding: bool = false

## True = drawing (gold, strikes add). False = refusing (blue, strikes subtract).
var _drawing: bool = true
var _phase_left: float = DRAW_TIME
var _volley_left: float = VOLLEY_DRAW
var _spent: bool = false
var _bob_t: float = 0.0

var _player: Node3D
## The four stone slabs of the body, their build-time rest positions, and the
## flinch tween running on each (parallel arrays, same index).
var _shell: Array[MeshInstance3D] = []
var _shell_rest: Array[Vector3] = []
var _shell_tweens: Array[Tween] = []
var _core: MeshInstance3D
var _ring: MeshInstance3D
var _lamp: OmniLight3D
var _label: Label3D
var _home: Vector3 = Vector3.ZERO


## Build the Gatekeeper at `world_position` (its floor point) and parent it to
## `host`. The only supported way to make one.
static func build(host: Node3D, world_position: Vector3) -> VaultGatekeeper:
	var g: VaultGatekeeper = VaultGatekeeper.new()
	g.position = world_position
	host.add_child(g)
	return g


func _ready() -> void:
	add_to_group(&"enemy")
	add_to_group(&"hittable")
	name = "Gatekeeper"
	# Collides with world geometry only. Like every monster it passes through
	# Kern rather than shoving him — a boss that could body-block in a sealed
	# room would be a camera problem, not a challenge.
	collision_layer = CombatLayers.ENEMY
	collision_mask = CombatLayers.WORLD
	_home = global_position
	_build_body()
	_refresh_polarity(true)


## A blunt, wide keystone shape: two slabs and a lintel around a glowing core,
## silhouette-first per GDD §10 — it should read as a doorway that woke up.
func _build_body() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(BODY_WIDTH, BODY_HEIGHT, 1.4)
	shape.shape = box
	shape.position = Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT * 0.5, 0.0)
	add_child(shape)

	var mid: float = HOVER_HEIGHT + BODY_HEIGHT * 0.5
	var jamb: Vector3 = Vector3(0.55, BODY_HEIGHT, 1.1)
	_shell.append(VaultBuild.decor(self, Vector3(-BODY_WIDTH * 0.5 + 0.28, mid, 0.0),
			jamb, VaultBuild.STONE_TRIM))
	_shell.append(VaultBuild.decor(self, Vector3(BODY_WIDTH * 0.5 - 0.28, mid, 0.0),
			jamb, VaultBuild.STONE_TRIM))
	_shell.append(VaultBuild.decor(self,
			Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT - 0.3, 0.0),
			Vector3(BODY_WIDTH, 0.6, 1.25), VaultBuild.STONE_TRIM))
	_shell.append(VaultBuild.decor(self, Vector3(0.0, HOVER_HEIGHT + 0.3, 0.0),
			Vector3(BODY_WIDTH, 0.6, 1.25), VaultBuild.STONE_TRIM))
	for part: MeshInstance3D in _shell:
		_shell_rest.append(part.position)
		_shell_tweens.append(null)

	# The core IS the charge meter — same fill shader as the chambers' sum
	# columns, so the player already knows how to read it before the fight.
	_core = VaultBuild.rune(self,
			Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT * 0.5, 0.0),
			Vector3(0.95, CORE_HEIGHT, 0.95), VaultBuild.LIGHT_POSITIVE, 3.0)
	VaultBuild.set_rune_fill(_core, 0.0)
	VaultBuild.set_rune_flow(_core, 0.6, 1.4, 0.7)

	# A halo ring that carries the polarity color at a glance, readable even
	# when the core is behind a jamb from the player's angle.
	_ring = VaultBuild.rune(self,
			Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT + 0.5, 0.0),
			Vector3(BODY_WIDTH * 1.5, 0.12, BODY_WIDTH * 1.5), VaultBuild.LIGHT_POSITIVE, 2.8)

	_lamp = VaultBuild.lamp(self, Vector3(0.0, mid, 0.0), VaultBuild.LIGHT_POSITIVE,
			3.4, 26.0)

	_label = VaultBuild.plaque(self,
			Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT + 1.3, 0.0), "the Gatekeeper", 6.0, 52)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_track_player(delta)
	_tick_charge(delta)
	_tick_polarity(delta)
	_tick_volley(delta)

	# It hovers in place rather than chasing — the arena is the fight, and a
	# charging boss you cannot out-walk would make dodging pointless.
	_bob_t += delta * BOB_SPEED
	global_position.y = _home.y + sin(_bob_t) * BOB_AMPLITUDE
	VaultBuild.set_rune_fill(_core, charge / THRESHOLD)


## Face Kern so the core (and the polarity tell) always presents to him.
func _track_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return
	var to: Vector3 = _player.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	# Negated because Godot's forward is -Z.
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, TURN_SPEED * delta))


## Leak, then feed. Order matters only for readability — both are per-second
## rates applied to the same accumulator.
func _tick_charge(delta: float) -> void:
	var before: float = charge
	charge = maxf(0.0, charge - LEAK_PER_SECOND * delta)
	if network_feeding:
		charge += NETWORK_FEED * delta
	charge = clampf(charge, 0.0, THRESHOLD)
	if charge >= THRESHOLD and before < THRESHOLD:
		_fire()


## Run the polarity clock and flip when it expires, flaring a warning as the
## flip approaches.
func _tick_polarity(delta: float) -> void:
	_phase_left -= delta
	if _phase_left <= 0.0:
		_drawing = not _drawing
		_phase_left = DRAW_TIME if _drawing else REFUSE_TIME
		_refresh_polarity(false)
		return
	# Warning flare: the ring quickens as the flip nears, so a player watching
	# the boss rather than a timer still gets the beat.
	if _phase_left <= FLIP_TELEGRAPH:
		var urgency: float = 1.0 - _phase_left / FLIP_TELEGRAPH
		VaultBuild.set_rune_pulse(_ring, 0.55, 3.0 + urgency * 9.0)


## Repaint everything that carries polarity. `initial` skips the shard puff so
## the boss does not burst on spawn.
func _refresh_polarity(initial: bool) -> void:
	var col: Color = VaultBuild.LIGHT_POSITIVE if _drawing else VaultBuild.LIGHT_NEGATIVE
	VaultBuild.set_rune_color(_core, col, 3.0)
	VaultBuild.set_rune_color(_ring, col, 2.8)
	VaultBuild.set_rune_pulse(_ring, 0.25, 1.8)
	if _lamp != null:
		_lamp.light_color = col
	if initial:
		return
	DamageShards.burst(get_tree().current_scene,
			global_position + Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT * 0.5, 0.0),
			col, 16, 4.2, 1.8, 1.0)
	EventBus.combat_shake.emit(0.10)


## Volley clock. Bolts fan out in a level arc centered on Kern, so there is
## always a gap to dodge into but never a safe place to stand still.
func _tick_volley(delta: float) -> void:
	_volley_left -= delta
	if _volley_left > 0.0:
		return
	_volley_left = VOLLEY_DRAW if _drawing else VOLLEY_REFUSE
	if _player == null or not is_instance_valid(_player):
		return
	var origin: Vector3 = global_position + Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT * 0.5, 0.0)
	var to_player: Vector3 = (_player.global_position + Vector3(0.0, 0.9, 0.0)) - origin
	var base_yaw: float = atan2(to_player.x, to_player.z)
	var pitch: float = to_player.normalized().y
	var spread: float = deg_to_rad(13.0)
	var col: Color = VaultBuild.LIGHT_POSITIVE if _drawing else VaultBuild.LIGHT_NEGATIVE
	for i in BOLTS_PER_VOLLEY:
		var offset: float = (float(i) - float(BOLTS_PER_VOLLEY - 1) * 0.5) * spread
		var yaw: float = base_yaw + offset
		var dir: Vector3 = Vector3(sin(yaw), pitch, cos(yaw)).normalized()
		Projectile.spawn(get_tree().current_scene, origin, dir, BOLT_SPEED,
				BOLT_DAMAGE, col)


## PlayerCombat's swing contract. `amount` and `knockback` are ignored on
## purpose — a keystone the size of a door does not stagger, and the fight is
## about WHEN you swing, not how hard. While drawing a strike adds charge;
## while refusing it takes the same amount away.
func apply_hit(_amount: float, from_position: Vector3, _knockback: float) -> void:
	if _spent:
		return
	var before: float = charge
	charge = clampf(charge + (STRIKE_CHARGE if _drawing else -STRIKE_CHARGE),
			0.0, THRESHOLD)
	var hit_at: Vector3 = global_position + Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT * 0.5, 0.0)
	var col: Color = VaultBuild.LIGHT_POSITIVE if _drawing else VaultBuild.LIGHT_NEGATIVE
	DamageShards.burst(get_tree().current_scene, hit_at, col, 10, 3.4, 1.6, 0.9)
	EventBus.combat_shake.emit(0.14 if _drawing else 0.08)
	# The shell flinches toward the blow so a refused hit still feels like
	# contact — the punishment is on the meter, not on the feedback.
	_flinch(from_position)
	# Deliberately does NOT emit EventBus.enemy_hit: that signal's second
	# argument is remaining hearts, and this boss has none. Passing charge
	# there would put a number in the contract that does not mean what the
	# signature says. enemy_defeated on the other hand is exactly true, and
	# is emitted in _fire().
	if charge >= THRESHOLD and before < THRESHOLD:
		_fire()


## A quick shove-and-return on the stone shell, away from the blow.
##
## The rest positions are the ones cached at build time, never the shell's
## current position: a three-hit combo lands faster than one flinch finishes,
## and reading the live position as "home" would let each overlapping tween
## start from the last one's displacement and walk the shell off the body.
func _flinch(from_position: Vector3) -> void:
	var away: Vector3 = global_position - from_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	# World offset into the body's own frame, so the shove reads correctly
	# whichever way the Gatekeeper happens to be facing.
	var push: Vector3 = global_transform.basis.inverse() * (away.normalized() * 0.22)
	for i in _shell.size():
		var part: MeshInstance3D = _shell[i]
		var rest: Vector3 = _shell_rest[i]
		var running: Tween = _shell_tweens[i]
		if running != null and running.is_valid():
			running.kill()
		var tw: Tween = create_tween()
		tw.tween_property(part, "position", rest + push, 0.05)
		tw.tween_property(part, "position", rest, 0.16)
		_shell_tweens[i] = tw


## The cell fires: the Gatekeeper cannot hold what it has summed, comes apart
## into shards (WORLDBOOK Part IV — never killed, never gore), and the vault
## opens behind it.
func _fire() -> void:
	if _spent:
		return
	_spent = true
	collision_layer = 0
	var center: Vector3 = global_position + Vector3(0.0, HOVER_HEIGHT + BODY_HEIGHT * 0.5, 0.0)
	DamageShards.burst(get_tree().current_scene, center, VaultBuild.LIGHT_POSITIVE,
			34, 7.0, 3.0, 1.6)
	EventBus.combat_shake.emit(0.5)
	EventBus.enemy_defeated.emit(monster_id, global_position)
	overloaded.emit()
	if _label != null:
		_label.visible = false
	# Collapse over a beat so the burst reads before the body goes.
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(queue_free)

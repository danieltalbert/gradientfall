class_name SignalFount
extends StaticBody3D
## One of the Perceptron Vault's two input pillars. It holds a single bit —
## lit or dark — and Kern flips it by hitting it with the sword.
##
## In ML terms this is an input x ∈ {0, 1} to the vault's 2-3-1 network; in
## world terms it is a stone basin that either carries signal or does not.
## Nothing in the vault ever says the former out loud (WORLDBOOK Part IV: the
## puns live in proper nouns and behavior, never in vocabulary).
##
## **Why it joins the "enemy" group.** PlayerCombat's swing only considers
## bodies that are in group "enemy" and expose `apply_hit()`. Rather than
## widen that contract from the dungeon (and collide with the sessions
## building other milestones), every strikeable vault prop wears the same
## costume: ENEMY collision layer, "enemy" group, `apply_hit()`. It is not in
## "hittable" — nothing here has hearts, and nothing here fights back.
##
## Built entirely in code by PerceptronVault; there is no fount scene. Emits
## `toggled` for the chamber network to recompute against, and plays a small
## shard puff on every flip so the strike always feels answered.

## Emitted whenever the fount's bit changes. `value` is 0 or 1.
signal toggled(value: int)

## Seconds a strike is ignored after a landed one. A three-hit combo would
## otherwise flip the bit three times and read as "the fount ignored me";
## one flip per swing is the intent.
const STRIKE_COOLDOWN: float = 0.42
## Basin dimensions, meters.
const PILLAR_HEIGHT: float = 2.2
const PILLAR_WIDTH: float = 1.1
## The floating bit-marble above the basin and how far it bobs.
const MARBLE_SIZE: float = 0.62
const BOB_AMPLITUDE: float = 0.09
const BOB_SPEED: float = 1.9

## Display name used on this fount's plaque ("the First Fount").
var fount_name: String = "Fount"
## The bit itself. Read by NeuronChamber every time the network recomputes.
var value: int = 0

var _cooldown: float = 0.0
var _marble: MeshInstance3D
var _basin_rune: MeshInstance3D
var _lamp: OmniLight3D
var _marble_base_y: float = 0.0
var _bob_t: float = 0.0


## Build a fount and parent it to `host`. `position` is the base of the
## pillar (floor level), and `start_value` seeds the bit — always 0 at build
## time, so a player entering a fresh vault finds it dark and inert.
static func build(host: Node3D, world_position: Vector3, display_name: String,
		start_value: int = 0) -> SignalFount:
	var f: SignalFount = SignalFount.new()
	f.fount_name = display_name
	f.value = clampi(start_value, 0, 1)
	f.position = world_position
	host.add_child(f)
	return f


func _ready() -> void:
	add_to_group(&"enemy")
	add_to_group(&"vault_prop")
	name = "Fount_" + fount_name.replace(" ", "_")
	collision_layer = CombatLayers.ENEMY
	collision_mask = 0
	_build()
	_refresh()


## Pillar, basin rim, the strike collider, and the floating marble that shows
## the bit. The collider is a single box covering the whole pillar so a swing
## anywhere along it registers — nobody should have to aim at a marble.
func _build() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(PILLAR_WIDTH, PILLAR_HEIGHT, PILLAR_WIDTH)
	shape.shape = box
	shape.position = Vector3(0.0, PILLAR_HEIGHT * 0.5, 0.0)
	add_child(shape)

	VaultBuild.decor(self, Vector3(0.0, PILLAR_HEIGHT * 0.5, 0.0),
			Vector3(PILLAR_WIDTH, PILLAR_HEIGHT, PILLAR_WIDTH), VaultBuild.STONE_WALL)
	VaultBuild.decor(self, Vector3(0.0, 0.14, 0.0),
			Vector3(PILLAR_WIDTH * 1.5, 0.28, PILLAR_WIDTH * 1.5), VaultBuild.STONE_TRIM)
	VaultBuild.decor(self, Vector3(0.0, PILLAR_HEIGHT + 0.09, 0.0),
			Vector3(PILLAR_WIDTH * 1.35, 0.18, PILLAR_WIDTH * 1.35), VaultBuild.STONE_TRIM)

	# A ring of light set into the basin's rim: the fount's own state, visible
	# from below when the marble is hidden behind the pillar.
	_basin_rune = VaultBuild.rune(self, Vector3(0.0, PILLAR_HEIGHT + 0.19, 0.0),
			Vector3(PILLAR_WIDTH * 1.15, 0.06, PILLAR_WIDTH * 1.15), VaultBuild.LIGHT_IDLE, 1.6)

	_marble_base_y = PILLAR_HEIGHT + 0.72
	_marble = VaultBuild.rune(self, Vector3(0.0, _marble_base_y, 0.0),
			Vector3(MARBLE_SIZE, MARBLE_SIZE, MARBLE_SIZE), VaultBuild.LIGHT_IDLE, 1.8)

	_lamp = VaultBuild.lamp(self, Vector3(0.0, _marble_base_y, 0.0),
			VaultBuild.LIGHT_IDLE, 0.0, 11.0)


## Bob the marble whether lit or dark — a fount is always powered, and a dead
## still marble would read as broken rather than as off.
func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_bob_t += delta * BOB_SPEED
	if _marble != null:
		_marble.position.y = _marble_base_y + sin(_bob_t) * BOB_AMPLITUDE
		_marble.rotation.y += delta * (0.9 if value == 1 else 0.25)


## PlayerCombat's swing contract. Damage and knockback are ignored — a fount
## has no hearts and cannot be pushed; a strike is a strike. Returns nothing,
## matching the signature Enemy exposes.
func apply_hit(_amount: float, _from_position: Vector3, _knockback: float) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = STRIKE_COOLDOWN
	value = 1 - value
	_refresh()
	# The puff reads as the strike landing, in the color the fount just became.
	DamageShards.burst(get_tree().current_scene,
			global_position + Vector3(0.0, _marble_base_y, 0.0),
			VaultBuild.LIGHT_POSITIVE if value == 1 else VaultBuild.LIGHT_IDLE,
			10, 3.0, 2.0, 0.7)
	EventBus.combat_shake.emit(0.05)
	toggled.emit(value)


## Push the bit out to every visible surface: marble, basin ring, and the
## pillar's fill light. A lit fount is gold and genuinely lights its corner
## of the hall; a dark one is cold and contributes nothing.
func _refresh() -> void:
	var lit: bool = value == 1
	var col: Color = VaultBuild.LIGHT_POSITIVE if lit else VaultBuild.LIGHT_IDLE
	VaultBuild.set_rune_color(_marble, col, 3.6 if lit else 0.7)
	VaultBuild.set_rune_pulse(_marble, 0.30 if lit else 0.10, 2.4)
	VaultBuild.set_rune_color(_basin_rune, col, 2.4 if lit else 0.5)
	if _lamp != null:
		_lamp.light_color = col
		_lamp.light_energy = 2.6 if lit else 0.0

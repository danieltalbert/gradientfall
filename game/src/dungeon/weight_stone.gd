class_name WeightStone
extends StaticBody3D
## A tunable weight set into a chamber wall — the Perceptron Vault's second
## verb. Kern strikes it and it steps to the next value on its own short
## ladder; the chamber's sum changes the instant it does.
##
## This is the milestone's teaching move. The vault's thresholds are fixed and
## the founts are only bits, so the ONLY way to make a chamber fire is to tune
## the weights until the sum clears the beam. Doing that by hand, chamber by
## chamber, is training a network by hand — the lesson arrives through the
## fingers rather than through a lecture.
##
## Each stone's ladder is fixed at build time and deliberately restricted:
## some sockets can only ever add (an excitatory input), others can only ever
## take away (an inhibitory one). Without that restriction the puzzle would
## collapse to "set everything to the maximum".
##
## Sign is carried by color everywhere in this dungeon and nowhere else: gold
## adds, blue takes away. Magnitude is carried by how many glyph bars light.
##
## Wears the same strikeable costume as SignalFount (ENEMY layer, "enemy"
## group, `apply_hit()`) for the reason documented there. Built in code by
## NeuronChamber; emits `changed` so the chamber can recompute.

## Emitted after a strike steps the ladder. `value` is the new weight.
signal changed(value: int)

const STRIKE_COOLDOWN: float = 0.42
## Socket dimensions, meters. The stone sits proud of the wall so its
## silhouette reads from across the chamber.
const STONE_SIZE: Vector3 = Vector3(1.0, 1.0, 0.55)
const GLYPH_BAR_SIZE: Vector3 = Vector3(0.62, 0.09, 0.06)
const GLYPH_BAR_GAP: float = 0.19
## Largest magnitude any ladder in the vault uses. Fixes how many glyph bars
## are built, so a stone's frame never has to be rebuilt when it steps.
const MAX_MAGNITUDE: int = 2

## The values this stone cycles through, in order, wrapping at the end.
var ladder: Array[int] = [1, 2]
## Index into `ladder`; `value` is derived from it.
var _rung: int = 0

var _face: MeshInstance3D
var _bars: Array[MeshInstance3D] = []
var _lamp: OmniLight3D
var _cooldown: float = 0.0


## Build a stone in a wall socket. `world_position` is the center of the
## stone's face, `facing_yaw` turns it to face into the room (radians), and
## `rungs` is the ladder — it must hold at least one value.
##
## `rungs` arrives untyped because the ladders live in a `const` table, and
## constants in Godot 4 are deeply read-only. `assign()` makes this stone a
## typed, mutable copy rather than aliasing the constant.
static func build(host: Node3D, world_position: Vector3, facing_yaw: float,
		rungs: Array) -> WeightStone:
	var s: WeightStone = WeightStone.new()
	var typed: Array[int] = []
	typed.assign(rungs)
	if typed.is_empty():
		typed.append(1)  # a stone with no ladder would be unstrikeable furniture
	s.ladder = typed
	s.position = world_position
	s.rotation.y = facing_yaw
	host.add_child(s)
	return s


func _ready() -> void:
	add_to_group(&"enemy")
	add_to_group(&"vault_prop")
	collision_layer = CombatLayers.ENEMY
	collision_mask = 0
	name = "WeightStone"
	_build()
	_refresh()


## Current weight. Always a member of `ladder`.
func value() -> int:
	return ladder[_rung]


## True if this socket can never contribute a positive weight — used by the
## chamber to write an honest plaque without hard-coding each socket's sign.
func is_inhibitory() -> bool:
	for v: int in ladder:
		if v > 0:
			return false
	return true


## Frame, strike collider, glyph face, and the fixed row of magnitude bars.
## Bars are built once for MAX_MAGNITUDE and simply lit or dimmed on change,
## so stepping the ladder never allocates.
func _build() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = STONE_SIZE * 1.25
	shape.shape = box
	shape.position = Vector3(0.0, 0.0, STONE_SIZE.z * 0.5)
	add_child(shape)

	# Surround: a stone frame a little larger than the glyph face.
	VaultBuild.decor(self, Vector3(0.0, 0.0, 0.0),
			Vector3(STONE_SIZE.x * 1.4, STONE_SIZE.y * 1.4, STONE_SIZE.z),
			VaultBuild.STONE_TRIM)
	_face = VaultBuild.rune(self, Vector3(0.0, 0.0, STONE_SIZE.z * 0.52),
			Vector3(STONE_SIZE.x, STONE_SIZE.y, 0.05), VaultBuild.LIGHT_IDLE, 1.4)

	# Magnitude bars, stacked and centered. Two bars lit means |w| = 2.
	var top: float = (float(MAX_MAGNITUDE) - 1.0) * GLYPH_BAR_GAP * 0.5
	for i in MAX_MAGNITUDE:
		var bar: MeshInstance3D = VaultBuild.rune(self,
				Vector3(0.0, top - float(i) * GLYPH_BAR_GAP, STONE_SIZE.z * 0.56),
				GLYPH_BAR_SIZE, VaultBuild.LIGHT_IDLE, 2.0)
		_bars.append(bar)

	_lamp = VaultBuild.lamp(self, Vector3(0.0, 0.0, STONE_SIZE.z + 0.5),
			VaultBuild.LIGHT_IDLE, 0.0, 7.0)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


## PlayerCombat's swing contract — see SignalFount for why a wall fixture
## answers to it. Steps one rung per swing and never wraps mid-combo.
func apply_hit(_amount: float, _from_position: Vector3, _knockback: float) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = STRIKE_COOLDOWN
	_rung = (_rung + 1) % ladder.size()
	_refresh()
	DamageShards.burst(get_tree().current_scene,
			global_position + global_transform.basis.z * 0.6,
			_sign_color(), 9, 2.6, 1.6, 0.6)
	EventBus.combat_shake.emit(0.05)
	changed.emit(value())


## Gold for a weight that adds, blue for one that takes away. This mapping is
## the dungeon's entire notation and is never reused for decoration.
func _sign_color() -> Color:
	return VaultBuild.LIGHT_POSITIVE if value() > 0 else VaultBuild.LIGHT_NEGATIVE


## Repaint the face and light exactly |value| bars. Unlit bars stay visible
## at low energy so the player can see how much room the ladder still has.
func _refresh() -> void:
	var col: Color = _sign_color()
	var magnitude: int = absi(value())
	VaultBuild.set_rune_color(_face, col, 1.9)
	for i in _bars.size():
		var lit: bool = i < magnitude
		VaultBuild.set_rune_color(_bars[i], col if lit else VaultBuild.LIGHT_IDLE,
				3.4 if lit else 0.45)
	if _lamp != null:
		_lamp.light_color = col
		_lamp.light_energy = 0.7 + 0.5 * float(magnitude)

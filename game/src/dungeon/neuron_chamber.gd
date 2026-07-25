class_name NeuronChamber
extends Node3D
## One chamber of the Perceptron Vault's hidden row — a single neuron you can
## walk around inside.
##
## The chamber takes two signals in, multiplies each by the weight sitting in
## its socket, stacks the results into the sum column at the room's center,
## and fires if that column reaches the threshold beam. That is the whole of
## `y = step(w1*x1 + w2*x2 - θ)`, at walking scale, with the weights as
## objects you can hit.
##
## Reading the room, with no text at all:
## * the two wall sockets are the inputs — gold stone adds, blue takes away
## * the column in the middle is the running sum; gold rising means the sum
##   is positive, blue means it went the wrong way
## * the ring of light around the room at a fixed height is the threshold
## * column over ring = the chamber fires, the room warms, the outbound
##   conduit lights and carries signal onward
##
## Where it sits: built by PerceptronVault, which owns the two SignalFounts
## and calls `recompute()` whenever any fount or stone changes. The chamber
## owns its two WeightStones and reports its own firing state upward; it
## never reaches for the network around it.
##
## Units: sums are plain integers (weights are integers, inputs are bits), and
## the column converts them to meters through `METERS_PER_UNIT`.

## Emitted when the chamber's firing state changes, so the vault can relight
## the conduits into the output chamber.
signal fired_changed(firing: bool)
## Emitted when one of this chamber's weight stones was struck. The chamber
## cannot see the founts, so it asks the vault to re-run the whole network
## rather than guessing — one code path for every recompute.
signal needs_recompute()

## How tall one unit of sum stands. With weights in ±2 and two inputs the sum
## spans -4..4, so the column tops out at 3.6 m inside an 8 m room.
const METERS_PER_UNIT: float = 0.9
## Interior clear volume of a chamber, meters (x, y, z).
const INNER: Vector3 = Vector3(14.0, 8.0, 18.0)
const WALL_THICKNESS: float = 1.2
## Door opening cut through the north and south walls.
const DOOR_WIDTH: float = 5.0
const DOOR_HEIGHT: float = 4.6
## The sum column's footprint. Tall and thin so its top edge is unambiguous.
const COLUMN_WIDTH: float = 1.15
## Full height of the column mesh — the meter's 100% mark. Sized to the
## largest sum the ladders can produce so the fill never clips.
const COLUMN_HEIGHT: float = 4.0
## Seconds the column takes to slide to a new sum. Instant would make the
## cause-and-effect of a strike harder to read, not easier.
const COLUMN_EASE: float = 6.0

## Display name, used on the chamber's plaque ("the First Chamber").
var chamber_name: String = "Chamber"
## The sum this chamber must reach to fire — its bias, with the sign flipped
## into the form a stonecutter would carve.
var threshold: int = 1
## True while `sum >= threshold`.
var firing: bool = false
## The chamber's live weighted sum. Integer: weights and inputs both are.
var sum: int = 0

var _stones: Array[WeightStone] = []
var _column: MeshInstance3D
## The four perimeter segments of the threshold ring.
var _beam: Array[MeshInstance3D] = []
var _out_rune: MeshInstance3D
var _room_lamp: OmniLight3D
var _shown_fill: float = 0.0
var _target_fill: float = 0.0
## World-space center of the chamber floor, cached for the fight and for the
## vault's conduit routing.
var _center: Vector3 = Vector3.ZERO


## Build a chamber. `center` is the middle of its floor in vault-local space,
## `ladders` holds the two weight ladders for the two sockets (west socket
## first) as plain integer arrays, and `fires_at` is the threshold.
static func build(host: Node3D, center: Vector3, display_name: String,
		ladders: Array, fires_at: int) -> NeuronChamber:
	var c: NeuronChamber = NeuronChamber.new()
	c.chamber_name = display_name
	c.threshold = fires_at
	c.position = center
	host.add_child(c)
	c._build(ladders)
	return c


func _ready() -> void:
	name = "Chamber_" + chamber_name.replace(" ", "_")


## Room shell, sockets, column, threshold beam, and the outbound rune. Called
## by `build()` after the node is in the tree, so `_center` can be resolved in
## world space for the conduits the vault runs between chambers.
func _build(ladders: Array) -> void:
	_center = global_position

	var doors: Array[Dictionary] = [
		{"side": "north", "width": DOOR_WIDTH, "height": DOOR_HEIGHT, "offset": 0.0},
		{"side": "south", "width": DOOR_WIDTH, "height": DOOR_HEIGHT, "offset": 0.0},
	]
	VaultBuild.room(self, Vector3.ZERO, INNER, WALL_THICKNESS, doors)

	# Sockets face each other across the room, set into the side walls at
	# chest height so a swing connects without aiming up or down.
	var socket_x: float = INNER.x * 0.5 - 0.35
	var socket_y: float = 1.55
	_stones.append(WeightStone.build(self, Vector3(-socket_x, socket_y, -2.2),
			deg_to_rad(90.0), ladders[0]))
	_stones.append(WeightStone.build(self, Vector3(socket_x, socket_y, -2.2),
			deg_to_rad(-90.0), ladders[1]))
	for s: WeightStone in _stones:
		s.changed.connect(_on_stone_changed)

	# The sum column: a plinth, then the glass tube that fills.
	VaultBuild.decor(self, Vector3(0.0, 0.2, 1.0),
			Vector3(COLUMN_WIDTH * 1.9, 0.4, COLUMN_WIDTH * 1.9), VaultBuild.STONE_TRIM)
	_column = VaultBuild.rune(self,
			Vector3(0.0, 0.4 + COLUMN_HEIGHT * 0.5, 1.0),
			Vector3(COLUMN_WIDTH, COLUMN_HEIGHT, COLUMN_WIDTH),
			VaultBuild.LIGHT_POSITIVE, 2.6)
	VaultBuild.set_rune_fill(_column, 0.0)
	VaultBuild.set_rune_flow(_column, 0.55, 0.7, 0.5)

	# The threshold beam: a thin ring of light running the full perimeter at
	# exactly the height the column must reach. Four bars hugging the walls,
	# not one slab across the room — the ring has to frame the column, not
	# hide it. Being room-wide rather than column-local is the point: you can
	# judge the remaining gap from anywhere in the chamber.
	var beam_y: float = 0.4 + float(threshold) * METERS_PER_UNIT
	var bar: float = 0.09
	var edge_x: float = INNER.x * 0.5 - bar * 0.5
	var edge_z: float = INNER.z * 0.5 - bar * 0.5
	for spec: Array in [
		[Vector3(0.0, beam_y, -edge_z), Vector3(INNER.x, bar, bar)],
		[Vector3(0.0, beam_y, edge_z), Vector3(INNER.x, bar, bar)],
		[Vector3(-edge_x, beam_y, 0.0), Vector3(bar, bar, INNER.z)],
		[Vector3(edge_x, beam_y, 0.0), Vector3(bar, bar, INNER.z)],
	]:
		var seg: MeshInstance3D = VaultBuild.rune(self, spec[0] as Vector3,
				spec[1] as Vector3, Color(0.95, 0.93, 0.86), 1.5)
		VaultBuild.set_rune_pulse(seg, 0.22, 1.1)
		_beam.append(seg)

	# Outbound marker over the south door: dark until the chamber fires.
	_out_rune = VaultBuild.rune(self,
			Vector3(0.0, DOOR_HEIGHT + 0.7, INNER.z * 0.5 - 0.1),
			Vector3(3.2, 0.34, 0.12), VaultBuild.LIGHT_IDLE, 1.0)

	_room_lamp = VaultBuild.lamp(self, Vector3(0.0, INNER.y - 1.4, 0.0),
			VaultBuild.LIGHT_IDLE, 1.5, 22.0)

	_build_plaque()


## The chamber's carved instruction. Written as the vault's builders would
## have written it — an operating note for whoever comes after, never a
## tutorial, and never using the vocabulary the mechanic is named for.
func _build_plaque() -> void:
	var sign_note: String = "Both stones here will add." if not _has_inhibitory() \
			else "One stone here can only take away."
	# Above the north doorway's 4.6 m lintel and clear of the 8 m ceiling.
	# Carved at eye height it would sit across the open doorway instead of
	# on stone.
	VaultBuild.plaque(self,
			Vector3(0.0, 5.9, -INNER.z * 0.5 + 0.12),
			"%s\nIt opens at %d.\n%s" % [chamber_name, threshold, sign_note],
			9.0, 34)


func _has_inhibitory() -> bool:
	for s: WeightStone in _stones:
		if s.is_inhibitory():
			return true
	return false


## Recompute the sum from the two input bits and repaint the room. Called by
## PerceptronVault on any fount change and by this chamber on any stone
## change, so the two paths can never disagree about the current state.
func recompute(input_a: int, input_b: int) -> void:
	sum = _stones[0].value() * input_a + _stones[1].value() * input_b
	var now_firing: bool = sum >= threshold
	_target_fill = clampf(float(absi(sum)) * METERS_PER_UNIT / COLUMN_HEIGHT, 0.0, 1.0)

	# Sign lives in the column's color, exactly as it does on the stones: a
	# blue column is the unmistakable "you pushed it the wrong way".
	var col: Color = VaultBuild.LIGHT_POSITIVE if sum >= 0 else VaultBuild.LIGHT_NEGATIVE
	VaultBuild.set_rune_color(_column, col, 2.6)

	if now_firing != firing:
		firing = now_firing
		_on_fire_changed()


## Everything that changes when the chamber crosses its threshold: the
## outbound rune, the room's fill light, a shard burst at the column head,
## and the signal upward. Only ever called on an actual transition, so the
## burst marks the moment rather than every recompute.
func _on_fire_changed() -> void:
	var col: Color = VaultBuild.LIGHT_POSITIVE if firing else VaultBuild.LIGHT_IDLE
	VaultBuild.set_rune_color(_out_rune, col, 3.4 if firing else 0.8)
	VaultBuild.set_rune_flow(_out_rune, 0.9 if firing else 0.0, 1.6, 0.8)
	if _room_lamp != null:
		_room_lamp.light_color = col
		_room_lamp.light_energy = 3.2 if firing else 1.5
	# A firing chamber's threshold ring steadies — the sum has cleared it and
	# it has nothing left to ask for.
	for seg: MeshInstance3D in _beam:
		VaultBuild.set_rune_pulse(seg, 0.12 if firing else 0.22, 1.1)
	if is_inside_tree():
		DamageShards.burst(get_tree().current_scene,
				global_position + Vector3(0.0, 0.4 + COLUMN_HEIGHT * _shown_fill, 1.0),
				col, 14 if firing else 8, 3.6, 2.2, 0.9)
		EventBus.combat_shake.emit(0.08 if firing else 0.04)
	fired_changed.emit(firing)


## The column eases toward its target rather than snapping, so a strike reads
## as "the sum moved" instead of "the room changed". Exponential smoothing:
## frame-rate independent, and it settles without overshoot.
func _process(delta: float) -> void:
	if absf(_shown_fill - _target_fill) < 0.001:
		return
	_shown_fill = lerpf(_shown_fill, _target_fill, 1.0 - exp(-COLUMN_EASE * delta))
	VaultBuild.set_rune_fill(_column, _shown_fill)


## A stone stepped — hand it up to the vault, which owns the input bits.
func _on_stone_changed(_value: int) -> void:
	needs_recompute.emit()


## World-space point where this chamber's outbound conduit starts.
func outlet_position() -> Vector3:
	return _center + Vector3(0.0, DOOR_HEIGHT + 0.7, INNER.z * 0.5)

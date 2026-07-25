class_name PerceptronVault
extends Node3D
## Dungeon 1 — **the Perceptron Vault** (Phase 1 milestone 12).
##
## The WORLDBOOK's brief for Datasedge Meadows is one sentence: "route glowing
## signals through weight-doors so the output gate fires; mini-boss the
## Gatekeeper (sums what hits it; overload it). Teaches: what a neuron does."
## The ROADMAP adds "traverse an actual neural network". This is that, built at
## walking scale: the vault IS a 2-3-1 network, laid out along its own axis,
## and Kern walks its layers in order.
##
##     two Signal Founts        (the inputs, x ∈ {0,1})
##       ↓
##     three Neuron Chambers    (the hidden row — each a room you stand inside)
##       ↓
##     the Junction             (the output cell's three weights)
##       ↓
##     the Gatekeeper           (the output cell, and the fight)
##       ↓
##     the Output Gate          (opens when the cell fires)
##
## The 2-3-1 figure is carved over the door and over the gate, and it is the
## same sigil already on the game's icon.
##
## **The puzzle is real and it is solvable exactly one way.** The thresholds
## are fixed; every weight steps through a short, restricted ladder — some
## sockets can only add, some can only take away. To light all three chambers
## and clear the output cell's threshold, a player has to work out that both
## founts must be lit and each chamber tuned to its best positive setting.
## That is a small network solved by hand, which is the lesson.
##
## **The fight does not require the puzzle** (GDD §3: no hard gates; danger
## and cleverness are the gates). A solved vault feeds the Gatekeeper while
## Kern dodges; an unsolved one means overloading it by sword alone against
## its leak. Both are intended routes.
##
## Where it sits: instanced by `Main._setup_vault()` in one line, per the
## "Wiring new systems into main.gd" convention in docs/ARCHITECTURE.md.
## Everything is built in code — there is no vault scene and no imported
## asset. It owns its own BitLandmark, so `MeadowLandmarks` needs no edit.
## Reads MeadowTerrain for its site, writes GameState (clear flag, Tokens,
## the reliquary item), and emits nothing on the EventBus itself — the
## Gatekeeper's `enemy_defeated` and GameState's `item_acquired` /
## `tokens_changed` already say everything a listener needs.
##
## Units: meters and seconds. Local space has the entrance at -Z (north, the
## same compass the meadow uses) and the gate at +Z.

# --- Placement ---------------------------------------------------------------

## Where the vault stands in the meadow, in world XZ. Chosen to be clear of
## every existing canon site: 117 m from Bootstrap (well outside the town
## flat), 122 m from the millpond, and 151 m from the nearest iris cluster —
## so it crowds nothing already built and leaves the iris flats to the
## compendium milestone.
const SITE: Vector2 = Vector2(64.0, 128.0)
## Clearance above the highest ground under the footprint. The floor is set
## from a survey of the terrain rather than a hard-coded height, so no hill
## can ever poke up through a chamber floor.
const FLOOR_CLEARANCE: float = 1.2
## Survey grid spacing (m) used to find that highest point.
const SURVEY_STEP: float = 6.0

# --- Architecture ------------------------------------------------------------

const WALL: float = 1.2                 ## wall/slab thickness
const HALL_INNER: Vector3 = Vector3(44.4, 8.0, 18.0)
const CHAMBER_PITCH: float = 15.2       ## chamber inner width + one wall
const JUNCTION_INNER: Vector3 = Vector3(44.4, 8.0, 12.0)
const ARENA_INNER: Vector3 = Vector3(44.4, 10.0, 30.0)
const RELIQUARY_INNER: Vector3 = Vector3(14.0, 6.0, 10.0)
const DOOR_W: float = 6.0
const DOOR_H: float = 5.0
## The output gate's opening.
const GATE_W: float = 8.0
const GATE_H: float = 6.0
## Approach ramp from the meadow up onto the vault's plinth.
const RAMP_LENGTH: float = 26.0
const RAMP_WIDTH: float = 14.0
const RAMP_THICKNESS: float = 1.0
## The platform the whole vault stands on. Wide and long enough to carry the
## facade at one end and the reliquary at the other, with an apron to spare.
const PLINTH_X_SPAN: float = 58.0
const PLINTH_Z_SPAN: float = 108.0
const PLINTH_Z: float = 12.0

# Z centers of each space, north (entrance) to south (reliquary).
const HALL_Z: float = -25.0
const CHAMBER_Z: float = -5.0
const JUNCTION_Z: float = 11.0
const ARENA_Z: float = 33.0
const RELIQUARY_Z: float = 55.0

# --- The network -------------------------------------------------------------

## The three hidden chambers: display name, the two weight ladders (west
## socket first), and the threshold each must reach.
##
## The ladders are the puzzle. Read them as a constraint system: Gamma can
## only fire with both founts lit and both its stones at maximum, which forces
## x1 = x2 = 1; with both lit, Alpha and Beta each have exactly one setting
## that reaches 1, because each carries a socket that can only subtract.
## Ladders are plain integer arrays so this whole table stays a constant
## expression — a `PackedInt32Array(...)` call would not be one, and GDScript
## rejects it in a `const`.
const CHAMBERS: Array[Dictionary] = [
	{
		"name": "the First Chamber",
		"ladders": [[1, 2], [-2, -1]],
		"threshold": 1,
	},
	{
		"name": "the Second Chamber",
		"ladders": [[-2, -1], [1, 2]],
		"threshold": 1,
	},
	{
		"name": "the Third Chamber",
		"ladders": [[1, 2], [1, 2]],
		"threshold": 3,
	},
]

## The output cell's three weight ladders (one per chamber, west to east) and
## its threshold. With every ladder capped at +2 the sum tops out at 6, so a
## threshold of 5 cannot be reached unless all three chambers fire — the
## output cell is what makes the hidden row matter.
const OUTPUT_LADDERS: Array = [[1, 2], [1, 2], [1, 2]]
const OUTPUT_THRESHOLD: int = 5
## Meters of column per unit of sum in the junction, and the column's full
## height (the meter's 100% mark, sized for the largest reachable sum).
const OUTPUT_METERS_PER_UNIT: float = 0.85
const OUTPUT_COLUMN_HEIGHT: float = 5.4

# --- Rewards -----------------------------------------------------------------

## GameState flag written once the gate opens. Part of the already-serialized
## flags dictionary, so this needs no change to the save shape and no
## SAVE_VERSION bump (CLAUDE.md iron rule 6).
const CLEARED_FLAG: String = "vault_perceptron_cleared"
const REWARD_TOKENS: int = 120
const REWARD_ITEM: String = "item_threshold_stone"

var _terrain: MeadowTerrain
var _founts: Array[SignalFount] = []
var _chambers: Array[NeuronChamber] = []
var _output_stones: Array[WeightStone] = []
var _gate: VaultGate
var _gatekeeper: VaultGatekeeper
## Floor height in world space; local y = 0 sits here. Both come from the
## build-time terrain survey.
var _floor_y: float = 0.0
var _lowest_ground: float = 0.0
var _output_column: MeshInstance3D
var _output_beam: Array[MeshInstance3D] = []
var _output_sum: int = 0
var _output_firing: bool = false
var _shown_output_fill: float = 0.0
var _target_output_fill: float = 0.0
## Conduit strips, relit as the network changes.
var _fount_conduits: Array[MeshInstance3D] = []
var _chamber_conduits: Array[MeshInstance3D] = []
var _arena_conduit: MeshInstance3D
var _cleared: bool = false


## Build the vault into `host` against `terrain`. The only entry point;
## `Main._setup_vault()` is its one caller.
static func build(host: Node3D, terrain: MeadowTerrain) -> PerceptronVault:
	var v: PerceptronVault = PerceptronVault.new()
	v.name = "PerceptronVault"
	v._terrain = terrain
	host.add_child(v)
	v._raise_and_build()
	return v


## Survey the ground, settle the floor height, then build every space.
## Split out of `build()` only so the node is already in the tree when the
## rooms resolve their world positions.
func _raise_and_build() -> void:
	var ground: Vector2 = _survey_ground()
	_lowest_ground = ground.x
	_floor_y = ground.y + FLOOR_CLEARANCE
	global_position = Vector3(SITE.x, _floor_y, SITE.y)

	_build_plinth()
	_build_hall()
	_build_chambers()
	_build_junction()
	_build_arena()
	_build_reliquary()
	_build_conduits()
	_build_landmark()

	# A returning player who already cleared it finds the gate standing open
	# and no Gatekeeper waiting — the world matches the save without needing
	# save/load to exist yet.
	if GameState.has_flag(CLEARED_FLAG):
		_cleared = true
		_gate.open_instantly()

	solve()
	print("PerceptronVault: built at (%.0f, %.0f), floor y=%.2f — %s." % [
		SITE.x, SITE.y, _floor_y,
		"already cleared" if _cleared else "sealed",
	])


## World Y of every interior floor in the vault. Read by `main.gd` so the
## screenshot rig can stand inside the vault instead of sampling terrain
## height and dropping through the plinth.
func floor_height() -> float:
	return _floor_y


## Sample the ground across the vault's footprint and return
## `Vector2(lowest, highest)` in world Y.
##
## Measuring rather than assuming is the whole point: the meadow's height is
## generated from noise and has already been re-tuned several times. The
## highest point (plus clearance) sets the floor, so no hill can ever push up
## through a chamber; the lowest sets how deep the plinth must reach, so no
## daylight shows under the vault from downhill.
func _survey_ground() -> Vector2:
	var lowest: float = INF
	var highest: float = -INF
	var x: float = -PLINTH_X_SPAN * 0.5
	while x <= PLINTH_X_SPAN * 0.5:
		var z: float = PLINTH_Z - PLINTH_Z_SPAN * 0.5
		while z <= PLINTH_Z + PLINTH_Z_SPAN * 0.5:
			var h: float = _terrain.get_height(SITE.x + x, SITE.y + z)
			lowest = minf(lowest, h)
			highest = maxf(highest, h)
			z += SURVEY_STEP
		x += SURVEY_STEP
	return Vector2(lowest, highest)


## The stone platform the whole vault stands on, and the ramp up to its door.
## The plinth is sunk to the lowest ground in the footprint, so from downhill
## the vault reads as half-buried rather than as a box on stilts.
func _build_plinth() -> void:
	# The plinth's TOP is flush with local y = 0 — the same plane as every
	# room's interior floor. That is what lets Kern walk from the ramp across
	# the apron and in through the door without a single step to catch on.
	var depth: float = maxf(3.0, _floor_y - _lowest_ground + 2.0)
	VaultBuild.solid(self, Vector3(0.0, -depth * 0.5, PLINTH_Z),
			Vector3(PLINTH_X_SPAN, depth, PLINTH_Z_SPAN), VaultBuild.STONE_DARK)
	# A lip just under the top edge — what sells "built" rather than
	# "extruded" when you walk up to it.
	VaultBuild.decor(self, Vector3(0.0, -0.35, PLINTH_Z),
			Vector3(PLINTH_X_SPAN + 1.6, 0.7, PLINTH_Z_SPAN + 1.6), VaultBuild.STONE_TRIM)

	# Approach ramp, from the plinth's north edge down to the meadow. Its far
	# end meets whatever height the terrain happens to be, so the slope is
	# measured, never assumed.
	var edge_z: float = PLINTH_Z - PLINTH_Z_SPAN * 0.5
	var far_z: float = edge_z - RAMP_LENGTH
	var drop: float = _floor_y - _terrain.get_height(SITE.x, SITE.y + far_z)
	var pitch: float = atan2(drop, RAMP_LENGTH)
	var length: float = sqrt(RAMP_LENGTH * RAMP_LENGTH + drop * drop)
	# Place the slab by its TOP face: that surface must pass through
	# (edge_z, y=0) and (far_z, y=-drop), so its midpoint is the average of
	# the two, and the box center sits half a thickness along the face
	# normal, back into the slab.
	var top_mid: Vector3 = Vector3(0.0, -drop * 0.5, (edge_z + far_z) * 0.5)
	var normal: Vector3 = Vector3(0.0, cos(pitch), -sin(pitch))
	var ramp: MeshInstance3D = VaultBuild.solid(self,
			top_mid - normal * (RAMP_THICKNESS * 0.5),
			Vector3(RAMP_WIDTH, RAMP_THICKNESS, length), VaultBuild.STONE_FLOOR)
	# Pitch about X so the slab's long Z axis runs down the slope.
	ramp.rotation.x = -pitch


## Facade and the Input Hall: the two founts, the entrance, and the sigil.
func _build_hall() -> void:
	VaultBuild.room(self, Vector3(0.0, 0.0, HALL_Z), HALL_INNER, WALL, [
		{"side": "north", "width": DOOR_W, "height": DOOR_H, "offset": 0.0},
		# A full-height, full-width "opening" in the south wall emits no wall
		# at all — the three chambers' own north walls are the boundary here,
		# and each carries its own doorway.
		{"side": "south", "width": HALL_INNER.x, "height": HALL_INNER.y, "offset": 0.0},
	])

	# The facade: a monolith standing proud of the hall's north wall, with the
	# vault's mark above the door. This is the "something is actually there"
	# silhouette from across the meadow (GDD design pillar 4).
	var face_z: float = HALL_Z - HALL_INNER.z * 0.5 - WALL - 1.0
	VaultBuild.decor(self, Vector3(-14.0, 6.0, face_z), Vector3(18.0, 12.0, 2.0),
			VaultBuild.STONE_WALL)
	VaultBuild.decor(self, Vector3(14.0, 6.0, face_z), Vector3(18.0, 12.0, 2.0),
			VaultBuild.STONE_WALL)
	VaultBuild.decor(self, Vector3(0.0, 9.4, face_z), Vector3(10.0, 5.2, 2.0),
			VaultBuild.STONE_WALL)
	VaultBuild.decor(self, Vector3(0.0, 13.2, face_z + 0.2), Vector3(48.0, 1.4, 2.6),
			VaultBuild.STONE_TRIM)
	_build_sigil(Vector3(0.0, 8.6, face_z - 1.2), 4.6, VaultBuild.LIGHT_IDLE)

	# Two founts, set symmetrically about the hall's axis so the pairing with
	# the two ladders in each chamber is obvious from the doorway.
	_founts.append(SignalFount.build(self, Vector3(-9.0, 0.0, HALL_Z + 1.0),
			"the First Fount"))
	_founts.append(SignalFount.build(self, Vector3(9.0, 0.0, HALL_Z + 1.0),
			"the Second Fount"))
	for f: SignalFount in _founts:
		f.toggled.connect(_on_fount_toggled)

	# Above the door lintel (5 m) and clear of the 8 m ceiling — carved where
	# you read it on the way back out, which is when it starts to make sense.
	VaultBuild.plaque(self, Vector3(0.0, 6.4, HALL_Z - HALL_INNER.z * 0.5 + 0.15),
			"THE PERCEPTRON VAULT\n"
			+ "Two founts feed three chambers.\n"
			+ "Three chambers feed the one beyond.\n"
			+ "Strike a fount to wake it. Strike a stone to set it.\n"
			+ "The gate opens for a sum, not for a key.",
			16.0, 34)

	VaultBuild.lamp(self, Vector3(0.0, HALL_INNER.y - 1.2, HALL_Z),
			Color(0.86, 0.82, 0.72), 2.2, 34.0)
	VaultBuild.lamp(self, Vector3(0.0, 3.0, HALL_Z - HALL_INNER.z * 0.5 + 2.0),
			Color(0.98, 0.86, 0.62), 1.6, 18.0)


## The three hidden chambers, side by side. Their inner walls are coincident
## by construction: pitch is exactly inner width plus one wall thickness, so
## neighbouring rooms share a single slab instead of leaving a cavity.
func _build_chambers() -> void:
	for i in CHAMBERS.size():
		var spec: Dictionary = CHAMBERS[i]
		var x: float = (float(i) - 1.0) * CHAMBER_PITCH
		var chamber: NeuronChamber = NeuronChamber.build(self,
				Vector3(x, 0.0, CHAMBER_Z), str(spec["name"]),
				spec["ladders"] as Array, int(spec["threshold"]))
		chamber.needs_recompute.connect(solve)
		_chambers.append(chamber)


## The Junction: where the three chambers' results are weighed together. Three
## pedestals (the output cell's weights), one sum column, one threshold ring.
##
## The arithmetic here is the same dot-product-and-compare a NeuronChamber
## does, but the housing is a corridor with three free-standing stones rather
## than a room with two wall sockets, and the cell has three inputs instead of
## two — so it is written out here rather than bent into NeuronChamber.
func _build_junction() -> void:
	VaultBuild.room(self, Vector3(0.0, 0.0, JUNCTION_Z), JUNCTION_INNER, WALL, [
		# No north wall — the chambers' south walls close this side.
		{"side": "north", "width": JUNCTION_INNER.x, "height": JUNCTION_INNER.y,
			"offset": 0.0},
		{"side": "south", "width": DOOR_W, "height": DOOR_H, "offset": 0.0},
	])

	for i in OUTPUT_LADDERS.size():
		var x: float = (float(i) - 1.0) * CHAMBER_PITCH
		# A plinth under each stone: these are posts in a corridor, not
		# fixtures in a wall, so they need something to stand on.
		VaultBuild.decor(self, Vector3(x, 0.55, JUNCTION_Z - 2.6),
				Vector3(1.6, 1.1, 1.6), VaultBuild.STONE_TRIM)
		# Facing north (PI), toward the chamber whose result it weighs, so a
		# player walking out of that chamber meets its stone face-on.
		var stone: WeightStone = WeightStone.build(self,
				Vector3(x, 1.75, JUNCTION_Z - 2.6), PI, OUTPUT_LADDERS[i])
		stone.changed.connect(_on_output_stone_changed)
		_output_stones.append(stone)

	VaultBuild.decor(self, Vector3(0.0, 0.2, JUNCTION_Z + 3.4),
			Vector3(2.4, 0.4, 2.4), VaultBuild.STONE_TRIM)
	_output_column = VaultBuild.rune(self,
			Vector3(0.0, 0.4 + OUTPUT_COLUMN_HEIGHT * 0.5, JUNCTION_Z + 3.4),
			Vector3(1.35, OUTPUT_COLUMN_HEIGHT, 1.35), VaultBuild.LIGHT_POSITIVE, 2.8)
	VaultBuild.set_rune_fill(_output_column, 0.0)
	VaultBuild.set_rune_flow(_output_column, 0.55, 0.7, 0.5)

	var beam_y: float = 0.4 + float(OUTPUT_THRESHOLD) * OUTPUT_METERS_PER_UNIT
	var bar: float = 0.1
	var ex: float = JUNCTION_INNER.x * 0.5 - bar
	var ez: float = JUNCTION_INNER.z * 0.5 - bar
	for spec: Array in [
		[Vector3(0.0, beam_y, JUNCTION_Z - ez), Vector3(JUNCTION_INNER.x, bar, bar)],
		[Vector3(0.0, beam_y, JUNCTION_Z + ez), Vector3(JUNCTION_INNER.x, bar, bar)],
		[Vector3(-ex, beam_y, JUNCTION_Z), Vector3(bar, bar, JUNCTION_INNER.z)],
		[Vector3(ex, beam_y, JUNCTION_Z), Vector3(bar, bar, JUNCTION_INNER.z)],
	]:
		var seg: MeshInstance3D = VaultBuild.rune(self, spec[0] as Vector3,
				spec[1] as Vector3, Color(0.95, 0.93, 0.86), 1.5)
		VaultBuild.set_rune_pulse(seg, 0.22, 1.1)
		_output_beam.append(seg)

	# On the junction's SOUTH wall, so it faces back north into the room —
	# hence the PI yaw. Above the 5 m doorway to the arena.
	VaultBuild.plaque(self, Vector3(0.0, 6.3, JUNCTION_Z + JUNCTION_INNER.z * 0.5 - 0.15),
			"Three chambers answer here.\nThe one beyond opens at %d."
					% OUTPUT_THRESHOLD, 11.0, 38, PI)
	VaultBuild.lamp(self, Vector3(0.0, JUNCTION_INNER.y - 1.2, JUNCTION_Z),
			Color(0.84, 0.80, 0.72), 2.0, 30.0)


## The Gatekeeper's arena and the output gate in its far wall. The boss is
## not built here — it wakes when Kern crosses the threshold, so a player
## walking back to re-tune a stone does not leave a boss idling in an empty
## room, and screenshot runs never spawn one.
func _build_arena() -> void:
	VaultBuild.room(self, Vector3(0.0, 0.0, ARENA_Z), ARENA_INNER, WALL, [
		{"side": "north", "width": DOOR_W, "height": DOOR_H, "offset": 0.0},
		{"side": "south", "width": GATE_W, "height": GATE_H, "offset": 0.0},
	])
	# Corner braziers: enough light to fight by, warm against the arena's
	# cold stone, and four of them so the boss always casts a readable
	# silhouette whichever way the camera swings.
	for cx: float in [-16.0, 16.0]:
		for cz: float in [ARENA_Z - 11.0, ARENA_Z + 11.0]:
			VaultBuild.decor(self, Vector3(cx, 1.1, cz), Vector3(1.0, 2.2, 1.0),
					VaultBuild.STONE_TRIM)
			VaultBuild.rune(self, Vector3(cx, 2.4, cz), Vector3(0.7, 0.5, 0.7),
					Color(1.0, 0.72, 0.38), 2.6)
			VaultBuild.lamp(self, Vector3(cx, 2.9, cz), Color(1.0, 0.78, 0.5),
					2.6, 22.0)

	var gate_z: float = ARENA_Z + ARENA_INNER.z * 0.5 + WALL * 0.5
	_gate = VaultGate.build(self, Vector3(0.0, 0.0, gate_z), GATE_W, GATE_H, WALL)

	# The trigger that wakes the boss: the arena's own doorway.
	var trigger: Area3D = Area3D.new()
	trigger.name = "ArenaTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = CombatLayers.PLAYER
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(ARENA_INNER.x, ARENA_INNER.y, 6.0)
	shape.shape = box
	trigger.add_child(shape)
	trigger.position = Vector3(0.0, ARENA_INNER.y * 0.5, ARENA_Z - ARENA_INNER.z * 0.5 + 3.0)
	trigger.body_entered.connect(_on_arena_entered)
	add_child(trigger)


## Beyond the gate: what the vault was built to keep. The reward is granted
## the moment the gate opens rather than on touching the plinth, so a player
## who clears the fight and walks away still keeps it.
func _build_reliquary() -> void:
	VaultBuild.room(self, Vector3(0.0, 0.0, RELIQUARY_Z), RELIQUARY_INNER, WALL, [
		{"side": "north", "width": GATE_W, "height": GATE_H, "offset": 0.0},
	])
	VaultBuild.decor(self, Vector3(0.0, 0.6, RELIQUARY_Z), Vector3(2.6, 1.2, 2.6),
			VaultBuild.STONE_TRIM)
	var relic: MeshInstance3D = VaultBuild.rune(self,
			Vector3(0.0, 2.1, RELIQUARY_Z), Vector3(0.9, 1.3, 0.9),
			VaultBuild.LIGHT_POSITIVE, 3.4)
	VaultBuild.set_rune_pulse(relic, 0.35, 1.3)
	VaultBuild.lamp(self, Vector3(0.0, 3.0, RELIQUARY_Z), VaultBuild.LIGHT_POSITIVE,
			2.8, 14.0)
	VaultBuild.plaque(self, Vector3(0.0, 4.0, RELIQUARY_Z + RELIQUARY_INNER.z * 0.5 - 0.15),
			"It only ever answered one question.\nIt answered honestly every time.",
			9.0, 38, PI)


## Floor conduits: fount to chambers, chambers to the junction, junction into
## the arena. They carry the travelling-band effect only while live, so the
## floor visibly shows where signal is and is not going.
func _build_conduits() -> void:
	for i in _founts.size():
		_fount_conduits.append(_floor_strip(
				Vector3(_founts[i].position.x, 0.03, HALL_Z + 4.5), 9.0, 0.34))
	for i in _chambers.size():
		_chamber_conduits.append(_floor_strip(
				Vector3((float(i) - 1.0) * CHAMBER_PITCH, 0.03, JUNCTION_Z - 5.4),
				5.0, 0.34))
	_arena_conduit = _floor_strip(Vector3(0.0, 0.03, JUNCTION_Z + 9.0), 14.0, 0.5)


## One conduit inlay, `length` meters long, running north-south.
##
## The rune shader's travelling band moves along the mesh's LOCAL Y, so the
## strip is built standing on end — length on Y — and then laid flat by a
## quarter turn about X. Building it lying down would squeeze the whole band
## into the strip's 6 cm thickness and show nothing.
func _floor_strip(center: Vector3, length: float, width: float) -> MeshInstance3D:
	var strip: MeshInstance3D = VaultBuild.rune(self, center,
			Vector3(width, length, 0.06), VaultBuild.LIGHT_IDLE, 1.2)
	strip.rotation.x = deg_to_rad(90.0)
	return strip


## Bit names the vault the first time Kern comes near. Owned here rather than
## added to MeadowLandmarks so this milestone touches no file another session
## is working in — BitLandmark registers itself through a group, which is
## exactly what makes that possible.
func _build_landmark() -> void:
	var lm: BitLandmark = BitLandmark.new()
	lm.name = "Landmark_perceptron_vault"
	lm.configure("perceptron_vault", "the Perceptron Vault", 46.0, [
		"The Perceptron Vault. Every door in there is a sum, Kern — feed it "
		+ "enough and it opens, feed it wrong and it just sits there. Rather "
		+ "like you before breakfast.",
		"That's the Perceptron Vault. Whatever's still awake inside has been "
		+ "counting since long before Bootstrap had a mayor. Do try not to "
		+ "let it count YOU.",
	], false)
	lm.position = Vector3(0.0, 3.0, -HALL_INNER.z * 0.5 + HALL_Z - 14.0)
	add_child(lm)


## The vault's mark: two nodes, then three, then one, fully joined. Carved on
## the facade and again on the gate; also the figure on the game's icon.
func _build_sigil(center: Vector3, span: float, color: Color) -> void:
	var rows: Array[int] = [2, 3, 1]
	var points: Array[Array] = []
	for r: int in rows.size():
		var count: int = rows[r]
		var row: Array[Vector3] = []
		for i: int in count:
			row.append(center + Vector3(
					(float(r) - 1.0) * span * 0.44,
					(float(i) - float(count - 1) * 0.5) * span * 0.34,
					0.0))
		points.append(row)
	for r: int in rows.size() - 1:
		for a: Vector3 in points[r]:
			for b: Vector3 in points[r + 1]:
				var delta: Vector3 = b - a
				var edge: MeshInstance3D = VaultBuild.rune(self, (a + b) * 0.5,
						Vector3(delta.length(), 0.07, 0.06), color, 1.2)
				edge.rotation.z = atan2(delta.y, delta.x)
	for row: Array in points:
		for p: Vector3 in row:
			var dot: MeshInstance3D = VaultBuild.rune(self, p as Vector3,
					Vector3(0.44, 0.44, 0.08), color, 1.8)
			VaultBuild.set_rune_pulse(dot, 0.3, 1.2)


# --- The network, solved -----------------------------------------------------

## Re-run the whole 2-3-1 network from the current fount bits and stone
## values, and push the result into every surface that shows it.
##
## Deliberately total rather than incremental: any change anywhere re-solves
## everything, so no two displays can ever drift out of agreement. The whole
## computation is a handful of integer multiplies — running it on every sword
## strike costs nothing.
func solve() -> void:
	var a: int = _founts[0].value if _founts.size() > 0 else 0
	var b: int = _founts[1].value if _founts.size() > 1 else 0

	for c: NeuronChamber in _chambers:
		c.recompute(a, b)

	# The output cell: each firing chamber contributes its weight, a dark one
	# contributes nothing — the same step function the chambers apply.
	_output_sum = 0
	for i in _chambers.size():
		if _chambers[i].firing:
			_output_sum += _output_stones[i].value()
	var firing: bool = _output_sum >= OUTPUT_THRESHOLD
	_target_output_fill = clampf(
			float(absi(_output_sum)) * OUTPUT_METERS_PER_UNIT / OUTPUT_COLUMN_HEIGHT,
			0.0, 1.0)
	VaultBuild.set_rune_color(_output_column,
			VaultBuild.LIGHT_POSITIVE if _output_sum >= 0 else VaultBuild.LIGHT_NEGATIVE,
			2.8)

	if firing != _output_firing:
		_output_firing = firing
		for seg: MeshInstance3D in _output_beam:
			VaultBuild.set_rune_pulse(seg, 0.12 if firing else 0.22, 1.1)
		if is_inside_tree():
			DamageShards.burst(get_tree().current_scene,
					global_position + Vector3(0.0, 2.6, JUNCTION_Z + 3.4),
					VaultBuild.LIGHT_POSITIVE if firing else VaultBuild.LIGHT_IDLE,
					18 if firing else 8, 4.0, 2.4, 1.0)
			EventBus.combat_shake.emit(0.12 if firing else 0.05)

	# The Gatekeeper reads the network's state every solve, so re-tuning a
	# stone mid-fight takes effect immediately — walking back out to fix the
	# puzzle is a legitimate tactic, not a soft-lock.
	if _gatekeeper != null and is_instance_valid(_gatekeeper):
		_gatekeeper.network_feeding = firing

	_relight_conduits(a, b, firing)


## Repaint the floor conduits to match the current signal. A conduit only
## flows where signal is genuinely travelling, so the floor is a readable map
## of the network's live state.
func _relight_conduits(a: int, b: int, output_firing: bool) -> void:
	var bits: Array[int] = [a, b]
	for i in _fount_conduits.size():
		var live: bool = bits[i] == 1
		VaultBuild.set_rune_color(_fount_conduits[i],
				VaultBuild.LIGHT_POSITIVE if live else VaultBuild.LIGHT_IDLE,
				2.4 if live else 0.5)
		VaultBuild.set_rune_flow(_fount_conduits[i], 1.0 if live else 0.0, 1.4, 0.5)
	for i in _chamber_conduits.size():
		var live: bool = _chambers[i].firing
		VaultBuild.set_rune_color(_chamber_conduits[i],
				VaultBuild.LIGHT_POSITIVE if live else VaultBuild.LIGHT_IDLE,
				2.4 if live else 0.5)
		VaultBuild.set_rune_flow(_chamber_conduits[i], 1.0 if live else 0.0, 1.4, 0.5)
	VaultBuild.set_rune_color(_arena_conduit,
			VaultBuild.LIGHT_POSITIVE if output_firing else VaultBuild.LIGHT_IDLE,
			3.0 if output_firing else 0.5)
	VaultBuild.set_rune_flow(_arena_conduit, 1.2 if output_firing else 0.0, 1.8, 0.4)


## Ease the junction column toward its target, matching the chambers' feel.
func _process(delta: float) -> void:
	if absf(_shown_output_fill - _target_output_fill) < 0.001:
		return
	_shown_output_fill = lerpf(_shown_output_fill, _target_output_fill,
			1.0 - exp(-NeuronChamber.COLUMN_EASE * delta))
	VaultBuild.set_rune_fill(_output_column, _shown_output_fill)


func _on_fount_toggled(_value: int) -> void:
	solve()


func _on_output_stone_changed(_value: int) -> void:
	solve()


## Kern stepped into the arena. Wake the Gatekeeper once, already fed by
## whatever the network is currently doing.
func _on_arena_entered(body: Node3D) -> void:
	if _cleared or _gatekeeper != null:
		return
	if not body.is_in_group(&"player"):
		return
	_gatekeeper = VaultGatekeeper.build(self, Vector3(0.0, 0.0, ARENA_Z + 4.0))
	_gatekeeper.network_feeding = _output_firing
	_gatekeeper.overloaded.connect(_on_gatekeeper_overloaded)
	print("PerceptronVault: the Gatekeeper wakes (network feeding: %s)." % _output_firing)


## The output cell fired. Open the gate and pay out — flag, Tokens, and the
## reliquary's stone. `add_tokens` and `add_item` emit their own EventBus
## signals, so the HUD and any quest listener hear about it without the vault
## knowing they exist.
func _on_gatekeeper_overloaded() -> void:
	if _cleared:
		return
	_cleared = true
	GameState.set_flag(CLEARED_FLAG)
	GameState.add_tokens(REWARD_TOKENS)
	GameState.add_item(REWARD_ITEM, 1)
	_gate.open()
	print("PerceptronVault: cleared — gate opening, %d Tokens and %s awarded."
			% [REWARD_TOKENS, REWARD_ITEM])

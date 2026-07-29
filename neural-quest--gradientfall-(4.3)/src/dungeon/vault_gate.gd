class_name VaultGate
extends Node3D
## The Perceptron Vault's output gate — two stone leaves that part when the
## last cell of the network fires.
##
## It is the only thing in the dungeon that is genuinely locked, and it is
## locked on the boss rather than on the puzzle (GDD §3: no hard gates except
## the Corpus Citadel; danger and cleverness are the gates). Beyond it sits
## the reliquary the vault was built to hold.
##
## Where it sits: built and owned by PerceptronVault, which calls `open()`
## when VaultGatekeeper reports it overloaded, or `open_instantly()` when a
## returning player already carries the cleared flag.
##
## The leaves carry their own collision (VaultBuild.solid parents the
## StaticBody3D to the mesh), so sliding the MeshInstance3D moves the wall
## Kern is standing against — no separate physics bookkeeping.

## Emitted once the leaves have finished parting.
signal opened()

## Seconds the leaves take to grind apart. Slow on purpose: this is the
## dungeon's payoff beat, not a door.
const OPEN_TIME: float = 2.6
## How far each leaf travels sideways, in meters. A leaf starts centered on
## its own half of the opening, so it must travel more than a full half-width
## to clear the doorway entirely — at exactly half it would still overhang.
## The leaves slide into the wall's jambs, pocket-door style.
const LEAF_TRAVEL: float = 4.2

var is_open: bool = false

var _leaves: Array[MeshInstance3D] = []
var _leaf_home: Array[Vector3] = []
var _runes: Array[MeshInstance3D] = []
var _lamp: OmniLight3D


## Build a two-leaf gate filling an opening `width` × `height` meters,
## centered on `center` in the parent's space, in a wall of `thickness`.
static func build(host: Node3D, center: Vector3, width: float, height: float,
		thickness: float) -> VaultGate:
	var g: VaultGate = VaultGate.new()
	g.position = center
	host.add_child(g)
	g._build(width, height, thickness)
	return g


func _ready() -> void:
	name = "OutputGate"


func _build(width: float, height: float, thickness: float) -> void:
	var half: float = width * 0.5
	for side: int in [-1, 1]:
		var leaf: MeshInstance3D = VaultBuild.solid(self,
				Vector3(float(side) * half * 0.5, height * 0.5, 0.0),
				Vector3(half, height, thickness), VaultBuild.STONE_TRIM)
		_leaves.append(leaf)
		_leaf_home.append(leaf.position)
		# A seam of light down each leaf's inner edge — dark while sealed, so
		# the gate reads as inert stone until the moment it matters. Set on
		# the NORTH face (-Z): that is the arena side, the only side a player
		# sees before the gate opens.
		var seam: MeshInstance3D = VaultBuild.rune(self,
				Vector3(float(side) * 0.09, height * 0.5, -thickness * 0.55),
				Vector3(0.1, height * 0.86, 0.05), VaultBuild.LIGHT_IDLE, 0.8)
		_runes.append(seam)

	# The 2-3-1 sigil above the gate: the vault's own mark, and the same
	# figure carved on the facade outside — two founts, three chambers, one
	# way out. It is also the shape on the game's icon. Arena side again, and
	# above the opening rather than on it, so the leaves never slide over it.
	_build_sigil(Vector3(0.0, height + 1.6, -thickness * 0.6), 3.0)

	_lamp = VaultBuild.lamp(self, Vector3(0.0, height * 0.6, -thickness * 1.2),
			VaultBuild.LIGHT_IDLE, 0.6, 14.0)


## The 2-3-1 figure: two nodes, then three, then one, with every node of each
## row joined to every node of the next. Drawn with thin boxes rather than
## lines so it catches the vault's own light. `span` is its full width.
func _build_sigil(center: Vector3, span: float) -> void:
	var rows: Array[int] = [2, 3, 1]
	var row_gap: float = span * 0.42
	var node_r: float = 0.19
	var points: Array[Array] = []
	for r: int in rows.size():
		var count: int = rows[r]
		var row: Array[Vector3] = []
		for i: int in count:
			# Center each row on x = 0 regardless of how many nodes it holds.
			var y: float = (float(i) - float(count - 1) * 0.5) * (span / 3.2)
			var x: float = (float(r) - 1.0) * row_gap
			row.append(center + Vector3(x, y, 0.0))
		points.append(row)

	# Edges first, so the node dots sit on top of them.
	for r: int in rows.size() - 1:
		for a: Vector3 in points[r]:
			for b: Vector3 in points[r + 1]:
				var mid: Vector3 = (a + b) * 0.5
				var delta: Vector3 = b - a
				var edge: MeshInstance3D = VaultBuild.rune(self, mid,
						Vector3(delta.length(), 0.045, 0.04),
						VaultBuild.LIGHT_IDLE, 1.0)
				# Rotate about Z so the bar's long X axis lies along the edge.
				edge.rotation.z = atan2(delta.y, delta.x)
				_runes.append(edge)
	for row: Array in points:
		for p: Vector3 in row:
			_runes.append(VaultBuild.rune(self, p as Vector3,
					Vector3(node_r * 2.0, node_r * 2.0, 0.05),
					VaultBuild.LIGHT_IDLE, 1.4))


## Part the leaves over OPEN_TIME, lighting the sigil and seams as they go.
## Safe to call twice — the second call is a no-op.
func open() -> void:
	if is_open:
		return
	is_open = true
	_light(VaultBuild.LIGHT_OPEN)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	for i in _leaves.size():
		var away: float = -LEAF_TRAVEL if i == 0 else LEAF_TRAVEL
		tw.tween_property(_leaves[i], "position",
				_leaf_home[i] + Vector3(away, 0.0, 0.0), OPEN_TIME)
	tw.chain().tween_callback(func() -> void: opened.emit())


## Put the gate straight into its open state with no animation — used when a
## returning player already cleared the vault, so the world matches the save
## the instant it loads.
func open_instantly() -> void:
	if is_open:
		return
	is_open = true
	_light(VaultBuild.LIGHT_OPEN)
	for i in _leaves.size():
		var away: float = -LEAF_TRAVEL if i == 0 else LEAF_TRAVEL
		_leaves[i].position = _leaf_home[i] + Vector3(away, 0.0, 0.0)
	opened.emit()


## Bring every rune on the gate up to `color` — the sigil, the seams, and the
## lamp that washes the wall around them.
func _light(color: Color) -> void:
	for r: MeshInstance3D in _runes:
		VaultBuild.set_rune_color(r, color, 3.2)
		VaultBuild.set_rune_pulse(r, 0.20, 1.4)
	if _lamp != null:
		_lamp.light_color = color
		_lamp.light_energy = 3.0

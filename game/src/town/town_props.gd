class_name TownProps
extends RefCounted
## The small stuff that makes Bootstrap look lived-in: market stalls, the
## notice board, carts and barrels, fences, lamp posts, the east gate, the
## fingerpost at the crossroads, Tansy's ribboned hives, Jory's irrigation
## channel, and Cedric's sheep.
##
## All statics returning ready-to-place nodes — BootstrapTown owns the map and
## drops these onto terrain heights. Props that a player could walk through if
## they were decoration only (carts, gate pillars, the notice board) come back
## as StaticBody3D with collision; pure dressing comes back as Node3D.

const WOOD: Color = Color(0.46, 0.33, 0.2)
const DARK_WOOD: Color = Color(0.32, 0.23, 0.14)
const IRON: Color = Color(0.24, 0.25, 0.27)
const CANVAS: Color = Color(0.9, 0.87, 0.78)


## A trader's stall: four posts, a striped awning, a counter, and goods.
## `goods` is "honey" (Tansy Hivewise) or "produce" (Orrin Bushel).
static func market_stall(stripe: Color, goods: String) -> StaticBody3D:
	var stall: StaticBody3D = StaticBody3D.new()
	stall.name = "Stall_" + goods
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			TownKit.plank(stall, "Post%d_%d" % [sx, sz], Vector3(0.12, 2.3, 0.12),
				Vector3(1.4 * sx, 1.15, 0.9 * sz), DARK_WOOD)
	# Awning: alternating canvas stripes, tilted forward over the counter.
	var awning: Node3D = Node3D.new()
	awning.name = "Awning"
	awning.position = Vector3(0.0, 2.45, -0.1)
	awning.rotation.x = -0.22
	stall.add_child(awning)
	for i in 7:
		var col: Color = CANVAS if i % 2 == 0 else stripe
		TownKit.plank(awning, "Stripe%d" % i, Vector3(0.44, 0.08, 2.6),
			Vector3(-1.32 + float(i) * 0.44, 0.0, 0.0), col)
	TownKit.plank(stall, "Counter", Vector3(3.0, 0.16, 1.0), Vector3(0.0, 1.0, -0.7), WOOD)
	TownKit.plank(stall, "CounterSkirt", Vector3(3.0, 0.9, 0.1), Vector3(0.0, 0.5, -1.15),
		WOOD.darkened(0.15))
	TownKit.collide_box(stall, Vector3(3.0, 1.1, 1.1), Vector3(0.0, 0.55, -0.7))

	var rng: RandomNumberGenerator = TownKit.rng_for("stall_" + goods)
	if goods == "honey":
		# Honey pots, ranked along the counter, and a straw skep behind.
		for i in 6:
			var pot: MeshInstance3D = TownKit.part(stall, "Pot%d" % i,
				TownKit.cyl(0.09, 0.12, 0.24, 8),
				Vector3(-1.2 + float(i) * 0.48, 1.2, -0.75),
				TownKit.toon(Color(0.86, 0.6, 0.18).lightened(rng.randf_range(0.0, 0.12))))
			TownKit.part(pot, "Lid", TownKit.cyl(0.1, 0.1, 0.05, 8), Vector3(0.0, 0.14, 0.0),
				TownKit.toon(Color(0.76, 0.72, 0.6)))
		stall.add_child(skep(Vector3(-1.0, 0.0, 0.7)))
	else:
		# Orrin's brass scale and his prize turnip, occupying one pan like royalty.
		TownKit.plank(stall, "ScalePost", Vector3(0.06, 0.5, 0.06), Vector3(1.1, 1.33, -0.7), IRON)
		TownKit.plank(stall, "ScaleBeam", Vector3(0.7, 0.05, 0.05), Vector3(1.1, 1.58, -0.7),
			Color(0.78, 0.66, 0.3))
		for sx: int in [-1, 1]:
			TownKit.part(stall, "Pan%d" % sx, TownKit.cyl(0.16, 0.13, 0.05, 10),
				Vector3(1.1 + 0.3 * sx, 1.44, -0.7), TownKit.toon(Color(0.78, 0.66, 0.3)))
		var turnip: MeshInstance3D = TownKit.part(stall, "QueenRootilda",
			TownKit.ball(0.13, 9, 6), Vector3(0.8, 1.55, -0.7),
			TownKit.toon(Color(0.9, 0.88, 0.86)))
		TownKit.part(turnip, "Top", TownKit.cyl(0.0, 0.06, 0.18, 6), Vector3(0.0, 0.16, 0.0),
			TownKit.toon(Color(0.44, 0.62, 0.25)))
		for i in 8:
			TownKit.part(stall, "Produce%d" % i, TownKit.ball(rng.randf_range(0.07, 0.11), 8, 5),
				Vector3(-1.3 + float(i) * 0.3, 1.16, -0.75 + rng.randf_range(-0.1, 0.1)),
				TownKit.toon([Color(0.82, 0.35, 0.24), Color(0.9, 0.66, 0.24),
					Color(0.45, 0.6, 0.25)][i % 3]))
		stall.add_child(crate(Vector3(-1.1, 0.0, 0.7)))
	return stall


## A straw bee skep. Tansy's bees queue along three colored ribbons — a system
## she admits they invented themselves.
static func skep(local: Vector3) -> Node3D:
	var hive: Node3D = Node3D.new()
	hive.name = "Skep"
	hive.position = local
	var straw: Color = Color(0.82, 0.68, 0.34)
	for i in 4:
		var r: float = 0.42 - float(i) * 0.09
		TownKit.part(hive, "Coil%d" % i, TownKit.cyl(r * 0.86, r, 0.16, 10),
			Vector3(0.0, 0.08 + float(i) * 0.16, 0.0), TownKit.toon(straw.darkened(float(i) * 0.03)))
	TownKit.part(hive, "Cap", TownKit.ball(0.14, 8, 5), Vector3(0.0, 0.72, 0.0),
		TownKit.toon(straw.darkened(0.12)))
	var ribbons: Array[Color] = [
		Color(0.85, 0.3, 0.35), Color(0.35, 0.55, 0.85), Color(0.95, 0.82, 0.3),
	]
	for i in ribbons.size():
		var ribbon: MeshInstance3D = TownKit.plank(hive, "Ribbon%d" % i,
			Vector3(0.04, 0.02, 1.6), Vector3(0.0, 0.5 + float(i) * 0.06, -0.8),
			ribbons[i])
		ribbon.rotation.y = -0.4 + float(i) * 0.4
	return hive


static func notice_board() -> StaticBody3D:
	var board: StaticBody3D = StaticBody3D.new()
	board.name = "NoticeBoard"
	for sx: int in [-1, 1]:
		TownKit.plank(board, "Post%d" % sx, Vector3(0.14, 2.2, 0.14), Vector3(0.85 * sx, 1.1, 0.0),
			DARK_WOOD)
	TownKit.plank(board, "Board", Vector3(2.0, 1.3, 0.1), Vector3(0.0, 1.55, 0.0), WOOD)
	TownKit.part(board, "Roof", TownKit.prism(Vector3(2.3, 0.4, 0.6)), Vector3(0.0, 2.4, 0.0),
		TownKit.toon(Color(0.5, 0.36, 0.22)), Vector3(0.0, PI * 0.5, 0.0))
	var rng: RandomNumberGenerator = TownKit.rng_for("notices")
	for i in 5:
		var note: MeshInstance3D = TownKit.plank(board, "Notice%d" % i,
			Vector3(rng.randf_range(0.3, 0.5), rng.randf_range(0.32, 0.46), 0.02),
			Vector3(rng.randf_range(-0.7, 0.7), 1.3 + rng.randf_range(0.0, 0.5), -0.06),
			Color(0.93, 0.9, 0.8))
		note.rotation.z = rng.randf_range(-0.09, 0.09)
	TownKit.collide_box(board, Vector3(2.0, 2.2, 0.4), Vector3(0.0, 1.1, 0.0))
	return board


## The crossroads fingerpost — the town's "you are here" and a quiet map of the
## region's canon sites.
static func fingerpost(directions: Array[Dictionary]) -> StaticBody3D:
	var post: StaticBody3D = StaticBody3D.new()
	post.name = "Fingerpost"
	TownKit.part(post, "Post", TownKit.cyl(0.1, 0.13, 3.2, 8), Vector3(0.0, 1.6, 0.0),
		TownKit.toon(DARK_WOOD))
	var i: int = 0
	for dir: Dictionary in directions:
		var arm: Node3D = Node3D.new()
		arm.name = "Arm%d" % i
		arm.position = Vector3(0.0, 2.9 - float(i) * 0.42, 0.0)
		arm.rotation.y = float(dir.get("yaw", 0.0))
		post.add_child(arm)
		var board: MeshInstance3D = TownKit.plank(arm, "Board", Vector3(1.5, 0.3, 0.06),
			Vector3(0.75, 0.0, 0.0), Color(0.74, 0.64, 0.44))
		for sz: int in [-1, 1]:
			var label: Label3D = Label3D.new()
			label.name = "Text%d" % sz
			label.text = str(dir.get("text", ""))
			label.font_size = 40
			label.pixel_size = 0.0042
			label.modulate = Color(0.25, 0.17, 0.1)
			label.outline_size = 0
			label.position = Vector3(0.0, 0.0, 0.05 * sz)
			label.rotation.y = 0.0 if sz < 0 else PI
			# Back-to-back pair: each face draws only its own side, or the far
			# label bleeds through and the sign reads mirrored.
			label.double_sided = false
			board.add_child(label)
		i += 1
	TownKit.collide_box(post, Vector3(0.3, 3.2, 0.3), Vector3(0.0, 1.6, 0.0))
	return post


static func cart() -> StaticBody3D:
	var cart_node: StaticBody3D = StaticBody3D.new()
	cart_node.name = "Cart"
	TownKit.plank(cart_node, "Bed", Vector3(1.6, 0.16, 2.6), Vector3(0.0, 0.75, 0.0), WOOD)
	for sx: int in [-1, 1]:
		TownKit.plank(cart_node, "Side%d" % sx, Vector3(0.1, 0.5, 2.6),
			Vector3(0.8 * sx, 1.0, 0.0), WOOD.darkened(0.1))
	TownKit.plank(cart_node, "Tail", Vector3(1.6, 0.5, 0.1), Vector3(0.0, 1.0, 1.3),
		WOOD.darkened(0.1))
	for sx: int in [-1, 1]:
		var wheel: MeshInstance3D = TownKit.part(cart_node, "Wheel%d" % sx,
			TownKit.cyl(0.62, 0.62, 0.14, 12), Vector3(0.85 * sx, 0.66, 0.4),
			TownKit.toon(DARK_WOOD), Vector3(0.0, 0.0, PI * 0.5))
		for i in 6:
			var spoke: MeshInstance3D = TownKit.plank(wheel, "Spoke%d" % i,
				Vector3(0.06, 0.16, 1.15), Vector3.ZERO, WOOD)
			spoke.rotation.y = TAU * float(i) / 6.0
	TownKit.plank(cart_node, "Shaft", Vector3(0.12, 0.12, 1.6), Vector3(0.0, 0.85, -2.0), WOOD)
	TownKit.collide_box(cart_node, Vector3(1.8, 1.3, 2.8), Vector3(0.0, 0.65, 0.0))
	return cart_node


static func barrel(local: Vector3 = Vector3.ZERO) -> Node3D:
	var b: Node3D = Node3D.new()
	b.name = "Barrel"
	b.position = local
	TownKit.part(b, "Body", TownKit.cyl(0.32, 0.32, 0.9, 12), Vector3(0.0, 0.45, 0.0),
		TownKit.toon(WOOD))
	TownKit.part(b, "Belly", TownKit.cyl(0.36, 0.36, 0.5, 12), Vector3(0.0, 0.45, 0.0),
		TownKit.toon(WOOD.lightened(0.05)))
	for y: float in [0.22, 0.68]:
		TownKit.part(b, "Hoop%.0f" % (y * 100.0), TownKit.cyl(0.35, 0.35, 0.07, 12),
			Vector3(0.0, y, 0.0), TownKit.toon(IRON))
	return b


static func crate(local: Vector3 = Vector3.ZERO) -> Node3D:
	var c: Node3D = Node3D.new()
	c.name = "Crate"
	c.position = local
	TownKit.plank(c, "Body", Vector3(0.7, 0.62, 0.7), Vector3(0.0, 0.31, 0.0), WOOD.lightened(0.06))
	for sz: int in [-1, 1]:
		TownKit.plank(c, "Batten%d" % sz, Vector3(0.74, 0.09, 0.06),
			Vector3(0.0, 0.45, 0.36 * sz), DARK_WOOD)
	return c


static func hay_bale(local: Vector3 = Vector3.ZERO) -> Node3D:
	var h: Node3D = Node3D.new()
	h.name = "HayBale"
	h.position = local
	TownKit.part(h, "Bale", TownKit.cyl(0.5, 0.5, 1.0, 12), Vector3(0.0, 0.5, 0.0),
		TownKit.toon(Color(0.83, 0.71, 0.36)), Vector3(PI * 0.5, 0.0, 0.0))
	for sx: int in [-1, 1]:
		TownKit.plank(h, "Twine%d" % sx, Vector3(0.03, 1.02, 1.02), Vector3(0.22 * sx, 0.5, 0.0),
			Color(0.6, 0.5, 0.28))
	return h


static func water_trough() -> StaticBody3D:
	var t: StaticBody3D = StaticBody3D.new()
	t.name = "Trough"
	TownKit.plank(t, "Body", Vector3(2.0, 0.6, 0.9), Vector3(0.0, 0.3, 0.0), DARK_WOOD)
	var water: MeshInstance3D = TownKit.part(t, "Water", TownKit.box(Vector3(1.8, 0.05, 0.75)),
		Vector3(0.0, 0.52, 0.0), TownKit.toon(Color(0.32, 0.5, 0.62)))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	TownKit.collide_box(t, Vector3(2.0, 0.6, 0.9), Vector3(0.0, 0.3, 0.0))
	return t


static func anvil() -> StaticBody3D:
	var a: StaticBody3D = StaticBody3D.new()
	a.name = "Anvil"
	TownKit.part(a, "Stump", TownKit.cyl(0.34, 0.38, 0.6, 10), Vector3(0.0, 0.3, 0.0),
		TownKit.toon(DARK_WOOD))
	TownKit.plank(a, "Waist", Vector3(0.28, 0.22, 0.36), Vector3(0.0, 0.72, 0.0), IRON)
	TownKit.plank(a, "Face", Vector3(0.9, 0.2, 0.42), Vector3(0.0, 0.92, 0.0), IRON.lightened(0.1))
	TownKit.part(a, "Horn", TownKit.cyl(0.0, 0.16, 0.4, 8), Vector3(-0.6, 0.92, 0.0),
		TownKit.toon(IRON.lightened(0.1)), Vector3(0.0, 0.0, PI * 0.5))
	TownKit.collide_box(a, Vector3(0.9, 1.0, 0.5), Vector3(0.0, 0.5, 0.0))
	return a


## A post-and-rail run that follows the ground between two points.
static func fence_run(from: Vector2, to: Vector2, terrain: Node, spacing: float = 2.2) -> Node3D:
	var run: Node3D = Node3D.new()
	run.name = "Fence"
	var span: float = from.distance_to(to)
	var count: int = maxi(2, int(round(span / spacing)) + 1)
	var prev: Vector3 = Vector3.ZERO
	for i in count:
		var t: float = float(i) / float(count - 1)
		var p: Vector2 = from.lerp(to, t)
		var y: float = _ground(terrain, p)
		var post_pos: Vector3 = Vector3(p.x, y + 0.6, p.y)
		TownKit.plank(run, "Post%d" % i, Vector3(0.12, 1.2, 0.12), post_pos, DARK_WOOD)
		if i > 0:
			for rail_y: float in [0.35, 0.75]:
				var a: Vector3 = prev + Vector3(0.0, rail_y - 0.6, 0.0)
				var b: Vector3 = post_pos + Vector3(0.0, rail_y - 0.6, 0.0)
				var mid: Vector3 = (a + b) * 0.5
				var rail: MeshInstance3D = TownKit.plank(run, "Rail%d_%.0f" % [i, rail_y * 100.0],
					Vector3(0.08, 0.1, a.distance_to(b)), mid, WOOD)
				rail.look_at_from_position(mid, b, Vector3.UP)
		prev = post_pos
	return run


## Flat stones with grass between them — Bootstrap's roads read as worn paths
## rather than painted stripes, and the meadow's grass field keeps growing
## right through the gaps. One MultiMesh for the whole run: a road across the
## town and out to the mill is hundreds of stones and one draw call.
static func path_stones(points: Array[Vector2], terrain: Node, key: String,
		width: float = 2.0) -> MultiMeshInstance3D:
	var rng: RandomNumberGenerator = TownKit.rng_for("path_" + key)
	var transforms: Array[Transform3D] = []
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var span: float = a.distance_to(b)
		var steps: int = maxi(1, int(span / 0.8))
		var side: Vector2 = (b - a).normalized().orthogonal()
		for s in steps:
			var base: Vector2 = a.lerp(b, float(s) / float(steps))
			for lane: int in [-1, 0, 1]:
				if rng.randf() < 0.24:
					continue
				var p: Vector2 = base + side * (float(lane) * width * 0.34
					+ rng.randf_range(-0.14, 0.14))
				var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				basis = basis.scaled(Vector3(rng.randf_range(0.72, 1.1), 1.0,
					rng.randf_range(0.72, 1.1)))
				transforms.append(Transform3D(basis,
					Vector3(p.x, _ground(terrain, p) + 0.035, p.y)))

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = TownKit.cyl(0.27, 0.24, 0.12, 6)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "Path_" + key
	node.multimesh = mm
	node.material_override = TownKit.toon(Color(0.57, 0.55, 0.5))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Fen Reedwhistle keeps a tiny empty chair beside him for the day's most
## persuasive fish, and insists it improves negotiations.
static func chair() -> Node3D:
	var c: Node3D = Node3D.new()
	c.name = "PersuasiveFishChair"
	TownKit.plank(c, "Seat", Vector3(0.42, 0.06, 0.42), Vector3(0.0, 0.38, 0.0), WOOD)
	TownKit.plank(c, "Back", Vector3(0.42, 0.44, 0.06), Vector3(0.0, 0.6, 0.18), WOOD)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			TownKit.plank(c, "Leg%d_%d" % [sx, sz], Vector3(0.05, 0.38, 0.05),
				Vector3(0.16 * sx, 0.19, 0.16 * sz), DARK_WOOD)
	return c


## Jory Slope's irrigation channel: a stone-lined ditch with a thin water
## ribbon, running downhill exactly the way he tests it — with a blue marble.
static func irrigation_channel(from: Vector2, to: Vector2, terrain: Node) -> Node3D:
	var ditch: Node3D = Node3D.new()
	ditch.name = "IrrigationChannel"
	var span: float = from.distance_to(to)
	var segments: int = maxi(2, int(span / 2.0))
	var side: Vector2 = (to - from).normalized().orthogonal()
	for i in segments:
		var t: float = float(i) / float(segments - 1)
		var p: Vector2 = from.lerp(to, t)
		var y: float = _ground(terrain, p)
		for sx: int in [-1, 1]:
			var edge: Vector2 = p + side * 0.62 * sx
			TownKit.part(ditch, "Kerb%d_%d" % [i, sx], TownKit.box(Vector3(0.5, 0.3, 2.1)),
				Vector3(edge.x, y + 0.05, edge.y),
				TownKit.toon(Color(0.55, 0.53, 0.48)),
				Vector3(0.0, atan2(side.x, side.y) + PI * 0.5, 0.0))
		var water: MeshInstance3D = TownKit.part(ditch, "Water%d" % i,
			TownKit.box(Vector3(0.9, 0.06, 2.1)), Vector3(p.x, y - 0.12, p.y),
			TownKit.toon(Color(0.35, 0.52, 0.6)),
			Vector3(0.0, atan2(side.x, side.y) + PI * 0.5, 0.0))
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ditch


## The eastern gate Rowan Threshold keeps: two stone pillars, a beam, a
## lantern, and short palisade wings that stop the town at a line.
static func gate_arch() -> StaticBody3D:
	var gate: StaticBody3D = StaticBody3D.new()
	gate.name = "EastGate"
	for sx: int in [-1, 1]:
		TownKit.plank(gate, "Pillar%d" % sx, Vector3(1.0, 4.0, 1.0), Vector3(3.2 * sx, 2.0, 0.0),
			Color(0.56, 0.55, 0.5))
		TownKit.plank(gate, "PillarCap%d" % sx, Vector3(1.25, 0.25, 1.25),
			Vector3(3.2 * sx, 4.15, 0.0), Color(0.5, 0.49, 0.45))
		TownKit.collide_box(gate, Vector3(1.0, 4.0, 1.0), Vector3(3.2 * sx, 2.0, 0.0))
	TownKit.plank(gate, "Beam", Vector3(7.6, 0.55, 0.7), Vector3(0.0, 4.5, 0.0), DARK_WOOD)
	TownKit.plank(gate, "BeamTrim", Vector3(7.0, 0.2, 0.85), Vector3(0.0, 4.15, 0.0), WOOD)
	for sx: int in [-1, 1]:
		var brace: MeshInstance3D = TownKit.plank(gate, "Brace%d" % sx, Vector3(1.4, 0.22, 0.4),
			Vector3(2.4 * sx, 4.0, 0.0), DARK_WOOD)
		brace.rotation.z = 0.6 * sx
	TownKit.lantern(gate, "GateLantern", Vector3(0.0, 4.0, 0.0), 12.0)
	# Rowan's chalk squares: one tally per patrol, painted on the near pillar.
	for i in 6:
		TownKit.plank(gate, "Chalk%d" % i, Vector3(0.16, 0.16, 0.02),
			Vector3(-3.2 + (float(i % 3) - 1.0) * 0.25, 1.6 - float(i / 3) * 0.25, -0.52),
			Color(0.92, 0.92, 0.88))
	return gate


static func lamp_post() -> StaticBody3D:
	var lamp: StaticBody3D = StaticBody3D.new()
	lamp.name = "LampPost"
	TownKit.part(lamp, "Post", TownKit.cyl(0.07, 0.1, 3.0, 8), Vector3(0.0, 1.5, 0.0),
		TownKit.toon(IRON))
	TownKit.plank(lamp, "Arm", Vector3(0.5, 0.06, 0.06), Vector3(0.2, 3.0, 0.0), IRON)
	TownKit.plank(lamp, "Housing", Vector3(0.3, 0.36, 0.3), Vector3(0.4, 2.8, 0.0), IRON)
	TownKit.part(lamp, "Cap", TownKit.cyl(0.0, 0.26, 0.18, 4), Vector3(0.4, 3.05, 0.0),
		TownKit.toon(IRON.darkened(0.2)), Vector3(0.0, PI * 0.25, 0.0))
	TownKit.lantern(lamp, "Flame", Vector3(0.4, 2.8, 0.0), 10.0)
	TownKit.collide_box(lamp, Vector3(0.25, 3.0, 0.25), Vector3(0.0, 1.5, 0.0))
	return lamp


## One of Cedric Cluster's sheep. He introduces every lamb as if presenting
## nobility, so they are at least modeled with dignity.
static func sheep(key: String) -> Node3D:
	var rng: RandomNumberGenerator = TownKit.rng_for("sheep_" + key)
	var s: Node3D = Node3D.new()
	s.name = "Sheep_" + key
	var wool: Color = Color(0.9, 0.89, 0.85).darkened(rng.randf_range(0.0, 0.1))
	var face: Color = Color(0.26, 0.23, 0.22)
	var body: MeshInstance3D = TownKit.part(s, "Body", TownKit.ball(0.42, 10, 7),
		Vector3(0.0, 0.62, 0.0), TownKit.toon(wool))
	body.scale = Vector3(1.0, 0.85, 1.45)
	for i in 5:
		TownKit.part(s, "Tuft%d" % i, TownKit.ball(rng.randf_range(0.16, 0.22), 8, 5),
			Vector3(rng.randf_range(-0.25, 0.25), 0.78 + rng.randf_range(-0.05, 0.08),
				rng.randf_range(-0.45, 0.45)), TownKit.toon(wool))
	var head: MeshInstance3D = TownKit.part(s, "Head", TownKit.ball(0.17, 9, 6),
		Vector3(0.0, 0.66, -0.62), TownKit.toon(face))
	head.scale = Vector3(0.9, 1.0, 1.2)
	for sx: int in [-1, 1]:
		TownKit.part(s, "Ear%d" % sx, TownKit.ball(0.08, 7, 4),
			Vector3(0.16 * sx, 0.74, -0.56), TownKit.toon(face))
		for sz: int in [-1, 1]:
			TownKit.part(s, "Leg%d_%d" % [sx, sz], TownKit.cyl(0.06, 0.05, 0.44, 6),
				Vector3(0.2 * sx, 0.22, 0.28 * sz), TownKit.toon(face))
	s.rotation.y = rng.randf_range(0.0, TAU)
	return s


## A vegetable patch — rows of leafy tufts in turned earth.
static func garden_patch(size: Vector2, key: String) -> Node3D:
	var patch: Node3D = Node3D.new()
	patch.name = "Garden_" + key
	var rng: RandomNumberGenerator = TownKit.rng_for("garden_" + key)
	var soil: MeshInstance3D = TownKit.plank(patch, "Soil", Vector3(size.x, 0.12, size.y),
		Vector3(0.0, 0.06, 0.0), Color(0.33, 0.25, 0.18))
	soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rows: int = maxi(2, int(size.y / 0.8))
	var per_row: int = maxi(2, int(size.x / 0.6))
	for r in rows:
		for c in per_row:
			var p: Vector3 = Vector3(
				-size.x * 0.5 + 0.4 + float(c) * (size.x - 0.8) / maxf(1.0, float(per_row - 1)),
				0.2,
				-size.y * 0.5 + 0.4 + float(r) * (size.y - 0.8) / maxf(1.0, float(rows - 1)))
			var leaf: MeshInstance3D = TownKit.part(patch, "Crop%d_%d" % [r, c],
				TownKit.ball(rng.randf_range(0.13, 0.2), 7, 4), p,
				TownKit.toon(Color(0.36, 0.55, 0.22).lightened(rng.randf_range(0.0, 0.15))))
			leaf.scale = Vector3(1.2, 0.7, 1.2)
	return patch


static func _ground(terrain: Node, p: Vector2) -> float:
	if terrain != null and terrain.has_method("get_height"):
		return terrain.get_height(p.x, p.y)
	return 0.0

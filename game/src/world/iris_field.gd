class_name IrisField
extends Node3D
## The meadow's irises, as collectible flora — Phase 1 milestone 13.
##
## Datasedge's iris flats have been scenery since milestone 3; `MeadowFlora`'s
## header has said since then that "the collectible system arrives with the
## compendium milestone". This is that system. The flats look exactly as they
## did — the scatter seed, cluster centers, counts, and family colors are all
## carried over unchanged — but every bloom now carries a real Iris specimen
## record, and walking over one collects it.
##
## **Collection is proximity, not a button.** Kern picks a bloom by walking
## through it, the way you pick things up in a field. That needs no new input
## action, nothing to aim at, and no per-bloom node: all 700 blooms live in a
## single MultiMesh, and this node keeps their positions and specimen records
## in parallel arrays. A picked bloom shrinks away over a beat rather than
## blinking out (GDD §10: nothing pops in or out without a transition).
##
## **What persists is the specimen, not the flower.** Cataloguing writes a
## GameState flag per SPECIMEN (150 of them), so the compendium is a set of
## booleans inside the already-serialized `flags` dictionary — no change to
## the save shape and no SAVE_VERSION bump. Individual blooms are not saved,
## so the flats regrow between sessions, which is what a meadow does. Picking
## an already-catalogued specimen still yields a petal; it just adds nothing
## new to the compendium.
##
## Where it sits: built as a child of MeadowFlora, which hands it the terrain
## and the same RNG seed. It emits EventBus.item_acquired indirectly through
## `GameState.add_item`, and nothing else. CompendiumUi reads the specimen
## table from here.
##
## Units: meters for the world, centimeters for the measurements on a bloom.

const IRIS_COUNT: int = 700
## Cluster centers of the iris flats, west of Bootstrap (GDD §7, WORLDBOOK).
## Unchanged from the original scatter so the flats sit exactly where players
## and screenshots have already seen them.
const CLUSTERS: Array[Vector2] = [
	Vector2(-95.0, 25.0), Vector2(-130.0, -15.0), Vector2(-75.0, 70.0),
	Vector2(-150.0, 55.0), Vector2(-110.0, 110.0),
]
## Standard deviation (m) of a bloom's distance from its cluster center.
const CLUSTER_SPREAD: float = 14.0
const EDGE_MARGIN: float = 12.0
## Y a culled bloom is parked at — the convention MeadowFlora uses for
## instances that landed somewhere unusable.
const PARKED_Y: float = -10000.0

## Horizontal reach (m) at which Kern picks a bloom, and the vertical slack
## that goes with it so a bloom on a slope below him still counts.
const PICK_RADIUS: float = 1.15
const PICK_HEIGHT: float = 2.2
## Seconds between proximity sweeps. At 700 blooms a sweep is trivial, but
## there is no reason to run it every frame — a walking player cannot cross
## the pick radius in a twelfth of a second.
const SWEEP_INTERVAL: float = 0.08
## Seconds a picked bloom takes to shrink away.
const VANISH_TIME: float = 0.28

## The item every bloom yields. Already approved content, so this needs no
## new entry and cannot collide with the items batch another session owns.
const PETAL_ITEM: String = "item_iris_petal"

## The 150 specimen records this meadow's blooms are drawn from. See
## IrisDataset.build_specimens() for the record shape.
var specimens: Array[Dictionary] = []

## Per-bloom parallel arrays, all IRIS_COUNT long and index-aligned with the
## MultiMesh's instances.
var _bloom_pos: PackedVector3Array = PackedVector3Array()
var _bloom_specimen: PackedInt32Array = PackedInt32Array()
var _bloom_scale: PackedFloat32Array = PackedFloat32Array()
var _bloom_yaw: PackedFloat32Array = PackedFloat32Array()
## True once a bloom has been picked (or was culled at build time for landing
## in water or off the map). Picked blooms are skipped by the sweep.
var _bloom_taken: PackedByteArray = PackedByteArray()

## Blooms mid-shrink: { index, elapsed }.
var _vanishing: Array[Dictionary] = []

var _terrain: MeadowTerrain
var _multimesh: MultiMesh
var _player: Node3D
var _sweep_left: float = 0.0


## Build the field against `terrain`, seeded so the flats are identical every
## boot. Called by MeadowFlora with its own scatter seed.
static func build(host: Node3D, terrain: MeadowTerrain, seed_value: int) -> IrisField:
	var f: IrisField = IrisField.new()
	f.name = "IrisField"
	f._terrain = terrain
	host.add_child(f)
	f._scatter(seed_value)
	return f


## Lay out every bloom and stamp a specimen on it.
func _scatter(seed_value: int) -> void:
	var start_ms: int = Time.get_ticks_msec()
	specimens = IrisDataset.build_specimens(seed_value)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = _build_iris_mesh()
	_multimesh.instance_count = IRIS_COUNT

	for i in IRIS_COUNT:
		var c: Vector2 = CLUSTERS[rng.randi() % CLUSTERS.size()]
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = absf(rng.randfn(0.0, CLUSTER_SPREAD))
		var x: float = c.x + cos(ang) * dist
		var z: float = c.y + sin(ang) * dist
		var h: float = _terrain.get_height(x, z)
		var usable: bool = _ground_ok(x, z, h)
		var yaw: float = rng.randf_range(0.0, TAU)
		var scale: float = rng.randf_range(0.8, 1.2)

		# Which of the 150 specimens this bloom is. Several blooms share a
		# specimen by design — the catalogue tracks findings, not flowers.
		var specimen: int = rng.randi() % specimens.size()

		_bloom_pos.append(Vector3(x, h, z))
		_bloom_specimen.append(specimen)
		_bloom_scale.append(scale)
		_bloom_yaw.append(yaw)
		# A bloom that landed in the pond or off the edge is marked taken so
		# the sweep never considers it; it is parked underground either way.
		_bloom_taken.append(0 if usable else 1)

		_write_instance(i, 1.0 if usable else 0.0)
		_multimesh.set_instance_color(i, _color_for(specimen))

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Irises"
	mmi.multimesh = _multimesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	var boundary: int = 0
	for s: Dictionary in specimens:
		if bool(s["boundary"]):
			boundary += 1
	print("IrisField: %d blooms over %d specimens (%d boundary blooms) in %d ms." % [
		IRIS_COUNT, specimens.size(), boundary, Time.get_ticks_msec() - start_ms,
	])


## Write one bloom's transform into the MultiMesh at `scale_mul` (0 hides it,
## 1 is full size). Parked blooms are pushed far underground so a zero-scale
## instance never leaves a speck at ground level.
func _write_instance(index: int, scale_mul: float) -> void:
	var pos: Vector3 = _bloom_pos[index]
	if scale_mul <= 0.0:
		pos.y = PARKED_Y
	var t: Transform3D = Transform3D(Basis.IDENTITY, pos)
	t = t.rotated_local(Vector3.UP, _bloom_yaw[index])
	var s: float = _bloom_scale[index] * scale_mul
	t = t.scaled_local(Vector3(s, s, s))
	_multimesh.set_instance_transform(index, t)


## A bloom's color: its family's, unless the specimen is ambiguous — boundary
## blooms wear their own near-white so a collector can spot one across a
## field, which is what makes them prizes rather than trivia.
func _color_for(specimen: int) -> Color:
	var record: Dictionary = specimens[specimen]
	if bool(record["boundary"]):
		return IrisDataset.BOUNDARY_COLOR
	return IrisDataset.FAMILY_COLORS[int(record["family"])]


## Same siting rule MeadowFlora applies to every scattered thing: inside the
## map's margin, and clear of the pond bed and waterline.
func _ground_ok(x: float, z: float, h: float) -> bool:
	if absf(x) > MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN:
		return false
	if absf(z) > MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN:
		return false
	if h < _terrain.water_level + 0.35:
		return false
	return true


func _process(delta: float) -> void:
	_advance_vanishing(delta)
	_sweep_left -= delta
	if _sweep_left > 0.0:
		return
	_sweep_left = SWEEP_INTERVAL
	_check_pickups()


## Shrink picked blooms out over VANISH_TIME, then park them.
func _advance_vanishing(delta: float) -> void:
	if _vanishing.is_empty():
		return
	var still_going: Array[Dictionary] = []
	for v: Dictionary in _vanishing:
		var elapsed: float = float(v["elapsed"]) + delta
		var index: int = int(v["index"])
		if elapsed >= VANISH_TIME:
			_write_instance(index, 0.0)
			continue
		# Ease out, so the bloom drops away quickly and then settles rather
		# than shrinking at a constant, mechanical rate.
		var t: float = elapsed / VANISH_TIME
		_write_instance(index, 1.0 - t * t)
		still_going.append({"index": index, "elapsed": elapsed})
	_vanishing = still_going


## Pick every uncollected bloom Kern is standing in.
##
## A flat scan of all 700 positions. That is a few thousand float operations
## twelve times a second on a machine speced for hundreds of thousands of
## instanced grass blades (GDD §10 hardware decree) — a spatial index here
## would be complexity bought with nothing.
func _check_pickups() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
		if _player == null:
			return
	var at: Vector3 = _player.global_position
	var radius_sq: float = PICK_RADIUS * PICK_RADIUS
	for i in _bloom_pos.size():
		if _bloom_taken[i] == 1:
			continue
		var p: Vector3 = _bloom_pos[i]
		if absf(p.y - at.y) > PICK_HEIGHT:
			continue
		var dx: float = p.x - at.x
		var dz: float = p.z - at.z
		if dx * dx + dz * dz <= radius_sq:
			_pick(i)


## Collect one bloom: yield a petal, catalogue the specimen if it is new, and
## start the bloom shrinking away.
func _pick(index: int) -> void:
	_bloom_taken[index] = 1
	_vanishing.append({"index": index, "elapsed": 0.0})

	var record: Dictionary = specimens[_bloom_specimen[index]]
	var specimen_index: int = int(record["index"])
	var was_new: bool = not IrisDataset.is_catalogued(specimen_index)
	if was_new:
		GameState.set_flag(IrisDataset.flag_for(specimen_index))
	GameState.add_item(PETAL_ITEM, 1)  # emits EventBus.item_acquired

	var at: Vector3 = _bloom_pos[index] + Vector3(0.0, 0.35, 0.0)
	var col: Color = _color_for(_bloom_specimen[index])
	# A new specimen bursts brighter and wider than a duplicate — the only
	# feedback that says "that one mattered" without opening a screen.
	DamageShards.burst(get_tree().current_scene, at, col,
			16 if was_new else 7, 3.0 if was_new else 2.0, 2.2, 0.5)
	if was_new:
		_announce(record, at)


## A short floating note over a newly catalogued bloom, naming what it was.
## Frees itself; nothing holds a reference.
func _announce(record: Dictionary, at: Vector3) -> void:
	var label: Label3D = Label3D.new()
	var family: String = IrisDataset.FAMILY_NAMES[int(record["family"])]
	label.text = ("a boundary bloom — %s" % family) if bool(record["boundary"]) \
			else family
	label.font_size = 34
	label.outline_size = 8
	label.pixel_size = 0.006
	label.modulate = IrisDataset.BOUNDARY_COLOR if bool(record["boundary"]) \
			else Color(0.97, 0.95, 0.88)
	label.outline_modulate = Color(0.08, 0.09, 0.07, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.no_depth_test = true
	add_child(label)
	label.global_position = at + Vector3(0.0, 0.5, 0.0)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position",
			label.global_position + Vector3(0.0, 0.9, 0.0), 1.6)
	tw.tween_property(label, "modulate:a", 0.0, 1.6).set_delay(0.7)
	tw.chain().tween_callback(label.queue_free)


## An iris: short stem quad + three diamond petals. Petal verts are COLOR
## white so the MultiMesh instance color tints petals; stem verts stay green.
## Moved here from MeadowFlora unchanged when the irises became collectible.
func _build_iris_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_col: Color = Color(0.3, 0.5, 0.24)
	var stem_h: float = 0.32
	# Stem: two crossed thin triangles.
	for k in 2:
		var b: Basis = Basis(Vector3.UP, PI * 0.5 * float(k))
		st.set_color(stem_col); st.set_normal(Vector3.UP)
		st.add_vertex(b * Vector3(-0.015, 0.0, 0.0))
		st.set_color(stem_col); st.set_normal(Vector3.UP)
		st.add_vertex(b * Vector3(0.015, 0.0, 0.0))
		st.set_color(stem_col); st.set_normal(Vector3.UP)
		st.add_vertex(b * Vector3(0.0, stem_h, 0.0))
	# Petals: three diamonds fanning from the stem tip. COLOR white = tinted.
	for k in 3:
		var b: Basis = Basis(Vector3.UP, TAU * float(k) / 3.0)
		var tip: Vector3 = Vector3(0.0, stem_h, 0.0)
		var out: Vector3 = b * Vector3(0.12, 0.06, 0.0)
		var side: Vector3 = b * Vector3(0.05, 0.0, 0.05)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip + out + side)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip + out * 1.6)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip + out * 1.6)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip + out - side)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st.commit()

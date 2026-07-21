class_name MeadowFlora
extends Node3D
## Datasedge Meadows vegetation.
##
## Everything scattered deterministically (fixed seed) on the terrain the
## sibling MeadowTerrain generated: a photoreal 2.5M-blade grass carpet in two
## camera-wrapped MultiMesh fields (grass_field.gdshader does the planting,
## clumping, wind, and trample), iris flats to the west (the region's canon
## flora — collectible system arrives with the compendium milestone; today
## they are scenery), daisies, pebbles, and tree copses with trunk collision.
## Zero textures — all variation is procedural.

const SCATTER_SEED: int = 20260717
# Two camera-wrapped carpets share grass_field.gdshader. The near field is a
# dense photoreal sward right around the camera (~415 blades/m², 5-segment
# cards); the far field carries the sweep to the horizon with fewer, wider,
# cheaper 3-segment blades — the Ghost-of-Tsushima distance trick. Budget is
# ~60M verts/frame: deliberately rich for high-end GPUs (GDD §10) while
# leaving frame-time headroom for the rest of the game.
const NEAR_COUNT: int = 1300000
const NEAR_TILE: float = 56.0
const NEAR_SEGMENTS: int = 5
const MID_COUNT: int = 750000
const MID_TILE: float = 104.0
const FAR_COUNT: int = 1200000
const FAR_TILE: float = 190.0
const FAR_SEGMENTS: int = 3
const BLADE_HALF_WIDTH: float = 0.011
# Each field is split into CHUNKS×CHUNKS MultiMeshes whose AABBs track their
# wrapped world rects every frame — so Godot frustum-culls the blades behind
# the camera (a single whole-map AABB defeats culling and doubles frame cost).
const FIELD_CHUNKS: int = 8
const IRIS_COUNT: int = 700
const DAISY_COUNT: int = 1200
const PEBBLE_COUNT: int = 750
const EDGE_MARGIN: float = 12.0

@onready var _terrain: MeadowTerrain = $"../Terrain"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# One entry per field chunk: {mmi, rect (tile-local), tile, cull_dist}.
var _field_chunks: Array[Dictionary] = []


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	_rng.seed = SCATTER_SEED
	# Dev A/B: `-- --no-grass` boots without the blade carpets so frame cost
	# can be attributed honestly (grass vs sky/GI/shadows).
	if not OS.get_cmdline_user_args().has("--no-grass"):
		_build_fine_field()
	_scatter_irises()
	_scatter_daisies()
	_scatter_pebbles()
	_plant_copses()
	print("MeadowFlora: %d near + %d mid + %d far blades, %d irises, %d daisies, %d pebbles in %d ms." % [
		NEAR_COUNT, MID_COUNT, FAR_COUNT,
		IRIS_COUNT, DAISY_COUNT, PEBBLE_COUNT,
		Time.get_ticks_msec() - start_ms,
	])


## The photoreal carpet: two camera-wrapped MultiMesh fields of unit-height
## blade strips on identity transforms. grass_field.gdshader wraps each tile
## around the camera, plants blades on the height map, rounds their normals,
## and curves/winds them. Buffers are written directly (12 floats/instance) —
## millions of blades in tens of milliseconds, zero CPU after boot.
func _build_fine_field() -> void:
	# Three carpets, each fading out as the next takes over. Blades get fewer
	# but wider with distance so PROJECTED coverage stays level — no visible
	# handoff bands: near ~415/m² to 27 m, mid ~69/m² to 51 m, far ~33/m² to
	# the fog line. Cheap 3-segment cards past the near ring.
	var far_mesh: ArrayMesh = _build_blade_strip(FAR_SEGMENTS)
	_spawn_field("FineFieldNear", _build_blade_strip(NEAR_SEGMENTS), NEAR_TILE,
			NEAR_COUNT, 0.42, 1.0, NEAR_TILE * 0.40, NEAR_TILE * 0.49)
	_spawn_field("FineFieldMid", far_mesh, MID_TILE,
			MID_COUNT, 0.46, 1.7, MID_TILE * 0.42, MID_TILE * 0.49)
	_spawn_field("FineFieldFar", far_mesh, FAR_TILE,
			FAR_COUNT, 0.50, 2.6, FAR_TILE * 0.42, FAR_TILE * 0.49)


## One camera-wrapped grass carpet, emitted as FIELD_CHUNKS² MultiMeshes so
## the engine can frustum-cull the blades behind the camera (see
## _update_field_culling). Height, width, and fade are per-field so the
## carpets differ while sharing the one shader.
func _spawn_field(
	node_name: String,
	blade: ArrayMesh,
	tile: float,
	count: int,
	blade_height: float,
	width_scale: float,
	fade_start: float,
	fade_end: float
) -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/grass_field.gdshader")
	mat.set_shader_parameter("height_map", _terrain.height_texture)
	mat.set_shader_parameter("terrain_size", MeadowTerrain.SIZE)
	mat.set_shader_parameter("water_level", _terrain.water_level)
	mat.set_shader_parameter("tile", tile)
	mat.set_shader_parameter("fade_start", fade_start)
	mat.set_shader_parameter("fade_end", fade_end)
	mat.set_shader_parameter("blade_height", blade_height)
	mat.set_shader_parameter("width_scale", width_scale)

	var field: Node3D = Node3D.new()
	field.name = node_name
	add_child(field)
	var chunk_size: float = tile / float(FIELD_CHUNKS)
	var per_chunk: int = count / (FIELD_CHUNKS * FIELD_CHUNKS)
	for cz in FIELD_CHUNKS:
		for cx in FIELD_CHUNKS:
			var x0: float = -tile * 0.5 + chunk_size * float(cx)
			var z0: float = -tile * 0.5 + chunk_size * float(cz)
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = blade
			mm.instance_count = per_chunk
			var buf: PackedFloat32Array = PackedFloat32Array()
			buf.resize(per_chunk * 12)
			var idx: int = 0
			for i in per_chunk:
				buf[idx] = 1.0
				buf[idx + 3] = x0 + _rng.randf() * chunk_size
				buf[idx + 5] = 1.0
				buf[idx + 10] = 1.0
				buf[idx + 11] = z0 + _rng.randf() * chunk_size
				idx += 12
			mm.buffer = buf

			var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mmi.name = "C%d_%d" % [cx, cz]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			field.add_child(mmi)
			_field_chunks.append({
				"mmi": mmi,
				"rect": Rect2(x0, z0, chunk_size, chunk_size),
				"tile": tile,
				"cull_dist": fade_end + chunk_size * 0.2,
			})


## Every frame each chunk's AABB is moved to the world rect its blades
## currently wrap to, and chunks fully outside their field's fade ring are
## hidden. ~200 cheap AABB updates buy back roughly half the vertex work.
func _update_field_culling() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	for chunk in _field_chunks:
		var tile: float = chunk["tile"]
		var rect: Rect2 = chunk["rect"]
		var mmi: MultiMeshInstance3D = chunk["mmi"]
		# Wrap each axis: a chunk maps to a contiguous world interval unless
		# it straddles the wrap seam — then fall back to the full tile span.
		var wx: float = cp.x + fposmod(rect.position.x - cp.x + tile * 0.5, tile) - tile * 0.5
		var wz: float = cp.z + fposmod(rect.position.y - cp.z + tile * 0.5, tile) - tile * 0.5
		var sx: float = rect.size.x
		var sz: float = rect.size.y
		if wx + sx > cp.x + tile * 0.5:
			wx = cp.x - tile * 0.5
			sx = tile
		if wz + sz > cp.z + tile * 0.5:
			wz = cp.z - tile * 0.5
			sz = tile
		# Distance cull: past the fade ring every blade has already died.
		var nearest: Vector2 = Vector2(
			clampf(cp.x, wx, wx + sx), clampf(cp.z, wz, wz + sz)
		)
		if nearest.distance_to(Vector2(cp.x, cp.z)) > chunk["cull_dist"]:
			mmi.visible = false
			continue
		mmi.visible = true
		mmi.custom_aabb = AABB(Vector3(wx, -40.0, wz), Vector3(sx, 100.0, sz))


func _process(_delta: float) -> void:
	_update_field_culling()


## One unit-height grass blade as a tapered vertical strip in the local XY
## plane (x = width in metres, y = 0→1 height, facing +Z). All curvature,
## normal rounding, and wind happen in the shader; this stays a cheap card.
## UV.x runs 0→1 across the width (drives normal rounding); UV.y runs 0→1
## root→tip. The final segment tapers to a point, giving a true blade tip.
func _build_blade_strip(segments: int) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	for seg in segments:
		var v0: float = float(seg) / float(segments)
		var v1: float = float(seg + 1) / float(segments)
		var w0: float = BLADE_HALF_WIDTH * pow(1.0 - v0, 0.7)
		var w1: float = BLADE_HALF_WIDTH * pow(1.0 - v1, 0.7)
		var pts: Array[Vector3] = [
			Vector3(-w0, v0, 0.0), Vector3(w0, v0, 0.0),
			Vector3(w1, v1, 0.0), Vector3(-w1, v1, 0.0),
		]
		var uvs: Array[Vector2] = [
			Vector2(0.0, v0), Vector2(1.0, v0),
			Vector2(1.0, v1), Vector2(0.0, v1),
		]
		for k in order:
			st.set_uv(uvs[k])
			st.set_normal(Vector3(0.0, 0.0, 1.0))
			st.add_vertex(pts[k])
	return st.commit()


func _ground_ok(x: float, z: float, h: float) -> bool:
	if absf(x) > MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN:
		return false
	if absf(z) > MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN:
		return false
	if h < _terrain.water_level + 0.35:  # pond bed and waterline stay bare
		return false
	return true


func _scatter_irises() -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _build_iris_mesh()
	mm.instance_count = IRIS_COUNT
	# Canon: the iris flats lie west of Bootstrap (GDD §7, WORLDBOOK).
	var clusters: Array[Vector2] = [
		Vector2(-95.0, 25.0), Vector2(-130.0, -15.0), Vector2(-75.0, 70.0),
		Vector2(-150.0, 55.0), Vector2(-110.0, 110.0),
	]
	# Real Iris dataset families, as bloom colors: setosa violet,
	# versicolor blue, virginica pale — the rare white is the collector tease.
	var petals: Array[Color] = [
		Color(0.52, 0.34, 0.78), Color(0.36, 0.44, 0.85), Color(0.88, 0.86, 0.95),
	]
	for i in IRIS_COUNT:
		var c: Vector2 = clusters[_rng.randi() % clusters.size()]
		var ang: float = _rng.randf_range(0.0, TAU)
		var dist: float = absf(_rng.randfn(0.0, 14.0))
		var x: float = c.x + cos(ang) * dist
		var z: float = c.y + sin(ang) * dist
		var h: float = _terrain.get_height(x, z)
		if not _ground_ok(x, z, h):
			h = -10000.0
		var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h, z))
		t = t.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
		var s: float = _rng.randf_range(0.8, 1.2)
		t = t.scaled_local(Vector3(s, s, s))
		mm.set_instance_transform(i, t)
		var roll: float = _rng.randf()
		var family: int = 0 if roll < 0.45 else (1 if roll < 0.9 else 2)
		mm.set_instance_color(i, petals[family])

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Irises"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## An iris: short stem quad + three diamond petals. Petal verts are COLOR
## white so instance color tints petals; stem verts stay green via COLOR.
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
	_fade_bloom(mat)
	st.set_material(mat)
	return st.commit()


## Blooms dissolve with distance — unfaded white petals read as scattered
## litter across the far sward instead of flowers.
func _fade_bloom(mat: StandardMaterial3D) -> void:
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_min_distance = 34.0
	mat.distance_fade_max_distance = 58.0


## Daisies: tiny white/cream blooms sprinkled everywhere — the ground clutter
## that makes a BOTW field feel alive at your feet.
func _scatter_daisies() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem: Color = Color(0.34, 0.52, 0.26)
	for k in 2:
		var b: Basis = Basis(Vector3.UP, PI * 0.5 * float(k))
		st.set_color(stem); st.set_normal(Vector3.UP)
		st.add_vertex(b * Vector3(-0.012, 0.0, 0.0))
		st.set_color(stem); st.set_normal(Vector3.UP)
		st.add_vertex(b * Vector3(0.012, 0.0, 0.0))
		st.set_color(stem); st.set_normal(Vector3.UP)
		st.add_vertex(b * Vector3(0.0, 0.16, 0.0))
	for k in 4:  # four petal diamonds around a warm center
		var b: Basis = Basis(Vector3.UP, TAU * float(k) / 4.0)
		var tip: Vector3 = Vector3(0.0, 0.16, 0.0)
		var out: Vector3 = b * Vector3(0.055, 0.015, 0.0)
		var side: Vector3 = b * Vector3(0.02, 0.0, 0.02)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip + out + side)
		st.set_color(Color(1.0, 0.9, 0.55)); st.set_normal(Vector3.UP); st.add_vertex(tip + out * 1.7)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip)
		st.set_color(Color(1.0, 0.9, 0.55)); st.set_normal(Vector3.UP); st.add_vertex(tip + out * 1.7)
		st.set_color(Color.WHITE); st.set_normal(Vector3.UP); st.add_vertex(tip + out - side)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fade_bloom(mat)
	st.set_material(mat)
	var mesh: ArrayMesh = st.commit()

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = DAISY_COUNT
	var half: float = MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN
	var tints: Array[Color] = [Color.WHITE, Color(1.0, 0.92, 0.95), Color(0.95, 0.9, 1.0)]
	var i: int = 0
	while i < DAISY_COUNT:
		var cx: float = _rng.randf_range(-half, half)
		var cz: float = _rng.randf_range(-half, half)
		var patch: int = mini(_rng.randi_range(3, 6), DAISY_COUNT - i)
		for j in patch:
			var x: float = cx + _rng.randfn(0.0, 1.1)
			var z: float = cz + _rng.randfn(0.0, 1.1)
			var h: float = _terrain.get_height(x, z)
			if not _ground_ok(x, z, h):
				h = -10000.0
			var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h, z))
			t = t.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
			var s: float = _rng.randf_range(0.8, 1.3)
			t = t.scaled_local(Vector3(s, s, s))
			mm.set_instance_transform(i, t)
			mm.set_instance_color(i, tints[_rng.randi() % tints.size()])
			i += 1
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Daisies"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Half-buried pebbles and small stones — quiet gray punctuation that keeps
## large grass fields from reading as a uniform green carpet.
func _scatter_pebbles() -> void:
	var pebble: SphereMesh = SphereMesh.new()
	pebble.radius = 0.16
	pebble.height = 0.2
	pebble.radial_segments = 6
	pebble.rings = 3
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/toon_soft.gdshader")
	mat.set_shader_parameter("rim_amount", 0.1)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = pebble
	pebble.material = mat
	mm.instance_count = PEBBLE_COUNT
	var half: float = MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN
	for i in PEBBLE_COUNT:
		var x: float = _rng.randf_range(-half, half)
		var z: float = _rng.randf_range(-half, half)
		var h: float = _terrain.get_height(x, z)
		if not _ground_ok(x, z, h):
			h = -10000.0
		var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h - 0.06, z))
		t = t.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
		var s: float = _rng.randf_range(0.4, 1.6)
		t = t.scaled_local(Vector3(s, s * _rng.randf_range(0.5, 0.8), s))
		mm.set_instance_transform(i, t)
		var g: float = _rng.randf_range(0.42, 0.6)
		mm.set_instance_color(i, Color(g, g * 0.97, g * 0.9))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Pebbles"
	mmi.multimesh = mm
	add_child(mmi)


func _plant_copses() -> void:
	var variants: Array[ArrayMesh] = [
		_build_tree_mesh(4.8, 3.0, Color(0.20, 0.36, 0.10)),
		_build_tree_mesh(5.9, 3.6, Color(0.17, 0.32, 0.085)),
		_build_tree_mesh(4.1, 2.65, Color(0.23, 0.40, 0.11)),
	]
	var trunk_shape: CylinderShape3D = CylinderShape3D.new()
	trunk_shape.radius = 0.46
	trunk_shape.height = 5.2
	var copses: Array[Vector2] = [
		Vector2(-160.0, -140.0), Vector2(60.0, -120.0), Vector2(160.0, -60.0),
		Vector2(170.0, 90.0), Vector2(60.0, 160.0), Vector2(-60.0, 170.0),
		Vector2(-170.0, 130.0), Vector2(-40.0, -170.0), Vector2(150.0, 170.0),
		Vector2(-190.0, 40.0), Vector2(120.0, 40.0), Vector2(30.0, -60.0),
		Vector2(-205.0, -65.0), Vector2(-115.0, -185.0), Vector2(205.0, -155.0),
		Vector2(205.0, 35.0), Vector2(5.0, 205.0), Vector2(-130.0, 205.0),
	]
	var trees: Node3D = Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	var planted: int = 0
	for c in copses:
		var count: int = _rng.randi_range(9, 15)
		for i in count:
			var ang: float = _rng.randf_range(0.0, TAU)
			var dist: float = absf(_rng.randfn(0.0, 16.0))
			var x: float = c.x + cos(ang) * dist
			var z: float = c.y + sin(ang) * dist
			var h: float = _terrain.get_height(x, z)
			if not _ground_ok(x, z, h):
				continue
			if Vector2(x, z).distance_to(MeadowTerrain.TOWN_CENTER) < MeadowTerrain.TOWN_FLAT_INNER:
				continue
			var tree: StaticBody3D = StaticBody3D.new()
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = variants[_rng.randi() % variants.size()]
			var col: CollisionShape3D = CollisionShape3D.new()
			col.shape = trunk_shape
			col.position.y = 2.6
			tree.add_child(mi)
			tree.add_child(col)
			tree.position = Vector3(x, h - 0.15, z)
			tree.rotation.y = _rng.randf_range(0.0, TAU)
			var s: float = _rng.randf_range(0.78, 1.25)
			tree.scale = Vector3(s, s, s)
			trees.add_child(tree)
			planted += 1
	print("MeadowFlora: %d trees across %d copses." % [planted, copses.size()])


## Realistic-fidelity tree: tapered trunk + 4-5 angled boughs (all wearing
## the procedural bark shader's grooves), crowned with ~850 individual leaf
## quads distributed through ellipsoid clouds at the crown and bough ends —
## every leaf flutters independently in the leaf shader's wind.
## Appends a capped, tapered cylinder aligned from start to end. Repeated short
## segments are cheaper than bespoke branch topology while preserving a fully
## readable trunk-primary-secondary-twig hierarchy.
func _append_tapered_branch(
	st: SurfaceTool,
	start: Vector3,
	end: Vector3,
	bottom_radius: float,
	top_radius: float,
	radial_segments: int
) -> void:
	var delta: Vector3 = end - start
	var length: float = delta.length()
	if length < 0.001:
		return
	var direction: Vector3 = delta / length
	var axis: Vector3 = Vector3.UP.cross(direction)
	var basis: Basis = Basis.IDENTITY
	if axis.length_squared() > 0.0001:
		basis = Basis(axis.normalized(), acos(clampf(Vector3.UP.dot(direction), -1.0, 1.0)))
	elif direction.dot(Vector3.UP) < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	var branch: CylinderMesh = CylinderMesh.new()
	branch.top_radius = top_radius
	branch.bottom_radius = bottom_radius
	branch.height = length
	branch.radial_segments = radial_segments
	branch.rings = 2
	st.append_from(branch, 0, Transform3D(basis, (start + end) * 0.5))


## High-detail broadleaf tree assembled as one shared two-surface mesh per
## variant: root flare and trunk, bent primary limbs, secondary limbs, fine
## twigs, then several thousand individually shaped leaves distributed through
## overlapping branch-tip strata. Reusing three variants keeps the forest
## inexpensive even though the silhouettes are dense at arm's length.
func _build_tree_mesh(trunk_h: float, crown_r: float, crown_col: Color) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.24
	trunk.bottom_radius = 0.52
	trunk.height = trunk_h
	trunk.radial_segments = 18
	trunk.rings = 6
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, trunk_h * 0.5, 0.0)))

	# Buttress roots anchor the silhouette instead of letting a cylinder meet
	# the terrain with the toy-like seam visible in the previous pass.
	var root_count: int = 7
	for root_index in root_count:
		var root_yaw: float = TAU * float(root_index) / float(root_count) + _rng.randf_range(-0.16, 0.16)
		var root_start: Vector3 = Vector3(
			cos(root_yaw) * 0.24, 0.36, sin(root_yaw) * 0.24
		)
		var root_length: float = _rng.randf_range(0.8, 1.35)
		var root_end: Vector3 = Vector3(
			cos(root_yaw) * root_length, 0.02, sin(root_yaw) * root_length
		)
		_append_tapered_branch(st, root_start, root_end, 0.19, 0.035, 7)

	var cluster_centers: Array[Vector3] = []
	var cluster_radii: Array[Vector3] = []
	cluster_centers.append(Vector3(0.0, trunk_h * 0.9 + crown_r * 0.36, 0.0))
	cluster_radii.append(Vector3(crown_r * 0.72, crown_r * 0.56, crown_r * 0.72))
	cluster_centers.append(Vector3(0.0, trunk_h + crown_r * 0.82, 0.0))
	cluster_radii.append(Vector3(crown_r * 0.48, crown_r * 0.58, crown_r * 0.48))

	# A visible central leader prevents the crown from reading as a detached ball.
	var leader_start: Vector3 = Vector3(0.0, trunk_h * 0.72, 0.0)
	var leader_mid: Vector3 = Vector3(0.08, trunk_h + crown_r * 0.3, -0.06)
	var leader_end: Vector3 = Vector3(-0.06, trunk_h + crown_r * 1.18, 0.1)
	_append_tapered_branch(st, leader_start, leader_mid, 0.19, 0.105, 9)
	_append_tapered_branch(st, leader_mid, leader_end, 0.105, 0.035, 7)
	cluster_centers.append(leader_end)
	cluster_radii.append(Vector3(crown_r * 0.31, crown_r * 0.36, crown_r * 0.31))

	var bough_count: int = _rng.randi_range(8, 10)
	for bough_index in bough_count:
		var yaw: float = TAU * float(bough_index) / float(bough_count)
		yaw += _rng.randf_range(-0.28, 0.28)
		var attach_h: float = trunk_h * _rng.randf_range(0.5, 0.91)
		var upward: float = _rng.randf_range(0.25, 0.62)
		var primary_direction: Vector3 = Vector3(cos(yaw), upward, sin(yaw)).normalized()
		var primary_length: float = crown_r * _rng.randf_range(0.82, 1.18)
		var attach: Vector3 = Vector3(0.0, attach_h, 0.0)
		var elbow: Vector3 = attach + primary_direction * (primary_length * 0.54)
		elbow += Vector3.UP * _rng.randf_range(0.05, 0.22)
		var primary_end: Vector3 = attach + primary_direction * primary_length
		primary_end += Vector3.UP * _rng.randf_range(0.12, 0.42)
		_append_tapered_branch(st, attach, elbow, 0.17, 0.105, 9)
		_append_tapered_branch(st, elbow, primary_end, 0.105, 0.052, 8)
		cluster_centers.append(primary_end)
		cluster_radii.append(Vector3(
			crown_r * _rng.randf_range(0.36, 0.5),
			crown_r * _rng.randf_range(0.3, 0.43),
			crown_r * _rng.randf_range(0.36, 0.5)
		))

		var secondary_count: int = _rng.randi_range(2, 3)
		for secondary_index in secondary_count:
			var along: float = 0.42 + 0.2 * float(secondary_index)
			var secondary_start: Vector3 = attach.lerp(primary_end, along)
			var side_sign: float = -1.0 if secondary_index % 2 == 0 else 1.0
			var secondary_yaw: float = yaw + side_sign * _rng.randf_range(0.55, 1.05)
			var lateral: Vector3 = Vector3(cos(secondary_yaw), 0.0, sin(secondary_yaw))
			var secondary_direction: Vector3 = (
				primary_direction * 0.3 + lateral * 0.7 + Vector3.UP * _rng.randf_range(0.1, 0.28)
			).normalized()
			var secondary_length: float = crown_r * _rng.randf_range(0.46, 0.72)
			var secondary_end: Vector3 = secondary_start + secondary_direction * secondary_length
			_append_tapered_branch(st, secondary_start, secondary_end, 0.062, 0.025, 6)
			cluster_centers.append(secondary_end)
			cluster_radii.append(Vector3(
				crown_r * _rng.randf_range(0.23, 0.34),
				crown_r * _rng.randf_range(0.2, 0.3),
				crown_r * _rng.randf_range(0.23, 0.34)
			))

			# Fine twigs remain visible through deliberate gaps in the leaf strata.
			var twig_start: Vector3 = secondary_start.lerp(secondary_end, 0.58)
			var twig_yaw: float = secondary_yaw + _rng.randf_range(-0.65, 0.65)
			var twig_direction: Vector3 = Vector3(
				cos(twig_yaw), _rng.randf_range(0.25, 0.62), sin(twig_yaw)
			).normalized()
			var twig_end: Vector3 = twig_start + twig_direction * crown_r * _rng.randf_range(0.22, 0.38)
			_append_tapered_branch(st, twig_start, twig_end, 0.028, 0.009, 5)
			cluster_centers.append(twig_end)
			cluster_radii.append(Vector3.ONE * crown_r * _rng.randf_range(0.14, 0.2))

	var mesh: ArrayMesh = st.commit()

	# Surface 1: dense but perforated leaf strata. Weighting cluster volume by
	# 0.72 gives smaller branch-tip clusters enough leaves to retain branching.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cluster_weights: PackedFloat32Array = PackedFloat32Array()
	var total_weight: float = 0.0
	for cluster_index in cluster_centers.size():
		var radii: Vector3 = cluster_radii[cluster_index]
		var weight: float = pow(radii.x * radii.y * radii.z, 0.72)
		cluster_weights.append(weight)
		total_weight += weight
	var leaf_count: int = int(3200.0 + crown_r * 500.0)
	var quad_order: Array[int] = [0, 1, 2, 0, 2, 3]
	var uvs: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(1.0, 0.0),
		Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	]
	for leaf_index in leaf_count:
		var pick: float = _rng.randf() * total_weight
		var chosen_index: int = 0
		for cluster_index in cluster_centers.size():
			pick -= cluster_weights[cluster_index]
			if pick <= 0.0:
				chosen_index = cluster_index
				break
		var chosen_center: Vector3 = cluster_centers[chosen_index]
		var chosen_radii: Vector3 = cluster_radii[chosen_index]
		var radius: float = pow(_rng.randf(), 0.46)
		var theta: float = _rng.randf_range(0.0, TAU)
		var phi: float = acos(_rng.randf_range(-1.0, 1.0))
		var sphere_point: Vector3 = Vector3(
			sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)
		) * radius
		var leaf_position: Vector3 = chosen_center + sphere_point * chosen_radii

		var yaw_basis: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
		var tilt_basis: Basis = Basis(Vector3.RIGHT, _rng.randf_range(-1.2, 1.2))
		var roll_basis: Basis = Basis(Vector3.FORWARD, _rng.randf_range(-0.35, 0.35))
		var leaf_basis: Basis = yaw_basis * tilt_basis * roll_basis
		var half_width: float = _rng.randf_range(0.09, 0.155)
		var leaf_length: float = _rng.randf_range(0.3, 0.48)
		var leaf_x: Vector3 = leaf_basis.x * half_width
		var leaf_y: Vector3 = leaf_basis.y * (leaf_length * 0.5)
		var corners: Array[Vector3] = [
			leaf_position - leaf_x - leaf_y,
			leaf_position + leaf_x - leaf_y,
			leaf_position + leaf_x + leaf_y,
			leaf_position - leaf_x + leaf_y,
		]
		var leaf_phase: float = _rng.randf()
		var height_ratio: float = clampf(
			leaf_position.y / (trunk_h + crown_r * 1.55), 0.0, 1.0
		)
		for corner_index in quad_order:
			st.set_uv(uvs[corner_index])
			st.set_uv2(Vector2(leaf_phase, height_ratio))
			st.set_normal(leaf_basis.z.normalized())
			st.add_vertex(corners[corner_index])
	mesh = st.commit(mesh)

	var bark: ShaderMaterial = ShaderMaterial.new()
	bark.shader = load("res://assets/shaders/bark.gdshader")
	bark.set_shader_parameter("tree_height", trunk_h + crown_r * 1.55)
	var leaf: ShaderMaterial = ShaderMaterial.new()
	leaf.shader = load("res://assets/shaders/leaf_wind.gdshader")
	leaf.set_shader_parameter("tree_height", trunk_h + crown_r * 1.55)
	leaf.set_shader_parameter("leaf_a", crown_col.darkened(0.2))
	leaf.set_shader_parameter("leaf_b", crown_col.lightened(0.15))
	mesh.surface_set_material(0, bark)
	mesh.surface_set_material(1, leaf)
	return mesh

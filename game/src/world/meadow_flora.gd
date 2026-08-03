class_name MeadowFlora
extends Node3D
## Datasedge Meadows vegetation.
##
## Everything scattered deterministically (fixed seed) on the terrain the
## sibling MeadowTerrain generated: a photoreal 2.5M-blade grass carpet in two
## camera-wrapped MultiMesh fields (grass_field.gdshader does the planting,
## clumping, wind, and trample), daisies, pebbles, and tree copses with trunk
## collision. Zero textures — all variation is procedural.
##
## The iris flats to the west are now collectible. IrisField keeps the current
## high-density grass implementation intact while owning the 700 bloom
## transforms, specimen records, collection animation, and compendium feed.

const SCATTER_SEED: int = 20260717
# Three camera-wrapped carpets share grass_field.gdshader. The near field is a
# BURY-THE-GROUND sward right around the camera (~1700 blades/m², 5-segment
# cards) — dense enough that grass is practically all you see, with only faint
# dirt peeking through (Danny's directive); the far fields carry the sweep to
# the horizon with fewer, wider, cheaper 3-segment blades (Ghost-of-Tsushima
# distance trick). ~8.5M blades: deliberately extravagant for a high-end GPU
# (GDD §10 "spend the budget"). Grass still thins on slopes / near rocks &
# water via the shader's alive-mask, so those spots keep showing ground.
const NEAR_COUNT: int = 2800000
const NEAR_TILE: float = 48.0
const NEAR_SEGMENTS: int = 5
const MID_COUNT: int = 1300000
const MID_TILE: float = 104.0
const FAR_COUNT: int = 1300000
const FAR_TILE: float = 190.0
const FAR_SEGMENTS: int = 3
const BLADE_HALF_WIDTH: float = 0.017
# Each field is split into CHUNKS×CHUNKS MultiMeshes whose AABBs track their
# wrapped world rects every frame — so Godot frustum-culls the blades behind
# the camera (a single whole-map AABB defeats culling and doubles frame cost).
const FIELD_CHUNKS: int = 8
const DAISY_COUNT: int = 1200
const PEBBLE_COUNT: int = 750
const EDGE_MARGIN: float = 12.0

@onready var _terrain: MeadowTerrain = $"../Terrain"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# One entry per field chunk: {mmi, rect (tile-local), tile, cull_dist}.
var _field_chunks: Array[Dictionary] = []
## Collectible iris flats, exposed so Main can connect the compendium UI.
var iris_field: IrisField


## Blade-count multiplier. The shipped density (~5.4M blades) is tuned for a
## high-end desktop GPU per GDD §10 and will crawl on a laptop/Mac, which makes
## the game hard to iterate on there. `-- --grass=0.25` (any 0.05-1.0 value)
## scales every carpet without changing the look's character, so a weaker
## machine can still run, test and judge everything else.
func _grass_scale() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grass="):
			return clampf(float(arg.get_slice("=", 1)), 0.05, 1.0)
	return 1.0


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	_rng.seed = SCATTER_SEED
	# Dev A/B: `-- --no-grass` boots without the blade carpets so frame cost
	# can be attributed honestly (grass vs sky/GI/shadows).
	if not OS.get_cmdline_user_args().has("--no-grass"):
		_build_fine_field()
	_scatter_daisies()
	_scatter_pebbles()
	_plant_copses()
	# Same seed the rest of the flora uses, preserving the established western
	# clusters while giving every bloom a real specimen record.
	iris_field = IrisField.build(self, _terrain, SCATTER_SEED)
	var s: float = _grass_scale()
	print("MeadowFlora: %d near + %d mid + %d far blades (scale %.2f), %d collectible irises, %d daisies, %d pebbles in %d ms." % [
		int(NEAR_COUNT * s), int(MID_COUNT * s), int(FAR_COUNT * s), s,
		IrisField.IRIS_COUNT, DAISY_COUNT, PEBBLE_COUNT,
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
	# handoff bands: near ~1700/m² to 25 m (buries the ground), mid ~222/m² to
	# 51 m, far ~42/m² to the fog line. Cheap 3-segment cards past the near ring.
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
	# Bootstrap's footprint: the field thins and crops short through town so the
	# square reads as trodden ground rather than waist-high meadow.
	mat.set_shader_parameter("town_center", MeadowTerrain.TOWN_CENTER)
	mat.set_shader_parameter("town_inner", MeadowTerrain.TOWN_FLAT_INNER * 0.9)
	mat.set_shader_parameter("town_outer", MeadowTerrain.TOWN_FLAT_OUTER * 0.85)

	var field: Node3D = Node3D.new()
	field.name = node_name
	add_child(field)
	var chunk_size: float = tile / float(FIELD_CHUNKS)
	var scaled_count: int = maxi(1, int(count * _grass_scale()))
	var per_chunk: int = maxi(1, scaled_count / (FIELD_CHUNKS * FIELD_CHUNKS))
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
	# Six variants, not three, and spread across a real height range. Three
	# near-identical shapes planted sixty times is what made the copses read as
	# an orchard; the trunk lean (see `_trunk_axis`) does the rest. A young
	# 3.4 m tree beside a 7.1 m veteran is what a wild copse actually looks
	# like, and the staggered crowns break the flat ceiling the canopy had.
	var variants: Array[ArrayMesh] = [
		_build_tree_mesh(3.4, 2.10, Color(0.25, 0.42, 0.12)),
		_build_tree_mesh(4.1, 2.65, Color(0.23, 0.40, 0.11)),
		_build_tree_mesh(4.8, 3.00, Color(0.20, 0.36, 0.10)),
		_build_tree_mesh(5.5, 3.35, Color(0.185, 0.345, 0.095)),
		_build_tree_mesh(5.9, 3.60, Color(0.17, 0.32, 0.085)),
		_build_tree_mesh(7.1, 4.05, Color(0.155, 0.30, 0.08)),
	]
	# Trunk heights, parallel to `variants`. The climb needs to know how far up a
	# given tree actually goes, and guessing from the mesh AABB would include the
	# crown, which would send Kern climbing into thin air above the boughs.
	var variant_trunk_h: Array[float] = [3.4, 4.1, 4.8, 5.5, 5.9, 7.1]
	# Only trunks at least this tall (after instance scaling) are worth climbing.
	# A meadow where every sapling is a ladder has no decisions in it.
	var climbable_min_h: float = 4.6
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
	var climbable: int = 0
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
			var variant_index: int = _rng.randi() % variants.size()
			mi.mesh = variants[variant_index]
			var col: CollisionShape3D = CollisionShape3D.new()
			col.shape = trunk_shape
			col.position.y = 2.6
			tree.add_child(mi)
			tree.add_child(col)
			tree.position = Vector3(x, h - 0.15, z)
			tree.rotation.y = _rng.randf_range(0.0, TAU)
			# Non-uniform: height varies more than girth, so two instances of one
			# variant still read as different trees, not a copy-paste.
			var s: float = _rng.randf_range(0.80, 1.22)
			var height_scale: float = _rng.randf_range(0.86, 1.18)
			tree.scale = Vector3(s, s * height_scale, s)
			# Climbable if the scaled trunk clears the bar. The metadata is what
			# `TreeClimb` reads: how high the trunk runs and how fat it is, both in
			# world units after scaling, so the climb hugs the real surface.
			var scaled_trunk: float = variant_trunk_h[variant_index] * s * height_scale
			if scaled_trunk >= climbable_min_h:
				tree.add_to_group(&"climbable")
				tree.set_meta("climb_height", scaled_trunk)
				tree.set_meta("climb_radius", 0.46 * s)
				climbable += 1
			trees.add_child(tree)
			planted += 1
	print("MeadowFlora: %d trees across %d copses, %d climbable." % [
			planted, copses.size(), climbable])


## 137.5 degrees in radians — the angle successive leaves step round a stem in
## almost every real plant, because it is the rotation that packs leaves so none
## sits directly above another and shades it. Free to implement and it is most
## of why real foliage does not read as rows.
const GOLDEN_ANGLE: float = 2.39996323


## Every twig of the tree currently being built, as `{a, b}` endpoints in local
## space. Leaves are hung along these, so foliage is attached to the branch that
## carries it rather than floating in a cloud near it.
var _twigs: Array[Dictionary] = []


## Grow a fan of twigs off a parent branch, each with its own finer twiglets,
## and record every one for the foliage pass.
##
## This is the level of branching that was missing. The old tree stopped at
## "secondary limb, one twig" — perhaps 25 tips for the whole crown — so leaves
## had nothing to hang from and were scattered into ellipsoids instead. Three
## levels of twig give a few hundred tips, which is what makes the canopy read
## as connected rather than as green wool laid over a skeleton.
func _grow_twigs(st: SurfaceTool, parent_start: Vector3, parent_end: Vector3,
		crown_r: float, count: int) -> void:
	var parent_axis: Vector3 = parent_end - parent_start
	if parent_axis.length_squared() < 0.000001:
		return
	parent_axis = parent_axis.normalized()
	for twig_index in count:
		# Spread the twigs along the outer half of the parent, spiralling round
		# it, the same way the leaves will spiral round the twigs.
		var along: float = 0.42 + 0.55 * (float(twig_index) + _rng.randf()) / float(count)
		var start: Vector3 = parent_start.lerp(parent_end, along)
		var spiral: float = float(twig_index) * GOLDEN_ANGLE + _rng.randf_range(-0.3, 0.3)
		var frame_u: Vector3 = parent_axis.cross(Vector3.UP)
		if frame_u.length_squared() < 0.001:
			frame_u = parent_axis.cross(Vector3.RIGHT)
		frame_u = frame_u.normalized()
		var frame_v: Vector3 = parent_axis.cross(frame_u).normalized()
		var out_dir: Vector3 = frame_u * cos(spiral) + frame_v * sin(spiral)
		# Twigs reach outward and upward — foliage chases light.
		var direction: Vector3 = (out_dir * 0.74 + parent_axis * 0.42
				+ Vector3.UP * _rng.randf_range(0.12, 0.44)).normalized()
		# Longer than the first pass. A twig's leaves can only cover the volume the
		# twig itself sweeps, so short twigs leave holes no leaf count can fill.
		var length: float = crown_r * _rng.randf_range(0.26, 0.44)
		var finish: Vector3 = start + direction * length
		_append_tapered_branch(st, start, finish, 0.022, 0.009, 5)
		_twigs.append({"a": start, "b": finish})

		# Twiglets: the last fork before leaf. Short, numerous, and the thing
		# that actually carries most of the canopy.
		var twiglet_count: int = _rng.randi_range(4, 6)
		for twiglet_index in twiglet_count:
			var t_along: float = 0.34 + 0.6 * (float(twiglet_index) + _rng.randf()) \
					/ float(twiglet_count)
			var t_start: Vector3 = start.lerp(finish, t_along)
			var t_spiral: float = float(twiglet_index) * GOLDEN_ANGLE
			var t_out: Vector3 = frame_u * cos(t_spiral) + frame_v * sin(t_spiral)
			var t_dir: Vector3 = (t_out * 0.66 + direction * 0.52
					+ Vector3.UP * _rng.randf_range(0.06, 0.3)).normalized()
			var t_end: Vector3 = t_start + t_dir * crown_r * _rng.randf_range(0.15, 0.26)
			_append_tapered_branch(st, t_start, t_end, 0.010, 0.004, 4)
			_twigs.append({"a": t_start, "b": t_end})


## The current tree's lean, as a horizontal displacement in metres applied at
## full trunk height. Set at the top of `_build_tree_mesh` and read by
## `_trunk_axis`; it exists as a field only because GDScript has no closures and
## every part of the crown has to agree with the trunk about where "up" went.
var _lean: Vector3 = Vector3.ZERO


## A point on the trunk's centre-line at normalized height `t` (0 = root,
## 1 = top). Quadratic in `t`, so the base stays planted and the lean grows
## toward the crown — a tree that curves, rather than a pole tipped over.
func _trunk_axis(t: float, trunk_h: float) -> Vector3:
	return Vector3(0.0, trunk_h * t, 0.0) + _lean * t * t


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

	# The trunk LEANS AND DRIFTS. It used to be one perfectly vertical cylinder,
	# and with three variants planted sixty times that read as an orchard — every
	# tree the same plumb-line, every crown at the same height. A tree that grew
	# somewhere windy leans; one that reached for a gap bends. Four stacked
	# tapered segments following a wandering axis cost almost nothing and break
	# the plantation look at every distance.
	# `_lean` is stored on the instance so `_trunk_axis()` can reproduce the same
	# curve for the boughs and crown clusters. If the crown ignored the lean it
	# would float off the top of a tilted trunk, which is worse than no lean.
	_lean = Vector3(cos(_rng.randf_range(0.0, TAU)), 0.0, 0.0)
	_lean = _lean.rotated(Vector3.UP, _rng.randf_range(0.0, TAU)) \
			* _rng.randf_range(0.03, 0.16) * trunk_h
	var trunk_segments: int = 4
	for seg in trunk_segments:
		var t0: float = float(seg) / float(trunk_segments)
		var t1: float = float(seg + 1) / float(trunk_segments)
		_append_tapered_branch(st, _trunk_axis(t0, trunk_h), _trunk_axis(t1, trunk_h),
				lerpf(0.52, 0.24, t0), lerpf(0.52, 0.24, t1), 18)

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
	# Every twig and twiglet, as {a, b} in local space. LEAVES GROW ALONG THESE.
	#
	# The old crown was ellipsoid clouds of leaves floating at branch tips, which
	# is why it read as green cotton wool stuck onto a skeleton: no leaf was
	# attached to anything. Foliage now hangs off the twig that carries it, with
	# real phyllotaxis, so following any leaf inward reaches a twig, then a
	# secondary, then a bough, then the trunk.
	_twigs.clear()

	# A visible central leader prevents the crown from reading as a detached ball.
	var leader_start: Vector3 = _trunk_axis(0.72, trunk_h)
	var leader_mid: Vector3 = _trunk_axis(1.0, trunk_h) 			+ Vector3(0.08, crown_r * 0.3, -0.06)
	var leader_end: Vector3 = _trunk_axis(1.0, trunk_h) 			+ Vector3(-0.06, crown_r * 1.18, 0.1) + _lean * 0.35
	_append_tapered_branch(st, leader_start, leader_mid, 0.19, 0.105, 9)
	_append_tapered_branch(st, leader_mid, leader_end, 0.105, 0.035, 7)
	_grow_twigs(st, leader_mid, leader_end, crown_r, 4)

	var bough_count: int = _rng.randi_range(8, 10)
	for bough_index in bough_count:
		var yaw: float = TAU * float(bough_index) / float(bough_count)
		yaw += _rng.randf_range(-0.28, 0.28)
		var attach_h: float = trunk_h * _rng.randf_range(0.5, 0.91)
		var upward: float = _rng.randf_range(0.25, 0.62)
		var primary_direction: Vector3 = Vector3(cos(yaw), upward, sin(yaw)).normalized()
		var primary_length: float = crown_r * _rng.randf_range(0.82, 1.18)
		var attach: Vector3 = _trunk_axis(attach_h / trunk_h, trunk_h)
		var elbow: Vector3 = attach + primary_direction * (primary_length * 0.54)
		elbow += Vector3.UP * _rng.randf_range(0.05, 0.22)
		var primary_end: Vector3 = attach + primary_direction * primary_length
		primary_end += Vector3.UP * _rng.randf_range(0.12, 0.42)
		_append_tapered_branch(st, attach, elbow, 0.17, 0.105, 9)
		_append_tapered_branch(st, elbow, primary_end, 0.105, 0.052, 8)

		var secondary_count: int = _rng.randi_range(3, 4)
		for secondary_index in secondary_count:
			var along: float = 0.34 + 0.19 * float(secondary_index)
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
			# Three or four twigs per secondary, each carrying its own twiglets.
			_grow_twigs(st, secondary_start, secondary_end, crown_r,
					_rng.randi_range(3, 4))

	var mesh: ArrayMesh = st.commit()

	# Surface 1: foliage, hung along the twigs collected above.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# LEAF BUDGET, tuned by render across two passes.
	#
	# The old 0.30-0.48 m leaves read as coins from ten metres, so they were cut
	# to real broadleaf size. Then hanging them along TWIGS instead of filling
	# ellipsoid clouds thinned the canopy badly — leaves on a line project far
	# less area than leaves filling a volume, and the copse came out looking like
	# bare spring saplings. Structure was right, density was wrong.
	#
	# So the count roughly doubles to pay for the honest placement. This is the
	# expensive way to build a crown and it is the one that looks like a tree.
	var leaf_count: int = int(23000.0 + crown_r * 2600.0)
	var quad_order: Array[int] = [0, 1, 2, 0, 2, 3]
	var uvs: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(1.0, 0.0),
		Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	]
	var crown_top: float = trunk_h + crown_r * 1.55
	# Longer twigs carry proportionally more leaves, so the crown thickens where
	# the branching actually is instead of uniformly.
	var twig_weights: PackedFloat32Array = PackedFloat32Array()
	var total_weight: float = 0.0
	for twig in _twigs:
		var w: float = (twig["b"] as Vector3).distance_to(twig["a"])
		twig_weights.append(w)
		total_weight += w
	if total_weight <= 0.0:
		push_warning("MeadowFlora: tree built with no twigs; crown will be bare.")
		total_weight = 1.0

	for leaf_index in leaf_count:
		var pick: float = _rng.randf() * total_weight
		var chosen: int = 0
		for twig_index in _twigs.size():
			pick -= twig_weights[twig_index]
			if pick <= 0.0:
				chosen = twig_index
				break
		var a: Vector3 = _twigs[chosen]["a"]
		var b: Vector3 = _twigs[chosen]["b"]
		var axis: Vector3 = b - a
		if axis.length_squared() < 0.000001:
			continue
		axis = axis.normalized()

		# Spread UNIFORMLY along the twig. Biasing toward the tip (the first pass
		# used pow(randf, 0.62), reasoning that new growth is outermost) piled every
		# leaf into the last few centimetres, and since twiglets are short the crown
		# came out as discrete pom-poms on sticks — broccoli, not a tree.
		var along_t: float = _rng.randf()
		var base: Vector3 = a.lerp(b, along_t)

		# Phyllotaxis: successive leaves step round the twig by the golden angle,
		# 137.5 degrees. It is why real foliage never shades itself in rows, and
		# it is free — one multiply on the leaf index.
		var spiral: float = float(leaf_index) * GOLDEN_ANGLE
		var frame_u: Vector3 = axis.cross(Vector3.UP)
		if frame_u.length_squared() < 0.001:
			frame_u = axis.cross(Vector3.RIGHT)
		frame_u = frame_u.normalized()
		var frame_v: Vector3 = axis.cross(frame_u).normalized()
		var out_dir: Vector3 = (frame_u * cos(spiral) + frame_v * sin(spiral)).normalized()

		# The blade droops away from the twig under its own weight, and tilts a
		# little along the twig so it is not a perfect wheel of spokes.
		var droop: float = _rng.randf_range(0.25, 0.72)
		var long_axis: Vector3 = (out_dir + Vector3.DOWN * droop
				+ axis * _rng.randf_range(-0.18, 0.34)).normalized()
		var side_axis: Vector3 = axis.cross(long_axis)
		if side_axis.length_squared() < 0.000001:
			side_axis = frame_u
		side_axis = side_axis.normalized()

		# Real broadleaf foliage is 6-14 cm across. Nudged up from the first
		# pass's 3.5-6.2 cm half-width, which was accurate for a small leaf and
		# left the crown reading thin once the leaves moved onto the twigs.
		var half_width: float = _rng.randf_range(0.045, 0.075)
		var leaf_length: float = _rng.randf_range(0.16, 0.26)
		# The petiole: a short stalk, so the blade starts clear of the twig
		# instead of intersecting it.
		var petiole: float = _rng.randf_range(0.012, 0.03)
		var leaf_center: Vector3 = base + long_axis * (petiole + leaf_length * 0.5)
		var leaf_x: Vector3 = side_axis * half_width
		var leaf_y: Vector3 = long_axis * (leaf_length * 0.5)
		var corners: Array[Vector3] = [
			leaf_center - leaf_x - leaf_y,
			leaf_center + leaf_x - leaf_y,
			leaf_center + leaf_x + leaf_y,
			leaf_center - leaf_x + leaf_y,
		]
		var leaf_phase: float = _rng.randf()
		var height_ratio: float = clampf(leaf_center.y / crown_top, 0.0, 1.0)
		var leaf_normal: Vector3 = side_axis.cross(long_axis).normalized()
		for corner_index in quad_order:
			st.set_uv(uvs[corner_index])
			st.set_uv2(Vector2(leaf_phase, height_ratio))
			st.set_normal(leaf_normal)
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

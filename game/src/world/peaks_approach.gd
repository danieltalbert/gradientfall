class_name PeaksApproach
extends Node3D
## The northern approach to the Gradient Peaks — the density pass that makes
## the meadow-to-mountain transition read like a real, inhabited world
## instead of a bare field with a backdrop (GDD §2 pillar 4, the BOTW rule:
## "if it looks interesting from a distance, something is actually there").
##
## Three deterministic scatters on the meadow's north band, all on-theme:
##   • an alpine TREELINE climbing the foothills — dense at the meadow's edge,
##     thinning upward to a ragged line, cool spruce high / warm fir low;
##   • BOULDER fields that visibly SORT with altitude (random low down; graded
##     sizes and a shared heading high up) — the hermit's "the mountains are
##     slowly sorting themselves," made literal (WORLDBOOK §3);
##   • DESCENT'S REST, the switchback village (WORLDBOOK §3), terraced houses
##     with warm-lit windows nestled where the foothills begin.
##
## Iterated against the Python twin (tools/proto_mountains.py, DEVLOG
## 2026-07-19). Trees/boulders are MultiMesh scenery (no per-instance
## collision yet — a follow-up); the village is instanced meshes.

const APPROACH_SEED: int = 20260719
## North band the approach dresses (world z; north is -z). Kept inside the
## 480 m terrain so everything sits on real ground with real height.
const BAND_Z_NEAR: float = -95.0
const BAND_Z_FAR: float = -236.0
const TREE_COUNT: int = 900
const BOULDER_COUNT: int = 120

const CONIFER_HI: Color = Color(0.128, 0.196, 0.15)   # alpine spruce, cool
const CONIFER_LO: Color = Color(0.205, 0.3, 0.17)     # warmer lower firs
const BOULDER_COL: Color = Color(0.5, 0.475, 0.452)
const TRUNK_COL: Color = Color(0.2, 0.14, 0.1)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _terrain: MeadowTerrain = $"../Terrain"


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	_rng.seed = APPROACH_SEED
	_scatter_treeline()
	_scatter_boulders()
	_raise_descents_rest()
	print("PeaksApproach: treeline + boulders + Descent's Rest in %d ms." % [
		Time.get_ticks_msec() - start_ms,
	])


func _band_ok(x: float, z: float, h: float) -> bool:
	if absf(x) > MeadowTerrain.SIZE * 0.5 - 10.0:
		return false
	if h < _terrain.water_level + 0.4:
		return false
	if Vector2(x, z).distance_to(MeadowTerrain.TOWN_CENTER) < 46.0:
		return false
	if Vector2(x, z).distance_to(MeadowTerrain.POND_CENTER) < MeadowTerrain.POND_RADIUS + 6.0:
		return false
	return true


## A cheap impostor conifer: a thin trunk + three stacked foliage cones. One
## mesh, MultiMesh'd hundreds of times with per-instance tint and scale — the
## alpine forest at vista distance, near-free after boot.
func _build_conifer_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.16
	trunk.height = 1.4
	trunk.radial_segments = 6
	trunk.rings = 1
	_append_colored(st, trunk, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.7, 0.0)), TRUNK_COL)
	# Three stacked foliage cones — the spruce silhouette. COLOR is white so
	# the MultiMesh instance tint fully drives each tree's hue.
	var tiers: Array = [
		{"y": 1.1, "r": 1.5, "h": 2.4},
		{"y": 2.3, "r": 1.05, "h": 2.0},
		{"y": 3.4, "r": 0.6, "h": 1.5},
	]
	for tier in tiers:
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = tier["r"]
		cone.height = tier["h"]
		cone.radial_segments = 7
		cone.rings = 1
		var cy: float = tier["y"] + tier["h"] * 0.5
		_append_colored(st, cone, Transform3D(Basis.IDENTITY, Vector3(0.0, cy, 0.0)), Color.WHITE)
	st.generate_normals()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	# Sky-tinted fill so shaded needles read painted, not dead (matches the
	# toon_soft fill trick used across the world).
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.14, 0.12)
	mat.emission_energy_multiplier = 0.25
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


func _append_colored(st: SurfaceTool, prim: PrimitiveMesh, xform: Transform3D, col: Color) -> void:
	var arr: Array = prim.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(col)
		st.set_normal(xform.basis * norms[i])
		st.add_vertex(xform * verts[i])


func _scatter_treeline() -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _build_conifer_mesh()
	mm.instance_count = TREE_COUNT
	var placed: int = 0
	var tries: int = 0
	while placed < TREE_COUNT and tries < TREE_COUNT * 8:
		tries += 1
		var z: float = _rng.randf_range(BAND_Z_FAR, BAND_Z_NEAR)
		# Density falls with altitude (here, latitude) — reject upper trees so
		# the canopy thins to a ragged treeline instead of a hard edge.
		var alt: float = smoothstep(BAND_Z_FAR, -110.0, z)  # 1 low → 0 high
		if _rng.randf() > 0.15 + 0.85 * alt:
			continue
		var x: float = _rng.randf_range(-232.0, 232.0)
		var h: float = _terrain.get_height(x, z)
		if not _band_ok(x, z, h):
			continue
		var s: float = _rng.randf_range(0.85, 1.5) * (1.15 - 0.35 * (1.0 - alt))
		var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h - 0.1, z))
		t = t.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
		t = t.scaled_local(Vector3(s, s * _rng.randf_range(0.9, 1.25), s))
		mm.set_instance_transform(placed, t)
		var col: Color = CONIFER_HI.lerp(CONIFER_LO, alt)
		col = col.lerp(col.lightened(0.15), _rng.randf() * 0.5)
		mm.set_instance_color(placed, col)
		placed += 1
	mm.instance_count = placed
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Treeline"
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(
		Vector3(-MeadowTerrain.SIZE * 0.5, -20.0, BAND_Z_FAR - 10.0),
		Vector3(MeadowTerrain.SIZE, 90.0, 160.0)
	)
	add_child(mmi)
	print("PeaksApproach: %d alpine conifers." % placed)


## A rounded low-poly boulder: hexagonal bipyramid, squat and wide, jittered.
func _build_boulder_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Vector3 = Vector3(0.1, 0.6, 0.0)
	var bot: Vector3 = Vector3(0.0, -0.1, 0.0)
	var ring: Array[Vector3] = []
	for a in 6:
		var th: float = TAU * float(a) / 6.0
		var rr: float = 1.05 + _rng.randf_range(0.0, 0.3)
		ring.append(Vector3(cos(th) * rr, 0.15 + _rng.randf_range(0.0, 0.16), sin(th) * rr * 0.9))
	for a in 6:
		var r0: Vector3 = ring[a]
		var r1: Vector3 = ring[(a + 1) % 6]
		st.set_color(Color.WHITE); st.add_vertex(top)
		st.set_color(Color.WHITE); st.add_vertex(r0)
		st.set_color(Color.WHITE); st.add_vertex(r1)
		st.set_color(Color.WHITE); st.add_vertex(bot)
		st.set_color(Color.WHITE); st.add_vertex(r1)
		st.set_color(Color.WHITE); st.add_vertex(r0)
	st.generate_normals()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = GradientPeaks.MOUNTAIN_SHADER
	mat.set_shader_parameter("grain_amount", 0.14)
	mat.set_shader_parameter("striation_amount", 0.0)
	mat.set_shader_parameter("haze_max", 0.0)
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


func _scatter_boulders() -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _build_boulder_mesh()
	mm.instance_count = BOULDER_COUNT
	var placed: int = 0
	var tries: int = 0
	while placed < BOULDER_COUNT and tries < BOULDER_COUNT * 8:
		tries += 1
		var z: float = _rng.randf_range(BAND_Z_FAR, -35.0)
		var x: float = _rng.randf_range(-232.0, 232.0)
		var h: float = _terrain.get_height(x, z)
		if not _band_ok(x, z, h):
			continue
		# Sorting: random low, graded-large and aligned high.
		var sort: float = smoothstep(-60.0, BAND_Z_FAR, z)  # 0 low → 1 high
		var size: float = _rng.randf_range(1.1, 2.2) * (1.0 + sort * 1.6)
		if sort > 0.4:
			size = _rng.randf_range(2.0, 3.0) * (1.0 + sort * 0.7)
		var head: float = _rng.randf_range(0.0, PI) * (1.0 - sort) + deg_to_rad(22.0) * sort
		var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h + size * 0.05, z))
		t = t.rotated_local(Vector3.UP, head)
		t = t.scaled_local(Vector3(size, size, size))
		mm.set_instance_transform(placed, t)
		mm.set_instance_color(placed, BOULDER_COL.lerp(BOULDER_COL.darkened(0.12), sort))
		placed += 1
	mm.instance_count = placed
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "SortedBoulders"
	mmi.multimesh = mm
	add_child(mmi)
	print("PeaksApproach: %d sorted boulders." % placed)


## Descent's Rest — the switchback village. Terraced rows of houses climbing
## NW into the foothills, each with a dark peaked roof and a warm-lit window.
func _raise_descents_rest() -> void:
	var town: Node3D = Node3D.new()
	town.name = "DescentsRest"
	add_child(town)
	var wall_mat: StandardMaterial3D = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.62, 0.52, 0.4)
	wall_mat.roughness = 0.9
	var roof_mat: StandardMaterial3D = StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.32, 0.19, 0.16)
	roof_mat.roughness = 0.85
	var win_mat: StandardMaterial3D = StandardMaterial3D.new()
	win_mat.albedo_color = Color(0.1, 0.08, 0.06)
	win_mat.emission_enabled = true
	win_mat.emission = Color(1.0, 0.74, 0.42)
	win_mat.emission_energy_multiplier = 1.4
	var base: Vector2 = Vector2(-118.0, -206.0)
	var count: int = 0
	for row in 4:
		var shelf_x: float = base.x - float(row) * 13.0
		var shelf_z: float = base.z - float(row) * 8.0
		for hi in 3 + (row % 2):
			var hx: float = shelf_x + float(hi) * 9.0 + _rng.randf_range(-1.5, 1.5)
			var hz: float = shelf_z + _rng.randf_range(-2.0, 2.0)
			var gh: float = _terrain.get_height(hx, hz)
			_build_house(town, Vector3(hx, gh, hz), wall_mat, roof_mat, win_mat)
			count += 1
	print("PeaksApproach: Descent's Rest, %d houses." % count)


func _build_house(
	parent: Node3D, pos: Vector3, wall_mat: Material, roof_mat: Material, win_mat: Material
) -> void:
	var house: Node3D = Node3D.new()
	house.position = pos
	house.rotation.y = _rng.randf_range(-0.3, 0.3)
	var wh: float = _rng.randf_range(3.4, 4.4)
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(4.2, wh, 4.0)
	body.mesh = box
	body.material_override = wall_mat
	body.position.y = wh * 0.5
	house.add_child(body)
	# Peaked roof: a wide, short prism sitting on the walls.
	var roof: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(4.9, 2.2, 4.6)
	roof.mesh = prism
	roof.material_override = roof_mat
	roof.position.y = wh + 1.1
	house.add_child(roof)
	# Warm window on the south face.
	var win: MeshInstance3D = MeshInstance3D.new()
	var wq: BoxMesh = BoxMesh.new()
	wq.size = Vector3(1.4, 1.1, 0.1)
	win.mesh = wq
	win.material_override = win_mat
	win.position = Vector3(0.0, wh * 0.45, 2.0)
	house.add_child(win)
	parent.add_child(house)

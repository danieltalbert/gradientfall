class_name MeadowFlora
extends Node3D
## Datasedge Meadows vegetation — Phase 1 milestone 3.
##
## Everything scattered deterministically (fixed seed) on the terrain the
## sibling MeadowTerrain generated: ~34k wind-swayed grass blades and dry-gold
## accents (MultiMesh + grass_wind shader), daisies, pebbles, and low-poly
## tree copses with trunk collision. Instance colors carry all variation;
## zero textures.
##
## The iris flats to the west used to be scattered here as scenery. Milestone
## 13 made them collectible, so they moved to the IrisField child this node
## builds — same seed, same clusters, same colors, same look, but every bloom
## now carries a real Iris specimen record. Flora still owns the vegetation;
## it just delegates the one part of it that is a game system.

const SCATTER_SEED: int = 20260717
const FIELD_COUNT: int = 1400000  # independently positioned fine blades
const FIELD_BLADES_PER_TUFT: int = 1
const FIELD_TILE: float = 190.0
const GRASS_COUNT: int = 180000   # uniformly scattered horizon accents
const ACCENT_BLADES_PER_TUFT: int = 2
const GRASS_INSTANCES_PER_CLUMP: int = 9
const DAISY_COUNT: int = 1200
const PEBBLE_COUNT: int = 750
const EDGE_MARGIN: float = 12.0

@onready var _terrain: MeadowTerrain = $"../Terrain"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The collectible iris flats. Built here rather than added to main.tscn so
## the scene file stays untouched.
var iris_field: IrisField


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	_rng.seed = SCATTER_SEED
	_build_fine_field()
	_scatter_grass()
	_scatter_daisies()
	_scatter_pebbles()
	_plant_copses()
	# Same seed the rest of the flora uses, so the flats land exactly where
	# they always have.
	iris_field = IrisField.build(self, _terrain, SCATTER_SEED)
	print("MeadowFlora: %d fine blades + %d accent blades, %d daisies, %d pebbles in %d ms." % [
		FIELD_COUNT * FIELD_BLADES_PER_TUFT,
		GRASS_COUNT * ACCENT_BLADES_PER_TUFT,
		DAISY_COUNT, PEBBLE_COUNT,
		Time.get_ticks_msec() - start_ms,
	])


## The infinite fine-grass carpet: one MultiMesh of thin 3-segment blades on
## identity transforms scattered in a flat tile; the grass_field shader wraps
## them around the camera, plants them on the heightmap, and animates gusts.
## Buffer is written directly (12 floats/instance) — 400k via set_instance_*
## would take seconds; this takes tens of milliseconds.
func _build_fine_field() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# One narrow curved leaf per transform eliminates repeated radial tuft silhouettes.
	_append_grass_ribbon(st, 0.0, 0.22, 0.0125, 0.09, 0.0, Vector3.ZERO, 3)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/grass_field.gdshader")
	mat.set_shader_parameter("height_map", _terrain.height_texture)
	mat.set_shader_parameter("terrain_size", MeadowTerrain.SIZE)
	mat.set_shader_parameter("water_level", _terrain.water_level)
	mat.set_shader_parameter("tile", FIELD_TILE)
	mat.set_shader_parameter("fade_start", FIELD_TILE * 0.41)
	mat.set_shader_parameter("fade_end", FIELD_TILE * 0.49)
	st.set_material(mat)
	var mesh: ArrayMesh = st.commit()

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = FIELD_COUNT
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(FIELD_COUNT * 12)
	var half_tile: float = FIELD_TILE * 0.5
	var idx: int = 0
	for i in FIELD_COUNT:
		buf[idx] = 1.0
		buf[idx + 3] = _rng.randf_range(-half_tile, half_tile)
		buf[idx + 5] = 1.0
		buf[idx + 10] = 1.0
		buf[idx + 11] = _rng.randf_range(-half_tile, half_tile)
		idx += 12
	mm.buffer = buf

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "FineField"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Blades relocate to wherever the camera is — cull against the whole map.
	mmi.custom_aabb = AABB(
		Vector3(-MeadowTerrain.SIZE * 0.5, -60.0, -MeadowTerrain.SIZE * 0.5),
		Vector3(MeadowTerrain.SIZE, 140.0, MeadowTerrain.SIZE)
	)
	add_child(mmi)


func _ground_ok(x: float, z: float, h: float) -> bool:
	if absf(x) > MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN:
		return false
	if absf(z) > MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN:
		return false
	if h < _terrain.water_level + 0.35:  # pond bed and waterline stay bare
		return false
	return true


func _scatter_grass() -> void:
	var mesh: ArrayMesh = _build_blade_mesh()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = GRASS_COUNT
	var half: float = MeadowTerrain.SIZE * 0.5 - EDGE_MARGIN
	# BOTW-style patchiness: blades grow in clumps, and each clump owns a
	# coherent hue so the field reads as drifts of color, not confetti.
	var green_a: Color = Color(0.22, 0.39, 0.095)
	var green_b: Color = Color(0.32, 0.48, 0.13)
	var gold: Color = Color(0.47, 0.38, 0.10)
	var hue_noise: FastNoiseLite = FastNoiseLite.new()
	hue_noise.seed = SCATTER_SEED + 41
	hue_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hue_noise.frequency = 0.014
	hue_noise.fractal_octaves = 3
	var dry_noise: FastNoiseLite = FastNoiseLite.new()
	dry_noise.seed = SCATTER_SEED + 83
	dry_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dry_noise.frequency = 0.008
	dry_noise.fractal_octaves = 2
	var i: int = 0
	while i < GRASS_COUNT:
		var cx: float = _rng.randf_range(-half, half)
		var cz: float = _rng.randf_range(-half, half)
		var hue: float = hue_noise.get_noise_2d(cx, cz) * 0.5 + 0.5
		var dry: float = smoothstep(0.55, 0.82, dry_noise.get_noise_2d(cx, cz) * 0.5 + 0.5)
		var clump_col: Color = green_a.lerp(green_b, hue)
		clump_col = clump_col.lerp(gold, dry * 0.58)
		var spread: float = _rng.randf_range(1.8, 3.4)
		var clump_size: int = mini(GRASS_INSTANCES_PER_CLUMP, GRASS_COUNT - i)
		for j in clump_size:
			var x: float = cx + _rng.randfn(0.0, spread)
			var z: float = cz + _rng.randfn(0.0, spread)
			var h: float = _terrain.get_height(x, z)
			if not _ground_ok(x, z, h):
				h = -10000.0  # park unusable blades far underground
			var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h, z))
			t = t.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
			var s: float = _rng.randf_range(0.78, 1.18)
			t = t.scaled_local(Vector3(s, s * _rng.randf_range(0.84, 1.12), s))
			mm.set_instance_transform(i, t)
			var col: Color = clump_col.lerp(green_b, _rng.randf_range(0.0, 0.12))
			mm.set_instance_color(i, col)
			i += 1

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Adds one curved ribbon to a shared tuft mesh. Four or five articulated
## segments produce a soft arc and a broad middle before tapering to a true
## leaf tip; the small upward normal bias keeps both faces readable at dusk.
func _append_grass_ribbon(
	st: SurfaceTool,
	yaw: float,
	height: float,
	half_width: float,
	lean: float,
	phase: float,
	base_offset: Vector3,
	segments: int
) -> void:
	var forward: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw))
	var side: Vector3 = Vector3(-sin(yaw), 0.0, cos(yaw))
	var normal: Vector3 = (-forward * 0.48 + Vector3.UP * 0.88).normalized()
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	for segment in segments:
		var t0: float = float(segment) / float(segments)
		var t1: float = float(segment + 1) / float(segments)
		var bend0: float = t0 * t0
		var bend1: float = t1 * t1
		var curl: float = sin(phase * TAU) * 0.025
		var center0: Vector3 = base_offset + Vector3.UP * (height * t0)
		center0 += forward * (lean * bend0) + side * (curl * bend0 * t0)
		var center1: Vector3 = base_offset + Vector3.UP * (height * t1)
		center1 += forward * (lean * bend1) + side * (curl * bend1 * t1)
		var width0: float = half_width * pow(maxf(0.0, 1.0 - t0), 0.72)
		var width1: float = half_width * pow(maxf(0.0, 1.0 - t1), 0.72)
		width0 *= 0.84 + 0.34 * sin(PI * t0)
		width1 *= 0.84 + 0.34 * sin(PI * t1)
		var points: Array[Vector3] = [
			center0 - side * width0,
			center0 + side * width0,
			center1 + side * width1,
			center1 - side * width1,
		]
		var uvs: Array[Vector2] = [
			Vector2(0.0, t0), Vector2(1.0, t0),
			Vector2(1.0, t1), Vector2(0.0, t1),
		]
		for point_index in order:
			st.set_uv(uvs[point_index])
			st.set_uv2(Vector2(phase, height))
			st.set_normal(normal)
			st.add_vertex(points[point_index])


## A lush accent tuft: five independently phased curved ribbons. The field
## shader supplies the dense sward; these taller silhouettes break it into
## readable wind-swept clumps without the old crossed-triangle spikes.
func _build_blade_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade_index in ACCENT_BLADES_PER_TUFT:
		var phase: float = float(blade_index) / float(ACCENT_BLADES_PER_TUFT)
		var yaw: float = float(blade_index) * 2.39996 + 0.23
		var radius: float = 0.035 + 0.018 * float(blade_index % 3)
		var offset: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw)) * radius
		_append_grass_ribbon(
			st,
			yaw,
			0.34 + 0.055 * float(blade_index),
			0.015 + 0.003 * float(blade_index % 2),
			0.12 + 0.035 * float(blade_index),
			phase,
			offset,
			3
		)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/grass_wind.gdshader")
	st.set_material(mat)
	return st.commit()


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

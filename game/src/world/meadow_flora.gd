class_name MeadowFlora
extends Node3D
## Datasedge Meadows vegetation — Phase 1 milestone 3.
##
## Everything scattered deterministically (fixed seed) on the terrain the
## sibling MeadowTerrain generated: ~34k wind-swayed grass blades and dry-gold
## accents (MultiMesh + grass_wind shader), iris flats to the west (the
## region's canon flora — collectible system arrives with the compendium
## milestone; today they are scenery), and low-poly tree copses with trunk
## collision. Instance colors carry all variation; zero textures.

const SCATTER_SEED: int = 20260717
const GRASS_COUNT: int = 34000
const IRIS_COUNT: int = 700
const EDGE_MARGIN: float = 12.0

@onready var _terrain: MeadowTerrain = $"../Terrain"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	_rng.seed = SCATTER_SEED
	_scatter_grass()
	_scatter_irises()
	_plant_copses()
	print("MeadowFlora: %d grass, %d irises, trees planted in %d ms." % [
		GRASS_COUNT, IRIS_COUNT, Time.get_ticks_msec() - start_ms,
	])


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
	var green_a: Color = Color(0.42, 0.62, 0.22)
	var green_b: Color = Color(0.52, 0.66, 0.23)
	var gold: Color = Color(0.74, 0.64, 0.26)
	for i in GRASS_COUNT:
		var x: float = _rng.randf_range(-half, half)
		var z: float = _rng.randf_range(-half, half)
		var h: float = _terrain.get_height(x, z)
		if not _ground_ok(x, z, h):
			h = _terrain.get_height(-x, -z)  # cheap retry mirrors the point
			x = -x
			z = -z
			if not _ground_ok(x, z, h):
				h = -10000.0  # park unusable blades far underground
		var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h, z))
		t = t.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
		var s: float = _rng.randf_range(0.7, 1.35)
		t = t.scaled_local(Vector3(s, s * _rng.randf_range(0.85, 1.3), s))
		mm.set_instance_transform(i, t)
		var col: Color = green_a.lerp(green_b, _rng.randf())
		if _rng.randf() < 0.18:
			col = col.lerp(gold, 0.7)
		mm.set_instance_color(i, col)

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A grass tuft: three crossed solid triangles, tips offset for a bent look.
func _build_blade_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var yaw: float = TAU * float(k) / 3.0
		var basis: Basis = Basis(Vector3.UP, yaw)
		var w: float = 0.05
		var height: float = 0.55
		var lean: Vector3 = basis * Vector3(0.10, 0.0, 0.0)
		var p0: Vector3 = basis * Vector3(-w, 0.0, 0.0)
		var p1: Vector3 = basis * Vector3(w, 0.0, 0.0)
		var p2: Vector3 = basis * Vector3(0.0, height, 0.0) + lean
		st.set_uv(Vector2(0.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p1)
		st.set_uv(Vector2(0.5, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(p2)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/grass_wind.gdshader")
	st.set_material(mat)
	return st.commit()


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
	st.set_material(mat)
	return st.commit()


func _plant_copses() -> void:
	var variants: Array[ArrayMesh] = [
		_build_tree_mesh(2.6, 1.9, Color(0.29, 0.46, 0.22)),
		_build_tree_mesh(3.4, 2.3, Color(0.25, 0.42, 0.19)),
		_build_tree_mesh(2.1, 1.5, Color(0.36, 0.5, 0.2)),
	]
	var trunk_shape: CylinderShape3D = CylinderShape3D.new()
	trunk_shape.radius = 0.35
	trunk_shape.height = 3.0
	var copses: Array[Vector2] = [
		Vector2(-160.0, -140.0), Vector2(60.0, -120.0), Vector2(160.0, -60.0),
		Vector2(170.0, 90.0), Vector2(60.0, 160.0), Vector2(-60.0, 170.0),
		Vector2(-170.0, 130.0), Vector2(-40.0, -170.0), Vector2(150.0, 170.0),
		Vector2(-190.0, 40.0), Vector2(120.0, 40.0), Vector2(30.0, -60.0),
	]
	var trees: Node3D = Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	var planted: int = 0
	for c in copses:
		var count: int = _rng.randi_range(5, 9)
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
			col.position.y = 1.5
			tree.add_child(mi)
			tree.add_child(col)
			tree.position = Vector3(x, h - 0.15, z)
			tree.rotation.y = _rng.randf_range(0.0, TAU)
			var s: float = _rng.randf_range(0.85, 1.4)
			tree.scale = Vector3(s, s, s)
			trees.add_child(tree)
			planted += 1
	print("MeadowFlora: %d trees across %d copses." % [planted, copses.size()])


## Low-poly tree: tapered trunk + two stacked faceted foliage blobs.
func _build_tree_mesh(trunk_h: float, crown_r: float, crown_col: Color) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.34
	trunk.height = trunk_h
	trunk.radial_segments = 6
	trunk.rings = 1
	var crown_a: SphereMesh = SphereMesh.new()
	crown_a.radius = crown_r
	crown_a.height = crown_r * 1.5
	crown_a.radial_segments = 7
	crown_a.rings = 4
	var crown_b: SphereMesh = SphereMesh.new()
	crown_b.radius = crown_r * 0.62
	crown_b.height = crown_r
	crown_b.radial_segments = 6
	crown_b.rings = 3

	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.4, 0.3, 0.22))
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, trunk_h * 0.5, 0.0)))
	var mesh: ArrayMesh = st.commit()

	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(crown_col)
	st.append_from(crown_a, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, trunk_h + crown_r * 0.55, 0.0)))
	st.append_from(crown_b, 0, Transform3D(
		Basis.IDENTITY, Vector3(crown_r * 0.35, trunk_h + crown_r * 1.25, crown_r * 0.2)
	))
	mesh = st.commit(mesh)

	var bark: StandardMaterial3D = StandardMaterial3D.new()
	bark.albedo_color = Color(0.4, 0.3, 0.22)
	bark.roughness = 1.0
	var leaf: StandardMaterial3D = StandardMaterial3D.new()
	leaf.albedo_color = crown_col
	leaf.roughness = 1.0
	mesh.surface_set_material(0, bark)
	mesh.surface_set_material(1, leaf)
	return mesh

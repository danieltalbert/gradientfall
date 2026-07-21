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
const FIELD_COUNT: int = 400000  # fine blades in the camera-following tile
const FIELD_TILE: float = 130.0
const GRASS_COUNT: int = 36000   # taller accent tufts, whole-map, mid-distance
const BLADES_PER_CLUMP: int = 9
const IRIS_COUNT: int = 700
const DAISY_COUNT: int = 1200
const PEBBLE_COUNT: int = 750
const EDGE_MARGIN: float = 12.0

@onready var _terrain: MeadowTerrain = $"../Terrain"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	_rng.seed = SCATTER_SEED
	_build_fine_field()
	_scatter_grass()
	_scatter_irises()
	_scatter_daisies()
	_scatter_pebbles()
	_plant_copses()
	print("MeadowFlora: %d field blades + %d tufts, %d irises, %d daisies, %d pebbles in %d ms." % [
		FIELD_COUNT, GRASS_COUNT, IRIS_COUNT, DAISY_COUNT, PEBBLE_COUNT,
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
	var w: float = 0.016
	var h1: float = 0.24
	var h2: float = 0.45
	var lean: float = 0.05
	var p: Array[Vector3] = [
		Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0),
		Vector3(-w * 0.55, h1, lean * 0.4), Vector3(w * 0.55, h1, lean * 0.4),
		Vector3(0.0, h2, lean),
	]
	var uvy: Array[float] = [0.0, 0.0, h1 / h2, h1 / h2, 1.0]
	var order: Array[int] = [0, 1, 2, 1, 3, 2, 2, 3, 4]
	for i in order:
		st.set_uv(Vector2(0.5, uvy[i]))
		st.set_normal(Vector3.UP)
		st.add_vertex(p[i])
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/grass_field.gdshader")
	mat.set_shader_parameter("height_map", _terrain.height_texture)
	mat.set_shader_parameter("terrain_size", MeadowTerrain.SIZE)
	mat.set_shader_parameter("water_level", _terrain.water_level)
	mat.set_shader_parameter("tile", FIELD_TILE)
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
	var green_a: Color = Color(0.42, 0.62, 0.22)
	var green_b: Color = Color(0.52, 0.66, 0.23)
	var gold: Color = Color(0.74, 0.64, 0.26)
	var i: int = 0
	while i < GRASS_COUNT:
		var cx: float = _rng.randf_range(-half, half)
		var cz: float = _rng.randf_range(-half, half)
		var clump_col: Color = green_a.lerp(green_b, _rng.randf())
		if _rng.randf() < 0.16:
			clump_col = clump_col.lerp(gold, 0.65)
		var clump_size: int = mini(BLADES_PER_CLUMP, GRASS_COUNT - i)
		for j in clump_size:
			var x: float = cx + _rng.randfn(0.0, 0.7)
			var z: float = cz + _rng.randfn(0.0, 0.7)
			var h: float = _terrain.get_height(x, z)
			if not _ground_ok(x, z, h):
				h = -10000.0  # park unusable blades far underground
			var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, h, z))
			t = t.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
			var s: float = _rng.randf_range(0.75, 1.4)
			t = t.scaled_local(Vector3(s, s * _rng.randf_range(0.85, 1.35), s))
			mm.set_instance_transform(i, t)
			var col: Color = clump_col.lerp(green_b, _rng.randf() * 0.25)
			mm.set_instance_color(i, col)
			i += 1

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
		var w: float = 0.065
		var height: float = 0.6
		var lean: Vector3 = basis * Vector3(0.12, 0.0, 0.0)
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
		_build_tree_mesh(2.6, 1.9, Color(0.38, 0.55, 0.26)),
		_build_tree_mesh(3.4, 2.3, Color(0.33, 0.5, 0.23)),
		_build_tree_mesh(2.1, 1.5, Color(0.45, 0.58, 0.24)),
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


## Realistic-fidelity tree: tapered trunk + 4-5 angled boughs (all wearing
## the procedural bark shader's grooves), crowned with ~850 individual leaf
## quads distributed through ellipsoid clouds at the crown and bough ends —
## every leaf flutters independently in the leaf shader's wind.
func _build_tree_mesh(trunk_h: float, crown_r: float, crown_col: Color) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()

	# --- Surface 0: wood ---
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.34
	trunk.height = trunk_h
	trunk.radial_segments = 12
	trunk.rings = 3
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, trunk_h * 0.5, 0.0)))

	var clusters: Array = [
		{"c": Vector3(0.0, trunk_h + crown_r * 0.45, 0.0), "r": crown_r},
	]
	var bough_count: int = _rng.randi_range(4, 5)
	for b in bough_count:
		var yaw: float = TAU * float(b) / float(bough_count) + _rng.randf_range(-0.4, 0.4)
		var pitch: float = deg_to_rad(_rng.randf_range(30.0, 55.0))
		var attach_h: float = trunk_h * _rng.randf_range(0.55, 0.92)
		var blen: float = _rng.randf_range(1.2, 2.0) * (crown_r / 2.0)
		var dir: Vector3 = Vector3(
			cos(yaw) * sin(pitch), cos(pitch), sin(yaw) * sin(pitch)
		).normalized()
		var bough: CylinderMesh = CylinderMesh.new()
		bough.top_radius = 0.045
		bough.bottom_radius = 0.11
		bough.height = blen
		bough.radial_segments = 7
		bough.rings = 1
		var up: Vector3 = Vector3.UP
		var axis: Vector3 = up.cross(dir).normalized()
		var basis: Basis = Basis(axis, up.angle_to(dir)) if axis.length_squared() > 0.001 else Basis.IDENTITY
		var attach: Vector3 = Vector3(0.0, attach_h, 0.0)
		st.append_from(bough, 0, Transform3D(basis, attach + dir * blen * 0.5))
		clusters.append({"c": attach + dir * blen, "r": crown_r * _rng.randf_range(0.4, 0.55)})
	var mesh: ArrayMesh = st.commit()

	# --- Surface 1: ~850 individual leaves across the cluster clouds ---
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total_weight: float = 0.0
	for cl in clusters:
		total_weight += pow(cl["r"], 3.0)
	for i in 1000:
		var pick: float = _rng.randf() * total_weight
		var cluster: Dictionary = clusters[0]
		for cl in clusters:
			pick -= pow(cl["r"], 3.0)
			if pick <= 0.0:
				cluster = cl
				break
		var r: float = cluster["r"] * pow(_rng.randf(), 0.33)
		var theta: float = _rng.randf_range(0.0, TAU)
		var phi: float = acos(_rng.randf_range(-1.0, 1.0))
		var pos: Vector3 = cluster["c"] + Vector3(
			r * sin(phi) * cos(theta), r * cos(phi) * 0.75, r * sin(phi) * sin(theta)
		)
		var s: float = _rng.randf_range(0.26, 0.4)
		var lyaw: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
		var tilt: Basis = Basis(Vector3.RIGHT, _rng.randf_range(-1.1, 1.1))
		var lb: Basis = lyaw * tilt
		var bx: Vector3 = lb.x * s * 0.5
		var by: Vector3 = lb.y * s
		var ph: float = _rng.randf()
		var corners: Array[Vector3] = [pos - bx, pos + bx, pos + bx + by, pos - bx + by]
		var uvs: Array[Vector2] = [
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)
		]
		var quad_order: Array[int] = [0, 1, 2, 0, 2, 3]
		for q in quad_order:
			st.set_uv(uvs[q])
			st.set_uv2(Vector2(ph, 0.0))
			st.set_normal((lb.z).normalized())
			st.add_vertex(corners[q])
	mesh = st.commit(mesh)

	var bark: ShaderMaterial = ShaderMaterial.new()
	bark.shader = load("res://assets/shaders/bark.gdshader")
	var leaf: ShaderMaterial = ShaderMaterial.new()
	leaf.shader = load("res://assets/shaders/leaf_wind.gdshader")
	leaf.set_shader_parameter("leaf_a", crown_col.darkened(0.25))
	leaf.set_shader_parameter("leaf_b", crown_col.lightened(0.12))
	mesh.surface_set_material(0, bark)
	mesh.surface_set_material(1, leaf)
	return mesh

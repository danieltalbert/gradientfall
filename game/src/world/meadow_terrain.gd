class_name MeadowTerrain
extends StaticBody3D
## Datasedge Meadows terrain — Phase 1 milestone 3.
##
## Fully procedural heightmap terrain, generated deterministically at boot:
## rolling hills (fbm noise) + macro undulation, a flattened town site for
## Bootstrap, the millpond carved to the east, foothills rising toward the
## Gradient Peaks vista (north), a gentle fall toward the sea (west).
## Visuals are an ArrayMesh with all color variation baked into vertex
## colors (grass tones, dry patches, slope rock, pond sand); collision is a
## trimesh built from the same mesh so physics always matches what you see.

const WORLD_SEED: int = 20260716
const SIZE: float = 480.0            # meters, square, centered on origin
const STEP: float = 2.0              # meters between mesh vertices

const TOWN_CENTER: Vector2 = Vector2(0.0, 30.0)
const TOWN_FLAT_INNER: float = 38.0
const TOWN_FLAT_OUTER: float = 75.0
const POND_CENTER: Vector2 = Vector2(95.0, 10.0)
const POND_RADIUS: float = 24.0
const POND_DEPTH: float = 3.0
const SPAWN_POINT: Vector2 = Vector2(-58.0, -62.0)

var water_level: float = 0.0
var town_height: float = 0.0
## R = terrain height, G = surface normal Y — sampled by the grass-field
## shader so half a million blades can find the ground without CPU work.
var height_texture: ImageTexture

var _rolling: FastNoiseLite
var _macro: FastNoiseLite
var _detail: FastNoiseLite
var _tint: FastNoiseLite


func _init() -> void:
	_rolling = FastNoiseLite.new()
	_rolling.seed = WORLD_SEED
	_rolling.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rolling.frequency = 0.008
	_rolling.fractal_octaves = 4
	_macro = FastNoiseLite.new()
	_macro.seed = WORLD_SEED + 1
	_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_macro.frequency = 0.0016
	_macro.fractal_octaves = 2
	_detail = FastNoiseLite.new()
	_detail.seed = WORLD_SEED + 2
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.06
	_detail.fractal_octaves = 2
	_tint = FastNoiseLite.new()
	_tint.seed = WORLD_SEED + 3
	_tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tint.frequency = 0.02
	_tint.fractal_octaves = 3
	town_height = _height_raw(TOWN_CENTER.x, TOWN_CENTER.y)
	water_level = _height_raw(POND_CENTER.x, POND_CENTER.y) - POND_DEPTH + 1.7


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	_build_mesh_and_collision()
	_add_pond_water()
	print("MeadowTerrain: %.0fx%.0f m generated in %d ms (water y=%.2f)." % [
		SIZE, SIZE, Time.get_ticks_msec() - start_ms, water_level,
	])


## Final ground height at any point — the one function everything trusts
## (mesh, collision, flora scatter, player spawn all sample this).
func get_height(x: float, z: float) -> float:
	var h: float = _height_raw(x, z)
	# Bootstrap's town site: blend flat.
	var town_dist: float = Vector2(x, z).distance_to(TOWN_CENTER)
	h = lerpf(town_height, h, smoothstep(TOWN_FLAT_INNER, TOWN_FLAT_OUTER, town_dist))
	# Millpond: carve a soft bowl.
	var pond_dist: float = Vector2(x, z).distance_to(POND_CENTER)
	h -= POND_DEPTH * (1.0 - smoothstep(POND_RADIUS * 0.35, POND_RADIUS, pond_dist))
	return h


## True over the millpond's deep water. Bit (who fears it) and a future
## swim system ask the terrain rather than hard-coding pond geometry.
func is_deep_water(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(POND_CENTER) < POND_RADIUS * 0.9


func get_normal(x: float, z: float) -> Vector3:
	var eps: float = 1.5
	var dx: float = get_height(x + eps, z) - get_height(x - eps, z)
	var dz: float = get_height(x, z + eps) - get_height(x, z - eps)
	return Vector3(-dx, 2.0 * eps, -dz).normalized()


func _height_raw(x: float, z: float) -> float:
	var h: float = _rolling.get_noise_2d(x, z) * 6.5
	h += _macro.get_noise_2d(x, z) * 11.0
	h += _detail.get_noise_2d(x, z) * 0.45
	# Foothills climbing toward the Gradient Peaks vista (north = -z).
	h += 22.0 * pow(smoothstep(110.0, 240.0, -z), 1.6)
	# Long fall toward the Convolution Coast vista (west = -x).
	h -= 9.0 * smoothstep(140.0, 240.0, -x)
	return h


func _vertex_color(x: float, z: float, h: float, normal: Vector3) -> Color:
	# Grassland ground sits UNDER a dense blade carpet now — it must read as
	# shadowed under-canopy soil, not bright turf, or gaps between blades
	# flash pale and the grass looks pasted on. Rock/sand stay lighter.
	var meadow_light: Color = Color(0.20, 0.30, 0.10)
	var meadow_deep: Color = Color(0.11, 0.19, 0.06)
	var dry_gold: Color = Color(0.38, 0.31, 0.13)
	var rock: Color = Color(0.42, 0.41, 0.34)
	var sand: Color = Color(0.72, 0.62, 0.38)

	var t: float = clampf(_tint.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var col: Color = meadow_deep.lerp(meadow_light, t)
	# Sun-dried golden patches (its own noise band, meadow character).
	var dry: float = smoothstep(0.55, 0.8, _tint.get_noise_2d(x + 900.0, z - 900.0) * 0.5 + 0.5)
	col = col.lerp(dry_gold, dry * 0.38)
	# Steep ground reads as worn rock.
	col = col.lerp(rock, smoothstep(0.82, 0.6, normal.y))
	# Pond bed and rim read as sand.
	var pond_dist: float = Vector2(x, z).distance_to(POND_CENTER)
	col = col.lerp(sand, 1.0 - smoothstep(POND_RADIUS * 0.85, POND_RADIUS * 1.25, pond_dist))
	# Bake soft sun-side variation so the ground never reads flat.
	col = col * (0.94 + 0.06 * t)
	return col


func _build_mesh_and_collision() -> void:
	var verts_per_side: int = int(SIZE / STEP) + 1
	var half: float = SIZE * 0.5
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	positions.resize(verts_per_side * verts_per_side)
	normals.resize(verts_per_side * verts_per_side)
	colors.resize(verts_per_side * verts_per_side)

	# Pass 1: heights once. Pass 2: normals from grid neighbors (no extra
	# noise sampling — this is the difference between a 1s and a 5s boot).
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(verts_per_side * verts_per_side)
	for iz in verts_per_side:
		for ix in verts_per_side:
			heights[iz * verts_per_side + ix] = get_height(-half + ix * STEP, -half + iz * STEP)

	var tex_data: PackedFloat32Array = PackedFloat32Array()
	tex_data.resize(verts_per_side * verts_per_side * 2)
	for iz in verts_per_side:
		for ix in verts_per_side:
			var x: float = -half + ix * STEP
			var z: float = -half + iz * STEP
			var idx: int = iz * verts_per_side + ix
			var h: float = heights[idx]
			var hl: float = heights[iz * verts_per_side + maxi(ix - 1, 0)]
			var hr: float = heights[iz * verts_per_side + mini(ix + 1, verts_per_side - 1)]
			var hu: float = heights[maxi(iz - 1, 0) * verts_per_side + ix]
			var hd: float = heights[mini(iz + 1, verts_per_side - 1) * verts_per_side + ix]
			var n: Vector3 = Vector3(hl - hr, 2.0 * STEP, hu - hd).normalized()
			positions[idx] = Vector3(x, h, z)
			normals[idx] = n
			colors[idx] = _vertex_color(x, z, h, n)
			tex_data[idx * 2] = h
			tex_data[idx * 2 + 1] = n.y

	var img: Image = Image.create_from_data(
		verts_per_side, verts_per_side, false, Image.FORMAT_RGF, tex_data.to_byte_array()
	)
	height_texture = ImageTexture.create_from_image(img)

	for iz in verts_per_side - 1:
		for ix in verts_per_side - 1:
			var a: int = iz * verts_per_side + ix
			var b: int = a + 1
			var c: int = a + verts_per_side
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/toon_soft.gdshader")
	# Ground rim is subtle — hills shouldn't glow, but a faint sky-lit edge on
	# ridgelines sells the painterly look.
	mat.set_shader_parameter("albedo_boost", 1.04)
	mat.set_shader_parameter("rim_amount", 0.08)
	mat.set_shader_parameter("rim_width", 0.82)
	mat.set_shader_parameter("fill_amount", 0.16)
	# Shadowed ground under the blade carpet must stay deep green — a pale
	# fill reads as gray litter through the sward.
	mat.set_shader_parameter("shadow_fill", Color(0.22, 0.30, 0.18))
	mat.set_shader_parameter("noise_amount", 0.08)
	mat.set_shader_parameter("noise_scale", 0.3)
	mesh.surface_set_material(0, mat)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "TerrainCollision"
	col.shape = mesh.create_trimesh_shape()
	add_child(col)


func _add_pond_water() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(POND_RADIUS * 2.6, POND_RADIUS * 2.6)
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	plane.material = mat
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "PondWater"
	water.mesh = plane
	water.position = Vector3(POND_CENTER.x, water_level, POND_CENTER.y)
	add_child(water)

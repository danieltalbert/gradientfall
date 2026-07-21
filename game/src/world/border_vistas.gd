class_name BorderVistas
extends Node3D
## Procedural horizon architecture for Datasedge Meadows.
##
## The four neighboring regions must read as places rather than backdrop
## cards. The north is a four-rank mountain range with real radial topology,
## branching ridge fields, gullies, strata, broken snow, a connected foothill
## apron, and a dense tree belt for scale. East is a layered 3D forest canopy,
## west is animated water, and south is a deep rank of rolling downs.

const VISTA_SEED: int = 20260718
const MOUNTAIN_GRID_X: int = 44
const MOUNTAIN_GRID_Z: int = 36
const HORIZON_TREE_VARIANTS: int = 4
const MOUNTAIN_SHADER_PATH: String = "res://assets/shaders/mountain_vista.gdshader"
const TOON_SOFT_SHADER_PATH: String = "res://assets/shaders/toon_soft.gdshader"
const CLIMBABLE_PEAKS := preload("res://src/world/gradient_peaks.gd")

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _apron_noise: FastNoiseLite = FastNoiseLite.new()
var _terrain: MeadowTerrain
var _mountain_shader: Shader
var _horizon_tree_meshes: Array[ArrayMesh] = []


func _ready() -> void:
	_rng.seed = VISTA_SEED
	_apron_noise.seed = VISTA_SEED + 71
	_apron_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_apron_noise.frequency = 0.006
	_apron_noise.fractal_octaves = 4
	_terrain = get_node_or_null("../Terrain") as MeadowTerrain
	_mountain_shader = load(MOUNTAIN_SHADER_PATH) as Shader

	_raise_climbable_peaks()
	_raise_gradient_peaks()
	_grow_latent_forest_wall()
	_lay_convolution_sea()
	_roll_southern_downs()
	print("BorderVistas: climbable Gradient Peaks + distant snow giants, forest, coast, and downs ready.")


## The near mountains are no longer painted cards: this stands up the real,
## collidable Gradient Peaks massif — the one the player can climb, valley
## through, and that future POIs anchor onto — rising off the meadow's north
## seam. _raise_gradient_peaks then keeps only the two distant ranks, which sit
## above and behind it as the snow-giant backdrop.
func _raise_climbable_peaks() -> void:
	var peaks := CLIMBABLE_PEAKS.new()
	peaks.name = "ClimbablePeaks"
	add_child(peaks)
	peaks.setup(_terrain)


## Build the main landmark from hand-composed ranks rather than an evenly
## spaced row. Vector4 fields are x, z, base radius, height. The asymmetric
## rhythm produces recognizable saddles and landmark summits from the meadow.
func _raise_gradient_peaks() -> void:
	var peaks: Node3D = Node3D.new()
	peaks.name = "GradientPeaks"
	add_child(peaks)

	var far_layout: Array[Vector4] = [
		Vector4(-900.0, -1110.0, 290.0, 355.0),
		Vector4(-680.0, -1070.0, 275.0, 430.0),
		Vector4(-430.0, -1135.0, 315.0, 500.0),
		Vector4(-165.0, -1080.0, 280.0, 380.0),
		Vector4(80.0, -1125.0, 305.0, 465.0),
		Vector4(350.0, -1065.0, 265.0, 410.0),
		Vector4(590.0, -1140.0, 320.0, 515.0),
		Vector4(865.0, -1090.0, 280.0, 365.0),
	]
	var high_layout: Array[Vector4] = [
		Vector4(-820.0, -900.0, 245.0, 330.0),
		Vector4(-615.0, -850.0, 225.0, 390.0),
		Vector4(-390.0, -920.0, 270.0, 425.0),
		Vector4(-150.0, -835.0, 230.0, 350.0),
		Vector4(65.0, -905.0, 250.0, 445.0),
		Vector4(300.0, -840.0, 215.0, 335.0),
		Vector4(505.0, -900.0, 255.0, 415.0),
		Vector4(745.0, -855.0, 230.0, 350.0),
	]
	# The former MiddleCrags and FrontRamparts ranks lived inside the footprint
	# the climbable massif now fills, so only the two distant ranges remain —
	# they read as the snow giants rising above and behind the real mountains.
	_add_mountain_rank(peaks, "FarGhostRange", far_layout, 3, -42.0)
	_add_mountain_rank(peaks, "HighSnowRange", high_layout, 2, -24.0)


func _add_mountain_rank(
		parent: Node3D,
		rank_name: String,
		layout: Array[Vector4],
		rank: int,
		base_y: float
) -> void:
	var rank_node: Node3D = Node3D.new()
	rank_node.name = rank_name
	parent.add_child(rank_node)
	for i in layout.size():
		var spec: Vector4 = layout[i]
		var peak_seed: int = VISTA_SEED + rank * 1009 + i * 131
		var peak_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		peak_rng.seed = peak_seed
		var mountain: MeshInstance3D = MeshInstance3D.new()
		mountain.name = "Peak_%02d" % i
		mountain.mesh = _build_peak_mesh(spec.z, spec.w, peak_seed, rank)
		mountain.material_override = _make_mountain_material(
			rank, spec.w, i, peak_rng
		)
		mountain.position = Vector3(spec.x, base_y, spec.y)
		mountain.rotation.y = peak_rng.randf_range(-0.32, 0.32)
		mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rank_node.add_child(mountain)


## A terrain-like massif rather than a radial cone. Several offset, faceted
## summit kernels meet along saddles while explicit ridge segments fork into
## secondary spurs. Patchy quantized shelves and gully cuts break the faces.
func _build_peak_mesh(base_radius: float, height: float, seed: int, rank: int) -> ArrayMesh:
	var peak_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	peak_rng.seed = seed
	# Roughly one peak in four remains a sharp landmark. The rest use a wider,
	# lower compound crown so the range does not become a forest of needles.
	var sharp_landmark: bool = posmod(seed + rank * 3, 4) == 0
	var surface_noise: FastNoiseLite = FastNoiseLite.new()
	surface_noise.seed = seed + 17
	surface_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	surface_noise.frequency = 0.74
	surface_noise.fractal_octaves = 4
	var fracture_noise: FastNoiseLite = FastNoiseLite.new()
	fracture_noise.seed = seed + 53
	fracture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fracture_noise.frequency = 1.65
	fracture_noise.fractal_octaves = 3

	var depth_scale: float = peak_rng.randf_range(0.74, 0.98)
	var crest_angle: float = peak_rng.randf_range(-0.65, 0.65)
	var crest_axis: Vector2 = Vector2(cos(crest_angle), sin(crest_angle))
	var crest_perpendicular: Vector2 = Vector2(-crest_axis.y, crest_axis.x)
	var main_center: Vector2 = Vector2(
		peak_rng.randf_range(-0.16, 0.12), peak_rng.randf_range(-0.13, 0.09)
	)
	var shoulder_a: Vector2 = main_center + crest_axis * peak_rng.randf_range(0.24, 0.36)
	shoulder_a += crest_perpendicular * peak_rng.randf_range(-0.09, 0.09)
	var shoulder_b: Vector2 = main_center - crest_axis * peak_rng.randf_range(0.2, 0.32)
	shoulder_b += crest_perpendicular * peak_rng.randf_range(0.12, 0.23)
	var outcrop_center: Vector2 = main_center - crest_perpendicular * peak_rng.randf_range(0.24, 0.35)
	outcrop_center += crest_axis * peak_rng.randf_range(-0.08, 0.12)

	var ridge_segments: Array[Vector4] = []
	var ridge_widths: PackedFloat32Array = PackedFloat32Array()
	var ridge_strengths: PackedFloat32Array = PackedFloat32Array()
	var gully_segments: Array[Vector4] = []
	for ridge_index in 5:
		var angle: float = crest_angle + TAU * float(ridge_index) / 5.0
		angle += peak_rng.randf_range(-0.36, 0.36)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var lateral: Vector2 = Vector2(-direction.y, direction.x)
		var start: Vector2 = main_center + direction * peak_rng.randf_range(0.02, 0.07)
		var split: Vector2 = start + direction * peak_rng.randf_range(0.28, 0.42)
		split += lateral * peak_rng.randf_range(-0.1, 0.1)
		var end: Vector2 = split + direction.rotated(peak_rng.randf_range(-0.22, 0.22)) \
				* peak_rng.randf_range(0.4, 0.62)
		ridge_segments.append(Vector4(start.x, start.y, split.x, split.y))
		ridge_widths.append(peak_rng.randf_range(0.074, 0.104))
		ridge_strengths.append(peak_rng.randf_range(0.095, 0.14))
		ridge_segments.append(Vector4(split.x, split.y, end.x, end.y))
		ridge_widths.append(peak_rng.randf_range(0.057, 0.082))
		ridge_strengths.append(peak_rng.randf_range(0.058, 0.088))
		var branch_direction: Vector2 = direction.rotated(
			peak_rng.randf_range(0.42, 0.76) * (-1.0 if ridge_index % 2 == 0 else 1.0)
		)
		var branch_end: Vector2 = split + branch_direction * peak_rng.randf_range(0.27, 0.46)
		ridge_segments.append(Vector4(split.x, split.y, branch_end.x, branch_end.y))
		ridge_widths.append(peak_rng.randf_range(0.046, 0.068))
		ridge_strengths.append(peak_rng.randf_range(0.038, 0.062))

		var gully_angle: float = angle + peak_rng.randf_range(0.34, 0.58)
		var gully_direction: Vector2 = Vector2(cos(gully_angle), sin(gully_angle))
		var gully_start: Vector2 = main_center + gully_direction * 0.13
		var gully_end: Vector2 = gully_start + gully_direction * peak_rng.randf_range(0.58, 0.82)
		gully_end += Vector2(-gully_direction.y, gully_direction.x) * peak_rng.randf_range(-0.1, 0.1)
		gully_segments.append(Vector4(gully_start.x, gully_start.y, gully_end.x, gully_end.y))

	var vertex_width: int = MOUNTAIN_GRID_X + 1
	var vertex_depth: int = MOUNTAIN_GRID_Z + 1
	var vertex_count: int = vertex_width * vertex_depth
	var positions: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var footprint_weights: PackedFloat32Array = PackedFloat32Array()
	positions.resize(vertex_count)
	colors.resize(vertex_count)
	uvs.resize(vertex_count)
	footprint_weights.resize(vertex_count)

	var main_radii: Vector2 = Vector2(
		peak_rng.randf_range(0.63, 0.76), peak_rng.randf_range(0.68, 0.84)
	)
	var main_exponent: float = peak_rng.randf_range(1.04, 1.3)
	var summit_a_center: Vector2 = main_center + crest_perpendicular * peak_rng.randf_range(0.055, 0.1)
	summit_a_center += crest_axis * peak_rng.randf_range(-0.04, 0.06)
	var summit_b_center: Vector2 = main_center - crest_perpendicular * peak_rng.randf_range(0.07, 0.13)
	summit_b_center -= crest_axis * peak_rng.randf_range(0.01, 0.08)
	var summit_a_radii: Vector2
	var summit_b_radii: Vector2
	var summit_a_height: float
	var summit_b_height: float
	if sharp_landmark:
		summit_a_radii = main_radii * Vector2(
			peak_rng.randf_range(0.43, 0.52), peak_rng.randf_range(0.48, 0.59)
		)
		summit_b_radii = main_radii * Vector2(
			peak_rng.randf_range(0.35, 0.46), peak_rng.randf_range(0.42, 0.53)
		)
		summit_a_height = 1.0
		summit_b_height = peak_rng.randf_range(0.84, 0.94)
	else:
		summit_a_radii = main_radii * Vector2(
			peak_rng.randf_range(0.62, 0.76), peak_rng.randf_range(0.66, 0.82)
		)
		summit_b_radii = main_radii * Vector2(
			peak_rng.randf_range(0.54, 0.68), peak_rng.randf_range(0.6, 0.74)
		)
		summit_a_height = peak_rng.randf_range(0.94, 0.98)
		summit_b_height = peak_rng.randf_range(0.82, 0.9)
	var shoulder_a_height: float = peak_rng.randf_range(0.62, 0.74) + (0.05 if not sharp_landmark else 0.0)
	var shoulder_b_height: float = peak_rng.randf_range(0.49, 0.64) + (0.045 if not sharp_landmark else 0.0)
	var outcrop_height: float = peak_rng.randf_range(0.37, 0.52)
	var gully_depth: float = peak_rng.randf_range(0.045, 0.07)
	var ledge_step: float = height * peak_rng.randf_range(0.032, 0.047)
	for iz in vertex_depth:
		var nz: float = lerpf(-1.08, 1.08, float(iz) / float(MOUNTAIN_GRID_Z))
		for ix in vertex_width:
			var nx: float = lerpf(-1.08, 1.08, float(ix) / float(MOUNTAIN_GRID_X))
			var point: Vector2 = Vector2(nx, nz)
			var index: int = iz * vertex_width + ix
			var outline_noise: float = surface_noise.get_noise_2d(nx * 1.8, nz * 1.8)
			var outline_radius: float = 1.0 + outline_noise * 0.095
			var footprint: float = 1.0 - smoothstep(
				outline_radius - 0.16, outline_radius + 0.02, point.length()
			)
			footprint_weights[index] = footprint

			var broad_main: float = _massif_kernel(
				point, main_center, main_radii, crest_angle,
				main_exponent, 0.42
			) * (0.79 if sharp_landmark else 0.86)
			var summit_a: float = _massif_kernel(
				point, summit_a_center, summit_a_radii, crest_angle + 0.18, 0.72, 0.74
			) * summit_a_height
			var summit_b: float = _massif_kernel(
				point, summit_b_center, summit_b_radii, crest_angle - 0.31, 0.68, 0.82
			) * summit_b_height
			var main: float = maxf(broad_main, maxf(summit_a, summit_b))
			var first_shoulder: float = _massif_kernel(
				point, shoulder_a, Vector2(0.46, 0.54), crest_angle + 0.28, 1.02, 0.58
			) * shoulder_a_height
			var second_shoulder: float = _massif_kernel(
				point, shoulder_b, Vector2(0.42, 0.5), crest_angle - 0.5, 0.92, 0.66
			) * shoulder_b_height
			var outcrop: float = _massif_kernel(
				point, outcrop_center, Vector2(0.3, 0.4), crest_angle + 0.9, 0.78, 0.78
			) * outcrop_height
			var altitude: float = maxf(maxf(main, first_shoulder), maxf(second_shoulder, outcrop))
			altitude = maxf(altitude, footprint * 0.14)

			var authored_ridge: float = 0.0
			for ridge_index in ridge_segments.size():
				var ridge_metric: Vector2 = _segment_metric(point, ridge_segments[ridge_index])
				var ridge_influence: float = pow(
					maxf(1.0 - ridge_metric.y / ridge_widths[ridge_index], 0.0), 2.2
				)
				ridge_influence *= smoothstep(0.0, 0.12, footprint)
				altitude += ridge_influence * ridge_strengths[ridge_index] \
						* (1.0 - ridge_metric.x * 0.34)
				authored_ridge = maxf(authored_ridge, ridge_influence)

			var authored_gully: float = 0.0
			for gully_segment in gully_segments:
				var gully_metric: Vector2 = _segment_metric(point, gully_segment)
				var gully_influence: float = pow(maxf(1.0 - gully_metric.y / 0.068, 0.0), 1.65)
				gully_influence *= smoothstep(0.08, 0.7, gully_metric.x)
				authored_gully = maxf(authored_gully, gully_influence)
			altitude -= authored_gully * gully_depth

			var crag_noise: float = fracture_noise.get_noise_2d(nx * 3.8, nz * 3.8)
			altitude += crag_noise * 0.022 * footprint * (1.0 - altitude * 0.38)
			altitude = maxf(altitude, -0.035)
			var y: float = height * altitude
			var ledge_noise: float = surface_noise.get_noise_3d(nx * 2.8, nz * 2.8, altitude * 5.0)
			var ledge_mask: float = smoothstep(0.05, 0.62, ledge_noise)
			ledge_mask *= smoothstep(0.16, 0.34, altitude) * (1.0 - smoothstep(0.78, 0.94, altitude))
			ledge_mask *= 1.0 - authored_ridge * 0.48
			var terraced_y: float = floor(y / ledge_step) * ledge_step
			y = lerpf(y, terraced_y, ledge_mask * 0.34)
			if footprint < 0.01:
				y = -height * 0.045

			var ridge_mask: float = clampf(
				0.39 + authored_ridge * 0.58 - authored_gully * 0.47 + crag_noise * 0.06,
				0.0, 1.0
			)
			var normalized_altitude: float = clampf(y / height, 0.0, 1.1)
			positions[index] = Vector3(nx * base_radius, y, nz * base_radius * depth_scale)
			colors[index] = _mountain_vertex_color(
				rank, normalized_altitude, ridge_mask, crag_noise
			)
			uvs[index] = Vector2(ridge_mask, normalized_altitude)

	for iz in MOUNTAIN_GRID_Z:
		for ix in MOUNTAIN_GRID_X:
			var a: int = iz * vertex_width + ix
			var b: int = a + 1
			var c: int = a + vertex_width
			var d: int = c + 1
			if maxf(maxf(footprint_weights[a], footprint_weights[b]),
					maxf(footprint_weights[c], footprint_weights[d])) > 0.001:
				indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	return _create_indexed_mesh(positions, colors, uvs, indices)


func _massif_kernel(
		point: Vector2,
		center: Vector2,
		radii: Vector2,
		angle: float,
		exponent: float,
		facet: float
) -> float:
	var delta: Vector2 = (point - center).rotated(-angle)
	var scaled: Vector2 = Vector2(delta.x / radii.x, delta.y / radii.y)
	var euclidean: float = scaled.length()
	var angular: float = maxf(absf(scaled.x), absf(scaled.y)) * 1.08
	var distance: float = lerpf(euclidean, angular, facet)
	return pow(maxf(1.0 - distance, 0.0), exponent)


## Returns segment progress in x and perpendicular distance in y.
func _segment_metric(point: Vector2, segment: Vector4) -> Vector2:
	var start: Vector2 = Vector2(segment.x, segment.y)
	var end: Vector2 = Vector2(segment.z, segment.w)
	var line: Vector2 = end - start
	var length_squared: float = maxf(line.length_squared(), 0.00001)
	var progress: float = clampf((point - start).dot(line) / length_squared, 0.0, 1.0)
	var nearest: Vector2 = start + line * progress
	return Vector2(progress, point.distance_to(nearest))


func _mountain_vertex_color(
		rank: int,
		altitude: float,
		ridge_mask: float,
		noise_value: float
) -> Color:
	var low: Color
	var middle: Color
	var high: Color
	match rank:
		0:
			low = Color(0.21, 0.235, 0.23)
			middle = Color(0.30, 0.315, 0.31)
			high = Color(0.39, 0.405, 0.41)
		1:
			low = Color(0.245, 0.275, 0.30)
			middle = Color(0.34, 0.37, 0.405)
			high = Color(0.45, 0.48, 0.52)
		2:
			low = Color(0.30, 0.35, 0.395)
			middle = Color(0.40, 0.455, 0.515)
			high = Color(0.52, 0.575, 0.63)
		_:
			low = Color(0.39, 0.465, 0.535)
			middle = Color(0.49, 0.56, 0.63)
			high = Color(0.60, 0.665, 0.72)
	var color: Color = low.lerp(middle, smoothstep(0.08, 0.62, altitude))
	color = color.lerp(high, smoothstep(0.56, 1.0, altitude))
	color = color.darkened((1.0 - ridge_mask) * 0.16)
	color = color.lightened(ridge_mask * 0.055)
	color *= 0.96 + noise_value * 0.045
	color.a = 1.0
	return color


func _make_mountain_material(
		rank: int,
		height: float,
		peak_index: int,
		peak_rng: RandomNumberGenerator
) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _mountain_shader
	var snowline_value: float = 0.98
	var snow_amount_value: float = 0.0
	match rank:
		0:
			if height > 200.0 and peak_index % 4 == 1:
				snowline_value = peak_rng.randf_range(0.86, 0.93)
				snow_amount_value = 0.18
		1:
			if height > 275.0 or peak_index % 5 == 3:
				snowline_value = peak_rng.randf_range(0.72, 0.84)
				snow_amount_value = peak_rng.randf_range(0.42, 0.68)
		2:
			snowline_value = peak_rng.randf_range(0.58, 0.74)
			snow_amount_value = 0.0 if peak_index % 5 == 3 else peak_rng.randf_range(0.64, 0.92)
		_:
			snowline_value = peak_rng.randf_range(0.56, 0.72)
			snow_amount_value = 0.0 if peak_index % 4 == 0 else peak_rng.randf_range(0.45, 0.78)

	var haze_by_rank: PackedFloat32Array = PackedFloat32Array([0.035, 0.105, 0.205, 0.34])
	var strata_by_rank: PackedFloat32Array = PackedFloat32Array([0.28, 0.245, 0.185, 0.115])
	material.set_shader_parameter("snowline", snowline_value)
	material.set_shader_parameter("snow_softness", peak_rng.randf_range(0.055, 0.095))
	material.set_shader_parameter("snow_amount", snow_amount_value)
	material.set_shader_parameter("haze_amount", haze_by_rank[rank])
	material.set_shader_parameter("strata_strength", strata_by_rank[rank])
	material.set_shader_parameter("fracture_strength", 0.25 - float(rank) * 0.035)
	material.set_shader_parameter("scree_strength", 0.28 - float(rank) * 0.04)
	material.set_shader_parameter("gully_strength", 0.43 - float(rank) * 0.045)
	material.set_shader_parameter("rock_detail", 0.36 - float(rank) * 0.04)
	material.set_shader_parameter("detail_scale", 0.038 - float(rank) * 0.004)
	material.set_shader_parameter("fill_amount", 0.055 + float(rank) * 0.012)
	material.set_shader_parameter("seed_offset", float((peak_index + rank * 11) % 29) * 0.73)
	return material


## Bridges the meadow's finite terrain mesh to the distant range. This visual
## ground shelf is the deliberate cure for the former bright sky-colored band
## at the mountain feet; it overlaps the real edge, rises into slate foothills,
## and is then concealed by the ramparts and tree belt.
func _build_northern_apron() -> void:
	const X_SEGMENTS: int = 64
	const Z_SEGMENTS: int = 18
	const WIDTH: float = 1900.0
	const NEAR_Z: float = -236.0
	const FAR_Z: float = -670.0
	var positions: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var row_width: int = X_SEGMENTS + 1
	positions.resize(row_width * (Z_SEGMENTS + 1))
	colors.resize(positions.size())
	uvs.resize(positions.size())

	for iz in Z_SEGMENTS + 1:
		var depth: float = float(iz) / float(Z_SEGMENTS)
		var z: float = lerpf(NEAR_Z, FAR_Z, depth)
		for ix in X_SEGMENTS + 1:
			var across: float = float(ix) / float(X_SEGMENTS)
			var x: float = lerpf(-WIDTH * 0.5, WIDTH * 0.5, across)
			var y: float = _north_apron_height(x, z)
			if depth < 0.12 and _terrain != null and absf(x) <= MeadowTerrain.SIZE * 0.5:
				var terrain_y: float = _terrain.get_height(x, maxf(z, -MeadowTerrain.SIZE * 0.5))
				y = lerpf(terrain_y - 0.65, y, smoothstep(0.0, 0.12, depth))
			var index: int = iz * row_width + ix
			positions[index] = Vector3(x, y, z)
			var meadow_edge: Color = Color(0.255, 0.34, 0.205)
			var foothill_rock: Color = Color(0.225, 0.27, 0.275)
			var far_slate: Color = Color(0.265, 0.315, 0.34)
			var color: Color = meadow_edge.lerp(foothill_rock, smoothstep(0.0, 0.42, depth))
			color = color.lerp(far_slate, smoothstep(0.48, 1.0, depth))
			var tint_noise: float = _apron_noise.get_noise_2d(x + 170.0, z - 90.0)
			color *= 0.94 + tint_noise * 0.055
			color.a = 1.0
			colors[index] = color
			uvs[index] = Vector2(tint_noise * 0.5 + 0.5, depth * 0.58)

	for iz in Z_SEGMENTS:
		for ix in X_SEGMENTS:
			var a: int = iz * row_width + ix
			var b: int = a + 1
			var c: int = a + row_width
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

	var apron_mesh: ArrayMesh = _create_indexed_mesh(positions, colors, uvs, indices)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _mountain_shader
	material.set_shader_parameter("snow_amount", 0.0)
	material.set_shader_parameter("snowline", 1.0)
	material.set_shader_parameter("haze_amount", 0.025)
	material.set_shader_parameter("strata_strength", 0.075)
	material.set_shader_parameter("fracture_strength", 0.07)
	material.set_shader_parameter("scree_strength", 0.11)
	material.set_shader_parameter("gully_strength", 0.1)
	material.set_shader_parameter("rock_detail", 0.18)
	material.set_shader_parameter("detail_scale", 0.028)
	material.set_shader_parameter("fill_amount", 0.045)
	material.set_shader_parameter("seed_offset", 4.7)
	apron_mesh.surface_set_material(0, material)
	var apron: MeshInstance3D = MeshInstance3D.new()
	apron.name = "NorthernFoothillApron"
	apron.mesh = apron_mesh
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(apron)


func _north_apron_height(x: float, z: float) -> float:
	var depth: float = clampf(inverse_lerp(-236.0, -670.0, z), 0.0, 1.0)
	var broad: float = _apron_noise.get_noise_2d(x, z) * (5.0 + depth * 10.0)
	var ridges: float = sin(x * 0.011 + z * 0.003) * (2.0 + depth * 5.0)
	ridges += sin(x * 0.026 - z * 0.006) * (1.0 + depth * 2.5)
	return 19.0 + depth * 39.0 + broad + ridges


## Four crown families share the belt: wind-bent pine, narrow fir, broad
## spruce, and clustered cedar. Separate MultiMeshes retain cheap instancing
## without repeating one geometric arrow along the whole horizon.
func _plant_mountain_tree_belt() -> void:
	var belt: Node3D = Node3D.new()
	belt.name = "MountainTreeBelt"
	add_child(belt)
	var counts: PackedInt32Array = PackedInt32Array([72, 42, 72, 54])
	var width_factors: PackedFloat32Array = PackedFloat32Array([0.95, 0.7, 1.15, 1.08])
	var height_factors: PackedFloat32Array = PackedFloat32Array([1.0, 1.08, 0.9, 0.86])
	for variant in HORIZON_TREE_VARIANTS:
		var trees: MultiMeshInstance3D = MultiMeshInstance3D.new()
		trees.name = "TreeFamily_%d" % variant
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.instance_count = counts[variant]
		multimesh.mesh = _get_horizon_tree_mesh(variant)
		var belt_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		belt_rng.seed = VISTA_SEED + 401 + variant * 97
		for i in multimesh.instance_count:
			var row: int = (i * 3 + variant) % 5
			var x: float = belt_rng.randf_range(-900.0, 900.0)
			var z: float = -305.0 - float(row) * 55.0 + belt_rng.randf_range(-24.0, 24.0)
			var uniform_scale: float = belt_rng.randf_range(0.42, 0.86) * (1.0 + float(row) * 0.06)
			var scale: Vector3 = Vector3(
				uniform_scale * width_factors[variant] * belt_rng.randf_range(0.78, 1.2),
				uniform_scale * height_factors[variant] * belt_rng.randf_range(0.88, 1.3),
				uniform_scale * width_factors[variant] * belt_rng.randf_range(0.76, 1.16)
			)
			var basis: Basis = Basis(Vector3.UP, belt_rng.randf_range(0.0, TAU)).scaled(scale)
			var origin: Vector3 = Vector3(x, _north_apron_height(x, z) - 2.0, z)
			multimesh.set_instance_transform(i, Transform3D(basis, origin))
			var tint: float = belt_rng.randf_range(0.76, 1.0)
			multimesh.set_instance_color(i, Color(tint * 0.82, tint * 0.93, tint, 1.0))
		trees.multimesh = multimesh
		trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		belt.add_child(trees)


## The eastern border is a forest volume, not a row of six-sided cones.
## Layered depths, irregular crown profiles, and a few tall emergent trees make
## the horizon breathe while the shared mesh keeps it inexpensive.
func _grow_latent_forest_wall() -> void:
	var wall: Node3D = Node3D.new()
	wall.name = "LatentForestWall"
	add_child(wall)
	var counts: PackedInt32Array = PackedInt32Array([58, 30, 60, 62])
	var width_factors: PackedFloat32Array = PackedFloat32Array([0.95, 0.7, 1.2, 1.12])
	var height_factors: PackedFloat32Array = PackedFloat32Array([1.0, 1.08, 0.92, 0.88])
	for variant in HORIZON_TREE_VARIANTS:
		var forest: MultiMeshInstance3D = MultiMeshInstance3D.new()
		forest.name = "CanopyFamily_%d" % variant
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.instance_count = counts[variant]
		multimesh.mesh = _get_horizon_tree_mesh(variant)
		var forest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		forest_rng.seed = VISTA_SEED + 809 + variant * 113
		for i in multimesh.instance_count:
			var layer: int = (i * 3 + variant) % 4
			var x: float = 430.0 + float(layer) * 58.0 + forest_rng.randf_range(-20.0, 24.0)
			var z: float = forest_rng.randf_range(-650.0, 650.0)
			var height_scale: float = forest_rng.randf_range(0.88, 1.56)
			if (i + variant * 7) % 29 == 0:
				height_scale *= 1.42
			var scale: Vector3 = Vector3(
				height_scale * width_factors[variant] * forest_rng.randf_range(0.72, 1.08),
				height_scale * height_factors[variant],
				height_scale * width_factors[variant] * forest_rng.randf_range(0.7, 1.06)
			)
			var basis: Basis = Basis(Vector3.UP, forest_rng.randf_range(0.0, TAU)).scaled(scale)
			var ground_y: float = -5.0 + sin(z * 0.014) * 7.0 + float(layer) * 2.0
			multimesh.set_instance_transform(i, Transform3D(basis, Vector3(x, ground_y, z)))
			var depth_tint: float = 0.94 - float(layer) * 0.055
			multimesh.set_instance_color(i, Color(
				depth_tint * forest_rng.randf_range(0.75, 0.91),
				depth_tint * forest_rng.randf_range(0.87, 1.0),
				depth_tint,
				1.0
			))
		forest.multimesh = multimesh
		forest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wall.add_child(forest)


func _get_horizon_tree_mesh(variant: int) -> ArrayMesh:
	while _horizon_tree_meshes.size() <= variant:
		_horizon_tree_meshes.append(_build_horizon_tree_mesh(_horizon_tree_meshes.size()))
	return _horizon_tree_meshes[variant]


func _build_horizon_tree_mesh(variant: int) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_tree_trunk(st, variant)
	var heights: PackedFloat32Array
	var radii: PackedFloat32Array
	match variant:
		0:
			heights = PackedFloat32Array([8.0, 12.0, 17.0, 22.0, 28.0, 34.0, 40.0, 45.0, 50.0, 54.0, 57.0])
			radii = PackedFloat32Array([1.0, 8.5, 11.0, 10.0, 13.0, 11.0, 9.2, 7.5, 5.2, 2.8, 0.25])
			_append_tree_crown(st, heights, radii, Vector3.ZERO, Vector3.ONE, 0.4, 1.5)
			_append_tree_crown(st, heights, radii, Vector3(-3.4, 3.0, 1.0), Vector3(0.48, 0.68, 0.5), 2.2, 1.1)
		1:
			heights = PackedFloat32Array([8.0, 13.0, 19.0, 25.0, 31.0, 37.0, 43.0, 49.0, 54.0, 58.0, 61.0])
			radii = PackedFloat32Array([0.8, 5.0, 7.4, 6.6, 8.3, 7.2, 6.3, 5.0, 3.4, 1.8, 0.2])
			_append_tree_crown(st, heights, radii, Vector3.ZERO, Vector3(0.9, 1.0, 0.9), 1.3, 0.9)
		2:
			heights = PackedFloat32Array([7.0, 11.0, 16.0, 21.0, 26.0, 31.0, 36.0, 41.0, 46.0, 50.0, 53.0])
			radii = PackedFloat32Array([1.2, 11.0, 14.5, 13.2, 15.5, 13.8, 12.2, 9.8, 7.0, 3.8, 0.3])
			_append_tree_crown(st, heights, radii, Vector3.ZERO, Vector3.ONE, 2.7, 2.0)
			_append_tree_crown(st, heights, radii, Vector3(4.0, 1.0, -1.2), Vector3(0.45, 0.66, 0.5), 4.1, 1.2)
		_:
			heights = PackedFloat32Array([12.0, 16.0, 21.0, 26.0, 31.0, 36.0, 41.0, 45.0, 48.0])
			radii = PackedFloat32Array([2.0, 8.5, 13.5, 15.5, 15.0, 13.0, 9.5, 5.2, 0.5])
			_append_tree_crown(st, heights, radii, Vector3(-3.5, 0.0, 1.0), Vector3(0.82, 0.98, 0.86), 0.8, 2.2)
			_append_tree_crown(st, heights, radii, Vector3(5.0, 1.5, -2.0), Vector3(0.7, 0.84, 0.76), 3.4, 1.8)
			_append_tree_crown(st, heights, radii, Vector3(0.0, 5.0, 3.5), Vector3(0.58, 0.7, 0.62), 5.1, 1.4)
	st.generate_normals()
	var tree_mesh: ArrayMesh = st.commit()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(TOON_SOFT_SHADER_PATH) as Shader
	material.set_shader_parameter("rim_amount", 0.045)
	material.set_shader_parameter("rim_width", 0.86)
	material.set_shader_parameter("fill_amount", 0.06)
	material.set_shader_parameter("noise_amount", 0.11)
	material.set_shader_parameter("noise_scale", 0.16)
	tree_mesh.surface_set_material(0, material)
	return tree_mesh


func _append_tree_trunk(st: SurfaceTool, variant: int) -> void:
	const SEGMENTS: int = 10
	var bark_low: Color = Color(0.16, 0.115, 0.075)
	var bark_high: Color = Color(0.25, 0.18, 0.105)
	var lean: Vector2 = Vector2(float(variant - 1) * 0.38, float((variant * 5) % 3 - 1) * 0.28)
	for segment in SEGMENTS:
		var a0: float = TAU * float(segment) / float(SEGMENTS)
		var a1: float = TAU * float(segment + 1) / float(SEGMENTS)
		var lower_a: Vector3 = Vector3(cos(a0) * 2.7, 0.0, sin(a0) * 2.7)
		var lower_b: Vector3 = Vector3(cos(a1) * 2.7, 0.0, sin(a1) * 2.7)
		var upper_a: Vector3 = Vector3(cos(a0) * 1.35 + lean.x, 27.0, sin(a0) * 1.35 + lean.y)
		var upper_b: Vector3 = Vector3(cos(a1) * 1.35 + lean.x, 27.0, sin(a1) * 1.35 + lean.y)
		_add_colored_triangle(st, lower_a, upper_a, lower_b, bark_low, bark_high, bark_low)
		_add_colored_triangle(st, lower_b, upper_a, upper_b, bark_low, bark_high, bark_high)


func _append_tree_crown(
		st: SurfaceTool,
		heights: PackedFloat32Array,
		radii: PackedFloat32Array,
		offset: Vector3,
		scale: Vector3,
		phase: float,
		drift: float
) -> void:
	const SEGMENTS: int = 16
	var deep_needles: Color = Color(0.105, 0.225, 0.17)
	var lit_needles: Color = Color(0.20, 0.36, 0.245)
	for ring in heights.size() - 1:
		var ring_t0: float = float(ring) / float(heights.size() - 1)
		var ring_t1: float = float(ring + 1) / float(heights.size() - 1)
		for segment in SEGMENTS:
			var a0: float = TAU * float(segment) / float(SEGMENTS)
			var a1: float = TAU * float(segment + 1) / float(SEGMENTS)
			var rough0: float = 1.0 + sin(a0 * 3.0 + phase + float(ring) * 0.51) * 0.09
			rough0 += sin(a0 * 7.0 - phase * 0.7 + float(ring) * 0.29) * 0.055
			var rough1: float = 1.0 + sin(a1 * 3.0 + phase + float(ring) * 0.51) * 0.09
			rough1 += sin(a1 * 7.0 - phase * 0.7 + float(ring) * 0.29) * 0.055
			var rough2: float = 1.0 + sin(a0 * 3.0 + phase + float(ring + 1) * 0.51) * 0.09
			rough2 += sin(a0 * 7.0 - phase * 0.7 + float(ring + 1) * 0.29) * 0.055
			var rough3: float = 1.0 + sin(a1 * 3.0 + phase + float(ring + 1) * 0.51) * 0.09
			rough3 += sin(a1 * 7.0 - phase * 0.7 + float(ring + 1) * 0.29) * 0.055
			var center0: Vector2 = Vector2(
				sin(float(ring) * 0.71 + phase), cos(float(ring) * 0.47 - phase) * 0.62
			) * drift
			var center1: Vector2 = Vector2(
				sin(float(ring + 1) * 0.71 + phase), cos(float(ring + 1) * 0.47 - phase) * 0.62
			) * drift
			var y_jitter0: float = sin(a0 * 4.0 + phase + float(ring)) * 0.42
			var y_jitter1: float = sin(a1 * 4.0 + phase + float(ring)) * 0.42
			var y_jitter2: float = sin(a0 * 4.0 + phase + float(ring + 1)) * 0.42
			var y_jitter3: float = sin(a1 * 4.0 + phase + float(ring + 1)) * 0.42
			var p00: Vector3 = offset + Vector3(
				(cos(a0) * radii[ring] * rough0 + center0.x) * scale.x,
				(heights[ring] + y_jitter0) * scale.y,
				(sin(a0) * radii[ring] * rough0 + center0.y) * scale.z
			)
			var p01: Vector3 = offset + Vector3(
				(cos(a1) * radii[ring] * rough1 + center0.x) * scale.x,
				(heights[ring] + y_jitter1) * scale.y,
				(sin(a1) * radii[ring] * rough1 + center0.y) * scale.z
			)
			var p10: Vector3 = offset + Vector3(
				(cos(a0) * radii[ring + 1] * rough2 + center1.x) * scale.x,
				(heights[ring + 1] + y_jitter2) * scale.y,
				(sin(a0) * radii[ring + 1] * rough2 + center1.y) * scale.z
			)
			var p11: Vector3 = offset + Vector3(
				(cos(a1) * radii[ring + 1] * rough3 + center1.x) * scale.x,
				(heights[ring + 1] + y_jitter3) * scale.y,
				(sin(a1) * radii[ring + 1] * rough3 + center1.y) * scale.z
			)
			var color0: Color = deep_needles.lerp(lit_needles, ring_t0 * 0.72 + rough0 * 0.08)
			var color1: Color = deep_needles.lerp(lit_needles, ring_t1 * 0.72 + rough2 * 0.08)
			_add_colored_triangle(st, p00, p10, p01, color0, color1, color0)
			_add_colored_triangle(st, p01, p10, p11, color0, color1, color1)


func _add_colored_triangle(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		color_a: Color,
		color_b: Color,
		color_c: Color
) -> void:
	st.set_color(color_a)
	st.add_vertex(a)
	st.set_color(color_b)
	st.add_vertex(b)
	st.set_color(color_c)
	st.add_vertex(c)


func _lay_convolution_sea() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1500.0, 1700.0)
	plane.subdivide_width = 72
	plane.subdivide_depth = 72
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://assets/shaders/water.gdshader") as Shader
	material.set_shader_parameter("wave_height", 0.14)
	material.set_shader_parameter("ripple_scale", 0.16)
	material.set_shader_parameter("ripple_strength", 0.48)
	material.set_shader_parameter("deep_color", Color(0.018, 0.12, 0.21, 0.98))
	material.set_shader_parameter("shallow_color", Color(0.07, 0.32, 0.43, 0.9))
	plane.material = material
	var sea: MeshInstance3D = MeshInstance3D.new()
	sea.name = "ConvolutionSea"
	sea.mesh = plane
	sea.position = Vector3(-990.0, -13.5, 0.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


func _roll_southern_downs() -> void:
	var downs: Node3D = Node3D.new()
	downs.name = "SouthernDowns"
	add_child(downs)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(TOON_SOFT_SHADER_PATH) as Shader
	material.set_shader_parameter("albedo_tint", Color(0.29, 0.405, 0.225))
	material.set_shader_parameter("rim_amount", 0.055)
	material.set_shader_parameter("rim_width", 0.88)
	material.set_shader_parameter("fill_amount", 0.08)
	material.set_shader_parameter("noise_amount", 0.13)
	material.set_shader_parameter("noise_scale", 0.08)
	for i in 12:
		var rear: bool = i % 2 == 0
		var hill: SphereMesh = SphereMesh.new()
		hill.radius = _rng.randf_range(150.0, 245.0) * (1.2 if rear else 0.85)
		hill.height = _rng.randf_range(72.0, 130.0) * (1.15 if rear else 0.86)
		hill.radial_segments = 32
		hill.rings = 14
		var hill_instance: MeshInstance3D = MeshInstance3D.new()
		hill_instance.name = "Down_%02d" % i
		hill_instance.mesh = hill
		hill_instance.material_override = material
		hill_instance.position = Vector3(
			-780.0 + 145.0 * float(i) + _rng.randf_range(-38.0, 38.0),
			-22.0,
			760.0 + (85.0 if rear else 0.0) + _rng.randf_range(-35.0, 35.0)
		)
		hill_instance.scale.z = _rng.randf_range(0.72, 1.25)
		hill_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		downs.add_child(hill_instance)


func _create_indexed_mesh(
		positions: PackedVector3Array,
		colors: PackedColorArray,
		uvs: PackedVector2Array,
		indices: PackedInt32Array
) -> ArrayMesh:
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(positions.size())
	for i in positions.size():
		normals[i] = Vector3.ZERO
	for triangle in range(0, indices.size(), 3):
		var ia: int = indices[triangle]
		var ib: int = indices[triangle + 1]
		var ic: int = indices[triangle + 2]
		var edge_a: Vector3 = positions[ib] - positions[ia]
		var edge_b: Vector3 = positions[ic] - positions[ia]
		var face_normal: Vector3 = edge_a.cross(edge_b)
		if face_normal.length_squared() > 0.000001:
			face_normal = face_normal.normalized()
			normals[ia] += face_normal
			normals[ib] += face_normal
			normals[ic] += face_normal
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.000001 else Vector3.UP

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

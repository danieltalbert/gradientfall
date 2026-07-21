class_name CloudLayer
extends Node3D
## Painterly horizon clouds for the Datasedge sky.
##
## The layer is deliberately geometric rather than a flat sky texture. Each
## cloud combines a broad, shaded base, overlapping cumulus towers, depth
## billows, and a second translucent mesh for wind-sheared wisps. The ring is
## composed around the meadow at a low apparent elevation because Kern's
## third-person camera looks slightly down; this keeps substantial cloud
## silhouettes in every authored vista instead of hiding them above frame.

const CLOUD_SEED: int = 20260719
const CLOUD_COUNT: int = 18
const CLOUD_ORIGIN: Vector3 = Vector3(-58.0, 0.0, -62.0)
const WRAP_MIN_X: float = -1550.0
const WRAP_MAX_X: float = 1550.0
const CORE_SHADER: Shader = preload("res://assets/shaders/painterly_cloud.gdshader")
const WISP_SHADER: Shader = preload("res://assets/shaders/painterly_cloud_wisp.gdshader")

const FIELD_FALLOFF: float = 2.15
const CORE_THRESHOLD: float = 0.30
const WISP_THRESHOLD: float = 0.25
const TETRAHEDRA: Array = [
	[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
	[0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
]

class CloudPuff:
	var center: Vector3
	var radii: Vector3
	var basis: Basis
	var inverse_basis: Basis
	var strength: float
	var tone: float

	func _init(c: Vector3, r: Vector3, rotation: Vector3, s: float, t: float) -> void:
		center = c
		radii = r
		basis = Basis.from_euler(rotation)
		inverse_basis = basis.transposed()
		strength = s
		tone = t

var _core_material: ShaderMaterial
var _wisp_material: ShaderMaterial
var _clouds: Array[Node3D] = []
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _base_heights: PackedFloat32Array = PackedFloat32Array()
var _base_depths: PackedFloat32Array = PackedFloat32Array()
var _phases: PackedFloat32Array = PackedFloat32Array()
var _elapsed: float = 0.0
var _cycle: SkyCycle
var _sun: DirectionalLight3D


func _ready() -> void:
	_cycle = get_node_or_null("../SkyCycle") as SkyCycle
	_sun = get_node_or_null("../../Sun") as DirectionalLight3D
	_core_material = ShaderMaterial.new()
	_core_material.shader = CORE_SHADER
	_wisp_material = ShaderMaterial.new()
	_wisp_material.shader = WISP_SHADER

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = CLOUD_SEED
	for i in CLOUD_COUNT:
		var cloud: Node3D = _build_cloud(rng, i % 4)
		var ring_slot: float = (float(i) + 0.36) / float(CLOUD_COUNT)
		var angle: float = ring_slot * TAU + rng.randf_range(-0.075, 0.075)
		var outer_ring: bool = i % 2 == 1
		var radius: float
		if outer_ring:
			radius = rng.randf_range(820.0, 1120.0)
		else:
			radius = rng.randf_range(520.0, 760.0)
		var radial: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		# A 5-8 degree apparent elevation stays inside the camera's sky band.
		var altitude: float = radius * rng.randf_range(0.075, 0.105) + rng.randf_range(8.0, 19.0)
		cloud.position = CLOUD_ORIGIN + radial * radius + Vector3(0.0, altitude, 0.0)
		# Keep each bank's broad axis roughly tangent to the viewing ring.
		cloud.rotation.y = -angle - PI * 0.5 + rng.randf_range(-0.22, 0.22)
		var scale_factor: float = rng.randf_range(0.88, 1.24)
		if outer_ring:
			scale_factor *= rng.randf_range(1.05, 1.32)
		cloud.scale = Vector3(scale_factor, scale_factor, scale_factor)
		add_child(cloud)
		_clouds.append(cloud)
		_speeds.append(rng.randf_range(0.28, 0.72))
		_base_heights.append(cloud.position.y)
		_base_depths.append(cloud.position.z)
		_phases.append(rng.randf_range(0.0, TAU))

	_update_palette()
	print("CloudLayer: %d layered cloud banks adrift." % CLOUD_COUNT)


func _process(delta: float) -> void:
	_elapsed += delta
	for i in _clouds.size():
		var cloud: Node3D = _clouds[i]
		cloud.position.x += _speeds[i] * delta
		if cloud.position.x > WRAP_MAX_X:
			cloud.position.x = WRAP_MIN_X
		cloud.position.y = _base_heights[i] + sin(_elapsed * 0.035 + _phases[i]) * 1.4
		cloud.position.z = _base_depths[i] + sin(_elapsed * 0.022 + _phases[i] * 1.7) * 3.2
	_update_palette()


func _build_cloud(rng: RandomNumberGenerator, profile: int) -> Node3D:
	var cloud: Node3D = Node3D.new()
	cloud.name = "CloudBank"

	var width: float = rng.randf_range(145.0, 225.0)
	var base_radius: float = rng.randf_range(19.0, 28.0)
	var tower_factor: float = 0.8
	match profile:
		0:
			tower_factor = 0.30  # broad fair-weather bank
		1:
			tower_factor = 0.78  # one substantial fused tower
		2:
			tower_factor = 0.48  # broken, asymmetric cumulus
		3:
			tower_factor = 0.64  # deep multi-tower mass

	var cloud_bottom: float = -base_radius * 0.96
	var cloud_top: float = base_radius * (1.55 + tower_factor * 1.45)
	var core_puffs: Array[CloudPuff] = []
	# A deliberately under-strength backbone joins the bank without dictating a
	# perfect capsule silhouette. Overlapping, offset base masses provide the
	# actual lower contour and blend into one isosurface below.
	core_puffs.append(CloudPuff.new(
		Vector3(0.0, -base_radius * 0.12, 0.0),
		Vector3(width * 0.38, base_radius * 0.52, base_radius * 1.06),
		Vector3(rng.randf_range(-0.035, 0.035), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.045, 0.045)),
		0.58, rng.randf_range(0.30, 0.44)
	))

	var base_lobes: int = rng.randi_range(4, 6)
	for lobe_index in base_lobes:
		var t: float = (float(lobe_index) + 0.5) / float(base_lobes)
		var arc: float = sin(t * PI)
		var radius: float = base_radius * rng.randf_range(0.90, 1.14)
		var center: Vector3 = Vector3(
			lerpf(-width * 0.40, width * 0.40, t) + rng.randf_range(-7.0, 7.0),
			base_radius * rng.randf_range(-0.14, 0.18) + arc * base_radius * rng.randf_range(0.18, 0.34),
			rng.randf_range(-base_radius * 0.26, base_radius * 0.26)
		)
		core_puffs.append(CloudPuff.new(
			center,
			Vector3(
				radius * rng.randf_range(1.30, 1.70),
				radius * rng.randf_range(0.62, 0.84),
				radius * rng.randf_range(1.00, 1.28)
			),
			Vector3(rng.randf_range(-0.11, 0.11), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.11, 0.11)),
			rng.randf_range(0.72, 0.92), rng.randf_range(0.35, 0.70)
		))

	# Broad overlapping upper masses build one irregular cauliflower skyline.
	# Their centers remain well inside one another's influence radii, avoiding
	# the visible snowman/egg stacks produced by intersecting sphere meshes.
	var upper_lobes: int = rng.randi_range(3, 5)
	for upper_index in upper_lobes:
		var upper_t: float = (float(upper_index) + rng.randf_range(0.25, 0.75)) / float(upper_lobes)
		var upper_radius: float = base_radius * rng.randf_range(0.82, 1.12)
		var upper_center: Vector3 = Vector3(
			lerpf(-width * 0.30, width * 0.30, upper_t) + rng.randf_range(-base_radius * 0.28, base_radius * 0.28),
			base_radius * rng.randf_range(0.32, 0.74) + sin(upper_t * PI) * base_radius * tower_factor * 0.34,
			rng.randf_range(-base_radius * 0.30, base_radius * 0.30)
		)
		core_puffs.append(CloudPuff.new(
			upper_center,
			Vector3(
				upper_radius * rng.randf_range(1.25, 1.62),
				upper_radius * rng.randf_range(0.82, 1.12),
				upper_radius * rng.randf_range(0.94, 1.24)
			),
			Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.28, 0.28), rng.randf_range(-0.12, 0.12)),
			rng.randf_range(0.76, 1.0), rng.randf_range(0.50, 0.86)
		))

	# One or two soft tower shoulders add hierarchy without isolated top beads.
	var tower_count: int = 1 if profile == 0 or profile == 2 else 2
	for tower_index in tower_count:
		var tower_t: float = (float(tower_index) + rng.randf_range(0.35, 0.68)) / float(tower_count)
		var tower_radius: float = base_radius * rng.randf_range(0.78, 1.02)
		var tower_center: Vector3 = Vector3(
			lerpf(-width * 0.24, width * 0.24, tower_t),
			base_radius * (0.68 + tower_factor * rng.randf_range(0.40, 0.78)),
			rng.randf_range(-base_radius * 0.18, base_radius * 0.18)
		)
		core_puffs.append(CloudPuff.new(
			tower_center,
			Vector3(
				tower_radius * rng.randf_range(1.12, 1.48),
				tower_radius * rng.randf_range(1.00, 1.34),
				tower_radius * rng.randf_range(0.94, 1.20)
			),
			Vector3(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.22, 0.22), rng.randf_range(-0.12, 0.12)),
			rng.randf_range(0.68, 0.88), rng.randf_range(0.62, 0.94)
		))

	# Forward and rear billows stop the cloud from reading as a flat cutout
	# when Kern walks around it or the camera catches a three-quarter angle.
	var depth_lobes: int = rng.randi_range(3, 4)
	for depth_index in depth_lobes:
		var depth_side: float = -1.0 if depth_index % 2 == 0 else 1.0
		var depth_radius: float = base_radius * rng.randf_range(0.64, 0.92)
		var depth_center: Vector3 = Vector3(
			rng.randf_range(-width * 0.30, width * 0.30),
			rng.randf_range(base_radius * 0.02, base_radius * 0.62),
			depth_side * rng.randf_range(base_radius * 0.46, base_radius * 0.76)
		)
		core_puffs.append(CloudPuff.new(
			depth_center,
			Vector3(depth_radius * rng.randf_range(1.22, 1.58), depth_radius * rng.randf_range(0.78, 1.02), depth_radius * 1.10),
			Vector3(rng.randf_range(-0.10, 0.10), rng.randf_range(-0.22, 0.22), rng.randf_range(-0.08, 0.08)),
			rng.randf_range(0.64, 0.84), rng.randf_range(0.30, 0.66)
		))

	var core: MeshInstance3D = MeshInstance3D.new()
	core.name = "Core"
	core.mesh = _build_implicit_mesh(
		core_puffs,
		Vector3(-width * 0.59, cloud_bottom - base_radius * 0.34, -base_radius * 1.68),
		Vector3(width * 0.59, cloud_top + base_radius * 0.42, base_radius * 1.68),
		Vector3i(26, 14, 14), CORE_THRESHOLD,
		cloud_bottom, cloud_top, rng.randf(), 1.0
	)
	core.material_override = _core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud.add_child(core)

	var wisp_puffs: Array[CloudPuff] = []
	var wisp_count: int = rng.randi_range(3, 4)
	var wind_side: float = -1.0 if rng.randf() < 0.5 else 1.0
	for wisp_index in wisp_count:
		var wisp_t: float = float(wisp_index) / maxf(float(wisp_count - 1), 1.0)
		var wisp_radius: float = base_radius * rng.randf_range(0.46, 0.68)
		var wisp_center: Vector3 = Vector3(
			wind_side * width * (0.39 + wisp_t * 0.22),
			base_radius * rng.randf_range(-0.18, 0.26) + sin(wisp_t * PI) * base_radius * 0.16,
			rng.randf_range(-base_radius * 0.42, base_radius * 0.42)
		)
		wisp_puffs.append(CloudPuff.new(
			wisp_center,
			Vector3(
				wisp_radius * rng.randf_range(2.20, 3.25),
				wisp_radius * rng.randf_range(0.32, 0.54),
				wisp_radius * rng.randf_range(0.72, 1.04)
			),
			Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.18, 0.18), rng.randf_range(-0.08, 0.08)),
			rng.randf_range(0.58, 0.78), rng.randf_range(0.25, 0.58)
		))

	var wisps: MeshInstance3D = MeshInstance3D.new()
	wisps.name = "Wisps"
	wisps.mesh = _build_implicit_mesh(
		wisp_puffs,
		Vector3(-width * 0.82, cloud_bottom - base_radius * 0.22, -base_radius * 1.24),
		Vector3(width * 0.82, base_radius * 0.76, base_radius * 1.24),
		Vector3i(22, 9, 10), WISP_THRESHOLD,
		cloud_bottom, cloud_top, rng.randf(), 0.62
	)
	wisps.material_override = _wisp_material
	wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud.add_child(wisps)
	return cloud


func _build_implicit_mesh(
		puffs: Array[CloudPuff],
		minimum: Vector3,
		maximum: Vector3,
		resolution: Vector3i,
		threshold: float,
		cloud_bottom: float,
		cloud_top: float,
		phase: float,
		density: float
	) -> ArrayMesh:
	var builder: SurfaceTool = SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points_x: int = resolution.x + 1
	var points_y: int = resolution.y + 1
	var points_z: int = resolution.z + 1
	var field: PackedFloat32Array = PackedFloat32Array()
	field.resize(points_x * points_y * points_z)
	var step: Vector3 = (maximum - minimum) / Vector3(resolution)
	for z in points_z:
		for y in points_y:
			for x in points_x:
				var point: Vector3 = minimum + Vector3(float(x), float(y), float(z)) * step
				field[_field_index(x, y, z, points_x, points_y)] = _sample_field(point, puffs)

	for z in resolution.z:
		for y in resolution.y:
			for x in resolution.x:
				var cell_origin: Vector3 = minimum + Vector3(float(x), float(y), float(z)) * step
				var corners: Array[Vector3] = [
					cell_origin,
					cell_origin + Vector3(step.x, 0.0, 0.0),
					cell_origin + Vector3(step.x, step.y, 0.0),
					cell_origin + Vector3(0.0, step.y, 0.0),
					cell_origin + Vector3(0.0, 0.0, step.z),
					cell_origin + Vector3(step.x, 0.0, step.z),
					cell_origin + step,
					cell_origin + Vector3(0.0, step.y, step.z),
				]
				var values: PackedFloat32Array = PackedFloat32Array([
					field[_field_index(x, y, z, points_x, points_y)],
					field[_field_index(x + 1, y, z, points_x, points_y)],
					field[_field_index(x + 1, y + 1, z, points_x, points_y)],
					field[_field_index(x, y + 1, z, points_x, points_y)],
					field[_field_index(x, y, z + 1, points_x, points_y)],
					field[_field_index(x + 1, y, z + 1, points_x, points_y)],
					field[_field_index(x + 1, y + 1, z + 1, points_x, points_y)],
					field[_field_index(x, y + 1, z + 1, points_x, points_y)],
				])
				for tetra_data: Array in TETRAHEDRA:
					_polygonise_tetra(
						builder, puffs, corners, values,
						int(tetra_data[0]), int(tetra_data[1]), int(tetra_data[2]), int(tetra_data[3]),
						threshold, cloud_bottom, cloud_top, phase, density
					)
	return builder.commit()


func _field_index(x: int, y: int, z: int, points_x: int, points_y: int) -> int:
	return x + points_x * (y + points_y * z)


func _sample_field(point: Vector3, puffs: Array[CloudPuff]) -> float:
	var total: float = 0.0
	for puff: CloudPuff in puffs:
		var local: Vector3 = puff.inverse_basis * (point - puff.center)
		var distance_squared: float = (
			local.x * local.x / (puff.radii.x * puff.radii.x)
			+ local.y * local.y / (puff.radii.y * puff.radii.y)
			+ local.z * local.z / (puff.radii.z * puff.radii.z)
		)
		if distance_squared < 3.2:
			total += puff.strength * exp(-FIELD_FALLOFF * distance_squared)
	return total


func _polygonise_tetra(
		builder: SurfaceTool,
		puffs: Array[CloudPuff],
		corners: Array[Vector3],
		values: PackedFloat32Array,
		i0: int, i1: int, i2: int, i3: int,
		threshold: float,
		cloud_bottom: float,
		cloud_top: float,
		phase: float,
		density: float
	) -> void:
	var indices: PackedInt32Array = PackedInt32Array([i0, i1, i2, i3])
	var inside: PackedInt32Array = PackedInt32Array()
	var outside: PackedInt32Array = PackedInt32Array()
	for index: int in indices:
		if values[index] >= threshold:
			inside.append(index)
		else:
			outside.append(index)
	if inside.is_empty() or outside.is_empty():
		return
	if inside.size() == 1 or outside.size() == 1:
		var lone: int = inside[0] if inside.size() == 1 else outside[0]
		var others: PackedInt32Array = outside if inside.size() == 1 else inside
		var a: Vector3 = _field_edge(corners[lone], corners[others[0]], values[lone], values[others[0]], threshold)
		var b: Vector3 = _field_edge(corners[lone], corners[others[1]], values[lone], values[others[1]], threshold)
		var c: Vector3 = _field_edge(corners[lone], corners[others[2]], values[lone], values[others[2]], threshold)
		_append_field_triangle(builder, puffs, a, b, c, cloud_bottom, cloud_top, phase, density)
		return

	var inside_a: int = inside[0]
	var inside_b: int = inside[1]
	var outside_a: int = outside[0]
	var outside_b: int = outside[1]
	var ac: Vector3 = _field_edge(corners[inside_a], corners[outside_a], values[inside_a], values[outside_a], threshold)
	var ad: Vector3 = _field_edge(corners[inside_a], corners[outside_b], values[inside_a], values[outside_b], threshold)
	var bc: Vector3 = _field_edge(corners[inside_b], corners[outside_a], values[inside_b], values[outside_a], threshold)
	var bd: Vector3 = _field_edge(corners[inside_b], corners[outside_b], values[inside_b], values[outside_b], threshold)
	_append_field_triangle(builder, puffs, ac, ad, bd, cloud_bottom, cloud_top, phase, density)
	_append_field_triangle(builder, puffs, ac, bd, bc, cloud_bottom, cloud_top, phase, density)


func _field_edge(a: Vector3, b: Vector3, value_a: float, value_b: float, threshold: float) -> Vector3:
	var denominator: float = value_b - value_a
	if absf(denominator) < 0.00001:
		return (a + b) * 0.5
	return a.lerp(b, clampf((threshold - value_a) / denominator, 0.0, 1.0))


func _append_field_triangle(
		builder: SurfaceTool,
		puffs: Array[CloudPuff],
		a: Vector3,
		b: Vector3,
		c: Vector3,
		cloud_bottom: float,
		cloud_top: float,
		phase: float,
		density: float
	) -> void:
	var normal_a: Vector3 = _field_normal(a, puffs)
	var normal_b: Vector3 = _field_normal(b, puffs)
	var normal_c: Vector3 = _field_normal(c, puffs)
	var geometric_normal: Vector3 = (b - a).cross(c - a)
	if geometric_normal.dot(normal_a + normal_b + normal_c) < 0.0:
		var swap_position: Vector3 = b
		b = c
		c = swap_position
		var swap_normal: Vector3 = normal_b
		normal_b = normal_c
		normal_c = swap_normal
	_append_field_vertex(builder, puffs, a, normal_a, cloud_bottom, cloud_top, phase, density)
	_append_field_vertex(builder, puffs, b, normal_b, cloud_bottom, cloud_top, phase, density)
	_append_field_vertex(builder, puffs, c, normal_c, cloud_bottom, cloud_top, phase, density)


func _field_normal(point: Vector3, puffs: Array[CloudPuff]) -> Vector3:
	var gradient: Vector3 = Vector3.ZERO
	for puff: CloudPuff in puffs:
		var local: Vector3 = puff.inverse_basis * (point - puff.center)
		var distance_squared: float = (
			local.x * local.x / (puff.radii.x * puff.radii.x)
			+ local.y * local.y / (puff.radii.y * puff.radii.y)
			+ local.z * local.z / (puff.radii.z * puff.radii.z)
		)
		if distance_squared < 3.2:
			var contribution: float = puff.strength * exp(-FIELD_FALLOFF * distance_squared)
			var local_gradient: Vector3 = Vector3(
				local.x / (puff.radii.x * puff.radii.x),
				local.y / (puff.radii.y * puff.radii.y),
				local.z / (puff.radii.z * puff.radii.z)
			) * (-2.0 * FIELD_FALLOFF * contribution)
			gradient += puff.basis * local_gradient
	if gradient.length_squared() < 0.0000001:
		return Vector3.UP
	return -gradient.normalized()


func _sample_tone(point: Vector3, puffs: Array[CloudPuff]) -> float:
	var weighted_tone: float = 0.0
	var weight: float = 0.0
	for puff: CloudPuff in puffs:
		var local: Vector3 = puff.inverse_basis * (point - puff.center)
		var distance_squared: float = (
			local.x * local.x / (puff.radii.x * puff.radii.x)
			+ local.y * local.y / (puff.radii.y * puff.radii.y)
			+ local.z * local.z / (puff.radii.z * puff.radii.z)
		)
		if distance_squared < 3.2:
			var influence: float = puff.strength * exp(-FIELD_FALLOFF * distance_squared)
			weighted_tone += puff.tone * influence
			weight += influence
	return weighted_tone / maxf(weight, 0.0001)


func _append_field_vertex(
		builder: SurfaceTool,
		puffs: Array[CloudPuff],
		position: Vector3,
		normal: Vector3,
		cloud_bottom: float,
		cloud_top: float,
		phase: float,
		density: float
	) -> void:
	var cloud_height: float = clampf(inverse_lerp(cloud_bottom, cloud_top, position.y), 0.0, 1.0)
	builder.set_normal(normal)
	builder.set_uv(Vector2(position.x, position.z) * 0.01)
	builder.set_color(Color(cloud_height, _sample_tone(position, puffs), phase, density))
	builder.add_vertex(position)


func _update_palette() -> void:
	var hour: float = _cycle.hour if _cycle != null else 10.0
	var day_amount: float = smoothstep(5.0, 8.2, hour) * (1.0 - smoothstep(18.0, 21.2, hour))
	var dawn_amount: float = maxf(0.0, 1.0 - absf(hour - 6.25) / 2.15)
	var dusk_amount: float = maxf(0.0, 1.0 - absf(hour - 18.15) / 2.35)
	var warm_amount: float = maxf(dawn_amount, dusk_amount)

	var top_color: Color = Color(0.14, 0.19, 0.34).lerp(Color(0.73, 0.80, 0.86), day_amount)
	var middle_color: Color = Color(0.08, 0.12, 0.25).lerp(Color(0.52, 0.62, 0.72), day_amount)
	var underside_color: Color = Color(0.035, 0.055, 0.13).lerp(Color(0.22, 0.30, 0.42), day_amount)
	var rim_color: Color = Color(0.23, 0.31, 0.60).lerp(Color(0.88, 0.87, 0.79), day_amount)
	var warm_top: Color = Color(1.0, 0.72, 0.55) if dusk_amount >= dawn_amount else Color(1.0, 0.84, 0.68)
	var warm_middle: Color = Color(0.72, 0.43, 0.52) if dusk_amount >= dawn_amount else Color(0.82, 0.61, 0.58)
	var warm_under: Color = Color(0.25, 0.24, 0.40) if dusk_amount >= dawn_amount else Color(0.33, 0.36, 0.52)
	top_color = top_color.lerp(warm_top, warm_amount * 0.58)
	middle_color = middle_color.lerp(warm_middle, warm_amount * 0.50)
	underside_color = underside_color.lerp(warm_under, warm_amount * 0.42)
	rim_color = rim_color.lerp(Color(1.0, 0.58, 0.38), warm_amount * 0.68)

	var sun_direction: Vector3 = Vector3(0.35, 0.72, 0.28).normalized()
	var sun_strength: float = day_amount
	if _sun != null:
		sun_direction = _sun.global_transform.basis.z.normalized()
		sun_strength = clampf(_sun.light_energy / 1.8, 0.04, 1.0)
		# Preserve moonlit edge definition without making night clouds white.
		sun_strength = maxf(sun_strength, (1.0 - day_amount) * 0.12)

	_apply_palette_to_material(_core_material, top_color, middle_color, underside_color, rim_color, sun_direction, sun_strength)
	_apply_palette_to_material(_wisp_material, top_color, middle_color, underside_color, rim_color, sun_direction, sun_strength)


func _apply_palette_to_material(
		material: ShaderMaterial,
		top_color: Color,
		middle_color: Color,
		underside_color: Color,
		rim_color: Color,
		sun_direction: Vector3,
		sun_strength: float
	) -> void:
	material.set_shader_parameter("top_tint", top_color)
	material.set_shader_parameter("middle_tint", middle_color)
	material.set_shader_parameter("underside_tint", underside_color)
	material.set_shader_parameter("rim_tint", rim_color)
	material.set_shader_parameter("sun_direction", sun_direction)
	material.set_shader_parameter("sun_strength", sun_strength)

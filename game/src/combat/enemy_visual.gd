class_name EnemyVisual
extends Node3D
## Species-specific, true-scale procedural meadow creatures.
##
## The original Combat-v1 renderer selected one of three placeholder blobs by
## behavior. This implementation dispatches on stable content ID and builds a
## complete anatomical silhouette in metres: articulated limbs, eyes, ears,
## tails, bills, webbing, feather groups, coat detail, horns, gills, antlers,
## scutes, bells, and species-specific surface response. Unknown future IDs
## still receive the old behavior-readable fallback.

const CREATURE_SHADER := "res://assets/shaders/creature_surface.gdshader"
const TOON_SHADER := "res://assets/shaders/toon.gdshader"

# Combat-facing dimensions, populated by each known species builder.
var height: float = 0.9
var body_radius: float = 0.32
var body_height: float = 1.0
var body_center_y: float = 0.5
var body_length: float = 0.0
var melee_width: float = 1.1
var melee_height: float = 1.2
var melee_reach: float = 1.9
var melee_origin_y: float = 0.7
var muzzle_local_position: Vector3 = Vector3(0.0, 0.8, -0.35)

var _monster_id: String = ""
var _behavior: String = "swarm"
var _variant: String = ""
var _time: float = 0.0
var _flash: float = 0.0
var _telegraph: float = 0.0
var _seed: float = 0.0
var _gait_rate: float = 7.0
var _materials: Array[ShaderMaterial] = []
var _motions: Array[Dictionary] = []


func setup(monster_id: String, behavior: String, base_color: Color, accent: Color,
		fallback_size: float, variant: String = "") -> void:
	_monster_id = monster_id
	_behavior = behavior
	_variant = variant
	_seed = randf_range(0.0, 80.0)
	match monster_id:
		"mon_meanwing_finch":
			_build_mean_seeking_finch()
		"mon_trail_loop_leveret":
			_build_overfit_loop_leveret()
		"mon_patchmunch_bramblehog":
			_build_mini_batch_bramblehog()
		"mon_middleset_mossram":
			_build_centroid_mossram()
		"mon_rustlewatch_prowler":
			_build_single_feature_prowler()
		"mon_lilywise_newt":
			_build_k_nearest_newt()
		"mon_lastlook_jackdaw":
			_build_recency_bias_jackdaw()
		"mon_brackenhoof_keeper_of_forks":
			_build_brackenhoof()
		_:
			_build_behavior_fallback(behavior, base_color, accent, fallback_size)
	match monster_id:
		"mon_trail_loop_leveret":
			_apply_anatomical_scale(Vector3(0.72, 0.80, 0.69))
		"mon_patchmunch_bramblehog":
			_apply_anatomical_scale(Vector3(0.78, 0.78, 0.63))
		"mon_middleset_mossram":
			_apply_anatomical_scale(Vector3(0.85, 0.76, 0.74))
		"mon_rustlewatch_prowler":
			_apply_anatomical_scale(Vector3(1.0, 1.0, 0.74))
		"mon_lilywise_newt":
			_apply_anatomical_scale(Vector3(0.65, 0.80, 0.57))
		"mon_lastlook_jackdaw":
			_apply_anatomical_scale(Vector3(1.0, 1.0, 0.58))
		"mon_brackenhoof_keeper_of_forks":
			_apply_anatomical_scale(Vector3(1.0, 0.91, 0.83))


func _apply_anatomical_scale(scale_value: Vector3) -> void:
	# Visual geometry is authored in metres. Non-uniform correction brings each
	# source-space span to the field-guide dimensions without changing combat AI.
	scale = scale_value
	height *= scale_value.y
	body_radius *= scale_value.x
	body_height *= scale_value.y
	body_center_y *= scale_value.y
	body_length *= scale_value.z
	melee_width *= scale_value.x
	melee_height *= scale_value.y
	melee_origin_y *= scale_value.y


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta * 6.5)
	var movement: float = 0.0
	var body := get_parent() as CharacterBody3D
	if body != null:
		movement = clampf(Vector2(body.velocity.x, body.velocity.z).length() / 4.5, 0.0, 1.0)

	for motion: Dictionary in _motions:
		var node := motion["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var base_pos: Vector3 = motion["position"]
		var base_rot: Vector3 = motion["rotation"]
		var base_scale: Vector3 = motion["scale"]
		var amount: float = float(motion["amount"])
		var rate: float = float(motion["rate"])
		var phase: float = float(motion["phase"])
		var axis: Vector3 = motion["axis"]
		var wave: float = sin(_time * rate + phase)
		var mode: String = str(motion["mode"])
		node.position = base_pos
		node.rotation = base_rot
		node.scale = base_scale
		match mode:
			"breathe":
				node.scale = base_scale * Vector3(1.0 + wave * amount * 0.35,
					1.0 + wave * amount, 1.0 + wave * amount * 0.55)
			"head":
				node.rotation += axis * (wave * amount + _telegraph * amount * 1.8)
			"ear":
				node.rotation += axis * (wave * amount + sin(_time * rate * 0.31 + phase) * amount * 0.35)
			"tail":
				node.rotation += axis * wave * amount * (0.35 + movement * 0.65)
			"leg":
				node.rotation += axis * sin(_time * (_gait_rate + movement * _gait_rate) + phase) \
					* amount * (0.12 + movement * 0.88)
			"wing":
				node.rotation += axis * (sin(_time * rate + phase) * amount * (0.35 + movement * 0.65)
					+ _telegraph * amount * 0.45)
			"hover":
				node.position = base_pos + axis * wave * amount
			"gill":
				node.scale = base_scale * (1.0 + wave * amount + _telegraph * amount * 0.7)
			"flock":
				var drift := Vector3(sin(_time * rate + phase), sin(_time * rate * 1.7 + phase),
					cos(_time * rate * 0.83 + phase)) * amount
				var centered := Vector3(base_pos.x * 0.24, base_pos.y, base_pos.z * 0.24)
				node.position = (base_pos + drift).lerp(centered + drift * 0.15, _telegraph)
			"bell":
				node.rotation += axis * wave * amount * (0.25 + movement * 0.75 + _telegraph * 0.8)

	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("hit_flash", _flash)
		material.set_shader_parameter("telegraph", _telegraph)


func flash() -> void:
	_flash = 1.0


func set_telegraph(amount: float) -> void:
	_telegraph = clampf(amount, 0.0, 1.0)


# -----------------------------------------------------------------------------
# Materials

func _surface(base: Color, detail: Color, options: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(CREATURE_SHADER) as Shader
	var variant_weight: float = float(options.get("variant_weight", 0.45))
	base = _variant_color(base, variant_weight)
	detail = _variant_color(detail, variant_weight * 0.8)
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("detail_color", detail)
	material.set_shader_parameter("detail_mix", float(options.get("detail_mix", 0.25)))
	material.set_shader_parameter("pattern_type", int(options.get("pattern", 0)))
	material.set_shader_parameter("pattern_scale", float(options.get("scale", 12.0)))
	material.set_shader_parameter("pattern_strength", float(options.get("strength", 0.25)))
	material.set_shader_parameter("micro_detail", float(options.get("micro", 0.12)))
	material.set_shader_parameter("seed_offset", _seed + float(_materials.size()) * 7.13)
	material.set_shader_parameter("surface_roughness", float(options.get("roughness", 0.78)))
	material.set_shader_parameter("surface_specular", float(options.get("specular", 0.28)))
	material.set_shader_parameter("surface_metallic", float(options.get("metallic", 0.0)))
	material.set_shader_parameter("wetness", clampf(float(options.get("wetness", 0.0))
		+ (0.35 if _variant == "weather" else 0.0), 0.0, 1.0))
	material.set_shader_parameter("micro_bump", float(options.get("bump", 0.045)))
	material.set_shader_parameter("fuzz", float(options.get("fuzz", 0.2)))
	material.set_shader_parameter("subsurface", float(options.get("subsurface", 0.0)))
	material.set_shader_parameter("sheen_color", options.get("sheen", Color(0.65, 0.75, 1.0)))
	material.set_shader_parameter("telegraph_gain", float(options.get("telegraph_gain", 1.0)))
	material.set_shader_parameter("corruption", 1.0 if _variant == "corrupted" else 0.0)
	_materials.append(material)
	return material


func _variant_color(color: Color, weight: float) -> Color:
	match _variant:
		"golden":
			return color.lerp(Color(0.96, 0.73, 0.18), clampf(weight, 0.0, 0.72))
		"night":
			return color.darkened(0.22).lerp(Color(0.18, 0.25, 0.48), weight * 0.25)
		"corrupted":
			return color.lerp(Color(0.24, 0.06, 0.31), weight * 0.25)
		"weather":
			return color.darkened(weight * 0.12)
		_:
			return color


func _standard(color: Color, roughness: float = 0.35, metallic: float = 0.0,
		emission_energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = _variant_color(color, 0.18)
	material.roughness = roughness
	material.metallic = metallic
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material


# -----------------------------------------------------------------------------
# Geometry and animation helpers

func _node(parent: Node3D, node_name: String, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	result.name = node_name
	result.position = pos
	result.rotation = rot
	parent.add_child(result)
	return result


func _motion(node: Node3D, mode: String, amount: float, rate: float,
		phase: float = 0.0, axis: Vector3 = Vector3(1.0, 0.0, 0.0)) -> void:
	_motions.append({
		"node": node,
		"mode": mode,
		"amount": amount,
		"rate": rate,
		"phase": phase,
		"axis": axis,
		"position": node.position,
		"rotation": node.rotation,
		"scale": node.scale,
	})


func _ellipsoid(parent: Node3D, part_name: String, pos: Vector3, dimensions: Vector3,
		material: Material, segments: int = 32, rings: int = 18) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return _mesh(parent, part_name, mesh, pos, Vector3.ZERO, dimensions, material)


func _box(parent: Node3D, part_name: String, pos: Vector3, dimensions: Vector3,
		material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	return _mesh(parent, part_name, mesh, pos, rot, dimensions, material)


func _disc(parent: Node3D, part_name: String, pos: Vector3, radius: float, depth: float,
		material: Material, rot: Vector3 = Vector3.ZERO, segments: int = 24) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = segments
	return _mesh(parent, part_name, mesh, pos, rot, Vector3.ONE, material)


func _segment(parent: Node3D, part_name: String, start: Vector3, finish: Vector3,
		radius: float, material: Material, segments: int = 18, end_radius: float = -1.0) -> MeshInstance3D:
	var direction: Vector3 = finish - start
	var length: float = direction.length()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if end_radius < 0.0 else end_radius
	mesh.height = length
	mesh.radial_segments = segments
	var result := _mesh(parent, part_name, mesh, (start + finish) * 0.5, Vector3.ZERO,
		Vector3.ONE, material)
	if length > 0.0001:
		result.quaternion = Quaternion(Vector3.UP, direction / length)
	return result


func _cone(parent: Node3D, part_name: String, base: Vector3, tip: Vector3,
		radius: float, material: Material, segments: int = 18) -> MeshInstance3D:
	return _segment(parent, part_name, base, tip, radius, material, segments, 0.0)


func _torus(parent: Node3D, part_name: String, pos: Vector3, inner: float, outer: float,
		material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 32
	mesh.ring_segments = 16
	return _mesh(parent, part_name, mesh, pos, rot, Vector3.ONE, material)


func _mesh(parent: Node3D, part_name: String, mesh: Mesh, pos: Vector3, rot: Vector3,
		scale_value: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = part_name
	result.mesh = mesh
	result.position = pos
	result.rotation = rot
	result.scale = scale_value
	result.material_override = material
	parent.add_child(result)
	if material is ShaderMaterial:
		result.set_instance_shader_parameter("pattern_metric", scale_value)
		result.set_instance_shader_parameter("pattern_offset", pos)
	return result


func _xform(pos: Vector3, rot: Vector3, scale_value: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scale_value), pos)


func _aligned_xform(pos: Vector3, direction: Vector3, scale_value: Vector3,
		twist: float = 0.0) -> Transform3D:
	var axis := direction.normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.UP
	var basis := Basis(Quaternion(Vector3.UP, axis))
	if absf(twist) > 0.0001:
		basis = Basis(Quaternion(axis, twist)) * basis
	return Transform3D(basis.scaled(scale_value), pos)


func _hash01(value: float) -> float:
	return fposmod(sin(value * 12.9898 + _seed * 0.173) * 43758.5453, 1.0)


func _coat_strands(parent: Node3D, part_name: String, center: Vector3, dimensions: Vector3,
		material: Material, count: int, strand_length: float, strand_width: float,
		seed_shift: float = 0.0, layback: float = 0.10) -> void:
	# Fibonacci-distributed guard hairs follow the ellipsoid normal instead of
	# floating as a shell. Thousands remain one draw call through MultiMesh.
	var transforms: Array = []
	for i in count:
		var u: float = -0.94 + 1.88 * (float(i) + 0.5) / float(count)
		var theta: float = fmod(float(i) * 2.399963 + seed_shift, TAU)
		var radial: float = sqrt(maxf(0.0, 1.0 - u * u))
		var sphere_point := Vector3(cos(theta) * radial, u, sin(theta) * radial)
		var surface := center + sphere_point * dimensions * 0.5
		var normal := Vector3(
			sphere_point.x / maxf(dimensions.x, 0.001),
			sphere_point.y / maxf(dimensions.y, 0.001),
			sphere_point.z / maxf(dimensions.z, 0.001)).normalized()
		var grain_direction := (normal + Vector3(0.0, 0.05, layback)).normalized()
		var variance: float = 0.72 + _hash01(float(i) + seed_shift * 11.0) * 0.48
		var length_value: float = strand_length * variance
		var width_value: float = strand_width * (0.78 + _hash01(float(i) * 1.71 + 9.0) * 0.44)
		transforms.append(_aligned_xform(surface + grain_direction * length_value * 0.48,
			grain_direction, Vector3(width_value, length_value, width_value),
			_hash01(float(i) * 0.63 + seed_shift) * TAU))
	_multi_cones(parent, part_name, transforms, material, false, 5)


func _multi_ellipsoids(parent: Node3D, part_name: String, transforms: Array,
		material: Material, shadow: bool = true, segments: int = 12, rings: int = 8) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return _multimesh(parent, part_name, mesh, transforms, material, shadow)


func _multi_cones(parent: Node3D, part_name: String, transforms: Array,
		material: Material, shadow: bool = false, segments: int = 8) -> MultiMeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = 0.5
	mesh.top_radius = 0.0
	mesh.height = 1.0
	mesh.radial_segments = segments
	return _multimesh(parent, part_name, mesh, transforms, material, shadow)


func _multi_tori(parent: Node3D, part_name: String, transforms: Array,
		material: Material, shadow: bool = true) -> MultiMeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.24
	mesh.outer_radius = 0.50
	mesh.rings = 14
	mesh.ring_segments = 8
	return _multimesh(parent, part_name, mesh, transforms, material, shadow)


func _multi_wool_curls(parent: Node3D, part_name: String, transforms: Array,
		material: Material, shadow: bool = true) -> MultiMeshInstance3D:
	# One physical fibre bundle coils 1.25 turns from a buried root to a loose
	# tip. MultiMesh repeats the same smooth tube thousands of times cheaply.
	const PATH_SEGMENTS := 12
	const SIDES := 5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for path_index in PATH_SEGMENTS + 1:
		var t: float = float(path_index) / float(PATH_SEGMENTS)
		var angle: float = t * TAU * 1.25
		var center := Vector3(cos(angle) * 0.32, t - 0.50, sin(angle) * 0.32)
		var tangent := Vector3(-sin(angle) * TAU * 1.25 * 0.32, 1.0,
			cos(angle) * TAU * 1.25 * 0.32).normalized()
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = tangent.cross(Vector3.FORWARD)
		side = side.normalized()
		var binormal := side.cross(tangent).normalized()
		for ring_index in SIDES:
			var ring_angle: float = TAU * float(ring_index) / float(SIDES)
			var ring_normal := side * cos(ring_angle) + binormal * sin(ring_angle)
			vertices.append(center + ring_normal * 0.11)
			normals.append(ring_normal)
			uvs.append(Vector2(float(ring_index) / float(SIDES), t))
	for path_index in PATH_SEGMENTS:
		for ring_index in SIDES:
			var next_ring: int = (ring_index + 1) % SIDES
			var a: int = path_index * SIDES + ring_index
			var b: int = path_index * SIDES + next_ring
			var c: int = (path_index + 1) * SIDES + ring_index
			var d: int = (path_index + 1) * SIDES + next_ring
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(b); indices.append(c); indices.append(d)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _multimesh(parent, part_name, mesh, transforms, material, shadow)


func _multi_feathers(parent: Node3D, part_name: String, transforms: Array,
		material: Material, shadow: bool = true) -> MultiMeshInstance3D:
	# A thin tapered prism gives every primary a crisp vane edge and a physical
	# central thickness; flattened spheres made wings read like paddles.
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.0, 0.12, 1.0)
	mesh.left_to_right = 0.5
	mesh.subdivide_width = 2
	mesh.subdivide_height = 1
	mesh.subdivide_depth = 3
	return _multimesh(parent, part_name, mesh, transforms, material, shadow)


func _multimesh(parent: Node3D, part_name: String, mesh: Mesh, transforms: Array,
		material: Material, shadow: bool) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var result := MultiMeshInstance3D.new()
	result.name = part_name
	result.multimesh = multi
	result.material_override = material
	if not shadow:
		result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result


func _loft(parent: Node3D, part_name: String, sections: Array, material: Material,
		radial_segments: int = 36) -> MeshInstance3D:
	# Smooth, continuous anatomy along local Z. Each section is
	# {"p": Vector3 centre, "r": Vector2(horizontal radius, vertical radius)}.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var previous_side := Vector3.ZERO
	for section_index in sections.size():
		var section: Dictionary = sections[section_index]
		var center: Vector3 = section["p"]
		var radius: Vector2 = section["r"]
		var previous_center: Vector3 = sections[maxi(0, section_index - 1)]["p"]
		var next_center: Vector3 = sections[mini(sections.size() - 1, section_index + 1)]["p"]
		var tangent: Vector3 = (next_center - previous_center).normalized()
		if tangent.length_squared() < 0.5:
			tangent = Vector3.FORWARD
		# Parallel-transport the ring frame down the centreline. Rebuilding every
		# ring against world-up makes a near-vertical ankle cross the pole and
		# suddenly flips the section 180 degrees.
		var side := Vector3.ZERO
		if previous_side.length_squared() > 0.5:
			var transported: Vector3 = previous_side - tangent * previous_side.dot(tangent)
			if transported.length_squared() > 0.0001:
				side = transported.normalized()
		if side.length_squared() < 0.5:
			var frame_reference := Vector3.UP
			if absf(tangent.dot(frame_reference)) > 0.92:
				frame_reference = Vector3.FORWARD
			side = tangent.cross(frame_reference).normalized()
		if previous_side.length_squared() > 0.5 and side.dot(previous_side) < 0.0:
			side = -side
		previous_side = side
		var vertical: Vector3 = side.cross(tangent).normalized()
		for ring_index in radial_segments:
			var angle: float = TAU * float(ring_index) / float(radial_segments)
			var c: float = cos(angle)
			var s: float = sin(angle)
			vertices.append(center + side * c * radius.x + vertical * s * radius.y)
			uvs.append(Vector2(float(ring_index) / float(radial_segments),
				float(section_index) / float(maxi(1, sections.size() - 1))))
	for section_index in sections.size() - 1:
		for ring_index in radial_segments:
			var next_ring: int = (ring_index + 1) % radial_segments
			var a: int = section_index * radial_segments + ring_index
			var b: int = section_index * radial_segments + next_ring
			var c: int = (section_index + 1) * radial_segments + ring_index
			var d: int = (section_index + 1) * radial_segments + next_ring
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(b); indices.append(c); indices.append(d)
	# Average the real triangle normals instead of approximating them from the
	# cross-section alone. That approximation ignored the changing section radii
	# and bent centreline, so tapered bodies caught direct light as pale bands.
	# Area-weighted face accumulation keeps joints, shoulders, and haunches smooth
	# while preserving the stronger planes around hooves and narrow limbs.
	var normal_accumulator: Array[Vector3] = []
	normal_accumulator.resize(vertices.size())
	normal_accumulator.fill(Vector3.ZERO)
	for triangle_start in range(0, indices.size(), 3):
		var ia: int = indices[triangle_start]
		var ib: int = indices[triangle_start + 1]
		var ic: int = indices[triangle_start + 2]
		# Godot treats clockwise ArrayMesh triangles as front-facing. The usual
		# counter-clockwise cross product therefore points into the creature,
		# turning the shader's view-angle fur sheen fully on and washing coats
		# lavender. Flip only the lighting normal; keep the visible winding.
		var face_normal: Vector3 = (vertices[ic] - vertices[ia]).cross(vertices[ib] - vertices[ia])
		if face_normal.length_squared() > 0.00000001:
			normal_accumulator[ia] += face_normal
			normal_accumulator[ib] += face_normal
			normal_accumulator[ic] += face_normal
	for vertex_index in vertices.size():
		var smooth_normal: Vector3 = normal_accumulator[vertex_index].normalized()
		if smooth_normal.length_squared() < 0.5:
			smooth_normal = Vector3.UP
		normals.append(smooth_normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return _mesh(parent, part_name, mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, material)


func _tube(parent: Node3D, part_name: String, points: Array[Vector3], radii: Array[float],
		material: Material, sides: int = 16) -> MeshInstance3D:
	var sections: Array = []
	for i in points.size():
		sections.append({"p": points[i], "r": Vector2(radii[i], radii[i])})
	return _loft(parent, part_name, sections, material, sides)


func _eyes(parent: Node3D, center: Vector3, spacing: float, eye_size: Vector3,
		iris: Color, pupil_size: Vector3 = Vector3(0.018, 0.024, 0.012),
		lateral_gaze: float = 0.45) -> void:
	var sclera := _standard(Color(0.018, 0.022, 0.021), 0.08)
	var iris_mat := _standard(iris.darkened(0.22), 0.07, 0.0, 0.16)
	var pupil_mat := _standard(Color(0.008, 0.009, 0.012), 0.05)
	var glint := _standard(Color(0.88, 0.94, 1.0), 0.02, 0.0, 0.42)
	for side: int in [-1, 1]:
		var eye_pos := center + Vector3(spacing * 0.5 * float(side), 0.0, 0.0)
		var globe_size := Vector3(eye_size.x, eye_size.y, eye_size.z * 0.68)
		_ellipsoid(parent, "Eye_%d" % side, eye_pos, globe_size, sclera, 24, 14)
		# Rotate a local gaze plane so iris, pupil, and catchlight stay tangent to
		# the eye. Translating axis-aligned discs sideways made far eyes detach.
		var yaw: float = -atan(float(side) * lateral_gaze)
		var gaze := _node(parent, "Gaze_%d" % side, eye_pos, Vector3(0.0, yaw, 0.0))
		var front := Vector3(0.0, 0.0, -globe_size.z * 0.47)
		_ellipsoid(gaze, "Iris", front, pupil_size * 1.7, iris_mat, 20, 12)
		_ellipsoid(gaze, "Pupil", front + Vector3(0.0, 0.0, -pupil_size.z * 0.34),
			pupil_size, pupil_mat, 18, 10)
		_ellipsoid(gaze, "Catchlight",
			front + Vector3(-pupil_size.x * 0.35, pupil_size.y * 0.35, -pupil_size.z * 0.72),
			pupil_size * 0.15, glint, 10, 6)


func _four_legs(parent: Node3D, points: Array[Vector3], upper: float, lower: float,
		radius: float, leg_mat: Material, hoof_mat: Material, hoof_size: Vector3,
		phase_offset: float = 0.0, style: String = "generic") -> void:
	for i in points.size():
		var anchor: Vector3 = points[i]
		var pivot := _node(parent, "LegPivot_%d" % i, anchor)
		var is_fore: bool = i < 2
		var side_sign: float = -1.0 if i % 2 == 0 else 1.0
		var total: float = upper + lower
		var knee := Vector3.ZERO
		var hock := Vector3.ZERO
		var ankle := Vector3.ZERO
		var radii: Array[float] = []
		match style:
			"leveret":
				if is_fore:
					knee = Vector3(0.0, -upper * 0.52, -0.020)
					hock = Vector3(0.0, -upper, -0.006)
					ankle = Vector3(0.0, -total, -0.050)
				else:
					knee = Vector3(0.012 * side_sign, -upper * 0.36, 0.078)
					hock = Vector3(0.006 * side_sign, -upper * 0.74, 0.125)
					ankle = Vector3(0.0, -total, -0.020)
				radii = [radius * 1.30, radius * 1.14, radius * 0.70, radius * 0.43]
			"hog":
				knee = Vector3(0.008 * side_sign, -upper * 0.52, -0.025 if is_fore else 0.060)
				hock = Vector3(0.0, -upper, 0.005 if is_fore else 0.085)
				ankle = Vector3(0.0, -total, -0.025 if is_fore else 0.015)
				radii = [radius * 1.18, radius * 0.96, radius * 0.66, radius * 0.44]
			"ungulate", "elk":
				if is_fore:
					knee = Vector3(0.008 * side_sign, -upper * 0.57, -upper * 0.10)
					hock = Vector3(0.0, -upper, -upper * 0.04)
					ankle = Vector3(0.0, -total, -lower * 0.12)
				else:
					knee = Vector3(0.012 * side_sign, -upper * 0.43, upper * 0.22)
					hock = Vector3(0.0, -upper * 0.88, upper * 0.30)
					ankle = Vector3(0.0, -total, lower * 0.02)
				radii = [radius * 1.20, radius * 0.90, radius * 0.45, radius * 0.27]
			"feline":
				if is_fore:
					knee = Vector3(0.006 * side_sign, -upper * 0.54, 0.035)
					hock = Vector3(0.0, -upper, -0.015)
					ankle = Vector3(0.0, -total, -0.075)
				else:
					knee = Vector3(0.015 * side_sign, -upper * 0.40, 0.105)
					hock = Vector3(0.005 * side_sign, -upper * 0.80, 0.165)
					ankle = Vector3(0.0, -total, -0.055)
				radii = [radius * 1.25, radius * 0.92, radius * 0.56, radius * 0.36]
			_:
				knee = Vector3(0.0, -upper * 0.58, 0.035 if is_fore else -0.09)
				hock = Vector3(0.0, -upper, 0.055)
				ankle = hock + Vector3(0.0, -lower, -0.045 if is_fore else 0.10)
				radii = [radius * 1.08, radius, radius * 0.78, radius * 0.56]
		_tube(pivot, "AnatomicalLeg", [Vector3.ZERO, knee, hock, ankle], radii, leg_mat, 22)
		match style:
			"leveret":
				var paw_center := ankle + Vector3(0.0, -hoof_size.y * 0.12, -hoof_size.z * 0.30)
				_ellipsoid(pivot, "FurredPaw", paw_center, hoof_size, hoof_mat, 22, 12)
				for toe in 4:
					var toe_x: float = (float(toe) - 1.5) * hoof_size.x * 0.19
					_ellipsoid(pivot, "Toe_%d" % toe, paw_center + Vector3(toe_x, -hoof_size.y * 0.25,
						-hoof_size.z * 0.34), Vector3(hoof_size.x * 0.18, hoof_size.y * 0.24,
						hoof_size.z * 0.28), hoof_mat, 12, 7)
			"feline":
				var paw_center := ankle + Vector3(0.0, -hoof_size.y * 0.10, -hoof_size.z * 0.26)
				_ellipsoid(pivot, "PaddedPaw", paw_center, hoof_size, hoof_mat, 22, 12)
				for toe in 4:
					var toe_x: float = (float(toe) - 1.5) * hoof_size.x * 0.20
					var toe_pos := paw_center + Vector3(toe_x, -hoof_size.y * 0.10,
						-hoof_size.z * (0.35 + 0.05 * absf(float(toe) - 1.5)))
					_ellipsoid(pivot, "ToePad_%d" % toe, toe_pos,
						Vector3(hoof_size.x * 0.20, hoof_size.y * 0.44, hoof_size.z * 0.28),
						hoof_mat, 14, 8)
			"hog", "ungulate", "elk":
				for digit: int in [-1, 1]:
					var hoof_root := _node(pivot, "ClovenDigit_%d" % digit,
						ankle + Vector3(hoof_size.x * 0.24 * float(digit), -hoof_size.y * 0.12,
						-hoof_size.z * 0.22), Vector3(0.0, 0.11 * float(digit), 0.0))
					_loft(hoof_root, "TaperedHoofWall", [
						{"p": Vector3(0.0, 0.0, hoof_size.z * 0.10),
							"r": Vector2(hoof_size.x * 0.23, hoof_size.y * 0.46)},
						{"p": Vector3(0.0, -hoof_size.y * 0.05, -hoof_size.z * 0.20),
							"r": Vector2(hoof_size.x * 0.21, hoof_size.y * 0.43)},
						{"p": Vector3(0.0, -hoof_size.y * 0.20, -hoof_size.z * 0.54),
							"r": Vector2(hoof_size.x * 0.17, hoof_size.y * 0.33)},
						{"p": Vector3(0.0, -hoof_size.y * 0.28, -hoof_size.z * 0.78),
							"r": Vector2(hoof_size.x * 0.065, hoof_size.y * 0.15)},
					], hoof_mat, 10)
			_:
				_ellipsoid(pivot, "Hoof", ankle + Vector3(0.0, -hoof_size.y * 0.2,
					-hoof_size.z * 0.15), hoof_size, hoof_mat, 16, 10)
		_motion(pivot, "leg", 0.34, _gait_rate, phase_offset + (PI if i in [1, 2] else 0.0))


func _whiskers(parent: Node3D, center: Vector3, length: float, count: int = 4) -> void:
	var whisker_mat := _standard(Color(0.86, 0.82, 0.72), 0.5)
	for side: int in [-1, 1]:
		for i in count:
			var y: float = (float(i) - float(count - 1) * 0.5) * 0.012
			var start := center + Vector3(0.035 * float(side), y, 0.0)
			var finish := start + Vector3(length * float(side), y * 1.5, -length * 0.35)
			_segment(parent, "Whisker_%d_%d" % [side, i], start, finish, 0.0012, whisker_mat, 5)


# -----------------------------------------------------------------------------
# Mean-Seeking Finch — seven individually life-sized birds in one flock.

func _build_mean_seeking_finch() -> void:
	height = 0.52
	body_radius = 0.48
	body_height = 0.52
	body_center_y = 0.28
	body_length = 0.90
	melee_width = 1.0
	melee_height = 0.7
	melee_reach = 1.15
	melee_origin_y = 0.28
	muzzle_local_position = Vector3(0.0, 0.34, -0.42)
	_gait_rate = 11.0
	var brown := _surface(Color("8a6b3e"), Color("523a24"), {"pattern": 4, "scale": 38.0,
		"strength": 0.34, "micro": 0.22, "roughness": 0.82, "fuzz": 0.52})
	var buff := _surface(Color("c9a66b"), Color("8f7045"), {"pattern": 4, "scale": 42.0,
		"strength": 0.22, "roughness": 0.86, "fuzz": 0.48})
	var wing := _surface(Color("1c2a38"), Color("667687"), {"pattern": 4, "scale": 54.0,
		"strength": 0.5, "roughness": 0.6, "fuzz": 0.32, "sheen": Color("8aa7c4")})
	var keratin := _surface(Color("c9b174"), Color("665839"), {"pattern": 3, "scale": 28.0,
		"roughness": 0.58, "fuzz": 0.02})
	var offsets: Array[Vector3] = [
		Vector3(-0.36, 0.27, 0.10), Vector3(-0.12, 0.39, -0.17), Vector3(0.14, 0.25, 0.12),
		Vector3(0.38, 0.34, -0.08), Vector3(-0.28, 0.18, -0.28), Vector3(0.29, 0.16, 0.27),
		Vector3(0.02, 0.48, 0.02), Vector3(-0.08, 0.13, 0.31), Vector3(0.19, 0.43, -0.31),
	]
	for i in offsets.size():
		var bird := _node(self, "Finch_%02d" % i, offsets[i], Vector3(0.0, (float(i) - 3.0) * 0.16, 0.0))
		bird.scale = Vector3.ONE * 0.58
		_motion(bird, "flock", 0.035, 1.8 + float(i) * 0.09, float(i) * 0.73)
		_build_finch_body(bird, brown, buff, wing, keratin, float(i) * 0.61)


func _build_finch_body(root: Node3D, brown: Material, buff: Material, wing_mat: Material,
		keratin: Material, phase: float) -> void:
	var body := _node(root, "BodyBreath")
	_ellipsoid(body, "Torso", Vector3(0.0, 0.0, 0.0), Vector3(0.068, 0.084, 0.125), brown, 24, 14)
	_ellipsoid(body, "Breast", Vector3(0.0, -0.004, -0.035), Vector3(0.058, 0.074, 0.072), buff, 22, 12)
	_motion(body, "breathe", 0.035, 4.8, phase)
	var head := _node(root, "Head", Vector3(0.0, 0.046, -0.061))
	_ellipsoid(head, "Skull", Vector3.ZERO, Vector3(0.054, 0.054, 0.059), brown, 24, 14)
	_cone(head, "UpperBeak", Vector3(0.0, 0.006, -0.027), Vector3(0.0, 0.001, -0.062), 0.014,
		keratin, 12)
	_cone(head, "LowerBeak", Vector3(0.0, -0.005, -0.025), Vector3(0.0, -0.004, -0.057), 0.010,
		keratin, 12)
	_eyes(head, Vector3(0.0, 0.012, -0.025), 0.038, Vector3(0.009, 0.010, 0.008),
		Color("6d542c"), Vector3(0.0035, 0.0045, 0.003), 0.65)
	_motion(head, "head", 0.08, 2.7, phase, Vector3(0.0, 1.0, 0.25))
	for side: int in [-1, 1]:
		var wing_pivot := _node(root, "Wing_%d" % side, Vector3(0.03 * float(side), 0.015, -0.004),
			Vector3(0.08, 0.0, -0.18 * float(side)))
		_ellipsoid(wing_pivot, "Covert", Vector3(0.018 * float(side), 0.0, 0.015),
			Vector3(0.026, 0.048, 0.092), wing_mat, 20, 12)
		var feathers: Array = []
		for f in 7:
			var spread: float = (float(f) - 3.0) * 0.006
			feathers.append(_xform(Vector3(0.018 * float(side) + spread * float(side), -0.006,
				0.025 + float(f) * 0.009), Vector3(0.08, 0.0, -0.08 * float(side)),
				Vector3(0.010, 0.008, 0.07 + float(f) * 0.004)))
		_multi_feathers(wing_pivot, "PrimaryFeathers", feathers, wing_mat, false)
		_motion(wing_pivot, "wing", 0.72, 10.5 + phase * 0.3, phase, Vector3(0.0, 0.0, float(side)))
	var tails: Array = []
	for f in 5:
		tails.append(_xform(Vector3((float(f) - 2.0) * 0.009, -0.006, 0.072),
			Vector3(0.10, 0.0, (float(f) - 2.0) * 0.07), Vector3(0.012, 0.008, 0.092)))
	_multi_feathers(root, "TailFeathers", tails, wing_mat, false)
	for side: int in [-1, 1]:
		_segment(root, "Tarsus_%d" % side, Vector3(0.014 * float(side), -0.038, -0.005),
			Vector3(0.016 * float(side), -0.072, -0.006), 0.003, keratin, 7)
		for toe in 3:
			var toe_x: float = (float(toe) - 1.0) * 0.008
			_segment(root, "Toe_%d_%d" % [side, toe], Vector3(0.016 * float(side), -0.071, -0.006),
				Vector3(0.016 * float(side) + toe_x, -0.073, -0.032), 0.0017, keratin, 5)


# -----------------------------------------------------------------------------
# Overfit Loop Leveret

func _build_overfit_loop_leveret() -> void:
	height = 0.41
	body_radius = 0.19
	body_height = 0.40
	body_center_y = 0.20
	body_length = 0.46
	melee_width = 0.52
	melee_height = 0.48
	melee_reach = 1.0
	melee_origin_y = 0.22
	muzzle_local_position = Vector3(0.0, 0.27, -0.31)
	_gait_rate = 8.4
	var fur := _surface(Color("a87446"), Color("6b452c"), {"pattern": 4, "scale": 27.0,
		"strength": 0.38, "micro": 0.24, "roughness": 0.88, "fuzz": 0.68})
	var cream := _surface(Color("d3b891"), Color("a48762"), {"pattern": 4, "scale": 30.0,
		"strength": 0.2, "roughness": 0.9, "fuzz": 0.62})
	var dark := _surface(Color("4b3326"), Color("211915"), {"pattern": 4, "scale": 32.0,
		"roughness": 0.82, "fuzz": 0.44})
	var ear_inner := _surface(Color("c98e86"), Color("7a4c4d"), {"pattern": 0, "scale": 20.0,
		"roughness": 0.58, "subsurface": 0.42, "fuzz": 0.16})
	var body := _node(self, "LeveretBody", Vector3(0.0, 0.22, 0.02))
	_loft(body, "ContinuousTorso", [
		{"p": Vector3(0.0, 0.0, -0.22), "r": Vector2(0.018, 0.025)},
		{"p": Vector3(0.0, 0.0, -0.17), "r": Vector2(0.075, 0.085)},
		{"p": Vector3(0.0, 0.005, -0.08), "r": Vector2(0.092, 0.105)},
		{"p": Vector3(0.0, 0.0, 0.02), "r": Vector2(0.082, 0.095)},
		{"p": Vector3(0.0, 0.015, 0.13), "r": Vector2(0.122, 0.142)},
		{"p": Vector3(0.0, 0.005, 0.22), "r": Vector2(0.096, 0.112)},
		{"p": Vector3(0.0, 0.0, 0.28), "r": Vector2(0.018, 0.024)},
	], fur, 40)
	_ellipsoid(body, "Belly", Vector3(0.0, -0.065, -0.045), Vector3(0.16, 0.10, 0.29), cream, 28, 16)
	for side: int in [-1, 1]:
		_ellipsoid(body, "Haunch_%d" % side, Vector3(0.075 * float(side), 0.0, 0.105),
			Vector3(0.12, 0.17, 0.18), fur, 28, 16)
	_motion(body, "breathe", 0.035, 3.2)
	var head := _node(self, "LeveretHead", Vector3(0.0, 0.315, -0.215), Vector3(-0.08, 0.0, 0.0))
	_ellipsoid(head, "Skull", Vector3.ZERO, Vector3(0.145, 0.15, 0.17), fur, 32, 18)
	for muzzle_side: int in [-1, 1]:
		_ellipsoid(head, "MuzzleLobe_%d" % muzzle_side,
			Vector3(0.027 * float(muzzle_side), -0.035, -0.098), Vector3(0.066, 0.068, 0.104),
			cream, 24, 14)
	_ellipsoid(head, "Chin", Vector3(0.0, -0.071, -0.096), Vector3(0.065, 0.032, 0.072),
		cream, 20, 12)
	_ellipsoid(head, "Nose", Vector3(0.0, -0.025, -0.145), Vector3(0.043, 0.032, 0.028),
		_surface(Color("392a25"), Color("171113"), {"pattern": 2, "scale": 32.0,
			"roughness": 0.24, "wetness": 0.34, "fuzz": 0.02}), 20, 12)
	_segment(head, "SplitUpperLip", Vector3(0.0, -0.043, -0.151), Vector3(0.0, -0.074, -0.136),
		0.0013, _standard(Color("3b2822"), 0.48), 5)
	_eyes(head, Vector3(0.0, 0.025, -0.063), 0.118, Vector3(0.019, 0.022, 0.016),
		Color("876a31"), Vector3(0.0055, 0.009, 0.0045), 0.76)
	_whiskers(head, Vector3(0.0, -0.035, -0.13), 0.11, 5)
	_motion(head, "head", 0.13, 2.2, 0.4, Vector3(1.0, 0.3, 0.0))
	for side: int in [-1, 1]:
		var ear := _node(head, "Ear_%d" % side, Vector3(0.047 * float(side), 0.06, 0.005),
			Vector3(-0.08, 0.0, 0.12 * float(side)))
		_loft(ear, "TaperedOuterEar", [
			{"p": Vector3(0.0, 0.0, 0.0), "r": Vector2(0.020, 0.018)},
			{"p": Vector3(0.0, 0.055, 0.0), "r": Vector2(0.033, 0.025)},
			{"p": Vector3(0.0, 0.145, 0.0), "r": Vector2(0.031, 0.021)},
			{"p": Vector3(0.0, 0.215, 0.0), "r": Vector2(0.018, 0.013)},
			{"p": Vector3(0.0, 0.238, 0.0), "r": Vector2(0.003, 0.004)},
		], fur, 28)
		_loft(ear, "VascularInnerEar", [
			{"p": Vector3(0.0, 0.020, -0.019), "r": Vector2(0.010, 0.003)},
			{"p": Vector3(0.0, 0.080, -0.022), "r": Vector2(0.022, 0.004)},
			{"p": Vector3(0.0, 0.155, -0.019), "r": Vector2(0.018, 0.0035)},
			{"p": Vector3(0.0, 0.205, -0.013), "r": Vector2(0.004, 0.002)},
		], ear_inner, 22)
		_motion(ear, "ear", 0.19, 1.7, float(side) * 0.9, Vector3(0.2, 0.35 * float(side), 1.0))
	var leg_points: Array[Vector3] = [Vector3(-0.06, 0.22, -0.115), Vector3(0.06, 0.22, -0.115),
		Vector3(-0.085, 0.23, 0.12), Vector3(0.085, 0.23, 0.12)]
	_four_legs(self, leg_points, 0.12, 0.10, 0.025, fur, dark,
		Vector3(0.055, 0.035, 0.13), 0.0, "leveret")
	_ellipsoid(self, "Tail", Vector3(0.0, 0.245, 0.245), Vector3(0.11, 0.12, 0.10), cream, 24, 14)
	_coat_strands(body, "TorsoGuardFur", Vector3(0.0, 0.008, 0.025), Vector3(0.235, 0.285, 0.50),
		fur, 2200, 0.009, 0.00035, 1.2, 0.16)
	_coat_strands(head, "FacialGuardFur", Vector3.ZERO, Vector3(0.148, 0.153, 0.174),
		fur, 700, 0.006, 0.00028, 3.4, 0.10)


# -----------------------------------------------------------------------------
# Mini-Batch Bramblehog

func _build_mini_batch_bramblehog() -> void:
	height = 0.43
	body_radius = 0.25
	body_height = 0.46
	body_center_y = 0.23
	body_length = 0.72
	melee_width = 0.7
	melee_height = 0.52
	melee_reach = 1.05
	melee_origin_y = 0.25
	muzzle_local_position = Vector3(0.0, 0.23, -0.47)
	_gait_rate = 7.2
	var coat := _surface(Color("6b3529"), Color("2c201d"), {"pattern": 4, "scale": 23.0,
		"strength": 0.52, "micro": 0.26, "roughness": 0.9, "fuzz": 0.7})
	var guard := _surface(Color("2a201c"), Color("7b4e35"), {"pattern": 4, "scale": 45.0,
		"strength": 0.5, "roughness": 0.82, "fuzz": 0.78})
	var mud := _surface(Color("46362b"), Color("211b18"), {"pattern": 2, "scale": 15.0,
		"strength": 0.55, "roughness": 0.56, "wetness": 0.45})
	var burr := _surface(Color("6f7442"), Color("353b24"), {"pattern": 2, "scale": 26.0,
		"roughness": 0.88, "telegraph_gain": 1.6, "variant_weight": 0.75})
	var hoof := _surface(Color("26201d"), Color("5b4a3e"), {"pattern": 3, "scale": 30.0,
		"roughness": 0.62})
	var body := _node(self, "BramblehogBody", Vector3(0.0, 0.25, 0.02))
	_loft(body, "ContinuousWedgeBody", [
		{"p": Vector3(0.0, 0.0, -0.36), "r": Vector2(0.035, 0.045)},
		{"p": Vector3(0.0, 0.025, -0.29), "r": Vector2(0.17, 0.19)},
		{"p": Vector3(0.0, 0.035, -0.16), "r": Vector2(0.20, 0.215)},
		{"p": Vector3(0.0, 0.015, 0.02), "r": Vector2(0.19, 0.205)},
		{"p": Vector3(0.0, 0.0, 0.19), "r": Vector2(0.175, 0.19)},
		{"p": Vector3(0.0, -0.005, 0.32), "r": Vector2(0.11, 0.14)},
		{"p": Vector3(0.0, 0.0, 0.38), "r": Vector2(0.025, 0.035)},
	], coat, 42)
	_ellipsoid(body, "MudBelly", Vector3(0.0, -0.135, 0.03), Vector3(0.31, 0.10, 0.46), mud, 28, 16)
	_motion(body, "breathe", 0.022, 2.6)
	var head := _node(self, "BramblehogHead", Vector3(0.0, 0.265, -0.37), Vector3(-0.06, 0.0, 0.0))
	_loft(head, "TaperedWedgeHead", [
		{"p": Vector3(0.0, 0.0, 0.16), "r": Vector2(0.105, 0.105)},
		{"p": Vector3(0.0, 0.015, 0.08), "r": Vector2(0.150, 0.132)},
		{"p": Vector3(0.0, 0.0, -0.02), "r": Vector2(0.142, 0.124)},
		{"p": Vector3(0.0, -0.025, -0.12), "r": Vector2(0.112, 0.092)},
		{"p": Vector3(0.0, -0.035, -0.17), "r": Vector2(0.082, 0.065)},
	], coat, 38)
	var snout := _node(head, "Snout", Vector3(0.0, -0.045, -0.185))
	_loft(snout, "FlexibleTaperedSnout", [
		{"p": Vector3(0.0, 0.0, 0.090), "r": Vector2(0.088, 0.072)},
		{"p": Vector3(0.0, -0.002, 0.025), "r": Vector2(0.079, 0.061)},
		{"p": Vector3(0.0, -0.003, -0.060), "r": Vector2(0.061, 0.047)},
		{"p": Vector3(0.0, 0.0, -0.130), "r": Vector2(0.047, 0.036)},
	], coat, 30)
	var nose_material := _surface(Color("3a2925"), Color("171112"), {"pattern": 2, "scale": 28.0,
		"roughness": 0.22, "wetness": 0.48, "fuzz": 0.01, "bump": 0.075})
	_disc(snout, "NoseDisc", Vector3(0.0, 0.0, -0.143), 0.033, 0.012,
		nose_material,
		Vector3(PI * 0.5, 0.0, 0.0), 24)
	for nostril_side: int in [-1, 1]:
		_ellipsoid(snout, "Nostril_%d" % nostril_side,
			Vector3(0.015 * float(nostril_side), 0.005, -0.151), Vector3(0.008, 0.005, 0.004),
			_standard(Color("0c0808"), 0.12), 14, 8)
	_motion(snout, "head", 0.10, 3.7, 0.0, Vector3(1.0, 0.0, 0.0))
	_eyes(head, Vector3(0.0, 0.038, -0.105), 0.195, Vector3(0.019, 0.021, 0.016),
		Color("76612d"), Vector3(0.0055, 0.008, 0.0045), 0.66)
	for side: int in [-1, 1]:
		var ear := _node(head, "Ear_%d" % side, Vector3(0.11 * float(side), 0.07, -0.025),
			Vector3(0.0, 0.0, 0.45 * float(side)))
		_ellipsoid(ear, "Ear", Vector3.ZERO, Vector3(0.075, 0.105, 0.028), coat, 22, 12)
		_motion(ear, "ear", 0.12, 2.1, float(side), Vector3(0.0, 0.6, 1.0))
	var leg_points: Array[Vector3] = [Vector3(-0.13, 0.25, -0.18), Vector3(0.13, 0.25, -0.18),
		Vector3(-0.13, 0.25, 0.18), Vector3(0.13, 0.25, 0.18)]
	_four_legs(self, leg_points, 0.13, 0.09, 0.038, coat, hoof,
		Vector3(0.060, 0.040, 0.080), 0.0, "hog")
	_coat_strands(body, "DenseUndercoat", Vector3(0.0, 0.015, 0.015), Vector3(0.405, 0.425, 0.72),
		coat, 2200, 0.011, 0.00055, 7.7, 0.22)
	# Irregular dorsal guard hairs follow the arched hide. A golden-angle layout
	# avoids the old picket-fence rows while retaining a single batched draw.
	var quills: Array = []
	for i in 210:
		var x_unit: float = _hash01(float(i) * 1.37 + 4.0) * 2.0 - 1.0
		var x: float = x_unit * 0.185
		var z: float = -0.29 + _hash01(float(i) * 2.11 + 18.0) * 0.61
		var arch: float = sqrt(maxf(0.0, 1.0 - x_unit * x_unit))
		var surface := Vector3(x, 0.405 + arch * 0.050 + sin(z * 19.0) * 0.006, z)
		var normal := Vector3(x_unit * 0.72, 0.72 + arch * 0.42,
			(_hash01(float(i) * 0.73) - 0.5) * 0.22).normalized()
		var quill_length: float = 0.043 + _hash01(float(i) * 3.19 + 2.0) * 0.048
		var quill_width: float = 0.0055 + _hash01(float(i) * 1.93 + 1.0) * 0.0032
		quills.append(_aligned_xform(surface + normal * quill_length * 0.48, normal,
			Vector3(quill_width, quill_length, quill_width), _hash01(float(i)) * TAU))
	_multi_cones(self, "GuardHairs", quills, guard, true, 7)
	var burrs: Array = []
	var burr_centers: Array[Vector3] = []
	for batch in 4:
		for i in 5:
			var x: float = (float(batch) - 1.5) * 0.09 + (float(i % 2) - 0.5) * 0.025
			var z: float = -0.17 + float(i) * 0.075
			var burr_center := Vector3(x, 0.466 + sin(float(i + batch)) * 0.010, z)
			burr_centers.append(burr_center)
			burrs.append(_xform(burr_center,
				Vector3(float(i), float(batch), 0.0), Vector3(0.026, 0.026, 0.026)))
	_multi_ellipsoids(self, "FourMiniBatchesOfBurrs", burrs, burr, true, 12, 8)
	var burr_spines: Array = []
	for burr_index in burr_centers.size():
		for spine in 9:
			var u: float = -0.72 + 1.44 * float(spine) / 8.0
			var theta: float = float(spine) * 2.399963 + float(burr_index) * 0.81
			var radial: float = sqrt(maxf(0.0, 1.0 - u * u))
			var direction := Vector3(cos(theta) * radial, u, sin(theta) * radial).normalized()
			var length_value: float = 0.011 + _hash01(float(spine + burr_index * 9)) * 0.006
			burr_spines.append(_aligned_xform(burr_centers[burr_index] + direction * 0.015,
				direction, Vector3(0.0018, length_value, 0.0018)))
	_multi_cones(self, "BurrHooks", burr_spines, burr, false, 5)


# -----------------------------------------------------------------------------
# Centroid Mossram

func _build_centroid_mossram() -> void:
	height = 1.02
	body_radius = 0.38
	body_height = 0.88
	body_center_y = 0.44
	body_length = 0.90
	melee_width = 0.9
	melee_height = 1.1
	melee_reach = 1.55
	melee_origin_y = 0.56
	muzzle_local_position = Vector3(0.0, 0.61, -0.72)
	_gait_rate = 6.0
	var wool := _surface(Color("77715f"), Color("45443b"), {"pattern": 2, "scale": 15.0,
		"strength": 0.56, "micro": 0.24, "roughness": 0.96, "fuzz": 0.88})
	var wool_fiber := _surface(Color("716b5b"), Color("575247"), {"pattern": 0, "scale": 34.0,
		"strength": 0.18, "detail_mix": 0.16, "micro": 0.10, "bump": 0.012,
		"roughness": 0.99, "specular": 0.18, "fuzz": 0.10})
	var face := _surface(Color("716250"), Color("3d342b"), {"pattern": 4, "scale": 22.0,
		"strength": 0.3, "roughness": 0.82, "fuzz": 0.46})
	var moss := _surface(Color("47673b"), Color("92a66b"), {"pattern": 2, "scale": 19.0,
		"strength": 0.72, "roughness": 0.94, "fuzz": 0.52, "telegraph_gain": 1.7})
	var horn := _surface(Color("b7aa8c"), Color("675f50"), {"pattern": 3, "scale": 32.0,
		"strength": 0.62, "roughness": 0.55, "fuzz": 0.03})
	var hoof := _surface(Color("292724"), Color("625c50"), {"pattern": 3, "scale": 24.0,
		"roughness": 0.62})
	var body := _node(self, "MossramBody", Vector3(0.0, 0.58, 0.03))
	_loft(body, "ContinuousBarrel", [
		{"p": Vector3(0.0, 0.0, -0.48), "r": Vector2(0.04, 0.05)},
		{"p": Vector3(0.0, 0.02, -0.39), "r": Vector2(0.25, 0.31)},
		{"p": Vector3(0.0, 0.02, -0.22), "r": Vector2(0.275, 0.32)},
		{"p": Vector3(0.0, 0.0, 0.02), "r": Vector2(0.27, 0.31)},
		{"p": Vector3(0.0, -0.01, 0.25), "r": Vector2(0.255, 0.29)},
		{"p": Vector3(0.0, -0.02, 0.43), "r": Vector2(0.18, 0.22)},
		{"p": Vector3(0.0, 0.0, 0.51), "r": Vector2(0.035, 0.045)},
	], wool, 44)
	_motion(body, "breathe", 0.04, 2.4)
	var neck := _node(self, "RamNeck", Vector3(0.0, 0.65, -0.43), Vector3(-0.25, 0.0, 0.0))
	_ellipsoid(neck, "NeckMass", Vector3.ZERO, Vector3(0.38, 0.48, 0.36), wool, 34, 20)
	var head := _node(self, "RamHead", Vector3(0.0, 0.70, -0.61), Vector3(-0.10, 0.0, 0.0))
	_ellipsoid(head, "Skull", Vector3.ZERO, Vector3(0.30, 0.34, 0.39), face, 36, 22)
	_ellipsoid(head, "Muzzle", Vector3(0.0, -0.075, -0.215), Vector3(0.215, 0.155, 0.245), face, 30, 18)
	var ram_nose := _surface(Color("3b312b"), Color("181313"), {"pattern": 2, "scale": 24.0,
		"roughness": 0.24, "wetness": 0.38, "fuzz": 0.01, "bump": 0.070})
	_disc(head, "Nose", Vector3(0.0, -0.065, -0.345), 0.057, 0.020,
		ram_nose,
		Vector3(PI * 0.5, 0.0, 0.0), 24)
	for nostril_side: int in [-1, 1]:
		_ellipsoid(head, "Nostril_%d" % nostril_side,
			Vector3(0.027 * float(nostril_side), -0.055, -0.357), Vector3(0.015, 0.009, 0.006),
			_standard(Color("0b0908"), 0.10), 14, 8)
	_eyes(head, Vector3(0.0, 0.035, -0.16), 0.250, Vector3(0.027, 0.026, 0.020),
		Color("b37a24"), Vector3(0.013, 0.0045, 0.0045), 0.76)
	_motion(head, "head", 0.18, 1.5, 0.0, Vector3(1.0, 0.15, 0.0))
	for side: int in [-1, 1]:
		var ear := _node(head, "Ear_%d" % side, Vector3(0.15 * float(side), 0.08, -0.02),
			Vector3(0.0, 0.0, 0.55 * float(side)))
		_ellipsoid(ear, "Ear", Vector3(0.055 * float(side), 0.0, 0.0), Vector3(0.16, 0.08, 0.035), face, 22, 12)
		_motion(ear, "ear", 0.13, 1.4, float(side) * 1.3, Vector3(0.2, 0.5, 1.0))
		_build_ram_horn(head, side, horn)
	var leg_points: Array[Vector3] = [Vector3(-0.17, 0.57, -0.30), Vector3(0.17, 0.57, -0.30),
		Vector3(-0.17, 0.57, 0.30), Vector3(0.17, 0.57, 0.30)]
	_four_legs(self, leg_points, 0.30, 0.22, 0.055, face, hoof,
		Vector3(0.080, 0.055, 0.100), 0.0, "ungulate")
	# Physically scaled helical fibre bundles: 7-11 mm curl diameter, roughly
	# 1.5-2.5 mm bundled strand thickness, with roots buried into the underwool.
	var curls: Array = []
	for i in 4200:
		var u: float = -0.97 + 1.94 * (float(i) + 0.5) / 4200.0
		u = clampf(u + (_hash01(float(i) * 1.37 + 2.0) - 0.5) * 0.016, -0.97, 0.97)
		var theta: float = fmod(float(i) * 2.399963 + (_hash01(float(i) * 2.11) - 0.5) * 0.055, TAU)
		var radial: float = sqrt(maxf(0.0, 1.0 - u * u))
		var x: float = cos(theta) * 0.282 * radial
		var y: float = 0.58 + u * 0.322
		var z: float = 0.03 + sin(theta) * 0.46 * radial
		var normal := Vector3(x / (0.282 * 0.282), (y - 0.58) / (0.322 * 0.322),
			(z - 0.03) / (0.46 * 0.46)).normalized()
		var curl_scale: float = 0.012 + _hash01(float(i) * 1.83 + 5.0) * 0.006
		var curl_depth: float = 0.010 + _hash01(float(i) * 2.71 + 19.0) * 0.008
		curls.append(_aligned_xform(Vector3(x, y, z) + normal * 0.003, normal,
			Vector3(curl_scale, curl_depth, curl_scale), theta * 0.73 + _hash01(float(i)) * TAU))
	_multi_wool_curls(self, "InterlockingWoolFibres", curls, wool_fiber, true)
	var brow_curls: Array = []
	for i in 650:
		var u: float = -0.84 + 1.68 * (float(i) + 0.5) / 650.0
		var theta: float = fmod(float(i) * 2.399963 + 0.7, TAU)
		var radial: float = sqrt(maxf(0.0, 1.0 - u * u))
		var local_normal := Vector3(cos(theta) * radial, u, sin(theta) * radial)
		var curl_pos := Vector3(local_normal.x * 0.155, 0.70 + local_normal.y * 0.175,
			-0.61 + local_normal.z * 0.205)
		var curl_scale: float = 0.011 + _hash01(float(i) + 36.0) * 0.005
		var curl_depth: float = 0.012 + _hash01(float(i) * 1.91 + 9.0) * 0.007
		brow_curls.append(_aligned_xform(curl_pos + local_normal * 0.003, local_normal,
			Vector3(curl_scale, curl_depth, curl_scale), theta + _hash01(float(i)) * TAU))
	_multi_wool_curls(self, "WoolForelockFibres", brow_curls, wool_fiber, false)
	_coat_strands(body, "FineWoolUnderfibres", Vector3(0.0, 0.0, 0.02),
		Vector3(0.57, 0.65, 0.94), wool_fiber, 8000, 0.010, 0.00024, 17.0, 0.04)
	_coat_strands(head, "FineForelockUnderfibres", Vector3(0.0, 0.01, 0.01),
		Vector3(0.32, 0.36, 0.42), wool_fiber, 1800, 0.008, 0.00020, 18.0, 0.02)
	var moss_clumps: Array = []
	for i in 34:
		var x: float = sin(float(i) * 2.37) * 0.23
		var z: float = -0.34 + fmod(float(i) * 0.113, 0.70)
		var y: float = 0.90 - absf(x) * 0.35 + sin(float(i) * 1.7) * 0.018
		moss_clumps.append(_xform(Vector3(x, y - 0.018, z), Vector3(0.0, float(i), 0.0),
			Vector3(0.040, 0.024 + float(i % 3) * 0.006, 0.052)))
	_multi_ellipsoids(self, "LivingMoss", moss_clumps, moss, true, 10, 7)


func _build_ram_horn(head: Node3D, side: int, material: Material) -> void:
	var points: Array[Vector3] = [Vector3(0.115 * float(side), 0.09, -0.02)]
	var radii: Array[float] = [0.046]
	for i in 28:
		var t: float = float(i + 1) / 28.0
		var angle: float = t * TAU * 0.78
		var radius: float = 0.12 + t * 0.09
		points.append(Vector3((0.115 + cos(angle) * radius) * float(side),
			0.08 + sin(angle) * radius, 0.02 + t * 0.13))
		radii.append(0.046 * (1.0 - t * 0.73))
	_tube(head, "ContinuousSpiralHorn_%d" % side, points, radii, material, 24)


# -----------------------------------------------------------------------------
# Single-Feature Prowler

func _build_single_feature_prowler() -> void:
	height = 0.70
	body_radius = 0.30
	body_height = 0.68
	body_center_y = 0.34
	body_length = 0.76
	melee_width = 0.78
	melee_height = 0.78
	melee_reach = 1.55
	melee_origin_y = 0.42
	muzzle_local_position = Vector3(0.0, 0.53, -0.58)
	_gait_rate = 7.8
	var coat := _surface(Color("8e735b"), Color("2d2a2a"), {"pattern": 1, "scale": 36.0,
		"strength": 0.52, "detail_mix": 0.16, "micro": 0.22, "roughness": 0.84,
		"fuzz": 0.64, "telegraph_gain": 1.3})
	var pale := _surface(Color("d5c9b9"), Color("806f63"), {"pattern": 4, "scale": 30.0,
		"strength": 0.25, "roughness": 0.86, "fuzz": 0.62})
	var dark := _surface(Color("2d2a2a"), Color("111215"), {"pattern": 4, "scale": 32.0,
		"roughness": 0.76, "fuzz": 0.5, "telegraph_gain": 2.2})
	var body := _node(self, "ProwlerBody", Vector3(0.0, 0.42, 0.04), Vector3(0.02, 0.0, 0.0))
	_loft(body, "FlexibleFelineSpine", [
		{"p": Vector3(0.0, 0.0, -0.38), "r": Vector2(0.025, 0.035)},
		{"p": Vector3(0.0, 0.025, -0.30), "r": Vector2(0.165, 0.205)},
		{"p": Vector3(0.0, 0.02, -0.17), "r": Vector2(0.17, 0.20)},
		{"p": Vector3(0.0, 0.0, 0.00), "r": Vector2(0.13, 0.155)},
		{"p": Vector3(0.0, 0.015, 0.18), "r": Vector2(0.16, 0.19)},
		{"p": Vector3(0.0, 0.0, 0.33), "r": Vector2(0.155, 0.18)},
		{"p": Vector3(0.0, 0.0, 0.42), "r": Vector2(0.022, 0.030)},
	], coat, 44)
	_ellipsoid(body, "Chest", Vector3(0.0, 0.02, -0.25), Vector3(0.34, 0.42, 0.34), coat, 36, 22)
	for side: int in [-1, 1]:
		_ellipsoid(body, "Haunch_%d" % side, Vector3(0.105 * float(side), 0.015, 0.24),
			Vector3(0.23, 0.32, 0.31), coat, 32, 18)
	_motion(body, "breathe", 0.025, 2.1)
	var neck := _node(self, "ProwlerNeck", Vector3(0.0, 0.49, -0.31), Vector3(-0.22, 0.0, 0.0))
	_ellipsoid(neck, "Neck", Vector3.ZERO, Vector3(0.21, 0.28, 0.27), coat, 32, 18)
	var head := _node(self, "ProwlerHead", Vector3(0.0, 0.57, -0.48), Vector3(-0.06, 0.0, 0.0))
	_ellipsoid(head, "Skull", Vector3.ZERO, Vector3(0.21, 0.19, 0.23), coat, 38, 22)
	for muzzle_side: int in [-1, 1]:
		_ellipsoid(head, "WhiskerPad_%d" % muzzle_side,
			Vector3(0.040 * float(muzzle_side), -0.040, -0.142), Vector3(0.090, 0.075, 0.120),
			pale, 30, 18)
	_ellipsoid(head, "Chin", Vector3(0.0, -0.086, -0.143), Vector3(0.084, 0.044, 0.090),
		pale, 24, 14)
	_ellipsoid(head, "Nose", Vector3(0.0, -0.022, -0.213), Vector3(0.052, 0.032, 0.026),
		_surface(Color("302725"), Color("131011"), {"pattern": 2, "scale": 34.0,
			"roughness": 0.18, "wetness": 0.46, "fuzz": 0.01}), 22, 12)
	_segment(head, "Philtrum", Vector3(0.0, -0.040, -0.216), Vector3(0.0, -0.086, -0.175),
		0.0018, _standard(Color("392a26"), 0.40), 5)
	_eyes(head, Vector3(0.0, 0.030, -0.100), 0.155, Vector3(0.022, 0.025, 0.016),
		Color("89a66a"), Vector3(0.006, 0.015, 0.0045), 0.24)
	_whiskers(head, Vector3(0.0, -0.042, -0.185), 0.16, 6)
	_motion(head, "head", 0.13, 1.7, 0.0, Vector3(1.0, 0.35, 0.0))
	for side: int in [-1, 1]:
		var ear := _node(head, "SensorEar_%d" % side, Vector3(0.09 * float(side), 0.10, -0.015),
			Vector3(0.0, 0.0, 0.10 * float(side)))
		_loft(ear, "OuterSensorPinna", [
			{"p": Vector3.ZERO, "r": Vector2(0.048, 0.033)},
			{"p": Vector3(0.004 * float(side), 0.070, 0.0), "r": Vector2(0.052, 0.031)},
			{"p": Vector3(0.010 * float(side), 0.132, 0.0), "r": Vector2(0.028, 0.019)},
			{"p": Vector3(0.014 * float(side), 0.162, 0.0), "r": Vector2(0.003, 0.004)},
		], coat, 26)
		_loft(ear, "PaleInnerPinna", [
			{"p": Vector3(0.0, 0.018, -0.029), "r": Vector2(0.024, 0.0035)},
			{"p": Vector3(0.003 * float(side), 0.075, -0.027), "r": Vector2(0.034, 0.004)},
			{"p": Vector3(0.010 * float(side), 0.132, -0.017), "r": Vector2(0.008, 0.0025)},
		], pale, 20)
		_cone(ear, "DarkEarTuft", Vector3(0.010 * float(side), 0.125, -0.002),
			Vector3(0.014 * float(side), 0.174, 0.0), 0.015, dark, 12)
		_motion(ear, "ear", 0.28, 1.3, float(side) * 1.9, Vector3(0.15, 0.65 * float(side), 1.0))
	var leg_points: Array[Vector3] = [Vector3(-0.105, 0.42, -0.25), Vector3(0.105, 0.42, -0.25),
		Vector3(-0.12, 0.43, 0.25), Vector3(0.12, 0.43, 0.25)]
	_four_legs(self, leg_points, 0.24, 0.20, 0.045, coat, dark,
		Vector3(0.11, 0.065, 0.15), 0.4, "feline")
	_coat_strands(body, "DirectionalTorsoCoat", Vector3(0.0, 0.005, 0.03),
		Vector3(0.35, 0.41, 0.82), coat, 3200, 0.011, 0.00045, 11.1, 0.26)
	_coat_strands(head, "FacialCoat", Vector3.ZERO, Vector3(0.215, 0.195, 0.235),
		coat, 900, 0.007, 0.00035, 12.7, 0.16)
	var tail := _node(self, "RingedTail", Vector3(0.0, 0.45, 0.36), Vector3(-0.25, 0.0, 0.0))
	var previous := Vector3.ZERO
	for i in 8:
		var t: float = float(i + 1) / 8.0
		var next := Vector3(sin(t * PI) * 0.11, 0.05 + sin(t * PI) * 0.08, t * 0.48)
		_segment(tail, "TailSection_%02d" % i, previous, next, 0.065 * (1.0 - t * 0.45),
			dark if i % 2 == 0 else coat, 16, 0.060 * (1.0 - t * 0.5))
		previous = next
	_motion(tail, "tail", 0.30, 1.9, 0.0, Vector3(0.1, 1.0, 0.0))


# -----------------------------------------------------------------------------
# K-Nearest Newt

func _build_k_nearest_newt() -> void:
	height = 0.24
	body_radius = 0.24
	body_height = 0.28
	body_center_y = 0.14
	body_length = 0.58
	melee_width = 0.62
	melee_height = 0.34
	melee_reach = 0.9
	melee_origin_y = 0.15
	muzzle_local_position = Vector3(0.0, 0.17, -0.31)
	_gait_rate = 5.2
	var skin := _surface(Color("53695d"), Color("324d45"), {"pattern": 2, "scale": 31.0,
		"strength": 0.48, "micro": 0.18, "bump": 0.020, "roughness": 0.48, "specular": 0.62,
		"wetness": 0.50, "fuzz": 0.02, "subsurface": 0.08})
	var belly := _surface(Color("9fa88f"), Color("59685a"), {"pattern": 2, "scale": 25.0,
		"strength": 0.3, "roughness": 0.50, "wetness": 0.46})
	var mouth := _standard(Color("25352f"), 0.24)
	var gill_colors: Array[Color] = [Color("6cae58"), Color("568ec3"), Color("d6ad42")]
	var body := _node(self, "NewtBody", Vector3(0.0, 0.14, 0.02))
	_loft(body, "ContinuousAmphibianBody", [
		{"p": Vector3(0.0, 0.0, -0.23), "r": Vector2(0.018, 0.014)},
		{"p": Vector3(0.0, 0.005, -0.18), "r": Vector2(0.105, 0.080)},
		{"p": Vector3(0.0, 0.008, -0.06), "r": Vector2(0.11, 0.085)},
		{"p": Vector3(0.0, 0.0, 0.08), "r": Vector2(0.095, 0.075)},
		{"p": Vector3(0.0, -0.005, 0.18), "r": Vector2(0.07, 0.055)},
		{"p": Vector3(0.0, 0.0, 0.24), "r": Vector2(0.016, 0.012)},
	], skin, 42)
	_ellipsoid(body, "Belly", Vector3(0.0, -0.052, -0.015), Vector3(0.155, 0.065, 0.29), belly, 32, 18)
	_motion(body, "breathe", 0.035, 2.0)
	var head := _node(self, "NewtHead", Vector3(0.0, 0.145, -0.22))
	_ellipsoid(head, "BroadHead", Vector3.ZERO, Vector3(0.158, 0.088, 0.170), skin, 40, 24)
	_ellipsoid(head, "FlattenedSnout", Vector3(0.0, -0.012, -0.100),
		Vector3(0.148, 0.058, 0.090), skin, 36, 20)
	for side: int in [-1, 1]:
		_ellipsoid(head, "OrbitalRidge_%d" % side, Vector3(0.105 * float(side), 0.048, -0.045),
			Vector3(0.027, 0.017, 0.030), skin, 18, 10)
		_ellipsoid(head, "Naris_%d" % side, Vector3(0.041 * float(side), 0.022, -0.182),
			Vector3(0.006, 0.0035, 0.003), mouth, 12, 7)
		_segment(head, "MouthCorner_%d" % side, Vector3(0.0, -0.045, -0.183),
			Vector3(0.115 * float(side), -0.038, -0.118), 0.0018, mouth, 6)
	_eyes(head, Vector3(0.0, 0.053, -0.052), 0.210, Vector3(0.013, 0.014, 0.010),
		Color("c8b94f"), Vector3(0.0045, 0.0065, 0.003), 0.30)
	_motion(head, "head", 0.07, 1.6, 0.0, Vector3(0.4, 1.0, 0.0))
	var tail := _node(self, "FinnedTail", Vector3(0.0, 0.14, 0.17))
	var previous := Vector3.ZERO
	for i in 7:
		var t: float = float(i + 1) / 7.0
		var next := Vector3(sin(t * PI * 1.3) * 0.025, sin(t * PI) * 0.025, t * 0.40)
		_segment(tail, "TailMuscle_%02d" % i, previous, next, 0.078 * (1.0 - t * 0.78), skin,
			18, 0.071 * (1.0 - t * 0.8))
		_ellipsoid(tail, "TailFin_%02d" % i, next + Vector3(0.0, 0.025, 0.0),
			Vector3(0.018, 0.085 * (1.0 - t * 0.45), 0.085), belly, 16, 10)
		previous = next
	_motion(tail, "tail", 0.38, 2.8, 0.0, Vector3(0.0, 1.0, 0.1))
	for i in 4:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var z: float = -0.105 if i < 2 else 0.11
		var limb := _node(self, "WebLeg_%d" % i, Vector3(0.07 * side, 0.13, z),
			Vector3(0.0, 0.0, -0.35 * side))
		_segment(limb, "Upper", Vector3.ZERO, Vector3(0.075 * side, -0.045, 0.02), 0.022, skin, 14)
		_segment(limb, "Forearm", Vector3(0.075 * side, -0.045, 0.02),
			Vector3(0.105 * side, -0.085, -0.015), 0.017, skin, 12)
		_ellipsoid(limb, "WebbedFoot", Vector3(0.115 * side, -0.088, -0.035),
			Vector3(0.075, 0.018, 0.065), belly, 18, 10)
		for toe in 3:
			_segment(limb, "Toe_%d" % toe, Vector3(0.10 * side, -0.087, -0.025),
				Vector3((0.13 + float(toe) * 0.012) * side, -0.09, -0.07 + float(toe) * 0.025),
				0.004, skin, 6)
		_motion(limb, "leg", 0.22, _gait_rate, PI if i in [1, 2] else 0.0)
	# Three explicit neighbor samples per side: green, iris blue, pollen gold.
	for sample in 3:
		var gill_mat := _surface(gill_colors[sample], gill_colors[(sample + 1) % 3],
			{"pattern": 0, "scale": 18.0, "strength": 0.25, "roughness": 0.28,
			"wetness": 0.45, "subsurface": 0.28, "telegraph_gain": 2.4, "variant_weight": 0.7})
		for side: int in [-1, 1]:
			var gill := _node(head, "NeighborGill_%d_%d" % [side, sample],
				Vector3(0.105 * float(side), 0.035 - float(sample) * 0.038, 0.01 + float(sample) * 0.025),
				Vector3(0.0, 0.0, -0.30 * float(side)))
			var stem_end := Vector3(0.125 * float(side), 0.032 + float(sample) * 0.014, 0.022)
			_segment(gill, "Stem", Vector3.ZERO, stem_end, 0.011, gill_mat, 12, 0.0045)
			for filament in 15:
				var t: float = float(filament + 1) / 16.0
				var start: Vector3 = stem_end * t
				var spread: float = (0.038 + sin(float(filament) * 1.7) * 0.008) * float(side)
				_segment(gill, "Filament_%02d" % filament, start,
					start + Vector3(spread, 0.034 + t * 0.034,
						sin(float(filament) * 0.82 + float(sample)) * 0.018),
					0.0028, gill_mat, 7, 0.0007)
			_motion(gill, "gill", 0.10, 3.1 + float(sample) * 0.25, float(side + sample), Vector3.ONE)


# -----------------------------------------------------------------------------
# Recency-Bias Jackdaw

func _build_recency_bias_jackdaw() -> void:
	height = 0.43
	body_radius = 0.20
	body_height = 0.46
	body_center_y = 0.23
	body_length = 0.34
	melee_width = 0.62
	melee_height = 0.56
	melee_reach = 1.0
	melee_origin_y = 0.33
	muzzle_local_position = Vector3(0.0, 0.43, -0.27)
	_gait_rate = 9.0
	var black := _surface(Color("1b2834"), Color("31516a"), {"pattern": 4, "scale": 48.0,
		"strength": 0.72, "detail_mix": 0.34, "micro": 0.16, "roughness": 0.48,
		"fuzz": 0.34, "sheen": Color("4c7da4"), "telegraph_gain": 1.3})
	var silver := _surface(Color("94a0a5"), Color("46535d"), {"pattern": 4, "scale": 44.0,
		"strength": 0.48, "roughness": 0.58, "fuzz": 0.38, "telegraph_gain": 2.1})
	var bill := _surface(Color("252b30"), Color("080a0c"), {"pattern": 3, "scale": 36.0,
		"roughness": 0.42, "fuzz": 0.02})
	var body := _node(self, "JackdawBody", Vector3(0.0, 0.28, 0.02))
	_loft(body, "FeatheredKeelBody", [
		{"p": Vector3(0.0, 0.015, -0.18), "r": Vector2(0.018, 0.022)},
		{"p": Vector3(0.0, 0.015, -0.13), "r": Vector2(0.085, 0.115)},
		{"p": Vector3(0.0, 0.0, -0.04), "r": Vector2(0.095, 0.135)},
		{"p": Vector3(0.0, -0.005, 0.07), "r": Vector2(0.088, 0.12)},
		{"p": Vector3(0.0, 0.0, 0.16), "r": Vector2(0.055, 0.075)},
		{"p": Vector3(0.0, 0.0, 0.21), "r": Vector2(0.012, 0.016)},
	], black, 42)
	_ellipsoid(body, "Chest", Vector3(0.0, -0.012, -0.085), Vector3(0.112, 0.178, 0.155), black, 32, 18)
	_motion(body, "breathe", 0.035, 3.1)
	var head := _node(self, "JackdawHead", Vector3(0.0, 0.43, -0.12))
	_ellipsoid(head, "Head", Vector3.ZERO, Vector3(0.132, 0.142, 0.170), black, 36, 20)
	_ellipsoid(head, "SilverNape", Vector3(0.0, -0.004, 0.064), Vector3(0.128, 0.104, 0.092), silver, 28, 16)
	for side: int in [-1, 1]:
		_ellipsoid(head, "SilverCheek_%d" % side, Vector3(0.102 * float(side), -0.022, 0.005),
			Vector3(0.046, 0.071, 0.073), silver, 20, 12)
	# A laterally broad, vertically compressed corvid bill stays readable in
	# silhouette; circular cones collapsed into an almost invisible black spike.
	_loft(head, "UpperBill", [
		{"p": Vector3(0.0, 0.018, -0.070), "r": Vector2(0.058, 0.030)},
		{"p": Vector3(0.0, 0.010, -0.125), "r": Vector2(0.046, 0.022)},
		{"p": Vector3(0.0, 0.000, -0.190), "r": Vector2(0.025, 0.012)},
		{"p": Vector3(0.0, -0.006, -0.235), "r": Vector2(0.003, 0.002)},
	], bill, 24)
	_loft(head, "LowerBill", [
		{"p": Vector3(0.0, -0.020, -0.068), "r": Vector2(0.050, 0.020)},
		{"p": Vector3(0.0, -0.021, -0.128), "r": Vector2(0.038, 0.014)},
		{"p": Vector3(0.0, -0.016, -0.206), "r": Vector2(0.003, 0.002)},
	], bill, 22)
	for nostril_side: int in [-1, 1]:
		_ellipsoid(head, "BillNostril_%d" % nostril_side,
			Vector3(0.021 * float(nostril_side), 0.026, -0.103), Vector3(0.006, 0.004, 0.003),
			_standard(Color("050607"), 0.08), 12, 7)
	_eyes(head, Vector3(0.0, 0.032, -0.073), 0.116, Vector3(0.017, 0.019, 0.014),
		Color("b9c4b5"), Vector3(0.005, 0.007, 0.0035), 0.68)
	_motion(head, "head", 0.22, 2.6, 0.3, Vector3(0.45, 1.0, 0.0))
	for side: int in [-1, 1]:
		var wing_pivot := _node(self, "JackdawWing_%d" % side,
			Vector3(0.072 * float(side), 0.31, -0.005), Vector3(0.04, 0.0, -0.035 * float(side)))
		_ellipsoid(wing_pivot, "FoldedCovert", Vector3(0.030 * float(side), -0.005, 0.052),
			Vector3(0.042, 0.075, 0.235), black, 28, 16)
		var feathers: Array = []
		for f in 14:
			var t: float = float(f) / 13.0
			var layer: float = float(f % 3)
			feathers.append(_xform(Vector3((0.036 + (1.0 - t) * 0.018) * float(side),
				-0.012 - layer * 0.012, 0.018 + t * 0.145),
				Vector3(0.035 + t * 0.025, 0.035 * float(side), (t - 0.5) * 0.08 * float(side)),
				Vector3(0.030 - t * 0.006, 0.010, 0.175 + t * 0.105)))
		_multi_feathers(wing_pivot, "FoldedPrimaryLayers", feathers, black, true)
		_motion(wing_pivot, "wing", 0.30, 7.2, float(side) * 0.8, Vector3(0.0, 0.0, float(side)))
	var tails: Array = []
	for f in 7:
		tails.append(_xform(Vector3((float(f) - 3.0) * 0.016, 0.25, 0.235),
			Vector3(0.08, 0.0, (float(f) - 3.0) * 0.035), Vector3(0.034, 0.014, 0.32)))
	_multi_feathers(self, "WedgeTail", tails, black, true)
	for side: int in [-1, 1]:
		_segment(self, "Tarsus_%d" % side, Vector3(0.045 * float(side), 0.20, 0.025),
			Vector3(0.05 * float(side), 0.075, 0.01), 0.012, bill, 10)
		for toe in 4:
			var angle: float = -0.8 + float(toe) * 0.5
			_segment(self, "Toe_%d_%d" % [side, toe], Vector3(0.05 * float(side), 0.075, 0.01),
				Vector3(0.05 * float(side) + sin(angle) * 0.04, 0.066, -0.04 + cos(angle) * 0.05),
				0.004, bill, 6)


# -----------------------------------------------------------------------------
# Brackenhoof, Keeper of the Decision Tree

func _build_brackenhoof() -> void:
	height = 2.72
	body_radius = 0.61
	body_height = 1.85
	body_center_y = 0.93
	body_length = 1.58
	melee_width = 1.45
	melee_height = 2.05
	melee_reach = 2.45
	melee_origin_y = 1.08
	muzzle_local_position = Vector3(0.0, 1.62, -1.58)
	_gait_rate = 4.6
	var coat := _surface(Color("3d2b24"), Color("6b4b3d"), {"pattern": 4, "scale": 19.0,
		"strength": 0.48, "micro": 0.25, "roughness": 0.88, "fuzz": 0.76})
	var dark_coat := _surface(Color("251b18"), Color("4f352c"), {"pattern": 4, "scale": 24.0,
		"strength": 0.42, "roughness": 0.9, "fuzz": 0.7})
	var antler := _surface(Color("c4b493"), Color("675b49"), {"pattern": 3, "scale": 24.0,
		"strength": 0.7, "roughness": 0.52, "fuzz": 0.02, "variant_weight": 0.65})
	var branch_glow := _surface(Color("d7c8a6"), Color("e4a23a"), {"pattern": 3, "scale": 28.0,
		"strength": 0.65, "roughness": 0.46, "telegraph_gain": 3.6, "variant_weight": 0.82})
	var scute := _surface(Color("416a4a"), Color("7fa36d"), {"pattern": 1, "scale": 21.0,
		"strength": 0.68, "roughness": 0.72, "fuzz": 0.18, "telegraph_gain": 1.7})
	var hoof := _surface(Color("201c19"), Color("5d5146"), {"pattern": 3, "scale": 20.0,
		"roughness": 0.58})
	var stone := _surface(Color("777977"), Color("383b3d"), {"pattern": 2, "scale": 13.0,
		"strength": 0.5, "roughness": 0.84, "telegraph_gain": 1.5})
	var flax := _surface(Color("a68d59"), Color("54452b"), {"pattern": 4, "scale": 36.0,
		"roughness": 0.92, "fuzz": 0.5})
	var body := _node(self, "BrackenhoofBody", Vector3(0.0, 1.08, 0.15), Vector3(0.02, 0.0, 0.0))
	_loft(body, "ContinuousElkTorso", [
		{"p": Vector3(0.0, 0.0, -0.83), "r": Vector2(0.06, 0.08)},
		{"p": Vector3(0.0, 0.06, -0.69), "r": Vector2(0.42, 0.55)},
		{"p": Vector3(0.0, 0.06, -0.45), "r": Vector2(0.45, 0.57)},
		{"p": Vector3(0.0, 0.02, -0.12), "r": Vector2(0.39, 0.48)},
		{"p": Vector3(0.0, 0.0, 0.25), "r": Vector2(0.40, 0.47)},
		{"p": Vector3(0.0, 0.03, 0.56), "r": Vector2(0.43, 0.50)},
		{"p": Vector3(0.0, 0.0, 0.78), "r": Vector2(0.28, 0.35)},
		{"p": Vector3(0.0, 0.0, 0.91), "r": Vector2(0.05, 0.07)},
	], coat, 56)
	_ellipsoid(body, "DeepChest", Vector3(0.0, 0.07, -0.53), Vector3(0.84, 1.08, 0.70), dark_coat, 46, 26)
	_ellipsoid(body, "Rump", Vector3(0.0, 0.0, 0.58), Vector3(0.77, 0.89, 0.69), coat, 44, 26)
	_motion(body, "breathe", 0.035, 1.45)
	var neck := _node(self, "BrackenhoofNeck", Vector3(0.0, 1.42, -0.57), Vector3(-0.45, 0.0, 0.0))
	_ellipsoid(neck, "RisingNeck", Vector3(0.0, 0.0, -0.12), Vector3(0.55, 0.88, 0.80), coat, 44, 26)
	_ellipsoid(neck, "DarkMane", Vector3(0.0, 0.12, 0.06), Vector3(0.60, 0.72, 0.46), dark_coat, 38, 22)
	var head := _node(self, "BrackenhoofHead", Vector3(0.0, 1.78, -1.06), Vector3(-0.10, 0.0, 0.0))
	_loft(head, "ContinuousCervidSkull", [
		{"p": Vector3(0.0, 0.015, 0.24), "r": Vector2(0.115, 0.150)},
		{"p": Vector3(0.0, 0.025, 0.10), "r": Vector2(0.220, 0.255)},
		{"p": Vector3(0.0, 0.005, -0.10), "r": Vector2(0.205, 0.230)},
		{"p": Vector3(0.0, -0.035, -0.29), "r": Vector2(0.174, 0.180)},
		{"p": Vector3(0.0, -0.070, -0.46), "r": Vector2(0.145, 0.132)},
		{"p": Vector3(0.0, -0.078, -0.59), "r": Vector2(0.112, 0.090)},
		{"p": Vector3(0.0, -0.080, -0.65), "r": Vector2(0.090, 0.070)},
	], coat, 52)
	_ellipsoid(head, "LowerJaw", Vector3(0.0, -0.155, -0.39), Vector3(0.27, 0.14, 0.36),
		dark_coat, 34, 20)
	var velvet_nose := _surface(Color("352725"), Color("171112"), {"pattern": 2, "scale": 30.0,
		"roughness": 0.18, "wetness": 0.44, "fuzz": 0.01, "bump": 0.080})
	_disc(head, "VelvetNose", Vector3(0.0, -0.08, -0.67), 0.096, 0.027,
		velvet_nose,
		Vector3(PI * 0.5, 0.0, 0.0), 30)
	for nostril_side: int in [-1, 1]:
		_ellipsoid(head, "Nostril_%d" % nostril_side,
			Vector3(0.045 * float(nostril_side), -0.064, -0.687), Vector3(0.030, 0.016, 0.009),
			_standard(Color("0b0808"), 0.08), 16, 9)
	_eyes(head, Vector3(0.0, 0.070, -0.10), 0.370, Vector3(0.039, 0.034, 0.027),
		Color("b88935"), Vector3(0.013, 0.0065, 0.006), 0.76)
	_motion(head, "head", 0.20, 1.1, 0.0, Vector3(1.0, 0.18, 0.0))
	for side: int in [-1, 1]:
		var ear := _node(head, "TrackingEar_%d" % side, Vector3(0.21 * float(side), 0.18, -0.03),
			Vector3(0.0, 0.0, 0.72 * float(side)))
		_ellipsoid(ear, "Ear", Vector3(0.10 * float(side), 0.0, 0.0), Vector3(0.30, 0.13, 0.055), coat, 28, 16)
		_motion(ear, "ear", 0.16, 1.0, float(side) * 1.7, Vector3(0.1, 0.5, 1.0))
		_build_decision_antler(head, side, antler, branch_glow, stone, flax)
	var leg_points: Array[Vector3] = [Vector3(-0.28, 1.10, -0.52), Vector3(0.28, 1.10, -0.52),
		Vector3(-0.29, 1.07, 0.58), Vector3(0.29, 1.07, 0.58)]
	_four_legs(self, leg_points, 0.56, 0.48, 0.095, coat, hoof,
		Vector3(0.130, 0.085, 0.180), 0.2, "elk")
	_coat_strands(body, "HighDensityGuardCoat", Vector3(0.0, 0.025, 0.04),
		Vector3(0.89, 1.09, 1.79), coat, 5500, 0.024, 0.00075, 20.0, 0.30)
	_coat_strands(neck, "NeckGuardCoat", Vector3(0.0, 0.0, -0.10),
		Vector3(0.57, 0.90, 0.82), coat, 1800, 0.030, 0.00085, 22.0, 0.24)
	var scutes: Array = []
	for row in 4:
		for col in 7:
			var x: float = (float(row) - 1.5) * 0.17
			var z: float = -0.50 + float(col) * 0.17
			var y: float = 1.59 - absf(x) * 0.38 + sin(float(col) * 1.6 + float(row)) * 0.025
			scutes.append(_xform(Vector3(x, y, z), Vector3(-0.16, 0.0, x * 0.55),
				Vector3(0.22, 0.045, 0.30)))
	_multi_ellipsoids(self, "FernVeinedShoulderScutes", scutes, scute, true, 18, 10)
	var coat_tufts: Array = []
	for ring in 10:
		for i in 18:
			var theta: float = TAU * float(i) / 18.0
			var z: float = -0.53 + float(ring) * 0.12
			var x: float = cos(theta) * 0.40
			var y: float = 1.08 + sin(theta) * 0.48
			coat_tufts.append(_xform(Vector3(x, y, z), Vector3(theta, 0.0, -cos(theta) * 0.45),
				Vector3(0.025, 0.085, 0.025)))
	_multi_cones(self, "SparseGuardCoat", coat_tufts, dark_coat, false, 7)


func _build_decision_antler(head: Node3D, side: int, bone: Material, glow: Material,
		stone: Material, flax: Material) -> void:
	var antler_root := _node(head, "DecisionAntler_%d" % side,
		Vector3(0.16 * float(side), 0.22, -0.05), Vector3(0.0, 0.0, -0.06 * float(side)))
	var trunk: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(0.10 * float(side), 0.25, 0.03),
		Vector3(0.19 * float(side), 0.48, 0.08),
		Vector3(0.28 * float(side), 0.68, 0.15),
		Vector3(0.36 * float(side), 0.85, 0.23),
	]
	for i in trunk.size() - 1:
		_segment(antler_root, "Trunk_%02d" % i, trunk[i], trunk[i + 1], 0.075 - float(i) * 0.011,
			bone, 22, 0.066 - float(i) * 0.011)
	# Binary forks make the decision-tree metaphor anatomically real.
	for level in range(1, 4):
		var branch_base: Vector3 = trunk[level]
		var outward := branch_base + Vector3((0.22 + float(level) * 0.035) * float(side),
			0.16 + float(level) * 0.035, -0.06 - float(level) * 0.04)
		var inward := branch_base + Vector3((-0.09 - float(level) * 0.02) * float(side),
			0.21 + float(level) * 0.03, 0.11 + float(level) * 0.04)
		var chosen: Material = glow if level in [1, 3] else bone
		_segment(antler_root, "ForkOut_%02d" % level, branch_base, outward,
			0.052 - float(level) * 0.008, chosen, 18, 0.024)
		_segment(antler_root, "ForkIn_%02d" % level, branch_base, inward,
			0.048 - float(level) * 0.007, bone, 18, 0.022)
		var outer_tip := outward + Vector3(0.10 * float(side), 0.18, -0.03)
		var inner_tip := inward + Vector3(-0.04 * float(side), 0.16, 0.08)
		_cone(antler_root, "OuterTine_%02d" % level, outward, outer_tip, 0.025, chosen, 16)
		_cone(antler_root, "InnerTine_%02d" % level, inward, inner_tip, 0.023, bone, 16)
	# Stone bells hang from real cords and move with the gait.
	for bell_index in 3:
		var source: Vector3 = trunk[bell_index + 1] + Vector3(0.025 * float(side), 0.0, 0.0)
		var bell_pivot := _node(antler_root, "BellPivot_%d" % bell_index, source)
		_segment(bell_pivot, "FlaxCord", Vector3.ZERO, Vector3(0.0, -0.17 - float(bell_index) * 0.025, 0.0),
			0.006, flax, 8)
		var bell_y: float = -0.19 - float(bell_index) * 0.025
		_cone(bell_pivot, "StoneBell", Vector3(0.0, bell_y + 0.07, 0.0), Vector3(0.0, bell_y - 0.04, 0.0),
			0.065, stone, 14)
		_disc(bell_pivot, "BellLip", Vector3(0.0, bell_y - 0.035, 0.0), 0.065, 0.018, stone)
		_motion(bell_pivot, "bell", 0.28, 2.2 + float(bell_index) * 0.3,
			float(side + bell_index), Vector3(0.0, 0.0, 1.0))


# -----------------------------------------------------------------------------
# Fallbacks for Stray Glitchling and non-content proving rigs.

func _build_behavior_fallback(behavior: String, base: Color, accent: Color, size: float) -> void:
	match behavior:
		"dummy":
			_build_dummy()
		"melee":
			_build_fallback_bruiser(base, accent, size)
		"ranged":
			_build_fallback_watcher(base, accent, size)
		_:
			_build_fallback_glitchling(base, accent, size)


func _build_fallback_glitchling(base: Color, accent: Color, size: float) -> void:
	height = 0.9 * size
	body_radius = 0.32 * size
	body_height = height
	body_center_y = height * 0.5
	var primary := _surface(base, accent, {"pattern": 2, "scale": 12.0, "strength": 0.5,
		"roughness": 0.65, "fuzz": 0.15})
	_ellipsoid(self, "GlitchCore", Vector3(0.0, 0.46 * size, 0.0),
		Vector3(0.52, 0.50, 0.48) * size, primary, 18, 10)
	var pixels: Array = []
	for i in 12:
		var angle: float = TAU * float(i) / 12.0
		pixels.append(_xform(Vector3(cos(angle) * 0.28 * size,
			0.48 * size + sin(angle * 1.7) * 0.18 * size, sin(angle) * 0.25 * size),
			Vector3(angle, angle * 0.4, 0.0), Vector3.ONE * (0.11 + float(i % 3) * 0.025) * size))
	var pixel_mesh := BoxMesh.new()
	pixel_mesh.size = Vector3.ONE
	_multimesh(self, "DataPixels", pixel_mesh, pixels, primary, true)
	_eyes(self, Vector3(0.0, 0.54 * size, -0.24 * size), 0.12 * size,
		Vector3.ONE * 0.055 * size, Color("ffd34d"), Vector3.ONE * 0.022 * size)


func _build_fallback_bruiser(base: Color, accent: Color, size: float) -> void:
	var scale_value: float = size * 1.35
	height = 1.2 * scale_value
	body_radius = 0.42 * scale_value
	body_height = height
	body_center_y = height * 0.5
	var primary := _surface(base, accent, {"pattern": 2, "scale": 13.0, "roughness": 0.74})
	_ellipsoid(self, "Bruiser", Vector3(0.0, 0.62 * scale_value, 0.0),
		Vector3(0.74, 0.86, 0.70) * scale_value, primary, 24, 14)
	for side: int in [-1, 1]:
		_cone(self, "Horn_%d" % side, Vector3(0.16 * scale_value * float(side), 0.95 * scale_value, -0.03),
			Vector3(0.30 * scale_value * float(side), 1.24 * scale_value, -0.08), 0.08 * scale_value,
			_standard(Color("ddd4be"), 0.55), 12)
	_eyes(self, Vector3(0.0, 0.72 * scale_value, -0.34 * scale_value), 0.18 * scale_value,
		Vector3.ONE * 0.06 * scale_value, Color("ffd34d"), Vector3.ONE * 0.025 * scale_value)


func _build_fallback_watcher(base: Color, accent: Color, size: float) -> void:
	height = 1.1 * size
	body_radius = 0.42 * size
	body_height = height
	body_center_y = height * 0.5
	var primary := _surface(base, accent, {"pattern": 2, "scale": 16.0, "roughness": 0.45,
		"specular": 0.6})
	_ellipsoid(self, "Watcher", Vector3(0.0, 0.8 * size, 0.0), Vector3.ONE * 0.62 * size,
		primary, 28, 16)
	_torus(self, "LensRing", Vector3(0.0, 0.8 * size, -0.29 * size), 0.17 * size, 0.27 * size,
		primary, Vector3(PI * 0.5, 0.0, 0.0))
	_ellipsoid(self, "Pupil", Vector3(0.0, 0.8 * size, -0.33 * size), Vector3.ONE * 0.20 * size,
		_standard(Color("ff65dd"), 0.08, 0.0, 2.5), 24, 14)


func _build_dummy() -> void:
	height = 1.7
	body_radius = 0.32
	body_height = 1.6
	body_center_y = 0.8
	var wood := _surface(Color("73532e"), Color("362718"), {"pattern": 3, "scale": 18.0,
		"strength": 0.65, "roughness": 0.9})
	var straw := _surface(Color("d8b94e"), Color("80642d"), {"pattern": 4, "scale": 30.0,
		"roughness": 0.94, "fuzz": 0.55})
	_box(self, "Post", Vector3(0.0, 0.76, 0.0), Vector3(0.17, 1.52, 0.17), wood)
	_box(self, "Arms", Vector3(0.0, 1.15, 0.0), Vector3(1.1, 0.14, 0.14), wood)
	_ellipsoid(self, "SackHead", Vector3(0.0, 1.50, 0.0), Vector3(0.46, 0.50, 0.42), straw, 20, 12)
	_ellipsoid(self, "StrawBale", Vector3(0.0, 0.56, 0.0), Vector3(0.54, 0.48, 0.48), straw, 18, 10)

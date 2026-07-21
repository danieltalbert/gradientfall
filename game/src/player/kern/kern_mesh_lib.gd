class_name KernMeshLib
extends RefCounted
## Geometry backbone for the code-built hero: lofted surfaces from stacked
## cross-section rings, with analytic smooth normals (central differences on
## the ring grid — no SurfaceTool smoothing lottery), UVs (x = around,
## y = along), per-vertex COLOR paint, and optional 2-bone skinning weights
## carried per ring. Everything commits straight into ArrayMesh surfaces.
##
## Conventions: rings run start -> end along the surface; each ring's points
## wind counter-clockwise seen from the "end" side so outward normals fall out
## of the cross products naturally. A loft dictionary is a plain surface-arrays
## bundle so lofts can be merged before committing (one material = one surface).

const TAU_F: float = TAU


## One cross-section slice of a loft.
class Ring:
	var points: PackedVector3Array = PackedVector3Array()
	## Whole-ring paint (rgb = albedo, a = material mask: thickness / looseness
	## / wear / edge depending on the shader).
	var color: Color = Color(1.0, 1.0, 1.0, 1.0)
	## Optional per-point paint; when non-empty it overrides `color`.
	var point_colors: PackedColorArray = PackedColorArray()
	var v: float = 0.0
	var bone_a: int = 0
	var bone_b: int = 0
	var blend: float = 0.0  # 0 = all bone_a, 1 = all bone_b


## Ellipse ring in the plane spanned by axis_u / axis_w. `shape` (optional)
## is Callable(angle: float) -> float multiplying the radius at that angle —
## how limbs get muscle bulges and torsos get flattened backs.
static func ellipse_ring(center: Vector3, axis_u: Vector3, axis_w: Vector3,
		ru: float, rw: float, segments: int, shape: Callable = Callable()) -> Ring:
	var ring: Ring = Ring.new()
	ring.points.resize(segments)
	for j in segments:
		var a: float = TAU_F * float(j) / float(segments)
		var m: float = 1.0
		if shape.is_valid():
			m = shape.call(a)
		ring.points[j] = center + axis_u * (cos(a) * ru * m) + axis_w * (sin(a) * rw * m)
	return ring


## Rings for a tube swept along a polyline with per-point radii, using
## rotation-minimizing frames so the tube never twists. flatten squashes the
## cross-section along the frame's second axis (hair clumps, straps).
## `path` is a plain Array of Vector3 (untyped so literal call sites work).
static func tube_rings(path: Array, radii: PackedFloat32Array,
		segments: int, flatten: float = 1.0, v_start: float = 0.0,
		v_end: float = 1.0) -> Array:
	var rings: Array = []
	var count: int = path.size()
	if count < 2:
		return rings
	# Initial frame from the first tangent.
	var t0: Vector3 = (path[1] - path[0]).normalized()
	var ref: Vector3 = Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u: Vector3 = t0.cross(ref).normalized()
	var w: Vector3 = t0.cross(u).normalized()
	for i in count:
		var tangent: Vector3
		if i == 0:
			tangent = (path[1] - path[0]).normalized()
		elif i == count - 1:
			tangent = (path[i] - path[i - 1]).normalized()
		else:
			tangent = (path[i + 1] - path[i - 1]).normalized()
		# Rotation-minimizing update: re-project the previous frame.
		u = (u - tangent * u.dot(tangent)).normalized()
		w = tangent.cross(u).normalized()
		var ring: Ring = ellipse_ring(path[i], u, w, radii[i], radii[i] * flatten, segments)
		ring.v = lerpf(v_start, v_end, float(i) / float(count - 1))
		rings.append(ring)
	return rings


## Stitch rings into surface arrays. All rings need the same point count.
## Returns {verts, normals, tangents, colors, uvs, bones, weights, indices}.
## `rings` is a plain Array of Ring (typed cross-script arrays are fragile).
static func loft(rings: Array, wrap: bool = true, cap_start: bool = false,
		cap_end: bool = false, skinned: bool = false, flip: bool = false) -> Dictionary:
	var ring_count: int = rings.size()
	var n: int = (rings[0] as Ring).points.size()
	var cols: int = n + 1 if wrap else n  # duplicate seam column for clean UVs
	var verts: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var bones: PackedInt32Array = PackedInt32Array()
	var weights: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()

	for r in ring_count:
		var ring: Ring = rings[r] as Ring
		for j in cols:
			var pj: int = j % n
			verts.append(ring.points[pj])
			var c: Color = ring.color
			if not ring.point_colors.is_empty():
				c = ring.point_colors[pj]
			colors.append(c)
			uvs.append(Vector2(float(j) / float(n), ring.v))
			if skinned:
				bones.append_array(PackedInt32Array([ring.bone_a, ring.bone_b, 0, 0]))
				weights.append_array(PackedFloat32Array(
					[1.0 - ring.blend, ring.blend, 0.0, 0.0]))
	for r in ring_count - 1:
		var base: int = r * cols
		for j in cols - 1:
			var i0: int = base + j
			var i1: int = base + j + 1
			var i2: int = base + cols + j
			var i3: int = base + cols + j + 1
			if flip:
				indices.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3]))
			else:
				indices.append_array(PackedInt32Array([i0, i1, i2, i1, i3, i2]))

	# Smooth normals + tangents by central differences over the ring grid.
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(verts.size())
	var tangents: PackedFloat32Array = PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for r in ring_count:
		for j in cols:
			var idx: int = r * cols + j
			var du: Vector3 = _grid_du(rings, r, j, n, wrap)
			var dv: Vector3 = _grid_dv(rings, r, j, n)
			var normal: Vector3 = du.cross(dv)
			if normal.length_squared() < 0.000001:
				normal = Vector3.UP
			normal = normal.normalized()
			if flip:
				normal = -normal
			normals[idx] = normal
			var tangent: Vector3 = du.normalized()
			if tangent.length_squared() < 0.5:
				tangent = normal.cross(Vector3.UP).normalized()
			tangents[idx * 4] = tangent.x
			tangents[idx * 4 + 1] = tangent.y
			tangents[idx * 4 + 2] = tangent.z
			tangents[idx * 4 + 3] = 1.0

	var surface: Dictionary = {
		"verts": verts, "normals": normals, "tangents": tangents,
		"colors": colors, "uvs": uvs, "indices": indices,
		"bones": bones, "weights": weights,
	}
	if cap_start:
		_add_cap(surface, rings[0], n, true if not flip else false, skinned)
	if cap_end:
		_add_cap(surface, rings[ring_count - 1], n, false if not flip else true, skinned)
	return surface


static func _grid_du(rings: Array, r: int, j: int, n: int, wrap: bool) -> Vector3:
	var ring: Ring = rings[r] as Ring
	if wrap:
		var j_prev: int = (j - 1 + n) % n
		var j_next: int = (j + 1) % n
		return ring.points[j_next] - ring.points[j_prev]
	var jc: int = clampi(j, 0, n - 1)
	var a: int = clampi(jc - 1, 0, n - 1)
	var b: int = clampi(jc + 1, 0, n - 1)
	return ring.points[b] - ring.points[a]


static func _grid_dv(rings: Array, r: int, j: int, n: int) -> Vector3:
	var pj: int = j % n
	var a: int = clampi(r - 1, 0, rings.size() - 1)
	var b: int = clampi(r + 1, 0, rings.size() - 1)
	return (rings[b] as Ring).points[pj] - (rings[a] as Ring).points[pj]


static func _add_cap(surface: Dictionary, ring: Ring, n: int, start: bool,
		skinned: bool) -> void:
	var verts: PackedVector3Array = surface["verts"]
	var normals: PackedVector3Array = surface["normals"]
	var tangents: PackedFloat32Array = surface["tangents"]
	var colors: PackedColorArray = surface["colors"]
	var uvs: PackedVector2Array = surface["uvs"]
	var indices: PackedInt32Array = surface["indices"]
	var bones: PackedInt32Array = surface["bones"]
	var weights: PackedFloat32Array = surface["weights"]

	var centroid: Vector3 = Vector3.ZERO
	for p in ring.points:
		centroid += p
	centroid /= float(n)
	# Cap normal from the ring plane; flipped for the start cap.
	var plane_n: Vector3 = (ring.points[1] - ring.points[0]).cross(
		ring.points[2 % n] - ring.points[0]).normalized()
	if start:
		plane_n = -plane_n
	var base: int = verts.size()
	for j in n + 1:
		var pj: int = j % n
		verts.append(ring.points[pj])
		normals.append(plane_n)
		tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		colors.append(ring.color if ring.point_colors.is_empty() else ring.point_colors[pj])
		uvs.append(Vector2(float(j) / float(n), ring.v))
		if skinned:
			bones.append_array(PackedInt32Array([ring.bone_a, ring.bone_b, 0, 0]))
			weights.append_array(PackedFloat32Array([1.0 - ring.blend, ring.blend, 0.0, 0.0]))
	verts.append(centroid)
	normals.append(plane_n)
	tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
	colors.append(ring.color if ring.point_colors.is_empty() else ring.point_colors[0])
	uvs.append(Vector2(0.5, ring.v))
	if skinned:
		bones.append_array(PackedInt32Array([ring.bone_a, ring.bone_b, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0 - ring.blend, ring.blend, 0.0, 0.0]))
	var center_idx: int = verts.size() - 1
	for j in n:
		if start:
			indices.append_array(PackedInt32Array([center_idx, base + j, base + j + 1]))
		else:
			indices.append_array(PackedInt32Array([center_idx, base + j + 1, base + j]))

	surface["verts"] = verts
	surface["normals"] = normals
	surface["tangents"] = tangents
	surface["colors"] = colors
	surface["uvs"] = uvs
	surface["indices"] = indices
	surface["bones"] = bones
	surface["weights"] = weights


## Merge several loft surfaces (same material) into one, offsetting indices.
## `surfaces` is a plain Array of surface dicts (untyped for literal call sites).
static func merge(surfaces: Array) -> Dictionary:
	var out: Dictionary = {
		"verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"tangents": PackedFloat32Array(), "colors": PackedColorArray(),
		"uvs": PackedVector2Array(), "indices": PackedInt32Array(),
		"bones": PackedInt32Array(), "weights": PackedFloat32Array(),
	}
	for s in surfaces:
		var offset: int = (out["verts"] as PackedVector3Array).size()
		(out["verts"] as PackedVector3Array).append_array(s["verts"])
		(out["normals"] as PackedVector3Array).append_array(s["normals"])
		(out["tangents"] as PackedFloat32Array).append_array(s["tangents"])
		(out["colors"] as PackedColorArray).append_array(s["colors"])
		(out["uvs"] as PackedVector2Array).append_array(s["uvs"])
		(out["bones"] as PackedInt32Array).append_array(s["bones"])
		(out["weights"] as PackedFloat32Array).append_array(s["weights"])
		var idx: PackedInt32Array = out["indices"]
		for i in (s["indices"] as PackedInt32Array):
			idx.append(i + offset)
		out["indices"] = idx
	return out


## Mirror a surface across X (positions, normals, tangents) and reverse
## winding so it stays outward-facing. For ears / hands / boots built once.
static func mirror_x(surface: Dictionary) -> Dictionary:
	var verts: PackedVector3Array = (surface["verts"] as PackedVector3Array).duplicate()
	var normals: PackedVector3Array = (surface["normals"] as PackedVector3Array).duplicate()
	var tangents: PackedFloat32Array = (surface["tangents"] as PackedFloat32Array).duplicate()
	for i in verts.size():
		verts[i] = Vector3(-verts[i].x, verts[i].y, verts[i].z)
		normals[i] = Vector3(-normals[i].x, normals[i].y, normals[i].z)
		tangents[i * 4] = -tangents[i * 4]
	var src_idx: PackedInt32Array = surface["indices"]
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(src_idx.size())
	for i in range(0, src_idx.size(), 3):
		indices[i] = src_idx[i]
		indices[i + 1] = src_idx[i + 2]
		indices[i + 2] = src_idx[i + 1]
	return {
		"verts": verts, "normals": normals, "tangents": tangents,
		"colors": (surface["colors"] as PackedColorArray).duplicate(),
		"uvs": (surface["uvs"] as PackedVector2Array).duplicate(),
		"indices": indices,
		"bones": (surface["bones"] as PackedInt32Array).duplicate(),
		"weights": (surface["weights"] as PackedFloat32Array).duplicate(),
	}


## Rigid transform of a surface in place (positions + normals + tangents).
static func transform_surface(surface: Dictionary, xf: Transform3D) -> Dictionary:
	var verts: PackedVector3Array = surface["verts"]
	var normals: PackedVector3Array = surface["normals"]
	var tangents: PackedFloat32Array = surface["tangents"]
	for i in verts.size():
		verts[i] = xf * verts[i]
		normals[i] = (xf.basis * normals[i]).normalized()
		var t: Vector3 = xf.basis * Vector3(
			tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		t = t.normalized()
		tangents[i * 4] = t.x
		tangents[i * 4 + 1] = t.y
		tangents[i * 4 + 2] = t.z
	return surface


## Commit one surface bundle onto a mesh (new surface, given material).
static func add_surface(mesh: ArrayMesh, surface: Dictionary, material: Material) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = surface["verts"]
	arrays[Mesh.ARRAY_NORMAL] = surface["normals"]
	arrays[Mesh.ARRAY_TANGENT] = surface["tangents"]
	arrays[Mesh.ARRAY_COLOR] = surface["colors"]
	arrays[Mesh.ARRAY_TEX_UV] = surface["uvs"]
	arrays[Mesh.ARRAY_INDEX] = surface["indices"]
	if not (surface["bones"] as PackedInt32Array).is_empty():
		arrays[Mesh.ARRAY_BONES] = surface["bones"]
		arrays[Mesh.ARRAY_WEIGHTS] = surface["weights"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## Convenience: single-surface MeshInstance3D.
static func make_instance(surface: Dictionary, material: Material,
		instance_name: String) -> MeshInstance3D:
	var mesh: ArrayMesh = ArrayMesh.new()
	add_surface(mesh, surface, material)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = instance_name
	mi.mesh = mesh
	return mi


## Cubic bezier point.
static func bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	var q2: Vector3 = p2.lerp(p3, t)
	var r0: Vector3 = q0.lerp(q1, t)
	var r1: Vector3 = q1.lerp(q2, t)
	return r0.lerp(r1, t)


## Sample a bezier into a path array.
static func bezier_path(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		steps: int) -> Array[Vector3]:
	var path: Array[Vector3] = []
	for i in steps:
		path.append(bezier(p0, p1, p2, p3, float(i) / float(steps - 1)))
	return path


## Deterministic scalar hash for jitter (no RNG state to collide across parts).
static func hash1(x: float) -> float:
	return fposmod(sin(x * 127.1) * 43758.5453, 1.0)

class_name GradientPeaks
extends Node3D
## The Gradient Peaks — a real mountain massif, not cones (richness pass 4).
##
## Three heightfield ranks arc around the meadow's north: green foothills that
## rise straight out of the Datasedge turf, the main rock wall with an authored
## eight-summit skyline, and a rank of snowbound giants behind it. The math was
## iterated against a Python twin of this file running the same FastNoiseLite
## library (docs/DEVLOG.md, 2026-07-18) — change constants there first, look,
## then port back.
##
## Structure per rank: an authored crest line (smooth-max of summit gaussians
## over an undulating base ridge → one connected massif), multiplied by a
## front-steep depth envelope and domain-warped ridged fBm (spur/gully
## skeleton), minus couloir channels squashed down-face, plus talus aprons at
## the foot. Crest zones are relaxation-blurred so summits read as solid horns,
## never needle clusters. Colors are baked per vertex: lithology-tinted rock,
## warped strata, cavity AO (blurred-height difference) that carves the
## drainage, turf/scree/conifer on the gentle low ground, and altitude snow
## that sheds on cliffs, packs into couloirs, and caps the summits solid.
## COLOR.a carries the snow mask for the mountain shader's sparkle pass.

const MOUNTAIN_SEED: int = 20260718
const BASE_Y: float = -12.0
const HAZE_COLOR: Color = Color(0.72, 0.82, 0.9)

## Authored skylines: [world_x, height_m, gaussian_half_width_m] per summit.
## Irregular spacing on purpose — nothing kills a range like periodicity.
const SUMMITS_MAIN: Array = [
	[-1150.0, 286.0, 170.0],
	[-880.0, 306.0, 170.0],
	[-620.0, 352.0, 185.0],
	[-350.0, 292.0, 145.0],
	[-140.0, 334.0, 150.0],
	[80.0, 402.0, 215.0],  # the monarch
	[290.0, 318.0, 140.0],
	[560.0, 364.0, 195.0],
	[880.0, 302.0, 160.0],
	[1150.0, 292.0, 175.0],
]
const SUMMITS_FAR: Array = [
	[-1550.0, 640.0, 320.0],
	[-1050.0, 640.0, 320.0],
	[-580.0, 692.0, 300.0],
	[-160.0, 655.0, 280.0],
	[320.0, 760.0, 330.0],
	[820.0, 700.0, 300.0],
	[1300.0, 620.0, 320.0],
	[1750.0, 600.0, 330.0],
]
const SUMMITS_FOOT: Array = [
	[-950.0, 108.0, 180.0],
	[-720.0, 118.0, 180.0],
	[-430.0, 96.0, 160.0],
	[-170.0, 126.0, 170.0],
	[140.0, 104.0, 160.0],
	[420.0, 122.0, 175.0],
	[700.0, 100.0, 160.0],
	[950.0, 95.0, 170.0],
]

## Rank configs. curve recesses the strip parabolically at |x| so the wall
## bends around the meadow instead of standing like a billboard.
## snow_frac > 1.0 disables snow (foothills). haze pre-bakes aerial
## perspective into the vertex colors — each rank a step paler and cooler.
const RANKS: Array = [
	{"name": "foot", "zc": -450.0, "depth": 260.0, "xh": 1150.0,
		"base_frac": 0.55, "step": 6.0, "haze": 0.05, "snow_frac": 2.5,
		"curve": 180.0},
	{"name": "main", "zc": -760.0, "depth": 360.0, "xh": 1500.0,
		"base_frac": 0.60, "step": 6.0, "haze": 0.13, "snow_frac": 0.70,
		"curve": 220.0},
	{"name": "far", "zc": -1060.0, "depth": 460.0, "xh": 2000.0,
		"base_frac": 0.62, "step": 10.0, "haze": 0.52, "snow_frac": 0.44,
		"curve": 340.0},
]

const ROCK_WARM: Color = Color(0.302, 0.262, 0.23)
const ROCK_COOL: Color = Color(0.208, 0.226, 0.288)
const SCREE: Color = Color(0.398, 0.362, 0.312)
const TURF_SAGE: Color = Color(0.352, 0.408, 0.262)
const CONIFER: Color = Color(0.172, 0.248, 0.176)
const SNOW_SUN: Color = Color(0.93, 0.948, 0.985)
const SNOW_SHADE: Color = Color(0.796, 0.852, 0.95)

var _ridge: FastNoiseLite
var _warp_x: FastNoiseLite
var _warp_z: FastNoiseLite
var _gully: FastNoiseLite
var _crest_n: FastNoiseLite
var _snowline: FastNoiseLite
var _litho: FastNoiseLite
var _strata_warp: FastNoiseLite
var _crag: FastNoiseLite
var _apron: FastNoiseLite
var _forest: FastNoiseLite


func _init() -> void:
	_ridge = _make_noise(MOUNTAIN_SEED + 10, 0.0028, 4, true)
	_warp_x = _make_noise(MOUNTAIN_SEED + 11, 0.0011, 2, false)
	_warp_z = _make_noise(MOUNTAIN_SEED + 12, 0.0011, 2, false)
	_gully = _make_noise(MOUNTAIN_SEED + 13, 0.0095, 3, true)
	_crest_n = _make_noise(MOUNTAIN_SEED + 14, 0.0018, 2, false)
	_snowline = _make_noise(MOUNTAIN_SEED + 15, 0.004, 2, false)
	_litho = _make_noise(MOUNTAIN_SEED + 16, 0.0021, 2, false)
	_strata_warp = _make_noise(MOUNTAIN_SEED + 17, 0.008, 2, false)
	_crag = _make_noise(MOUNTAIN_SEED + 18, 0.03, 3, false)
	_apron = _make_noise(MOUNTAIN_SEED + 19, 0.012, 2, false)
	_forest = _make_noise(MOUNTAIN_SEED + 20, 0.016, 3, false)


func _ready() -> void:
	var start_ms: int = Time.get_ticks_msec()
	var total_verts: int = 0
	for rank in RANKS:
		total_verts += _build_rank(rank)
	print("GradientPeaks: 3 ranks, %d verts in %d ms." % [
		total_verts, Time.get_ticks_msec() - start_ms,
	])


static func _make_noise(seed_v: int, freq: float, octaves: int, ridged: bool) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n


## Connected ridgeline across x: smooth-max of the summit gaussians over an
## undulating base ridge. One massif — cols between summits, never gaps.
static func _crest_profile(x: float, summits: Array, base_frac: float, cn: float) -> float:
	var hmax: float = 0.0
	for s in summits:
		hmax = maxf(hmax, s[1])
	var base: float = hmax * base_frac * (0.82 + 0.18 * cn)
	var acc: float = 0.000000001
	var k: float = 9.0
	for s in summits:
		var dx: float = (x - s[0]) / s[2]
		var g: float = s[1] * exp(-dx * dx)
		acc += exp((g - hmax) / hmax * k)
	var smax: float = hmax + log(acc) * hmax / k
	return maxf(base, smax)


## Separable box blur repeated 3x (≈ gaussian) over a row-major grid.
static func _box_blur(grid: PackedFloat32Array, nx: int, nz: int, k: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = grid.duplicate()
	for _pass in 3:
		var tmp: PackedFloat32Array = PackedFloat32Array()
		tmp.resize(out.size())
		for iz in nz:
			var row: int = iz * nx
			var acc: float = 0.0
			for ix in range(-k, k + 1):
				acc += out[row + clampi(ix, 0, nx - 1)]
			for ix in nx:
				tmp[row + ix] = acc / float(2 * k + 1)
				var add_i: int = clampi(ix + k + 1, 0, nx - 1)
				var sub_i: int = clampi(ix - k, 0, nx - 1)
				acc += out[row + add_i] - out[row + sub_i]
		for ix in nx:
			var acc2: float = 0.0
			for iz in range(-k, k + 1):
				acc2 += tmp[clampi(iz, 0, nz - 1) * nx + ix]
			for iz in nz:
				out[iz * nx + ix] = acc2 / float(2 * k + 1)
				var add_j: int = clampi(iz + k + 1, 0, nz - 1)
				var sub_j: int = clampi(iz - k, 0, nz - 1)
				acc2 += tmp[add_j * nx + ix] - tmp[sub_j * nx + ix]
	return out


func _build_rank(rank: Dictionary) -> int:
	var step: float = rank["step"]
	var xh: float = rank["xh"]
	var zc: float = rank["zc"]
	var depth: float = rank["depth"]
	var summits: Array = SUMMITS_FOOT
	if rank["name"] == "main":
		summits = SUMMITS_MAIN
	elif rank["name"] == "far":
		summits = SUMMITS_FAR

	var nx: int = int(2.0 * xh / step) + 1
	var nz: int = int(1.1 * depth / step) + 1
	var z0: float = zc - depth * 0.55
	var count: int = nx * nz

	var hgt: PackedFloat32Array = PackedFloat32Array()
	var crest_arr: PackedFloat32Array = PackedFloat32Array()
	var ridge_arr: PackedFloat32Array = PackedFloat32Array()
	var couloir_arr: PackedFloat32Array = PackedFloat32Array()
	hgt.resize(count)
	crest_arr.resize(count)
	ridge_arr.resize(count)
	couloir_arr.resize(count)

	# --- pass 1: heights + geometry masks
	for iz in nz:
		var z: float = z0 + float(iz) * step
		for ix in nx:
			var x: float = -xh + float(ix) * step
			var idx: int = iz * nx + ix
			# The arc: recess the strip at |x| so the wall bends around us.
			var z_arc: float = z + rank["curve"] * pow(x / xh, 2.0)
			var v: float = clampf((z_arc - (zc + depth * 0.5)) / (-depth), 0.0, 1.0)

			var wx: float = _warp_x.get_noise_2d(x, z) * 90.0
			var wz: float = _warp_z.get_noise_2d(x, z) * 90.0
			# Big landforms from low-frequency ridged fBm in warped space;
			# ^1.55 sharpens crests without adding sawtooth noise.
			var r: float = (_ridge.get_noise_2d(x + wx, z_arc + wz) + 1.0) * 0.5
			r = pow(r, 1.55)

			var front: float = pow(smoothstep(0.02, 0.62, v), 1.25)
			var back: float = 1.0 - smoothstep(0.62, 1.0, v) * 0.85
			var env: float = front * back

			var cn: float = _crest_n.get_noise_2d(x, z)
			var crest: float = _crest_profile(x, summits, rank["base_frac"], cn)

			var h: float = crest * env * (0.50 + 0.60 * r)

			# Couloirs: ridged channels squashed down-face — the drainage.
			var gn: float = (_gully.get_noise_2d(x + wx * 0.4, z_arc * 0.35) + 1.0) * 0.5
			var couloir: float = pow(1.0 - gn, 2.2)
			h -= couloir * 34.0 * env

			# Talus aprons flaring at the foot.
			h += (1.0 - smoothstep(0.0, 0.3, v)) * (10.0 + 8.0 * _apron.get_noise_2d(x, z))
			# Micro crag, kept small — solidity beats noise.
			h += _crag.get_noise_2d(x, z) * 2.2 * env

			hgt[idx] = maxf(h, 0.0) + BASE_Y
			crest_arr[idx] = crest
			ridge_arr[idx] = r
			couloir_arr[idx] = couloir

	# --- pass 2: crest relaxation — summits become solid horns, not needles.
	var blurred: PackedFloat32Array = _box_blur(hgt, nx, nz, maxi(2, int(14.0 / step)))
	for idx in count:
		var relc: float = (hgt[idx] - BASE_Y) / maxf(crest_arr[idx], 1.0)
		var w: float = smoothstep(0.55, 0.95, relc) * 0.6
		hgt[idx] = hgt[idx] * (1.0 - w) + blurred[idx] * w

	# --- pass 3: cavity AO (blurred-height difference carves the faces).
	var cav_blur: PackedFloat32Array = _box_blur(hgt, nx, nz, maxi(2, int(24.0 / step)))
	var cavity: PackedFloat32Array = PackedFloat32Array()
	cavity.resize(count)
	for idx in count:
		cavity[idx] = clampf((cav_blur[idx] - hgt[idx]) / 18.0, -1.0, 1.0)

	# --- pass 4: positions, normals, colors, indices
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	positions.resize(count)
	normals.resize(count)
	colors.resize(count)
	for iz in nz:
		var z: float = z0 + float(iz) * step
		for ix in nx:
			var x: float = -xh + float(ix) * step
			var idx: int = iz * nx + ix
			var h: float = hgt[idx]
			var hl: float = hgt[iz * nx + maxi(ix - 1, 0)]
			var hr: float = hgt[iz * nx + mini(ix + 1, nx - 1)]
			var hu: float = hgt[maxi(iz - 1, 0) * nx + ix]
			var hd: float = hgt[mini(iz + 1, nz - 1) * nx + ix]
			var nrm: Vector3 = Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			positions[idx] = Vector3(x, h, z)
			normals[idx] = nrm
			colors[idx] = _rank_color(
				rank, x, z, h, nrm, crest_arr[idx], ridge_arr[idx],
				couloir_arr[idx], cavity[idx]
			)

	var indices: PackedInt32Array = PackedInt32Array()
	for iz in nz - 1:
		for ix in nx - 1:
			var a: int = iz * nx + ix
			var b: int = a + 1
			var c: int = a + nx
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
	mat.shader = load("res://assets/shaders/mountain.gdshader")
	mat.set_shader_parameter("haze_color", HAZE_COLOR)
	# The far rank is already deep in baked haze — its shader haze starts
	# closer and pushes harder so it melts into the sky, never pops.
	if rank["name"] == "far":
		mat.set_shader_parameter("haze_start", 700.0)
		mat.set_shader_parameter("haze_max", 0.30)
	mesh.surface_set_material(0, mat)

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = String(rank["name"]).capitalize() + "Rank"
	mi.mesh = mesh
	add_child(mi)
	return count


func _rank_color(
	rank: Dictionary, x: float, z: float, h: float, nrm: Vector3,
	crest: float, ridge: float, couloir: float, cavity: float
) -> Color:
	var haze: float = rank["haze"]
	var snow_frac: float = rank["snow_frac"]
	var is_foot: bool = rank["name"] == "foot"
	var ny: float = nrm.y
	var rel: float = (h - BASE_Y) / maxf(crest, 1.0)

	var litho: float = smoothstep(0.25, 0.75, (_litho.get_noise_2d(x, z) + 1.0) * 0.5)
	var col: Color = ROCK_COOL.lerp(ROCK_WARM, litho)

	# Strata banding, warped so it reads geological, not procedural.
	var sw: float = _strata_warp.get_noise_2d(x, z)
	var strata: float = sin(h * 0.045 + sw * 2.6) * 0.5 + 0.5
	col = col * (0.95 + strata * 0.08)

	# Baked AO: cavity + couloir darken AND cool (sky-lit shadow) — this is
	# what carves the drainage into the faces at vista distance.
	var ao: float = clampf(maxf(cavity, 0.0) * 0.9 + couloir * 0.45, 0.0, 1.0)
	col = col * (1.0 - ao * 0.42)
	col.b += ao * 0.03
	var ridge_hi: float = smoothstep(0.72, 0.95, ridge) * clampf(-cavity, 0.0, 1.0)
	col = col * (1.0 + ridge_hi * 0.1)

	# Gentle low ground: turf, conifer pockets (foothills only), scree.
	var gentle: float = smoothstep(0.8, 0.94, ny)
	var low: float = 1.0 - smoothstep(0.16, 0.42, rel)
	if is_foot:
		low = 1.0 - smoothstep(0.3, 0.65, rel)
	var turf_m: float = gentle * low
	col = col.lerp(TURF_SAGE, turf_m)
	if is_foot:
		var fn: float = (_forest.get_noise_2d(x, z) + 1.0) * 0.5
		var forest: float = smoothstep(0.58, 0.78, fn) * smoothstep(0.74, 0.9, ny) \
			* (1.0 - smoothstep(0.5, 0.75, rel))
		col = col.lerp(CONIFER * (0.9 + 0.2 * fn), forest)
	var scree_m: float = smoothstep(0.62, 0.83, ny) * (1.0 - gentle) \
		* (1.0 - smoothstep(0.3, 0.55, rel))
	col = col.lerp(SCREE, scree_m * 0.7)

	# Snow: noisy altitude line, sheds on cliffs, packs into couloirs,
	# caps the summits solid, wind-scoured on exposed crests.
	var snow: float = 0.0
	if snow_frac <= 1.0:
		var line: float = crest * snow_frac + BASE_Y \
			+ _snowline.get_noise_2d(x, z) * 30.0 - couloir * 40.0
		var alt: float = smoothstep(0.0, 16.0, h - line)
		var hold: float = smoothstep(0.48, 0.78, ny)
		hold = maxf(hold, couloir * 0.9)
		var cap: float = smoothstep(40.0, 90.0, h - line)
		hold = maxf(hold, cap)
		snow = alt * hold
		var scour: float = smoothstep(0.9, 1.0, ridge) \
			* smoothstep(0.5, 0.9, rel) * (1.0 - cap)
		snow *= 1.0 - scour * 0.3
	var snow_col: Color = SNOW_SUN.lerp(SNOW_SHADE, ao * 0.6)
	col = col.lerp(snow_col, snow)

	# Rank haze pre-bake: aerial perspective layering, one step per rank.
	col = col.lerp(HAZE_COLOR, haze)
	col.a = snow  # snow mask → mountain shader sparkle/gloss pass
	return col

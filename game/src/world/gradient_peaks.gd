class_name GradientPeaks
extends StaticBody3D
## Climbable Gradient Peaks — the real, collidable northern range.
##
## Where BorderVistas paints distant mountain silhouettes, this builds a
## genuine heightfield you can walk onto: it rises off the meadow's north seam
## as a steep rock wall, slit by a single graded U-valley that carries the
## player up into a cirque bowl ringed by summits. Authored summits, ridged
## multifractal crests, spur ridges and drainage gullies give the faces their
## specific shape; a saddle pass, an overlook ledge, a summit shoulder and two
## lower benches are flattened into it as "rooms" future content can occupy.
##
## Everything samples one get_height() — mesh, trimesh collision, tree scatter,
## and the named-location markers — so physics always matches what is drawn and
## later systems can drop props onto real ground. All colour lives in vertex
## colour + mountain_terrain.gdshader; nothing is downloaded.

const PEAKS_SEED: int = 20260720

# Footprint. North is -Z; the range fills the band just past the meadow edge.
const NEAR_Z: float = -240.0      # shared seam line with the meadow's north edge
const FAR_Z: float = -724.0       # hand-off to BorderVistas' distant snow giants
const WEST_X: float = -474.0
const EAST_X: float = 474.0
const RENDER_STEP: float = 2.0    # metres between drawn vertices — the finest
                                  # authored feature is ~11 m, so this loses no
                                  # visible detail (the shader carries sub-2 m)
const COLLIDE_STEP: float = 3.0   # metres between physics vertices (same height source)

const RANGE_BASE: float = 172.0   # interior valley-floor datum the front wall climbs to
const FRONT_SPAN: float = 96.0    # metres of depth the seam→range wall occupies
const SEAM_BLEND_DEPTH: float = 30.0
const SEAM_TUCK: float = 0.18     # sink the seam edge under the meadow: hides the crack
                                  # without making a lip the capsule can't roll over

const SEAM_REF: float = 24.0      # altitude datum for normalized height (meadow floor)
const HIGH_REF: float = 520.0     # the tallest summit — the top of the 0..1 altitude ramp
const RIDGE_AMP: float = 74.0     # ridged-crest relief on the upper faces
const SHELF_STRENGTH: float = 0.9 # how hard authored pads pull the surface to their datum

const MOUNTAIN_SHADER_PATH: String = "res://assets/shaders/mountain_terrain.gdshader"
const TOON_SOFT_SHADER_PATH: String = "res://assets/shaders/toon_soft.gdshader"

## Named anchors, filled during the build — Vector3 world positions on the
## surface. Future POI / monster / shrine placement queries these by name.
var named_locations: Dictionary = {}

var _terrain: MeadowTerrain
var _ridged: FastNoiseLite = FastNoiseLite.new()
var _chute: FastNoiseLite = FastNoiseLite.new()
var _rubble: FastNoiseLite = FastNoiseLite.new()
var _detail: FastNoiseLite = FastNoiseLite.new()
var _tint: FastNoiseLite = FastNoiseLite.new()

# (x, z, base_radius, peak_world_y). Hand-placed so the skyline has recognizable
# landmark summits rather than an even comb of cones.
var _summits: Array[Vector4] = [
	Vector4(-185.0, -560.0, 236.0, 520.0),  # the Summit (west) — the tallest, snow-crowned
	Vector4(35.0, -658.0, 214.0, 486.0),    # North Wall — the back rampart of the cirque
	Vector4(232.0, -548.0, 222.0, 452.0),   # East Peak
	Vector4(-362.0, -604.0, 212.0, 430.0),  # west flank giant
	Vector4(398.0, -612.0, 208.0, 408.0),   # east flank giant
	Vector4(-74.0, -468.0, 152.0, 300.0),   # west gate crag (flanks the valley mouth)
	Vector4(152.0, -452.0, 150.0, 316.0),   # east gate crag
]
# 0 = broad compound crown, 1 = sharp needle. Governs the summit falloff exponent.
var _summit_sharp: PackedFloat32Array = PackedFloat32Array(
	[0.86, 0.7, 0.78, 0.58, 0.58, 0.46, 0.5]
)

# Spur ridges radiating off the summits (x0,z0 -> x1,z1) and the gullies that
# drain between them. Authored so the primary ridgelines read as deliberate.
# The last seven spurs are the frontal BUTTRESSES: ribs that run down the range
# wall toward the meadow seam, giving the front the spur-and-gully topography a
# real mountain foot has instead of one smooth rampart.
var _spurs: Array[Vector4] = [
	Vector4(-185.0, -560.0, -140.0, -410.0),
	Vector4(-185.0, -560.0, -300.0, -470.0),
	Vector4(35.0, -658.0, 70.0, -520.0),
	Vector4(35.0, -658.0, -30.0, -560.0),
	Vector4(232.0, -548.0, 300.0, -430.0),
	Vector4(232.0, -548.0, 190.0, -470.0),
	Vector4(-388.0, -420.0, -366.0, -252.0),
	Vector4(-266.0, -430.0, -286.0, -254.0),
	Vector4(-148.0, -412.0, -128.0, -250.0),
	Vector4(-30.0, -424.0, -18.0, -252.0),
	Vector4(210.0, -408.0, 224.0, -250.0),
	Vector4(316.0, -428.0, 300.0, -254.0),
	Vector4(422.0, -416.0, 438.0, -252.0),
]
var _spur_width: PackedFloat32Array = PackedFloat32Array(
	[46.0, 52.0, 42.0, 44.0, 50.0, 40.0, 40.0, 36.0, 34.0, 38.0, 36.0, 40.0, 38.0]
)
var _spur_strength: PackedFloat32Array = PackedFloat32Array(
	[34.0, 30.0, 30.0, 26.0, 30.0, 24.0, 30.0, 26.0, 24.0, 26.0, 24.0, 28.0, 26.0]
)
var _gullies: Array[Vector4] = [
	Vector4(-150.0, -470.0, -120.0, -300.0),
	Vector4(90.0, -560.0, 105.0, -400.0),
	Vector4(-40.0, -600.0, -70.0, -470.0),
	Vector4(270.0, -520.0, 300.0, -400.0),
	Vector4(-330.0, -420.0, -322.0, -256.0),
	Vector4(-206.0, -426.0, -196.0, -254.0),
	Vector4(-84.0, -414.0, -76.0, -252.0),
	Vector4(262.0, -418.0, 268.0, -254.0),
	Vector4(374.0, -422.0, 366.0, -254.0),
]
var _gully_width: PackedFloat32Array = PackedFloat32Array(
	[34.0, 32.0, 30.0, 30.0, 28.0, 26.0, 26.0, 26.0, 28.0]
)
var _gully_depth: PackedFloat32Array = PackedFloat32Array(
	[30.0, 26.0, 24.0, 22.0, 26.0, 24.0, 22.0, 22.0, 24.0]
)

# Flattened rooms cut into the final surface (x, z, radius, target_world_y).
# Targets are authored close to the local wall height so each room shelves into
# the mountainside; get_height presses the inner floor nearly flat.
var _pads: Array[Vector4] = [
	Vector4(-96.0, -566.0, 66.0, 250.0),    # the Saddle — the pass over the west rim
	Vector4(-153.0, -566.0, 58.0, 348.0),   # West Summit shoulder — the reachable top
	Vector4(150.0, -432.0, 50.0, 185.0),    # Overshoot Ledge — the meadow overlook
	Vector4(12.0, -332.0, 26.0, 150.0),     # Cairn Bench (west of the valley mouth)
	Vector4(96.0, -350.0, 26.0, 158.0),     # Cairn Bench (east of the valley mouth)
]
var _pad_strength: PackedFloat32Array = PackedFloat32Array([0.985, 0.98, 0.98, 0.97, 0.97])

# Walkable channels carved toward a rising floor. The main valley threads the
# front wall and opens into the bowl; the ramp lifts the pass to the shoulder.
var _channels: Array[Dictionary] = []


func setup(terrain: MeadowTerrain) -> void:
	_terrain = terrain
	_configure_noise()
	_configure_channels()
	var start_ms: int = Time.get_ticks_msec()
	_build_surface()
	_scatter_conifers()
	_scatter_boulders()
	_plant_location_markers()
	print("GradientPeaks: climbable range %.0fx%.0f m built in %d ms (%d anchors)." % [
		EAST_X - WEST_X, NEAR_Z - FAR_Z, Time.get_ticks_msec() - start_ms, named_locations.size(),
	])


## The one height everything trusts. World (x,z) in metres -> surface world Y.
func get_height(x: float, z: float) -> float:
	var seam_h: float = _seam_height(x)
	# The wall's rise varies along its length: embayments where the interior
	# datum sits lower and the climb runs deep, thrusting buttress bases where
	# it comes up fast. One low-frequency noise drives both so the range front
	# reads as bays and headlands rather than a levee.
	var front_shape: float = _ridged.get_noise_2d(x * 0.35, -111.0)
	var local_base: float = RANGE_BASE + front_shape * 44.0
	var local_span: float = FRONT_SPAN * (1.0 + front_shape * 0.45)
	var climb: float = smoothstep(0.0, local_span, NEAR_Z - z)
	var floor_level: float = lerpf(seam_h, local_base, climb)

	# Summit envelope: each kernel lifts the floor toward its peak, smooth-max'd
	# so overlapping summits meet in natural cols instead of hard creases.
	var p: Vector2 = Vector2(x, z)
	var relief: float = 0.0
	for i in _summits.size():
		var s: Vector4 = _summits[i]
		var d: float = (p - Vector2(s.x, s.y)).length() / s.z
		var falloff: float = pow(maxf(1.0 - d, 0.0), lerpf(1.7, 3.3, _summit_sharp[i]))
		relief = _smooth_max(relief, (s.w - floor_level) * falloff, 46.0)
	var h: float = floor_level + relief

	# Ridged multifractal + authored spurs shape every raised face — including
	# the frontal wall itself, which is why 'above' measures height over the
	# SEAM, not over the local datum. The walkable channels are carved after
	# and the seam band is masked, so the routes stay smooth where it matters.
	var above: float = clampf((h - seam_h - 14.0) / 110.0, 0.0, 1.0)
	above *= smoothstep(6.0, 30.0, NEAR_Z - z)
	if above > 0.001:
		var ridged: float = _ridged.get_noise_2d(x, z) * 0.5 + 0.5
		h += (ridged - 0.4) * RIDGE_AMP * above
		for i in _spurs.size():
			var metric: Vector2 = _segment_metric(p, _spurs[i])
			var infl: float = pow(maxf(1.0 - metric.y / _spur_width[i], 0.0), 2.0)
			h += infl * _spur_strength[i] * above
		for i in _gullies.size():
			var gm: Vector2 = _segment_metric(p, _gullies[i])
			var cut: float = pow(maxf(1.0 - gm.y / _gully_width[i], 0.0), 1.7)
			h -= cut * _gully_depth[i] * above * smoothstep(0.05, 0.5, gm.x)
		# Erosion detail: avalanche chutes rake the raised faces, and metre-scale
		# rubble keeps every slope from interpolating glass-smooth.
		var chute: float = _chute.get_noise_2d(x, z) * 0.5 + 0.5
		h -= chute * chute * 9.5 * above
		h += _rubble.get_noise_2d(x, z) * 1.35 * above

	# Channels are sampled once up front: their mask both carves the trails
	# (below, with the last word) and tells the rooms where to stand aside.
	var channel_samples: Array[Dictionary] = []
	var trail_mask: float = 0.0
	for channel in _channels:
		var sample: Dictionary = _channel_sample(p, channel)
		channel_samples.append(sample)
		trail_mask = maxf(trail_mask, sample["mask"])

	# Flatten the authored rooms into whatever the faces left there: a plateau
	# profile pressed almost totally flat (ridged-noise creases are locally
	# near-vertical, so anything less leaves unwalkable spikes), then gentle
	# rubble undulation and a rim-ward dish added BACK deliberately so the
	# floor reads as mountain ground rather than a stamped disc. Rooms yield
	# to the trail corridor (the 1 - trail_mask factor): where a switchback
	# climbs out through a room it keeps its graded floor and cuts a real
	# embankment through the shelf, instead of the two flattenings fighting.
	for i in _pads.size():
		var pad: Vector4 = _pads[i]
		var pd: float = (p - Vector2(pad.x, pad.y)).length()
		var w: float = 1.0 - smoothstep(pad.z * 0.55, pad.z, pd)
		w *= 1.0 - trail_mask
		if w > 0.001:
			var room_floor: float = pad.w \
					+ _rubble.get_noise_2d(x * 1.3, z * 1.3) * 1.1 \
					+ pow(pd / pad.z, 2.0) * 3.0
			h = lerpf(h, room_floor, w * _pad_strength[i])

	# The walkable channels (valley, switchback ramp) carve LAST — a graded
	# trail keeps its promised floor everywhere along its length.
	for sample in channel_samples:
		h = lerpf(h, sample["floor"], sample["mask"])

	# Marry the near edge exactly to the meadow so grass meets rock with no crack.
	var seam_t: float = smoothstep(NEAR_Z - SEAM_BLEND_DEPTH, NEAR_Z, z)
	h = lerpf(h, seam_h - SEAM_TUCK, seam_t)
	return h


func in_bounds(x: float, z: float) -> bool:
	return x >= WEST_X and x <= EAST_X and z <= NEAR_Z and z >= FAR_Z


func _configure_noise() -> void:
	_ridged.seed = PEAKS_SEED
	_ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridged.frequency = 0.0045
	_ridged.fractal_octaves = 5
	_ridged.fractal_lacunarity = 2.1
	_ridged.fractal_gain = 0.52
	_ridged.domain_warp_enabled = true
	_ridged.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_ridged.domain_warp_amplitude = 42.0
	_ridged.domain_warp_frequency = 0.006
	# Avalanche chutes / couloirs: tighter ridged noise that streaks the faces
	# with parallel runnels a few tens of metres apart.
	_chute.seed = PEAKS_SEED + 7
	_chute.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_chute.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_chute.frequency = 0.02
	_chute.fractal_octaves = 3
	# Metre-scale rubble bumps so no face interpolates glass-smooth.
	_rubble.seed = PEAKS_SEED + 11
	_rubble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rubble.frequency = 0.085
	_rubble.fractal_octaves = 2
	_detail.seed = PEAKS_SEED + 17
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.03
	_detail.fractal_octaves = 3
	_tint.seed = PEAKS_SEED + 41
	_tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tint.frequency = 0.05
	_tint.fractal_octaves = 2


## The valley mouth sits at the meadow floor and climbs, widening into the bowl;
## the ramp lifts the saddle to the summit shoulder. Floor Y and the flat/rim
## half-widths are per node, interpolated along each polyline.
func _configure_channels() -> void:
	_channels = [
		{
			"nodes": [
				Vector3(56.0, -286.0, 30.0),
				Vector3(56.0, -360.0, 68.0),
				Vector3(48.0, -442.0, 122.0),
				Vector3(42.0, -524.0, 172.0),
				Vector3(38.0, -602.0, 208.0),   # the Vale — cirque floor
			],
			"floor_w": PackedFloat32Array([16.0, 17.0, 19.0, 24.0, 54.0]),
			"rim_w": PackedFloat32Array([40.0, 44.0, 50.0, 60.0, 96.0]),
		},
		{
			# Switchbacks: ~32° sustained grade — a mountain trail Kern can walk
			# without ever pressing the 45° floor limit.
			"nodes": [
				Vector3(-96.0, -566.0, 252.0),  # the Saddle
				Vector3(-126.0, -598.0, 280.0),
				Vector3(-156.0, -586.0, 301.0),
				Vector3(-138.0, -560.0, 321.0),
				Vector3(-160.0, -548.0, 337.0),
				Vector3(-153.0, -564.0, 348.0), # the shoulder
			],
			"floor_w": PackedFloat32Array([15.0, 13.0, 12.0, 12.0, 13.0, 16.0]),
			"rim_w": PackedFloat32Array([34.0, 30.0, 28.0, 28.0, 30.0, 34.0]),
		},
	]


## Meadow height at the seam for a given x, so the wall foot lands exactly on
## the meadow's rolling edge. Beyond the meadow's width the edge value extends.
func _seam_height(x: float) -> float:
	if _terrain == null:
		return SEAM_REF
	var clamped_x: float = clampf(x, -MeadowTerrain.SIZE * 0.5 + 2.0, MeadowTerrain.SIZE * 0.5 - 2.0)
	return _terrain.get_height(clamped_x, NEAR_Z + 1.0)


## Smooth maximum (polynomial). Blends two heights over a band of width k so
## intersecting summit kernels form rounded saddles rather than sharp seams.
func _smooth_max(a: float, b: float, k: float) -> float:
	var m: float = maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + m * m * k * 0.25


## Progress along the segment in x, perpendicular distance in y.
func _segment_metric(point: Vector2, segment: Vector4) -> Vector2:
	var start: Vector2 = Vector2(segment.x, segment.y)
	var finish: Vector2 = Vector2(segment.z, segment.w)
	var line: Vector2 = finish - start
	var length_squared: float = maxf(line.length_squared(), 0.00001)
	var progress: float = clampf((point - start).dot(line) / length_squared, 0.0, 1.0)
	return Vector2(progress, point.distance_to(start + line * progress))


## Carve floor and mask for a point near a channel polyline. Every in-range
## segment CONTRIBUTES, weighted by proximity, instead of only the nearest one
## winning — where switchback legs pass close to each other the floors blend
## into one terraced ramp rather than flickering between two heights and
## leaving a cliff on the trail itself.
func _channel_sample(point: Vector2, channel: Dictionary) -> Dictionary:
	var nodes: Array = channel["nodes"]
	var floor_w: PackedFloat32Array = channel["floor_w"]
	var rim_w: PackedFloat32Array = channel["rim_w"]
	var weight_sum: float = 0.0
	var floor_sum: float = 0.0
	var mask: float = 0.0
	for i in nodes.size() - 1:
		var a: Vector3 = nodes[i]
		var b: Vector3 = nodes[i + 1]
		var metric: Vector2 = _segment_metric(point, Vector4(a.x, a.y, b.x, b.y))
		var flat: float = lerpf(floor_w[i], floor_w[i + 1], metric.x)
		var rim: float = lerpf(rim_w[i], rim_w[i + 1], metric.x)
		var seg_mask: float = 1.0 - smoothstep(flat, rim, metric.y)
		if seg_mask <= 0.0:
			continue
		# Inverse-cubed distance: on a segment's centreline its own floor
		# dominates ~1000:1, so far end-caps can't tilt a straight trail, while
		# two switchback legs passing close still blend into one terrace.
		var seg_weight: float = pow(1.0 / (metric.y + 3.0), 3.0)
		weight_sum += seg_weight
		floor_sum += lerpf(a.z, b.z, metric.x) * seg_weight
		mask = maxf(mask, seg_mask)
	if weight_sum <= 0.0:
		return {"floor": 0.0, "mask": 0.0}
	return {"floor": floor_sum / weight_sum, "mask": mask}


## Distance from (x,z) to the nearest walkable-channel centreline, turned into
## a 1-on-the-path / 0-off-it mask. Paints the worn dirt track and steers the
## conifer scatter off the routes.
func _track_mask(p: Vector2) -> float:
	var nearest: float = INF
	for channel in _channels:
		var nodes: Array = channel["nodes"]
		for i in nodes.size() - 1:
			var a: Vector3 = nodes[i]
			var b: Vector3 = nodes[i + 1]
			var metric: Vector2 = _segment_metric(p, Vector4(a.x, a.y, b.x, b.y))
			nearest = minf(nearest, metric.y)
	return 1.0 - smoothstep(2.6, 5.4, nearest)


func _build_surface() -> void:
	# The drawn surface runs at double the physics resolution: close-range
	# fidelity where the player's eyes are, while collision (which the player's
	# feet can't tell apart at 3 m) stays a quarter the triangle count.
	var render_mesh: ArrayMesh = _build_grid_mesh(RENDER_STEP, true)
	render_mesh.surface_set_material(0, _make_surface_material())
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "PeaksMesh"
	mesh_instance.mesh = render_mesh
	add_child(mesh_instance)

	var collision_mesh: ArrayMesh = _build_grid_mesh(COLLIDE_STEP, false)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "PeaksCollision"
	collision.shape = collision_mesh.create_trimesh_shape()
	add_child(collision)


func _build_grid_mesh(step: float, with_surface_data: bool) -> ArrayMesh:
	var width: int = int((EAST_X - WEST_X) / step) + 1
	var depth: int = int((NEAR_Z - FAR_Z) / step) + 1
	var count: int = width * depth
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(count)
	for iz in depth:
		var z: float = NEAR_Z - iz * step
		for ix in width:
			heights[iz * width + ix] = get_height(WEST_X + ix * step, z)

	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	positions.resize(count)
	normals.resize(count)
	if with_surface_data:
		colors.resize(count)
		uvs.resize(count)

	for iz in depth:
		var z: float = NEAR_Z - iz * step
		for ix in width:
			var x: float = WEST_X + ix * step
			var idx: int = iz * width + ix
			var h: float = heights[idx]
			var hl: float = heights[iz * width + maxi(ix - 1, 0)]
			var hr: float = heights[iz * width + mini(ix + 1, width - 1)]
			var hu: float = heights[maxi(iz - 1, 0) * width + ix]
			var hd: float = heights[mini(iz + 1, depth - 1) * width + ix]
			var normal: Vector3 = Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			positions[idx] = Vector3(x, h, z)
			normals[idx] = normal
			if with_surface_data:
				var slope: float = 1.0 - normal.y
				var alt: float = clampf((h - SEAM_REF) / (HIGH_REF - SEAM_REF), 0.0, 1.0)
				var flatness: float = 1.0 - smoothstep(0.12, 0.42, slope)
				var track: float = _track_mask(Vector2(x, z))
				colors[idx] = _surface_color(x, z, slope, alt, flatness, track)
				# The shader's turf pass reads UV.x; pulling it down along the
				# track keeps the painted dirt from being re-greened.
				uvs[idx] = Vector2(flatness * (1.0 - track * 0.72), alt)

	for iz in depth - 1:
		for ix in width - 1:
			var a: int = iz * width + ix
			var b: int = a + 1
			var c: int = a + width
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	if with_surface_data:
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _surface_color(
		x: float, z: float, slope: float, alt: float, flatness: float, track: float
) -> Color:
	var soil: Color = Color(0.285, 0.225, 0.155)
	var rock: Color = Color(0.33, 0.335, 0.35)
	var rock_warm: Color = Color(0.385, 0.35, 0.31)
	var rock_pale: Color = Color(0.5, 0.515, 0.55)
	var scree: Color = Color(0.43, 0.415, 0.39)
	var alpine: Color = Color(0.245, 0.36, 0.14)
	var trodden: Color = Color(0.4, 0.315, 0.205)

	# Steep ground is stone almost immediately — bare dirt only survives on the
	# gentler shoulders, which keeps the big faces reading as rock, not mud.
	var col: Color = soil.lerp(rock, smoothstep(0.16, 0.42, slope))
	# Warm sediment bands wander across the mid faces so the grey has life.
	var band: float = clampf(_tint.get_noise_2d(x * 0.6, z * 0.6) * 0.5 + 0.5, 0.0, 1.0)
	col = col.lerp(rock_warm, band * 0.3 * smoothstep(0.2, 0.5, slope) * (1.0 - smoothstep(0.5, 0.8, alt)))
	# Loose stone gathers low on the steep faces.
	var low_face: float = (1.0 - smoothstep(0.16, 0.5, alt)) * smoothstep(0.34, 0.66, slope)
	col = col.lerp(scree, low_face * 0.45)
	# High rock goes paler and colder as it approaches the snow.
	col = col.lerp(rock_pale, smoothstep(0.55, 0.86, alt) * (1.0 - flatness * 0.4))
	# Alpine turf on the low, walkable benches — the shader deepens it further.
	col = col.lerp(alpine, flatness * (1.0 - smoothstep(0.03, 0.32, alt)))
	# The worn dirt track along the walkable channels: boots and hooves have
	# beaten the turf down to packed earth, ragged at the edges by tint noise.
	var wear: float = clampf(
		track + (_tint.get_noise_2d(x * 2.2, z * 2.2)) * 0.35 * track, 0.0, 1.0
	)
	col = col.lerp(trodden, smoothstep(0.25, 0.85, wear) * 0.88 * flatness)
	var tint: float = clampf(_tint.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	col *= 0.9 + 0.1 * tint
	col.a = 1.0
	return col


func _make_surface_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(MOUNTAIN_SHADER_PATH) as Shader
	material.set_shader_parameter("detail_scale", 0.05)
	material.set_shader_parameter("rock_detail", 0.32)
	material.set_shader_parameter("strata_strength", 0.26)
	material.set_shader_parameter("fracture_strength", 0.24)
	material.set_shader_parameter("dirt_grain", 0.28)
	material.set_shader_parameter("scree_strength", 0.3)
	material.set_shader_parameter("grass_blend", 0.6)
	material.set_shader_parameter("snowline", 0.6)
	material.set_shader_parameter("snow_softness", 0.11)
	material.set_shader_parameter("snow_amount", 0.85)
	material.set_shader_parameter("haze_amount", 0.028)
	material.set_shader_parameter("bump_strength", 1.15)
	material.set_shader_parameter("fill_amount", 0.075)
	material.set_shader_parameter("seed_offset", 3.1)
	return material


## Conifers on the lower, gentler flanks and valley shoulders — scale, life, and
## the "dirt-and-trees" read the player expects at a mountain foot. One shared
## mesh, one MultiMesh; placement is seeded and samples the real surface.
func _scatter_conifers() -> void:
	var mesh: ArrayMesh = _build_conifer_mesh()
	var transforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = PEAKS_SEED + 200
	var step: float = 19.0
	var x: float = WEST_X + 30.0
	while x < EAST_X - 30.0:
		var z: float = NEAR_Z - 24.0
		while z > FAR_Z + 30.0:
			var jx: float = x + rng.randf_range(-8.0, 8.0)
			var jz: float = z + rng.randf_range(-8.0, 8.0)
			var alt: float = clampf((get_height(jx, jz) - SEAM_REF) / (HIGH_REF - SEAM_REF), 0.0, 1.0)
			var normal: Vector3 = _surface_normal(jx, jz)
			var slope: float = 1.0 - normal.y
			# Timberline gates: lower slopes only, off bare cliffs, clear of the
			# walkable tracks, and never straddling a cliff lip (the ring check —
			# a tree whose neighbours are cliff reads as a pasted-on silhouette).
			if alt >= 0.31 or slope < 0.09 or slope > 0.36 or rng.randf() > 0.68:
				z -= step
				continue
			if _track_mask(Vector2(jx, jz)) > 0.04:
				z -= step
				continue
			var ring_ok: bool = true
			for ring_angle in 4:
				var offset: Vector2 = Vector2(3.2, 0.0).rotated(TAU * float(ring_angle) / 4.0)
				var ring_normal: Vector3 = _surface_normal(jx + offset.x, jz + offset.y)
				if 1.0 - ring_normal.y > 0.52:
					ring_ok = false
					break
			if not ring_ok:
				z -= step
				continue
			var ground: float = get_height(jx, jz)
			var s: float = rng.randf_range(0.65, 1.25) * (1.0 - alt * 0.55)
			var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(s * rng.randf_range(0.88, 1.12), s * rng.randf_range(0.92, 1.28), s * rng.randf_range(0.88, 1.12))
			)
			transforms.append(Transform3D(basis, Vector3(jx, ground - 0.35, jz)))
			var shade: float = rng.randf_range(0.82, 1.05)
			tints.append(Color(shade * 0.92, shade, shade * 0.9, 1.0))
			z -= step
		x += step

	if transforms.is_empty():
		return
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, tints[i])
	var trees: MultiMeshInstance3D = MultiMeshInstance3D.new()
	trees.name = "PeakConifers"
	trees.multimesh = multimesh
	add_child(trees)


func _surface_normal(x: float, z: float) -> Vector3:
	var eps: float = COLLIDE_STEP
	var dx: float = get_height(x + eps, z) - get_height(x - eps, z)
	var dz: float = get_height(x, z + eps) - get_height(x, z - eps)
	return Vector3(-dx, 2.0 * eps, -dz).normalized()


## A subalpine spruce built for close range: 12-sided trunk and six stacked,
## sag-edged needle skirts whose radii jitter out of phase, so the silhouette
## is ragged instead of a stack of perfect cones. Needle colors run lighter
## than the horizon trees — at track distance dark facets read as holes.
func _build_conifer_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = Color(0.22, 0.16, 0.1)
	var bark_lit: Color = Color(0.3, 0.215, 0.13)
	var needle_low: Color = Color(0.155, 0.275, 0.185)
	var needle_high: Color = Color(0.275, 0.45, 0.275)
	var segments: int = 12
	for segment in segments:
		var a0: float = TAU * float(segment) / float(segments)
		var a1: float = TAU * float(segment + 1) / float(segments)
		var l0: Vector3 = Vector3(cos(a0) * 0.62, 0.0, sin(a0) * 0.62)
		var l1: Vector3 = Vector3(cos(a1) * 0.62, 0.0, sin(a1) * 0.62)
		var u0: Vector3 = Vector3(cos(a0) * 0.3, 4.5, sin(a0) * 0.3)
		var u1: Vector3 = Vector3(cos(a1) * 0.3, 4.5, sin(a1) * 0.3)
		_tri(st, l0, u0, l1, bark, bark_lit, bark)
		_tri(st, l1, u0, u1, bark, bark_lit, bark_lit)
	var skirts: Array = [
		{"base": 1.9, "top": 5.4, "radius": 4.3, "phase": 0.0},
		{"base": 4.0, "top": 7.6, "radius": 3.8, "phase": 1.7},
		{"base": 6.1, "top": 9.8, "radius": 3.2, "phase": 3.9},
		{"base": 8.2, "top": 11.9, "radius": 2.55, "phase": 0.9},
		{"base": 10.2, "top": 13.8, "radius": 1.9, "phase": 2.8},
		{"base": 12.1, "top": 15.6, "radius": 1.15, "phase": 5.1},
	]
	for skirt in skirts:
		var base_y: float = skirt["base"]
		var top_y: float = skirt["top"]
		var radius: float = skirt["radius"]
		var phase: float = skirt["phase"]
		for segment in segments:
			var a0: float = TAU * float(segment) / float(segments)
			var a1: float = TAU * float(segment + 1) / float(segments)
			var j0: float = 0.82 + 0.3 * absf(sin(a0 * 3.0 + phase)) + 0.1 * sin(a0 * 7.0 - phase)
			var j1: float = 0.82 + 0.3 * absf(sin(a1 * 3.0 + phase)) + 0.1 * sin(a1 * 7.0 - phase)
			var sag0: float = 0.55 * (j0 - 0.82)
			var sag1: float = 0.55 * (j1 - 0.82)
			var b0: Vector3 = Vector3(cos(a0) * radius * j0, base_y - sag0, sin(a0) * radius * j0)
			var b1: Vector3 = Vector3(cos(a1) * radius * j1, base_y - sag1, sin(a1) * radius * j1)
			var apex: Vector3 = Vector3(0.0, top_y, 0.0)
			var tip0: Color = needle_low.lerp(needle_high, clampf((j0 - 0.82) * 2.4, 0.0, 1.0))
			var tip1: Color = needle_low.lerp(needle_high, clampf((j1 - 0.82) * 2.4, 0.0, 1.0))
			_tri(st, b0, apex, b1, tip0, needle_high, tip1)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(TOON_SOFT_SHADER_PATH) as Shader
	material.set_shader_parameter("rim_amount", 0.07)
	material.set_shader_parameter("rim_width", 0.85)
	material.set_shader_parameter("fill_amount", 0.12)
	material.set_shader_parameter("shadow_fill", Color(0.42, 0.55, 0.48))
	material.set_shader_parameter("noise_amount", 0.14)
	material.set_shader_parameter("noise_scale", 0.4)
	mesh.surface_set_material(0, material)
	return mesh


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


## Fallen rock where geology would leave it: clusters at the valley-mouth gate,
## in the Vale, at gully mouths and bench edges, plus lone erratics scattered
## sparse across the lower ground. Three deformed-sphere variants share one
## MultiMesh each; boulders over ~1.8 m also get a collision sphere so the
## player walks around them, not through them.
func _scatter_boulders() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = PEAKS_SEED + 300
	var variants: Array[ArrayMesh] = []
	for variant in 3:
		variants.append(_build_boulder_mesh(variant))
	var placements: Array[Array] = [[], [], []]  # per-variant Transform3D lists

	# Authored clusters: (x, z, spread radius, count).
	var clusters: Array[Vector4] = [
		Vector4(30.0, -300.0, 22.0, 9.0),     # valley-mouth gate, west side
		Vector4(84.0, -312.0, 20.0, 7.0),     # valley-mouth gate, east side
		Vector4(20.0, -590.0, 34.0, 11.0),    # the Vale's cirque floor
		Vector4(74.0, -620.0, 26.0, 8.0),     # below the North Wall
		Vector4(-84.0, -540.0, 20.0, 6.0),    # approach to the Saddle
		Vector4(158.0, -448.0, 18.0, 6.0),    # Overshoot Ledge rim
		Vector4(12.0, -344.0, 14.0, 5.0),     # Cairn Bench West
		Vector4(102.0, -360.0, 14.0, 5.0),    # Cairn Bench East
	]
	for cluster in clusters:
		for i in int(cluster.w):
			var angle: float = rng.randf_range(0.0, TAU)
			var reach: float = sqrt(rng.randf()) * cluster.z
			var bx: float = cluster.x + cos(angle) * reach
			var bz: float = cluster.y + sin(angle) * reach
			_place_boulder(bx, bz, rng, placements, rng.randf_range(0.7, 3.2))

	# Lone erratics over the walkable lower ground.
	for i in 90:
		var bx: float = rng.randf_range(WEST_X + 40.0, EAST_X - 40.0)
		var bz: float = rng.randf_range(FAR_Z + 40.0, NEAR_Z - 20.0)
		var alt: float = clampf((get_height(bx, bz) - SEAM_REF) / (HIGH_REF - SEAM_REF), 0.0, 1.0)
		var slope: float = 1.0 - _surface_normal(bx, bz).y
		if alt < 0.5 and slope < 0.34 and _track_mask(Vector2(bx, bz)) < 0.3:
			_place_boulder(bx, bz, rng, placements, rng.randf_range(0.5, 2.4))

	for variant in 3:
		if placements[variant].is_empty():
			continue
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = variants[variant]
		multimesh.instance_count = placements[variant].size()
		for i in placements[variant].size():
			multimesh.set_instance_transform(i, placements[variant][i])
		var rocks: MultiMeshInstance3D = MultiMeshInstance3D.new()
		rocks.name = "Boulders_%d" % variant
		rocks.multimesh = multimesh
		add_child(rocks)


func _place_boulder(
		bx: float, bz: float, rng: RandomNumberGenerator,
		placements: Array[Array], size: float
) -> void:
	var ground: float = get_height(bx, bz)
	var basis: Basis = Basis.from_euler(Vector3(
		rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, TAU), rng.randf_range(-0.3, 0.3)
	)).scaled(Vector3(
		size * rng.randf_range(0.8, 1.25),
		size * rng.randf_range(0.62, 0.95),
		size * rng.randf_range(0.8, 1.25)
	))
	# Sit a quarter into the ground — a boulder resting ON the surface reads
	# as dropped there by a level designer, half-buried reads as geology.
	var origin: Vector3 = Vector3(bx, ground - size * 0.22, bz)
	placements[rng.randi_range(0, 2)].append(Transform3D(basis, origin))
	if size > 1.8:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = size * 0.72
		shape.shape = sphere
		shape.position = origin
		add_child(shape)


## A glacial boulder: UV-sphere squashed and knocked about by radial noise so
## every silhouette is lumpy, with pale up-facing weathering baked per vertex.
func _build_boulder_mesh(variant: int) -> ArrayMesh:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = PEAKS_SEED + 500 + variant * 37
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.9
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = 7
	var segments: int = 10
	var base_grey: Color = Color(0.36, 0.355, 0.345)
	var top_pale: Color = Color(0.5, 0.5, 0.49)
	var under_dark: Color = Color(0.24, 0.235, 0.235)
	var points: Array[Vector3] = []
	var colors: Array[Color] = []
	for ring in rings + 1:
		var v: float = float(ring) / float(rings)
		var polar: float = v * PI
		for segment in segments:
			var azimuth: float = TAU * float(segment) / float(segments)
			var direction: Vector3 = Vector3(
				sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth)
			)
			var wobble: float = 1.0 + noise.get_noise_3d(
				direction.x * 2.2, direction.y * 2.2, direction.z * 2.2
			) * 0.34
			points.append(direction * wobble)
			var up_weathering: float = clampf(direction.y * 0.5 + 0.5, 0.0, 1.0)
			var color: Color = under_dark.lerp(base_grey, smoothstep(0.0, 0.45, up_weathering))
			color = color.lerp(top_pale, smoothstep(0.55, 1.0, up_weathering))
			color *= 0.92 + 0.08 * noise.get_noise_3d(direction.z * 5.0, direction.x * 5.0, 1.0)
			colors.append(color)
	for ring in rings:
		for segment in segments:
			var next_segment: int = (segment + 1) % segments
			var a: int = ring * segments + segment
			var b: int = ring * segments + next_segment
			var c: int = (ring + 1) * segments + segment
			var d: int = (ring + 1) * segments + next_segment
			_tri(st, points[a], points[c], points[b], colors[a], colors[c], colors[b])
			_tri(st, points[b], points[c], points[d], colors[b], colors[c], colors[d])
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(TOON_SOFT_SHADER_PATH) as Shader
	material.set_shader_parameter("rim_amount", 0.06)
	material.set_shader_parameter("rim_width", 0.84)
	material.set_shader_parameter("fill_amount", 0.09)
	material.set_shader_parameter("noise_amount", 0.16)
	material.set_shader_parameter("noise_scale", 1.4)
	mesh.surface_set_material(0, material)
	return mesh


## Drop invisible anchors on the surface at each authored room and register them
## in a group so a future landmarks/POI pass can find real ground to build on.
func _plant_location_markers() -> void:
	var spots: Dictionary = {
		"Valley Mouth": Vector2(56.0, -300.0),
		"The Vale": Vector2(38.0, -602.0),
		"The Saddle": Vector2(-96.0, -566.0),
		"West Summit Shoulder": Vector2(-153.0, -564.0),
		"Overshoot Ledge": Vector2(150.0, -432.0),
		"Cairn Bench West": Vector2(12.0, -332.0),
		"Cairn Bench East": Vector2(96.0, -350.0),
	}
	for label in spots:
		var flat: Vector2 = spots[label]
		var pos: Vector3 = Vector3(flat.x, get_height(flat.x, flat.y), flat.y)
		named_locations[label] = pos
		var marker: Marker3D = Marker3D.new()
		marker.name = "Anchor_" + String(label).replace(" ", "")
		marker.position = pos
		marker.add_to_group("peak_landmark")
		add_child(marker)

class_name BorderVistas
extends Node3D
## Region-border vistas — Phase 1 milestone 3 (the BOTW rule, GDD §2 pillar 4:
## "if it looks interesting from a distance, something is actually there").
##
## Distant, cheap, evocative geometry ringing the meadow, one hint per
## neighboring region: the Gradient Peaks serrating the north sky, the Latent
## Forest as a dark tree-wall east, the sea of Convolution Coast glinting
## west, and low rolling downs south. Distance haze (fog in the Environment)
## does the atmospheric work. All deterministic, all generated in code.

const VISTA_SEED: int = 20260718

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = VISTA_SEED
	_raise_gradient_peaks()
	_grow_latent_forest_wall()
	_lay_convolution_sea()
	_roll_southern_downs()
	print("BorderVistas: peaks north, forest east, sea west, downs south.")


## A real ridged mountain: radial ring mesh whose radius wanders with noise
## per bearing (jagged spurs and gullies), craggy vertical jitter, and
## altitude/slope-based vertex colors — slate rock, darker gully shadows,
## snow above a wandering snowline. Fog supplies the aerial haze; SDFGI and
## the soft shader light it like terrain, not like a paper cutout.
func _build_peak_mesh(base_r: float, height: float) -> ArrayMesh:
	var segs: int = 26
	var rings: int = 9
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock: Color = Color(0.32, 0.34, 0.42)
	var gully: Color = Color(0.22, 0.24, 0.32)
	var snow: Color = Color(0.93, 0.95, 0.99)
	var snowline: float = height * _rng.randf_range(0.48, 0.6)

	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for ring in rings + 1:
		var t: float = float(ring) / float(rings)
		for s in segs:
			var a: float = TAU * float(s) / float(segs)
			var ridge: float = noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0)
			var spur: float = 1.0 + ridge * 0.5 * (1.0 - t * 0.6)
			var r: float = base_r * pow(1.0 - t, 1.2) * spur
			var y: float = height * t + noise.get_noise_2d(a * 3.0, t * 6.0) * height * 0.06
			if ring == rings:
				r = 0.0
				y = height * (1.0 + ridge * 0.04)
			verts.append(Vector3(cos(a) * r, y, sin(a) * r))
			var c: Color = rock.lerp(gully, clampf(-ridge * 1.4, 0.0, 1.0))
			if y > snowline + ridge * height * 0.08:
				c = snow
			cols.append(c)
	for ring in rings:
		for s in segs:
			var a0: int = ring * segs + s
			var a1: int = ring * segs + (s + 1) % segs
			var b0: int = (ring + 1) * segs + s
			var b1: int = (ring + 1) * segs + (s + 1) % segs
			for idx in [a0, b0, a1, a1, b0, b1]:
				st.set_color(cols[idx])
				st.add_vertex(verts[idx])
	st.generate_normals()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/toon_soft.gdshader")
	mat.set_shader_parameter("rim_amount", 0.08)
	mat.set_shader_parameter("fill_amount", 0.16)
	mat.set_shader_parameter("noise_amount", 0.08)
	mat.set_shader_parameter("noise_scale", 0.12)
	st.set_material(mat)
	return st.commit()


func _raise_gradient_peaks() -> void:
	var peaks: Node3D = Node3D.new()
	peaks.name = "GradientPeaks"
	add_child(peaks)
	# Two ranks: craggy foothills in front, tall snow-capped rank behind.
	for i in 11:
		var x: float = -620.0 + 124.0 * float(i) + _rng.randf_range(-30.0, 30.0)
		var back: bool = i % 2 == 0
		var base_r: float = _rng.randf_range(130.0, 220.0) * (1.3 if back else 0.85)
		var height: float = _rng.randf_range(200.0, 310.0) * (1.35 if back else 0.7)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = _build_peak_mesh(base_r, height)
		mi.position = Vector3(x, -12.0, -770.0 if back else -640.0)
		mi.rotation.y = _rng.randf_range(0.0, TAU)
		peaks.add_child(mi)


func _grow_latent_forest_wall() -> void:
	var wall: Node3D = Node3D.new()
	wall.name = "LatentForestWall"
	add_child(wall)
	var deep_green: StandardMaterial3D = StandardMaterial3D.new()
	deep_green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	deep_green.albedo_color = Color(0.2, 0.3, 0.24)
	for i in 34:
		var z: float = -480.0 + 30.0 * float(i) + _rng.randf_range(-10.0, 10.0)
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = _rng.randf_range(22.0, 40.0)
		cone.height = _rng.randf_range(55.0, 95.0)
		cone.radial_segments = 6
		cone.rings = 1
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = deep_green
		mi.position = Vector3(560.0 + _rng.randf_range(-25.0, 45.0), cone.height * 0.3, z)
		wall.add_child(mi)


func _lay_convolution_sea() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1400.0, 1600.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.3, 0.42)
	mat.roughness = 0.05
	mat.metallic = 0.55
	plane.material = mat
	var sea: MeshInstance3D = MeshInstance3D.new()
	sea.name = "ConvolutionSea"
	sea.mesh = plane
	sea.position = Vector3(-980.0, -14.0, 0.0)
	add_child(sea)


func _roll_southern_downs() -> void:
	var downs: Node3D = Node3D.new()
	downs.name = "SouthernDowns"
	add_child(downs)
	var soft_green: StandardMaterial3D = StandardMaterial3D.new()
	soft_green.albedo_color = Color(0.35, 0.47, 0.27)
	soft_green.roughness = 1.0
	for i in 7:
		var x: float = -540.0 + 180.0 * float(i) + _rng.randf_range(-40.0, 40.0)
		var hill: SphereMesh = SphereMesh.new()
		hill.radius = _rng.randf_range(140.0, 240.0)
		hill.height = _rng.randf_range(60.0, 110.0)
		hill.radial_segments = 8
		hill.rings = 4
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = hill
		mi.material_override = soft_green
		mi.position = Vector3(x, -8.0, 640.0 + _rng.randf_range(-40.0, 60.0))
		downs.add_child(mi)

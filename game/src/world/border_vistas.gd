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


func _peak_material(shade: float) -> StandardMaterial3D:
	# Distant mountains are haze silhouettes, not lit geometry — shaded
	# cones tilt their faces sunward and blow out to pastel. Unshaded flat
	# color (fog still applies) is exactly the BOTW horizon look.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.29, 0.35, 0.5).lerp(Color(0.44, 0.5, 0.64), shade)
	return mat


func _raise_gradient_peaks() -> void:
	var peaks: Node3D = Node3D.new()
	peaks.name = "GradientPeaks"
	add_child(peaks)
	# Two ranks: near foothill cones and the tall serrated back rank.
	for i in 11:
		var x: float = -620.0 + 124.0 * float(i) + _rng.randf_range(-30.0, 30.0)
		var back: bool = i % 2 == 0
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = _rng.randf_range(120.0, 210.0) * (1.25 if back else 0.8)
		cone.height = _rng.randf_range(190.0, 300.0) * (1.35 if back else 0.75)
		cone.radial_segments = 5
		cone.rings = 1
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = _peak_material(0.85 if back else 0.35)
		mi.position = Vector3(x, cone.height * 0.32, -760.0 if back else -640.0)
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

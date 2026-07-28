extends Node3D
## Isolated look-dev harness for the climbable Gradient Peaks — a verification
## tool, not shipped content. It stands up the real MeadowTerrain + BorderVistas
## (which builds the climbable massif and the distant backdrop) under a copy of
## the main scene's environment and sun, then flies a camera to a set of
## interior and from-meadow vantage points and saves PNGs. It touches no shared
## gameplay file, so it can run while another session edits main.tscn/main.gd.
##
## Run:  godot --path <game> res://scenes/dev/peaks_lookdev.tscn -- --screenshot=<dir>

var _terrain: MeadowTerrain
var _peaks: GradientPeaks
var _camera: Camera3D


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	_build_environment()
	_build_sun()

	var world: Node3D = Node3D.new()
	world.name = "World"
	add_child(world)
	_terrain = MeadowTerrain.new()
	_terrain.name = "Terrain"
	world.add_child(_terrain)
	var vistas: BorderVistas = BorderVistas.new()
	vistas.name = "Vistas"
	world.add_child(vistas)
	_peaks = vistas.get_node_or_null("ClimbablePeaks") as GradientPeaks

	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 4000.0
	_camera.current = true
	add_child(_camera)

	_capture()


func _capture() -> void:
	var dir: String = _screenshot_dir()
	if dir == "":
		push_error("peaks_lookdev: no --screenshot=<dir> given.")
		get_tree().quit()
		return

	# Let terrain, shadows, TAA and SDFGI settle before the first frame.
	for i in 130:
		await get_tree().process_frame

	for shot in _shots():
		_camera.global_position = shot["pos"]
		_camera.look_at(shot["look"], Vector3.UP)
		if shot.has("fov"):
			_camera.fov = shot["fov"]
		else:
			_camera.fov = 62.0
		for i in 30:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = dir.path_join(String(shot["name"]) + ".png")
		var err: int = img.save_png(path)
		print("Shot %s -> %s" % ["OK" if err == OK else "FAIL", path])

	get_tree().quit()


## Vantage points are resolved off the real surface: camera eye heights sample
## get_height so they sit a person's height above the ground they describe.
func _shots() -> Array[Dictionary]:
	var vale: Vector3 = _anchor("The Vale", Vector3(38.0, 208.0, -602.0))
	var ledge: Vector3 = _anchor("Overshoot Ledge", Vector3(150.0, 185.0, -432.0))
	var shoulder: Vector3 = _anchor("West Summit Shoulder", Vector3(-153.0, 348.0, -564.0))
	var mouth: Vector3 = _anchor("Valley Mouth", Vector3(56.0, 40.0, -300.0))

	return [
		# The headline read: the whole range seen from the meadow floor.
		{
			"name": "peaks_01_from_meadow",
			"pos": Vector3(-20.0, _ground(-20.0, -70.0) + 12.0, -70.0),
			"look": Vector3(10.0, 210.0, -560.0),
			"fov": 68.0,
		},
		# Standing at the valley mouth, looking up the U-valley into the Vale.
		{
			"name": "peaks_02_valley_mouth",
			"pos": Vector3(66.0, _peak(66.0, -288.0) + 3.0, -288.0),
			"look": vale + Vector3(-10.0, 40.0, 0.0),
			"fov": 66.0,
		},
		# Inside the cirque, turning up to the North Wall and ringing summits.
		{
			"name": "peaks_03_the_vale",
			"pos": Vector3(58.0, _peak(58.0, -566.0) + 3.0, -566.0),
			"look": Vector3(20.0, 330.0, -655.0),
			"fov": 70.0,
		},
		# Overshoot Ledge, looking back out and down over the meadow far below.
		{
			"name": "peaks_04_overshoot_ledge",
			"pos": Vector3(ledge.x - 4.0, ledge.y + 3.0, ledge.z + 6.0),
			"look": Vector3(150.0, 20.0, -110.0),
			"fov": 72.0,
		},
		# The West Summit shoulder: the reachable top, looking at the snow crown.
		{
			"name": "peaks_05_summit_shoulder",
			"pos": Vector3(shoulder.x + 6.0, shoulder.y + 3.0, shoulder.z + 8.0),
			"look": Vector3(-185.0, 520.0, -560.0),
			"fov": 64.0,
		},
		# Low three-quarter on the forested lower flank — boulders, conifers, dirt.
		{
			"name": "peaks_06_lower_flank",
			"pos": Vector3(-40.0, _peak(-40.0, -300.0) + 2.4, -300.0),
			"look": Vector3(20.0, _peak(20.0, -430.0) + 20.0, -430.0),
			"fov": 60.0,
		},
		# A high oblique from the west, the range raking across the frame with the
		# backdrop giants behind — judges the ridgelines and snowline as a set.
		{
			"name": "peaks_07_west_oblique",
			"pos": Vector3(-360.0, 360.0, -300.0),
			"look": Vector3(60.0, 200.0, -600.0),
			"fov": 58.0,
		},
		# Down the switchback ramp / saddle toward the Vale — reads the trail.
		{
			"name": "peaks_08_saddle_down",
			"pos": Vector3(-120.0, _peak(-120.0, -560.0) + 3.0, -560.0),
			"look": vale + Vector3(10.0, -6.0, 0.0),
			"fov": 68.0,
		},
	]


func _anchor(label: String, fallback: Vector3) -> Vector3:
	if _peaks != null and _peaks.named_locations.has(label):
		return _peaks.named_locations[label]
	return fallback


func _peak(x: float, z: float) -> float:
	if _peaks != null:
		return _peaks.get_height(x, z)
	return 24.0


func _ground(x: float, z: float) -> float:
	if _terrain != null:
		return _terrain.get_height(x, z)
	return 0.0


func _screenshot_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			return arg.get_slice("=", 1)
	return ""


func _build_sun() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	# Mid-morning key, matched to main.tscn's sun.
	sun.transform = Transform3D(
		Basis(
			Vector3(0.866025, 0.0, -0.5),
			Vector3(-0.35, 0.713817, -0.606507),
			Vector3(0.356624, 0.700335, 0.618178)
		),
		Vector3(0.0, 60.0, 0.0)
	)
	sun.light_energy = 1.55
	sun.light_color = Color(1.0, 0.95, 0.8)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 480.0
	add_child(sun)


func _build_environment() -> void:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.48, 0.88)
	sky_material.sky_horizon_color = Color(0.74, 0.85, 0.95)
	sky_material.ground_bottom_color = Color(0.25, 0.32, 0.22)
	sky_material.ground_horizon_color = Color(0.66, 0.76, 0.62)
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.08
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 5
	env.sdfgi_max_distance = 400.0
	env.glow_enabled = true
	env.glow_intensity = 0.48
	env.glow_bloom = 0.10
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.9)
	env.fog_density = 0.00028
	env.fog_sky_affect = 0.04
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.00065
	env.volumetric_fog_albedo = Color(0.92, 0.95, 1.0)
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_length = 160.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 0.98

	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

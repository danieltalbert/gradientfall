extends Node3D
## Dev-only screenshot rig for the climbable Gradient Peaks (GDD §10: visual
## work needs eyes). Instances the real main scene, then flies its own camera
## through authored vantage points — meadow vista, valley mouth, the climb, the
## Vale, the Saddle, the summit shoulder — and saves PNGs.
##
## The camera carries its own Environment so these captures stay judgeable even
## while other in-flight work (sky/cloud passes) is mid-surgery in the shared
## scene. Run:
##   godot --path game res://scenes/dev/peaks_shots.tscn -- --peaksdir=C:/abs/dir
## Never part of the shipped game; nothing else references this scene.

var _main: Node3D
var _camera: Camera3D


func _ready() -> void:
	var dir: String = _shots_dir()
	if dir == "":
		push_error("PeaksShots: pass -- --peaksdir=C:/abs/dir")
		get_tree().quit(1)
		return
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_camera = Camera3D.new()
	_camera.name = "PeaksCamera"
	_camera.fov = 62.0
	_camera.far = 4000.0
	_camera.environment = _make_environment()
	add_child(_camera)
	_capture_all.call_deferred(dir)


func _shots_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peaksdir="):
			return arg.get_slice("=", 1)
	return ""


func _make_environment() -> Environment:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.48, 0.88)
	sky_material.sky_horizon_color = Color(0.74, 0.85, 0.95)
	sky_material.ground_bottom_color = Color(0.25, 0.32, 0.22)
	sky_material.ground_horizon_color = Color(0.66, 0.76, 0.62)
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.08
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.88
	environment.glow_enabled = true
	environment.glow_intensity = 0.48
	environment.glow_bloom = 0.1
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.82, 0.9)
	environment.fog_density = 0.00028
	environment.fog_sky_affect = 0.04
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.1
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.6
	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_cascades = 5
	environment.sdfgi_max_distance = 400.0
	environment.sdfgi_read_sky_light = true
	return environment


func _capture_all(dir: String) -> void:
	var terrain: MeadowTerrain = _main.get_node("World/Terrain") as MeadowTerrain
	var peaks: GradientPeaks = _main.get_node_or_null("World/Vistas/ClimbablePeaks") as GradientPeaks
	if peaks == null:
		push_error("PeaksShots: ClimbablePeaks not found under World/Vistas.")
		get_tree().quit(1)
		return
	var hud: Node = _main.get_node_or_null("CombatHud")
	if hud != null and "visible" in hud:
		hud.set("visible", false)
	var cycle: SkyCycle = _main.get_node_or_null("World/SkyCycle") as SkyCycle
	if cycle != null:
		cycle.paused = true
		cycle.set_hour(10.2)
	_camera.current = true

	# {name, pos:Vector2, height above surface, aim:Vector2, aim height offset}.
	# Positions sample the real surface so shots stay honest as the range
	# iterates. Aims frame the specific landform each capture is judging.
	var shots: Array[Dictionary] = [
		{"name": "01_range_from_town", "pos": Vector2(0.0, 40.0), "up": 8.0,
			"aim": Vector2(0.0, -560.0), "aim_up": 300.0},
		{"name": "02_range_from_meadow_edge", "pos": Vector2(-30.0, -130.0), "up": 3.0,
			"aim": Vector2(20.0, -560.0), "aim_up": 320.0},
		{"name": "03_buttress_foot", "pos": Vector2(190.0, -252.0), "up": 4.0,
			"aim": Vector2(224.0, -390.0), "aim_up": 160.0},
		{"name": "04_valley_mouth", "pos": Vector2(56.0, -276.0), "up": 3.5,
			"aim": Vector2(48.0, -442.0), "aim_up": 60.0},
		{"name": "05_valley_climb", "pos": Vector2(50.0, -420.0), "up": 4.0,
			"aim": Vector2(38.0, -602.0), "aim_up": 90.0},
		{"name": "06_the_vale", "pos": Vector2(60.0, -570.0), "up": 4.0,
			"aim": Vector2(-96.0, -600.0), "aim_up": 120.0},
		{"name": "07_vale_north_wall", "pos": Vector2(38.0, -560.0), "up": 4.0,
			"aim": Vector2(35.0, -658.0), "aim_up": 300.0},
		{"name": "08_saddle_pass", "pos": Vector2(-70.0, -560.0), "up": 4.0,
			"aim": Vector2(-153.0, -564.0), "aim_up": 120.0},
		{"name": "09_summit_shoulder_south", "pos": Vector2(-146.0, -524.0), "up": 7.0,
			"aim": Vector2(-40.0, -60.0), "aim_up": 30.0},
		{"name": "10_overshoot_ledge", "pos": Vector2(150.0, -428.0), "up": 4.0,
			"aim": Vector2(60.0, -80.0), "aim_up": -30.0},
	]

	for i in 130:  # SDFGI / TAA convergence
		await get_tree().process_frame
	for shot in shots:
		var flat: Vector2 = shot["pos"]
		var ground: float = _surface_height(flat, terrain, peaks)
		_camera.position = Vector3(flat.x, ground + float(shot["up"]), flat.y)
		var aim_flat: Vector2 = shot["aim"]
		var aim_ground: float = _surface_height(aim_flat, terrain, peaks)
		_camera.look_at(Vector3(aim_flat.x, aim_ground + float(shot["aim_up"]), aim_flat.y))
		for i in 40:
			await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = dir.path_join(String(shot["name"]) + ".png")
		print("PeaksShots %s -> %s" % ["OK" if image.save_png(path) == OK else "FAILED", path])
	get_tree().quit()


func _surface_height(flat: Vector2, terrain: MeadowTerrain, peaks: GradientPeaks) -> float:
	if peaks.in_bounds(flat.x, flat.y):
		return peaks.get_height(flat.x, flat.y)
	return terrain.get_height(flat.x, flat.y)

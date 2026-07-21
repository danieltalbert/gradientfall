extends Node3D
## Dev-only character studio for Kern (GDD §10: visual work needs eyes). Stands
## the hero on a small turntable plinth under neutral 3-point lighting and
## saves a shot list — full body, three-quarter, face close-up, hands, gear
## back (the patched cloak), plus a short turntable sweep. Never shipped;
## nothing else references this scene.
##
## Run:
##   godot --path game res://scenes/dev/kern_studio.tscn -- --kerndir=C:/abs/dir
## Optional: --anim=walk|guard|attack to capture a mid-pose instead of idle.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

var _kern: Node3D
var _visual: Node3D
var _camera: Camera3D
var _fake_body: CharacterBody3D


func _ready() -> void:
	var dir: String = _arg("--kerndir=")
	if dir == "":
		push_error("KernStudio: pass -- --kerndir=C:/abs/dir")
		get_tree().quit(1)
		return
	_build_stage()
	_spawn_kern()
	_capture_all.call_deferred(dir)


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.get_slice("=", 1)
	return ""


func _build_stage() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.70)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.12
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssao_radius = 0.4
	env.sdfgi_enabled = false

	_camera = Camera3D.new()
	_camera.name = "StudioCamera"
	_camera.fov = 40.0
	_camera.environment = env
	add_child(_camera)

	# Key, fill, and cool rim so the character shaders' rim/fill read honestly.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "Key"
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.97, 0.9)
	key.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(38.0), 0.0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(-58.0), 0.0)
	add_child(fill)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_energy = 2.2
	rim.light_color = Color(0.75, 0.85, 1.0)
	rim.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(170.0), 0.0)
	add_child(rim)

	# Plinth so contact + AO have something to sit on.
	var plinth: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.7
	cyl.height = 0.06
	plinth.mesh = cyl
	plinth.position = Vector3(0.0, -0.03, 0.0)
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.albedo_color = Color(0.22, 0.23, 0.26)
	pm.roughness = 0.9
	plinth.material_override = pm
	add_child(plinth)


func _spawn_kern() -> void:
	# Instance the real player, then neutralise its controller scripts so it
	# just stands there as a pure art subject on our stage.
	_kern = PlayerScene.instantiate() as Node3D
	add_child(_kern)
	for child_name in ["CameraRig"]:
		var n: Node = _kern.get_node_or_null(child_name)
		if n != null:
			n.set_process(false)
			n.set_physics_process(false)
	# Disable the player's own scripts' processing so nothing fights our poses.
	_kern.set_physics_process(false)
	_kern.set_process(false)
	_visual = _kern.get_node_or_null("Visual")

	# Drive a static animation pose if requested.
	var anim: String = _arg("--anim=")
	if _visual != null:
		match anim:
			"guard":
				_visual.call_deferred("pose_guard", true)
			"attack":
				_visual.call_deferred("pose_attack", 0.5)


func _capture_all(dir: String) -> void:
	# Let the rig build, materials compile, GI/AO settle.
	for i in 90:
		await get_tree().process_frame

	var eye_h: float = 1.55
	var mid_h: float = 0.95
	# {name, cam pos, look-at target, fov}
	var shots: Array = [
		{"name": "01_full_front", "pos": Vector3(0.0, mid_h, 4.4),
			"look": Vector3(0.0, mid_h, 0.0), "fov": 30.0},
		{"name": "02_full_threequarter", "pos": Vector3(2.7, mid_h + 0.15, 3.4),
			"look": Vector3(0.0, mid_h, 0.0), "fov": 32.0},
		{"name": "03_full_side", "pos": Vector3(4.3, mid_h, 0.2),
			"look": Vector3(0.0, mid_h, 0.0), "fov": 30.0},
		{"name": "04_full_back", "pos": Vector3(0.0, mid_h + 0.1, -4.4),
			"look": Vector3(0.0, mid_h, 0.0), "fov": 32.0},
		{"name": "05_face", "pos": Vector3(0.22, eye_h, 0.85),
			"look": Vector3(0.0, eye_h - 0.02, 0.0), "fov": 22.0},
		{"name": "06_face_profile", "pos": Vector3(0.95, eye_h - 0.02, 0.35),
			"look": Vector3(0.0, eye_h - 0.04, 0.0), "fov": 22.0},
		{"name": "07_upperbody", "pos": Vector3(1.1, 1.35, 2.0),
			"look": Vector3(0.0, 1.25, 0.0), "fov": 30.0},
		{"name": "08_hands", "pos": Vector3(0.55, 0.95, 1.05),
			"look": Vector3(0.18, 0.92, 0.05), "fov": 26.0},
		{"name": "09_cloak_back", "pos": Vector3(1.4, 1.0, -3.0),
			"look": Vector3(0.0, 0.9, 0.0), "fov": 34.0},
		{"name": "10_sword", "pos": Vector3(1.4, 1.15, 1.4),
			"look": Vector3(0.35, 1.1, 0.15), "fov": 30.0},
	]
	for shot in shots:
		_camera.fov = float(shot["fov"])
		_camera.position = shot["pos"]
		_camera.look_at(shot["look"])
		for i in 6:
			await get_tree().process_frame
		_save(dir, shot["name"])

	# Turntable: 8 frames orbiting the full body.
	for k in 8:
		var a: float = TAU * float(k) / 8.0
		_camera.fov = 30.0
		_camera.position = Vector3(sin(a) * 4.4, mid_h + 0.1, cos(a) * 4.4)
		_camera.look_at(Vector3(0.0, mid_h, 0.0))
		for i in 4:
			await get_tree().process_frame
		_save(dir, "turn_%02d" % k)

	get_tree().quit()


func _save(dir: String, shot_name: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = dir.path_join(shot_name + ".png")
	var ok: int = image.save_png(path)
	print("KernStudio %s -> %s" % ["OK" if ok == OK else "FAIL", path])

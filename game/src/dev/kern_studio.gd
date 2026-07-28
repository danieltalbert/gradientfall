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
	env.ambient_light_color = Color(0.45, 0.50, 0.60)
	env.ambient_light_energy = 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.13
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.25
	env.ssao_enabled = true
	env.ssao_intensity = 1.5
	env.ssao_radius = 0.4
	env.sdfgi_enabled = false

	_camera = Camera3D.new()
	_camera.name = "StudioCamera"
	_camera.fov = 40.0
	_camera.environment = env
	add_child(_camera)
	_camera.current = true  # claim the viewport from the player's own camera

	# Key, fill, and cool rim so the character shaders' rim/fill read honestly.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "Key"
	key.light_energy = 1.45
	key.light_color = Color(1.0, 0.96, 0.88)
	key.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(38.0), 0.0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.32
	fill.light_color = Color(0.68, 0.78, 1.0)
	fill.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(-58.0), 0.0)
	add_child(fill)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_energy = 1.0
	rim.light_color = Color(0.72, 0.82, 1.0)
	rim.rotation = Vector3(deg_to_rad(-6.0), deg_to_rad(168.0), 0.0)
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
	# Silence the player's camera rig so our studio camera owns the view.
	var rig: Node = _kern.get_node_or_null("CameraRig")
	if rig != null:
		rig.set_process(false)
		rig.set_physics_process(false)
		var pcam: Camera3D = rig.get_node_or_null("SpringArm3D/Camera3D")
		if pcam != null:
			pcam.current = false
			pcam.queue_free()
	# Disable the player's own scripts' processing so nothing fights our poses.
	_kern.set_physics_process(false)
	_kern.set_process(false)
	_visual = _kern.get_node_or_null("Visual")
	# Model forward is -Z; turn it to face the +Z camera bank so "front" shots
	# actually show Kern's face.
	if _visual != null:
		_visual.rotation.y = PI
		# Force the arcane awaken level for the shoot (rest vs charged).
		var aw: String = _arg("--awaken=")
		if aw != "":
			_visual.set("awaken_override", clampf(aw.to_float(), 0.0, 1.0))

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

	var eye_h: float = 1.64   # eye line of the sculpted head
	var mid_h: float = 0.95   # centre of the standing figure
	# {name, cam pos, look-at target, fov}
	var shots: Array = [
		{"name": "01_full_front", "pos": Vector3(0.0, 1.15, 3.6),
			"look": Vector3(0.0, 0.98, 0.0), "fov": 30.0},
		{"name": "02_full_threequarter", "pos": Vector3(2.1, 1.25, 2.9),
			"look": Vector3(0.0, 0.98, 0.0), "fov": 32.0},
		{"name": "03_full_side", "pos": Vector3(3.6, 1.1, 0.15),
			"look": Vector3(0.0, 0.98, 0.0), "fov": 30.0},
		{"name": "04_full_back", "pos": Vector3(0.0, 1.2, -3.7),
			"look": Vector3(0.0, 0.98, 0.0), "fov": 32.0},
		{"name": "05_face", "pos": Vector3(0.18, eye_h + 0.02, 0.72),
			"look": Vector3(0.0, eye_h, 0.0), "fov": 22.0},
		{"name": "05b_eye", "pos": Vector3(0.0, eye_h, 0.34),
			"look": Vector3(0.0, eye_h, 0.0), "fov": 12.0},
		{"name": "06_face_profile", "pos": Vector3(0.78, eye_h, 0.28),
			"look": Vector3(0.0, eye_h - 0.01, 0.0), "fov": 22.0},
		{"name": "07_upperbody", "pos": Vector3(0.9, 1.5, 1.8),
			"look": Vector3(0.0, 1.32, 0.0), "fov": 30.0},
		{"name": "08_hands", "pos": Vector3(0.42, 1.02, 0.9),
			"look": Vector3(0.14, 0.9, 0.1), "fov": 26.0},
		{"name": "09_cloak_back", "pos": Vector3(1.2, 1.25, -2.7),
			"look": Vector3(0.0, 0.95, 0.0), "fov": 34.0},
		{"name": "10_sword", "pos": Vector3(1.2, 1.2, 1.2),
			"look": Vector3(0.28, 1.05, 0.15), "fov": 30.0},
		{"name": "11_boots", "pos": Vector3(0.35, 0.32, 0.85),
			"look": Vector3(0.0, 0.10, 0.0), "fov": 26.0},
		{"name": "12_hem_trim", "pos": Vector3(0.15, 0.95, 0.9),
			"look": Vector3(0.0, 0.86, 0.0), "fov": 26.0},
	]
	for shot in shots:
		# Hide the held sword for face/portrait shots so the blade doesn't
		# bisect the head.
		var name_s: String = shot["name"]
		var portrait: bool = name_s.begins_with("05") or name_s.begins_with("06")
		var sword: Node = _visual.get_node_or_null("KernSkeleton/HandRAttach/TravelerSword") \
			if _visual != null else null
		if sword != null and "visible" in sword:
			sword.set("visible", not portrait)
		_camera.fov = float(shot["fov"])
		_camera.position = shot["pos"]
		_camera.look_at(shot["look"])
		for i in 6:
			await get_tree().process_frame
		_save(dir, shot["name"])

	# Turntable: 8 frames orbiting the full body at eye level.
	for k in 8:
		var a: float = TAU * float(k) / 8.0
		_camera.fov = 30.0
		_camera.position = Vector3(sin(a) * 3.7, 1.15, cos(a) * 3.7)
		_camera.look_at(Vector3(0.0, 0.98, 0.0))
		for i in 4:
			await get_tree().process_frame
		_save(dir, "turn_%02d" % k)

	get_tree().quit()


func _save(dir: String, shot_name: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = dir.path_join(shot_name + ".png")
	var ok: int = image.save_png(path)
	print("KernStudio %s -> %s" % ["OK" if ok == OK else "FAIL", path])

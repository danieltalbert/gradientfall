extends Node3D
## Vertical-slice world: sky, sun, Datasedge Meadows (terrain + flora +
## border vistas, all procedural), and Kern with the milestone-2 controller.
##
## Dev screenshot mode (GDD §10: headless boots can't see — live sessions
## must LOOK): run with `-- --screenshot=C:/abs/dir` and the game waits for
## the world to settle, captures a few angles from Kern's camera, saves PNGs
## to that directory, and quits. Used by live sessions to attach visual
## evidence to the devlog; harmless in normal play.

@onready var _player: CharacterBody3D = $Player
@onready var _terrain: MeadowTerrain = $World/Terrain
@onready var _bit: Bit = $Bit
@onready var _landmarks: MeadowLandmarks = $World/Landmarks

var _spawner: MonsterSpawner
var _hud: CombatHud


func _ready() -> void:
	print("Neural Quest: Gradientfall — scaffold boot OK.")
	print("Controls: WASD move / Space jump / Shift sprint / mouse orbits, Esc frees it / gamepad supported.")
	print("GameState: save_version=%d, region=%s, player=%s" % [
		GameState.SAVE_VERSION, GameState.current_region, GameState.player_name,
	])
	var errors: PackedStringArray = ContentDB.get_load_errors()
	if errors.is_empty():
		print("ContentDB check: %d NPCs, %d quests, %d quizzes approved." % [
			ContentDB.get_all("npcs").size(),
			ContentDB.get_all("quests").size(),
			ContentDB.get_all("quizzes").size(),
		])
	else:
		push_error("ContentDB reported %d load error(s) — see above." % errors.size())

	_spawn_player()
	_landmarks.build(_terrain)
	_bit.setup(_player, _terrain)

	# Screenshot mode is the visual-verification tool — keep it clean of HUD
	# and roaming enemies. Normal play gets the combat HUD + monster spawner.
	var shot_dir: String = _screenshot_dir()
	if shot_dir != "":
		_capture_screens(shot_dir)
	else:
		_setup_combat()


func _setup_combat() -> void:
	_hud = CombatHud.new()
	_hud.name = "CombatHud"
	add_child(_hud)
	_player.broadcast_hearts()  # HUD was created after the player spawned
	var prompt: KnowledgePrompt = KnowledgePrompt.new()
	prompt.name = "KnowledgePrompt"
	add_child(prompt)
	_spawner = MonsterSpawner.new()
	_spawner.name = "MonsterSpawner"
	$World.add_child(_spawner)
	var sp: Vector2 = MeadowTerrain.SPAWN_POINT
	var spawn_pos: Vector3 = Vector3(sp.x, _terrain.get_height(sp.x, sp.y), sp.y)
	_spawner.setup(_terrain, spawn_pos)
	print("Combat v1 online: sword combo/dodge/block, hearts, monster spawner + proving ground.")
	print("Knowledge charge v1 online: Q mid-fight calls the focus channel — answer with Bit to forge the strike.")


func _spawn_player() -> void:
	var sp: Vector2 = MeadowTerrain.SPAWN_POINT
	var ground: float = _terrain.get_height(sp.x, sp.y)
	_player.global_position = Vector3(sp.x, ground + 0.8, sp.y)
	# Face Kern southeast toward Bootstrap's town site and the pond.
	_player.rotation.y = deg_to_rad(-135.0)


func _screenshot_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			return arg.get_slice("=", 1)
	return ""


func _capture_screens(dir: String) -> void:
	# Angles chosen to judge the GDD §10 bar: the town-and-pond view, the
	# Gradient Peaks vista, the sea horizon, and grass up close.
	var rig: Node3D = _player.get_node("CameraRig")
	# Keep the frame clean: Kern's body, Bit, and the floating landmark/bark
	# labels otherwise sit right on the lens and block the world we're judging.
	var kern_visual: Node3D = _player.get_node("Visual") as Node3D
	if kern_visual != null:
		kern_visual.visible = false
	_bit.visible = false
	_landmarks.visible = false
	var cycle: SkyCycle = get_node("World/SkyCycle") as SkyCycle
	if cycle != null:
		cycle.paused = true
		cycle.set_hour(8.5)
	var arm: SpringArm3D = rig.get_node("SpringArm3D") as SpringArm3D
	var shots: Array[Dictionary] = [
		{"name": "meadow_southeast_town", "yaw": deg_to_rad(-135.0), "pitch": -0.25},
		{"name": "meadow_north_peaks", "yaw": deg_to_rad(35.0), "pitch": 0.05},
		{"name": "meadow_west_sea", "yaw": deg_to_rad(115.0), "pitch": -0.18},
		{"name": "meadow_east_forest", "yaw": deg_to_rad(-65.0), "pitch": -0.22},
		{"name": "detail_pond_water", "yaw": deg_to_rad(-90.0), "pitch": -0.13,
			"pos": Vector2(66.0, 10.0)},
		{"name": "detail_tree_canopy", "yaw": deg_to_rad(-90.0), "pitch": 0.08,
			"pos": Vector2(15.0, -60.0)},
		{"name": "detail_grass_horizon", "yaw": deg_to_rad(20.0), "pitch": 0.02,
			"pos": Vector2(-42.0, -82.0)},
		{"name": "detail_grass_closeup", "yaw": deg_to_rad(20.0), "pitch": -0.34,
			"pos": Vector2(-42.0, -82.0), "eye": 0.55},
		# Kern standing in the sward — verifies the trample parting around him.
		# Spring arm collapsed so the camera sits exactly at the posed point
		# and looks straight down at his feet, where the parting shows.
		{"name": "detail_trample", "yaw": 0.0, "pitch": -0.42,
			"pos": Vector2(-40.0, -76.6), "eye": 1.7, "show_kern": true,
			"spring": 0.0, "freeze_rig": true, "player_at": Vector2(-40.0, -80.0)},
	]
	for i in 110:  # let terrain, shadows, TAA, and SDFGI converge
		await get_tree().process_frame
	# Honest steady-state frame rate: time a 60-frame window post-convergence
	# (Engine.get_frames_per_second() right after boot reports compile spikes).
	var t0: int = Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
	var avg_fps: float = 60.0 * 1e6 / float(Time.get_ticks_usec() - t0)
	print("Screenshot mode steady-state FPS: %.1f" % avg_fps)
	for shot in shots:
		if kern_visual != null:
			kern_visual.visible = shot.get("show_kern", false)
		# The rig normally re-follows the player every frame (and forces a
		# 1.65 m eye) — freeze it so a posed camera that looks AT Kern (e.g.
		# the trample shot) actually stays where it's put.
		if shot.get("freeze_rig", false):
			rig.set_process(false)
		if shot.has("pos"):
			var sample: Vector2 = shot["pos"]
			var eye: float = shot.get("eye", 2.45)
			# Kern normally stands at the camera spot; a shot can instead pose
			# him elsewhere in frame (e.g. to verify the grass trample).
			var stand: Vector2 = shot.get("player_at", sample)
			_player.global_position = Vector3(
				stand.x, _terrain.get_height(stand.x, stand.y) + 0.8, stand.y
			)
			rig.global_position = Vector3(
				sample.x, _terrain.get_height(sample.x, sample.y) + eye, sample.y
			)
		rig.rotation.y = shot["yaw"]
		arm.rotation.x = shot["pitch"]
		arm.spring_length = shot.get("spring", 5.0)
		for i in 35:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = dir.path_join(String(shot["name"]) + ".png")
		var err: int = img.save_png(path)
		print("Screenshot %s -> %s" % ["OK" if err == OK else "FAILED", path])

	# Day/night showcase: the same town view across the color script.
	if kern_visual != null:
		kern_visual.visible = false  # the trample shot re-showed him
	arm.spring_length = 5.0          # the trample shot collapsed it
	if cycle != null:
		var sp: Vector2 = MeadowTerrain.SPAWN_POINT
		_player.global_position = Vector3(sp.x, _terrain.get_height(sp.x, sp.y) + 0.8, sp.y)
		rig.global_position = _player.global_position + Vector3(0.0, 1.65, 0.0)
		rig.rotation.y = deg_to_rad(-135.0)
		arm.rotation.x = -0.25
		for tod in [{"n": "tod_dawn", "h": 6.2}, {"n": "tod_noon", "h": 13.0},
				{"n": "tod_dusk", "h": 17.8}, {"n": "tod_night", "h": 22.0}]:
			cycle.set_hour(tod["h"])
			for i in 30:
				await get_tree().process_frame
			var img2: Image = get_viewport().get_texture().get_image()
			var path2: String = dir.path_join(String(tod["n"]) + ".png")
			var err2: int = img2.save_png(path2)
			print("Screenshot %s -> %s" % ["OK" if err2 == OK else "FAILED", path2])
	get_tree().quit()

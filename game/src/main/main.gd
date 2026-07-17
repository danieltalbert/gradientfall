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
	_maybe_run_screenshot_mode()


func _spawn_player() -> void:
	var sp: Vector2 = MeadowTerrain.SPAWN_POINT
	var ground: float = _terrain.get_height(sp.x, sp.y)
	_player.global_position = Vector3(sp.x, ground + 0.8, sp.y)
	# Face Kern southeast toward Bootstrap's town site and the pond.
	_player.rotation.y = deg_to_rad(-135.0)


func _maybe_run_screenshot_mode() -> void:
	var dir: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			dir = arg.get_slice("=", 1)
	if dir.is_empty():
		return
	_capture_screens(dir)


func _capture_screens(dir: String) -> void:
	# Angles chosen to judge the GDD §10 bar: the town-and-pond view, the
	# Gradient Peaks vista, the sea horizon, and grass up close.
	var rig: Node3D = _player.get_node("CameraRig")
	var shots: Array = [
		{"name": "meadow_southeast_town", "yaw": deg_to_rad(-135.0)},
		{"name": "meadow_north_peaks", "yaw": deg_to_rad(35.0)},
		{"name": "meadow_west_sea", "yaw": deg_to_rad(115.0)},
		{"name": "meadow_east_forest", "yaw": deg_to_rad(-65.0)},
	]
	for i in 30:  # let terrain, shadows, and glow settle
		await get_tree().process_frame
	for shot in shots:
		rig.rotation.y = shot["yaw"]
		for i in 8:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = dir.path_join(String(shot["name"]) + ".png")
		var err: int = img.save_png(path)
		print("Screenshot %s -> %s" % ["OK" if err == OK else "FAILED", path])
	get_tree().quit()

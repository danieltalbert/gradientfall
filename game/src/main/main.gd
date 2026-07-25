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
var _pack: InventoryScreen
var _forage: MeadowForage


func _ready() -> void:
	print("Neural Quest: Gradientfall — scaffold boot OK.")
	print("Controls: WASD move / Space jump / Shift sprint / mouse orbits, Esc frees it / gamepad supported.")
	print("GameState: save_version=%d, region=%s, player=%s" % [
		GameState.SAVE_VERSION, GameState.current_region, GameState.player_name,
	])
	var errors: PackedStringArray = ContentDB.get_load_errors()
	if errors.is_empty():
		print("ContentDB check: %d NPCs, %d quests, %d items, %d quizzes approved." % [
			ContentDB.get_all("npcs").size(),
			ContentDB.get_all("quests").size(),
			ContentDB.get_all("items").size(),
			ContentDB.get_all("quizzes").size(),
		])
	else:
		push_error("ContentDB reported %d load error(s) — see above." % errors.size())

	_spawn_player()
	_landmarks.build(_terrain)
	_bit.setup(_player, _terrain)

	# Screenshot mode is the visual-verification tool — keep it clean of HUD,
	# roaming enemies, and glowing pickups. Normal play gets all of it.
	var shot_dir: String = _screenshot_dir()
	if shot_dir != "":
		_capture_screens(shot_dir)
	else:
		_setup_combat()
		_setup_pack()


func _setup_combat() -> void:
	_hud = CombatHud.new()
	_hud.name = "CombatHud"
	add_child(_hud)
	_player.broadcast_hearts()  # HUD was created after the player spawned
	_spawner = MonsterSpawner.new()
	_spawner.name = "MonsterSpawner"
	$World.add_child(_spawner)
	var sp: Vector2 = MeadowTerrain.SPAWN_POINT
	var spawn_pos: Vector3 = Vector3(sp.x, _terrain.get_height(sp.x, sp.y), sp.y)
	_spawner.setup(_terrain, spawn_pos)
	print("Combat v1 online: sword combo/dodge/block, hearts, monster spawner + proving ground.")


## Milestone 10: the pack screen plus the forage that fills it. Forage is built
## after the landmarks (above) because curios and tools cluster around them.
func _setup_pack() -> void:
	_pack = InventoryScreen.new()
	_pack.name = "InventoryScreen"
	add_child(_pack)
	_forage = MeadowForage.new()
	_forage.name = "MeadowForage"
	$World.add_child(_forage)
	_forage.setup(_terrain)
	print("Pack online: press I for the inventory; Tokens ride the HUD purse.")


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
	]
	for i in 110:  # let terrain, shadows, TAA, and SDFGI converge
		await get_tree().process_frame
	for shot in shots:
		if shot.has("pos"):
			var sample: Vector2 = shot["pos"]
			_player.global_position = Vector3(
				sample.x, _terrain.get_height(sample.x, sample.y) + 0.8, sample.y
			)
			rig.global_position = _player.global_position + Vector3(0.0, 1.65, 0.0)
		rig.rotation.y = shot["yaw"]
		arm.rotation.x = shot["pitch"]
		for i in 35:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = dir.path_join(String(shot["name"]) + ".png")
		var err: int = img.save_png(path)
		print("Screenshot %s -> %s" % ["OK" if err == OK else "FAILED", path])

	# Day/night showcase: the same town view across the color script.
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

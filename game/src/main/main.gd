extends Node3D
## Vertical-slice world: sky, sun, Datasedge Meadows (terrain + flora +
## border vistas, all procedural), and Kern with the milestone-2 controller.
##
## Dev screenshot mode (GDD §10: headless boots can't see — live sessions
## must LOOK): run with `-- --screenshot=C:/abs/dir` and the game waits for
## the world to settle, captures a few angles from Kern's camera, saves PNGs
## to that directory, and quits. Used by live sessions to attach visual
## evidence to the devlog; harmless in normal play.
##
## Three narrower capture modes exist for lanes the broad pass cannot judge:
## `--florashot=` (five distances on one copse), `--mapshot=` (the UI, which the
## world pass deliberately hides), and `--townshot=` (fifteen close standing
## points inside Bootstrap). All of them skip the HUD and the monster spawner.

@onready var _player: CharacterBody3D = $Player
@onready var _terrain: MeadowTerrain = $World/Terrain
@onready var _bit: Bit = $Bit
@onready var _landmarks: MeadowLandmarks = $World/Landmarks
@onready var _town: BootstrapTown = $World/Town
@onready var _sky: SkyCycle = $World/SkyCycle

var _spawner: MonsterSpawner
var _hud: CombatHud
var _dialogue: DialogueUi
var _interactor: NpcInteractor
var _pack: InventoryScreen
var _forage: MeadowForage
var _vault: PerceptronVault
var _compendium: CompendiumUi
var _map: WorldMapUi
var _minimap: Minimap
var _town_shots: TownShots


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
	# The swimmer asks the terrain where the water is, so it can only be bound
	# once the world exists.
	_player.call(&"setup_water", _terrain)
	_town.build(_terrain, _sky)
	_landmarks.build(_terrain)
	_bit.setup(_player, _terrain)
	_setup_vault()

	# Screenshot mode is the visual-verification tool — keep it clean of HUD
	# and roaming enemies. Normal play gets the combat HUD + monster spawner.
	var shot_dir: String = _screenshot_dir()
	var map_dir: String = _flag_value("--mapshot=")
	var flora_dir: String = _flag_value("--florashot=")
	var town_dir: String = _flag_value("--townshot=")
	if shot_dir != "":
		_capture_screens(shot_dir)
	elif town_dir != "":
		# Bootstrap iteration loop: the full pass gives the town three frames
		# from tens of metres out, which cannot judge a door, a sign or a face.
		# TownShots stands in the streets instead — see src/dev/town_shots.gd.
		# Held in a member: the capture is a coroutine, and a RefCounted with no
		# surviving reference is not something to gamble a 15-shot pass on.
		_town_shots = TownShots.new()
		_town_shots.capture(self, _player, _terrain, _town, _sky,
			_landmarks, _bit, town_dir)
	elif flora_dir != "":
		# Flora iteration loop: five angles on one copse, nothing else. The full
		# screenshot pass is ~29 shots and too slow to tune trees against.
		_capture_flora(flora_dir)
	elif map_dir != "":
		# UI shot mode: the world screenshot pass above deliberately leaves the
		# interface out, so the map and the minimap have no way to produce
		# visual evidence through it. This builds the normal-play stack and
		# photographs the UI instead.
		_setup_combat()
		_setup_compendium()
		_setup_map()
		_capture_map(map_dir)
	else:
		_setup_combat()
		_setup_compendium()
		_setup_map()


## The world map (M) and the top-right minimap. Normal play only — both are UI,
## and screenshot captures stay clean of UI. Both read WorldAtlas, so neither
## holds any geography of its own that could fall out of step with the world.
func _setup_map() -> void:
	_map = WorldMapUi.build(self, _player)
	_minimap = Minimap.build(self, _player)
	print("Map online: press M for the continent; the minimap rides the top right.")


## Dungeon 1 — the Perceptron Vault. Built in both modes on purpose: it is
## world geometry, so screenshot runs must see it, and the only actor it
## spawns (the Gatekeeper) waits for Kern to walk into the arena, which a
## screenshot run never does.
func _setup_vault() -> void:
	_vault = PerceptronVault.build($World, _terrain)


## Compendium v1 — Kern's field notebook, opened with J. Normal play only:
## it is UI, and screenshot captures stay clean of UI. It reads the meadow's
## iris specimens straight off the field MeadowFlora built.
func _setup_compendium() -> void:
	var flora: MeadowFlora = $World/Flora as MeadowFlora
	if flora != null and flora.iris_field != null:
		_compendium = CompendiumUi.build(self, flora.iris_field)


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
	_setup_dialogue()


## Bootstrap's villagers (milestone 8) talk back: a proximity interactor raises
## the talk prompt, and the dialogue box plays the lines out of ContentDB.
func _setup_dialogue() -> void:
	_dialogue = DialogueUi.new()
	_dialogue.name = "DialogueUi"
	add_child(_dialogue)
	_interactor = NpcInteractor.new()
	_interactor.name = "NpcInteractor"
	add_child(_interactor)
	_interactor.setup(_player)
	print("Bootstrap online: %d villagers to talk to — walk up and press E." % [
		get_tree().get_nodes_in_group(&"npc").size(),
	])
	_setup_pack()


## Milestone 10: the pack screen plus the forage that fills it. Forage is built
## after the landmarks because curios and tools cluster around them.
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
	return _flag_value("--screenshot=")


## Read a `--name=value` user argument, or "" when it was not passed.
func _flag_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.get_slice("=", 1)
	return ""


## Photograph the interface: the minimap in play, then the world map open, then
## the map again from a second standing point so the "you are here" ring and the
## nearest-place readout can both be checked against somewhere known.
func _capture_map(dir: String) -> void:
	for i in 90:
		await get_tree().process_frame
	await _shoot(dir, "ui_minimap_at_spawn")

	_map.set_open(true)
	for i in 25:
		await get_tree().process_frame
	await _shoot(dir, "ui_world_map")

	# Stand Kern on the millpond's edge: a named place, water in the minimap,
	# and a different region readout line to check.
	_map.set_open(false)
	var pond: Vector2 = MeadowTerrain.POND_CENTER + Vector2(-30.0, 0.0)
	_player.global_position = Vector3(pond.x, _terrain.get_height(pond.x, pond.y) + 0.8, pond.y)
	for i in 30:
		await get_tree().process_frame
	await _shoot(dir, "ui_minimap_at_millpond")

	_map.set_open(true)
	for i in 25:
		await get_tree().process_frame
	await _shoot(dir, "ui_world_map_millpond")

	# Drop Kern into the middle of the millpond from three metres up. This is
	# the only water in the game he can actually reach, so it is the only way to
	# photograph the swim: he should sink, bob back to the surface with his
	# shoulders out, and take NO damage, because the pond is named safe water.
	_map.set_open(false)
	var drop: Vector2 = MeadowTerrain.POND_CENTER
	_player.global_position = Vector3(drop.x, _terrain.water_level + 3.0, drop.y)
	_player.velocity = Vector3.ZERO
	for i in 150:
		await get_tree().process_frame
	print("Swim check: swimming=%s, hearts=%.2f, y=%.2f (water %.2f)" % [
		_player.call(&"is_swimming"),
		(_player.get_node("Health") as Health).current,
		_player.global_position.y, _terrain.water_level,
	])
	await _shoot(dir, "ui_swim_millpond")
	get_tree().quit()


## Photograph the trees at the five distances that decide whether they work:
## the trunk you stand next to, the whole tree at conversation range, the
## canopy from underneath, a copse across a field, and the treeline on the
## horizon. A tree that only reads at one of these is not finished.
##
## All angles look due east (+X) at the copse seeded near (30, -60).
func _capture_flora(dir: String) -> void:
	var rig: Node3D = _player.get_node("CameraRig")
	var arm: SpringArm3D = rig.get_node("SpringArm3D") as SpringArm3D
	var kern_visual: Node3D = _player.get_node("Visual") as Node3D
	if kern_visual != null:
		kern_visual.visible = false
	_bit.visible = false
	_landmarks.visible = false
	var cycle: SkyCycle = get_node("World/SkyCycle") as SkyCycle
	if cycle != null:
		cycle.paused = true
		cycle.set_hour(9.5)   # side light: bark grooves and canopy depth both read
	rig.set_process(false)
	arm.spring_length = 0.0

	var shots: Array[Dictionary] = [
		{"name": "tree_trunk", "pos": Vector2(25.0, -60.0), "eye": 1.30, "pitch": -0.06},
		{"name": "tree_whole", "pos": Vector2(19.0, -60.0), "eye": 2.20, "pitch": 0.14},
		{"name": "tree_canopy_under", "pos": Vector2(30.0, -60.0), "eye": 1.70, "pitch": 0.80},
		{"name": "copse_mid", "pos": Vector2(-8.0, -60.0), "eye": 2.40, "pitch": 0.03},
		{"name": "copse_far", "pos": Vector2(-82.0, -60.0), "eye": 3.20, "pitch": 0.04},
	]
	for i in 100:
		await get_tree().process_frame
	for shot in shots:
		var at: Vector2 = shot["pos"]
		var ground: float = _terrain.get_height(at.x, at.y)
		_player.global_position = Vector3(at.x, ground + 0.8, at.y)
		rig.global_position = Vector3(at.x, ground + float(shot["eye"]), at.y)
		rig.rotation.y = deg_to_rad(-90.0)     # due east
		arm.rotation.x = shot["pitch"]
		for i in 30:
			await get_tree().process_frame
		await _shoot(dir, String(shot["name"]))
	await _capture_climb(dir)
	get_tree().quit()


## Put Kern on a trunk and photograph him up it. Input is driven synthetically
## because there is nobody at the keyboard: press `interact` to take hold, then
## hold `move_forward` and let the climb run.
func _capture_climb(dir: String) -> void:
	var trees: Array = get_tree().get_nodes_in_group(&"climbable")
	if trees.is_empty():
		push_warning("Climb shot skipped: no climbable trees in the meadow.")
		return
	# The climbable tree nearest the copse the other flora shots look at.
	var target: Node3D = null
	var best: float = INF
	for node in trees:
		var tree: Node3D = node as Node3D
		var d: float = Vector2(tree.global_position.x, tree.global_position.z) \
				.distance_to(Vector2(30.0, -60.0))
		if d < best:
			best = d
			target = tree
	var trunk: Vector3 = target.global_position
	var height: float = float(target.get_meta("climb_height", 4.0))
	var radius: float = float(target.get_meta("climb_radius", 0.46))

	var rig: Node3D = _player.get_node("CameraRig")
	var arm: SpringArm3D = rig.get_node("SpringArm3D") as SpringArm3D
	var kern_visual: Node3D = _player.get_node("Visual") as Node3D
	kern_visual.visible = true
	rig.set_process(false)

	# Stand him just west of the trunk, facing east into it.
	_player.global_position = trunk + Vector3(-(radius + 0.7), 0.4, 0.0)
	# Zero the BODY yaw first. It is set to -135 degrees at spawn and never
	# touched again, so a visual rotation set on top of it lands 135 degrees off
	# — which is exactly how the first climb attempt ended up facing away from
	# the tree it was standing next to.
	_player.rotation.y = 0.0
	kern_visual.rotation.y = atan2(-1.0, 0.0)  # face +X, into the trunk
	for i in 20:
		await get_tree().process_frame

	# Held for several frames, not one. `is_action_just_pressed` is polled from
	# _physics_process, which runs on its own clock — a press and release inside
	# a single rendered frame can fall entirely between two physics ticks, and
	# the grab silently never happens.
	var flat: Vector3 = trunk - _player.global_position
	flat.y = 0.0
	var face: Vector3 = -kern_visual.global_transform.basis.z
	face.y = 0.0
	print("Climb probe: gap=%.2f m (reach %.2f), facing dot=%.2f (need %.2f), kern=%s tree=%s" % [
		flat.length() - radius, TreeClimb.REACH,
		face.normalized().dot(flat.normalized()), TreeClimb.FACING_DOT,
		_player.global_position, trunk,
	])
	Input.action_press(&"interact")
	for i in 6:
		await get_tree().process_frame
	Input.action_release(&"interact")
	Input.action_press(&"move_forward")
	for i in 150:
		await get_tree().process_frame
	Input.action_release(&"move_forward")

	var climbing: bool = bool(_player.get_node("TreeClimb").get(&"is_climbing"))
	print("Climb check: climbing=%s, trunk_h=%.2f, kern_y=%.2f (base %.2f, gained %.2f m)" % [
		climbing, height, _player.global_position.y, trunk.y,
		_player.global_position.y - trunk.y,
	])
	rig.global_position = trunk + Vector3(-6.5, height * 0.7, 3.0)
	rig.rotation.y = deg_to_rad(-115.0)
	arm.rotation.x = 0.10
	arm.spring_length = 0.0
	for i in 25:
		await get_tree().process_frame
	await _shoot(dir, "climb_in_tree")


func _shoot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = dir.path_join(shot_name + ".png")
	print("Screenshot %s -> %s" % ["OK" if img.save_png(path) == OK else "FAILED", path])


func _capture_screens(dir: String) -> void:
	# Angles chosen to judge the GDD §10 bar: the town-and-pond view, the
	# Gradient Peaks vista, the sea horizon, grass up close — and, since
	# milestone 12, the Perceptron Vault inside and out, which is sealed and
	# lit only by its own runes and so cannot be judged from the field.
	var rig: Node3D = _player.get_node("CameraRig")
	# Keep the frame clean: Kern's body, Bit, and the floating landmark/bark
	# labels otherwise sit right on the lens and block the world we're judging.
	var kern_visual: Node3D = _player.get_node("Visual") as Node3D
	if kern_visual != null:
		kern_visual.visible = false
	# Bit is hidden by default (he sits right on the lens for world shots) but a
	# shot can opt back in with "show_bit" — the companion milestone has no other
	# way to produce visual evidence, since he only exists at runtime.
	_bit.visible = false
	_landmarks.visible = false
	var cycle: SkyCycle = get_node("World/SkyCycle") as SkyCycle
	if cycle != null:
		cycle.paused = true
		cycle.set_hour(8.5)
	var arm: SpringArm3D = rig.get_node("SpringArm3D") as SpringArm3D
	# Vault interiors need an absolute Y: the floor sits on a plinth above the
	# terrain, so sampling ground height there would drop Kern through it.
	var floor_y: float = _vault.floor_height() + 0.8 if _vault != null else 0.0
	var site: Vector2 = PerceptronVault.SITE
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
		# Bootstrap (milestone 8): the square from the south road, the market
		# and inn across the crossroads, and the mill out at the pond.
		{"name": "town_square", "yaw": 0.0, "pitch": -0.04, "pos": Vector2(0.0, 54.0)},
		{"name": "town_market", "yaw": deg_to_rad(37.0), "pitch": -0.06,
			"pos": Vector2(19.0, 45.0)},
		{"name": "town_mill", "yaw": deg_to_rad(-42.0), "pitch": -0.08,
			"pos": Vector2(61.0, 21.0)},
		# Sky/cloud verification: the volumetric deck lives at 600-1820 m, so a
		# ground-facing frame shows almost none of it. These look UP.
		{"name": "sky_clouds_up", "yaw": deg_to_rad(-40.0), "pitch": 0.62,
			"pos": Vector2(-42.0, -82.0)},
		{"name": "sky_clouds_horizon", "yaw": deg_to_rad(150.0), "pitch": 0.26,
			"pos": Vector2(-42.0, -82.0)},
		# In-game third-person shots: Kern visible in the dense meadow at the
		# normal ~4.5 m behind-and-above framing — "how it actually looks in
		# play." Camera is placed explicitly behind him (rig frozen, spring 0)
		# because the spring arm mis-settles under teleport. `face` turns Kern
		# into the view. `pos` = camera, `player_at` = where Kern stands.
		{"name": "ingame_kern_meadow", "yaw": deg_to_rad(18.0), "pitch": -0.16,
			"pos": Vector2(-40.6, -77.7), "eye": 2.0, "show_kern": true,
			"spring": 0.0, "freeze_rig": true, "player_at": Vector2(-42.0, -82.0),
			"face": deg_to_rad(18.0)},
		{"name": "ingame_kern_field", "yaw": deg_to_rad(-70.0), "pitch": -0.15,
			"pos": Vector2(17.8, -42.5), "eye": 2.0, "show_kern": true,
			"spring": 0.0, "freeze_rig": true, "player_at": Vector2(22.0, -44.0),
			"face": deg_to_rad(-70.0)},
		{"name": "ingame_kern_toward_peaks", "yaw": deg_to_rad(40.0), "pitch": -0.10,
			"pos": Vector2(-15.1, -26.5), "eye": 2.0, "show_kern": true,
			"spring": 0.0, "freeze_rig": true, "player_at": Vector2(-18.0, -30.0),
			"face": deg_to_rad(40.0)},
		# Kern standing in the sward — verifies the trample parting around him.
		# Spring arm collapsed so the camera sits exactly at the posed point
		# and looks straight down at his feet, where the parting shows.
		{"name": "detail_trample", "yaw": 0.0, "pitch": -0.42,
			"pos": Vector2(-40.0, -76.6), "eye": 1.7, "show_kern": true,
			"spring": 0.0, "freeze_rig": true, "player_at": Vector2(-40.0, -80.0)},
		# The landing area — where a new player actually opens their eyes.
		# SPAWN_POINT is (-58, -62) and Kern is turned to -135 deg (southeast,
		# toward Bootstrap and the pond), so "behind him" is northwest: the
		# camera offsets below are that facing reversed, 3-4 m back.
		{"name": "spawn_over_shoulder", "yaw": deg_to_rad(-135.0), "pitch": -0.11,
			"pos": Vector2(-60.1, -64.1), "eye": 2.0, "show_kern": true,
			"show_bit": true, "spring": 0.0, "freeze_rig": true,
			"player_at": Vector2(-58.0, -62.0), "face": deg_to_rad(-135.0)},
		# Reverse angle: the camera stands southeast of Kern looking back at him,
		# so the face the imported base mesh gave him is actually in frame.
		{"name": "spawn_facing_kern", "yaw": deg_to_rad(45.0), "pitch": -0.09,
			"pos": Vector2(-55.5, -59.5), "eye": 2.0, "show_kern": true,
			"show_bit": true, "spring": 0.0, "freeze_rig": true,
			"player_at": Vector2(-58.0, -62.0), "face": deg_to_rad(-135.0)},
		# Bit at his own altitude. He hovers Bit.HOVER_HEIGHT = 1.78 m above
		# Kern's origin, so the lens sits at eye 2.6 to meet him level rather
		# than looking up at his underside.
		{"name": "bit_closeup", "yaw": deg_to_rad(-135.0), "pitch": -0.02,
			"pos": Vector2(-59.3, -63.3), "eye": 2.6, "show_kern": true,
			"show_bit": true, "spring": 0.0, "freeze_rig": true,
			"player_at": Vector2(-58.0, -62.0), "face": deg_to_rad(-135.0)},
		# The landing area with nobody standing in it, from Kern's own eyeline.
		{"name": "spawn_landing_wide", "yaw": deg_to_rad(-135.0), "pitch": -0.06,
			"pos": Vector2(-58.0, -62.0), "eye": 2.45},
		# Yaw 180° looks due south — straight down the vault's axis, which is
		# the order a player walks it: facade, hall, chamber, junction, arena.
		{"name": "vault_approach", "yaw": PI, "pitch": 0.10,
			"pos": site + Vector2(0.0, -73.0)},
		{"name": "vault_input_hall", "yaw": PI, "pitch": 0.02,
			"pos": site + Vector2(0.0, -30.0), "y": floor_y},
		{"name": "vault_chamber", "yaw": PI, "pitch": 0.02,
			"pos": site + Vector2(15.2, -10.0), "y": floor_y},
		{"name": "vault_junction", "yaw": PI, "pitch": 0.04,
			"pos": site + Vector2(0.0, 7.0), "y": floor_y},
		{"name": "vault_arena_gate", "yaw": PI, "pitch": 0.02,
			"pos": site + Vector2(0.0, 22.0), "y": floor_y},
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
		_bit.visible = shot.get("show_bit", false)
		# The rig normally re-follows the player every frame (and forces a
		# 1.65 m eye) — freeze it so a posed camera that looks AT Kern (e.g.
		# the trample shot) actually stays where it's put.
		if shot.get("freeze_rig", false):
			rig.set_process(false)
		if shot.has("pos"):
			var sample: Vector2 = shot["pos"]
			var eye: float = shot.get("eye", 2.45)
			# Kern normally stands at the camera spot; a shot can instead pose
			# him elsewhere in frame (e.g. to verify the grass trample). Vault
			# interiors use an absolute floor height because terrain sampling
			# would place Kern below the constructed dungeon floor.
			var stand: Vector2 = shot.get("player_at", sample)
			var stand_y: float = float(shot["y"]) if shot.has("y") \
					else _terrain.get_height(stand.x, stand.y) + 0.8
			_player.global_position = Vector3(
				stand.x, stand_y, stand.y
			)
			if shot.has("face"):
				_player.rotation.y = shot["face"]
			var camera_y: float = stand_y + 1.65 if shot.has("y") \
					else _terrain.get_height(sample.x, sample.y) + eye
			rig.global_position = Vector3(
				sample.x, camera_y, sample.y
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

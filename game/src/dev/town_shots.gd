class_name TownShots
extends RefCounted
## Dev-only close-range photographer for the Town of Bootstrap.
##
## The existing `--screenshot=` pass (main.gd) gives Bootstrap exactly three
## frames, all of them from tens of metres out. That is enough to answer "is
## there a town there" and useless for "is the town any good" — you cannot judge
## a doorway, a sign, a market counter or a villager's face from the far side of
## the square. This rig answers the second question: fifteen authored vantage
## points at conversation range, standing in the streets.
##
## It deliberately drives the **player's own CameraRig** rather than adding a
## camera of its own, so every frame comes through the game's real
## WorldEnvironment, real tonemap and real post stack. A shot taken through a
## private camera can flatter geometry the player will never see that way.
##
## Camera aim is authored as a *look-at target*, not as yaw/pitch, because a
## close shot is framed around a thing (the anvil, the sign, the wheel), and the
## angle that frames it changes whenever that thing moves. Positions are in
## town-local metres around `MeadowTerrain.TOWN_CENTER` — the same frame
## `bootstrap_town.gd` authors its map in — so this list follows the town if the
## town ever moves.
##
## Run:
##   godot --path game --resolution 1920x1080 -- --townshot=C:/abs/dir
## Never part of the shipped game; only main.gd's dev branch calls it.

## Hour of the sky cycle every shot is taken at. Mid-morning: the sun is high
## enough to light shopfronts but low enough that eaves, thatch courses and the
## forge's open front still cast shadows that show their depth.
const SHOT_HOUR: float = 10.0

## Frames to wait before the first capture. SDFGI cascades, TAA history and the
## shadow atlas all need to converge or the first frame renders visibly noisy.
const SETTLE_FRAMES: int = 120

## Frames to wait after each camera move. TAA re-converges quickly but not
## instantly; below ~25 frames close geometry keeps a faint ghost.
const REFRAME_FRAMES: int = 36


## Photograph Bootstrap from fifteen standing points inside it.
##
## `main` owns the tree; `player` supplies the camera rig this drives; `terrain`
## answers ground height under each stand; `town` is asked where the mill ended
## up (its site is chosen from the pond's bank at runtime, so it is not a
## constant anyone can type here); `cycle` is pinned so a long capture does not
## drift through the afternoon; `landmarks` and `bit` are hidden because both
## otherwise sit directly on the lens.
func capture(main: Node3D, player: CharacterBody3D, terrain: MeadowTerrain,
		town: BootstrapTown, cycle: SkyCycle, landmarks: Node3D, bit: Node3D,
		dir: String, hour: float = SHOT_HOUR) -> void:
	var rig: Node3D = player.get_node("CameraRig")
	var arm: SpringArm3D = rig.get_node("SpringArm3D") as SpringArm3D
	var camera: Camera3D = arm.get_node("Camera3D") as Camera3D
	var kern: Node3D = player.get_node("Visual") as Node3D

	# The rig re-follows Kern and re-lerps its FOV every frame; a posed camera
	# that is not frozen drifts back onto his shoulder mid-exposure.
	rig.set_process(false)
	arm.spring_length = 0.0
	if landmarks != null:
		landmarks.visible = false  # floating place-labels sit over the rooftops
	if bit != null:
		bit.visible = false
	if cycle != null:
		cycle.paused = true
		cycle.set_hour(hour)

	var shots: Array[Dictionary] = _shot_list(town)
	for i in SETTLE_FRAMES:
		await main.get_tree().process_frame

	for shot: Dictionary in shots:
		var cam_pos: Vector3 = _resolve(shot, "cam", "pos", "eye", terrain)
		var aim_pos: Vector3 = _resolve(shot, "aim_world", "aim", "aim_up", terrain)

		# Kern appears in one frame only, as a scale rule against the buildings.
		# Everywhere else he stands in the way of what is being judged.
		if kern != null:
			kern.visible = shot.get("show_kern", false)
		if shot.has("kern_at"):
			var stand: Vector2 = _world(shot["kern_at"])
			player.global_position = Vector3(stand.x,
				terrain.get_height(stand.x, stand.y) + 0.8, stand.y)
			player.velocity = Vector3.ZERO
			player.rotation.y = float(shot.get("kern_face", 0.0))

		rig.global_position = cam_pos
		var d: Vector3 = aim_pos - cam_pos
		var flat: float = Vector2(d.x, d.z).length()
		rig.rotation.y = atan2(-d.x, -d.z)
		arm.rotation.x = atan2(d.y, flat)
		# A close shot at the rig's 64 deg play FOV stretches whatever is near the
		# frame edge, which reads as a modelling fault that is not there. Detail
		# shots drop to a portrait lens; context shots keep the play FOV so the
		# framing stays honest about what the game actually shows.
		camera.fov = float(shot.get("fov", CameraRig.FOV_BASE))

		for i in REFRAME_FRAMES:
			await main.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = main.get_viewport().get_texture().get_image()
		var path: String = dir.path_join(String(shot["name"]) + ".png")
		print("TownShot %s -> %s" % ["OK" if image.save_png(path) == OK else "FAILED", path])

	main.get_tree().quit()


## Resolve one end of a shot into world space. A shot normally gives a
## town-local XZ and a height above the ground there; the mill shots instead
## carry an absolute Vector3, because the mill stands on a pond bank whose
## ground height is below the waterline the wheel is framed against.
func _resolve(shot: Dictionary, world_key: String, local_key: String,
		up_key: String, terrain: MeadowTerrain) -> Vector3:
	if shot.has(world_key):
		return shot[world_key]
	var flat: Vector2 = _world(shot[local_key])
	return Vector3(flat.x, terrain.get_height(flat.x, flat.y) + float(shot[up_key]), flat.y)


## Town-local metres -> world XZ, matching `bootstrap_town.gd`'s own helper.
func _world(local: Vector2) -> Vector2:
	return MeadowTerrain.TOWN_CENTER + local


## The fifteen standing points, in the order a visitor would walk them: in from
## the south road, round the square, out through the east gate to the mill.
## Every `pos`/`aim` below is town-local, and every one of them is aimed at a
## specific authored thing — the coordinates are copied from the plot and prop
## map in `bootstrap_town.gd`, so if that map moves, these follow it by hand.
func _shot_list(town: BootstrapTown) -> Array[Dictionary]:
	var shots: Array[Dictionary] = [
		# 1 — the arrival view, and the only frame with Kern in it. He is the
		# 1.75 m rule STRUCTURE_PIPELINE section 3 measures every building
		# against, so one frame has to contain him or scale is unjudgeable.
		{"name": "01_main_street_arrival", "pos": Vector2(0.0, 17.0), "eye": 1.75,
			"aim": Vector2(0.0, -19.0), "aim_up": 3.2,
			"show_kern": true, "kern_at": Vector2(2.8, 9.0), "kern_face": 0.0},
		# 2 — the mayor's hall closes the north side; banner, door and chimney.
		#     Stood back 15 m: the hall is 13 m wide and a closer lens frames
		#     one porch column instead of a building.
		{"name": "02_town_hall_facade", "pos": Vector2(-7.0, -4.0), "eye": 2.05,
			"aim": Vector2(0.0, -17.5), "aim_up": 3.2, "fov": 55.0},
		# 3 — Mayor Maxwell Pool at his post, at the distance you talk to him.
		{"name": "03_mayor_maxwell", "pos": Vector2(3.4, -8.4), "eye": 1.68,
			"aim": Vector2(0.15, -11.8), "aim_up": 1.45, "fov": 45.0},
		# 4 — Clem Clatter's tower and the bell named Confusion. The tower is 7 m
		#     to the eaves and ~8 m to the roof peak, so the camera needs 13 m
		#     and a 52 deg lens to get the bell inside the frame at all.
		#     Stand clear of the forge while doing it: the forge is rotated to face
		#     west, so its 9 m width runs along Z and its footprint is
		#     x 12.5..19.5 / z -11.5..-2.5 — not the 9-wide-in-X box the plot
		#     table reads like, and a camera at x 19.5 is inside its wall.
		{"name": "04_bell_tower_and_clem", "pos": Vector2(21.5, -12.5), "eye": 2.00,
			"aim": Vector2(10.5, -19.8), "aim_up": 3.4, "fov": 52.0},
		# 5 — the Warm Start: jettied upper storey, dormer, door lantern, bench.
		#     Shot from the square rather than head-on, because the two
		#     square-corner lamp posts stand almost exactly on the head-on
		#     sightline. NOTE: the "The Warm Start" signboard is NOT in this
		#     frame and cannot be — it is built inside the jetty. See DEVLOG.
		#     Reframed for the Blender-authored inn (2026-08-09): the building
		#     is now 7.7 m to the ridge instead of 5.8, and the old standing
		#     point cropped its roof off.
		#     Approached from the south-east so the notice board, which stands
		#     one metre off the straight-on line, stays out of the lens.
		{"name": "05_warm_start_inn", "pos": Vector2(-1.5, -10.0), "eye": 2.05,
			"aim": Vector2(-12.0, -5.0), "aim_up": 3.9, "fov": 52.0},
		# 6 — Mara Mallow outside her own door.
		{"name": "06_mara_at_the_inn", "pos": Vector2(-7.2, -6.0), "eye": 1.60,
			"aim": Vector2(-10.0, -4.0), "aim_up": 1.45, "fov": 42.0},
		# 7 — Branna's yard: anvil, quench trough, and the open-fronted forge,
		#     with Branna herself at the far end of it. One frame covers the
		#     smith and her workplace, which is why she gets no separate portrait.
		{"name": "07_forge_yard_and_anvil", "pos": Vector2(6.0, -3.4), "eye": 1.65,
			"aim": Vector2(13.5, -7.2), "aim_up": 1.30, "fov": 52.0},
		# 8 — Tansy's honey stall: ranked pots, the striped awning, and the
		#     ribboned skeps standing behind her. Eye is above the 1.0 m counter
		#     and the approach is angled off the notice board, which stands one
		#     metre off the straight-on line and fills the frame edge from there.
		{"name": "08_market_honey_stall", "pos": Vector2(-8.0, 1.5), "eye": 2.10,
			"aim": Vector2(-5.8, 8.6), "aim_up": 1.75, "fov": 50.0},
		# 9 — Orrin's produce stall: the brass scale and the prize turnip. Kept
		#     west of the cart and the two barrels, which sit on the eastern
		#     approach at arm's length from the lens.
		{"name": "09_market_produce_stall", "pos": Vector2(4.5, -0.5), "eye": 2.15,
			"aim": Vector2(5.6, 8.6), "aim_up": 1.75, "fov": 48.0},
		# 10 — the crossroads fingerpost, Bootstrap's quiet map of the region.
		{"name": "10_crossroads_fingerpost", "pos": Vector2(-1.6, -1.2), "eye": 1.95,
			"aim": Vector2(2.6, -6.0), "aim_up": 2.40, "fov": 44.0},
		# 11 — the square's furniture: notice board, cart, barrels, stepping stones.
		{"name": "11_notice_board_and_cart", "pos": Vector2(-1.0, 8.2), "eye": 1.62,
			"aim": Vector2(-4.2, 3.2), "aim_up": 1.60, "fov": 48.0},
		# 12 — the one true detail shot: a shuttered window on the east cottage's
		#      road wall, close enough to judge the shutter leaf, the flower box,
		#      the half-timber and the plaster. Whole cottages are legible in
		#      shots 1, 11 and 13; what those cannot answer is material quality.
		{"name": "12_cottage_window_detail", "pos": Vector2(18.5, 3.4), "eye": 1.70,
			"aim": Vector2(29.0, 2.4), "aim_up": 2.30, "fov": 36.0},
		# 13 — Cedric Cluster's fold: post-and-rail, five sheep, the hay bale.
		{"name": "13_sheepfold_and_cedric", "pos": Vector2(-15.5, -14.5), "eye": 1.72,
			"aim": Vector2(-23.5, -21.0), "aim_up": 0.75, "fov": 48.0},
		# 14 — the east gate Rowan Threshold keeps, with the mill road beyond it.
		#      Threaded between two rotated footprints: the forge sits at
		#      x 12.5..19.5 / z -11.5..-2.5 and the east cottage at x 21..27 /
		#      z 1.5..8.5, leaving one narrow corridor that sees the arch at all.
		{"name": "14_east_gate_and_rowan", "pos": Vector2(15.5, -0.5), "eye": 2.05,
			"aim": Vector2(30.0, 1.3), "aim_up": 2.70, "fov": 44.0},
	]
	# 15 — the mill, the one piece of Bootstrap outside the square and the
	# town's only moving machine. Appended rather than authored inline because
	# its site is not a constant; see `_mill_shot`.
	var mill_shot: Dictionary = _mill_shot(town)
	if not mill_shot.is_empty():
		shots.append(mill_shot)
	return shots


## Frame the millpond wheel, or `{}` if the mill is missing.
##
## The mill's site is chosen at runtime by walking in from the pond's rim, so
## nothing here may be hard-coded. The wheel is authored on the building's +X
## side and the building is turned to face the water, so a camera placed out
## over the pond and swung along the bank sees the paddles side-on, which is the
## only angle at which "is it actually in the water" can be answered.
func _mill_shot(town: BootstrapTown) -> Dictionary:
	var mill: Node3D = town.get_node_or_null("Building_mill") as Node3D
	if mill == null:
		push_warning("TownShots: no mill built — keeping the east gate shot instead.")
		return {}
	var wheel: Node3D = mill.get("wheel") as Node3D
	if wheel == null:
		push_warning("TownShots: mill has no wheel node — keeping the east gate shot.")
		return {}
	var hub: Vector3 = wheel.global_position
	var site: Vector2 = Vector2(mill.global_position.x, mill.global_position.z)
	var to_water: Vector2 = (MeadowTerrain.POND_CENTER - site).normalized()
	var along_bank: Vector2 = Vector2(-to_water.y, to_water.x)
	var cam_flat: Vector2 = site + to_water * 9.0 + along_bank * 8.5
	return {
		"name": "15_the_mill_wheel",
		"cam": Vector3(cam_flat.x, hub.y + 2.2, cam_flat.y),
		"aim_world": Vector3(hub.x, hub.y - 0.6, hub.z),
		"fov": 46.0,
	}

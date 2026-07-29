class_name BootstrapTown
extends Node3D
## The Town of Bootstrap — Phase 1 milestone 8.
##
## WORLDBOOK Part II: Bootstrap is Datasedge Meadows' town, "13 NPCs approved
## (Mayor Maxwell Pool + 12 townsfolk). Complete; extend only via side quests."
## So this script builds the *place* and lets ContentDB supply the *people*: it
## owns a map (where each building stands, which way it faces, which villager
## works there) and nothing else. Every spoken word comes from
## content/approved/npcs.
##
## The map is authored in town-local meters around MeadowTerrain.TOWN_CENTER,
## whose pad the terrain already flattens, so the layout follows the town if
## the world's geography ever moves. Local +X is east, +Z is south.
##
## Canon anchors honored here: the Warm Start Inn (Mara), Branna's forge and
## its notched beam, the Mayor's hall, Clem's bell tower (the bell is named
## Confusion), the market where Tansy and Orrin trade, the eastern gate Rowan
## keeps, Elowen's seed-ledger house, Nessa's window seat, Cedric's sheepfold,
## Jory's irrigation channel, and — out along the east road at the millpond
## MeadowTerrain carves — the Mill itself, with Fen fishing beside it. Bit
## already names that mill ("Lovely wheel"); now there is one, and it turns.

const NIGHT_WINDOW_ENERGY: float = 2.6
const NIGHT_LAMP_ENERGY: float = 2.4
const WHEEL_SPEED: float = 0.55

var _terrain: MeadowTerrain
var _cycle: SkyCycle
var _windows: Array[MeshInstance3D] = []
var _lamp_flames: Array[MeshInstance3D] = []
var _lamp_lights: Array[OmniLight3D] = []
var _swingers: Array[Node3D] = []
var _sheep: Array[Node3D] = []
var _sheep_base: PackedFloat32Array = PackedFloat32Array()
var _wheel: Node3D
var _mill_site: Vector2 = Vector2.ZERO
var _time: float = 0.0


func build(terrain: MeadowTerrain, cycle: SkyCycle) -> void:
	var start_ms: int = Time.get_ticks_msec()
	_terrain = terrain
	_cycle = cycle
	_mill_site = _find_mill_site()
	_build_roads()
	var buildings: int = _build_buildings()
	_build_yards()
	var placed: int = _place_npcs()
	_collect_lit_props()
	_apply_night(_night_factor())
	print("BootstrapTown: %d buildings, %d villagers, %d windows, %d lamps in %d ms." % [
		buildings, placed, _windows.size(), _lamp_lights.size(),
		Time.get_ticks_msec() - start_ms,
	])


func _process(delta: float) -> void:
	_time += delta
	_apply_night(_night_factor())
	if _wheel != null:
		_wheel.rotate_object_local(Vector3.UP, WHEEL_SPEED * delta)
	for i in _swingers.size():
		_swingers[i].rotation.z = sin(_time * 1.15 + float(i) * 0.7) * 0.045
	for i in _sheep.size():
		_sheep[i].position.y = _sheep_base[i] + sin(_time * 1.3 + float(i) * 1.9) * 0.02


# --- The map -----------------------------------------------------------------

func _build_buildings() -> int:
	var plaster: Color = Color(0.86, 0.83, 0.73)
	var lime: Color = Color(0.9, 0.88, 0.8)
	var clay: Color = Color(0.78, 0.72, 0.6)
	var slate_roof: Color = Color(0.4, 0.36, 0.38)
	var tile_roof: Color = Color(0.55, 0.31, 0.24)
	var thatch_roof: Color = Color(0.66, 0.54, 0.28)

	var plots: Array[Dictionary] = [
		# The mayor's hall closes the north side of the square.
		{"key": "town_hall", "style": "hall", "pos": Vector2(0.0, -20.0),
			"face": Vector2(0.0, 0.0), "size": Vector3(13.0, 4.2, 9.0),
			"wall": lime, "roof": slate_roof, "opts": {"banner": true, "chimney": true}},
		{"key": "bell_tower", "style": "tower", "pos": Vector2(10.5, -20.5),
			"face": Vector2(0.0, 0.0), "size": Vector3(2.8, 7.0, 2.8),
			"wall": plaster, "roof": slate_roof, "opts": {}},
		# The Warm Start keeps the west side, its sign over the road.
		{"key": "warm_start_inn", "style": "inn", "pos": Vector2(-16.0, -4.0),
			"face": Vector2(0.0, -4.0), "size": Vector3(11.0, 5.8, 8.0),
			"wall": plaster, "roof": tile_roof,
			"opts": {"sign": "The Warm Start", "chimney": true, "smoke": true,
				"lantern": true}},
		# Branna's forge faces the square across the east road, open-fronted.
		{"key": "forge", "style": "forge", "pos": Vector2(16.0, -7.0),
			"face": Vector2(0.0, -7.0), "size": Vector3(9.0, 3.8, 7.0),
			"wall": clay, "roof": slate_roof, "opts": {"chimney": true, "smoke": true}},
		# Elowen's seed-ledger house, with the wide window she reads by.
		{"key": "ledger_house", "style": "house", "pos": Vector2(-15.0, 12.0),
			"face": Vector2(-15.0, 0.0), "size": Vector3(8.0, 3.4, 7.0),
			"wall": plaster, "roof": tile_roof, "opts": {"chimney": true}},
		# Nessa's cottage — she mends from the window seat.
		{"key": "menders_cottage", "style": "house", "pos": Vector2(14.0, 12.0),
			"face": Vector2(14.0, 0.0), "size": Vector3(7.5, 3.2, 6.5),
			"wall": clay, "roof": thatch_roof, "opts": {"chimney": true}},
		{"key": "cottage_west", "style": "cottage", "pos": Vector2(-26.0, -14.0),
			"face": Vector2(0.0, -14.0), "size": Vector3(7.0, 3.2, 6.0),
			"wall": plaster, "roof": thatch_roof, "opts": {"chimney": true, "smoke": true}},
		{"key": "cottage_east", "style": "cottage", "pos": Vector2(24.0, 5.0),
			"face": Vector2(0.0, 5.0), "size": Vector3(7.0, 3.2, 6.0),
			"wall": clay, "roof": tile_roof, "opts": {"chimney": true}},
		{"key": "cottage_southwest", "style": "cottage", "pos": Vector2(-22.0, 22.0),
			"face": Vector2(0.0, 6.0), "size": Vector3(6.5, 3.0, 6.0),
			"wall": plaster, "roof": thatch_roof, "opts": {}},
		{"key": "cottage_south", "style": "cottage", "pos": Vector2(9.0, 25.0),
			"face": Vector2(0.0, 6.0), "size": Vector3(7.0, 3.2, 6.0),
			"wall": clay, "roof": thatch_roof, "opts": {"chimney": true, "smoke": true}},
		{"key": "cottage_south_west", "style": "cottage", "pos": Vector2(-8.0, 27.0),
			"face": Vector2(0.0, 6.0), "size": Vector3(6.5, 3.0, 5.5),
			"wall": plaster, "roof": tile_roof, "opts": {"chimney": true}},
		{"key": "cottage_northeast", "style": "cottage", "pos": Vector2(26.0, -17.0),
			"face": Vector2(6.0, 0.0), "size": Vector3(6.5, 3.0, 5.5),
			"wall": clay, "roof": thatch_roof, "opts": {"chimney": true}},
	]

	for plot: Dictionary in plots:
		var pos: Vector2 = plot["pos"]
		var building: TownBuilding = TownBuilding.new()
		building.name = "Building_" + str(plot["key"])
		add_child(building)
		building.build(str(plot["style"]), plot["size"], plot["wall"], plot["roof"],
			plot["opts"] as Dictionary)
		_place(building, pos, _yaw_to(pos, plot["face"]))
		_swingers.append_array(building.swingers)

	_build_mill()
	return plots.size() + 1


## Where a miller would actually build: walk in from the pond's northwestern
## rim until the bank is about a wheel's soak above the water. Picking the site
## from the terrain instead of a hand-typed coordinate is what keeps the wheel
## in the water — the bank drops 2.5 m in the last few meters, so a guessed
## spot buries the paddles or leaves them spinning in the air.
func _find_mill_site() -> Vector2:
	var toward_shore: Vector2 = Vector2(-0.94, -0.34).normalized()
	var site: Vector2 = MeadowTerrain.POND_CENTER + toward_shore * MeadowTerrain.POND_RADIUS
	for i in 40:
		var r: float = MeadowTerrain.POND_RADIUS - float(i) * 0.4
		var p: Vector2 = MeadowTerrain.POND_CENTER + toward_shore * r
		if _terrain.get_height(p.x, p.y) - _terrain.water_level <= 1.3:
			return p
		site = p
	return site


func _build_mill() -> void:
	var ground: float = _terrain.get_height(_mill_site.x, _mill_site.y)
	var radius: float = 2.6
	# Hub height so the paddles break the surface, but never sink the axle.
	var hub_y: float = clampf(_terrain.water_level + radius - 0.45 - ground,
		radius * 0.35, radius + 0.3)
	var mill: TownBuilding = TownBuilding.new()
	mill.name = "Building_mill"
	add_child(mill)
	mill.build("mill", Vector3(8.0, 4.4, 7.0), Color(0.8, 0.75, 0.62),
		Color(0.5, 0.33, 0.25),
		{"wheel_radius": radius, "wheel_hub_y": hub_y,
			"sign": "Bootstrap Mill", "sign_side": -1.0})
	mill.position = Vector3(_mill_site.x, ground, _mill_site.y)
	# The wheel is authored on the building's +X side, so point +X at the water.
	mill.rotation.y = _arm_yaw(_mill_site, MeadowTerrain.POND_CENTER)
	_wheel = mill.wheel
	_swingers.append_array(mill.swingers)
	print("BootstrapTown: mill sited at (%.1f, %.1f), bank %.2f m over the water." % [
		_mill_site.x, _mill_site.y, ground - _terrain.water_level,
	])


func _build_roads() -> void:
	# Stepping-stone roads: north-south through the square, the east road out
	# through the gate to the mill, and a west spur past the inn.
	var north_south: Array[Vector2] = [
		_world(Vector2(0.0, -16.0)), _world(Vector2(0.0, 0.0)), _world(Vector2(0.0, 27.0)),
	]
	var east_west: Array[Vector2] = [
		_world(Vector2(-26.0, 0.0)), _world(Vector2(0.0, 0.0)), _world(Vector2(30.0, 2.0)),
	]
	# The mill road leaves the pad entirely, so its far points are world-space:
	# it bends around the pond's northern rim to the mill.
	var mill_road: Array[Vector2] = [
		_world(Vector2(32.0, 2.0)), Vector2(50.0, 24.0), _mill_site + Vector2(-7.0, 3.0),
	]
	add_child(TownProps.path_stones(north_south, _terrain, "main_street", 2.4))
	add_child(TownProps.path_stones(east_west, _terrain, "market_road", 2.4))
	add_child(TownProps.path_stones(mill_road, _terrain, "mill_road", 1.8))


## Everything between the buildings: the square's furniture, the market, the
## gate, the sheepfold, the gardens, and Jory's channel.
func _build_yards() -> void:
	_add_prop(TownProps.notice_board(), Vector2(-4.0, 3.0), PI)
	_add_prop(TownProps.cart(), Vector2(6.0, 4.0), -0.6)
	_add_prop(TownProps.barrel(), Vector2(7.4, 2.6), 0.0)
	_add_prop(TownProps.barrel(), Vector2(8.0, 3.4), 0.7)
	_add_prop(TownProps.crate(), Vector2(-6.5, 4.2), 0.4)

	# The crossroads fingerpost: Bootstrap's quiet map of the region.
	var post_local: Vector2 = Vector2(2.6, -6.0)
	var post_world: Vector2 = _world(post_local)
	var arms: Array[Dictionary] = [
		{"text": "Seed Vault ruins", "yaw": _arm_yaw(post_world, Vector2(-72.0, -70.0))},
		{"text": "Gradient Peaks", "yaw": _arm_yaw(post_world, Vector2(0.0, -205.0))},
		{"text": "The Old Millpond", "yaw": _arm_yaw(post_world, MeadowTerrain.POND_CENTER)},
		{"text": "Whispering Well", "yaw": _arm_yaw(post_world, Vector2(46.0, 24.0))},
	]
	_add_prop(TownProps.fingerpost(arms), post_local, 0.0)

	# Market row on the square's south side.
	_add_prop(TownProps.market_stall(Color(0.93, 0.78, 0.3), "honey"),
		Vector2(-5.5, 8.0), _yaw_to(Vector2(-5.5, 8.0), Vector2(-5.5, 0.0)))
	_add_prop(TownProps.market_stall(Color(0.72, 0.34, 0.3), "produce"),
		Vector2(5.5, 8.0), _yaw_to(Vector2(5.5, 8.0), Vector2(5.5, 0.0)))
	_add_prop(TownProps.skep(Vector3.ZERO), Vector2(-9.5, 10.0), 0.4)
	_add_prop(TownProps.skep(Vector3.ZERO), Vector2(-10.8, 11.2), 1.1)

	# Lamps: four at the square's corners, two more BESIDE the roads out — the
	# stepping-stone lanes are 2.4 m wide and centred on x = 0 / z = 0, so
	# anything standing on those lines is standing in the road.
	for spot: Vector2 in [Vector2(-7.5, -7.0), Vector2(7.5, -7.0), Vector2(-7.5, 7.5),
			Vector2(7.5, 7.5), Vector2(20.0, 4.2), Vector2(2.8, 18.0)]:
		_add_prop(TownProps.lamp_post(), spot, 0.0)

	# Branna's yard: the anvil in front of the open forge, water to quench in.
	_add_prop(TownProps.anvil(), Vector2(11.0, -7.0), 0.3)
	_add_prop(TownProps.water_trough(), Vector2(12.5, -3.2), 0.0)
	_add_prop(TownProps.barrel(), Vector2(12.2, -10.5), 0.0)

	# The eastern gate, turned so the road runs through it.
	_add_prop(TownProps.gate_arch(), Vector2(30.0, 2.0), PI * 0.5)

	# Cedric's fold: a pen of post-and-rail with his flock inside.
	var pen: Array[Vector2] = [
		Vector2(-28.0, -25.0), Vector2(-19.0, -25.0), Vector2(-19.0, -17.0),
		Vector2(-28.0, -17.0), Vector2(-28.0, -25.0),
	]
	for i in pen.size() - 1:
		add_child(TownProps.fence_run(_world(pen[i]), _world(pen[i + 1]), _terrain))
	var flock: Array[Vector2] = [
		Vector2(-25.5, -22.5), Vector2(-22.0, -23.5), Vector2(-21.0, -19.5),
		Vector2(-25.0, -19.0), Vector2(-23.5, -21.0),
	]
	for i in flock.size():
		var lamb: Node3D = TownProps.sheep("bootstrap_%d" % i)
		_add_prop(lamb, flock[i], 0.0)
		_sheep.append(lamb)
		_sheep_base.append(lamb.position.y)
	_add_prop(TownProps.hay_bale(), Vector2(-18.0, -20.0), 0.5)

	# Kitchen gardens behind the southern cottages.
	_add_prop(TownProps.garden_patch(Vector2(5.0, 3.5), "south"), Vector2(9.0, 20.0), 0.0)
	_add_prop(TownProps.garden_patch(Vector2(4.0, 3.0), "ledger"), Vector2(-15.0, 17.0), 0.0)

	# Jory's irrigation channel, running off the pad and downhill to the west.
	add_child(TownProps.irrigation_channel(_world(Vector2(-6.0, 30.0)),
		_world(Vector2(-26.0, 41.0)), _terrain))

	# Fen's chair at the millpond, for the day's most persuasive fish.
	var chair_pos: Vector2 = _mill_site + Vector2(-1.5, 6.0)
	var chair: Node3D = TownProps.chair()
	chair.position = Vector3(chair_pos.x, _terrain.get_height(chair_pos.x, chair_pos.y),
		chair_pos.y)
	chair.rotation.y = _yaw_to(chair_pos, MeadowTerrain.POND_CENTER)
	add_child(chair)
	var barrel_pos: Vector2 = _mill_site + Vector2(-5.0, -1.5)
	var mill_barrel: Node3D = TownProps.barrel()
	mill_barrel.position = Vector3(barrel_pos.x,
		_terrain.get_height(barrel_pos.x, barrel_pos.y), barrel_pos.y)
	add_child(mill_barrel)


# --- The people --------------------------------------------------------------

## Where each approved villager works. Positions are town-local; `face` is the
## point they idle toward; `accent` picks the props their approved description
## insists on. Anyone approved for the region without a post here still gets
## placed (in the square) rather than silently vanishing.
func _npc_posts() -> Dictionary:
	return {
		"npc_mayor_maxwell": {"pos": Vector2(0.0, -12.0), "face": Vector2(0.0, 0.0),
			"accent": "mayor"},
		"npc_mara_mallow": {"pos": Vector2(-10.0, -4.0), "face": Vector2(0.0, -2.0),
			"accent": ""},
		"npc_branna_bellows": {"pos": Vector2(11.6, -7.8), "face": Vector2(11.0, -7.0),
			"accent": ""},
		"npc_elowen_patch": {"pos": Vector2(-13.6, 7.4), "face": Vector2(-8.0, 2.0),
			"accent": ""},
		"npc_nessa_fold": {"pos": Vector2(12.4, 7.6), "face": Vector2(8.0, 2.0),
			"accent": "seamstress"},
		"npc_tansy_hivewise": {"pos": Vector2(-5.5, 9.7), "face": Vector2(-5.5, 0.0),
			"accent": "beekeeper"},
		"npc_orrin_bushel": {"pos": Vector2(5.5, 9.7), "face": Vector2(5.5, 0.0),
			"accent": "greengrocer"},
		"npc_rowan_threshold": {"pos": Vector2(26.5, 3.4), "face": Vector2(36.0, 3.4),
			"accent": ""},
		"npc_clem_clatter": {"pos": Vector2(10.5, -16.6), "face": Vector2(4.0, -4.0),
			"accent": "bellringer"},
		"npc_cedric_cluster": {"pos": Vector2(-17.4, -20.5), "face": Vector2(-23.0, -21.0),
			"accent": "shepherd"},
		"npc_jory_slope": {"pos": Vector2(-8.0, 28.5), "face": Vector2(-14.0, 32.0),
			"accent": "ditcher"},
		"npc_tilly_tangle": {"pos": Vector2(3.0, 3.5), "face": Vector2(0.0, -4.0),
			"accent": "", "wander": 6.5},
		# Fen fishes the millpond itself, out along the east road past the gate,
		# so his post is pinned to the sited mill rather than to the square.
		"npc_fen_reedwhistle": {
			"pos": _to_local(_mill_site + Vector2(-0.5, 4.5)),
			"face": _to_local(MeadowTerrain.POND_CENTER), "accent": ""},
	}


func _place_npcs() -> int:
	var posts: Dictionary = _npc_posts()
	var placed: int = 0
	var spare: int = 0
	for entry: Dictionary in ContentDB.get_all("npcs"):
		if str(entry.get("region", "")) != "datasedge_meadows":
			continue
		var id: String = str(entry.get("id", ""))
		var post: Dictionary = posts.get(id, {}) as Dictionary
		var local: Vector2
		var face: Vector2
		if post.is_empty():
			# A villager approved after this map was drawn: stand them in the
			# square so new content shows up in the world without a code change.
			var ang: float = TAU * float(spare) / 8.0
			local = Vector2(cos(ang), sin(ang)) * 11.0
			face = Vector2.ZERO
			spare += 1
			push_warning("BootstrapTown: no post for %s — placed in the square." % id)
		else:
			local = post["pos"]
			face = post["face"]
		var world_pos: Vector2 = _world(local)
		var npc: NpcActor = NpcActor.new()
		add_child(npc)
		npc.configure(entry, str(post.get("accent", "")),
			Vector3(world_pos.x, _terrain.get_height(world_pos.x, world_pos.y), world_pos.y),
			_yaw_to(world_pos, _world(face)), _terrain,
			float(post.get("wander", 0.0)))
		placed += 1
	return placed


# --- Night ------------------------------------------------------------------

func _collect_lit_props() -> void:
	for node: Node in get_tree().get_nodes_in_group(TownKit.GROUP_WINDOW):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi != null:
			_windows.append(mi)
	for node: Node in get_tree().get_nodes_in_group(TownKit.GROUP_LAMP):
		var light: OmniLight3D = node as OmniLight3D
		if light != null:
			_lamp_lights.append(light)
			continue
		var flame: MeshInstance3D = node as MeshInstance3D
		if flame != null:
			_lamp_flames.append(flame)


## 0 at midday, 1 deep in the night — the same dusk/dawn shoulders SkyCycle's
## color script turns on.
func _night_factor() -> float:
	if _cycle == null:
		return 0.0
	var h: float = _cycle.hour
	var day: float = smoothstep(5.2, 7.4, h) * (1.0 - smoothstep(17.2, 19.4, h))
	return 1.0 - day


func _apply_night(night: float) -> void:
	for mi: MeshInstance3D in _windows:
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_color = TownKit.GLASS_DAY.lerp(TownKit.GLASS_NIGHT, night)
		mat.emission_energy_multiplier = night * NIGHT_WINDOW_ENERGY
	for flame: MeshInstance3D in _lamp_flames:
		var fmat: StandardMaterial3D = flame.material_override as StandardMaterial3D
		if fmat != null:
			fmat.albedo_color = TownKit.FLAME_DAY.lerp(TownKit.FLAME_NIGHT, night)
			fmat.emission_energy_multiplier = night * 3.2
	for light: OmniLight3D in _lamp_lights:
		light.light_energy = night * NIGHT_LAMP_ENERGY


# --- Map helpers -------------------------------------------------------------

## Town-local meters -> world XZ, and back.
func _world(local: Vector2) -> Vector2:
	return MeadowTerrain.TOWN_CENTER + local


func _to_local(world_pos: Vector2) -> Vector2:
	return world_pos - MeadowTerrain.TOWN_CENTER


## Yaw that turns a node authored facing -Z (Godot forward) toward `to`. Local
## and world coordinates differ only by a translation, so either may be passed
## as long as both arguments agree.
func _yaw_to(from: Vector2, to: Vector2) -> float:
	var d: Vector2 = to - from
	if d.length_squared() < 0.0001:
		return 0.0
	return atan2(-d.x, -d.y)


## Yaw that points a fingerpost arm (authored along +X) at a world target.
func _arm_yaw(from: Vector2, to: Vector2) -> float:
	var d: Vector2 = to - from
	return atan2(-d.y, d.x)


func _place(node: Node3D, local: Vector2, yaw: float) -> void:
	var world_pos: Vector2 = _world(local)
	node.position = Vector3(world_pos.x, _terrain.get_height(world_pos.x, world_pos.y),
		world_pos.y)
	node.rotation.y = yaw


func _add_prop(node: Node3D, local: Vector2, yaw: float) -> void:
	add_child(node)
	_place(node, local, yaw)

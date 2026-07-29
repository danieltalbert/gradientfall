class_name MonsterSpawner
extends Node3D
## Populates the field with region-appropriate approved monsters (data-driven
## from ContentDB) and stands up a small COMBAT PROVING GROUND near Kern's
## start so every Combat-v1 behavior is exercisable the moment you boot.
##
## Why a proving ground: only one meadow monster is approved so far (the swarm
## Stray Glitchling); the melee and ranged brains have nothing canon to wear
## yet. Rather than invent canon (that's ChatGPT's briefed job — batch_04), the
## arena uses clearly non-content sparring rigs (monster_id ""): a straw dummy,
## one melee sparring construct, one ranged sparring construct. As batch_04's
## real monsters land in approved/, the FIELD spawner picks them up automatically
## and the arena can be retired. Set DEBUG_PROVING_GROUND=false to disable it.

const DEBUG_PROVING_GROUND: bool = true

const FIELD_CAP: int = 5
const SPAWN_BAND_MIN: float = 13.0
const SPAWN_BAND_MAX: float = 26.0
const RESPAWN_INTERVAL: float = 4.0
const MAP_HALF: float = 228.0
const TOWN_SAFE_RADIUS: float = 42.0

var enabled: bool = true

var _terrain: Node
var _field_root: Node3D
var _arena_root: Node3D
var _tick_left: float = 2.0
var _region_monsters: Array[Dictionary] = []
var _arena_slots: Array[Dictionary] = []  ## { cfg, pos, node }


func setup(terrain: Node, player_spawn: Vector3) -> void:
	_terrain = terrain
	_field_root = Node3D.new()
	_field_root.name = "FieldEnemies"
	add_child(_field_root)
	_arena_root = Node3D.new()
	_arena_root.name = "ProvingGround"
	add_child(_arena_root)
	_collect_region_monsters()
	if DEBUG_PROVING_GROUND:
		_setup_proving_ground(player_spawn)
	print("MonsterSpawner: %d approved monster type(s) for region '%s'; proving ground %s." % [
		_region_monsters.size(), GameState.current_region,
		"on" if DEBUG_PROVING_GROUND else "off",
	])


func _collect_region_monsters() -> void:
	_region_monsters.clear()
	var region: String = GameState.current_region
	for m: Dictionary in ContentDB.get_all("monsters"):
		var regions: Array = m.get("regions", [])
		var tier: String = str(m.get("tier", "fodder"))
		if tier in ["world_boss", "dungeon_boss"]:
			continue  # bosses are placed by hand, never field-spawned
		if regions.has(region):
			_region_monsters.append(m)


func _process(delta: float) -> void:
	if not enabled:
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = RESPAWN_INTERVAL
	_refill_arena()
	_refill_field()


# --- Field spawns ------------------------------------------------------------

func _refill_field() -> void:
	if _region_monsters.is_empty():
		return
	var alive: int = _count_valid(_field_root)
	if alive >= FIELD_CAP:
		return
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	var spot: Vector3 = _find_spawn_spot(player.global_position)
	if spot == Vector3.INF:
		return
	var cfg: Dictionary = _region_monsters[randi() % _region_monsters.size()]
	Enemy.spawn(_field_root, cfg, spot)


func _find_spawn_spot(around: Vector3) -> Vector3:
	for attempt: int in 8:
		var ang: float = randf() * TAU
		var r: float = randf_range(SPAWN_BAND_MIN, SPAWN_BAND_MAX)
		var x: float = around.x + cos(ang) * r
		var z: float = around.z + sin(ang) * r
		if absf(x) > MAP_HALF or absf(z) > MAP_HALF:
			continue
		if _terrain.has_method("is_deep_water") and _terrain.is_deep_water(x, z):
			continue
		if Vector2(x, z).distance_to(MeadowTerrain.TOWN_CENTER) < TOWN_SAFE_RADIUS:
			continue
		var y: float = _terrain.get_height(x, z) if _terrain.has_method("get_height") else 0.0
		return Vector3(x, y + 0.2, z)
	return Vector3.INF


# --- Proving ground ----------------------------------------------------------

func _setup_proving_ground(player_spawn: Vector3) -> void:
	# A little clearing a few steps from where Kern wakes.
	var base: Vector3 = player_spawn + Vector3(9.0, 0.0, 9.0)
	_arena_slots = [
		{"cfg": _rig("Straw Sparring Dummy", "dummy", 6.0, 0.0),
			"pos": _ground(base + Vector3(-2.5, 0.0, 0.0)), "node": null},
		{"cfg": _rig("Melee Sparring Construct", "melee", 3.0, 0.5),
			"pos": _ground(base + Vector3(2.0, 0.0, 1.5)), "node": null},
		{"cfg": _rig("Ranged Sparring Construct", "ranged", 2.5, 0.5),
			"pos": _ground(base + Vector3(0.0, 0.0, 6.0)), "node": null},
	]
	_refill_arena()


func _refill_arena() -> void:
	for slot: Dictionary in _arena_slots:
		var node: Variant = slot["node"]
		if node == null or not is_instance_valid(node):
			slot["node"] = Enemy.spawn(_arena_root, slot["cfg"], slot["pos"])


func _rig(rig_name: String, behavior: String, hearts: float, atk: float) -> Dictionary:
	# monster_id "" marks these as non-content sparring rigs, not canon monsters.
	return {
		"id": "", "name": rig_name, "behavior": behavior, "tier": "standard",
		"hearts": hearts, "attack": atk, "regions": [GameState.current_region],
		"drops": [], "variants": [], "variant": "",
	}


func _ground(p: Vector3) -> Vector3:
	var y: float = _terrain.get_height(p.x, p.z) if _terrain != null and _terrain.has_method("get_height") else 0.0
	return Vector3(p.x, y + 0.2, p.z)


func _count_valid(root: Node3D) -> int:
	var n: int = 0
	for c: Node in root.get_children():
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			n += 1
	return n

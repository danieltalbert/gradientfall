class_name MeadowForage
extends Node3D
## Scatters findable items across Datasedge Meadows so the pack has something to
## hold the moment you start walking — the inventory milestone's supply side.
##
## Everything is data-driven: the forage table is every approved ContentDB item
## whose `found_in` includes the current region, weighted so common things turn
## up constantly and a Boundary Bloom almost never does. Crafted goods carry no
## `found_in` (that is the reviewed convention — you brew a cordial, you don't
## find one in the grass), so they never spawn here.
##
## Placement reads the item's CATEGORY, never its id: flora likes open meadow,
## materials like shorelines and worn slopes, curios and tools turn up around
## the named landmarks. Slots are laid out from a fixed seed, so the meadow's
## good picking spots are the same every session and worth remembering; a
## collected slot regrows after a while with a fresh roll.
##
## GDD §10 visible surface: UNSEEN until a live Godot session lays eyes on it.

const SLOT_COUNT: int = 140
const MAP_HALF: float = 205.0        # inside the 480 m terrain, clear of the vistas
const TOWN_CLEAR: float = 34.0       # leave Bootstrap's site to the town builder
const REGROW_MIN: float = 75.0
const REGROW_MAX: float = 150.0
const PLACE_ATTEMPTS: int = 14
const SLOPE_WORN: float = 0.955      # normal.y below this reads as worn ground
const SHORE_INNER: float = 0.95      # × pond radius — just past the deep water
const SHORE_OUTER: float = 1.4
const LANDMARK_MIN: float = 5.0
const LANDMARK_MAX: float = 17.0
const LANDMARK_MAX_RANGE: float = 190.0  # skip the distant border-vista markers
const GROUND_OFFSET: float = 0.12
const SEED_OFFSET: int = 977

## Placed deliberately by quests, vendors, and dungeons — never foraged.
const SKIP_CATEGORIES: Array[String] = ["weapon", "armor", "key_item", "furniture"]

## Rarity → relative chance of being what a given slot grows.
const RARITY_WEIGHT: Dictionary = {
	"common": 1.0, "uncommon": 0.32, "rare": 0.05, "epic": 0.015, "golden": 0.01,
}

var _terrain: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _table: Array[Dictionary] = []
var _weights: Array[float] = []
var _weight_total: float = 0.0
var _landmarks: Array[Vector3] = []
## { pos: Vector3, node: ItemPickup, regrow: float }
var _slots: Array[Dictionary] = []


func setup(terrain: Node) -> void:
	_terrain = terrain
	_rng.seed = MeadowTerrain.WORLD_SEED + SEED_OFFSET
	_collect_table()
	if _table.is_empty():
		print("MeadowForage: no forageable items approved for region '%s' — nothing planted." % GameState.current_region)
		return
	_collect_landmarks()
	_build_slots()
	print("MeadowForage: %d forage spots planted from %d forageable item type(s) in '%s'." % [
		_slots.size(), _table.size(), GameState.current_region,
	])


func _process(delta: float) -> void:
	for slot: Dictionary in _slots:
		var node: Variant = slot["node"]
		if node != null and is_instance_valid(node):
			continue
		var left: float = float(slot["regrow"])
		if left <= 0.0:
			# Empty with no timer running: only reachable if a pickup vanished
			# without reporting in. Start the clock rather than pop one back.
			slot["node"] = null
			slot["regrow"] = _rng.randf_range(REGROW_MIN, REGROW_MAX)
			continue
		left -= delta
		slot["regrow"] = left
		if left <= 0.0:
			_grow(slot)


# --- Forage table ------------------------------------------------------------

func _collect_table() -> void:
	_table.clear()
	_weights.clear()
	_weight_total = 0.0
	var region: String = GameState.current_region
	for e: Dictionary in ContentDB.get_all("items"):
		var regions: Array = e.get("found_in", [])
		if not regions.has(region):
			continue
		if SKIP_CATEGORIES.has(ItemStyle.category_of(e)):
			continue
		var w: float = float(RARITY_WEIGHT.get(str(e.get("rarity", "common")), 0.05))
		_table.append(e)
		_weights.append(w)
		_weight_total += w


func _pick_entry() -> Dictionary:
	var roll: float = _rng.randf() * _weight_total
	for i: int in _table.size():
		roll -= _weights[i]
		if roll <= 0.0:
			return _table[i]
	return _table[_table.size() - 1]


func _collect_landmarks() -> void:
	_landmarks.clear()
	for node: Node in get_tree().get_nodes_in_group(&"bit_landmark"):
		var lm: Node3D = node as Node3D
		if lm == null:
			continue
		var p: Vector3 = lm.global_position
		if absf(p.x) > LANDMARK_MAX_RANGE or absf(p.z) > LANDMARK_MAX_RANGE:
			continue  # the Peaks and Forest markers live out past the map edge
		_landmarks.append(p)


# --- Slots -------------------------------------------------------------------

func _build_slots() -> void:
	_slots.clear()
	for i: int in SLOT_COUNT:
		var entry: Dictionary = _pick_entry()
		var spot: Vector3 = _find_spot(ItemStyle.category_of(entry))
		if spot == Vector3.INF:
			continue
		var slot: Dictionary = {"pos": spot, "node": null, "regrow": 0.0}
		_slots.append(slot)
		_plant(slot, entry)


## Regrowth re-rolls the item, so a picked spot is worth walking back to.
func _grow(slot: Dictionary) -> void:
	_plant(slot, _pick_entry())


func _plant(slot: Dictionary, entry: Dictionary) -> void:
	var pickup: ItemPickup = ItemPickup.spawn(self, entry, slot["pos"])
	pickup.collected.connect(_on_collected.bind(slot))
	slot["node"] = pickup
	slot["regrow"] = 0.0


func _on_collected(_pickup: ItemPickup, slot: Dictionary) -> void:
	slot["node"] = null
	slot["regrow"] = _rng.randf_range(REGROW_MIN, REGROW_MAX)


## Rejection-samples a spot whose ground suits the category, falling back to
## plain open meadow so a slot is never lost to a fussy habitat rule.
func _find_spot(category: String) -> Vector3:
	for attempt: int in PLACE_ATTEMPTS:
		var p: Vector2 = _sample_point(category, attempt)
		if absf(p.x) > MAP_HALF or absf(p.y) > MAP_HALF:
			continue
		if _is_deep_water(p.x, p.y):
			continue
		if p.distance_to(MeadowTerrain.TOWN_CENTER) < TOWN_CLEAR:
			continue
		if not _habitat_ok(category, p, attempt):
			continue
		return Vector3(p.x, _height(p.x, p.y) + GROUND_OFFSET, p.y)
	return Vector3.INF


func _sample_point(category: String, attempt: int) -> Vector2:
	# The first attempts try the category's favourite ground; later ones widen
	# out to anywhere in the meadow rather than leaving the slot empty.
	if attempt < PLACE_ATTEMPTS / 2:
		match category:
			"curio", "tool":
				var anchor: Vector3 = _random_landmark()
				if anchor != Vector3.INF:
					var a: float = _rng.randf() * TAU
					var r: float = _rng.randf_range(LANDMARK_MIN, LANDMARK_MAX)
					return Vector2(anchor.x + cos(a) * r, anchor.z + sin(a) * r)
			"fish":
				return _shore_point()
			"material":
				if _rng.randf() < 0.4:
					return _shore_point()
	return Vector2(
		_rng.randf_range(-MAP_HALF, MAP_HALF), _rng.randf_range(-MAP_HALF, MAP_HALF)
	)


func _shore_point() -> Vector2:
	var a: float = _rng.randf() * TAU
	var r: float = MeadowTerrain.POND_RADIUS * _rng.randf_range(SHORE_INNER, SHORE_OUTER)
	return MeadowTerrain.POND_CENTER + Vector2(cos(a) * r, sin(a) * r)


func _habitat_ok(category: String, p: Vector2, attempt: int) -> bool:
	if attempt >= PLACE_ATTEMPTS / 2:
		return true  # widened search: any legal ground will do
	match category:
		"flora":
			# Growing things want gentle, open ground.
			return _normal_y(p.x, p.y) >= SLOPE_WORN
		"material":
			# Stone, clay, and grit collect where the ground is worn or wet.
			return _normal_y(p.x, p.y) < SLOPE_WORN or _near_shore(p)
	return true


func _random_landmark() -> Vector3:
	if _landmarks.is_empty():
		return Vector3.INF
	return _landmarks[_rng.randi() % _landmarks.size()]


func _near_shore(p: Vector2) -> bool:
	var d: float = p.distance_to(MeadowTerrain.POND_CENTER)
	return d < MeadowTerrain.POND_RADIUS * SHORE_OUTER


# --- Terrain access (kept tolerant so a stub terrain never crashes forage) ----

func _height(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("get_height"):
		return float(_terrain.get_height(x, z))
	return 0.0


func _normal_y(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("get_normal"):
		return float((_terrain.get_normal(x, z) as Vector3).y)
	return 1.0


func _is_deep_water(x: float, z: float) -> bool:
	if _terrain != null and _terrain.has_method("is_deep_water"):
		return bool(_terrain.is_deep_water(x, z))
	return false

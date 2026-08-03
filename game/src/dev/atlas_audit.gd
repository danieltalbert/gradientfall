extends SceneTree
## Headless self-audit for `WorldAtlas` — the continent's geometry, checked.
##
## A map is a pile of numbers that are all individually plausible and can still
## put a harbour town in open water (this audit caught exactly that on its first
## run). Everything asserted here is something a human would only notice by
## staring at a drawing, so it gets checked by machine instead, every time.
##
## Run:
##   godot --headless --script res://src/dev/atlas_audit.gd
##
## Exit code is 0 when every check passes and 1 otherwise, so this can gate a
## commit. Dev tool only; never part of the shipped game.

## Sites that are MEANT to be in open water. Anything else failing the land test
## is a bug, not a design choice — the point of naming these is that the list is
## short enough to be argued with.
const EXPECTED_AT_SEA: Array[StringName] = [
	&"kernel_reef",       # a reef; the dungeon is submerged by design
	&"the_unsinkable",    # a ghost ship, offshore
	&"window_flats",      # tide-walk: water most of the time, floor for a window
	&"shrine_tide",       # a tidal rock, revealed by the sliding tide
	&"isle_longstride", &"isle_halfstride", &"isle_padding",
]

## How close a "reaches_sea" river's mouth must be to the coastline, in km. A
## river that stops 3 km short of the water is a river that does not reach it.
const MOUTH_TOLERANCE_KM: float = 0.6

## Round-trip tolerance for the km<->metre bridge, in metres.
##
## Godot's Vector2 is float32, so converting 1.5 km to kilometres and back loses
## about 3 mm. That is not a bug to chase — it is 3 mm across a hundred-kilometre
## continent. The tolerance is set at 5 cm, which still catches any real error
## (a wrong sign, a missing scale factor, a swapped axis) by three orders of
## magnitude while ignoring the noise floor of the type.
const BRIDGE_TOLERANCE_M: float = 0.05

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	print("=== WorldAtlas audit ===")
	_audit_coordinate_bridge()
	_audit_site_ids()
	_audit_land_and_sea()
	_audit_region_cores()
	_audit_rivers()
	_audit_roads()
	_audit_shrines()
	_audit_safe_water()
	print("---")
	if _failures == 0:
		print("PASS: %d checks, 0 failures." % _checks)
	else:
		printerr("FAIL: %d checks, %d failure(s)." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("  FAIL  %s%s" % [label, ("  --  " + detail) if detail != "" else ""])


## The km<->metre bridge must round-trip exactly, in both directions, for every
## region. The `-z` north flip is the part that silently breaks.
func _audit_coordinate_bridge() -> void:
	print("- coordinate bridge")
	for region_id in WorldAtlas.REGIONS:
		for probe in [Vector2(0.0, 0.0), Vector2(240.0, -240.0), Vector2(-1500.0, 620.0)]:
			var km: Vector2 = WorldAtlas.local_to_km(region_id, probe.x, probe.y)
			var back: Vector2 = WorldAtlas.km_to_local(region_id, km)
			_check(back.distance_to(probe) < BRIDGE_TOLERANCE_M,
				"round-trip %s at (%.0f, %.0f)" % [region_id, probe.x, probe.y],
				"came back (%.3f, %.3f)" % [back.x, back.y])
		# North must increase atlas y. This is the flip that bites.
		var here: Vector2 = WorldAtlas.local_to_km(region_id, 0.0, 0.0)
		var north: Vector2 = WorldAtlas.local_to_km(region_id, 0.0, -1000.0)
		_check(north.y > here.y, "north increases atlas y in %s" % region_id,
			"1 km north gave y %.3f from %.3f" % [north.y, here.y])
		var east: Vector2 = WorldAtlas.local_to_km(region_id, 1000.0, 0.0)
		_check(east.x > here.x, "east increases atlas x in %s" % region_id)


## Duplicate ids silently shadow each other in every lookup that follows.
func _audit_site_ids() -> void:
	print("- site ids")
	var seen: Dictionary = {}
	for site in WorldAtlas.SITES:
		var id: StringName = site["id"]
		_check(not seen.has(id), "site id '%s' is unique" % id)
		seen[id] = true
		_check(WorldAtlas.REGIONS.has(site["region"]),
			"site '%s' names a real region" % id, String(site["region"]))


## Towns need ground under them; reefs and ghost ships do not.
func _audit_land_and_sea() -> void:
	print("- land and sea")
	for site in WorldAtlas.SITES:
		var id: StringName = site["id"]
		var on_land: bool = WorldAtlas.is_on_land(site["km"])
		var want_sea: bool = EXPECTED_AT_SEA.has(id)
		if want_sea:
			_check(not on_land, "'%s' is at sea as intended" % id,
				"but it is on land at (%.2f, %.2f)" % [site["km"].x, site["km"].y])
		else:
			_check(on_land, "'%s' has land under it" % id,
				"it is in open water at (%.2f, %.2f)" % [site["km"].x, site["km"].y])


## Region cores. Convolution Coast is the deliberate exception: its core centre
## sits offshore because the region IS the water.
func _audit_region_cores() -> void:
	print("- region cores")
	for region_id in WorldAtlas.REGIONS:
		var core: Vector2 = WorldAtlas.REGIONS[region_id]["core_km"]
		var on_land: bool = WorldAtlas.is_on_land(core)
		if region_id == &"convolution_coast":
			_check(not on_land, "convolution_coast core is offshore by design")
		else:
			_check(on_land, "%s core is on land" % region_id,
				"(%.1f, %.1f) is in the sea" % [core.x, core.y])
		# A core must sit inside the 0-100 atlas square with its radius intact.
		var r: float = float(WorldAtlas.REGIONS[region_id]["core_size_km"]) * 0.5
		_check(core.x - r > 0.0 and core.x + r < WorldAtlas.WORLD_SPAN_KM
				and core.y - r > 0.0 and core.y + r < WorldAtlas.WORLD_SPAN_KM,
			"%s core fits inside the atlas square" % region_id)


## A river that claims the sea has to actually get there; one that does not must
## actually stop inland. Both directions are design facts worth protecting.
func _audit_rivers() -> void:
	print("- rivers")
	for river in WorldAtlas.RIVERS:
		var points: Array = river["points"]
		_check(points.size() >= 2, "%s has a course" % river["name"])
		var mouth: Vector2 = points[points.size() - 1]
		var d: float = _distance_to_coast(mouth)
		if bool(river.get("frozen", false)):
			# A frozen river neither arrives nor dies; it is simply stopped.
			_check(true, "%s is frozen in place" % river["name"])
		elif bool(river["reaches_sea"]):
			_check(d <= MOUTH_TOLERANCE_KM, "%s reaches the sea" % river["name"],
				"mouth is %.2f km from the coastline" % d)
		else:
			_check(d > 2.0, "%s dies inland as designed" % river["name"],
				"but its end is only %.2f km from the coast" % d)
		# The Emberflow is the one that must run UPHILL - it is error-flame, not
		# water (WORLDBOOK section 7). Everything else is checked for sanity by
		# the land test above; elevation profiles arrive with the terrain.
		if river["id"] == &"the_emberflow":
			_check(points[points.size() - 1].y > points[0].y,
				"the Emberflow runs backward, toward the Forge")


## Roads must start and finish near something worth walking to.
func _audit_roads() -> void:
	print("- roads")
	for road in WorldAtlas.ROADS:
		var points: Array = road["points"]
		_check(points.size() >= 2, "%s has a course" % road["name"])
		for end_point in [points[0], points[points.size() - 1]]:
			var near: Dictionary = WorldAtlas.nearest_site(end_point, 1.5)
			_check(not near.is_empty(),
				"%s ends at a named place" % road["name"],
				"loose end at (%.2f, %.2f)" % [end_point.x, end_point.y])


## Nine shrines, nine regions, and Overfit Swamp deliberately without one.
func _audit_shrines() -> void:
	print("- memory shrines")
	var shrines: Array = WorldAtlas.sites_of_kind(&"shrine")
	_check(shrines.size() == 9, "there are nine Memory Shrines",
		"found %d" % shrines.size())
	var regions_with: Dictionary = {}
	for shrine in shrines:
		var region_id: StringName = shrine["region"]
		_check(not regions_with.has(region_id),
			"only one shrine in %s" % region_id)
		regions_with[region_id] = true
	_check(not regions_with.has(&"overfit_swamp"),
		"Overfit Swamp has no shrine (WORLDBOOK: nine shrines, ten regions)")


## Safe water has to be water, or the swim rule is protecting a field.
func _audit_safe_water() -> void:
	print("- safe water")
	for zone in WorldAtlas.SAFE_WATER:
		var centre: Vector2 = zone["centre"]
		# The millpond and the city canal are inland water by definition, so
		# they sit on "land" as far as the coastline polygon is concerned.
		if zone["id"] == &"old_millpond" or zone["id"] == &"city_canal":
			_check(WorldAtlas.is_on_land(centre),
				"%s is inland water" % zone["name"])
			continue
		_check(not WorldAtlas.is_on_land(centre),
			"%s is actually water" % zone["name"],
			"(%.2f, %.2f) is on land" % [centre.x, centre.y])
	# The Deep must be survivable for a real push and fatal for a crossing.
	var seconds_to_empty: float = 3.0 / WorldAtlas.DEEP_DRAIN_PER_SEC
	_check(seconds_to_empty > 25.0 and seconds_to_empty < 60.0,
		"the Deep drains a 3-heart Kern in 25-60 s",
		"currently %.0f s" % seconds_to_empty)


## Shortest distance from a point to the coastline polygon, in km.
func _distance_to_coast(km: Vector2) -> float:
	var best: float = INF
	var count: int = WorldAtlas.COASTLINE_KM.size()
	for i in count:
		var a: Vector2 = WorldAtlas.COASTLINE_KM[i]
		var b: Vector2 = WorldAtlas.COASTLINE_KM[(i + 1) % count]
		best = minf(best, _point_to_segment(km, a, b))
	return best


func _point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

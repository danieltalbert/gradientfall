class_name WorldMapUi
extends CanvasLayer
## The map Kern carries — the whole continent of Aligned, opened with M.
##
## Everything drawn here comes from `WorldAtlas`, which is also what the
## minimap, the swim rule and every future terrain stamper read. There is no
## second copy of the world's geometry: if the map is wrong, the world is wrong
## in exactly the same way, which is the only arrangement that stays honest
## across a hundred sessions.
##
## Where it sits: instanced by `main.gd` during normal play only (screenshot
## mode leaves UI out). No scene file and no textures — a full-rect Control
## painting in its `draw` callback, the same shape as `CombatHud` and
## `CompendiumUi`. Toggled with the `world_map` action; Escape closes.
##
## Regions Kern has not reached yet are drawn faint. That is not fog of war —
## the coastline and every region name are legible from the first minute,
## because GDD §2 says go anywhere from hour one and a map that hides the world
## argues with the pillar. What the dimming marks is simply where he has been.
##
## Sizes are pixels at the viewport's scale.

## Panel inset from the screen edge, and the panel's internal padding.
const MARGIN: float = 40.0
const PAD: float = 24.0
## Room reserved under the plate for the footer readout.
const FOOTER_H: float = 58.0

const BACKDROP: Color = Color(0.04, 0.05, 0.06, 0.86)
const PARCHMENT: Color = Color(0.855, 0.836, 0.744)
const PARCHMENT_EDGE: Color = Color(0.30, 0.28, 0.22)
const SEA: Color = Color(0.506, 0.616, 0.647)
const SHELF: Color = Color(0.616, 0.714, 0.729)
const LAND: Color = Color(0.879, 0.867, 0.769)
const INK: Color = Color(0.129, 0.157, 0.153)
const INK_DIM: Color = Color(0.404, 0.435, 0.416)
const OXIDE: Color = Color(0.639, 0.278, 0.184)
const TEAL: Color = Color(0.192, 0.412, 0.451)
const CORRUPT: Color = Color(0.451, 0.376, 0.573)
const KERN: Color = Color(0.851, 0.302, 0.161)

## Tier colours, indexed 1-5. Index 0 is unused and holds a visible error
## magenta, so a tier that falls out of range shows itself instead of hiding.
const TIER_COLORS: Array[Color] = [
	Color(1.0, 0.0, 1.0),
	Color(0.294, 0.475, 0.247), Color(0.184, 0.478, 0.439),
	Color(0.690, 0.541, 0.173), Color(0.749, 0.416, 0.149),
	Color(0.659, 0.235, 0.184),
]

## True while the map is open; also gates the redraw.
var is_open: bool = false

var _player: Node3D
var _control: Control
var _font: Font
## Cached plate transform, recomputed on each open: km -> panel pixels.
var _origin: Vector2 = Vector2.ZERO
var _scale: float = 1.0


## Create the map and bind it to the player whose pin it draws.
static func build(host: Node, player: Node3D) -> WorldMapUi:
	var ui: WorldMapUi = WorldMapUi.new()
	ui.name = "WorldMapUi"
	ui._player = player
	host.add_child(ui)
	return ui


func _ready() -> void:
	# Above the combat HUD (10) and alongside the compendium (20) — only one of
	# the full-screen readers can be open at a time in practice, and neither
	# should ever be drawn over.
	layer = 20
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Same reason as CombatHud: the camera rig needs clicks to recapture the
	# cursor, and the map is keyboard-driven.
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)
	_control.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"world_map"):
		set_open(not is_open)
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.is_pressed() \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()


## Open or close the map. Repainting once per open is enough — Kern cannot move
## while he is reading it.
func set_open(open: bool) -> void:
	if open == is_open:
		return
	is_open = open
	_control.visible = open
	if open:
		_mark_region_seen()
		_control.queue_redraw()


## Kern's position in atlas kilometres. Everything he can currently stand on is
## in Datasedge's local frame; when streaming lands, this becomes a lookup of
## whichever region frame he is in.
func _kern_km() -> Vector2:
	if _player == null:
		return WorldAtlas.core_of(&"datasedge_meadows")
	var p: Vector3 = _player.global_position
	return WorldAtlas.local_to_km(&"datasedge_meadows", p.x, p.z)


## Record that Kern has been here, so the region stops drawing faint. One flag
## per region in GameState.flags — no save-shape change, no SAVE_VERSION bump.
func _mark_region_seen() -> void:
	GameState.set_flag("region_seen_" + String(WorldAtlas.region_at(_kern_km())))


func _seen(region_id: StringName) -> bool:
	return GameState.has_flag("region_seen_" + String(region_id))


# --- Projection --------------------------------------------------------------

## Atlas km to panel pixels. Set up once per repaint by `_fit()`.
func _at(km: Vector2) -> Vector2:
	return Vector2(_origin.x + km.x * _scale, _origin.y - km.y * _scale)


## The 0-100 km square in panel pixels. Everything chart-like is bounded by it.
func _square() -> Rect2:
	var side: float = WorldAtlas.WORLD_SPAN_KM * _scale
	return Rect2(_at(Vector2(0.0, WorldAtlas.WORLD_SPAN_KM)), Vector2(side, side))


## Fit the 100 x 100 km square inside `plate`, preserving the aspect so the
## continent is never stretched, and centre it in whichever axis has slack.
func _fit(plate: Rect2) -> void:
	_scale = minf(plate.size.x, plate.size.y) / WorldAtlas.WORLD_SPAN_KM
	var used: float = WorldAtlas.WORLD_SPAN_KM * _scale
	_origin = Vector2(
		plate.position.x + (plate.size.x - used) * 0.5,
		plate.position.y + (plate.size.y - used) * 0.5 + used,
	)


# --- Drawing -----------------------------------------------------------------

func _render() -> void:
	var size: Vector2 = _control.size
	var panel: Rect2 = Rect2(MARGIN, MARGIN, size.x - MARGIN * 2.0, size.y - MARGIN * 2.0)
	_control.draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	_control.draw_rect(panel, PARCHMENT)
	_control.draw_rect(panel, PARCHMENT_EDGE, false, 2.0)

	var plate: Rect2 = Rect2(
		panel.position + Vector2(PAD, PAD + 30.0),
		panel.size - Vector2(PAD * 2.0, PAD * 2.0 + 30.0 + FOOTER_H),
	)
	_fit(plate)

	_draw_sea()
	_draw_land()
	_draw_biomes()
	_draw_coast_line()
	_draw_rivers()
	_draw_roads()
	_draw_sites()
	_draw_region_names()
	_draw_kern()
	_draw_furniture(panel, plate)


func _draw_sea() -> void:
	# The sea fills the ATLAS SQUARE, not the whole plate. Filling the plate let
	# the water and its graticule run out past the neatline, which made the
	# chart look like a picture of a chart rather than one.
	_control.draw_rect(_square(), SEA)
	var step: float = 10.0
	var k: float = 0.0
	while k <= WorldAtlas.WORLD_SPAN_KM:
		var vertical_a: Vector2 = _at(Vector2(k, 0.0))
		var vertical_b: Vector2 = _at(Vector2(k, WorldAtlas.WORLD_SPAN_KM))
		var horizontal_a: Vector2 = _at(Vector2(0.0, k))
		var horizontal_b: Vector2 = _at(Vector2(WorldAtlas.WORLD_SPAN_KM, k))
		_control.draw_line(vertical_a, vertical_b, Color(SEA.darkened(0.18), 0.5), 1.0)
		_control.draw_line(horizontal_a, horizontal_b, Color(SEA.darkened(0.18), 0.5), 1.0)
		k += step


func _draw_land() -> void:
	var poly: PackedVector2Array = PackedVector2Array()
	for km in WorldAtlas.COASTLINE_KM:
		poly.append(_at(km))
	# Shallow-water shelf: the coast stroked fat, under the land fill, so only
	# its seaward half survives. The same trick the paper chart uses.
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	_control.draw_polyline(closed, SHELF, 7.0, true)
	_control.draw_colored_polygon(poly, LAND)


## Regional colour, so the interior is not a blank sheet between the cores.
##
## Godot's immediate-mode draw has no blur and no polygon clip, so each wash is
## a stack of concentric discs with rising alpha — a radial gradient built by
## hand. Cores sit far enough inland that the spill into the sea is small, and
## `_draw_coast_line()` runs afterwards to put a crisp edge back over it.
func _draw_biomes() -> void:
	const RINGS: int = 7
	for region_id: StringName in WorldAtlas.REGIONS:
		var region: Dictionary = WorldAtlas.REGIONS[region_id]
		var tint: Color = TIER_COLORS[clampi(int(region["tier"]), 1, 5)]
		var span_km: float = clampf(float(region["core_size_km"]), 6.0, 18.0) * 0.55
		var here: Vector2 = _at(region["core_km"])
		var faint: float = 0.10 if _seen(region_id) else 0.05
		for ring in RINGS:
			var t: float = 1.0 - float(ring) / float(RINGS)
			_control.draw_circle(here, span_km * t * _scale, Color(tint, faint))


func _draw_coast_line() -> void:
	var closed: PackedVector2Array = PackedVector2Array()
	for km in WorldAtlas.COASTLINE_KM:
		closed.append(_at(km))
	closed.append(closed[0])
	_control.draw_polyline(closed, Color(INK, 0.85), 2.0, true)


func _draw_rivers() -> void:
	for river in WorldAtlas.RIVERS:
		var pts: PackedVector2Array = PackedVector2Array()
		for km in river["points"]:
			pts.append(_at(km))
		if pts.size() < 2:
			continue
		var frozen: bool = bool(river.get("frozen", false))
		var fire: bool = river["id"] == &"the_emberflow"
		var tint: Color = OXIDE if fire else (Color(TEAL, 0.55) if frozen else TEAL)
		# Rivers widen downstream: draw the course in three overlapping passes,
		# each starting later and stroked thicker, so the head is a thread.
		for pass_index in 3:
			var from: int = int(float(pts.size()) * float(pass_index) / 3.0)
			var seg: PackedVector2Array = pts.slice(maxi(0, from - 1))
			if seg.size() < 2:
				continue
			_control.draw_polyline(seg, tint, 1.0 + float(pass_index) * 0.9, true)


func _draw_roads() -> void:
	for road in WorldAtlas.ROADS:
		var pts: PackedVector2Array = PackedVector2Array()
		for km in road["points"]:
			pts.append(_at(km))
		if pts.size() < 2:
			continue
		var spine: bool = road["id"] == &"great_east_road"
		# The Old Boundary Line is a road that stopped being a road, so it is
		# drawn as the ghost of one rather than as a route you can follow.
		var ghost: bool = road["id"] == &"old_boundary_line"
		_control.draw_polyline(pts, Color(INK, 0.28 if ghost else 0.6),
				2.4 if spine else 1.5, true)


func _draw_sites() -> void:
	for site in WorldAtlas.SITES:
		var here: Vector2 = _at(site["km"])
		var faded: bool = not _seen(site["region"])
		_draw_symbol(site["kind"], here, faded)


## One site's mark. Symbol carries the kind, so the plate reads without the
## legend: a ringed dot is a town, a lozenge a dungeon, a hollow triangle a
## world boss, a filled one a surveyed height, a star a Memory Shrine.
func _draw_symbol(kind: StringName, at: Vector2, faded: bool) -> void:
	var a: float = 0.34 if faded else 1.0
	match kind:
		&"town", &"hamlet":
			_control.draw_circle(at, 4.4, Color(LAND, a))
			_control.draw_arc(at, 4.4, 0.0, TAU, 18, Color(INK, a), 1.7)
			_control.draw_circle(at, 1.5, Color(INK, a))
		&"dungeon":
			_control.draw_colored_polygon(PackedVector2Array([
				at + Vector2(0.0, -5.0), at + Vector2(4.4, 0.0),
				at + Vector2(0.0, 5.0), at + Vector2(-4.4, 0.0),
			]), Color(INK, a))
		&"shrine":
			_control.draw_colored_polygon(PackedVector2Array([
				at + Vector2(0.0, -5.6), at + Vector2(1.6, -1.6),
				at + Vector2(5.6, 0.0), at + Vector2(1.6, 1.6),
				at + Vector2(0.0, 5.6), at + Vector2(-1.6, 1.6),
				at + Vector2(-5.6, 0.0), at + Vector2(-1.6, -1.6),
			]), Color(OXIDE, a))
		&"world_boss":
			var tri: PackedVector2Array = PackedVector2Array([
				at + Vector2(0.0, -5.2), at + Vector2(4.5, 2.6),
				at + Vector2(-4.5, 2.6), at + Vector2(0.0, -5.2),
			])
			_control.draw_polyline(tri, Color(TIER_COLORS[5], a), 1.8, true)
		&"landmark", &"pass":
			_control.draw_colored_polygon(PackedVector2Array([
				at + Vector2(0.0, -5.4), at + Vector2(4.6, 2.7),
				at + Vector2(-4.6, 2.7),
			]), Color(INK, a))
		&"island":
			_control.draw_circle(at, 3.2, Color(LAND, a))
			_control.draw_arc(at, 3.2, 0.0, TAU, 14, Color(INK, a), 1.2)
		&"gate":
			_control.draw_arc(at, 4.6, PI, TAU, 16, Color(CORRUPT, a), 2.4)
		&"zone":
			_control.draw_arc(at, 5.2, 0.0, TAU, 20, Color(CORRUPT, a * 0.8), 1.3)
		&"water":
			_control.draw_circle(at, 2.6, Color(TEAL, a))
		&"district":
			_control.draw_rect(Rect2(at - Vector2(3.0, 3.0), Vector2(6.0, 6.0)),
					Color(INK, a), false, 1.4)
		_:
			_control.draw_circle(at, 2.2, Color(INK_DIM, a))


func _draw_region_names() -> void:
	for region_id: StringName in WorldAtlas.REGIONS:
		var region: Dictionary = WorldAtlas.REGIONS[region_id]
		var here: Vector2 = _at(region["core_km"])
		var seen: bool = _seen(region_id)
		var label: String = String(region["name"]).to_upper()
		var tier: int = int(region["tier"])
		var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 15).x
		# The name sits above the core, centred, clear of the site symbols.
		var at: Vector2 = here + Vector2(-width * 0.5, -22.0)
		_control.draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(INK, 1.0 if seen else 0.4))
		_control.draw_rect(Rect2(at + Vector2(0.0, 4.0), Vector2(width, 2.0)),
				Color(TIER_COLORS[clampi(tier, 1, 5)], 0.85 if seen else 0.35))


func _draw_kern() -> void:
	var here: Vector2 = _at(_kern_km())
	# A ring rather than a dot: at continental scale Kern's whole meadow is
	# smaller than the mark, and a ring says "somewhere in here" honestly.
	_control.draw_arc(here, 11.0, 0.0, TAU, 28, Color(KERN, 0.55), 2.0)
	_control.draw_circle(here, 3.4, KERN)


## Neatline, title, scale bar, legend and the footer readout.
func _draw_furniture(panel: Rect2, plate: Rect2) -> void:
	var square: Rect2 = _square()
	_control.draw_rect(square, Color(INK, 0.9), false, 1.6)

	_control.draw_string(_font, panel.position + Vector2(PAD, PAD + 8.0),
			"THE CONTINENT OF ALIGNED", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	_control.draw_string(_font, panel.position + Vector2(PAD + 330.0, PAD + 8.0),
			"100 x 100 km  ·  N up  ·  M closes", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			INK_DIM)

	# Scale bar: 20 km, with the number that actually matters underneath.
	var bar_left: Vector2 = Vector2(square.position.x + 14.0,
			square.position.y + square.size.y - 18.0)
	var bar: float = 20.0 * _scale
	_control.draw_line(bar_left, bar_left + Vector2(bar, 0.0), INK, 2.0)
	for i in 3:
		var tick: Vector2 = bar_left + Vector2(bar * float(i) * 0.5, 0.0)
		_control.draw_line(tick + Vector2(0.0, -4.0), tick + Vector2(0.0, 4.0), INK, 1.5)
	_control.draw_string(_font, bar_left + Vector2(0.0, -8.0),
			"20 km  ·  about 45 min on foot", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK_DIM)

	# Footer: where Kern is, in both grids, plus the nearest named place. The
	# metre reading is the one a builder wants; the km reading is the one a
	# player wants.
	var km: Vector2 = _kern_km()
	var local: Vector2 = WorldAtlas.km_to_local(&"datasedge_meadows", km)
	var region: StringName = WorldAtlas.region_at(km)
	var region_name: String = String(WorldAtlas.REGIONS[region]["name"]) \
			if WorldAtlas.REGIONS.has(region) else "the wilds"
	var foot: Vector2 = Vector2(panel.position.x + PAD,
			panel.position.y + panel.size.y - PAD - 22.0)
	_control.draw_string(_font, foot,
			"KERN  ·  %s  ·  %.2f, %.2f km  ·  local %.0f, %.0f m"
					% [region_name, km.x, km.y, local.x, local.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)

	var near: Dictionary = WorldAtlas.nearest_site(km, 6.0)
	var note: String = "out in the wilds"
	if not near.is_empty():
		note = "nearest: %s, %.0f m" % [near["site"]["name"], float(near["km"]) * 1000.0]
	_control.draw_string(_font, foot + Vector2(0.0, 20.0), note,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK_DIM)

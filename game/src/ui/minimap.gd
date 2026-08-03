class_name Minimap
extends CanvasLayer
## Top-right minimap — **PLACEHOLDER v1.**
##
## ============================================================================
## THIS IS DELIBERATELY BASIC AND IS MEANT TO BE REPLACED.
## Danny asked for "something basic quickly so that I know to go back to it and
## improve it later" (2026-08-03). This is that. What it does NOT have, and
## what a real one wants:
##   * no terrain under it — it is a plain disc, not a picture of the ground
##   * no rotation mode (north-up only; many games offer heading-up)
##   * no zoom control, no edge arrows for off-window markers
##   * no quest or objective pins, because the quest system does not exist yet
##   * no fog of war and no discovery state beyond the region flag
##   * redraws every frame, which is fine at this size and would not be at a
##     real one
## Everything it draws comes from `WorldAtlas`, so improving it is a drawing
## job, not a data job.
## ============================================================================
##
## Where it sits: instanced by `main.gd` during normal play only (screenshot
## mode leaves UI out). No scene file, no textures — a Control painting in its
## `draw` callback, the same shape as `CombatHud`.
##
## Sizes are pixels at the viewport's scale.

## Disc radius and its inset from the top-right corner.
const RADIUS: float = 84.0
const INSET: Vector2 = Vector2(26.0, 26.0)
## How much world the disc covers, edge to centre.
##
## Tuned by looking: the first pass used 340 m, which is wider than the ENTIRE
## built meadow (480 m across), so every landmark in Datasedge piled into a knot
## at the middle and the disc told the player nothing. 120 m is about sixteen
## seconds at a sprint — near enough to be "my surroundings", far enough to see
## the next thing coming.
const RANGE_M: float = 120.0
## Sites are held in atlas km; this is RANGE_M expressed there, plus a margin so
## a marker slides in smoothly rather than appearing on the rim.
const RANGE_KM: float = 0.18

## The disc is nearly opaque on purpose: at 0.72 the meadow showed through and
## the markers had to compete with waving grass for legibility.
const DISC: Color = Color(0.106, 0.129, 0.125, 0.88)
const DISC_EDGE: Color = Color(0.855, 0.836, 0.744, 0.65)
const INK: Color = Color(0.898, 0.886, 0.804)
const INK_DIM: Color = Color(0.639, 0.647, 0.600)
const OXIDE: Color = Color(0.831, 0.408, 0.286)
const TEAL: Color = Color(0.373, 0.639, 0.678)
const KERN: Color = Color(0.949, 0.514, 0.298)
const NORTH: Color = Color(0.851, 0.302, 0.161)

var _player: Node3D
var _control: Control
var _font: Font


## Create the minimap and bind it to the player it follows.
static func build(host: Node, player: Node3D) -> Minimap:
	var ui: Minimap = Minimap.new()
	ui.name = "Minimap"
	ui._player = player
	host.add_child(ui)
	return ui


func _ready() -> void:
	# Below the full-screen readers (20) and above the world, alongside the
	# combat HUD — the map screen must cover this when it opens.
	layer = 10
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)


func _process(_delta: float) -> void:
	# PLACEHOLDER: a real minimap would redraw on movement past a threshold,
	# not unconditionally. At this size it costs nothing measurable.
	_control.queue_redraw()


func _centre() -> Vector2:
	return Vector2(_control.size.x - INSET.x - RADIUS, INSET.y + RADIUS)


func _render() -> void:
	if _player == null:
		return
	var mid: Vector2 = _centre()
	var here: Vector3 = _player.global_position
	var km: Vector2 = WorldAtlas.local_to_km(&"datasedge_meadows", here.x, here.z)

	_control.draw_circle(mid, RADIUS, DISC)
	_control.draw_arc(mid, RADIUS, 0.0, TAU, 48, DISC_EDGE, 1.6)

	_draw_water(mid, here)
	_draw_markers(mid, km)
	_draw_kern(mid)
	_draw_north(mid)
	_draw_caption(mid, km)


## Local metres to disc pixels. North is -Z in the world and up on the disc, so
## the z axis flips; x does not. North-up only, by design of this placeholder.
func _to_disc(mid: Vector2, offset_x: float, offset_z: float) -> Vector2:
	var k: float = RADIUS / RANGE_M
	return mid + Vector2(offset_x * k, offset_z * k)


## The millpond, because it is the only water Kern can currently reach and
## because swimming into it is about to matter. Drawn from MeadowTerrain's own
## constants rather than a copy, so it cannot drift from the terrain.
func _draw_water(mid: Vector2, here: Vector3) -> void:
	var pond: Vector2 = MeadowTerrain.POND_CENTER
	var offset: Vector2 = Vector2(pond.x - here.x, pond.y - here.z)
	if offset.length() > RANGE_M + MeadowTerrain.POND_RADIUS:
		return
	var at: Vector2 = _to_disc(mid, offset.x, offset.y)
	var r: float = MeadowTerrain.POND_RADIUS * (RADIUS / RANGE_M)
	# Clipped by hand: Godot's immediate-mode draw has no circular clip, so a
	# pond straddling the rim is simply drawn smaller rather than spilling out.
	if at.distance_to(mid) - r < RADIUS:
		_control.draw_circle(at, minf(r, RADIUS - at.distance_to(mid) + r), Color(TEAL, 0.55))


func _draw_markers(mid: Vector2, km: Vector2) -> void:
	for site in WorldAtlas.SITES:
		var delta_km: Vector2 = site["km"] - km
		if delta_km.length() > RANGE_KM:
			continue
		# Atlas km back to metres relative to Kern: +x east, and atlas north is
		# -z, so the z offset is the negated northward difference.
		var at: Vector2 = _to_disc(mid, delta_km.x * 1000.0, -delta_km.y * 1000.0)
		if at.distance_to(mid) > RADIUS - 6.0:
			continue
		match site["kind"]:
			&"town", &"hamlet":
				_control.draw_circle(at, 3.4, INK)
			&"dungeon":
				_control.draw_colored_polygon(PackedVector2Array([
					at + Vector2(0.0, -3.6), at + Vector2(3.2, 0.0),
					at + Vector2(0.0, 3.6), at + Vector2(-3.2, 0.0),
				]), INK)
			&"shrine":
				_control.draw_circle(at, 3.2, OXIDE)
			&"world_boss":
				_control.draw_arc(at, 3.4, 0.0, TAU, 12, OXIDE, 1.4)
			&"water":
				pass  # the pond is already drawn as an area, not a pin
			_:
				_control.draw_circle(at, 2.0, Color(INK, 0.65))


## Kern's arrow, pointing where he faces. The player's yaw is measured from -Z,
## which is up on the disc, so the arrow is built pointing up and rotated by it.
func _draw_kern(mid: Vector2) -> void:
	var yaw: float = _player.global_rotation.y
	var tip: Vector2 = Vector2(0.0, -10.0).rotated(-yaw)
	var left: Vector2 = Vector2(-6.4, 6.2).rotated(-yaw)
	var right: Vector2 = Vector2(6.4, 6.2).rotated(-yaw)
	var notch: Vector2 = Vector2(0.0, 2.6).rotated(-yaw)
	# A notched arrowhead rather than a plain triangle: at this size a triangle
	# reads as a blob and its heading is a guess.
	_control.draw_colored_polygon(PackedVector2Array([
		mid + tip, mid + right, mid + notch, mid + left,
	]), KERN)
	_control.draw_polyline(PackedVector2Array([
		mid + tip, mid + right, mid + notch, mid + left, mid + tip,
	]), Color(0.05, 0.06, 0.06, 0.85), 1.2, true)


func _draw_north(mid: Vector2) -> void:
	var top: Vector2 = mid + Vector2(0.0, -RADIUS)
	_control.draw_line(top, top + Vector2(0.0, 7.0), NORTH, 2.0)
	_control.draw_string(_font, top + Vector2(-4.0, -4.0), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, NORTH)


## Region name under the disc, and the nearest named place when there is one
## close enough to be worth saying.
func _draw_caption(mid: Vector2, km: Vector2) -> void:
	var region: StringName = WorldAtlas.region_at(km)
	var name_text: String = String(WorldAtlas.REGIONS[region]["name"]) \
			if WorldAtlas.REGIONS.has(region) else "the wilds"
	var width: float = _font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 14).x
	_control.draw_string(_font, mid + Vector2(-width * 0.5, RADIUS + 18.0), name_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)

	var near: Dictionary = WorldAtlas.nearest_site(km, RANGE_KM)
	if near.is_empty():
		return
	var note: String = near["site"]["name"]
	var note_w: float = _font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_control.draw_string(_font, mid + Vector2(-note_w * 0.5, RADIUS + 33.0), note,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_DIM)

class_name CompendiumUi
extends CanvasLayer
## Compendium v1 — Kern's field notebook of the meadow's irises.
##
## GDD §9 lists a "discovery compendium" beside the quest journal; the
## WORLDBOOK's Datasedge entry says the compendium "classifies them into the
## three families" and that "rare boundary blooms (ambiguous specimens) are
## collector prizes". This is that, for the first region's flora.
##
## Three family columns, every catalogued specimen listed with the triplet
## Kern measured and what the notebook makes of it, plus a boundary-bloom
## roll at the foot. A specimen the notebook gets WRONG is shown as such —
## that is the honest and interesting case, and it is exactly where the three
## families genuinely overlap.
##
## Where it sits: instanced by `main.gd` during normal play only (screenshot
## mode leaves UI out). No scene file, no textures — a full-rect Control that
## paints in its `draw` callback, in the same shape as CombatHud. It reads
## the specimen table straight off IrisField and the catalogued set off
## GameState flags, so it holds no state of its own that could fall out of
## step. Toggled with the `compendium` action (J, or the gamepad's Back
## button); Escape closes it.
##
## Sizes are pixels at the viewport's scale.

## Panel inset from the screen edge, and the panel's internal padding.
const MARGIN: float = 54.0
const PAD: float = 26.0
## Row height and the gap under each column heading.
const ROW_H: float = 19.0
const HEADING_GAP: float = 34.0
## Rows a column shows before it stops and reports the remainder. Compendium
## v1 is a read-out, not a scrolling document — paging arrives with the full
## journal milestone.
const MAX_ROWS: int = 18

const BACKDROP: Color = Color(0.05, 0.06, 0.08, 0.82)
const PANEL: Color = Color(0.11, 0.12, 0.15, 0.96)
const PANEL_EDGE: Color = Color(0.62, 0.58, 0.42, 0.9)
const INK: Color = Color(0.93, 0.91, 0.83)
const INK_DIM: Color = Color(0.62, 0.61, 0.56)
const MISCLASSIFIED: Color = Color(0.96, 0.62, 0.42)

## True while the notebook is open. Also gates `_process`, so a closed
## compendium costs one boolean test a frame.
var is_open: bool = false

var _field: IrisField
var _control: Control
var _font: Font


## Create the compendium and bind it to the meadow's iris field.
static func build(host: Node, field: IrisField) -> CompendiumUi:
	var ui: CompendiumUi = CompendiumUi.new()
	ui.name = "CompendiumUi"
	ui._field = field
	host.add_child(ui)
	return ui


func _ready() -> void:
	# Above the combat HUD (layer 10) — the notebook covers the screen when
	# it is open, and nothing should draw over it.
	layer = 20
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	# MOUSE_FILTER_IGNORE for the same reason CombatHud uses it: the camera
	# rig needs clicks to recapture the cursor, and the compendium is
	# keyboard-driven.
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)
	_control.visible = false


## Toggle on the `compendium` action; Escape closes but never opens, so it
## keeps its existing job of releasing the mouse.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"compendium"):
		set_open(not is_open)
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.is_pressed() \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()


## Open or close the notebook. Repainting only on open (and once per open) is
## enough: nothing can be catalogued while the page is being read.
func set_open(open: bool) -> void:
	if open == is_open:
		return
	is_open = open
	_control.visible = open
	if open:
		_control.queue_redraw()


# --- Drawing -----------------------------------------------------------------

## Paint the whole notebook. Called from the Control's `draw` signal, so
## every position here is in that Control's local space, which is the
## viewport rect.
func _render() -> void:
	if _field == null:
		return
	var size: Vector2 = _control.size
	var panel: Rect2 = Rect2(MARGIN, MARGIN,
			size.x - MARGIN * 2.0, size.y - MARGIN * 2.0)
	_control.draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	_control.draw_rect(panel, PANEL)
	_control.draw_rect(panel, PANEL_EDGE, false, 2.0)

	var specimens: Array[Dictionary] = _field.specimens
	var stats: Dictionary = IrisDataset.progress(specimens)
	var origin: Vector2 = panel.position + Vector2(PAD, PAD + 22.0)

	_control.draw_string(_font, origin, "THE MEADOW COMPENDIUM — irises",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK)
	_control.draw_string(_font, origin + Vector2(0.0, 26.0),
			"%d of %d specimens pressed   ·   boundary blooms %d of %d   ·   J closes"
					% [stats["found"], stats["total"],
					stats["boundary_found"], stats["boundary_total"]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK_DIM)

	var column_w: float = (panel.size.x - PAD * 2.0) / 3.0
	var top: float = origin.y + HEADING_GAP + 22.0
	for family in IrisDataset.FAMILY_NAMES.size():
		_draw_family_column(specimens, family,
				Vector2(origin.x + column_w * float(family), top),
				column_w - 18.0, panel.position.y + panel.size.y - PAD - 74.0)

	_draw_boundary_roll(specimens, panel)


## One family's column: heading, count, and a line per catalogued specimen.
## `bottom` is the y the list must stop above, so the boundary roll at the
## foot of the page always has its room.
func _draw_family_column(specimens: Array[Dictionary], family: int,
		at: Vector2, width: float, bottom: float) -> void:
	var color: Color = IrisDataset.FAMILY_COLORS[family]
	var total: int = 0
	var rows: Array[Dictionary] = []
	for s: Dictionary in specimens:
		if int(s["family"]) != family:
			continue
		total += 1
		if IrisDataset.is_catalogued(int(s["index"])):
			rows.append(s)

	_control.draw_rect(Rect2(at + Vector2(0.0, -16.0), Vector2(width, 3.0)), color)
	_control.draw_string(_font, at, IrisDataset.FAMILY_NAMES[family],
			HORIZONTAL_ALIGNMENT_LEFT, width, 20, color)
	_control.draw_string(_font, at + Vector2(0.0, 20.0),
			"%d of %d pressed" % [rows.size(), total],
			HORIZONTAL_ALIGNMENT_LEFT, width, 14, INK_DIM)

	if rows.is_empty():
		_control.draw_string(_font, at + Vector2(0.0, 46.0),
				"— none yet —", HORIZONTAL_ALIGNMENT_LEFT, width, 14, INK_DIM)
		return

	# The three measurements, then what the notebook made of the specimen.
	# A disagreement is called out rather than hidden: those specimens are
	# where the families actually overlap, and noticing that IS the lesson.
	var y: float = at.y + 46.0
	var shown: int = 0
	for s: Dictionary in rows:
		if y > bottom or shown >= MAX_ROWS:
			_control.draw_string(_font, Vector2(at.x, y),
					"… and %d more" % (rows.size() - shown),
					HORIZONTAL_ALIGNMENT_LEFT, width, 14, INK_DIM)
			return
		var m: Array = s["measures"]
		var line: String = "%4.1f  %4.1f  %4.1f cm" % [m[0], m[1], m[2]]
		var wrong: bool = int(s["classified"]) != family
		if bool(s["boundary"]):
			line += "   ◆"
		if wrong:
			line += "   reads as %s" % IrisDataset.FAMILY_NAMES[int(s["classified"])]
		_control.draw_string(_font, Vector2(at.x, y), line,
				HORIZONTAL_ALIGNMENT_LEFT, width, 14,
				MISCLASSIFIED if wrong else INK)
		y += ROW_H
		shown += 1


## The foot of the page: what a boundary bloom is, and how many are pressed.
func _draw_boundary_roll(specimens: Array[Dictionary], panel: Rect2) -> void:
	var found: int = 0
	var total: int = 0
	for s: Dictionary in specimens:
		if not bool(s["boundary"]):
			continue
		total += 1
		if IrisDataset.is_catalogued(int(s["index"])):
			found += 1

	var y: float = panel.position.y + panel.size.y - PAD - 44.0
	_control.draw_rect(Rect2(panel.position.x + PAD, y - 18.0,
			panel.size.x - PAD * 2.0, 2.0), IrisDataset.BOUNDARY_COLOR)
	_control.draw_string(_font, Vector2(panel.position.x + PAD, y),
			"◆ BOUNDARY BLOOMS — %d of %d" % [found, total],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, IrisDataset.BOUNDARY_COLOR)
	_control.draw_string(_font, Vector2(panel.position.x + PAD, y + 22.0),
			"Specimens the notebook cannot call. Their measurements sit as near "
			+ "one family as another, and no amount of pressing settles it. "
			+ "They grow paler than the rest — look for the near-white ones.",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - PAD * 2.0, 14, INK_DIM)

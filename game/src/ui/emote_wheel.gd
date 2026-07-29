class_name EmoteWheel
extends CanvasLayer
## The radial emote picker: hold the emote key to open it, aim with the stick or
## mouse, release to perform.
##
## **Why a wheel and not a menu.** Emotes are social, spontaneous and used mid-
## play, so the interaction has to survive being done without looking. A radial
## selector is muscle-memorable — the third dance is always up-and-right — and
## the hold-aim-release shape means an emote costs one gesture rather than a
## menu round trip. Everything is drawn in code, per the project's
## generated-assets rule (CLAUDE.md § Conventions).
##
## **Time does not stop.** The wheel is deliberately non-modal: the world keeps
## running behind it, because pausing for a dance would make emoting feel like
## opening the inventory instead of like an expressive act.
##
## Architecture: pure presentation. It reads `EmoteLibrary.defs()` for its
## contents and emits `chosen` with an emote id; `player.gd` owns the input hold
## and hands the result to `KernVisual.play_emote()`. Nothing here touches the
## rig. See `docs/ARCHITECTURE.md`.

## Emitted on release with the highlighted emote's id, or "" if none.
signal chosen(emote_id: String)

## Radius of the ring of options, pixels.
const RADIUS: float = 168.0

## Dead zone at the centre, in pixels for the mouse and 0..1 for a stick, inside
## which nothing is selected — so opening and releasing without aiming cancels.
const DEAD_ZONE_PIXELS: float = 46.0
const DEAD_ZONE_STICK: float = 0.35

const BACKDROP: Color = Color(0.04, 0.05, 0.08, 0.55)
const SLICE_IDLE: Color = Color(0.16, 0.19, 0.26, 0.82)
const SLICE_HOT: Color = Color(0.36, 0.62, 0.95, 0.95)
const TEXT_IDLE: Color = Color(0.80, 0.85, 0.93)
const TEXT_HOT: Color = Color(1.0, 1.0, 1.0)
const DANCE_TINT: Color = Color(0.95, 0.72, 0.38)

var _root: Control
var _defs: Array = []
var _selected: int = -1
var _open: bool = false
## Aim direction while a gamepad is driving, kept between frames because a stick
## returned to centre should HOLD the last choice rather than deselect — letting
## go of the stick to press the button must not cancel the pick.
var _stick_aim: Vector2 = Vector2.ZERO


## Build the wheel under `parent` and return it, hidden.
static func build(parent: Node) -> EmoteWheel:
	var wheel: EmoteWheel = EmoteWheel.new()
	wheel.name = "EmoteWheel"
	parent.add_child(wheel)
	return wheel


func _ready() -> void:
	layer = 12
	_defs = EmoteLibrary.defs()
	_root = Control.new()
	_root.name = "WheelRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.draw.connect(_on_draw)
	visible = false


## Show the wheel and start tracking aim.
func open() -> void:
	if _open:
		return
	_open = true
	_selected = -1
	_stick_aim = Vector2.ZERO
	visible = true
	_root.queue_redraw()


## Hide the wheel and emit whatever was highlighted.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var id: String = ""
	if _selected >= 0 and _selected < _defs.size():
		id = (_defs[_selected] as EmoteLibrary.EmoteDef).id
	chosen.emit(id)


## True while the wheel is showing.
func is_open() -> bool:
	return _open


func _process(_delta: float) -> void:
	if not _open:
		return
	_update_selection()
	_root.queue_redraw()


## Work out which slice is aimed at, from either stick or mouse.
func _update_selection() -> void:
	var stick: Vector2 = Input.get_vector(&"cam_left", &"cam_right",
		&"cam_up", &"cam_down")
	var aim: Vector2 = Vector2.ZERO
	if stick.length() > DEAD_ZONE_STICK:
		_stick_aim = stick
	if _stick_aim.length() > DEAD_ZONE_STICK:
		# Stick Y is inverted relative to screen space.
		aim = Vector2(_stick_aim.x, _stick_aim.y)
	else:
		var centre: Vector2 = _root.size * 0.5
		var offset: Vector2 = _root.get_local_mouse_position() - centre
		if offset.length() > DEAD_ZONE_PIXELS:
			aim = offset

	if aim.length() < 0.001:
		_selected = -1
		return
	# Slice 0 sits at the top and they run clockwise.
	var angle: float = fposmod(atan2(aim.x, -aim.y), TAU)
	var count: int = _defs.size()
	_selected = int(floor(angle / TAU * float(count) + 0.5)) % count


func _on_draw() -> void:
	var centre: Vector2 = _root.size * 0.5
	_root.draw_rect(Rect2(Vector2.ZERO, _root.size), BACKDROP)
	var count: int = _defs.size()
	var font: Font = ThemeDB.fallback_font
	for i in count:
		var def: EmoteLibrary.EmoteDef = _defs[i]
		var angle: float = TAU * float(i) / float(count)
		var dir: Vector2 = Vector2(sin(angle), -cos(angle))
		var at: Vector2 = centre + dir * RADIUS
		var hot: bool = i == _selected
		var fill: Color = SLICE_HOT if hot else SLICE_IDLE
		if def.category == "dance" and not hot:
			fill = SLICE_IDLE.lerp(DANCE_TINT, 0.22)
		_root.draw_circle(at, 34.0 if hot else 29.0, fill)
		var label: String = def.display_name
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 14).x
		_root.draw_string(font, at + Vector2(-width * 0.5, 52.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			TEXT_HOT if hot else TEXT_IDLE)
	var hint: String = "aim and release"
	if _selected >= 0:
		hint = (_defs[_selected] as EmoteLibrary.EmoteDef).display_name
	var hint_width: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT,
		-1, 18).x
	_root.draw_string(font, centre + Vector2(-hint_width * 0.5, 6.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_HOT)

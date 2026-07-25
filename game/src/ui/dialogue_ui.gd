class_name DialogueUi
extends CanvasLayer
## The talking box, and the "press E" chip that offers a conversation.
##
## Drawn entirely in code (no textures, no theme resources) like CombatHud, and
## fed only by EventBus — it holds no reference to any villager, so it will
## serve every region's NPCs unchanged. It owns exactly one piece of state the
## rest of the game cares about: whether the current line has finished typing.
## NpcInteractor waits on `dialogue_line_revealed` before it turns the page, and
## asks for an instant reveal with `dialogue_skip_requested`, so the first press
## always finishes the sentence and the second always advances.

const CHARS_PER_SEC: float = 62.0
const PANEL_MAX_WIDTH: float = 900.0
const PANEL_HEIGHT: float = 176.0
const PANEL_MARGIN: float = 44.0
const TEXT_PAD: Vector2 = Vector2(30.0, 34.0)
const NAME_SIZE: int = 21
const BODY_SIZE: int = 22
const PROMPT_SIZE: int = 18
const FADE_SPEED: float = 7.0

const INK: Color = Color(0.055, 0.065, 0.095, 0.93)
const BRASS: Color = Color(0.87, 0.73, 0.42)
const PARCHMENT: Color = Color(0.96, 0.94, 0.88)

var _control: Control
var _font: Font

var _speaker: String = ""
var _line: String = ""
var _shown: float = 0.0
var _line_id: String = ""
var _announced: bool = true
var _open: float = 0.0            ## dialogue panel fade, 0..1
var _prompt_text: String = ""
var _prompt_fade: float = 0.0
var _blink: float = 0.0


func _ready() -> void:
	layer = 11                     # above CombatHud's 10
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.name = "DialogueCanvas"
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)
	EventBus.interact_target_changed.connect(_on_target_changed)
	EventBus.dialogue_started.connect(_on_started)
	EventBus.dialogue_line.connect(_on_line)
	EventBus.dialogue_ended.connect(_on_ended)
	EventBus.dialogue_skip_requested.connect(_on_skip)


func _process(delta: float) -> void:
	_blink += delta
	var open_target: float = 1.0 if _speaker != "" else 0.0
	_open = move_toward(_open, open_target, FADE_SPEED * delta)
	var prompt_target: float = 1.0 if (_prompt_text != "" and _speaker == "") else 0.0
	_prompt_fade = move_toward(_prompt_fade, prompt_target, FADE_SPEED * delta)

	if not _announced:
		_shown = minf(_shown + CHARS_PER_SEC * delta, float(_line.length()))
		if _shown >= float(_line.length()):
			_announced = true
			EventBus.dialogue_line_revealed.emit(_line_id)
	_control.queue_redraw()


# --- EventBus ----------------------------------------------------------------

func _on_target_changed(_npc_id: String, prompt: String) -> void:
	_prompt_text = prompt


func _on_started(_npc_id: String, speaker: String) -> void:
	_speaker = speaker
	_prompt_text = ""


func _on_line(npc_id: String, line: String) -> void:
	_line_id = npc_id
	_line = line
	_shown = 0.0
	_announced = false


func _on_skip() -> void:
	_shown = float(_line.length())


func _on_ended(_npc_id: String) -> void:
	_speaker = ""
	_line = ""
	_shown = 0.0
	_announced = true


# --- Drawing -----------------------------------------------------------------

func _render() -> void:
	var screen: Vector2 = _control.get_viewport_rect().size
	if _prompt_fade > 0.002:
		_draw_prompt(screen)
	if _open > 0.002:
		_draw_panel(screen)


func _draw_prompt(screen: Vector2) -> void:
	var label: String = _prompt_text
	var text_w: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		PROMPT_SIZE).x
	var key_w: float = 30.0
	var pad: float = 16.0
	var w: float = key_w + 12.0 + text_w + pad * 2.0
	var h: float = 40.0
	var origin: Vector2 = Vector2(screen.x * 0.5 - w * 0.5, screen.y - PANEL_MARGIN
		- PANEL_HEIGHT - 26.0 - h)
	# Rises slightly as it fades in.
	origin.y += (1.0 - _prompt_fade) * 10.0

	var pill: StyleBoxFlat = _style(INK, BRASS, 20.0, _prompt_fade)
	_control.draw_style_box(pill, Rect2(origin, Vector2(w, h)))

	var cap: StyleBoxFlat = _style(Color(0.9, 0.86, 0.76, 0.95), Color(0.35, 0.3, 0.22),
		6.0, _prompt_fade)
	var cap_rect: Rect2 = Rect2(origin + Vector2(pad, (h - 26.0) * 0.5), Vector2(key_w, 26.0))
	_control.draw_style_box(cap, cap_rect)
	var key_size: Vector2 = _font.get_string_size("E", HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_SIZE)
	_control.draw_string(_font,
		cap_rect.position + Vector2((key_w - key_size.x) * 0.5, 19.0), "E",
		HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_SIZE,
		Color(0.16, 0.13, 0.1, _prompt_fade))
	_control.draw_string(_font, origin + Vector2(pad + key_w + 12.0, h * 0.5 + 6.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_SIZE, Color(PARCHMENT, _prompt_fade))


func _draw_panel(screen: Vector2) -> void:
	var w: float = minf(PANEL_MAX_WIDTH, screen.x - 120.0)
	var origin: Vector2 = Vector2(screen.x * 0.5 - w * 0.5,
		screen.y - PANEL_MARGIN - PANEL_HEIGHT)
	origin.y += (1.0 - _open) * 22.0
	var panel_rect: Rect2 = Rect2(origin, Vector2(w, PANEL_HEIGHT))
	_control.draw_style_box(_style(INK, BRASS, 12.0, _open), panel_rect)

	# Speaker tab, sitting on the panel's top edge.
	var name_size: Vector2 = _font.get_string_size(_speaker, HORIZONTAL_ALIGNMENT_LEFT, -1,
		NAME_SIZE)
	var tab: Rect2 = Rect2(origin + Vector2(26.0, -19.0), Vector2(name_size.x + 34.0, 36.0))
	_control.draw_style_box(_style(BRASS, Color(0.42, 0.32, 0.16), 10.0, _open), tab)
	_control.draw_string(_font, tab.position + Vector2(17.0, 25.0), _speaker,
		HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, Color(Color(0.15, 0.11, 0.07), _open))

	var shown_text: String = _line.substr(0, int(_shown))
	_control.draw_multiline_string(_font, origin + TEXT_PAD, shown_text,
		HORIZONTAL_ALIGNMENT_LEFT, w - TEXT_PAD.x * 2.0, BODY_SIZE, -1,
		Color(PARCHMENT, _open))

	if _announced:
		_draw_chevron(origin + Vector2(w - 34.0, PANEL_HEIGHT - 26.0))


## A small blinking arrow: the universal "there's more, press again".
func _draw_chevron(at: Vector2) -> void:
	var pulse: float = 0.55 + 0.45 * sin(_blink * 4.2)
	var nudge: float = sin(_blink * 4.2) * 2.0
	var col: Color = Color(BRASS, _open * pulse)
	var pts: PackedVector2Array = PackedVector2Array([
		at + Vector2(-7.0, -4.0 + nudge), at + Vector2(7.0, -4.0 + nudge),
		at + Vector2(0.0, 6.0 + nudge),
	])
	_control.draw_colored_polygon(pts, col)


func _style(fill: Color, border: Color, radius: float, fade: float) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(fill, fill.a * fade)
	sb.border_color = Color(border, border.a * fade)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(radius))
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35 * fade)
	sb.shadow_size = 6
	return sb

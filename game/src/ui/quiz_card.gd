class_name QuizCard
extends CanvasLayer
## The in-combat question card — Phase 1 milestone 7 (Knowledge charge v1).
##
## Pure presentation: it draws whatever `KnowledgeQuiz` hands it and reports
## nothing back. Input, timing, scoring, and the EventBus emit all live in the
## director; this file owns pixels only. Drawn entirely in code (no textures, no
## theme resources) like the rest of the project's UI, in the combat HUD's
## palette so the card and the focus meter read as one system.
##
## It never blocks play: the control ignores the mouse, the camera stays
## captured, and the world keeps running underneath. The card sits low and
## centred so it can be read with a monster still on screen — answering under
## pressure IS the mechanic.
##
## Colour is never the only signal (a right answer also gets a drawn check, a
## wrong pick a drawn cross), so the card survives colour-blind eyes and a
## washed-out screenshot alike.
##
## GDD §10 visible surface: UNSEEN — no Godot in this build environment, so a
## live session must lay eyes on this before the milestone box ticks clean.

enum State { HIDDEN, ASKING, REVEAL }

const CARD_MAX_WIDTH: float = 700.0
const SIDE_MARGIN: float = 60.0
const BOTTOM_MARGIN: float = 52.0
const TOP_CLAMP: float = 10.0
const PAD: float = 18.0
const TIMER_HEIGHT: float = 4.0
const HEADER_HEIGHT: float = 20.0
const FOOTER_HEIGHT: float = 18.0
const ROW_MIN_HEIGHT: float = 30.0
const ROW_GAP: float = 6.0
const ROW_PAD: float = 7.0
const BADGE_SIZE: float = 22.0
const BADGE_GAP: float = 10.0
const QUESTION_GAP: float = 14.0

const QUESTION_FONT: int = 19
const CHOICE_FONT: int = 16
const LABEL_FONT: int = 12
const EXPLANATION_FONT: int = 14

const RISE_DISTANCE: float = 26.0
const FADE_IN_SPEED: float = 7.0
const FADE_OUT_SPEED: float = 5.0
const EXPLAIN_GROW_SPEED: float = 6.0

# Shared with CombatHud's focus meter so the card reads as the same system.
const COL_PANEL: Color = Color(0.055, 0.065, 0.105, 0.90)
const COL_PANEL_EDGE: Color = Color(1.0, 0.82, 0.32, 0.55)
const COL_ACCENT: Color = Color(0.55, 0.78, 1.0)
const COL_GOLD: Color = Color(1.0, 0.82, 0.32)
const COL_TEXT: Color = Color(0.94, 0.95, 0.99)
const COL_DIM: Color = Color(0.66, 0.70, 0.78)
const COL_RIGHT: Color = Color(0.45, 0.88, 0.55)
const COL_WRONG: Color = Color(0.93, 0.40, 0.38)
const COL_ROW: Color = Color(0.11, 0.13, 0.19, 0.85)
const COL_URGENT: Color = Color(1.0, 0.62, 0.30)

const URGENT_BELOW: float = 0.3

## topic id (quiz.schema.json enum) -> the label drawn on the card. Chrome only:
## the world's own voice never speaks in these terms (WORLDBOOK Part IV).
const TOPIC_LABELS: Dictionary = {
	"ml_basics": "FOUNDATIONS",
	"data": "DATA",
	"models": "MODELS",
	"training": "TRAINING",
	"evaluation": "EVALUATION",
	"neural_networks": "NEURAL NETWORKS",
	"overfitting": "OVERFITTING",
	"nlp_llms": "LANGUAGE",
	"computer_vision": "VISION",
	"reinforcement": "REINFORCEMENT",
	"ethics_alignment": "ALIGNMENT",
}

var _control: Control
var _font: Font

var _state: int = State.HIDDEN
var _entry: Dictionary = {}
var _picked: int = -1
var _correct: bool = false
var _timed_out: bool = false
var _focus_full: bool = false
var _time_left: float = 1.0

var _alpha: float = 0.0
var _target_alpha: float = 0.0
var _explain: float = 0.0
var _breaking: bool = false


func _ready() -> void:
	layer = 11  # one above CombatHud
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.name = "CardCanvas"
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)


func _process(delta: float) -> void:
	var was_drawing: bool = _state != State.HIDDEN or _alpha > 0.0
	var speed: float = FADE_IN_SPEED if _target_alpha > _alpha else FADE_OUT_SPEED
	_alpha = move_toward(_alpha, _target_alpha, speed * delta)
	if _state == State.REVEAL:
		_explain = minf(1.0, _explain + EXPLAIN_GROW_SPEED * delta)
	if _alpha <= 0.001 and _target_alpha <= 0.0 and _state != State.HIDDEN:
		_state = State.HIDDEN
		_entry = {}
	if was_drawing:
		# One last redraw on the way out clears the canvas; then we go quiet.
		_control.queue_redraw()


# --- Director-facing API -----------------------------------------------------

## Put a question up. `entry` is an approved ContentDB quiz record.
func ask(entry: Dictionary) -> void:
	_entry = entry
	_state = State.ASKING
	_picked = -1
	_correct = false
	_timed_out = false
	_focus_full = false
	_breaking = false
	_explain = 0.0
	_time_left = 1.0
	_target_alpha = 1.0


## Remaining answer time, 1 → 0. Pushed every frame; the director owns the clock.
func set_time_left(fraction: float) -> void:
	_time_left = clampf(fraction, 0.0, 1.0)


## Show the verdict: which choice was picked, whether it was right, and whether
## that answer just topped the focus meter off.
func reveal(picked: int, correct: bool, focus_full: bool) -> void:
	if _state == State.HIDDEN:
		return
	_picked = picked
	_correct = correct
	_timed_out = false
	_focus_full = focus_full
	_state = State.REVEAL
	_explain = 0.0
	_time_left = 0.0


## Nobody answered in time. The right answer is still shown — the point is to
## teach, and a missed question isn't a wrong one.
func time_out() -> void:
	if _state == State.HIDDEN:
		return
	_picked = -1
	_correct = false
	_timed_out = true
	_focus_full = false
	_state = State.REVEAL
	_explain = 0.0
	_time_left = 0.0


## Kern took a hit mid-question: concentration breaks, the card snaps away.
func interrupt() -> void:
	_breaking = true
	_target_alpha = 0.0


func dismiss() -> void:
	_target_alpha = 0.0


func is_showing() -> bool:
	return _state != State.HIDDEN


# --- Drawing -----------------------------------------------------------------

func _render() -> void:
	if _alpha <= 0.003 or _entry.is_empty() or _font == null:
		return
	var screen: Vector2 = _control.get_viewport_rect().size
	var width: float = minf(CARD_MAX_WIDTH, maxf(320.0, screen.x - SIDE_MARGIN * 2.0))
	var inner: float = width - PAD * 2.0
	var layout: Dictionary = _measure(inner)
	var height: float = float(layout["height"])
	var rise: float = (1.0 - _alpha) * RISE_DISTANCE
	# Sits above the bottom margin, but never so tall that the countdown bar and
	# the header climb off the top of a small window.
	var top: float = maxf(TOP_CLAMP, screen.y - BOTTOM_MARGIN - height + rise)
	var origin: Vector2 = Vector2(floor((screen.x - width) * 0.5), floor(top))

	_draw_panel(origin, Vector2(width, height))
	var y: float = origin.y + TIMER_HEIGHT + PAD
	_draw_header(Vector2(origin.x + PAD, y), inner)
	y += HEADER_HEIGHT + 6.0
	_draw_wrapped(str(_entry.get("question", "")), Vector2(origin.x + PAD, y), inner,
		QUESTION_FONT, _tint(COL_TEXT))
	y += float(layout["question"]) + QUESTION_GAP

	var rows: Array = layout["rows"]
	var choices: Array = _entry.get("choices", [])
	for i in choices.size():
		var row_h: float = float(rows[i])
		_draw_choice(i, str(choices[i]), Vector2(origin.x + PAD, y), inner, row_h)
		y += row_h + ROW_GAP

	if _state == State.REVEAL and _explain > 0.0:
		_draw_explanation(Vector2(origin.x + PAD, y), inner)
	_draw_footer(Vector2(origin.x + PAD, origin.y + height - PAD - FOOTER_HEIGHT), inner)


func _measure(inner: float) -> Dictionary:
	var question_h: float = _wrapped_height(str(_entry.get("question", "")), inner, QUESTION_FONT)
	var choice_width: float = inner - BADGE_SIZE - BADGE_GAP
	var rows: Array[float] = []
	var rows_total: float = 0.0
	for choice: Variant in _entry.get("choices", []):
		var h: float = maxf(ROW_MIN_HEIGHT,
			_wrapped_height(str(choice), choice_width, CHOICE_FONT) + ROW_PAD * 2.0)
		rows.append(h)
		rows_total += h + ROW_GAP
	var explain_h: float = 0.0
	if _state == State.REVEAL:
		var text_h: float = _wrapped_height(_explanation_text(), inner, EXPLANATION_FONT)
		explain_h = (text_h + 12.0) * _explain
	var height: float = TIMER_HEIGHT + PAD + HEADER_HEIGHT + 6.0 + question_h + QUESTION_GAP \
		+ rows_total + explain_h + FOOTER_HEIGHT + PAD
	return {"height": height, "question": question_h, "rows": rows, "explain": explain_h}


func _draw_panel(origin: Vector2, size: Vector2) -> void:
	_control.draw_rect(Rect2(origin + Vector2(4.0, 5.0), size), _tint(Color(0, 0, 0, 0.35)))
	_control.draw_rect(Rect2(origin, size), _tint(COL_PANEL))
	var edge: Color = COL_PANEL_EDGE
	if _state == State.REVEAL:
		edge = COL_RIGHT if _correct else (COL_DIM if _timed_out else COL_WRONG)
	elif _breaking:
		edge = COL_WRONG
	_control.draw_rect(Rect2(origin, size), _tint(edge), false, 2.0)
	# The answer clock rides the card's top edge and warms as it runs out.
	var bar: Color = COL_URGENT if _time_left <= URGENT_BELOW else COL_ACCENT
	_control.draw_rect(Rect2(origin, Vector2(size.x, TIMER_HEIGHT)), _tint(Color(0, 0, 0, 0.5)))
	if _time_left > 0.0:
		_control.draw_rect(Rect2(origin, Vector2(size.x * _time_left, TIMER_HEIGHT)), _tint(bar))


func _draw_header(pos: Vector2, inner: float) -> void:
	var topic: String = str(_entry.get("topic", ""))
	var label: String = "RECALL"
	if TOPIC_LABELS.has(topic):
		label += " · " + str(TOPIC_LABELS[topic])
	_control.draw_string(_font, pos + Vector2(0.0, LABEL_FONT), label,
		HORIZONTAL_ALIGNMENT_LEFT, inner, LABEL_FONT, _tint(COL_GOLD))
	_draw_difficulty_pips(Vector2(pos.x + inner, pos.y + LABEL_FONT * 0.4),
		int(_entry.get("difficulty", 1)))


## Difficulty as little diamonds, right-aligned: filled for this question's
## rating, hollow for the rest of the five-step scale.
func _draw_difficulty_pips(right_anchor: Vector2, difficulty: int) -> void:
	var pip: float = 4.0
	var gap: float = 5.0
	var count: int = 5
	var span: float = float(count) * (pip * 2.0 + gap) - gap
	var x: float = right_anchor.x - span + pip
	for i in count:
		var centre: Vector2 = Vector2(x + float(i) * (pip * 2.0 + gap), right_anchor.y)
		var diamond: PackedVector2Array = [
			centre + Vector2(0.0, -pip), centre + Vector2(pip, 0.0),
			centre + Vector2(0.0, pip), centre + Vector2(-pip, 0.0),
		]
		if i < difficulty:
			_control.draw_colored_polygon(diamond, _tint(COL_GOLD))
		else:
			_control.draw_polyline(diamond + PackedVector2Array([diamond[0]]),
				_tint(Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.45)), 1.0)


func _draw_choice(index: int, text: String, pos: Vector2, inner: float, row_h: float) -> void:
	var answer: int = int(_entry.get("answer_index", -1))
	var revealed: bool = _state == State.REVEAL
	var is_answer: bool = revealed and index == answer
	var is_bad_pick: bool = revealed and index == _picked and index != answer

	var fill: Color = COL_ROW
	var text_col: Color = COL_TEXT
	if revealed:
		if is_answer:
			fill = Color(COL_RIGHT.r, COL_RIGHT.g, COL_RIGHT.b, 0.26)
		elif is_bad_pick:
			fill = Color(COL_WRONG.r, COL_WRONG.g, COL_WRONG.b, 0.24)
		else:
			text_col = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.65)
	_control.draw_rect(Rect2(pos, Vector2(inner, row_h)), _tint(fill))
	if is_answer or is_bad_pick:
		var edge: Color = COL_RIGHT if is_answer else COL_WRONG
		_control.draw_rect(Rect2(pos, Vector2(inner, row_h)), _tint(edge), false, 1.5)

	# Key badge: the number you press, or the verdict mark once it's over.
	var badge: Rect2 = Rect2(pos + Vector2(0.0, (row_h - BADGE_SIZE) * 0.5),
		Vector2(BADGE_SIZE, BADGE_SIZE))
	var badge_col: Color = COL_ACCENT
	if is_answer:
		badge_col = COL_RIGHT
	elif is_bad_pick:
		badge_col = COL_WRONG
	elif revealed:
		badge_col = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.5)
	_control.draw_rect(badge, _tint(Color(badge_col.r, badge_col.g, badge_col.b, 0.22)))
	_control.draw_rect(badge, _tint(badge_col), false, 1.0)
	if is_answer:
		_draw_check(badge.get_center(), _tint(COL_RIGHT))
	elif is_bad_pick:
		_draw_cross(badge.get_center(), _tint(COL_WRONG))
	else:
		var number: String = str(index + 1)
		var w: float = _font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT).x
		_control.draw_string(_font,
			badge.get_center() + Vector2(-w * 0.5, LABEL_FONT * 0.42), number,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, _tint(badge_col))

	_draw_wrapped(text, pos + Vector2(BADGE_SIZE + BADGE_GAP, ROW_PAD),
		inner - BADGE_SIZE - BADGE_GAP, CHOICE_FONT, _tint(text_col))


## A drawn tick, not a glyph — the fallback font is never asked for symbols.
func _draw_check(centre: Vector2, col: Color) -> void:
	var pts: PackedVector2Array = [
		centre + Vector2(-5.0, 0.0), centre + Vector2(-1.5, 4.0), centre + Vector2(5.5, -4.5),
	]
	_control.draw_polyline(pts, col, 2.0)


func _draw_cross(centre: Vector2, col: Color) -> void:
	_control.draw_line(centre + Vector2(-4.5, -4.5), centre + Vector2(4.5, 4.5), col, 2.0)
	_control.draw_line(centre + Vector2(4.5, -4.5), centre + Vector2(-4.5, 4.5), col, 2.0)


func _draw_explanation(pos: Vector2, inner: float) -> void:
	# Fades in only once the panel has finished growing to hold it, so the text
	# never spills past the bottom edge mid-transition.
	var alpha: float = smoothstep(0.75, 1.0, _explain)
	if alpha <= 0.01:
		return
	var col: Color = COL_DIM if not _correct else COL_RIGHT.lerp(COL_TEXT, 0.5)
	_control.draw_line(pos + Vector2(0.0, 4.0), pos + Vector2(inner, 4.0),
		_tint(Color(1, 1, 1, 0.10 * alpha)), 1.0)
	_draw_wrapped(_explanation_text(), pos + Vector2(0.0, 10.0), inner, EXPLANATION_FONT,
		_tint(Color(col.r, col.g, col.b, alpha)))


func _draw_footer(pos: Vector2, inner: float) -> void:
	var left: String = "1-4  /  D-PAD"
	var right: String = ""
	match _state:
		State.REVEAL:
			if _timed_out:
				left = "NO ANSWER"
			elif _correct:
				left = "CORRECT  ·  FOCUS RISES"
				right = "PRESS Q — FOCUS FULL" if _focus_full else ""
			else:
				left = "NOT QUITE  ·  NO CHARGE"
		_:
			right = "ANSWER WHILE YOU CAN"
	var col: Color = COL_DIM
	if _state == State.REVEAL:
		col = COL_RIGHT if _correct else (COL_DIM if _timed_out else COL_WRONG)
	_control.draw_string(_font, pos + Vector2(0.0, LABEL_FONT), left,
		HORIZONTAL_ALIGNMENT_LEFT, inner, LABEL_FONT, _tint(col))
	if right != "":
		_control.draw_string(_font, pos + Vector2(0.0, LABEL_FONT), right,
			HORIZONTAL_ALIGNMENT_RIGHT, inner, LABEL_FONT, _tint(COL_GOLD))


func _explanation_text() -> String:
	return str(_entry.get("explanation", ""))


func _draw_wrapped(text: String, top_left: Vector2, width: float, size: int, col: Color) -> void:
	# draw_multiline_string anchors to the first line's baseline, not its top.
	_control.draw_multiline_string(_font, top_left + Vector2(0.0, _font.get_ascent(size)),
		text, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, col)


func _wrapped_height(text: String, width: float, size: int) -> float:
	return _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size).y


func _tint(col: Color) -> Color:
	return Color(col.r, col.g, col.b, col.a * _alpha)

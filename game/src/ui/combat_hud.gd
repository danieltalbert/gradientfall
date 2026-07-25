class_name CombatHud
extends CanvasLayer
## A deliberately small combat read-out: a heart row (half-heart aware), a focus
## (knowledge-charge) sliver, and a damage vignette. It exists so Combat v1 is
## actually playable/verifiable — the full HUD (hearts + Tokens + minimap) is its
## own later ROADMAP milestone and will supersede this v0. Everything is drawn in
## code (no textures), reading only EventBus signals.
##
## Instanced by main.gd during normal play (screenshot mode leaves it out so
## captures stay clean). It has no scene file and no node dependencies: it
## adds a full-rect Control and paints in that Control's `draw` callback,
## driven entirely by EventBus.player_hearts_changed, knowledge_charge_changed,
## and player_hit. Sizes are pixels at the viewport's scale.

## Heart glyph size and spacing in pixels, and the top-left screen inset the
## whole read-out is laid out from.
const HEART_SIZE: float = 22.0
const HEART_GAP: float = 8.0
const MARGIN: Vector2 = Vector2(26.0, 22.0)

## Mirrored player state. Hearts are floats so half-hearts are representable.
var _hearts: float = 3.0
var _hearts_max: float = 3.0
## Knowledge-charge meter fill in [0, 1]; 1.0 means the special is ready.
var _charge: float = 0.0
## Damage-flash intensity, set to 1.0 on a hit and decayed each frame.
var _vignette: float = 0.0

## The Control that owns the actual drawing surface.
var _control: Control


## Create the drawing surface and subscribe to the three combat signals.
func _ready() -> void:
	# Above world UI; nothing else claims layer 10 yet.
	layer = 10
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The HUD must never swallow clicks — the camera rig needs them to
	# recapture the mouse cursor.
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)
	EventBus.player_hearts_changed.connect(_on_hearts)
	EventBus.knowledge_charge_changed.connect(_on_charge)
	EventBus.player_hit.connect(_on_player_hit)


## Fade the damage flash (a full flash clears in ~0.6 s) and request a
## repaint. The redraw is unconditional because the low-health pulse and the
## focus meter both animate continuously.
func _process(delta: float) -> void:
	if _vignette > 0.0:
		_vignette = maxf(0.0, _vignette - delta * 1.6)
	_control.queue_redraw()


## EventBus.player_hearts_changed handler.
func _on_hearts(current: float, max_hearts: float) -> void:
	_hearts = current
	_hearts_max = max_hearts


## EventBus.knowledge_charge_changed handler; `fraction` is the meter fill.
func _on_charge(fraction: float) -> void:
	_charge = fraction


## EventBus.player_hit handler — the damage amount doesn't matter here, any
## hit triggers the same full-strength flash.
func _on_player_hit(_amount: float) -> void:
	_vignette = 1.0


# --- Drawing -----------------------------------------------------------------

## The Control's draw callback. Vignette first so the hearts and meter paint
## on top of it.
func _render() -> void:
	var screen: Vector2 = _control.get_viewport_rect().size
	_draw_damage_vignette(screen)
	_draw_hearts()
	_draw_focus()


## Lay out the heart row: one glyph per whole heart of capacity, each drawn
## full, half, or empty. The epsilon on the floor keeps a value like 2.9999
## (float accumulation) from rendering as two and a half hearts.
func _draw_hearts() -> void:
	var full: int = int(floor(_hearts + 0.001))
	var half: bool = (_hearts - float(full)) >= 0.5
	var total: int = int(ceil(_hearts_max))
	for i in total:
		var pos: Vector2 = MARGIN + Vector2(float(i) * (HEART_SIZE + HEART_GAP), 0.0)
		# 0 empty, 1 half, 2 full — matches _draw_heart's `state`.
		var state: int = 0
		if i < full:
			state = 2
		elif i == full and half:
			state = 1
		_draw_heart(pos, HEART_SIZE, state)


## Draw one heart glyph: two circles for the humps plus a downward triangle
## for the point. `state` is 0 empty, 1 half, 2 full. The empty shape is
## always laid down first so a partial heart still shows its outline.
func _draw_heart(top_left: Vector2, size: float, state: int) -> void:
	var c: Vector2 = top_left + Vector2(size * 0.5, size * 0.5)
	var r: float = size * 0.5
	var empty_col: Color = Color(0.16, 0.05, 0.08, 0.75)
	var fill_col: Color = Color(0.93, 0.24, 0.32, 1.0)
	var hump_r: float = r * 0.56
	var lhump: Vector2 = c + Vector2(-r * 0.46, -r * 0.34)
	var rhump: Vector2 = c + Vector2(r * 0.46, -r * 0.34)
	var tri: PackedVector2Array = [
		c + Vector2(-r, -r * 0.12), c + Vector2(r, -r * 0.12), c + Vector2(0.0, r),
	]
	# Base (empty) always drawn.
	_control.draw_circle(lhump, hump_r, empty_col)
	_control.draw_circle(rhump, hump_r, empty_col)
	_control.draw_colored_polygon(tri, empty_col)
	if state == 2:
		_control.draw_circle(lhump, hump_r, fill_col)
		_control.draw_circle(rhump, hump_r, fill_col)
		_control.draw_colored_polygon(tri, fill_col)
	elif state == 1:
		# Left half only → a classic half heart.
		_control.draw_circle(lhump, hump_r, fill_col)
		var lhalf: PackedVector2Array = [
			c + Vector2(-r, -r * 0.12), c + Vector2(0.0, -r * 0.12), c + Vector2(0.0, r),
		]
		_control.draw_colored_polygon(lhalf, fill_col)


## The knowledge-charge sliver under the hearts: a dark trough, a fill bar,
## and a hairline border. The fill turns from blue to gold at full charge —
## the player's cue that the special is available.
func _draw_focus() -> void:
	var w: float = 168.0
	var h: float = 9.0
	var pos: Vector2 = MARGIN + Vector2(0.0, HEART_SIZE + 14.0)
	var bg: Color = Color(0.08, 0.08, 0.12, 0.7)
	_control.draw_rect(Rect2(pos, Vector2(w, h)), bg)
	if _charge > 0.0:
		var glow: Color = Color(1.0, 0.82, 0.32, 0.95) if _charge >= 1.0 else Color(0.55, 0.78, 1.0, 0.9)
		_control.draw_rect(Rect2(pos, Vector2(w * _charge, h)), glow)
	_control.draw_rect(Rect2(pos, Vector2(w, h)), Color(1, 1, 1, 0.18), false, 1.0)


## Red screen-edge tint from two independent sources: the fading flash of a
## recent hit, and a steady pulse while below a third of maximum hearts. The
## stronger of the two wins, so a hit taken at low health doesn't stack into
## an opaque screen. Drawn as four edge bands rather than a real radial
## gradient — no shader, and at this opacity the difference doesn't read.
func _draw_damage_vignette(screen: Vector2) -> void:
	var low: float = 0.0
	# Not while downed (hearts == 0): the come-apart has its own feedback.
	if _hearts_max > 0.0 and (_hearts / _hearts_max) <= 0.34 and _hearts > 0.0:
		low = 0.18 + 0.10 * sin(Time.get_ticks_msec() * 0.006)
	var a: float = maxf(_vignette * 0.30, low)
	if a <= 0.001:
		return
	var col: Color = Color(0.75, 0.05, 0.08, a)
	var band: float = 90.0
	# Four edge bands (cheap vignette without a shader).
	_control.draw_rect(Rect2(Vector2.ZERO, Vector2(screen.x, band)), col)
	_control.draw_rect(Rect2(Vector2(0.0, screen.y - band), Vector2(screen.x, band)), col)
	_control.draw_rect(Rect2(Vector2.ZERO, Vector2(band, screen.y)), col)
	_control.draw_rect(Rect2(Vector2(screen.x - band, 0.0), Vector2(band, screen.y)), col)

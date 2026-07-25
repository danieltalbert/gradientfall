class_name CombatHud
extends CanvasLayer
## A deliberately small field read-out: a heart row (half-heart aware), a focus
## (knowledge-charge) sliver, a damage vignette, the Token purse, and the pickup
## toasts. It exists so Combat v1 and the pack are actually playable/verifiable —
## the full HUD (hearts + Tokens + minimap) is its own later ROADMAP milestone
## and will supersede this v0. Everything is drawn in code (no textures), reading
## only EventBus signals.

const HEART_SIZE: float = 22.0
const HEART_GAP: float = 8.0
const MARGIN: Vector2 = Vector2(26.0, 22.0)

# Token purse (top right) and the pickup toast column beneath it.
const PURSE_MARGIN: Vector2 = Vector2(30.0, 30.0)
const COIN_RADIUS: float = 11.0
const TOAST_LIFETIME: float = 3.4
const TOAST_FADE: float = 0.8
const TOAST_MAX: int = 5
const TOAST_LINE_HEIGHT: float = 24.0
const TOAST_FONT_SIZE: int = 17
const PURSE_FONT_SIZE: int = 20
const COIN_COLOR: Color = Color(1.0, 0.82, 0.35)

var _hearts: float = 3.0
var _hearts_max: float = 3.0
var _charge: float = 0.0
var _vignette: float = 0.0
var _tokens: int = 0
var _token_pulse: float = 0.0
## { text: String, color: Color, life: float }
var _toasts: Array[Dictionary] = []

var _control: Control
var _font: Font


func _ready() -> void:
	layer = 10
	_font = ThemeDB.fallback_font
	_tokens = GameState.tokens
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)
	EventBus.player_hearts_changed.connect(_on_hearts)
	EventBus.knowledge_charge_changed.connect(_on_charge)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.tokens_changed.connect(_on_tokens_changed)


func _process(delta: float) -> void:
	if _vignette > 0.0:
		_vignette = maxf(0.0, _vignette - delta * 1.6)
	if _token_pulse > 0.0:
		_token_pulse = maxf(0.0, _token_pulse - delta * 1.5)
	_age_toasts(delta)
	_control.queue_redraw()


func _on_hearts(current: float, max_hearts: float) -> void:
	_hearts = current
	_hearts_max = max_hearts


func _on_charge(fraction: float) -> void:
	_charge = fraction


func _on_player_hit(_amount: float) -> void:
	_vignette = 1.0


## Every acquisition announces itself — forage, drops, and quest rewards alike.
func _on_item_acquired(item_id: String, count: int) -> void:
	if count <= 0:
		return
	var entry: Dictionary = ContentDB.get_entry("items", item_id)
	var label: String = ItemStyle.display_name(item_id, entry)
	_push_toast("%s  ×%d" % [label, count], ItemStyle.rarity_color(entry))


func _on_tokens_changed(new_total: int) -> void:
	var delta: int = new_total - _tokens
	_tokens = new_total
	if delta > 0:
		_token_pulse = 1.0
		_push_toast("+%d Tokens" % delta, COIN_COLOR)


func _push_toast(text: String, color: Color) -> void:
	_toasts.append({"text": text, "color": color, "life": TOAST_LIFETIME})
	while _toasts.size() > TOAST_MAX:
		_toasts.pop_front()


func _age_toasts(delta: float) -> void:
	if _toasts.is_empty():
		return
	var alive: Array[Dictionary] = []
	for t: Dictionary in _toasts:
		var life: float = float(t["life"]) - delta
		if life <= 0.0:
			continue
		t["life"] = life
		alive.append(t)
	_toasts = alive


# --- Drawing -----------------------------------------------------------------

func _render() -> void:
	var screen: Vector2 = _control.get_viewport_rect().size
	_draw_damage_vignette(screen)
	_draw_hearts()
	_draw_focus()
	_draw_purse(screen)
	_draw_toasts(screen)


func _draw_hearts() -> void:
	var full: int = int(floor(_hearts + 0.001))
	var half: bool = (_hearts - float(full)) >= 0.5
	var total: int = int(ceil(_hearts_max))
	for i in total:
		var pos: Vector2 = MARGIN + Vector2(float(i) * (HEART_SIZE + HEART_GAP), 0.0)
		var state: int = 0
		if i < full:
			state = 2
		elif i == full and half:
			state = 1
		_draw_heart(pos, HEART_SIZE, state)


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


## A code-drawn coin and the running total, top right. Pulses when it grows.
func _draw_purse(screen: Vector2) -> void:
	if _font == null:
		return
	var text: String = str(_tokens)
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PURSE_FONT_SIZE).x
	var right: float = screen.x - PURSE_MARGIN.x
	var mid_y: float = PURSE_MARGIN.y + COIN_RADIUS
	var pulse: float = 1.0 + 0.22 * _token_pulse
	var coin_center: Vector2 = Vector2(right - width - 14.0 - COIN_RADIUS, mid_y)
	_control.draw_circle(coin_center, COIN_RADIUS * pulse, COIN_COLOR)
	_control.draw_circle(coin_center, COIN_RADIUS * 0.58 * pulse, COIN_COLOR.darkened(0.35))
	_control.draw_string(
		_font, Vector2(right - width, mid_y + PURSE_FONT_SIZE * 0.36), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, PURSE_FONT_SIZE, Color(1, 1, 1, 0.94)
	)


## Acquisition toasts stack under the purse and fade out oldest-first.
func _draw_toasts(screen: Vector2) -> void:
	if _font == null or _toasts.is_empty():
		return
	var top: float = PURSE_MARGIN.y + COIN_RADIUS * 2.0 + 16.0
	for i: int in _toasts.size():
		var t: Dictionary = _toasts[i]
		var life: float = float(t["life"])
		var alpha: float = clampf(life / TOAST_FADE, 0.0, 1.0)
		var text: String = String(t["text"])
		var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TOAST_FONT_SIZE).x
		var col: Color = t["color"]
		col.a = alpha
		_control.draw_string(
			_font,
			Vector2(screen.x - PURSE_MARGIN.x - width, top + float(i) * TOAST_LINE_HEIGHT),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, TOAST_FONT_SIZE, col
		)


func _draw_damage_vignette(screen: Vector2) -> void:
	var low: float = 0.0
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

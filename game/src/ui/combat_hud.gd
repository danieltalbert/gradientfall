class_name CombatHud
extends CanvasLayer
## A deliberately small combat read-out: a heart row (half-heart aware), a focus
## (knowledge-charge) sliver, and a damage vignette. It exists so Combat v1 is
## actually playable/verifiable — the full HUD (hearts + Tokens + minimap) is its
## own later ROADMAP milestone and will supersede this v0. Everything is drawn in
## code (no textures), reading only EventBus signals.

const HEART_SIZE: float = 22.0
const HEART_GAP: float = 8.0
const MARGIN: Vector2 = Vector2(26.0, 22.0)

var _hearts: float = 3.0
var _hearts_max: float = 3.0
var _charge: float = 0.0
var _vignette: float = 0.0

var _control: Control


func _ready() -> void:
	layer = 10
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)
	_control.draw.connect(_render)
	EventBus.player_hearts_changed.connect(_on_hearts)
	EventBus.knowledge_charge_changed.connect(_on_charge)
	EventBus.player_hit.connect(_on_player_hit)


func _process(delta: float) -> void:
	if _vignette > 0.0:
		_vignette = maxf(0.0, _vignette - delta * 1.6)
	_control.queue_redraw()


func _on_hearts(current: float, max_hearts: float) -> void:
	_hearts = current
	_hearts_max = max_hearts


func _on_charge(fraction: float) -> void:
	_charge = fraction


func _on_player_hit(_amount: float) -> void:
	_vignette = 1.0


# --- Drawing -----------------------------------------------------------------

func _render() -> void:
	var screen: Vector2 = _control.get_viewport_rect().size
	_draw_damage_vignette(screen)
	_draw_hearts()
	_draw_focus()


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

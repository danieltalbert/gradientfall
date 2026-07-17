class_name SkyCycle
extends Node
## Day/night cycle — Phase 1 milestone 4 (GDD §10: painterly sky with full
## day/night palette shifts).
##
## Drives the sun's arc plus a hand-authored color script across the day:
## dawn gold → bright noon → warm dusk → blue night. Sky gradient, sun color
## and energy, ambient, and fog all interpolate between keyframes, so the
## whole meadow changes mood as time passes. Deterministic given `hour`.

const DAY_LENGTH_DEFAULT: float = 300.0  # seconds for a full 24 h (look-dev)

## A moment in the color script.
class SkyKey:
	var hour: float
	var sky_top: Color
	var sky_horizon: Color
	var sun_color: Color
	var sun_energy: float
	var ambient: Color
	var ambient_energy: float
	var fog: Color

	func _init(h: float, st: Color, sh: Color, sc: Color, se: float,
			am: Color, ae: float, fg: Color) -> void:
		hour = h
		sky_top = st
		sky_horizon = sh
		sun_color = sc
		sun_energy = se
		ambient = am
		ambient_energy = ae
		fog = fg

@export var paused: bool = false
@export_range(0.0, 24.0) var hour: float = 8.0
@export var day_length: float = DAY_LENGTH_DEFAULT

var _keys: Array[SkyKey] = []
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial


func _ready() -> void:
	_sun = get_node("../../Sun") as DirectionalLight3D
	var we: WorldEnvironment = get_node("../../WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
		_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	_build_keys()
	_apply(hour)


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply(hour)


func _process(delta: float) -> void:
	if paused or day_length <= 0.0:
		return
	hour = fposmod(hour + delta * (24.0 / day_length), 24.0)
	_apply(hour)


func _build_keys() -> void:
	# hour, sky_top, sky_horizon, sun_color, sun_energy, ambient, amb_energy, fog
	_keys = [
		SkyKey.new(0.0, Color(0.03, 0.04, 0.12), Color(0.08, 0.09, 0.2),
			Color(0.35, 0.4, 0.7), 0.06, Color(0.12, 0.16, 0.32), 0.32, Color(0.1, 0.12, 0.24)),
		SkyKey.new(6.0, Color(0.28, 0.34, 0.55), Color(0.85, 0.6, 0.42),
			Color(1.0, 0.72, 0.5), 0.9, Color(0.5, 0.5, 0.62), 0.9, Color(0.78, 0.68, 0.66)),
		SkyKey.new(9.0, Color(0.26, 0.5, 0.86), Color(0.7, 0.83, 0.93),
			Color(1.0, 0.95, 0.82), 1.45, Color(0.7, 0.78, 0.9), 1.0, Color(0.72, 0.82, 0.9)),
		SkyKey.new(13.0, Color(0.22, 0.47, 0.9), Color(0.74, 0.85, 0.96),
			Color(1.0, 0.98, 0.92), 1.6, Color(0.75, 0.82, 0.95), 1.05, Color(0.74, 0.84, 0.93)),
		SkyKey.new(17.5, Color(0.34, 0.4, 0.66), Color(0.95, 0.62, 0.36),
			Color(1.0, 0.66, 0.4), 1.1, Color(0.6, 0.54, 0.58), 0.9, Color(0.86, 0.66, 0.6)),
		SkyKey.new(19.5, Color(0.15, 0.16, 0.36), Color(0.62, 0.36, 0.4),
			Color(0.9, 0.5, 0.42), 0.4, Color(0.3, 0.3, 0.46), 0.7, Color(0.4, 0.3, 0.42)),
		SkyKey.new(21.5, Color(0.05, 0.06, 0.16), Color(0.12, 0.12, 0.26),
			Color(0.4, 0.45, 0.72), 0.09, Color(0.13, 0.17, 0.34), 0.36, Color(0.12, 0.14, 0.26)),
	]


func _sample(h: float) -> SkyKey:
	var a: SkyKey = _keys[_keys.size() - 1]
	var b: SkyKey = _keys[0]
	var span: float = 24.0
	var base: float = a.hour - 24.0
	for i in _keys.size():
		var k: SkyKey = _keys[i]
		if h < k.hour:
			b = k
			a = _keys[(i - 1 + _keys.size()) % _keys.size()]
			base = a.hour if i > 0 else a.hour - 24.0
			span = b.hour - base
			break
		if i == _keys.size() - 1:
			a = k
			b = _keys[0]
			base = a.hour
			span = (b.hour + 24.0) - base
	var t: float = clampf((h - base) / maxf(span, 0.001), 0.0, 1.0)
	t = smoothstep(0.0, 1.0, t)
	var out: SkyKey = SkyKey.new(h,
		a.sky_top.lerp(b.sky_top, t), a.sky_horizon.lerp(b.sky_horizon, t),
		a.sun_color.lerp(b.sun_color, t), lerpf(a.sun_energy, b.sun_energy, t),
		a.ambient.lerp(b.ambient, t), lerpf(a.ambient_energy, b.ambient_energy, t),
		a.fog.lerp(b.fog, t))
	return out


func _apply(h: float) -> void:
	var k: SkyKey = _sample(h)
	# Sun arc: east at dawn, high at noon, west at dusk, below at night.
	var elev: float = sin((h - 6.0) / 12.0 * PI)  # -1 midnight … 1 noon
	var pitch: float = deg_to_rad(lerpf(6.0, -82.0, clampf(elev * 0.5 + 0.5, 0.0, 1.0)))
	var yaw: float = deg_to_rad(lerpf(70.0, -70.0, clampf(h / 24.0, 0.0, 1.0)))
	if _sun != null:
		_sun.rotation = Vector3(pitch, yaw, 0.0)
		_sun.light_color = k.sun_color
		_sun.light_energy = k.sun_energy
		_sun.shadow_enabled = k.sun_energy > 0.2
	if _sky_mat != null:
		_sky_mat.sky_top_color = k.sky_top
		_sky_mat.sky_horizon_color = k.sky_horizon
		_sky_mat.ground_horizon_color = k.sky_horizon.darkened(0.15)
	if _env != null:
		_env.ambient_light_color = k.ambient
		_env.ambient_light_energy = k.ambient_energy
		_env.fog_light_color = k.fog

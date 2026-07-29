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
const VOLUMETRIC_SKY_SHADER: Shader = preload("res://assets/shaders/volumetric_sky.gdshader")

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
var _moon_light: DirectionalLight3D
var _env: Environment
var _vol_sky_mat: ShaderMaterial


func _ready() -> void:
	_sun = get_node("../../Sun") as DirectionalLight3D
	_moon_light = get_node_or_null("../../MoonLight") as DirectionalLight3D
	var we: WorldEnvironment = get_node("../../WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
		# Swap the placeholder gradient sky for the volumetric cloud sky at
		# runtime, so main.tscn is left untouched (the grass/mountain sessions
		# edit that scene too). Only the sky RENDER changes; the sun/moon/
		# ambient/fog driven below are identical to before, so scene lighting is
		# unchanged and the vistas still meet the same horizon colour.
		if _env.sky != null:
			_vol_sky_mat = ShaderMaterial.new()
			_vol_sky_mat.shader = VOLUMETRIC_SKY_SHADER
			_env.sky.sky_material = _vol_sky_mat
			# Animated radiance so the new sky reflects in the water. REALTIME
			# requires a 256 radiance map; the shader's AT_CUBEMAP_PASS branch
			# keeps that per-frame cubemap render cheap (no cloud march).
			_env.sky.radiance_size = Sky.RADIANCE_SIZE_256
			_env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_build_keys()
	_apply(hour)


## The volumetric sky material. CloudLayer writes the weather-side uniforms
## (coverage, wind, density, layer heights, detail); this node owns the
## time-of-day atmosphere uniforms. The two write disjoint parameter sets.
func get_sky_material() -> ShaderMaterial:
	return _vol_sky_mat


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
		SkyKey.new(0.0, Color(0.022, 0.035, 0.105), Color(0.07, 0.105, 0.22),
			Color(0.34, 0.43, 0.76), 0.055, Color(0.21, 0.24, 0.34), 0.60, Color(0.075, 0.10, 0.20)),
		SkyKey.new(5.5, Color(0.10, 0.16, 0.36), Color(0.96, 0.39, 0.18),
			Color(1.0, 0.56, 0.28), 0.55, Color(0.29, 0.25, 0.25), 0.42, Color(0.38, 0.25, 0.25)),
		SkyKey.new(6.5, Color(0.12, 0.27, 0.55), Color(1.0, 0.58, 0.27),
			Color(1.0, 0.68, 0.38), 1.15, Color(0.34, 0.34, 0.30), 0.47, Color(0.46, 0.36, 0.34)),
		SkyKey.new(9.0, Color(0.08, 0.34, 0.72), Color(0.48, 0.68, 0.82),
			Color(1.0, 0.84, 0.58), 1.38, Color(0.34, 0.38, 0.33), 0.48, Color(0.38, 0.48, 0.52)),
		SkyKey.new(13.0, Color(0.055, 0.30, 0.69), Color(0.44, 0.65, 0.80),
			Color(1.0, 0.92, 0.70), 1.48, Color(0.35, 0.39, 0.34), 0.50, Color(0.38, 0.47, 0.50)),
		SkyKey.new(17.5, Color(0.10, 0.17, 0.40), Color(0.82, 0.30, 0.12),
			Color(1.0, 0.48, 0.20), 1.10, Color(0.31, 0.25, 0.23), 0.42, Color(0.40, 0.24, 0.22)),
		SkyKey.new(19.5, Color(0.055, 0.065, 0.19), Color(0.42, 0.15, 0.22),
			Color(0.82, 0.32, 0.25), 0.24, Color(0.20, 0.18, 0.24), 0.34, Color(0.19, 0.13, 0.20)),
		SkyKey.new(21.5, Color(0.022, 0.036, 0.11), Color(0.07, 0.105, 0.22),
			Color(0.36, 0.45, 0.78), 0.06, Color(0.21, 0.24, 0.35), 0.58, Color(0.075, 0.105, 0.21)),
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
	# BOTW-like nights remain traversable and dimensional. A separate cool
	# directional source behaves as moonlight instead of asking a near-zero
	# below-horizon sun to carry every shadowed material.
	var day_amount: float = smoothstep(5.4, 7.2, h) * (1.0 - smoothstep(18.2, 20.4, h))
	var moon_amount: float = 1.0 - day_amount
	if _moon_light != null:
		_moon_light.rotation = Vector3(
			deg_to_rad(-46.0 + sin(h * 0.24) * 6.0),
			deg_to_rad(28.0 + h * 2.2),
			0.0
		)
		_moon_light.light_energy = moon_amount * 0.42
		_moon_light.shadow_enabled = moon_amount > 0.42
	if _vol_sky_mat != null:
		_vol_sky_mat.set_shader_parameter("sky_top_color", k.sky_top)
		_vol_sky_mat.set_shader_parameter("sky_horizon_color", k.sky_horizon)
		_vol_sky_mat.set_shader_parameter("ground_color", k.ambient.darkened(0.55))
		if _sun != null:
			# DirectionalLight3D shines along -Z; +Z of its basis points AT the sun.
			_vol_sky_mat.set_shader_parameter("sun_direction", _sun.global_transform.basis.z)
			_vol_sky_mat.set_shader_parameter("sun_color", k.sun_color)
			_vol_sky_mat.set_shader_parameter("sun_energy", k.sun_energy)
		if _moon_light != null:
			_vol_sky_mat.set_shader_parameter("moon_direction", _moon_light.global_transform.basis.z)
			_vol_sky_mat.set_shader_parameter("moon_color", _moon_light.light_color)
			_vol_sky_mat.set_shader_parameter("moon_energy", _moon_light.light_energy)
		_vol_sky_mat.set_shader_parameter("day_amount", day_amount)
		# Dawn/dusk thicken the horizon haze; clear noon thins it.
		var warm: float = maxf(
			maxf(0.0, 1.0 - absf(h - 6.25) / 2.0),
			maxf(0.0, 1.0 - absf(h - 18.15) / 2.2)
		)
		_vol_sky_mat.set_shader_parameter("haze_strength", clampf(0.42 + warm * 0.34, 0.0, 1.0))
	if _env != null:
		_env.ambient_light_color = k.ambient
		_env.ambient_light_energy = k.ambient_energy
		_env.ambient_light_sky_contribution = 0.0
		_env.fog_light_color = k.fog
		_env.volumetric_fog_albedo = k.fog.lightened(0.08)

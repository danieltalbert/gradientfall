class_name CloudLayer
extends Node3D
## Weather director for the volumetric raymarched sky.
##
## The old mesh cloud banks are retired: clouds now live INSIDE the sky shader
## (assets/shaders/volumetric_sky.gdshader) as a true volumetric layer between
## ~600 m and ~1700 m, raymarched to a life-sized horizon. This node's job is
## the WEATHER — it owns the shader's weather-side uniforms (coverage, wind,
## density, layer heights, storminess, cirrus) and evolves them over the day,
## while SkyCycle owns the atmosphere/time-of-day side. The two write disjoint
## uniform sets, so there are no races between them.
##
## Weather is deterministic in SkyCycle.hour: screenshot mode pauses the cycle
## and therefore freezes the weather, keeping visual-verification shots
## reproducible. In play, the same hour always brings the same sky mood — a
## daily rhythm (clear dawns, convective afternoons, streaked evening cirrus)
## with noise-driven fronts layered on top.
##
## The future Phase 2 weather-system milestone should drive this node through
## set_weather_override() instead of poking shader uniforms directly.

const WEATHER_SEED: float = 20260720.0

## Baseline fair-weather numbers for the Datasedge Meadows.
const BASE_COVERAGE: float = 0.46
const BASE_DENSITY: float = 1.35
const BASE_WIND_SPEED: float = 30.0
const CLOUD_BASE_M: float = 620.0
const CLOUD_TOP_M: float = 1680.0

var _cycle: SkyCycle
var _sky_material: ShaderMaterial
var _announced: bool = false

## Optional override from gameplay/weather systems: -1 means "not overridden".
var _coverage_override: float = -1.0
var _storminess_override: float = -1.0


func _ready() -> void:
	_cycle = get_node_or_null("../SkyCycle") as SkyCycle
	# SkyCycle (an earlier sibling) has already built the sky material by now,
	# but stay defensive and re-check in _process until it exists.
	_try_bind()


func _process(_delta: float) -> void:
	if _sky_material == null:
		_try_bind()
		if _sky_material == null:
			return
	var hour: float = _cycle.hour if _cycle != null else 12.0
	_apply_weather(hour)


func _try_bind() -> void:
	if _cycle != null:
		_sky_material = _cycle.get_sky_material()
	if _sky_material != null and not _announced:
		_announced = true
		print("CloudLayer: volumetric sky online — raymarched cloud deck %d–%d m, weather deterministic in hour." % [
			int(CLOUD_BASE_M), int(CLOUD_TOP_M),
		])


## Gameplay hook (quests, the Phase 2 weather system): force a sky mood.
## Values clamp to [0,1]; pass -1.0 to release a channel back to the daily model.
func set_weather_override(coverage: float, storminess: float) -> void:
	_coverage_override = clampf(coverage, -1.0, 1.0)
	_storminess_override = clampf(storminess, -1.0, 1.0)


func clear_weather_override() -> void:
	_coverage_override = -1.0
	_storminess_override = -1.0


## Deterministic 1D fractal noise in [0,1] — smooth, cheap, no state.
func _weather_noise(x: float) -> float:
	var total: float = 0.0
	total += sin(x * 1.000 + WEATHER_SEED * 0.101) * 0.50
	total += sin(x * 2.130 + WEATHER_SEED * 0.317) * 0.26
	total += sin(x * 4.410 + WEATHER_SEED * 0.523) * 0.14
	total += sin(x * 8.870 + WEATHER_SEED * 0.771) * 0.10
	return clampf(total * 0.5 + 0.5, 0.0, 1.0)


func _apply_weather(hour: float) -> void:
	# --- Fronts: slow noise bands rolling through over multiple game-hours. ---
	var front: float = _weather_noise(hour * 0.55)          # broad pressure mood
	var gust_mood: float = _weather_noise(hour * 1.7 + 40.0) # faster texture mood

	# --- Diurnal convection: cumulus builds through the afternoon. ------------
	# Real fair-weather cumulus pops mid-morning, peaks mid-afternoon, and
	# decays after sunset as the ground stops heating.
	var convection: float = smoothstep(8.5, 14.5, hour) * (1.0 - smoothstep(17.5, 21.0, hour))

	var coverage: float = BASE_COVERAGE
	coverage += (front - 0.5) * 0.42          # fronts swing the whole deck
	coverage += convection * 0.14             # afternoon build
	coverage -= smoothstep(3.0, 6.0, hour) * (1.0 - smoothstep(6.0, 9.0, hour)) * 0.10  # clearer dawns
	coverage = clampf(coverage, 0.16, 0.86)

	# --- Storminess: rare, only when a strong front meets peak convection. ----
	var storminess: float = smoothstep(0.72, 0.95, front) * convection
	storminess = clampf(storminess, 0.0, 0.55)  # Phase 2's weather system owns real storms

	if _coverage_override >= 0.0:
		coverage = _coverage_override
	if _storminess_override >= 0.0:
		storminess = _storminess_override

	# --- Wind: veers slowly through the day, freshens with fronts. ------------
	var wind_angle: float = deg_to_rad(211.0) + (_weather_noise(hour * 0.31 + 9.0) - 0.5) * 1.15
	var wind_dir: Vector2 = Vector2(cos(wind_angle), sin(wind_angle))
	var wind_speed: float = BASE_WIND_SPEED * (0.75 + front * 0.55 + storminess * 0.6)

	# --- Vertical structure: storms drop the base and stretch the tops. -------
	var base_m: float = CLOUD_BASE_M - storminess * 140.0
	var top_m: float = CLOUD_TOP_M + storminess * 620.0 + convection * 160.0

	# --- Texture: crisper erosion on fair days, softer when overcast. ---------
	var detail: float = lerpf(0.68, 0.44, smoothstep(0.55, 0.85, coverage))
	var density: float = BASE_DENSITY * (1.0 + storminess * 0.9 + (coverage - BASE_COVERAGE) * 0.35)
	var shape_scale: float = lerpf(1.06, 0.84, maxf(storminess, coverage * 0.5))

	# --- Cirrus: streaked veils favour dawn/dusk and calm high-pressure days. -
	var twilight: float = maxf(
		maxf(0.0, 1.0 - absf(hour - 6.5) / 2.6),
		maxf(0.0, 1.0 - absf(hour - 17.8) / 2.8)
	)
	var cirrus: float = clampf(0.18 + twilight * 0.34 + (1.0 - front) * 0.22 + gust_mood * 0.08, 0.0, 0.85)

	_sky_material.set_shader_parameter("cloud_coverage", coverage)
	_sky_material.set_shader_parameter("cloud_density", density)
	_sky_material.set_shader_parameter("cloud_base", base_m)
	_sky_material.set_shader_parameter("cloud_top", top_m)
	_sky_material.set_shader_parameter("wind_dir", wind_dir)
	_sky_material.set_shader_parameter("wind_speed", wind_speed)
	_sky_material.set_shader_parameter("detail_strength", detail)
	_sky_material.set_shader_parameter("shape_scale", shape_scale)
	_sky_material.set_shader_parameter("cirrus_amount", cirrus)
	_sky_material.set_shader_parameter("storminess", storminess)

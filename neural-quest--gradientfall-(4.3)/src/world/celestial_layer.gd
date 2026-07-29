class_name CelestialLayer
extends Node3D
## Procedural night sky: star dome with a Milky Way band, a phase-correct moon
## that hangs where the scene's moonlight actually comes from, and occasional
## meteors. Follows the player horizontally so the dome never parallax-slides.

const FIELD_STAR_COUNT: int = 1150
const BAND_STAR_COUNT: int = 1450
const DOME_RADIUS: float = 430.0
const MOON_DISTANCE: float = 400.0
const METEOR_DISTANCE: float = 415.0
const METEOR_DURATION: float = 0.85

## The Milky Way great circle: stars cluster around the plane whose pole is
## this axis. Tilted so the band arcs high across the meadow's night sky.
const BAND_POLE: Vector3 = Vector3(0.55, 0.38, 0.74)

var _stars: MultiMeshInstance3D
var _star_material: ShaderMaterial
var _moon: MeshInstance3D
var _moon_material: ShaderMaterial
var _meteor: MeshInstance3D
var _meteor_material: ShaderMaterial
var _meteor_life: float = -1.0          # <0 idle, else 0..1 playing
var _meteor_wait: float = 14.0
var _meteor_rng: RandomNumberGenerator
var _cycle: SkyCycle
var _player: Node3D
var _sun: DirectionalLight3D
var _moon_light: DirectionalLight3D


func _ready() -> void:
	_cycle = get_node_or_null("../SkyCycle") as SkyCycle
	_player = get_node_or_null("../../Player") as Node3D
	_sun = get_node_or_null("../../Sun") as DirectionalLight3D
	_moon_light = get_node_or_null("../../MoonLight") as DirectionalLight3D
	_meteor_rng = RandomNumberGenerator.new()
	_meteor_rng.seed = 20260720
	_build_stars()
	_build_moon()
	_build_meteor()


func _process(delta: float) -> void:
	if _player != null:
		global_position = Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var h: float = _cycle.hour if _cycle != null else 12.0
	var evening: float = smoothstep(18.2, 20.8, h)
	var morning: float = 1.0 - smoothstep(4.4, 6.3, h)
	var night: float = clampf(maxf(evening, morning), 0.0, 1.0)
	_star_material.set_shader_parameter("visibility", night)
	_moon_material.set_shader_parameter("visibility", smoothstep(0.08, 0.65, night))
	_stars.rotation.y = Time.get_ticks_msec() * 0.0000035

	# The moon hangs on the axis the MoonLight shines FROM, so its light and
	# its disc always agree; the sun direction drives the visible phase.
	if _moon_light != null:
		var moon_dir: Vector3 = _moon_light.global_transform.basis.z.normalized()
		_moon.position = moon_dir * MOON_DISTANCE
	if _sun != null:
		_moon_material.set_shader_parameter("sun_dir_world", _sun.global_transform.basis.z)

	_update_meteor(delta, night)


func _build_stars() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_star_material = ShaderMaterial.new()
	_star_material.shader = load("res://assets/shaders/starfield.gdshader") as Shader
	quad.material = _star_material

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = FIELD_STAR_COUNT + BAND_STAR_COUNT
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026071709

	# Sparse bright field stars across the whole dome.
	for i in FIELD_STAR_COUNT:
		var azimuth: float = rng.randf_range(0.0, TAU)
		var elevation: float = asin(rng.randf_range(0.12, 0.98))
		var ring: float = cos(elevation) * DOME_RADIUS
		var pos: Vector3 = Vector3(cos(azimuth) * ring, sin(elevation) * DOME_RADIUS,
			sin(azimuth) * ring)
		var size: float = rng.randf_range(0.42, 1.08)
		if rng.randf() < 0.06:
			size *= 1.85
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, size, size)), pos))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 1.0))

	# The Milky Way: many small faint stars gaussian-clustered on a tilted
	# great circle, densest near the "galactic core" stretch of the band.
	var pole: Vector3 = BAND_POLE.normalized()
	var axis_a: Vector3 = pole.cross(Vector3.UP).normalized()
	if axis_a.length_squared() < 0.01:
		axis_a = pole.cross(Vector3.RIGHT).normalized()
	var axis_b: Vector3 = pole.cross(axis_a).normalized()
	var placed: int = 0
	while placed < BAND_STAR_COUNT:
		var t: float = rng.randf_range(0.0, TAU)
		# Bias density toward one stretch of the circle — the bright core.
		if rng.randf() > 0.45 + 0.55 * (0.5 + 0.5 * cos(t - 1.1)):
			continue
		var spread: float = rng.randfn(0.0, 0.15)
		var dir: Vector3 = (axis_a * cos(t) + axis_b * sin(t) + pole * spread).normalized()
		if dir.y < 0.10:
			continue  # keep the band above the horizon haze
		var pos2: Vector3 = dir * DOME_RADIUS
		# Nearer the plane = fainter and finer, so the band reads as dust.
		var closeness: float = clampf(1.0 - absf(spread) * 5.0, 0.0, 1.0)
		var size2: float = rng.randf_range(0.16, 0.42) + closeness * rng.randf_range(0.0, 0.18)
		if rng.randf() < 0.02:
			size2 *= 2.1  # a few genuine stars riding the band
		var index: int = FIELD_STAR_COUNT + placed
		mm.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(size2, size2, size2)), pos2))
		mm.set_instance_custom_data(index, Color(rng.randf(), 0.0, 0.0, 1.0))
		placed += 1

	_stars = MultiMeshInstance3D.new()
	_stars.name = "Stars"
	_stars.multimesh = mm
	_stars.visibility_range_end = 1000.0
	_stars.custom_aabb = AABB(Vector3(-460.0, -20.0, -460.0), Vector3(920.0, 500.0, 920.0))
	add_child(_stars)


func _build_moon() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(30.0, 30.0)
	_moon_material = ShaderMaterial.new()
	_moon_material.shader = load("res://assets/shaders/moon.gdshader") as Shader
	quad.material = _moon_material
	_moon = MeshInstance3D.new()
	_moon.name = "Moon"
	_moon.mesh = quad
	_moon.position = Vector3(520.0, 175.0, 505.0)  # re-aimed every frame
	add_child(_moon)


func _build_meteor() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(64.0, 1.7)
	_meteor_material = ShaderMaterial.new()
	_meteor_material.shader = load("res://assets/shaders/shooting_star.gdshader") as Shader
	quad.material = _meteor_material
	_meteor = MeshInstance3D.new()
	_meteor.name = "Meteor"
	_meteor.mesh = quad
	_meteor.visible = false
	add_child(_meteor)


func _update_meteor(delta: float, night: float) -> void:
	if _meteor_life >= 0.0:
		_meteor_life += delta / METEOR_DURATION
		if _meteor_life >= 1.0:
			_meteor_life = -1.0
			_meteor.visible = false
			_meteor_wait = _meteor_rng.randf_range(18.0, 70.0)
		else:
			_meteor_material.set_shader_parameter("life", _meteor_life)
		return
	if night < 0.55:
		return
	_meteor_wait -= delta
	if _meteor_wait > 0.0:
		return
	# Launch: pick a high sky point and a tangent flight line across it.
	var azimuth: float = _meteor_rng.randf_range(0.0, TAU)
	var elevation: float = _meteor_rng.randf_range(0.55, 1.15)
	var radial: Vector3 = Vector3(
		cos(azimuth) * cos(elevation), sin(elevation), sin(azimuth) * cos(elevation)
	)
	var swing: float = _meteor_rng.randf_range(0.0, TAU)
	var tangent_seed: Vector3 = Vector3(cos(swing), _meteor_rng.randf_range(-0.4, -0.05), sin(swing))
	var travel: Vector3 = (tangent_seed - radial * tangent_seed.dot(radial)).normalized()
	var normal: Vector3 = -radial  # face the dome centre / camera
	var side: Vector3 = normal.cross(travel).normalized()
	_meteor.transform = Transform3D(
		Basis(travel, side, normal), radial * METEOR_DISTANCE
	)
	_meteor.visible = true
	_meteor_life = 0.0
	_meteor_material.set_shader_parameter("life", 0.0)

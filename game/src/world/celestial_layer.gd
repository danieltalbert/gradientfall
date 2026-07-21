class_name CelestialLayer
extends Node3D
## Procedural moon and star dome for the complete day/night color script.

const STAR_COUNT: int = 920
const DOME_RADIUS: float = 430.0

var _stars: MultiMeshInstance3D
var _star_material: ShaderMaterial
var _moon: MeshInstance3D
var _moon_material: ShaderMaterial
var _cycle: SkyCycle
var _player: Node3D


func _ready() -> void:
	_cycle = get_node_or_null("../SkyCycle") as SkyCycle
	_player = get_node_or_null("../../Player") as Node3D
	_build_stars()
	_build_moon()


func _process(_delta: float) -> void:
	if _player != null:
		global_position = Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var h: float = _cycle.hour if _cycle != null else 12.0
	var evening: float = smoothstep(18.2, 20.8, h)
	var morning: float = 1.0 - smoothstep(4.4, 6.3, h)
	var night: float = clampf(maxf(evening, morning), 0.0, 1.0)
	_star_material.set_shader_parameter("visibility", night)
	_moon_material.set_shader_parameter("visibility", smoothstep(0.08, 0.65, night))
	_stars.rotation.y = Time.get_ticks_msec() * 0.0000035


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
	mm.instance_count = STAR_COUNT
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026071709
	for i in STAR_COUNT:
		var azimuth: float = rng.randf_range(0.0, TAU)
		var elevation: float = asin(rng.randf_range(0.14, 0.98))
		var ring: float = cos(elevation) * DOME_RADIUS
		var pos: Vector3 = Vector3(cos(azimuth) * ring, sin(elevation) * DOME_RADIUS,
			sin(azimuth) * ring)
		var size: float = rng.randf_range(0.42, 1.08)
		if rng.randf() < 0.06:
			size *= 1.85
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, size, size)), pos))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 1.0))
	_stars = MultiMeshInstance3D.new()
	_stars.name = "Stars"
	_stars.multimesh = mm
	_stars.visibility_range_end = 1000.0
	_stars.custom_aabb = AABB(Vector3(-460.0, -20.0, -460.0), Vector3(920.0, 500.0, 920.0))
	add_child(_stars)


func _build_moon() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(38.0, 38.0)
	_moon_material = ShaderMaterial.new()
	_moon_material.shader = load("res://assets/shaders/moon.gdshader") as Shader
	quad.material = _moon_material
	_moon = MeshInstance3D.new()
	_moon.name = "Moon"
	_moon.mesh = quad
	# Low enough to enter the normal third-person sky band and far enough away
	# to sit behind the nearest cloud banks rather than behaving like a prop.
	_moon.position = Vector3(520.0, 175.0, 505.0)
	add_child(_moon)

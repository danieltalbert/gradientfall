class_name CloudLayer
extends Node3D
## Stylized cumulus layer (GDD §10: painterly sky). BOTW skies are never
## empty — soft cloud shapes drift, catch dawn/dusk color, and give the
## horizon depth. Each cloud is a merged puff-cluster of low-poly spheres on
## a shared unshaded material; the layer tints itself from the SkyCycle so
## clouds blush at dusk and go slate at night. Deterministic; slow drift
## with wraparound.

const CLOUD_SEED: int = 20260719
const CLOUD_COUNT: int = 16
const WRAP_X: float = 1000.0

var _mat: StandardMaterial3D
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _clouds: Array[MeshInstance3D] = []
var _cycle: SkyCycle


func _ready() -> void:
	_cycle = get_node_or_null("../SkyCycle") as SkyCycle
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color.WHITE
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = CLOUD_SEED
	for i in CLOUD_COUNT:
		var cloud: MeshInstance3D = MeshInstance3D.new()
		cloud.mesh = _build_cloud_mesh(rng)
		cloud.material_override = _mat
		cloud.position = Vector3(
			rng.randf_range(-WRAP_X, WRAP_X),
			rng.randf_range(240.0, 380.0),
			rng.randf_range(-900.0, 900.0)
		)
		var s: float = rng.randf_range(0.8, 2.4)
		cloud.scale = Vector3(s, s * 0.8, s)
		add_child(cloud)
		_clouds.append(cloud)
		_speeds.append(rng.randf_range(1.2, 3.0))
	print("CloudLayer: %d clouds adrift." % CLOUD_COUNT)


func _process(delta: float) -> void:
	for i in _clouds.size():
		var c: MeshInstance3D = _clouds[i]
		c.position.x += _speeds[i] * delta
		if c.position.x > WRAP_X:
			c.position.x = -WRAP_X
	if _cycle != null:
		# Day white → dusk blush → night slate, keyed off the sun's energy
		# and warmth so it needs no extra color script.
		var sun: DirectionalLight3D = get_node_or_null("../../Sun")
		if sun != null:
			var e: float = clampf(sun.light_energy / 1.6, 0.0, 1.0)
			var day: Color = Color(1.0, 1.0, 1.0)
			var warm: Color = Color(1.0, 0.82, 0.78)
			var night: Color = Color(0.2, 0.23, 0.34)
			var lit: Color = day.lerp(warm, clampf(1.0 - sun.light_color.b, 0.0, 1.0) * 1.4)
			_mat.albedo_color = night.lerp(lit, smoothstep(0.02, 0.5, e))


func _build_cloud_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var puffs: int = rng.randi_range(4, 7)
	var base_r: float = rng.randf_range(18.0, 30.0)
	for p in puffs:
		var puff: SphereMesh = SphereMesh.new()
		puff.radius = base_r * rng.randf_range(0.45, 1.0)
		puff.height = puff.radius * 1.1
		puff.radial_segments = 7
		puff.rings = 4
		var off: Vector3 = Vector3(
			rng.randf_range(-base_r * 1.6, base_r * 1.6),
			rng.randf_range(0.0, base_r * 0.5),
			rng.randf_range(-base_r * 0.7, base_r * 0.7)
		)
		st.append_from(puff, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(1.35, 0.62, 1.0)), off))
	return st.commit()

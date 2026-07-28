class_name Projectile
extends Area3D
## A ranged enemy's shot — a small glowing data-bolt that flies straight, hits
## Kern or the terrain, pops into shards, and expires. Built entirely in code
## and self-instanced by ranged enemies (no scene file), so it needs no .uid.
##
## Layer discipline: the bolt sits on no layer and only *watches* the player
## body and the world, so bolts never collide with each other or their caster.

var _dir: Vector3 = Vector3.FORWARD
var _speed: float = 14.0
var _damage: float = 0.5
var _life: float = 4.0
var _color: Color = Color(0.7, 0.45, 1.0)
var _spent: bool = false


static func spawn(host: Node, from_position: Vector3, dir: Vector3, speed: float,
		damage: float, color: Color) -> void:
	if host == null or not host.is_inside_tree():
		return
	var p: Projectile = Projectile.new()
	p._dir = dir.normalized()
	p._speed = speed
	p._damage = damage
	p._color = color
	host.add_child(p)
	p.global_position = from_position


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER | CombatLayers.WORLD
	monitoring = true
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.22
	shape.shape = sphere
	add_child(shape)
	_build_visual()
	body_entered.connect(_on_body_entered)


func _build_visual() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = _color.lightened(0.3)
	mat.emission_energy_multiplier = 4.0

	var core: MeshInstance3D = MeshInstance3D.new()
	var core_mesh: SphereMesh = SphereMesh.new()
	core_mesh.radius = 0.16
	core_mesh.height = 0.32
	core_mesh.radial_segments = 10
	core_mesh.rings = 5
	core.mesh = core_mesh
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	# A stretched tail selling motion.
	var tail_mat: StandardMaterial3D = mat.duplicate()
	tail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tail_mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.5)
	var tail: MeshInstance3D = MeshInstance3D.new()
	var tail_mesh: BoxMesh = BoxMesh.new()
	tail_mesh.size = Vector3(0.12, 0.12, 0.7)
	tail.mesh = tail_mesh
	tail.material_override = tail_mat
	tail.position = Vector3(0.0, 0.0, 0.35)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tail)

	var glow: OmniLight3D = OmniLight3D.new()
	glow.light_color = _color
	glow.light_energy = 1.6
	glow.omni_range = 3.0
	glow.shadow_enabled = false
	add_child(glow)

	# Orient the tail down-range, guarding the degenerate straight-up/down case.
	if _dir.length_squared() > 0.0001 and absf(_dir.normalized().dot(Vector3.UP)) < 0.99:
		look_at(global_position + _dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	global_position += _dir * _speed * delta
	_life -= delta
	if _life <= 0.0:
		_pop()


func _on_body_entered(body: Node) -> void:
	if _spent:
		return
	if body.is_in_group(&"player") and body.has_method(&"apply_hit"):
		body.apply_hit(_damage, global_position, 4.0)
	_pop()


func _pop() -> void:
	_spent = true
	monitoring = false
	DamageShards.burst(get_tree().current_scene, global_position, _color, 8, 3.5, 1.2, 0.8)
	queue_free()

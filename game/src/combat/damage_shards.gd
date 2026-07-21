class_name DamageShards
extends Node3D
## The canon "dissolved into shards" effect (WORLDBOOK Part IV: no gore — things
## come apart into data). A short-lived burst of little glowing cubes that fling
## out, tumble, fall under a light gravity, then shrink and fade. Pure code, no
## textures or particle materials, so it renders identically on any machine and
## is fully static-verifiable.
##
## Fire-and-forget: `DamageShards.burst(world, position, color)` spawns one that
## frees itself when the last shard has faded.

const GRAVITY: float = 14.0
const LIFETIME: float = 0.62
const DRAG: float = 1.8

var _shards: Array[Dictionary] = []
var _age: float = 0.0
var _max_life: float = LIFETIME
var _mat: StandardMaterial3D


static func burst(host: Node, world_position: Vector3, color: Color,
		count: int = 14, power: float = 5.0, up_bias: float = 2.2,
		scale_mul: float = 1.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var fx: DamageShards = DamageShards.new()
	host.add_child(fx)
	fx.global_position = world_position
	fx._spawn(color, count, power, up_bias, scale_mul)


func _spawn(color: Color, count: int, power: float, up_bias: float, scale_mul: float) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color.lightened(0.25)
	mat.emission_energy_multiplier = 2.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat = mat
	_max_life = LIFETIME * randf_range(0.85, 1.15)
	for i in count:
		var s: float = randf_range(0.055, 0.13) * scale_mul
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(s, s, s)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(randf_range(-0.12, 0.12), randf_range(0.0, 0.35), randf_range(-0.12, 0.12))
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(mi)
		var dir: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
		var vel: Vector3 = dir * power * randf_range(0.6, 1.3) + Vector3.UP * up_bias
		var angvel: Vector3 = Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		_shards.append({"node": mi, "vel": vel, "angvel": angvel, "base": s})


func _process(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / _max_life, 0.0, 1.0)
	var fade: float = 1.0 - t
	if _mat != null:
		_mat.albedo_color.a = fade
	for shard: Dictionary in _shards:
		var mi: MeshInstance3D = shard["node"]
		var vel: Vector3 = shard["vel"]
		vel.y -= GRAVITY * delta
		vel = vel.lerp(Vector3.ZERO, 1.0 - exp(-DRAG * delta))
		shard["vel"] = vel
		mi.position += vel * delta
		mi.rotation += (shard["angvel"] as Vector3) * delta
		mi.scale = Vector3.ONE * (0.35 + fade * 0.65)
	if _age >= _max_life:
		queue_free()

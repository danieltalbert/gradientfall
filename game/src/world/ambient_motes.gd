class_name AmbientMotes
extends GPUParticles3D
## Drifting pollen/dust motes around the player (GDD §10: drifting particles).
## The quiet magic trick of BOTW's fields — the air itself has depth. A box
## of tiny billboard specks follows Kern; they catch the light warmly by day
## and read as fireflies after dark, which suits the meadow either way.


func _ready() -> void:
	amount = 240
	lifetime = 9.0
	preprocess = 5.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-40.0, -12.0, -40.0), Vector3(80.0, 26.0, 80.0))

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28.0, 8.0, 28.0)
	pm.gravity = Vector3(0.0, -0.02, 0.0)
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.direction = Vector3(1.0, 0.15, 0.3)
	pm.spread = 180.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	process_material = pm

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.95, 0.72, 0.32)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 0.6
	quad.material = mat
	draw_pass_1 = quad


func _process(_delta: float) -> void:
	var player: Node3D = get_node_or_null("../../Player")
	if player != null:
		global_position = player.global_position + Vector3(0.0, 3.0, 0.0)

class_name AmbientMotes
extends GPUParticles3D
## Drifting pollen/dust motes around the player (GDD §10: drifting particles).
## The quiet magic trick of BOTW's fields — the air itself has depth. A box
## of tiny billboard specks follows Kern; they catch the light warmly by day
## and read as fireflies after dark, which suits the meadow either way.
##
## Sits at Main/World/Motes (main.tscn) and is configured entirely in code —
## the scene node carries no inspector settings. Each frame the emitter
## recenters on ../../Player so the volume travels with Kern; because
## `local_coords` is false, particles already in the air stay put in world
## space and Kern walks through them instead of dragging them along.
## Distances are meters, times are seconds.


## Configure the emitter, its process material, and the billboard draw pass.
func _ready() -> void:
	amount = 240
	lifetime = 9.0
	# Warm the simulation 5 s before the first frame so the air is already
	# full of motes at spawn instead of filling in as the player watches.
	preprocess = 5.0
	# World-space particles: the emitter box follows Kern, but the specks it
	# already released hang in the air rather than sliding with him.
	local_coords = false
	# Manual bounds — the emitter moves every frame and particles live in
	# world space, so automatic culling bounds would be wrong.
	visibility_aabb = AABB(Vector3(-40.0, -12.0, -40.0), Vector3(80.0, 26.0, 80.0))

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	# 56 x 16 x 56 m box (extents are half-sizes) centered on the player.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28.0, 8.0, 28.0)
	# Barely-there downward pull (m/s²): motes settle over their 9 s life
	# instead of hanging perfectly still or falling like rain.
	pm.gravity = Vector3(0.0, -0.02, 0.0)
	# Drift speeds in m/s — slow enough to read as air movement, not sparks.
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	# A prevailing breeze direction, but 180° of spread means motes wander
	# every which way around it rather than streaming in formation.
	pm.direction = Vector3(1.0, 0.15, 0.3)
	pm.spread = 180.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	process_material = pm

	# 7.5 cm billboard specks; mote.gdshader handles the warm day glow and
	# the firefly look after dark.
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/mote.gdshader") as Shader
	quad.material = mat
	draw_pass_1 = quad


## Keep the emitter box centered on the player, lifted 3 m so the volume
## brackets Kern's head height rather than his feet. Resolved every frame
## (not cached) so the node works even if the player spawns late; null-safe
## for scenes with no player, such as screenshot mode.
func _process(_delta: float) -> void:
	var player: Node3D = get_node_or_null("../../Player")
	if player != null:
		global_position = player.global_position + Vector3(0.0, 3.0, 0.0)

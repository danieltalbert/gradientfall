class_name TownKit
extends RefCounted
## Shared code-art helpers for the Town of Bootstrap.
##
## Every building, prop, and villager in Bootstrap is generated from engine
## primitives at boot — no imported assets (ARCHITECTURE.md: world geometry,
## visual assets, and shaders are authored in code). Without this, the town's
## builder scripts would each re-roll the same toon material and
## MeshInstance3D boilerplate, so the shared pieces live here as statics.
##
## Lit props register themselves in two groups; BootstrapTown scans them once
## after the build and drives them from the day/night cycle.

const TOON_SHADER: String = "res://assets/shaders/toon.gdshader"

## Warm interior glow behind a window, and the lantern flame on a post.
const GROUP_WINDOW: StringName = &"town_window"
const GROUP_LAMP: StringName = &"town_lamp"


## The town's shared cel-shaded material. Bootstrap reads warmer than the
## meadow: a low sun-gold rim and a blue-violet shadow fill so painted shade
## sits against the grass instead of going black.
static func toon(color: Color, rim_amount: float = 0.26) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(TOON_SHADER) as Shader
	mat.set_shader_parameter("use_srgb_vertex", false)
	mat.set_shader_parameter("albedo_tint", color)
	mat.set_shader_parameter("rim_color", Color(1.0, 0.85, 0.62))
	mat.set_shader_parameter("rim_amount", rim_amount)
	mat.set_shader_parameter("rim_width", 0.72)
	mat.set_shader_parameter("shadow_fill", Color(0.44, 0.47, 0.6))
	mat.set_shader_parameter("fill_amount", 0.15)
	return mat


static func emissive(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## Unlit matte — eyes, ink, iron fittings: things that must read as dark even
## in the toon shader's lifted shadows.
static func flat(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func box(size: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	return m


static func cyl(top_radius: float, bottom_radius: float, height: float,
		segments: int = 10) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = bottom_radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func ball(radius: float, segments: int = 10, rings: int = 6) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m


static func prism(size: Vector3) -> PrismMesh:
	var m: PrismMesh = PrismMesh.new()
	m.size = size
	return m


## Adds one shaded mesh piece and returns it, so callers can keep animating it.
static func part(parent: Node3D, part_name: String, mesh: Mesh, pos: Vector3,
		mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Convenience for the common case: a toon-shaded box.
static func plank(parent: Node3D, part_name: String, size: Vector3, pos: Vector3,
		color: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return part(parent, part_name, box(size), pos, toon(color), rot)


static func collide_box(body: CollisionObject3D, size: Vector3, pos: Vector3,
		yaw: float = 0.0) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	col.rotation.y = yaw
	body.add_child(col)


## Dark glass by day, warm hearthlight by night — BootstrapTown drives the
## crossfade from the day/night cycle, and every pane joins GROUP_WINDOW so it
## can find them without wiring.
const GLASS_DAY: Color = Color(0.12, 0.14, 0.19)
const GLASS_NIGHT: Color = Color(1.0, 0.79, 0.44)
## Same crossfade for a lantern flame: cold soot by day, lit at dusk.
const FLAME_DAY: Color = Color(0.2, 0.18, 0.16)
const FLAME_NIGHT: Color = Color(1.0, 0.72, 0.34)


static func window_pane(parent: Node3D, part_name: String, size: Vector2,
		pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	var mat: StandardMaterial3D = emissive(GLASS_NIGHT, 0.0)
	mat.albedo_color = GLASS_DAY
	# The pane is a quad on a wall authored facing -Z, so its one face points
	# into the room. Draw both sides or the glass is invisible from the street.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = quad
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.add_to_group(GROUP_WINDOW)
	return mi


## A lantern flame plus the light it casts. Both sleep by day (BootstrapTown
## fades them in at dusk); the node returned is the flame mesh.
static func lantern(parent: Node3D, part_name: String, pos: Vector3,
		radius: float = 9.0) -> MeshInstance3D:
	var flame_mat: StandardMaterial3D = emissive(FLAME_NIGHT, 0.0)
	flame_mat.albedo_color = FLAME_DAY
	var flame: MeshInstance3D = part(parent, part_name, ball(0.08, 8, 5), pos, flame_mat)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light: OmniLight3D = OmniLight3D.new()
	light.name = part_name + "Light"
	light.position = pos
	light.light_color = Color(1.0, 0.76, 0.45)
	light.light_energy = 0.0
	light.omni_range = radius
	light.shadow_enabled = false
	parent.add_child(light)
	flame.add_to_group(GROUP_LAMP)
	light.add_to_group(GROUP_LAMP)
	return flame


## Chimney/forge smoke. Cheap, soft, and always drifting — GDD §10 asks that
## nothing in the world sit perfectly still.
static func smoke(rate: float, size: float, color: Color) -> GPUParticles3D:
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 0.0))
	ramp.set_offset(1, 0.25)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.5))
	ramp.add_point(1.0, Color(color.r, color.g, color.b, 0.0))
	var ramp_tex: GradientTexture1D = GradientTexture1D.new()
	ramp_tex.gradient = ramp

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3(0.15, 1.0, 0.05)
	process.spread = 12.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0.25, 0.35, 0.1)
	process.scale_min = size * 0.6
	process.scale_max = size * 1.4
	process.color_ramp = ramp_tex
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.35
	process.turbulence_noise_scale = 1.6

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var puff: StandardMaterial3D = StandardMaterial3D.new()
	puff.albedo_color = Color(1, 1, 1, 1)
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff.vertex_color_use_as_albedo = true

	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "Smoke"
	particles.amount = maxi(4, int(rate))
	particles.lifetime = 4.5
	particles.draw_pass_1 = quad
	particles.material_override = puff
	particles.process_material = process
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## Deterministic per-name RNG, so a villager or house keeps the same palette
## across every boot (the world seed is fixed; nothing in the town is random
## between sessions).
static func rng_for(key: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng

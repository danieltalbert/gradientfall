class_name EnemyVisual
extends Node3D
## Code-built, cel-shaded monster bodies â€” silhouette-first per GDD Â§10, no
## imported assets. One generator dresses every Datasedge foe by BEHAVIOR:
##   * swarm   â†’ a Stray Glitchling: a knee-high wobble of mismatched pixel-cubes
##   * melee   â†’ a heavier bruiser with horn spikes
##   * ranged  â†’ a floating single-eyed "watcher" with a lens ring
##   * dummy   â†’ a straw sparring post (no wobble; a safe hit-test target)
## Variants (golden / night) recolor and brighten. The visual owns two combat
## tells the AI drives: a white HIT flash and a warm TELEGRAPH glow before a
## strike â€” both animate the shared toon shader's albedo tint.

const TOON_SHADER: String = "res://assets/shaders/toon.gdshader"

var height: float = 0.9   ## approx top, for the health-aim / label offset

var _parts: Array[Dictionary] = []   ## { mi, base:Color, mat:ShaderMaterial, offset:Vector3, jitter:float }
var _behavior: String = "swarm"
var _wobble: float = 0.0
var _flash: float = 0.0
var _telegraph: float = 0.0
var _seed: float = 0.0


func setup(behavior: String, base_color: Color, accent: Color, size: float,
		variant: String = "") -> void:
	_behavior = behavior
	_seed = randf() * TAU
	var b: Color = base_color
	var a: Color = accent
	var eye_glow: float = 3.0
	if variant == "golden":
		b = Color(0.95, 0.78, 0.24)
		a = Color(1.0, 0.9, 0.5)
		eye_glow = 4.0
	elif variant == "night":
		b = base_color.darkened(0.45)
		a = accent.darkened(0.3)
		eye_glow = 5.0
	match behavior:
		"melee":
			_build_bruiser(b, a, size, eye_glow)
		"ranged":
			_build_watcher(b, a, size, eye_glow)
		"dummy":
			_build_dummy()
		_:
			_build_glitchling(b, a, size, eye_glow)


func _process(delta: float) -> void:
	_wobble += delta
	_flash = maxf(0.0, _flash - delta * 6.0)
	# Cubes jitter in place â€” the "mismatched pixels" read. Dummies stay still.
	if _behavior != "dummy":
		for p: Dictionary in _parts:
			var jit: float = p["jitter"]
			if jit > 0.0:
				var mi: MeshInstance3D = p["node"]
				var o: Vector3 = p["offset"]
				mi.position = o + Vector3(
					sin(_wobble * 9.0 + o.x * 12.0), sin(_wobble * 11.0 + o.y * 9.0),
					cos(_wobble * 10.0 + o.z * 11.0)) * jit
	# Drive flash (white) + telegraph (warm) onto each part's tint.
	for p: Dictionary in _parts:
		var base: Color = p["base"]
		var tint: Color = base.lerp(Color(1, 1, 1), _flash)
		if _telegraph > 0.0:
			tint = tint.lerp(Color(1.0, 0.55, 0.3), _telegraph * 0.55)
		(p["mat"] as ShaderMaterial).set_shader_parameter("albedo_tint", tint)


func flash() -> void:
	_flash = 1.0


func set_telegraph(amount: float) -> void:
	_telegraph = clampf(amount, 0.0, 1.0)


# --- Body styles -------------------------------------------------------------

func _build_glitchling(base: Color, accent: Color, size: float, eye_glow: float) -> void:
	height = 0.9 * size
	var core: SphereMesh = SphereMesh.new()
	core.radius = 0.26 * size
	core.height = 0.5 * size
	core.radial_segments = 10
	core.rings = 6
	_part("Core", core, Vector3(0.0, 0.5 * size, 0.0), base, 0.0)
	# Mismatched pixel-cubes clustered around the core.
	var n: int = 7
	for i in n:
		var ang: float = TAU * float(i) / float(n) + _seed
		var r: float = 0.24 * size
		var off: Vector3 = Vector3(cos(ang) * r, 0.5 * size + sin(ang * 1.7) * 0.16 * size, sin(ang) * r)
		var c: BoxMesh = BoxMesh.new()
		var cs: float = randf_range(0.1, 0.19) * size
		c.size = Vector3(cs, cs, cs)
		var tint: Color = base.lerp(accent, randf()) if (i % 2 == 0) else accent.lerp(base, randf())
		_part("Pixel%d" % i, c, off, tint, 0.03 * size)
	_legs(size, base.darkened(0.25))
	_eyes(Vector3(0.0, 0.56 * size, -0.24 * size), 0.05 * size, 0.11 * size, eye_glow)


func _build_bruiser(base: Color, accent: Color, size: float, eye_glow: float) -> void:
	var s: float = size * 1.35
	height = 1.15 * s
	var body: SphereMesh = SphereMesh.new()
	body.radius = 0.36 * s
	body.height = 0.78 * s
	body.radial_segments = 12
	body.rings = 7
	_part("Body", body, Vector3(0.0, 0.62 * s, 0.0), base, 0.0)
	# Angry cube pauldrons.
	for sx: int in [-1, 1]:
		var pad: BoxMesh = BoxMesh.new()
		pad.size = Vector3(0.22 * s, 0.16 * s, 0.22 * s)
		_part("Pauldron%d" % sx, pad, Vector3(0.34 * s * sx, 0.86 * s, 0.0), accent, 0.012 * s)
	# Horn spikes (silhouette).
	for sx: int in [-1, 1]:
		var horn: CylinderMesh = CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.08 * s
		horn.height = 0.34 * s
		horn.radial_segments = 7
		var mi: MeshInstance3D = _part("Horn%d" % sx, horn, Vector3(0.15 * s * sx, 1.02 * s, -0.05 * s),
			Color(0.92, 0.9, 0.85), 0.0)
		mi.rotation = Vector3(-0.3, 0.0, 0.35 * sx)
	_legs(s, base.darkened(0.3))
	_eyes(Vector3(0.0, 0.72 * s, -0.34 * s), 0.06 * s, 0.16 * s, eye_glow)


func _build_watcher(base: Color, accent: Color, size: float, eye_glow: float) -> void:
	var s: float = size
	height = 1.1 * s
	# A floating orb â€” one big lens eye, ringed.
	var orb: SphereMesh = SphereMesh.new()
	orb.radius = 0.3 * s
	orb.height = 0.6 * s
	orb.radial_segments = 12
	orb.rings = 7
	_part("Orb", orb, Vector3(0.0, 0.95 * s, 0.0), base, 0.0)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.3 * s
	ring.outer_radius = 0.42 * s
	ring.rings = 16
	ring.ring_segments = 10
	var ring_mi: MeshInstance3D = _part("LensRing", ring, Vector3(0.0, 0.95 * s, 0.0), accent, 0.0)
	ring_mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	# One large pupil that also serves as the muzzle glow.
	var pupil: SphereMesh = SphereMesh.new()
	pupil.radius = 0.13 * s
	pupil.height = 0.26 * s
	var pupil_mi: MeshInstance3D = MeshInstance3D.new()
	pupil_mi.name = "Pupil"
	pupil_mi.mesh = pupil
	pupil_mi.position = Vector3(0.0, 0.95 * s, -0.24 * s)
	pupil_mi.material_override = _emissive(Color(1.0, 0.5, 0.95), eye_glow)
	pupil_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pupil_mi)


func _build_dummy() -> void:
	height = 1.7
	var post: BoxMesh = BoxMesh.new()
	post.size = Vector3(0.16, 1.5, 0.16)
	_part("Post", post, Vector3(0.0, 0.75, 0.0), Color(0.5, 0.36, 0.2), 0.0)
	var arms: BoxMesh = BoxMesh.new()
	arms.size = Vector3(1.1, 0.14, 0.14)
	_part("Arms", arms, Vector3(0.0, 1.15, 0.0), Color(0.5, 0.36, 0.2), 0.0)
	var sack: SphereMesh = SphereMesh.new()
	sack.radius = 0.24
	sack.height = 0.5
	_part("Sack", sack, Vector3(0.0, 1.55, 0.0), Color(0.82, 0.72, 0.42), 0.0)
	var straw: BoxMesh = BoxMesh.new()
	straw.size = Vector3(0.5, 0.4, 0.5)
	_part("Straw", straw, Vector3(0.0, 0.5, 0.0), Color(0.86, 0.74, 0.34), 0.0)


# --- Shared pieces -----------------------------------------------------------

func _legs(size: float, color: Color) -> void:
	for sx: int in [-1, 1]:
		var leg: CylinderMesh = CylinderMesh.new()
		leg.top_radius = 0.055 * size
		leg.bottom_radius = 0.05 * size
		leg.height = 0.28 * size
		leg.radial_segments = 7
		_part("Leg%d" % sx, leg, Vector3(0.12 * size * sx, 0.16 * size, 0.0), color, 0.0)


func _eyes(center: Vector3, radius: float, spread: float, glow: float) -> void:
	for sx: int in [-1, 1]:
		var eye: SphereMesh = SphereMesh.new()
		eye.radius = radius
		eye.height = radius * 2.0
		eye.radial_segments = 8
		eye.rings = 4
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Eye%d" % sx
		mi.mesh = eye
		mi.position = center + Vector3(spread * 0.5 * sx, 0.0, 0.0)
		mi.material_override = _emissive(Color(1.0, 0.85, 0.3), glow)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _part(part_name: String, mesh: Mesh, pos: Vector3, color: Color, jitter: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	var mat: ShaderMaterial = _toon(color)
	mi.material_override = mat
	add_child(mi)
	_parts.append({"node": mi, "base": color, "mat": mat, "offset": pos, "jitter": jitter})
	return mi


func _toon(color: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(TOON_SHADER) as Shader
	mat.set_shader_parameter("use_srgb_vertex", false)
	mat.set_shader_parameter("albedo_tint", color)
	mat.set_shader_parameter("rim_color", Color(1.0, 0.6, 0.5))
	mat.set_shader_parameter("rim_amount", 0.5)
	mat.set_shader_parameter("rim_width", 0.6)
	mat.set_shader_parameter("shadow_fill", Color(0.4, 0.3, 0.5))
	mat.set_shader_parameter("fill_amount", 0.1)
	return mat


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

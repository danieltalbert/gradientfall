class_name KernMaterials
extends RefCounted
## Material factory for Kern. One place owns every color decision so the
## whole character stays on a single palette: sun-warm skin, chestnut hair,
## moss-green wools, oiled leather, honest steel. All materials ride the
## character shader family (cel bands + rim + sky fill) so Kern sits in the
## same painted light as the world.

const SKIN_SHADER: Shader = preload("res://assets/shaders/character/kern_skin.gdshader")
const CLOTH_SHADER: Shader = preload("res://assets/shaders/character/kern_cloth.gdshader")
const LEATHER_SHADER: Shader = preload("res://assets/shaders/character/kern_leather.gdshader")
const METAL_SHADER: Shader = preload("res://assets/shaders/character/kern_metal.gdshader")
const HAIR_SHADER: Shader = preload("res://assets/shaders/character/kern_hair.gdshader")
const EYE_SHADER: Shader = preload("res://assets/shaders/character/kern_eye.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/character/kern_glow.gdshader")

# --- Awaken: one level (0 = disguised traveller, 1 = First Model showing) that
# every magical material reads. Materials register themselves so a single
# set_awaken() updates the whole character. ---
static var _awaken_mats: Array = []
static var _awaken: float = 0.12


## Register a ShaderMaterial so `awaken` is kept in sync on it. Harmless for
## shaders without an `awaken` uniform (the set is a no-op there).
static func _reg(m: ShaderMaterial) -> ShaderMaterial:
	_awaken_mats.append(m)
	m.set_shader_parameter("awaken", _awaken)
	return m


## Drive the whole character's magic. 0 = ordinary; 1 = fully lit.
static func set_awaken(level: float) -> void:
	_awaken = clampf(level, 0.0, 1.0)
	for m in _awaken_mats:
		(m as ShaderMaterial).set_shader_parameter("awaken", _awaken)


static func awaken_level() -> float:
	return _awaken

# --- The palette (authored as display/sRGB; shaders linearize) --------------
# Skin: warm tan of someone who works outdoors; painted zones shift around it.
const SKIN_BASE: Color = Color(0.790, 0.560, 0.415)
const SKIN_FLUSH: Color = Color(0.810, 0.470, 0.345)  # cheeks/nose/ears/knuckles
const SKIN_SHADOWED: Color = Color(0.660, 0.455, 0.350)  # eye sockets, under jaw
const LIP_COLOR: Color = Color(0.720, 0.400, 0.335)
# Hair: chestnut, warmer at the tips (shader ramps between these).
const HAIR_ROOT: Color = Color(0.155, 0.085, 0.045)
const HAIR_TIP: Color = Color(0.410, 0.240, 0.105)
const BROW_ROOT: Color = Color(0.130, 0.075, 0.042)
const BROW_TIP: Color = Color(0.240, 0.140, 0.070)
# Cloth: Vaultborn travel-wear. Tunic moss green, trousers walnut-grey,
# cloak weathered russet-brown with a warmer lining, scarf madder red.
const TUNIC_GREEN: Color = Color(0.295, 0.410, 0.265)
const TUNIC_SLEEVE: Color = Color(0.330, 0.430, 0.285)
const TROUSER_GREY: Color = Color(0.265, 0.290, 0.270)
const CLOAK_BROWN: Color = Color(0.360, 0.235, 0.155)
const CLOAK_LINING: Color = Color(0.560, 0.375, 0.220)
const SCARF_RED: Color = Color(0.690, 0.290, 0.160)
const PATCH_TAN: Color = Color(0.585, 0.430, 0.240)
const PATCH_GREEN: Color = Color(0.250, 0.360, 0.290)
const THREAD_COLOR: Color = Color(0.820, 0.760, 0.620)
# Leather: oiled brown, belt darker than boots.
const BELT_BROWN: Color = Color(0.290, 0.170, 0.095)
const BOOT_BROWN: Color = Color(0.370, 0.230, 0.130)
const GRIP_BROWN: Color = Color(0.240, 0.130, 0.070)
const SCABBARD_BROWN: Color = Color(0.330, 0.195, 0.110)
# Metal.
const STEEL: Color = Color(0.760, 0.790, 0.820)
const BRONZE: Color = Color(0.680, 0.480, 0.220)
const BUCKLE_IRON: Color = Color(0.450, 0.460, 0.480)
# The canon hand-mark glow.
const MARK_GOLD: Color = Color(1.0, 0.72, 0.18)

# Shared instances (meshes vary via vertex COLOR, so most parts can share).
static var _skin: ShaderMaterial
static var _hair: ShaderMaterial
static var _brow: ShaderMaterial
static var _eye: ShaderMaterial
static var _glow: ShaderMaterial


static func skin() -> ShaderMaterial:
	if _skin == null:
		_skin = ShaderMaterial.new()
		_skin.shader = SKIN_SHADER
		_reg(_skin)
	return _skin


## The living arcane glow — hand-mark, latent threads, sword sigil. Emissive,
## awaken-driven, with a light pulse flowing along each thread.
static func glow() -> ShaderMaterial:
	if _glow == null:
		_glow = ShaderMaterial.new()
		_glow.shader = GLOW_SHADER
		_reg(_glow)
	return _glow


static func hair() -> ShaderMaterial:
	if _hair == null:
		_hair = ShaderMaterial.new()
		_hair.shader = HAIR_SHADER
		_hair.set_shader_parameter("root_color", HAIR_ROOT)
		_hair.set_shader_parameter("tip_color", HAIR_TIP)
		_reg(_hair)
	return _hair


## Iris material for the flat cornea disc (gradient + shimmer + awaken glow).
static func iris() -> ShaderMaterial:
	if _eye == null:
		_eye = ShaderMaterial.new()
		_eye.shader = EYE_SHADER
		_reg(_eye)
	return _eye


static func brow() -> ShaderMaterial:
	if _brow == null:
		_brow = ShaderMaterial.new()
		_brow.shader = HAIR_SHADER
		_brow.set_shader_parameter("root_color", BROW_ROOT)
		_brow.set_shader_parameter("tip_color", BROW_TIP)
		_brow.set_shader_parameter("sheen_strength", 0.25)
		_brow.set_shader_parameter("rim_amount", 0.18)
	return _brow


static func cloth(weave_scale: float = 190.0, wind_strength: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = CLOTH_SHADER
	m.set_shader_parameter("weave_scale", weave_scale)
	m.set_shader_parameter("wind_strength", wind_strength)
	return _reg(m)


## Add an embroidered trim border to a cloth material. Bands are (centre_v,
## half_height) in the garment's UV.y; pass Vector2(-1,0.05) to disable one.
static func add_trim(m: ShaderMaterial, band_a: Vector2, band_b: Vector2,
		reps: float = 26.0, gold: Color = Color(0.86, 0.70, 0.30),
		accent: Color = Color(0.62, 0.24, 0.16)) -> void:
	m.set_shader_parameter("trim_band_a", band_a)
	m.set_shader_parameter("trim_band_b", band_b)
	m.set_shader_parameter("trim_reps", reps)
	m.set_shader_parameter("trim_color", gold)
	m.set_shader_parameter("trim_color2", accent)


static func leather() -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = LEATHER_SHADER
	return m


static func metal(spec_strength: float = 1.9) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = METAL_SHADER
	m.set_shader_parameter("spec_strength", spec_strength)
	return m


## The glowing hand-mark / pommel sigil. Unshaded emissive so it reads at
## night and inside shadow — canon: "glows near ancient machinery".
static func mark_glow(energy: float = 2.6) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = MARK_GOLD
	m.emission_enabled = true
	m.emission = Color(1.0, 0.58, 0.10)
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Teeth / nails: simple warm off-white, standard shading is fine at this size.
static func bone_white() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.905, 0.870, 0.800)
	m.roughness = 0.35
	return m

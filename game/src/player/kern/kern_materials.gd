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

# --- The palette (authored as display/sRGB; shaders linearize) --------------
# Skin: warm tan of someone who works outdoors; painted zones shift around it.
const SKIN_BASE: Color = Color(0.855, 0.635, 0.470)
const SKIN_FLUSH: Color = Color(0.880, 0.545, 0.400)  # cheeks/nose/ears/knuckles
const SKIN_SHADOWED: Color = Color(0.760, 0.545, 0.420)  # eye sockets, under jaw
const LIP_COLOR: Color = Color(0.795, 0.470, 0.385)
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


static func skin() -> ShaderMaterial:
	if _skin == null:
		_skin = ShaderMaterial.new()
		_skin.shader = SKIN_SHADER
	return _skin


static func hair() -> ShaderMaterial:
	if _hair == null:
		_hair = ShaderMaterial.new()
		_hair.shader = HAIR_SHADER
		_hair.set_shader_parameter("root_color", HAIR_ROOT)
		_hair.set_shader_parameter("tip_color", HAIR_TIP)
	return _hair


static func brow() -> ShaderMaterial:
	if _brow == null:
		_brow = ShaderMaterial.new()
		_brow.shader = HAIR_SHADER
		_brow.set_shader_parameter("root_color", BROW_ROOT)
		_brow.set_shader_parameter("tip_color", BROW_TIP)
		_brow.set_shader_parameter("sheen_strength", 0.25)
		_brow.set_shader_parameter("rim_amount", 0.18)
	return _brow


static func eye() -> ShaderMaterial:
	if _eye == null:
		_eye = ShaderMaterial.new()
		_eye.shader = EYE_SHADER
	return _eye


static func cloth(weave_scale: float = 190.0, flutter: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = CLOTH_SHADER
	m.set_shader_parameter("weave_scale", weave_scale)
	m.set_shader_parameter("flutter_amount", flutter)
	return m


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

class_name VaultBuild
extends RefCounted
## Construction kit for the Perceptron Vault — the only place the dungeon's
## stone and light are actually meshed.
##
## Every other dungeon script describes the vault in rooms, walls, and runes
## and lets these static helpers emit the geometry, so the puzzle scripts stay
## about the puzzle. Nothing here holds state; call the statics from any node.
##
## Where it sits: pure builder, used by PerceptronVault (architecture),
## NeuronChamber, SignalFount, WeightStone, VaultGate, and VaultGatekeeper.
## Nothing here reads GameState, ContentDB, or the EventBus.
##
## Conventions:
## * Meters everywhere. Box sizes are full extents (not half-extents), and
##   positions are the box CENTER, matching Godot's BoxMesh/BoxShape3D.
## * Stone uses the shared toon shader so the dungeon reads as the same world
##   as the meadow (GDD §10 non-negotiable: cel shading everywhere). Glowing
##   surfaces use vault_rune.gdshader.
## * Solid stone is built on the WORLD collision layer, so Kern collides with
##   it exactly as he does with terrain and monsters ignore it the same way.

const TOON_SHADER: String = "res://assets/shaders/toon.gdshader"
const RUNE_SHADER: String = "res://assets/shaders/vault_rune.gdshader"

## The vault's stone palette. Pale, dry, and slightly warm — the Seed Vault
## builders' stone, lighter than the meadow's rock so interiors do not go
## muddy under rune light alone.
const STONE_WALL: Color = Color(0.60, 0.58, 0.53)
const STONE_FLOOR: Color = Color(0.44, 0.43, 0.41)
const STONE_TRIM: Color = Color(0.71, 0.68, 0.60)
const STONE_DARK: Color = Color(0.31, 0.30, 0.29)

## Signal light: warm gold reads as "adding", cold blue as "taking away".
## The whole dungeon teaches sign with these two colors and nothing else, so
## they are never used for decoration.
const LIGHT_POSITIVE: Color = Color(1.00, 0.78, 0.32)
const LIGHT_NEGATIVE: Color = Color(0.36, 0.62, 0.95)
## An inert fixture: powered, but carrying no signal.
const LIGHT_IDLE: Color = Color(0.55, 0.60, 0.66)
## The output gate's own color — the vault's one green, spent only on "open".
const LIGHT_OPEN: Color = Color(0.42, 0.92, 0.58)

## Label3D scale: meters per pixel of font size. Lets plaque() take widths
## and sizes in meters while Label3D works internally in pixels.
const PLAQUE_METERS_PER_PIXEL: float = 0.01


# --- Stone -------------------------------------------------------------------

## A solid stone box: visible mesh plus matching collision, centered on
## `center`. `size` is full extents in meters. Returns the MeshInstance3D so
## callers can tween or recolor it (VaultGate slides its doors this way).
static func solid(parent: Node3D, center: Vector3, size: Vector3,
		color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = decor(parent, center, size, color)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = CombatLayers.WORLD
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	# Parented to the mesh, not to `parent`: a moving door then carries its
	# own collision without the caller having to move two nodes in step.
	mi.add_child(body)
	return mi


## A stone box with no collision — trim, cornices, sigil bars, anything Kern
## can never reach. Cheaper than `solid()` and keeps the physics world small.
static func decor(parent: Node3D, center: Vector3, size: Vector3,
		color: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	mi.material_override = toon_material(color)
	parent.add_child(mi)
	return mi


## The shared cel-shading material, tinted. Vertex colors are unused on these
## boxes, so the tint uniform carries the color and `use_srgb_vertex` is off
## (BoxMesh has no COLOR channel to linearize).
static func toon_material(color: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(TOON_SHADER) as Shader
	mat.set_shader_parameter("use_srgb_vertex", false)
	mat.set_shader_parameter("albedo_tint", color)
	mat.set_shader_parameter("rim_amount", 0.22)
	mat.set_shader_parameter("rim_color", Color(0.86, 0.88, 0.95))
	# Warmer than the meadow's sky fill: underground, the bounce light comes
	# off the vault's own gold runes rather than off a blue sky.
	mat.set_shader_parameter("shadow_fill", Color(0.72, 0.62, 0.48))
	mat.set_shader_parameter("fill_amount", 0.20)
	return mat


# --- Rooms -------------------------------------------------------------------

## A sealed rectangular room: floor, ceiling, and four walls, built inward
## from `inner_size` (the clear interior volume, in meters) so the caller can
## reason about the space Kern actually walks in.
##
## `center` is the middle of the FLOOR, so a room at y = 0 has its floor slab
## just below y = 0 and its ceiling `inner_size.y` above it.
##
## `doors` cuts openings: each entry is `{ "side": "north"|"south"|"east"|
## "west", "width": float, "height": float, "offset": float }`, where offset
## slides the opening along the wall from its center. A wall with an opening
## is emitted as two jambs plus a lintel; a wall without one is a single box.
static func room(parent: Node3D, center: Vector3, inner_size: Vector3,
		thickness: float, doors: Array[Dictionary] = []) -> void:
	var hx: float = inner_size.x * 0.5
	var hz: float = inner_size.z * 0.5
	var h: float = inner_size.y

	# Floor and ceiling overhang the walls by `thickness` on each side so
	# corners never show a seam from inside.
	var slab: Vector3 = Vector3(inner_size.x + thickness * 2.0, thickness,
			inner_size.z + thickness * 2.0)
	solid(parent, center + Vector3(0.0, -thickness * 0.5, 0.0), slab, STONE_FLOOR)
	solid(parent, center + Vector3(0.0, h + thickness * 0.5, 0.0), slab, STONE_DARK)

	# North is -Z and south is +Z, matching the meadow's compass (the Gradient
	# Peaks vista sits at -Z). East is +X.
	_wall(parent, center, Vector3(0.0, 0.0, -hz - thickness * 0.5),
			Vector3(inner_size.x + thickness * 2.0, h, thickness),
			_door_for(doors, "north"), true)
	_wall(parent, center, Vector3(0.0, 0.0, hz + thickness * 0.5),
			Vector3(inner_size.x + thickness * 2.0, h, thickness),
			_door_for(doors, "south"), true)
	_wall(parent, center, Vector3(-hx - thickness * 0.5, 0.0, 0.0),
			Vector3(thickness, h, inner_size.z),
			_door_for(doors, "west"), false)
	_wall(parent, center, Vector3(hx + thickness * 0.5, 0.0, 0.0),
			Vector3(thickness, h, inner_size.z),
			_door_for(doors, "east"), false)


## Find the door spec for one side, or an empty Dictionary if that wall is
## solid. Only the first match is used — two openings in one wall would need
## a second call with a different offset.
static func _door_for(doors: Array[Dictionary], side: String) -> Dictionary:
	for d: Dictionary in doors:
		if str(d.get("side", "")) == side:
			return d
	return {}


## One wall of a room. `span_on_x` says which horizontal axis the wall runs
## along, which is what decides where the jambs go. With no door spec the
## wall is a single box.
static func _wall(parent: Node3D, center: Vector3, offset: Vector3,
		size: Vector3, door: Dictionary, span_on_x: bool) -> void:
	var base: Vector3 = center + offset + Vector3(0.0, size.y * 0.5, 0.0)
	if door.is_empty():
		solid(parent, base, size, STONE_WALL)
		return

	var dw: float = float(door.get("width", 5.0))
	var dh: float = float(door.get("height", 4.5))
	var dof: float = float(door.get("offset", 0.0))
	var span: float = size.x if span_on_x else size.z
	# Jamb widths either side of the opening. maxf keeps a jamb from going
	# negative if a caller asks for an opening wider than its wall.
	var left: float = maxf(0.0, span * 0.5 + dof - dw * 0.5)
	var right: float = maxf(0.0, span * 0.5 - dof - dw * 0.5)
	var left_c: float = -span * 0.5 + left * 0.5
	var right_c: float = span * 0.5 - right * 0.5

	if span_on_x:
		if left > 0.01:
			solid(parent, base + Vector3(left_c, 0.0, 0.0),
					Vector3(left, size.y, size.z), STONE_WALL)
		if right > 0.01:
			solid(parent, base + Vector3(right_c, 0.0, 0.0),
					Vector3(right, size.y, size.z), STONE_WALL)
		if size.y - dh > 0.01:
			solid(parent, base + Vector3(dof, (size.y + dh) * 0.5 - size.y * 0.5, 0.0),
					Vector3(dw, size.y - dh, size.z), STONE_WALL)
	else:
		if left > 0.01:
			solid(parent, base + Vector3(0.0, 0.0, left_c),
					Vector3(size.x, size.y, left), STONE_WALL)
		if right > 0.01:
			solid(parent, base + Vector3(0.0, 0.0, right_c),
					Vector3(size.x, size.y, right), STONE_WALL)
		if size.y - dh > 0.01:
			solid(parent, base + Vector3(0.0, (size.y + dh) * 0.5 - size.y * 0.5, dof),
					Vector3(size.x, size.y - dh, dw), STONE_WALL)


# --- Light -------------------------------------------------------------------

## A glowing surface using vault_rune.gdshader. `size` is full extents; the
## mesh's long axis should be Y when the caller intends to use `set_fill()`.
## No collision — light is never solid in this vault.
static func rune(parent: Node3D, center: Vector3, size: Vector3, color: Color,
		energy: float = 2.4) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(RUNE_SHADER) as Shader
	mat.set_shader_parameter("glow_color", color)
	mat.set_shader_parameter("energy", energy)
	# The meter uniforms describe this mesh's Y extent, so callers can pass a
	# plain 0..1 fraction to set_fill() without knowing the geometry.
	mat.set_shader_parameter("fill_height", size.y)
	mat.set_shader_parameter("fill_base", -size.y * 0.5)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Recolor a rune built by `rune()`. Used constantly — a fount toggling, a
## weight flipping sign, a chamber firing.
static func set_rune_color(mi: MeshInstance3D, color: Color, energy: float = -1.0) -> void:
	var mat: ShaderMaterial = mi.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("glow_color", color)
	if energy >= 0.0:
		mat.set_shader_parameter("energy", energy)


## Drive a rune as a fill meter. `fraction` is 0..1 of the mesh's Y extent.
static func set_rune_fill(mi: MeshInstance3D, fraction: float) -> void:
	var mat: ShaderMaterial = mi.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fill", clampf(fraction, 0.0, 1.0))


## Turn on the travelling-band effect — a conduit carrying signal. `amount`
## is 0 to switch it off. Negative `speed` runs the band the other way, which
## is how an inbound conduit is distinguished from an outbound one.
static func set_rune_flow(mi: MeshInstance3D, amount: float, speed: float = 1.2,
		density: float = 0.35) -> void:
	var mat: ShaderMaterial = mi.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flow_amount", amount)
	mat.set_shader_parameter("flow_speed", speed)
	mat.set_shader_parameter("flow_density", density)


## Set the breathing rate/depth of a rune. Distinct phases keep a row of
## fixtures from throbbing in unison, which reads as machinery, not magic.
static func set_rune_pulse(mi: MeshInstance3D, amount: float, speed: float = 1.6,
		phase: float = 0.0) -> void:
	var mat: ShaderMaterial = mi.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("pulse_amount", amount)
	mat.set_shader_parameter("pulse_speed", speed)
	mat.set_shader_parameter("pulse_phase", phase)


## An omni light — the vault is sealed, so every lit space needs one. Kept
## shadowless by default: these are fill lights for a windowless interior and
## the sun's 4k shadow map is already doing the expensive work outside.
static func lamp(parent: Node3D, center: Vector3, color: Color,
		energy: float = 2.0, range_m: float = 16.0,
		shadows: bool = false) -> OmniLight3D:
	var l: OmniLight3D = OmniLight3D.new()
	l.position = center
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = shadows
	parent.add_child(l)
	return l


# --- Inscriptions ------------------------------------------------------------

## A carved plaque. The vault explains itself in plain stonecutter's English —
## WORLDBOOK Part IV forbids the vocabulary the mechanic is named after, so
## these read as instructions from the builders and never as a tutorial.
##
## `yaw` (radians) turns the carving to face into its room. Label3D faces
## local +Z, so a plaque on a room's NORTH wall needs yaw 0 and one on the
## SOUTH wall needs PI — get this wrong and the text faces into the stone.
static func plaque(parent: Node3D, center: Vector3, text: String,
		width: float = 6.0, size_px: int = 44, yaw: float = 0.0) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.position = center
	label.rotation.y = yaw
	label.font_size = size_px
	label.outline_size = size_px / 5
	label.modulate = Color(0.96, 0.90, 0.74)
	label.outline_modulate = Color(0.10, 0.08, 0.06, 0.9)
	# Label3D measures its wrap width in pixels and scales by pixel_size. At
	# 0.01 m/px, 100 px is one meter — so `width` can be given in meters.
	label.pixel_size = PLAQUE_METERS_PER_PIXEL
	label.width = width / PLAQUE_METERS_PER_PIXEL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Carved into a wall: it must not swivel to face the camera.
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.shaded = false
	parent.add_child(label)
	return label

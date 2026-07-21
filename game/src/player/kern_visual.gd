class_name KernVisual
extends Node3D
## Code-built silhouette-first look-dev for Kern.
##
## This is still a procedural Phase-1 hero, but it is deliberately shaped as
## a small adventurer rather than a capsule: layered tunic, wind cape, hooded
## head, limbs, boots, sword, and the canon glowing hand mark. The simple
## animation pass keeps the silhouette alive while walking or standing.

const TOON_SHADER: String = "res://assets/shaders/toon.gdshader"

# Sword rest pose (matches _build_sword). Combat poses lerp away and back.
const SWORD_REST_POS: Vector3 = Vector3(0.30, 1.00, 0.30)
const SWORD_REST_ROT: Vector3 = Vector3(0.10, 0.0, -0.62)

var _body: CharacterBody3D
var _torso: Node3D
var _cape: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _sword: Node3D
var _phase: float = 0.0
## While true, PlayerCombat owns the right arm + sword; idle/walk anim yields.
var _combat_arm_override: bool = false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_build_hero()


func _process(delta: float) -> void:
	if _body == null:
		return
	var speed: float = Vector2(_body.velocity.x, _body.velocity.z).length()
	var moving: float = smoothstep(0.15, 2.5, speed)
	_phase += delta * lerpf(1.4, 8.5, clampf(speed / 7.5, 0.0, 1.0))
	var swing: float = sin(_phase) * 0.52 * moving
	_left_arm.rotation.x = swing
	if not _combat_arm_override:
		_right_arm.rotation.x = -swing
	_left_leg.rotation.x = -swing * 0.72
	_right_leg.rotation.x = swing * 0.72
	_torso.position.y = sin(_phase * 2.0) * 0.018 * moving
	var breathe: float = sin(Time.get_ticks_msec() * 0.0021) * 0.012
	_torso.scale = Vector3(1.0 - breathe * 0.25, 1.0 + breathe, 1.0 - breathe * 0.25)
	_cape.rotation.x = 0.11 + speed * 0.018 + sin(_phase * 1.37) * (0.025 + moving * 0.035)


func _build_hero() -> void:
	_torso = Node3D.new()
	_torso.name = "TorsoRig"
	add_child(_torso)

	var tunic: CylinderMesh = CylinderMesh.new()
	tunic.top_radius = 0.27
	tunic.bottom_radius = 0.36
	tunic.height = 0.66
	tunic.radial_segments = 12
	tunic.rings = 2
	_add_part(_torso, "Tunic", tunic, Vector3(0.0, 0.98, 0.0),
		Color(0.20, 0.34, 0.22), Vector3.ONE)

	var belt: CylinderMesh = CylinderMesh.new()
	belt.top_radius = 0.365
	belt.bottom_radius = 0.365
	belt.height = 0.105
	belt.radial_segments = 12
	_add_part(_torso, "Belt", belt, Vector3(0.0, 0.78, 0.0),
		Color(0.20, 0.12, 0.075), Vector3.ONE)

	var mantle: CylinderMesh = CylinderMesh.new()
	mantle.top_radius = 0.29
	mantle.bottom_radius = 0.39
	mantle.height = 0.18
	mantle.radial_segments = 12
	_add_part(_torso, "ShoulderMantle", mantle, Vector3(0.0, 1.27, 0.0),
		Color(0.32, 0.23, 0.16), Vector3.ONE)

	var hood: SphereMesh = SphereMesh.new()
	hood.radius = 0.255
	hood.height = 0.51
	hood.radial_segments = 14
	hood.rings = 7
	_add_part(_torso, "Hood", hood, Vector3(0.0, 1.51, 0.055),
		Color(0.18, 0.25, 0.16), Vector3(1.08, 1.06, 1.02))

	var face: SphereMesh = SphereMesh.new()
	face.radius = 0.205
	face.height = 0.41
	face.radial_segments = 14
	face.rings = 7
	_add_part(_torso, "Face", face, Vector3(0.0, 1.49, -0.115),
		Color(0.52, 0.32, 0.18), Vector3(0.92, 1.0, 0.68))
	var eye: SphereMesh = SphereMesh.new()
	eye.radius = 0.022
	eye.height = 0.044
	eye.radial_segments = 8
	eye.rings = 4
	_add_part(_torso, "LeftEye", eye, Vector3(-0.068, 1.52, -0.252),
		Color(0.035, 0.045, 0.035), Vector3(0.76, 1.1, 0.52))
	_add_part(_torso, "RightEye", eye, Vector3(0.068, 1.52, -0.252),
		Color(0.035, 0.045, 0.035), Vector3(0.76, 1.1, 0.52))
	var fringe: BoxMesh = BoxMesh.new()
	fringe.size = Vector3(0.30, 0.085, 0.055)
	_add_part(_torso, "HairFringe", fringe, Vector3(-0.025, 1.655, -0.235),
		Color(0.13, 0.075, 0.035), Vector3.ONE, Vector3(0.0, 0.0, -0.10))

	var hair: CylinderMesh = CylinderMesh.new()
	hair.top_radius = 0.0
	hair.bottom_radius = 0.095
	hair.height = 0.28
	hair.radial_segments = 7
	_add_part(_torso, "HairTuft", hair, Vector3(-0.08, 1.73, -0.04),
		Color(0.16, 0.10, 0.055), Vector3.ONE, Vector3(0.18, 0.0, -0.42))

	var scarf: BoxMesh = BoxMesh.new()
	scarf.size = Vector3(0.44, 0.11, 0.12)
	_add_part(_torso, "Scarf", scarf, Vector3(0.0, 1.30, -0.20),
		Color(0.66, 0.25, 0.12), Vector3.ONE, Vector3(0.08, 0.0, 0.0))

	_left_arm = _build_limb("LeftArm", Vector3(-0.34, 1.24, 0.0),
		Color(0.25, 0.37, 0.22), false)
	_right_arm = _build_limb("RightArm", Vector3(0.34, 1.24, 0.0),
		Color(0.25, 0.37, 0.22), true)
	_left_leg = _build_leg("LeftLeg", Vector3(-0.15, 0.70, 0.0))
	_right_leg = _build_leg("RightLeg", Vector3(0.15, 0.70, 0.0))

	_build_cape()
	_build_sword()


func _build_limb(part_name: String, pos: Vector3, color: Color, marked: bool) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = part_name
	pivot.position = pos
	add_child(pivot)
	var arm: CapsuleMesh = CapsuleMesh.new()
	arm.radius = 0.085
	arm.height = 0.58
	arm.radial_segments = 10
	arm.rings = 4
	_add_part(pivot, "Sleeve", arm, Vector3(0.0, -0.27, 0.0), color, Vector3.ONE)
	var hand: SphereMesh = SphereMesh.new()
	hand.radius = 0.095
	hand.height = 0.19
	hand.radial_segments = 10
	hand.rings = 5
	_add_part(pivot, "Hand", hand, Vector3(0.0, -0.56, -0.01),
		Color(0.52, 0.32, 0.18), Vector3(0.9, 1.15, 0.8))
	if marked:
		var mark: SphereMesh = SphereMesh.new()
		mark.radius = 0.045
		mark.height = 0.09
		mark.radial_segments = 10
		var mark_node: MeshInstance3D = MeshInstance3D.new()
		mark_node.name = "HandMark"
		mark_node.mesh = mark
		mark_node.position = Vector3(0.075, -0.56, -0.045)
		var mark_mat: StandardMaterial3D = StandardMaterial3D.new()
		mark_mat.albedo_color = Color(1.0, 0.74, 0.16)
		mark_mat.emission_enabled = true
		mark_mat.emission = Color(1.0, 0.55, 0.08)
		mark_mat.emission_energy_multiplier = 3.2
		mark_node.material_override = mark_mat
		pivot.add_child(mark_node)
	return pivot


func _build_leg(part_name: String, pos: Vector3) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = part_name
	pivot.position = pos
	add_child(pivot)
	var leg: CapsuleMesh = CapsuleMesh.new()
	leg.radius = 0.105
	leg.height = 0.55
	leg.radial_segments = 10
	leg.rings = 4
	_add_part(pivot, "Trouser", leg, Vector3(0.0, -0.25, 0.0),
		Color(0.14, 0.19, 0.17), Vector3.ONE)
	var boot: CapsuleMesh = CapsuleMesh.new()
	boot.radius = 0.12
	boot.height = 0.27
	boot.radial_segments = 10
	boot.rings = 4
	_add_part(pivot, "Boot", boot, Vector3(0.0, -0.55, -0.055),
		Color(0.16, 0.095, 0.055), Vector3(1.0, 0.9, 1.35), Vector3(PI * 0.5, 0.0, 0.0))
	return pivot


func _build_cape() -> void:
	_cape = Node3D.new()
	_cape.name = "CapeRig"
	_cape.position = Vector3(0.0, 1.30, 0.20)
	add_child(_cape)
	var cape_node: MeshInstance3D = MeshInstance3D.new()
	cape_node.name = "PatchedCape"
	cape_node.mesh = _make_cape_mesh()
	cape_node.material_override = _make_toon_material(Color(0.28, 0.16, 0.11), 0.46)
	_cape.add_child(cape_node)
	# Two visible repair patches break up the large cape shape.
	var patch_mesh: BoxMesh = BoxMesh.new()
	patch_mesh.size = Vector3(0.17, 0.15, 0.018)
	_add_part(_cape, "CapePatchA", patch_mesh, Vector3(-0.14, -0.48, 0.025),
		Color(0.48, 0.31, 0.15), Vector3.ONE, Vector3(0.0, 0.0, -0.13))
	_add_part(_cape, "CapePatchB", patch_mesh, Vector3(0.17, -0.70, 0.03),
		Color(0.16, 0.28, 0.20), Vector3(0.72, 0.75, 1.0), Vector3(0.0, 0.0, 0.18))


func _make_cape_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tl: Vector3 = Vector3(-0.30, 0.0, 0.0)
	var tr: Vector3 = Vector3(0.30, 0.0, 0.0)
	var ml: Vector3 = Vector3(-0.40, -0.55, 0.035)
	var mr: Vector3 = Vector3(0.40, -0.55, 0.035)
	var b0: Vector3 = Vector3(-0.43, -0.98, 0.08)
	var b1: Vector3 = Vector3(-0.21, -0.87, 0.095)
	var b2: Vector3 = Vector3(0.0, -1.02, 0.10)
	var b3: Vector3 = Vector3(0.22, -0.88, 0.095)
	var b4: Vector3 = Vector3(0.43, -0.97, 0.08)
	var tris: Array[Vector3] = [
		tl, ml, tr, tr, ml, mr,
		ml, b0, b1, ml, b1, mr,
		mr, b1, b2, mr, b2, b3, mr, b3, b4,
	]
	for i in range(0, tris.size(), 3):
		_add_cape_tri(st, tris[i], tris[i + 1], tris[i + 2], Vector3(0.0, 0.0, 1.0))
		_add_cape_tri(st, tris[i + 2], tris[i + 1], tris[i], Vector3(0.0, 0.0, -1.0))
	st.index()
	return st.commit()


func _add_cape_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)


func _build_sword() -> void:
	var sword: Node3D = Node3D.new()
	sword.name = "TravelerSword"
	sword.position = SWORD_REST_POS
	sword.rotation = SWORD_REST_ROT
	add_child(sword)
	_sword = sword
	var blade: BoxMesh = BoxMesh.new()
	blade.size = Vector3(0.055, 0.76, 0.028)
	_add_part(sword, "Blade", blade, Vector3(0.0, 0.12, 0.0),
		Color(0.42, 0.52, 0.55), Vector3.ONE)
	var guard: BoxMesh = BoxMesh.new()
	guard.size = Vector3(0.25, 0.055, 0.07)
	_add_part(sword, "Guard", guard, Vector3(0.0, -0.27, 0.0),
		Color(0.68, 0.45, 0.14), Vector3.ONE)
	var grip: CylinderMesh = CylinderMesh.new()
	grip.top_radius = 0.045
	grip.bottom_radius = 0.045
	grip.height = 0.24
	grip.radial_segments = 8
	_add_part(sword, "Grip", grip, Vector3(0.0, -0.41, 0.0),
		Color(0.18, 0.09, 0.045), Vector3.ONE)


func _add_part(parent: Node3D, part_name: String, mesh: Mesh, pos: Vector3,
		color: Color, part_scale: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = pos
	part.rotation = rot
	part.scale = part_scale
	part.material_override = _make_toon_material(color, 0.34)
	parent.add_child(part)
	return part


func _make_toon_material(color: Color, rim: float) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(TOON_SHADER) as Shader
	mat.set_shader_parameter("use_srgb_vertex", false)
	mat.set_shader_parameter("albedo_tint", color)
	mat.set_shader_parameter("rim_color", Color(0.72, 0.86, 1.0))
	mat.set_shader_parameter("rim_amount", rim)
	mat.set_shader_parameter("rim_width", 0.66)
	mat.set_shader_parameter("shadow_fill", Color(0.34, 0.45, 0.68))
	mat.set_shader_parameter("fill_amount", 0.08)
	return mat


# --- Combat poses (driven by PlayerCombat) -----------------------------------

## phase 0..1 across one swing: raise-back → sweep down-across → settle.
func pose_attack(phase: float) -> void:
	if _sword == null:
		return
	_combat_arm_override = true
	if phase < 0.3:
		var t: float = phase / 0.3
		_right_arm.rotation.x = lerpf(0.0, -1.5, t)
		_sword.rotation = Vector3(0.1, 0.0, lerpf(-0.62, -1.9, t))
		_sword.position = Vector3(0.30, lerpf(1.0, 1.35, t), lerpf(0.30, 0.1, t))
	elif phase < 0.62:
		var e: float = smoothstep(0.0, 1.0, (phase - 0.3) / 0.32)
		_right_arm.rotation.x = lerpf(-1.5, 1.4, e)
		_sword.rotation = Vector3(lerpf(0.1, 0.5, e), lerpf(0.0, -0.6, e), lerpf(-1.9, 0.7, e))
		_sword.position = Vector3(lerpf(0.30, 0.05, e), lerpf(1.35, 0.8, e), lerpf(0.1, 0.55, e))
	else:
		var e2: float = smoothstep(0.0, 1.0, (phase - 0.62) / 0.38)
		_right_arm.rotation.x = lerpf(1.4, 0.0, e2)
		_sword.rotation = Vector3(
			lerpf(0.5, 0.1, e2), lerpf(-0.6, 0.0, e2), lerpf(0.7, -0.62, e2))
		_sword.position = Vector3(lerpf(0.05, 0.30, e2), lerpf(0.8, 1.0, e2), lerpf(0.55, 0.30, e2))


func pose_guard(active: bool) -> void:
	if _sword == null:
		return
	_combat_arm_override = active
	if active:
		_right_arm.rotation.x = -0.55
		_sword.rotation = Vector3(1.45, 0.0, -0.1)
		_sword.position = Vector3(0.08, 1.12, -0.18)


func combat_release() -> void:
	if not _combat_arm_override:
		return
	_combat_arm_override = false
	if _sword != null:
		_sword.rotation = SWORD_REST_ROT
		_sword.position = SWORD_REST_POS

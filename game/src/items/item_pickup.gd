class_name ItemPickup
extends Area3D
## One findable thing sitting in the world: an approved ContentDB item wearing a
## small code-built prop that bobs, turns, and glows enough to be spotted in
## waist-high grass. Walk into it and it goes straight into the pack.
##
## The prop is generated from the entry's CATEGORY and tinted by its RARITY —
## never from its id — so every item ChatGPT ever writes gets a body for free
## (docs/ARCHITECTURE.md: the runtime never hardcodes authored content).
##
## GDD §10 visible surface: built with no Godot in this environment, so it is
## UNSEEN until a live session lays eyes on it.

signal collected(pickup: ItemPickup)

const REACH: float = 1.15          # metres — generous, this is walk-over pickup
const BOB_SPEED: float = 1.7
const BOB_AMPLITUDE: float = 0.075
const SPIN_SPEED: float = 0.85     # radians/second
const REST_HEIGHT: float = 0.55    # sits above the grass line, not buried in it
const VIEW_RANGE: float = 95.0     # per-mesh cull distance; the meadow is 480 m
const GLOW_LIGHT_RANGE: float = 5.0

var item_id: String = ""
var entry: Dictionary = {}

var _taken: bool = false
var _bob: float = 0.0
var _prop: Node3D


static func spawn(host: Node, item_entry: Dictionary, world_position: Vector3) -> ItemPickup:
	var p: ItemPickup = ItemPickup.new()
	p.entry = item_entry
	p.item_id = str(item_entry.get("id", ""))
	# Place before entering the tree so the bob anchor is right on frame one.
	p.position = world_position
	host.add_child(p)
	return p


func _ready() -> void:
	add_to_group(&"item_pickup")
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER
	monitoring = true
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = REACH
	shape.shape = sphere
	add_child(shape)
	_build_prop()
	_bob = randf() * TAU  # so a field of pickups never bobs in lockstep
	body_entered.connect(_on_body_entered)
	_scan_once.call_deferred()


## Area3D only reports NEW overlaps, and forage regrows on its own clock — a
## spot can come back while Kern is standing right on it. Take one look around
## after physics has ticked so that pickup isn't stranded until he walks off.
func _scan_once() -> void:
	await get_tree().physics_frame
	if _taken or not is_inside_tree():
		return
	for body: Node3D in get_overlapping_bodies():
		if body != null and body.is_in_group(&"player"):
			_collect()
			return


func _process(delta: float) -> void:
	if _prop == null or _taken:
		return
	_bob += delta * BOB_SPEED
	_prop.position.y = REST_HEIGHT + sin(_bob) * BOB_AMPLITUDE
	_prop.rotation.y += delta * SPIN_SPEED


func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group(&"player"):
		return
	_collect()


func _collect() -> void:
	_taken = true
	monitoring = false
	GameState.add_item(item_id, 1)  # emits EventBus.item_acquired → HUD + Bit
	DamageShards.burst(
		get_tree().current_scene, global_position + Vector3(0.0, REST_HEIGHT, 0.0),
		ItemStyle.rarity_color(entry), 9, 2.6, 1.9, 0.75
	)
	collected.emit(self)
	queue_free()


# --- Code-built prop ---------------------------------------------------------

func _build_prop() -> void:
	_prop = Node3D.new()
	_prop.name = "Prop"
	_prop.position = Vector3(0.0, REST_HEIGHT, 0.0)
	add_child(_prop)

	var tint: Color = ItemStyle.rarity_color(entry)
	match ItemStyle.category_of(entry):
		"flora":
			_build_sprig(tint)
		"material":
			_build_chunk(tint)
		"consumable":
			_build_flask(tint)
		"tool":
			_build_ring(tint)
		"curio", "key_item":
			_build_tablet(tint)
		_:
			_build_chunk(tint)

	# A soft additive shell so the thing is findable in tall grass at any hour.
	var halo: MeshInstance3D = _mesh(_sphere(0.26, 10), _glow_material(tint, 1.5, 0.20))
	_prop.add_child(halo)

	# Only the genuinely rare finds are worth a light of their own.
	if ItemStyle.rarity_rank(entry) >= 2:
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = tint
		light.light_energy = 1.1
		light.omni_range = GLOW_LIGHT_RANGE
		light.shadow_enabled = false
		_prop.add_child(light)


## A little three-leaf sprig with a bud — grasses, petals, roots, herbs.
func _build_sprig(tint: Color) -> void:
	var mat: StandardMaterial3D = _solid_material(tint.lerp(Color(0.45, 0.72, 0.32), 0.45))
	for i in 3:
		var blade: MeshInstance3D = _mesh(_box(Vector3(0.045, 0.30, 0.012)), mat)
		var a: float = TAU * float(i) / 3.0
		blade.position = Vector3(cos(a) * 0.055, 0.02, sin(a) * 0.055)
		blade.rotation = Vector3(0.34 * sin(a), -a, 0.34 * cos(a))
		_prop.add_child(blade)
	var bud: MeshInstance3D = _mesh(_sphere(0.075, 10), _solid_material(tint))
	bud.position = Vector3(0.0, 0.19, 0.0)
	_prop.add_child(bud)


## An irregular two-block chunk — ore, clay, grit, wool, scales.
func _build_chunk(tint: Color) -> void:
	var mat: StandardMaterial3D = _solid_material(tint)
	var big: MeshInstance3D = _mesh(_box(Vector3(0.19, 0.15, 0.17)), mat)
	big.rotation = Vector3(0.35, 0.5, 0.22)
	_prop.add_child(big)
	var small: MeshInstance3D = _mesh(_box(Vector3(0.11, 0.10, 0.12)), mat)
	small.position = Vector3(0.10, 0.07, -0.05)
	small.rotation = Vector3(-0.4, 0.9, 0.3)
	_prop.add_child(small)


## A stoppered bottle — tonics, teas, cordials.
func _build_flask(tint: Color) -> void:
	var body: MeshInstance3D = _mesh(_cylinder(0.085, 0.20, 12), _solid_material(tint))
	_prop.add_child(body)
	var neck: MeshInstance3D = _mesh(_cylinder(0.035, 0.09, 8), _solid_material(tint.lightened(0.25)))
	neck.position = Vector3(0.0, 0.14, 0.0)
	_prop.add_child(neck)


## A knotted loop — cords, tools, implements.
func _build_ring(tint: Color) -> void:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.10
	torus.outer_radius = 0.16
	torus.rings = 16
	var ring: MeshInstance3D = _mesh(torus, _solid_material(tint))
	ring.rotation = Vector3(1.1, 0.0, 0.25)
	_prop.add_child(ring)


## A flat marked disc — rubbings, pebbles, oddments, keys.
func _build_tablet(tint: Color) -> void:
	var disc: MeshInstance3D = _mesh(_cylinder(0.135, 0.035, 14), _solid_material(tint))
	disc.rotation = Vector3(0.42, 0.0, 0.18)
	_prop.add_child(disc)
	var mark: MeshInstance3D = _mesh(_box(Vector3(0.13, 0.008, 0.028)), _glow_material(tint, 2.2, 0.9))
	mark.position = Vector3(0.0, 0.024, 0.0)
	mark.rotation = Vector3(0.42, 0.6, 0.18)
	_prop.add_child(mark)


# --- Small builders ----------------------------------------------------------

func _mesh(m: Mesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIEW_RANGE
	mi.visibility_range_end_margin = 12.0
	return mi


func _box(size: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	return m


func _sphere(radius: float, segments: int) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(4, segments / 2)
	return m


func _cylinder(radius: float, height: float, segments: int) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


## Lit like the rest of the world, with just enough emission to catch the eye.
func _solid_material(albedo: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = 0.55
	mat.emission_enabled = true
	mat.emission = albedo.lightened(0.3)
	mat.emission_energy_multiplier = 0.55
	return mat


func _glow_material(tint: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

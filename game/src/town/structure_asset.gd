class_name StructureAsset
extends RefCounted
## Loads a Blender-authored building `.glb` and dresses it in the game's own
## materials — the runtime half of `docs/STRUCTURE_PIPELINE.md`.
##
## The pipeline rule is that a `.glb` carries **geometry and UVs only**
## (`export_materials="NONE"`), because the game's look lives in
## `assets/shaders/`. So an imported building arrives as a tree of unshaded
## MeshInstance3Ds named for their material group — `inn_plaster`, `inn_timber`,
## `inn_roof` — and something has to put the right shader on each. That is this.
##
## Matching is by **node-name substring**, deliberately: it means an artist can
## split `inn_timber` into `inn_timber_front` and `inn_timber_gable` in Blender
## for their own convenience and nothing here needs to change.
##
## Collision is generated here rather than exported, for the same reason the
## GDScript buildings did it: a player needs a wall that is one clean box, not a
## trimesh of three thousand roof tiles.

const SHADER: String = "res://assets/shaders/structure.gdshader"

## Surface kinds, matching the `kind` switch in `structure.gdshader`.
enum Kind {PLASTER = 0, TIMBER = 1, TILE = 2, STONE = 3, METAL = 4, GLASS = 5}

## One entry per material group: the shader parameters that make that material
## look like itself. `scale` is metres-per-repeat of the coarse pattern; `unit`
## must match the tile/stone module the Blender script actually laid down, or
## the per-unit tint grid cuts across the units instead of following them.
const SURFACES: Dictionary = {
	# Values are set for SEPARATION IN BRIGHTNESS first, hue second: at twenty
	# metres a facade is read as light panels between dark bones, and if those
	# two sit at similar values the whole building turns to mud. Grime is kept
	# low on everything above the plinth — the first pass ran it at 0.22-0.34
	# and the inn came out visibly sootier than every building around it.
	"plaster": {
		"kind": Kind.PLASTER, "color": Color(0.885, 0.860, 0.775),
		"rough": 0.92, "scale": 1.0, "bump": 0.85, "variation": 0.12,
		"grime": 0.20,
	},
	"timber": {
		"kind": Kind.TIMBER, "color": Color(0.325, 0.225, 0.150),
		"rough": 0.86, "scale": 1.0, "bump": 0.75, "variation": 0.20,
		"grime": 0.12,
	},
	"joinery": {
		"kind": Kind.TIMBER, "color": Color(0.375, 0.265, 0.170),
		"rough": 0.80, "scale": 1.4, "bump": 0.65, "variation": 0.18,
		"grime": 0.12,
	},
	"roof": {
		"kind": Kind.TILE, "color": Color(0.485, 0.245, 0.170),
		"rough": 0.88, "scale": 1.0, "bump": 0.45, "variation": 0.24,
		"grime": 0.18, "unit": Vector2(0.225, 0.128),
	},
	"stone": {
		"kind": Kind.STONE, "color": Color(0.520, 0.505, 0.460),
		"rough": 0.94, "scale": 1.0, "bump": 1.05, "variation": 0.22,
		# The plinth is the one place heavy grime is right: it is the splash
		# zone, and dirt there grounds the building instead of dirtying it.
		"grime": 0.42, "unit": Vector2(0.36, 0.19),
	},
	"chimney": {
		"kind": Kind.STONE, "color": Color(0.500, 0.487, 0.445),
		"rough": 0.94, "scale": 1.0, "bump": 1.05, "variation": 0.22,
		"grime": 0.16, "unit": Vector2(0.42, 0.22),
	},
	"signiron": {
		"kind": Kind.METAL, "color": Color(0.085, 0.085, 0.095),
		"rough": 0.44, "scale": 2.0, "bump": 0.5, "variation": 0.10,
		"grime": 0.10, "metallic": 0.85,
	},
	"iron": {
		"kind": Kind.METAL, "color": Color(0.095, 0.095, 0.105),
		"rough": 0.46, "scale": 2.0, "bump": 0.5, "variation": 0.10,
		"grime": 0.14, "metallic": 0.85,
	},
	"glass": {
		"kind": Kind.GLASS, "color": Color(0.115, 0.150, 0.175),
		"rough": 0.10, "scale": 1.0, "bump": 0.0, "variation": 0.05,
		"grime": 0.0,
	},
	# A signboard is PAINTED, so it gets the plaster pattern — a soft mottle —
	# rather than oak grain. Given wood grain it read as basketwork, because a
	# ring pattern on a small flat panel has nothing to be the grain of.
	"sign": {
		"kind": Kind.PLASTER, "color": Color(0.395, 0.275, 0.170),
		"rough": 0.74, "scale": 0.9, "bump": 0.30, "variation": 0.09,
		"grime": 0.12,
	},
	"dressing": {
		"kind": Kind.TIMBER, "color": Color(0.420, 0.310, 0.195),
		"rough": 0.86, "scale": 0.9, "bump": 0.6, "variation": 0.20,
		"grime": 0.18,
	},
	# Hand-thrown clay: pots by the inn door, tipped crock by the bench.
	# Plaster pattern (soft mottle), terracotta colour, a little smoother.
	"pottery": {
		"kind": Kind.PLASTER, "color": Color(0.560, 0.330, 0.210),
		"rough": 0.68, "scale": 1.8, "bump": 0.35, "variation": 0.14,
		"grime": 0.20,
	},
}

## Longest key first, so "signiron" wins over "iron" and "chimney" over the
## generic groups. Dictionary order in GDScript is insertion order, which is
## not sorted by length, so this is computed rather than assumed.
static var _match_order: PackedStringArray = _build_match_order()


static func _build_match_order() -> PackedStringArray:
	var keys: Array = SURFACES.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var out: PackedStringArray = PackedStringArray()
	for key: String in keys:
		out.append(key)
	return out


## Instance `path` under `parent`, shade every mesh, and give it one box
## collider of `footprint` (x, y, z) metres sitting on the origin's ground
## plane. Returns the root, or null if the asset is missing.
static func spawn(parent: Node3D, path: String, node_name: String,
		footprint: Vector3) -> Node3D:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("StructureAsset: cannot load %s" % path)
		return null
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	parent.add_child(body)
	var model: Node3D = packed.instantiate() as Node3D
	body.add_child(model)
	var shaded: int = _shade_tree(model)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = footprint
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, footprint.y * 0.5, 0.0)
	body.add_child(col)
	print("StructureAsset: %s — %d surfaces shaded." % [node_name, shaded])
	return body


## Walk the imported tree and apply a material to every MeshInstance3D.
static func _shade_tree(root: Node) -> int:
	var count: int = 0
	for node: Node in _walk(root):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null:
			continue
		var spec: Dictionary = _spec_for(mesh.name)
		if spec.is_empty():
			push_warning("StructureAsset: no surface for '%s' — left unshaded." % mesh.name)
			continue
		mesh.material_override = _material(spec)
		# Glass joins the same group the code-built windows use, so the town's
		# dusk pass finds an authored building's windows without knowing that
		# it came from a .glb. Skipping this is a silent regression: the inn
		# simply stops lighting up at night and nothing errors.
		if int(spec["kind"]) == Kind.GLASS:
			mesh.add_to_group(TownKit.GROUP_WINDOW)
		count += 1
	return count


static func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_walk(child))
	return out


## Longest matching key wins, so `inn_signiron` does not match `iron`.
static func _spec_for(mesh_name: String) -> Dictionary:
	var lower: String = mesh_name.to_lower()
	for key: String in _match_order:
		if lower.contains(key):
			return SURFACES[key] as Dictionary
	return {}


static func _material(spec: Dictionary) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(SHADER) as Shader
	mat.set_shader_parameter("albedo_tint", spec["color"])
	mat.set_shader_parameter("kind", int(spec["kind"]))
	mat.set_shader_parameter("roughness_base", float(spec["rough"]))
	mat.set_shader_parameter("metallic_base", float(spec.get("metallic", 0.0)))
	mat.set_shader_parameter("pattern_scale", float(spec["scale"]))
	mat.set_shader_parameter("bump_strength", float(spec["bump"]))
	mat.set_shader_parameter("value_variation", float(spec["variation"]))
	mat.set_shader_parameter("grime_amount", float(spec.get("grime", 0.25)))
	mat.set_shader_parameter("unit_size", spec.get("unit", Vector2(0.25, 0.15)))
	return mat

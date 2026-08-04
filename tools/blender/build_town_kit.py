"""Datasedge cob-and-thatch building kit, authored in Blender.

Authorised by GDD §10 Amendment 2026-08-03 (the structure split) and specified
by ``docs/STRUCTURE_PIPELINE.md``. Buildings are design decisions, so they leave
GDScript and become geometry a human can open and improve.

What this buys that ``town_building.gd`` could never have:

* **Bevel** on every hard edge. Nothing real has a zero-radius corner, and a
  1-3 cm bevel catching a highlight is the single biggest difference between
  "3D model" and "object".
* **Solidify**, so a wall has thickness and a window reveal has a visible
  depth — thick walls are most of what reads as *old*.
* **Boolean**, so an opening is cut through a wall instead of being four
  separate boxes arranged around a hole.
* **Custom split normals** at a 30 degree auto-smooth angle, so a thatch roof
  curves and a plank stays sharp.
* Real UVs.

Run::

    blender -b --python tools/blender/build_town_kit.py

Writes ``game/assets/models/town/kit_datasedge.glb``. Every part is a separate
object inside that one file; ``bootstrap_town.gd`` picks parts by node name.

Scale is metres, 1.0, against Kern at 1.75 m. Every dimension here comes from
the real-world table in STRUCTURE_PIPELINE.md §3 — none of them are invented.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

# --- Real-world dimensions (STRUCTURE_PIPELINE.md §3) -----------------------
MODULE = 1.0            # plan grid, metres
DOOR_W, DOOR_H = 0.95, 1.95      # Kern is 1.75 m and must clear the lintel
WIN_W, WIN_H = 0.90, 1.20
WIN_SILL = 0.90
WALL_T = 0.45           # cob: thick walls read as old
STOREY = 2.50           # floor to ceiling
EAVES = 0.60            # overhang; its shadow line is free depth
THATCH_PITCH = math.radians(50.0)   # must shed water
TILE_PITCH = math.radians(35.0)

BEVEL_WIDTH = 0.018     # ~2 cm
SMOOTH_ANGLE = math.radians(30.0)

OUT_DIR = os.path.join("game", "assets", "models", "town")
OUT_NAME = "kit_datasedge.glb"


# --- Blender helpers --------------------------------------------------------

def reset_scene():
    """Empty the file. `-b` still opens the startup scene with a cube in it."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_mesh(name):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def box(bm, centre, size):
    """Add an axis-aligned box to a bmesh. `centre` is its middle, `size` full."""
    matrix = None
    bmesh.ops.create_cube(bm, size=1.0, matrix=matrix)
    verts = [v for v in bm.verts if not hasattr(v, "_placed")]
    # create_cube makes a unit cube at the origin; scale and move the new verts.
    fresh = [v for v in bm.verts if v.tag is False]
    for v in fresh:
        v.co.x = v.co.x * size[0] + centre[0]
        v.co.y = v.co.y * size[1] + centre[1]
        v.co.z = v.co.z * size[2] + centre[2]
        v.tag = True
    return fresh


def add_box(bm, centre, size):
    """Append a box to `bm`, tagging existing verts so only the new ones move."""
    for v in bm.verts:
        v.tag = True
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        if not v.tag:
            v.co.x = v.co.x * size[0] + centre[0]
            v.co.y = v.co.y * size[1] + centre[1]
            v.co.z = v.co.z * size[2] + centre[2]


def add_prism(bm, centre, width, depth, height):
    """A gable prism: triangular in XZ, extruded along Y. Ridge runs +Y."""
    for v in bm.verts:
        v.tag = True
    hw, hd = width * 0.5, depth * 0.5
    profile = [
        (-hw, -hd, 0.0), (hw, -hd, 0.0), (0.0, -hd, height),
        (-hw, hd, 0.0), (hw, hd, 0.0), (0.0, hd, height),
    ]
    verts = [bm.verts.new((p[0] + centre[0], p[1] + centre[1], p[2] + centre[2]))
             for p in profile]
    faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    for f in faces:
        try:
            bm.faces.new([verts[i] for i in f])
        except ValueError:
            pass  # duplicate face; harmless


def clean(obj):
    """Weld coincident vertices, drop degenerate faces, and make normals agree.

    Booleans and stacked boxes both produce geometry that renders fine and
    exports badly. Doing this before the bevel matters: a bevel run over a
    non-manifold edge widens the fault instead of rounding it.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0005, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def finish(obj, bevel=True, bevel_width=BEVEL_WIDTH, segments=2, solidify=0.0):
    """Apply the modifier stack that GDScript never had, then bake it down.

    Order matters: solidify first so the bevel runs along the new inner edges
    too, then bevel, then smooth. Applying here rather than at export keeps the
    exported mesh honest about its own triangle count.
    """
    bpy.context.view_layer.objects.active = obj
    if solidify > 0.0:
        mod = obj.modifiers.new("solidify", "SOLIDIFY")
        mod.thickness = solidify
        mod.offset = 0.0
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel_width
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35.0)
        mod.harden_normals = False
    for mod in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError as exc:
            print("  ! modifier %s failed on %s: %s" % (mod.name, obj.name, exc))
    # Smooth shading with a sharp-edge angle: thatch curves, planks stay crisp.
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.set_sharp_from_angle(angle=SMOOTH_ANGLE)


def uv_project(obj, scale=0.5):
    """Box-project UVs by hand, in bmesh.

    `bpy.ops.uv.cube_project` needs edit mode, an active object AND a selection,
    and it fails with "context is incorrect" the moment any of those drift — in
    a headless script that is a whole class of failure for no benefit. Doing it
    directly is a dozen lines and cannot break.

    A box projection is the right unwrap for architecture: walls, roofs and
    floors are all near-planar, so choosing the axis each face most faces gives
    even texel density with no seam anyone will ever stand close enough to see.
    """
    if not obj.data.polygons:
        print("  ! %s has no faces to unwrap" % obj.name)
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:      # floor / roof: project down
                u, v = co.x, co.y
            elif ax >= ay:                 # east/west wall: project along X
                u, v = co.y, co.z
            else:                          # north/south wall: project along Y
                u, v = co.x, co.z
            loop[uv_layer].uv = (u * scale, v * scale)
    bm.to_mesh(obj.data)
    bm.free()


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# --- Kit parts --------------------------------------------------------------
#
# Origin convention (STRUCTURE_PIPELINE.md §5): centre of the footprint on the
# ground plane. Blender is Z-up here; the glTF exporter converts to Godot's
# Y-up on the way out.

def _solid_box(name, centre, size):
    """A standalone closed box object, for use as a boolean operand."""
    obj = new_mesh(name)
    bm = bmesh.new()
    add_box(bm, centre, size)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def _boolean(obj, cutter, operation):
    """Apply one boolean and delete the operand. Returns False if it emptied the
    mesh, which is the failure mode worth catching loudly — an exact boolean on
    coincident coplanar faces returns nothing at all rather than erroring."""
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("bool", "BOOLEAN")
    mod.operation = operation
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    if not obj.data.polygons:
        print("  ! %s: %s boolean emptied the mesh" % (obj.name, operation))
        return False
    return True


def wall_panel(length, name, door=False, window=False, window_x=0.0):
    """A cob wall on a stone plinth, with its openings BOOLEANED THROUGH.

    This part is most of why the structure split is worth doing. The GDScript
    version made an opening by arranging four boxes around a hole, which leaves
    no reveal — from any angle off square the wall was visibly paper. Cutting
    through a solid 0.45 m wall gives a real reveal, and that reveal is what the
    eye reads as masonry.

    Build order matters and cost two failed exports to learn: the plinth is
    UNIONED to the wall first, then the openings are cut from the single solid.
    Leaving them as two boxes that merely touch gives coincident coplanar faces,
    and Blender's exact solver answers that with an empty mesh — no error, just
    a part that silently vanishes.
    """
    plinth_h = 0.36
    obj = _solid_box(name, (0.0, 0.0, plinth_h + STOREY * 0.5),
                     (length, WALL_T, STOREY))
    # Overlap the plinth INTO the wall so the union has volume to work with.
    plinth = _solid_box(name + "_plinth", (0.0, 0.0, plinth_h * 0.5 + 0.02),
                        (length + 0.10, WALL_T + 0.10, plinth_h + 0.04))
    _boolean(obj, plinth, "UNION")

    if door:
        # Cut the doorway through wall AND plinth: a 0.36 m threshold is a step
        # nobody walks over.
        cutter = _solid_box(name + "_doorcut", (0.0, 0.0, DOOR_H * 0.5 - 0.1),
                            (DOOR_W, WALL_T * 3.0, DOOR_H + 0.2))
        _boolean(obj, cutter, "DIFFERENCE")
    if window:
        cutter = _solid_box(name + "_wincut",
                            (window_x, 0.0, plinth_h + WIN_SILL + WIN_H * 0.5),
                            (WIN_W, WALL_T * 3.0, WIN_H))
        _boolean(obj, cutter, "DIFFERENCE")

    clean(obj)
    finish(obj, bevel_width=0.022)
    uv_project(obj)
    return obj


def gable_roof(width, depth, name, pitch=THATCH_PITCH, thatch=True):
    """A pitched roof with real overhang. Thatch gets a thicker, softer edge;
    tile gets a thinner, crisper one, which is most of how the two read apart
    at distance."""
    obj = new_mesh(name)
    bm = bmesh.new()
    span = width + EAVES * 2.0
    height = (span * 0.5) * math.tan(pitch)
    add_prism(bm, (0.0, 0.0, 0.0), span, depth + EAVES * 2.0, height)
    bm.to_mesh(obj.data)
    bm.free()
    # Thatch is 0.35 m of packed straw; tile is 0.06 m of clay on battens.
    finish(obj, bevel_width=0.05 if thatch else 0.02,
           segments=3 if thatch else 2,
           solidify=0.35 if thatch else 0.09)
    uv_project(obj)
    return obj


def door_leaf(name):
    """Vertical planks with two ledger battens across — the plank-and-ledge door
    every pre-industrial village has, and one of the few props where the joint
    IS the design."""
    obj = new_mesh(name)
    bm = bmesh.new()
    planks = 5
    plank_w = DOOR_W / planks
    for i in range(planks):
        x = -DOOR_W * 0.5 + plank_w * (i + 0.5)
        add_box(bm, (x, 0.0, DOOR_H * 0.5), (plank_w * 0.92, 0.05, DOOR_H))
    for z in (DOOR_H * 0.22, DOOR_H * 0.78):
        add_box(bm, (0.0, -0.04, z), (DOOR_W * 0.92, 0.04, 0.14))
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, bevel_width=0.006, segments=1)
    uv_project(obj)
    return obj


def window_frame(name):
    """Frame plus mullion. The reveal comes from the wall's thickness, so this
    only has to sit in it."""
    obj = new_mesh(name)
    bm = bmesh.new()
    t = 0.07
    add_box(bm, (0.0, 0.0, WIN_H * 0.5), (WIN_W, t, t))            # sill
    add_box(bm, (0.0, 0.0, -WIN_H * 0.5), (WIN_W, t, t))           # head
    add_box(bm, (-WIN_W * 0.5, 0.0, 0.0), (t, t, WIN_H))           # jambs
    add_box(bm, (WIN_W * 0.5, 0.0, 0.0), (t, t, WIN_H))
    add_box(bm, (0.0, 0.0, 0.0), (0.05, t * 0.8, WIN_H))           # mullion
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, bevel_width=0.005, segments=1)
    uv_project(obj)
    return obj


def chimney(name, height=2.2):
    """Stone stack with a corbelled cap. The cap overhang is what stops a
    chimney reading as a pipe."""
    obj = new_mesh(name)
    bm = bmesh.new()
    add_box(bm, (0.0, 0.0, height * 0.5), (0.72, 0.72, height))
    add_box(bm, (0.0, 0.0, height + 0.06), (0.92, 0.92, 0.12))
    add_box(bm, (0.0, 0.0, height + 0.20), (0.78, 0.78, 0.16))
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, bevel_width=0.02)
    uv_project(obj)
    return obj


def porch(name):
    """Two posts and a lean-to roof. The cheapest attachment that changes a
    silhouette, and the one that says 'somebody lives here'."""
    obj = new_mesh(name)
    bm = bmesh.new()
    for x in (-0.75, 0.75):
        add_box(bm, (x, 0.0, 1.05), (0.13, 0.13, 2.10))
    # Sloped roof slab, low at the front.
    for v in range(1):
        add_box(bm, (0.0, -0.1, 2.24), (1.90, 1.45, 0.10))
    bm.to_mesh(obj.data)
    bm.free()
    # Tilt the slab by shearing the top verts forward and down.
    for v in obj.data.vertices:
        if v.co.z > 2.1:
            v.co.z -= (v.co.y + 0.8) * 0.16
    finish(obj, bevel_width=0.012)
    uv_project(obj)
    return obj


def lean_to(name):
    """The extension nobody planned. STRUCTURE_PIPELINE.md §4.2: every building
    gets at least one deliberate irregularity, and this is the kit's."""
    obj = new_mesh(name)
    bm = bmesh.new()
    add_box(bm, (0.0, 0.0, 1.05), (2.60, 2.20, 2.10))
    bm.to_mesh(obj.data)
    bm.free()
    for v in obj.data.vertices:
        if v.co.z > 1.0:
            v.co.z -= (v.co.y + 1.1) * 0.30   # mono-pitch, shedding away
    finish(obj, bevel_width=0.02, solidify=0.0)
    uv_project(obj)
    return obj


def fence_run(name, length=4.0):
    """Post-and-rail. Yards and gaps are architecture too (§4.7)."""
    obj = new_mesh(name)
    bm = bmesh.new()
    posts = int(length / 1.33) + 1
    for i in range(posts):
        x = -length * 0.5 + length * i / max(1, posts - 1)
        add_box(bm, (x, 0.0, 0.55), (0.10, 0.10, 1.10))
    for z in (0.42, 0.86):
        add_box(bm, (0.0, 0.0, z), (length, 0.045, 0.09))
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, bevel_width=0.006, segments=1)
    uv_project(obj)
    return obj


def build_kit():
    reset_scene()
    parts = []
    # Wall panels on the 1 m grid, in the lengths a cottage and a hall need.
    for length in (2, 3, 4, 5, 6):
        parts.append(wall_panel(float(length), "kit_cob_wall_%dm" % length))
    parts.append(wall_panel(4.0, "kit_cob_wall_4m_door", door=True))
    parts.append(wall_panel(4.0, "kit_cob_wall_4m_window", window=True))
    parts.append(wall_panel(6.0, "kit_cob_wall_6m_window", window=True, window_x=1.2))

    parts.append(gable_roof(6.0, 8.0, "kit_thatch_roof_6x8", THATCH_PITCH, True))
    parts.append(gable_roof(8.0, 10.0, "kit_thatch_roof_8x10", THATCH_PITCH, True))
    parts.append(gable_roof(11.0, 16.0, "kit_tile_roof_11x16", TILE_PITCH, False))

    parts.append(door_leaf("kit_shared_door_plank"))
    parts.append(window_frame("kit_shared_window"))
    parts.append(chimney("kit_shared_chimney"))
    parts.append(porch("kit_shared_porch"))
    parts.append(lean_to("kit_shared_leanto"))
    parts.append(fence_run("kit_shared_fence_4m", 4.0))

    total = 0
    print("--- kit parts ---")
    for obj in parts:
        count = tris(obj)
        total += count
        print("  %-28s %5d tris" % (obj.name, count))
    print("  %-28s %5d tris total" % ("", total))
    return parts, total


def export(parts):
    root = os.getcwd()
    out_dir = os.path.join(root, OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, OUT_NAME)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,              # Godot is Y-up
        export_normals=True,
        export_texcoords=True,
        export_materials="NONE",      # the game's look lives in assets/shaders
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    print("exported -> %s" % path)
    return path


def main():
    parts, total = build_kit()
    path = export(parts)
    budget = 250000
    if total > budget:
        print("WARNING: kit is %d tris, over the %d budget" % (total, budget))
    print("OK %d parts, %d tris, %s" % (len(parts), total, path))


if __name__ == "__main__":
    main()

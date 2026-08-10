"""Shared Blender authoring helpers for Gradientfall structures.

Authorised by GDD §10 Amendment 2026-08-03 (the structure split) and specified
by ``docs/STRUCTURE_PIPELINE.md``. ``build_town_kit.py`` predates this module
and still carries its own copies; new structures import from here.

WHY THIS EXISTS
---------------
The 2026-08-09 survey found Bootstrap reading as a prototype at eye level, and
the diagnosis was not "the shapes are wrong" — it was **detail density**. Every
surface was one flat colour on an unbevelled box. Raising detail density needs
two things this module provides and a hand-rolled script does not:

1. **Primitives that produce detail per call**, not per line of script. A
   ``beam`` between two points, a ``sweep`` along a curve, a ``scatter`` of
   jittered units. One call to ``sweep`` is a carved bracket; one call to
   ``jitter`` is the difference between "machined" and "built by someone".
2. **A render loop fast enough to actually look.** The survey's own conclusion
   was that quality is accumulated by iteration and the iteration count was
   three orders of magnitude too low. ``render_views`` renders a structure from
   authored angles straight out of the build script, so build-and-look is one
   command and a few seconds, not a Godot boot.

Everything here is metres, Z-up (Blender). The glTF exporter converts to
Godot's Y-up on the way out, which maps **Blender +Y to Godot -Z** — so a
structure authored with its front at +Y arrives facing -Z, the direction
``town_building.gd`` and ``bootstrap_town.gd`` have always called "front".
"""

import math
import os
import random

import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

#: Default bevel width. Nothing real has a zero-radius corner, and ~2 cm
#: catching a highlight is the single biggest "3D model" -> "object" step.
BEVEL_WIDTH = 0.018
#: Auto-smooth angle: below this an edge shades smooth, above it stays sharp.
SMOOTH_ANGLE = math.radians(32.0)


# --- Scene ------------------------------------------------------------------

def reset_scene():
    """Empty the file. ``-b`` still opens the startup scene with a cube in it."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_object(name):
    """An empty mesh object, linked into the scene collection."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


class Part:
    """One material group under construction.

    A structure exports as several objects — plaster, timber, roof, iron —
    because ``export_materials="NONE"`` is the pipeline rule and the game
    assigns its own shaders by node name. A Part is one of those groups: an
    open bmesh you keep adding to, closed once by :meth:`build`.
    """

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()

    def build(self, bevel=BEVEL_WIDTH, segments=2, smooth=True):
        """Close the bmesh into a real object and run the modifier stack."""
        obj = new_object(self.name)
        self.bm.to_mesh(obj.data)
        self.bm.free()
        self.bm = None
        clean(obj)
        if bevel > 0.0:
            bevel_edges(obj, bevel, segments)
        if smooth:
            shade_auto_smooth(obj)
        return obj


# --- Primitives -------------------------------------------------------------
#
# All of these append to an open bmesh and return the verts they added, so a
# caller can keep transforming or jittering them afterwards.

def _stamp(bm, matrix):
    """Add a unit cube and push it through ``matrix``. The workhorse."""
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=matrix, verts=verts)
    return verts


def stamp_group(bm, matrix, build):
    """Build a sub-assembly at the origin, then place it with one transform.

    THE primitive for detail at scale. Without it, a shutter is authored as
    loose parts whose *positions* are written in world space, so rotating the
    leaf rotates each plank about its own centre and the assembly fans apart —
    which is exactly how the first version of this building's shutters came
    out. With it, a shutter, a window or a dormer is authored once in its own
    local space (X across, Y outward, Z up) and stamped anywhere at any angle.

    ``build`` is called with a fresh bmesh and adds geometry around the origin.
    """
    tmp_mesh = bpy.data.meshes.new("_stamp_tmp")
    tmp = bmesh.new()
    build(tmp)
    bmesh.ops.transform(tmp, matrix=matrix, verts=tmp.verts)
    tmp.to_mesh(tmp_mesh)
    tmp.free()
    bm.from_mesh(tmp_mesh)          # from_mesh appends; it does not clear
    bpy.data.meshes.remove(tmp_mesh)


def place(location, yaw=0.0, pitch=0.0, roll=0.0):
    """Convenience transform for :func:`stamp_group`: move, then turn."""
    return (Matrix.Translation(Vector(location))
            @ Euler((pitch, roll, yaw)).to_matrix().to_4x4())


def clip_segment(p0, p1, umin, umax, vmin, vmax):
    """Clip a 2D segment to a rectangle (Liang-Barsky). ``None`` if outside.

    Needed anywhere a repeating pattern has to stop at an edge — leaded window
    cames, herringbone infill, plank cladding on a gable. Emitting the full
    line and hoping the wall hides the overshoot does not work: the first
    version of this building's leaded lights threw diagonal bars several
    metres out across the plaster.
    """
    x0, y0 = p0
    x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, x0 - umin), (dx, umax - x0),
                 (-dy, y0 - vmin), (dy, vmax - y0)):
        if abs(p) < 1e-12:
            if q < 0.0:
                return None
            continue
        r = q / p
        if p < 0.0:
            if r > t1:
                return None
            t0 = max(t0, r)
        else:
            if r < t0:
                return None
            t1 = min(t1, r)
    if t1 - t0 < 1e-6:
        return None
    return ((x0 + dx * t0, y0 + dy * t0), (x0 + dx * t1, y0 + dy * t1))


def wedge(bm, centre, span, height, thickness):
    """A triangular prism, apex up, extruded along X — a gable infill panel.

    Built as real geometry rather than a stack of boxes because a stepped
    approximation of a roof line is visible from the ground as a staircase,
    and no amount of jitter hides it.
    """
    cx, cy, cz = centre
    ht = thickness * 0.5
    hs = span * 0.5
    rings = []
    for sx in (-1.0, 1.0):
        rings.append([bm.verts.new((cx + sx * ht, cy - hs, cz)),
                      bm.verts.new((cx + sx * ht, cy + hs, cz)),
                      bm.verts.new((cx + sx * ht, cy, cz + height))])
    a, b = rings
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for k in range(3):
        bm.faces.new((a[k], a[(k + 1) % 3], b[(k + 1) % 3], b[k]))
    return a + b


def box(bm, centre, size, rot=None):
    """An axis-aligned (or Euler-rotated) box. ``size`` is full width, not half."""
    matrix = Matrix.Translation(Vector(centre))
    if rot is not None:
        matrix = matrix @ Euler(rot).to_matrix().to_4x4()
    matrix = matrix @ Matrix.Diagonal(Vector(size).to_4d())
    return _stamp(bm, matrix)


def beam(bm, start, end, width, height, roll=0.0):
    """A rectangular timber running from ``start`` to ``end``.

    Length comes from the two points, so a frame is authored as joinery —
    "post foot to bressumer" — instead of as a centre plus a size that has to
    be recomputed by hand every time the storey height moves.

    ``width`` is across the run, ``height`` is the other section axis, and
    ``roll`` spins the section about the run for a brace laid on its face.
    """
    p0, p1 = Vector(start), Vector(end)
    direction = p1 - p0
    length = direction.length
    if length < 1e-6:
        return []
    matrix = (Matrix.Translation((p0 + p1) * 0.5)
              @ _aim(direction).to_matrix().to_4x4()
              @ Matrix.Rotation(roll, 4, "X")
              @ Matrix.Diagonal(Vector((length, width, height)).to_4d()))
    return _stamp(bm, matrix)


def _aim(direction):
    """Rotation taking +X onto ``direction``, stable at the 180 degree case.

    ``Vector.rotation_difference`` picks an arbitrary axis when the two vectors
    are exactly opposed, which silently rolls a beam onto its side. Braces are
    frequently authored right-to-left, so this case is not hypothetical.
    """
    d = Vector(direction).normalized()
    if d.dot(Vector((1.0, 0.0, 0.0))) < -0.999999:
        return Quaternion((0.0, 0.0, 1.0), math.pi)
    return Vector((1.0, 0.0, 0.0)).rotation_difference(d)


def sweep(bm, path, width, height, up=(0.0, 0.0, 1.0), taper=None):
    """Sweep a rectangular section along a polyline and cap both ends.

    This is the curved-member primitive: corbel brackets, wrought-iron scrolls,
    braces with a real arc. A curve is the clearest signal in a building that a
    person shaped it rather than a loop emitting boxes, and it is unreachable
    with :func:`box` at any quantity.

    ``taper`` is an optional callable ``t -> scale`` over 0..1 along the path,
    for a bracket that thins toward its tip.
    """
    pts = [Vector(p) for p in path]
    if len(pts) < 2:
        return []
    up_v = Vector(up).normalized()
    rings = []
    for i, p in enumerate(pts):
        # Tangent by central difference, so the section stays square to a curve
        # rather than to each individual segment (which visibly facets).
        if i == 0:
            tangent = pts[1] - pts[0]
        elif i == len(pts) - 1:
            tangent = pts[-1] - pts[-2]
        else:
            tangent = pts[i + 1] - pts[i - 1]
        tangent.normalize()
        side = tangent.cross(up_v)
        if side.length < 1e-6:
            side = tangent.cross(Vector((0.0, 1.0, 0.0)))
        side.normalize()
        normal = side.cross(tangent).normalized()
        scale = 1.0 if taper is None else taper(i / float(len(pts) - 1))
        hw, hh = width * 0.5 * scale, height * 0.5 * scale
        rings.append([bm.verts.new(p + side * hw + normal * hh),
                      bm.verts.new(p - side * hw + normal * hh),
                      bm.verts.new(p - side * hw - normal * hh),
                      bm.verts.new(p + side * hw - normal * hh)])
    made = []
    for a, b in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    for ring in rings:
        made.extend(ring)
    return made


def arc(start, end, bulge, segments=8, axis=(1.0, 0.0, 0.0)):
    """Points along a circular-ish arc from ``start`` to ``end``.

    ``bulge`` is how far the middle bows away from the straight line, in metres,
    perpendicular to it and within the plane whose normal is ``axis``.
    """
    p0, p1 = Vector(start), Vector(end)
    chord = p1 - p0
    normal = chord.cross(Vector(axis))
    if normal.length < 1e-6:
        normal = chord.cross(Vector((0.0, 0.0, 1.0)))
    normal.normalize()
    pts = []
    for i in range(segments + 1):
        t = i / float(segments)
        pts.append(p0 + chord * t + normal * (bulge * math.sin(math.pi * t)))
    return pts


def cylinder(bm, centre, radius, height, segments=12, axis="Z", rot=None):
    """A capped cylinder — pegs, chimney pots, iron rings, ridge rolls."""
    matrix = Matrix.Translation(Vector(centre))
    if rot is not None:
        matrix = matrix @ Euler(rot).to_matrix().to_4x4()
    if axis == "X":
        matrix = matrix @ Matrix.Rotation(math.radians(90.0), 4, "Y")
    elif axis == "Y":
        matrix = matrix @ Matrix.Rotation(math.radians(-90.0), 4, "X")
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False,
                                segments=segments, radius1=radius,
                                radius2=radius, depth=height, matrix=matrix)
    return ret["verts"]


def half_round(bm, start, end, radius, segments=8):
    """A half-cylinder lying along a run, flat side down: ridge and hip tiles."""
    p0, p1 = Vector(start), Vector(end)
    direction = p1 - p0
    matrix = (Matrix.Translation((p0 + p1) * 0.5)
              @ _aim(direction).to_matrix().to_4x4()
              @ Matrix.Rotation(math.radians(90.0), 4, "Y"))
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments * 2,
                                radius1=radius, radius2=radius,
                                depth=direction.length, matrix=matrix)
    verts = ret["verts"]
    # Flatten everything below the axis onto it: a half-round sitting on a roof.
    axis_z = ((p0 + p1) * 0.5).z
    for v in verts:
        if v.co.z < axis_z:
            v.co.z = axis_z
    return verts


# --- Imperfection -----------------------------------------------------------

def jitter(verts, amount, rng, axes=(True, True, True)):
    """Nudge each vertex by up to ``amount`` metres.

    Straightness is the loudest tell that a building was emitted by a loop.
    Real timber warps, real stone is not square, real tiles do not line up.
    Called per part with a small amount (3-15 mm), this is most of the
    difference between "machined" and "built by someone".
    """
    for v in verts:
        v.co.x += rng.uniform(-amount, amount) if axes[0] else 0.0
        v.co.y += rng.uniform(-amount, amount) if axes[1] else 0.0
        v.co.z += rng.uniform(-amount, amount) if axes[2] else 0.0


def sag(verts, span_axis, centre, half_span, depth):
    """Bow a run of geometry downward toward its middle.

    An old roof ridge dips, a bressumer bellies, a shelf droops. The eye reads
    a dead-straight horizontal at this scale as new construction, and every
    building in a village that is centuries old reads wrong because of it.
    """
    index = {"X": 0, "Y": 1, "Z": 2}[span_axis]
    for v in verts:
        t = (v.co[index] - centre) / half_span
        v.co.z -= depth * max(0.0, 1.0 - t * t)


# --- Finishing --------------------------------------------------------------

def clean(obj):
    """Weld coincident verts, drop degenerate faces, make normals agree.

    Runs before the bevel on purpose: a bevel over a non-manifold edge widens
    the fault instead of rounding it.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0004, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def bevel_edges(obj, width=BEVEL_WIDTH, segments=2, angle=35.0):
    """Bevel every edge sharper than ``angle`` and bake it into the mesh."""
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    mod.use_clamp_overlap = True
    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError as exc:
        print("  ! bevel failed on %s: %s" % (obj.name, exc))


def shade_auto_smooth(obj, angle=SMOOTH_ANGLE):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.set_sharp_from_angle(angle=angle)


def uv_project(obj, scale=0.5):
    """Box-project UVs in bmesh — no operators, no edit mode, cannot break.

    A box projection is the right unwrap for architecture: walls, roofs and
    floors are all near-planar, so choosing the axis a face most faces gives
    even texel density and puts every seam on a corner.
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
            if az >= ax and az >= ay:
                u, v = co.x, co.y
            elif ax >= ay:
                u, v = co.y, co.z
            else:
                u, v = co.x, co.z
            loop[uv_layer].uv = (u * scale, v * scale)
    bm.to_mesh(obj.data)
    bm.free()


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def report(parts):
    """Print a triangle budget table and return the total."""
    total = 0
    print("--- parts ---")
    for obj in parts:
        count = tris(obj)
        total += count
        print("  %-24s %7d tris" % (obj.name, count))
    print("  %-24s %7d tris total" % ("", total))
    return total


def export_glb(parts, out_dir, out_name):
    """Export the given objects as one .glb, geometry and UVs only."""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, out_name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,            # Godot is Y-up; Blender +Y becomes Godot -Z
        export_normals=True,
        export_texcoords=True,
        export_materials="NONE",    # the game's look lives in assets/shaders
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    print("exported -> %s" % path)
    return path


# --- The look loop ----------------------------------------------------------

def _sun(name, rotation, energy, colour=(1.0, 0.96, 0.9)):
    light = bpy.data.lights.new(name, type="SUN")
    light.energy = energy
    light.color = colour
    light.angle = math.radians(2.5)
    obj = bpy.data.objects.new(name, light)
    obj.rotation_euler = Euler(rotation)
    bpy.context.collection.objects.link(obj)
    return obj


def setup_studio(sky=(0.30, 0.44, 0.66), ground=(0.28, 0.26, 0.22)):
    """A neutral outdoor studio: key sun, sky fill, and a ground plane.

    Deliberately plain. This is for judging a building, so nothing here may
    flatter it — no rim light, no dramatic angle, no coloured practicals.
    """
    world = bpy.data.worlds.new("studio")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (sky[0], sky[1], sky[2], 1.0)
    bg.inputs[1].default_value = 1.0
    bpy.context.scene.world = world
    # Sky strength is deliberately low. A bright sky fills every shadow evenly
    # and flattens exactly the crevice detail the building was built for — the
    # first version of this studio washed the whole facade blue and hid it.
    bg.inputs[1].default_value = 0.28
    _sun("key", (math.radians(52.0), 0.0, math.radians(128.0)), 4.2,
         (1.0, 0.94, 0.84))
    _sun("fill", (math.radians(64.0), 0.0, math.radians(-40.0)), 0.55,
         (0.72, 0.80, 1.0))
    ground_mesh = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    box(bm, (0.0, 0.0, -0.25), (120.0, 120.0, 0.5))
    bm.to_mesh(ground_mesh)
    bm.free()
    obj = bpy.data.objects.new("ground", ground_mesh)
    bpy.context.collection.objects.link(obj)
    mat = bpy.data.materials.new("ground")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        ground[0], ground[1], ground[2], 1.0)
    obj.data.materials.append(mat)
    return obj


def human_scale(height=1.75):
    """A 1.75 m block figure — Kern's height — to stand beside the building.

    STRUCTURE_PIPELINE §3 says wrong scale is the commonest reason a game
    village reads as a toy and that it is invisible until someone stands next
    to it. So someone stands next to it in every render.
    """
    obj = new_object("scale_figure")
    bm = bmesh.new()
    box(bm, (0.0, 0.0, height * 0.44), (0.42, 0.26, height * 0.52))
    box(bm, (0.0, 0.0, height * 0.09), (0.34, 0.24, height * 0.18))
    cylinder(bm, (0.0, 0.0, height * 0.79), 0.115, height * 0.16, 10)
    box(bm, (0.0, 0.0, height * 0.93), (0.19, 0.21, 0.23))
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def preview_materials(scheme):
    """Assign flat Principled materials by object-name substring.

    Purely for the look loop — the shipped ``.glb`` carries no materials, per
    the pipeline rule that the game's look lives in ``assets/shaders``. But a
    render with no materials at all cannot answer the question that actually
    decides whether a building works at gameplay distance: **does it read in
    value?** A facade where timber and plaster sit at the same brightness is
    mud from twenty metres no matter how good the geometry is.

    ``scheme`` maps a substring of the object name to
    ``(r, g, b, roughness)``. First match wins, so order it specific-first.
    """
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for key, (r, g, b, rough) in scheme.items():
            if key in obj.name:
                mat = bpy.data.materials.new("prev_" + key)
                mat.use_nodes = True
                bsdf = mat.node_tree.nodes["Principled BSDF"]
                bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
                bsdf.inputs["Roughness"].default_value = rough
                obj.data.materials.clear()
                obj.data.materials.append(mat)
                break


def render_views(outdir, views, target=(0.0, 0.0, 3.0), res=1100, engine=None,
                 samples=24, lens=52.0):
    """Render the scene from named viewpoints. The whole point of the tool.

    ``views`` maps a filename stem to a dict with ``bearing`` (degrees around
    the structure; 0 looks at its +Y face, the front), ``elev`` (degrees above
    the target), ``dist`` (metres), and optionally its own ``target`` and
    ``lens``.

    Framing is the caller's job and it is easy to get wrong: with a 52 mm lens
    on a 16:9 frame the vertical field is only ~22 degrees, so an eight-metre
    building needs close to thirty metres of standoff to fit — roughly twice
    the distance that intuition suggests.
    """
    scene = bpy.context.scene
    engine = engine or _pick_engine()
    scene.render.engine = engine
    if engine.startswith("BLENDER_EEVEE"):
        try:
            scene.eevee.taa_render_samples = samples
        except AttributeError:
            pass
    elif engine == "BLENDER_WORKBENCH":
        shading = scene.display.shading
        shading.light = "STUDIO"
        shading.show_cavity = True
        shading.cavity_type = "BOTH"
        shading.curvature_ridge_factor = 1.6
        shading.curvature_valley_factor = 1.6
    scene.render.resolution_x = int(res * 16 / 9)
    scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"

    cam_data = bpy.data.cameras.new("shot")
    cam = bpy.data.objects.new("shot", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    os.makedirs(outdir, exist_ok=True)
    written = []
    for name, spec in views.items():
        cam_data.lens = spec.get("lens", lens)
        focus = Vector(spec.get("target", target))
        yaw = math.radians(spec["bearing"])
        pitch = math.radians(spec["elev"])
        offset = Vector((math.sin(yaw) * math.cos(pitch),
                         math.cos(yaw) * math.cos(pitch),
                         math.sin(pitch))) * spec["dist"]
        cam.location = focus + offset
        direction = focus - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(outdir, name + ".png")
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
        print("  rendered %s" % scene.render.filepath)
    return written


def _pick_engine():
    """EEVEE if this build offers it, Workbench otherwise.

    Blender renamed the EEVEE engine id across 4.x/5.x and background rendering
    without a GPU context is not guaranteed, so this asks rather than assumes.
    Workbench is a genuinely good fallback for judging *form* — flat studio
    light plus cavity shading is what modellers judge shape in, with no
    material or lighting able to flatter the result.
    """
    available = {item.identifier for item in
                 bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    for candidate in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        if candidate in available:
            return candidate
    return "BLENDER_WORKBENCH"


def rng_for(seed_text):
    """A named, deterministic RNG, so a rebuild reproduces the same building."""
    return random.Random(hash(seed_text) & 0xFFFFFFFF)

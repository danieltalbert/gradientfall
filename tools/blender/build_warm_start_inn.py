"""The Warm Start Inn — Bootstrap's hero building, authored in Blender.

Run::

    blender -b --python tools/blender/build_warm_start_inn.py
    blender -b --python tools/blender/build_warm_start_inn.py -- --render C:/dir

Writes ``game/assets/models/town/warm_start_inn.glb``. Every material group is
a separate named object inside it; the game assigns shaders by node name.

WHY THIS BUILDING, AND WHY LIKE THIS
------------------------------------
The 2026-08-09 survey photographed Bootstrap at eye level for the first time
and found it reading as a prototype. The diagnosis was **detail density**, not
wrong shapes: every surface was one flat colour on an unbevelled box, with no
texture, no wear and no asymmetry anywhere in the town. This file is the test
of whether that is fixable — one building taken to a genuinely finished
standard, so the cost of "finished" is known before twenty-three more are
built to the same bar.

The detail here is deliberately of five specific kinds, because these are the
five the old town had none of:

1. **Unit geometry.** The plinth is stones, the roof is tiles, the chimney is
   courses. Not a stone-coloured box, a *stone-shaped stone*, times nine
   hundred. This is the single biggest change and most of the triangles.
2. **Real joinery.** Posts, sill, bressumer, wall plate, close studding, and
   curved corner braces that meet where a carpenter would join them — plus
   pegs at the joints. The frame is structure, not stripes painted on plaster.
3. **Depth at every opening.** Walls are a real 0.28 m thick and openings are
   booleaned through, so each window has a reveal that catches a shadow. The
   old town made a hole by arranging four boxes around it.
4. **Curves.** Corbel brackets under the jetty and the wrought-iron sign
   bracket are swept along arcs. A curve is the clearest possible signal that
   a person shaped a thing, and it is unreachable from an axis-aligned box.
5. **Imperfection.** The ridge sags, timbers warp a few millimetres, stones
   are uneven, tiles sit at slightly different angles. Dead-straight geometry
   reads as new construction; this village is supposed to be old.

Scale is metres against Kern at 1.75 m, per ``docs/STRUCTURE_PIPELINE.md`` §3.
Front is +Y in Blender, which the glTF exporter turns into Godot's -Z.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bkit  # noqa: E402  (must follow the sys.path fix-up)


# --- Dimensions -------------------------------------------------------------
# Every number is measured against Kern at 1.75 m. A coaching inn is the tallest
# thing in a village of cottages, and this one is deliberately allowed to be.

W = 9.0                 # ground-floor width  (X)
D = 6.0                 # ground-floor depth  (Y), front face at +Y
WALL_T = 0.28           # panel thickness — this IS the window reveal
PLINTH_H = 0.52         # stone splash course
GF_TOP = 2.62           # top of ground-floor framing
BRESS_H = 0.32          # bressumer beam depth
UF_BOT = GF_TOP + BRESS_H
UF_TOP = 5.15           # top of the upper wall plate
JETTY = 0.42            # upper storey overhang, front and both sides

W2 = W + JETTY * 2.0    # upper storey width
FRONT2 = D * 0.5 + JETTY
BACK = -D * 0.5

EAVES = 0.55            # roof overhang past the wall
VERGE = 0.45            # roof overhang past the gable
PITCH = math.radians(38.0)
RIDGE_Y = (FRONT2 + BACK) * 0.5
#: Half the roofed span AT THE WALL. The roof plane passes through the wall
#: head here, so this — not the eaves half-span — is what sets ridge height.
WALL_HALF = (FRONT2 - BACK) * 0.5
#: Half the tile field, i.e. out to the dripping edge past the eaves.
HALF_SPAN = WALL_HALF + EAVES
#: Height of the eaves line: the overhang keeps falling past the wall head.
EAVE_Z = UF_TOP - EAVES * math.tan(PITCH)
#: Ridge height. Deriving this from HALF_SPAN instead of WALL_HALF was the
#: single arithmetic error behind four separate visible faults in v1 — the
#: ridge tiles floated 0.43 m above the top tile course as a bar in the sky,
#: the gable infill overshot the roof on both slopes as a white band along the
#: verge, and the barge boards sloped at 42 degrees over a 38 degree roof.
RIDGE_Z = UF_TOP + WALL_HALF * math.tan(PITCH)
ROOF_HALF_X = W2 * 0.5 + VERGE

POST = 0.22             # corner post section
STUD = 0.13             # intermediate stud section
PROUD = 0.055           # how far framing stands out of its plaster panel

DOOR_W, DOOR_H = 1.06, 2.08
WIN_W, WIN_H = 1.12, 1.16
WIN_SILL = 0.98         # ground floor
UWIN_W, UWIN_H = 0.94, 1.02
#: Upper-storey sill height above the jetty floor. At the first setting (0.78)
#: the window heads ran into the wall plate and the whole row read as a dark
#: slot jammed under the eaves; 0.55 leaves a band of wall above them.
UPPER_SILL = UF_BOT + 0.55

#: Door lantern position, Blender space. The housing is modelled here; the
#: flame and the OmniLight3D are placed by bootstrap_town.gd at the Godot
#: equivalent of this point, printed by the build for exactly that purpose.
LANTERN_AT = (1.12, D * 0.5 + 0.30, 2.28)

OUT_DIR = os.path.join("game", "assets", "models", "town")
OUT_NAME = "warm_start_inn.glb"


def slope_len():
    """Rafter length from eave to ridge, along the pitch."""
    return HALF_SPAN / math.cos(PITCH)


# --- Boolean plumbing -------------------------------------------------------

def solid(name, centre, size):
    """A standalone closed box, for use as a boolean operand."""
    obj = bkit.new_object(name)
    bm = bmesh.new()
    bkit.box(bm, centre, size)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def cut(obj, openings):
    """Difference a list of ``(centre, size)`` boxes out of ``obj``.

    Each opening is cut separately and checked. An exact boolean against
    coincident coplanar faces returns an *empty mesh* rather than an error, so
    a silent failure here would otherwise show up as a missing wall in-game.
    """
    for i, (centre, size) in enumerate(openings):
        cutter = solid("%s_cut%d" % (obj.name, i), centre, size)
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new("bool", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        mod.solver = "EXACT"
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter, do_unlink=True)
        if not obj.data.polygons:
            raise RuntimeError("%s: opening %d emptied the mesh" % (obj.name, i))


def shell(bm, centre, size, thickness, open_top=True, open_bottom=True):
    """Four walls of ``thickness`` around a footprint — a storey, not a block.

    Built as four overlapping slabs rather than a solid minus a solid: the
    subtraction produces coplanar faces at every corner, which is exactly the
    input the exact boolean solver answers with an empty mesh.
    """
    cx, cy, cz = centre
    sx, sy, sz = size
    hx, hy = sx * 0.5, sy * 0.5
    t = thickness
    bkit.box(bm, (cx, cy + hy - t * 0.5, cz), (sx, t, sz))          # front
    bkit.box(bm, (cx, cy - hy + t * 0.5, cz), (sx, t, sz))          # back
    bkit.box(bm, (cx - hx + t * 0.5, cy, cz), (t, sy - t * 2.0, sz))  # left
    bkit.box(bm, (cx + hx - t * 0.5, cy, cz), (t, sy - t * 2.0, sz))  # right
    if not open_bottom:
        bkit.box(bm, (cx, cy, cz - sz * 0.5 + t * 0.5), (sx, sy, t))
    if not open_top:
        bkit.box(bm, (cx, cy, cz + sz * 0.5 - t * 0.5), (sx, sy, t))


# --- Stonework --------------------------------------------------------------

def stone_face(bm, axis, plane, outward, u0, u1, v0, v1, rng,
               course=0.19, unit=0.36, depth=0.075, taper=0.0):
    """Tile one wall face with running-bond rubble standing proud of it.

    ``axis`` is the face's normal axis ("X" or "Y"), ``plane`` its coordinate,
    ``outward`` +1/-1. Stones are laid in courses with a half-unit offset every
    other course, each one jittered in length, height and how far it stands out.

    Only the outward face is stoned — the core behind it is a plain box. That
    keeps a full stone plinth around a nine-metre building at ~700 units
    instead of the ~2,000 a solid ring of real stones would cost, and nothing
    can ever see the difference.
    """
    made = []
    v = v0
    row = 0
    while v < v1 - 0.001:
        h = min(course * rng.uniform(0.82, 1.18), v1 - v)
        u = u0 - (unit * 0.5 if row % 2 else 0.0)
        while u < u1 - 0.001:
            length = unit * rng.uniform(0.55, 1.35)
            lo, hi = max(u, u0), min(u + length, u1)
            if hi - lo > 0.06:
                d = depth * rng.uniform(0.55, 1.15)
                # Taper pulls the face in as it rises, for a battered chimney.
                pull = taper * (v - v0)
                pos = plane + outward * (d * 0.5 - pull)
                cu, cv = (lo + hi) * 0.5, v + h * 0.5
                size_u, size_v = (hi - lo) * 0.94, h * 0.9
                if axis == "Y":
                    centre = (cu, pos, cv)
                    size = (size_u, d, size_v)
                else:
                    centre = (pos, cu, cv)
                    size = (d, size_u, size_v)
                verts = bkit.box(bm, centre, size)
                bkit.jitter(verts, 0.012, rng)
                made.extend(verts)
            u += length + 0.018
        v += h + 0.016
        row += 1
    return made


def build_stone(rng):
    """The plinth: a stone splash course the whole building sits on."""
    part = bkit.Part("inn_stone")
    bm = part.bm
    # Core, so the plinth is solid even where a stone happens to be thin.
    bkit.box(bm, (0.0, 0.0, PLINTH_H * 0.5), (W + 0.05, D + 0.05, PLINTH_H))
    hx, hy = (W + 0.05) * 0.5, (D + 0.05) * 0.5
    for axis, plane, outward, a0, a1 in (
            ("Y", hy, 1.0, -hx, hx), ("Y", -hy, -1.0, -hx, hx),
            ("X", hx, 1.0, -hy, hy), ("X", -hx, -1.0, -hy, hy)):
        stone_face(bm, axis, plane, outward, a0, a1, 0.0, PLINTH_H, rng)
    # A weathered capping course, slightly oversailing, that throws a shadow
    # line along the whole building at ankle height.
    bkit.box(bm, (0.0, 0.0, PLINTH_H + 0.045), (W + 0.20, D + 0.20, 0.09))
    # Threshold slab, worn into a dish by two centuries of boots.
    step = bkit.box(bm, (0.0, D * 0.5 + 0.30, 0.10), (1.7, 0.75, 0.20))
    bkit.sag(step, "X", 0.0, 0.85, 0.035)
    return part.build(bevel=0.010, segments=1)


def build_chimney(rng):
    """A stone stack on the west gable, from the ground to a metre above ridge.

    External, battered, and leaning 1.2 degrees. It is the tallest thing on the
    building and does most of the work in the silhouette.
    """
    part = bkit.Part("inn_chimney")
    bm = part.bm
    top_z = RIDGE_Z + 1.05
    x = -W * 0.5 - 0.42
    base_w, base_d = 1.55, 2.05
    # The core is battered in the same steps the stone facing is, so the two
    # stay in contact all the way up. The first version tapered only the
    # facing, by 16 mm per metre — over eight metres that is 130 mm, far more
    # than the 80 mm the stones stand proud, so every stone above waist height
    # sank inside the core and the stack rendered as a smooth white pipe.
    steps = 7
    for i in range(steps):
        z0 = top_z * i / steps
        z1 = top_z * (i + 1) / steps
        pull = 0.045 * i
        bkit.box(bm, (x, 0.0, (z0 + z1) * 0.5),
                 (base_w - pull * 2.0, base_d - pull * 2.0, z1 - z0 + 0.01))
    hx, hy = base_w * 0.5, base_d * 0.5
    for axis, plane, outward, a0, a1 in (
            ("X", x - hx, -1.0, -hy, hy),
            ("Y", hy, 1.0, x - hx, x + hx),
            ("Y", -hy, -1.0, x - hx, x + hx)):
        stone_face(bm, axis, plane, outward, a0, a1, 0.0, top_z - 0.55, rng,
                   # Matched to the core's batter: 0.045 m per step over
                   # top_z/7 metres is 0.034 m per metre. Facing and core must
                   # pull in at the same rate or one swallows the other.
                   course=0.22, unit=0.42, depth=0.085, taper=0.034)
    # Two oversailing courses make the cap, which is what stops a chimney
    # reading as a pipe.
    bkit.box(bm, (x, 0.0, top_z - 0.42), (base_w + 0.16, base_d + 0.16, 0.14))
    bkit.box(bm, (x, 0.0, top_z - 0.26), (base_w + 0.28, base_d + 0.28, 0.16))
    for offset in (-0.52, 0.52):
        bkit.cylinder(bm, (x, offset, top_z + 0.16), 0.19, 0.62, 10)
        bkit.cylinder(bm, (x, offset, top_z + 0.47), 0.22, 0.09, 10)
    obj = part.build(bevel=0.012, segments=1)
    obj.rotation_euler = (math.radians(1.2), 0.0, 0.0)
    return obj


# --- Plaster ----------------------------------------------------------------

def build_plaster():
    """Both storeys' infill panels, with every opening cut through the wall."""
    part = bkit.Part("inn_plaster")
    bm = part.bm
    gf_h = GF_TOP - PLINTH_H
    shell(bm, (0.0, 0.0, PLINTH_H + gf_h * 0.5), (W, D, gf_h), WALL_T)
    uf_h = UF_TOP - UF_BOT
    shell(bm, (0.0, (FRONT2 + BACK) * 0.5, UF_BOT + uf_h * 0.5),
          (W2, FRONT2 - BACK, uf_h), WALL_T)
    # Gable infill above the upper wall plate, both ends. A real wedge, not a
    # stack of boxes: at this pitch a stepped approximation reads from the
    # ground as a white staircase climbing the roof, which is exactly what the
    # first render of this building showed.
    #
    # The span has to be taken at the WALL, not at the eaves. HALF_SPAN
    # includes the eaves overhang, so using it here pushed the gable 0.55 m
    # out past the tiles on both slopes.
    gable_span = WALL_HALF
    for sx in (-1.0, 1.0):
        gx = sx * (W2 * 0.5 - WALL_T * 0.5)
        # Dropped 0.09 clear of the roof plane. Built flush, the wedge's
        # sloping edge and the tile undersides are within a few millimetres of
        # each other, and once the roof's sag and the tiles' own jitter are
        # applied the plaster surfaces through the tiles as a pale stripe down
        # both verges.
        bkit.wedge(bm, (gx, RIDGE_Y, UF_TOP - 0.11),
                   gable_span * 2.0, RIDGE_Z - UF_TOP + 0.02, WALL_T)
    for x in DORMER_X:
        bkit.stamp_group(bm, bkit.place((x, DORMER_Y, DORMER_Z)), _dormer_shell)
    obj = part.build(bevel=0.008, segments=1)
    openings = []
    fy = D * 0.5
    openings.append(((0.0, fy, PLINTH_H + DOOR_H * 0.5 - 0.1),
                     (DOOR_W, WALL_T * 4.0, DOOR_H)))
    for x in (-2.55, 2.55):
        openings.append(((x, fy, WIN_SILL + WIN_H * 0.5),
                         (WIN_W, WALL_T * 4.0, WIN_H)))
    for sx in (-1.0, 1.0):
        openings.append(((sx * W * 0.5, 0.55, WIN_SILL + WIN_H * 0.5),
                         (WALL_T * 4.0, WIN_W, WIN_H)))
    uz = UPPER_SILL + UWIN_H * 0.5
    for x in (-3.15, -1.05, 1.05, 3.15):
        openings.append(((x, FRONT2, uz), (UWIN_W, WALL_T * 4.0, UWIN_H)))
    for sx in (-1.0, 1.0):
        openings.append(((sx * W2 * 0.5, 0.2, uz), (WALL_T * 4.0, UWIN_W, UWIN_H)))
    for x in (-2.2, 2.2):
        openings.append(((x, BACK, uz), (UWIN_W, WALL_T * 4.0, UWIN_H)))
    for x in DORMER_X:
        openings.append(((x, DORMER_Y - 0.06, DORMER_Z + 0.52),
                         (DORMER_WIN[0], 0.9, DORMER_WIN[1])))
    cut(obj, openings)
    bkit.uv_project(obj, 0.5)
    return obj


# --- The frame --------------------------------------------------------------

def build_timber(rng):
    """Posts, rails, close studding, curved braces, pegs, jetty and rafters."""
    part = bkit.Part("inn_timber")
    bm = part.bm
    fy = D * 0.5
    face = fy + PROUD          # front framing plane, ground floor
    face2 = FRONT2 + PROUD     # front framing plane, upper floor
    all_verts = []

    def member(p0, p1, w, h, warp=0.006):
        verts = bkit.beam(bm, p0, p1, w, h)
        bkit.jitter(verts, warp, rng)
        all_verts.extend(verts)
        return verts

    def peg(centre, axis="Y"):
        bkit.cylinder(bm, centre, 0.028, PROUD + 0.03, 6, axis=axis)

    # --- Ground floor, front ------------------------------------------------
    member((-W * 0.5, face, PLINTH_H), (W * 0.5, face, PLINTH_H), W, 0.0) \
        if False else None
    # Sill beam on the plinth, and the bressumer over it.
    member((-W * 0.5, face, PLINTH_H + 0.09), (W * 0.5, face, PLINTH_H + 0.09),
           0.20, 0.18)
    bress = member((-W2 * 0.5, face2 - 0.02, GF_TOP + BRESS_H * 0.5),
                   (W2 * 0.5, face2 - 0.02, GF_TOP + BRESS_H * 0.5),
                   0.30, BRESS_H)
    bkit.sag(bress, "X", 0.0, W2 * 0.5, 0.035)
    # Corner posts and door posts.
    for x in (-W * 0.5 + POST * 0.5, W * 0.5 - POST * 0.5,
              -DOOR_W * 0.5 - 0.13, DOOR_W * 0.5 + 0.13):
        member((x, face, PLINTH_H), (x, face, GF_TOP), POST, POST)
        peg((x, face, PLINTH_H + 0.28))
        peg((x, face, GF_TOP - 0.24))
    # Close studding between the openings — the expensive-looking frame.
    for x in (-3.75, -3.15, -1.95, -1.35, 1.35, 1.95, 3.15, 3.75):
        member((x, face, PLINTH_H + 0.14), (x, face, GF_TOP), STUD, STUD * 0.8)
    # Head and sill rails around each ground-floor window.
    for x in (-2.55, 2.55):
        for z in (WIN_SILL - 0.09, WIN_SILL + WIN_H + 0.09):
            member((x - WIN_W * 0.5 - 0.22, face, z),
                   (x + WIN_W * 0.5 + 0.22, face, z), 0.16, 0.13)
    member((-DOOR_W * 0.5 - 0.26, face, PLINTH_H + DOOR_H - 0.06),
           (DOOR_W * 0.5 + 0.26, face, PLINTH_H + DOOR_H - 0.06), 0.20, 0.17)

    # --- Curved corner braces ----------------------------------------------
    # The characterful member. A straight brace reads as bracing; a curved one
    # reads as a carpenter's decision.
    for sx in (-1.0, 1.0):
        px = sx * (W * 0.5 - POST * 0.5)
        bkit.sweep(bm, bkit.arc((px, face, GF_TOP - 1.15),
                                (px - sx * 1.15, face, GF_TOP - 0.03),
                                0.20, 10, axis=(0.0, 1.0, 0.0)),
                   0.155, 0.13, up=(0.0, 1.0, 0.0))
        # And the same on the return face, so corners read from both sides.
        sxf = sx * (W * 0.5 + PROUD)
        bkit.sweep(bm, bkit.arc((sxf, fy - 0.12, GF_TOP - 1.15),
                                (sxf, fy - 1.25, GF_TOP - 0.03),
                                0.20, 10, axis=(1.0, 0.0, 0.0)),
                   0.155, 0.13, up=(1.0, 0.0, 0.0))

    # --- Jetty --------------------------------------------------------------
    # Corbel brackets: swept ogees carrying the overhang. Six on the front,
    # two per side. These are the first thing a player sees from the square.
    for x in (-3.6, -1.8, 0.0, 1.8, 3.6):
        path = bkit.arc((x, fy - 0.05, GF_TOP - 0.72),
                        (x, face2 - 0.06, GF_TOP + 0.10), 0.19, 9,
                        axis=(1.0, 0.0, 0.0))
        bkit.sweep(bm, path, 0.15, 0.20, up=(1.0, 0.0, 0.0),
                   taper=lambda t: 1.0 - 0.30 * t)
    for sx in (-1.0, 1.0):
        for y in (-1.6, 1.4):
            path = bkit.arc((sx * (W * 0.5 - 0.05), y, GF_TOP - 0.72),
                            (sx * (W2 * 0.5 - 0.06), y, GF_TOP + 0.10), 0.19, 9,
                            axis=(0.0, 1.0, 0.0))
            bkit.sweep(bm, path, 0.15, 0.20, up=(0.0, 1.0, 0.0),
                       taper=lambda t: 1.0 - 0.30 * t)
    # Exposed joist ends along the underside of the jetty.
    for x in [-4.2 + i * 0.62 for i in range(14)]:
        bkit.box(bm, (x, face2 - 0.16, GF_TOP - 0.02), (0.11, 0.30, 0.13))
    # Side bressumers.
    for sx in (-1.0, 1.0):
        member((sx * (W2 * 0.5 - 0.02), BACK, GF_TOP + BRESS_H * 0.5),
               (sx * (W2 * 0.5 - 0.02), FRONT2, GF_TOP + BRESS_H * 0.5),
               0.30, BRESS_H)

    # --- Upper floor --------------------------------------------------------
    for x in (-W2 * 0.5 + POST * 0.5, W2 * 0.5 - POST * 0.5):
        member((x, face2, UF_BOT), (x, face2, UF_TOP), POST, POST)
    # Close studding: an upper storey of a good inn is densely studded, and
    # density here is nearly free while reading as expensive carpentry.
    for i in range(15):
        x = -W2 * 0.5 + 0.62 + i * 0.62
        member((x, face2, UF_BOT), (x, face2, UF_TOP), STUD, STUD * 0.8)
    # Sill rail, carrying the whole upper window row. It has to sit BELOW
    # UPPER_SILL — at its first height it ran straight through the glass.
    mid = member((-W2 * 0.5, face2, UPPER_SILL - 0.11),
                 (W2 * 0.5, face2, UPPER_SILL - 0.11), 0.20, 0.16)
    bkit.sag(mid, "X", 0.0, W2 * 0.5, 0.02)
    plate = member((-W2 * 0.5, face2, UF_TOP - 0.11), (W2 * 0.5, face2, UF_TOP - 0.11),
                   0.24, 0.22)
    bkit.sag(plate, "X", 0.0, W2 * 0.5, 0.03)
    # Side walls: posts, plate, studs.
    for sx in (-1.0, 1.0):
        px = sx * (W2 * 0.5 + PROUD)
        member((px, BACK, UF_TOP - 0.11), (px, FRONT2, UF_TOP - 0.11), 0.24, 0.22)
        for i in range(9):
            y = BACK + 0.55 + i * 0.72
            member((px, y, UF_BOT), (px, y, UF_TOP), STUD, STUD * 0.8)

    # --- Side and back elevations ------------------------------------------
    # The first render made this omission obvious: only the front had a frame,
    # so the gable elevation was a blank white box the size of a house. A
    # building is seen from every side in an open world and there is no such
    # thing as a back.
    for sx in (-1.0, 1.0):
        px = sx * (W * 0.5 + PROUD)
        member((px, BACK, PLINTH_H + 0.09), (px, D * 0.5, PLINTH_H + 0.09), 0.20, 0.18)
        for y in (BACK + POST * 0.5, D * 0.5 - POST * 0.5):
            member((px, y, PLINTH_H), (px, y, GF_TOP), POST, POST)
        for i in range(6):
            y = BACK + 0.86 + i * 0.86
            member((px, y, PLINTH_H + 0.14), (px, y, GF_TOP), STUD, STUD * 0.8)
        for z in (WIN_SILL - 0.09, WIN_SILL + WIN_H + 0.09):
            member((px, 0.55 - WIN_W * 0.5 - 0.24, z),
                   (px, 0.55 + WIN_W * 0.5 + 0.24, z), 0.16, 0.13)
    by = BACK - PROUD
    member((-W * 0.5, by, PLINTH_H + 0.09), (W * 0.5, by, PLINTH_H + 0.09), 0.20, 0.18)
    member((-W * 0.5, by, GF_TOP - 0.11), (W * 0.5, by, GF_TOP - 0.11), 0.22, 0.20)
    for i in range(10):
        x = -W * 0.5 + 0.82 + i * 0.82
        member((x, by, PLINTH_H + 0.14), (x, by, GF_TOP), STUD, STUD * 0.8)
    for sx in (-1.0, 1.0):
        bx = sx * (W2 * 0.5 + PROUD)
        member((bx, BACK - PROUD, UF_BOT), (bx, BACK - PROUD, UF_TOP), POST, POST)
        member((-W2 * 0.5, BACK - PROUD, UF_BOT + 1.02),
               (W2 * 0.5, BACK - PROUD, UF_BOT + 1.02), 0.20, 0.16)
    for i in range(13):
        x = -W2 * 0.5 + 0.72 + i * 0.72
        member((x, BACK - PROUD, UF_BOT), (x, BACK - PROUD, UF_TOP), STUD, STUD * 0.8)

    # --- Gable framing ------------------------------------------------------
    # Tie beam, collar, king post and raking studs. The gable is a whole
    # elevation and it faced the square as a blank white triangle.
    gable_span = WALL_HALF
    for sx in (-1.0, 1.0):
        gx = sx * (W2 * 0.5 + PROUD)
        member((gx, RIDGE_Y - gable_span, UF_TOP + 0.06),
               (gx, RIDGE_Y + gable_span, UF_TOP + 0.06), 0.26, 0.22)
        collar_z = UF_TOP + (RIDGE_Z - UF_TOP) * 0.52
        collar_half = gable_span * 0.48
        member((gx, RIDGE_Y - collar_half, collar_z),
               (gx, RIDGE_Y + collar_half, collar_z), 0.20, 0.17)
        member((gx, RIDGE_Y, UF_TOP + 0.06), (gx, RIDGE_Y, RIDGE_Z - 0.10), 0.19, 0.19)
        for frac in (0.32, 0.66):
            hs = gable_span * (1.0 - frac)
            for sy in (-1.0, 1.0):
                member((gx, RIDGE_Y + sy * hs, UF_TOP + 0.06),
                       (gx, RIDGE_Y + sy * hs * 0.34,
                        UF_TOP + (RIDGE_Z - UF_TOP) * (1.0 - 0.34) * frac + 0.06),
                       STUD, STUD * 0.8)

    for x in DORMER_X:
        bkit.stamp_group(bm, bkit.place((x, DORMER_Y, DORMER_Z)), _dormer_timber)

    # --- Roof structure -----------------------------------------------------
    # Rafter tails poking past the eaves, and barge boards on the gables. Both
    # are pure silhouette: they break the roof's edge so it stops reading as a
    # folded card.
    drop = EAVES * math.tan(PITCH)
    for i in range(19):
        x = -W2 * 0.5 + 0.02 + i * (W2 - 0.04) / 18.0
        for sy, wall_y in ((1.0, FRONT2), (-1.0, BACK)):
            bkit.beam(bm, (x, wall_y, UF_TOP + 0.04),
                      (x, wall_y + sy * EAVES, UF_TOP + 0.04 - drop), 0.09, 0.13)
    # The barge board follows the ACTUAL roof plane. Its foot is at the eaves
    # line, which is EAVES*tan(pitch) BELOW the wall plate, not level with it —
    # getting that wrong left both boards floating a third of a metre above the
    # tiles, reading as a scaffolding pole laid across the roof.
    eave_z = UF_TOP - drop
    for sx in (-1.0, 1.0):
        bx = sx * (ROOF_HALF_X - 0.09)
        for sy in (-1.0, 1.0):
            bkit.beam(bm, (bx, RIDGE_Y + sy * HALF_SPAN, eave_z + 0.05),
                      (bx, RIDGE_Y, RIDGE_Z + 0.05), 0.26, 0.10)
    obj = part.build(bevel=0.014, segments=1)
    bkit.uv_project(obj, 0.6)
    return obj


# --- Roof -------------------------------------------------------------------

#: Where the dormers sit on the front slope, measured up the pitch from the
#: eaves so they follow the roof if any of its dimensions move.
DORMER_X = (-2.35, 2.35)
DORMER_RUN = 1.05
DORMER_Y = RIDGE_Y + HALF_SPAN - DORMER_RUN * math.cos(PITCH)
DORMER_Z = EAVE_Z + DORMER_RUN * math.sin(PITCH)
DORMER_W = 1.34
DORMER_WALL = 0.92          # cheek height at the front face
DORMER_RISE = 0.46          # its own little gable
DORMER_DEPTH = 1.75         # how far back into the main slope it cuts


#: Dormer local space: origin at the middle of its front face where that face
#: meets the main roof slope; +Y points out of the building, +Z up. Every
#: dormer piece below is authored in it and stamped by :func:`bkit.stamp_group`.
DORMER_WIN = (0.74, 0.66)


def _dormer_shell(bm):
    """The dormer's plaster: front panel and two cheeks."""
    hw = DORMER_W * 0.5
    bkit.box(bm, (0.0, -0.06, DORMER_WALL * 0.5),
             (DORMER_W - 0.14, 0.12, DORMER_WALL))
    for sx in (-1.0, 1.0):
        bkit.box(bm, (sx * (hw - 0.06), -DORMER_DEPTH * 0.5, DORMER_WALL * 0.5),
                 (0.11, DORMER_DEPTH, DORMER_WALL))


def _dormer_timber(bm):
    """Corner posts, head beam and barge boards for one dormer."""
    hw = DORMER_W * 0.5
    for sx in (-1.0, 1.0):
        bkit.beam(bm, (sx * (hw - 0.03), 0.02, 0.0),
                  (sx * (hw - 0.03), 0.02, DORMER_WALL), 0.10, 0.09)
        # Barge board along the dormer's own pitch, from its eave to its apex.
        bkit.beam(bm, (sx * (hw + 0.16), 0.05, DORMER_WALL - 0.10),
                  (0.0, 0.05, DORMER_WALL + DORMER_RISE + 0.04), 0.16, 0.07)
    bkit.beam(bm, (-hw, 0.02, DORMER_WALL - 0.055),
              (hw, 0.02, DORMER_WALL - 0.055), 0.13, 0.11)


def _dormer_tiles(bm, rng):
    """One dormer's gable infill and tiled roof, same local space."""
    hw = DORMER_W * 0.5
    pitch = math.atan2(DORMER_RISE, hw)
    # Gable infill. The wedge primitive spans Y and extrudes along X, so it is
    # stamped with a quarter turn to face out of the dormer instead of across.
    # Span and rise matched to the dormer's own tile pitch, and set 0.05 below
    # it, for the same reason the main gable is: a wedge built flush with the
    # tiles shows through them.
    bkit.stamp_group(bm, bkit.place((0.0, -0.02, DORMER_WALL - 0.05),
                                    yaw=math.radians(90.0)),
                     lambda b: bkit.wedge(b, (0.0, 0.0, 0.0), DORMER_W - 0.14,
                                          (DORMER_W - 0.14) * 0.5 * math.tan(pitch),
                                          0.12))
    # Its own tiny tiled roof, in courses like the big one.
    slope = math.hypot(hw + 0.14, DORMER_RISE)
    gauge, tile_w = 0.115, 0.20
    for sx in (-1.0, 1.0):
        for c in range(int(slope / gauge) + 1):
            run = min(c * gauge, slope)
            x = sx * (hw + 0.14 - run * math.cos(pitch))
            z = DORMER_WALL - 0.09 + run * math.sin(pitch)
            for i in range(int(DORMER_DEPTH / tile_w) + 2):
                y = 0.16 - i * tile_w
                if y < -DORMER_DEPTH - 0.1:
                    continue
                verts = bkit.box(bm, (x, y, z + 0.02),
                                 (0.19, tile_w * 0.93, 0.024),
                                 rot=(0.0, sx * pitch + rng.uniform(-0.03, 0.03),
                                      0.0))
                bkit.jitter(verts, 0.005, rng)
    for i in range(int(DORMER_DEPTH / 0.38) + 1):
        bkit.half_round(bm, (0.0, 0.18 - i * 0.38, DORMER_WALL + DORMER_RISE + 0.01),
                        (0.0, 0.18 - (i + 1) * 0.38,
                         DORMER_WALL + DORMER_RISE + 0.01), 0.085, 5)


def build_roof(rng):
    """A tiled roof laid course by course, one object per tile.

    ~3,500 individual tiles. This is by far the largest single cost in the
    building and it buys the largest single improvement: a roof is the biggest
    unbroken surface on any house, and a flat-shaded plane there is what made
    every Bootstrap building read as cardboard. Tiles are *not* bevelled — the
    gap between them already reads as an edge, and bevelling 3,500 boxes would
    quadruple the triangle count for nothing.
    """
    part = bkit.Part("inn_roof")
    bm = part.bm
    tile_w, gauge = 0.225, 0.128
    courses = int(math.ceil(slope_len() / gauge))
    across = int(math.ceil((ROOF_HALF_X * 2.0) / tile_w)) + 1
    # A solid deck under the tiles. Plain tiling is laid with a 7% gap between
    # neighbours in a course, and with nothing behind it every one of those
    # joints showed daylight — from above the roof read as a lattice rather
    # than a surface. Real tiles sit on battens over a boarded slope; this is
    # that slope, and it costs twelve triangles.
    for sy in (-1.0, 1.0):
        mid = slope_len() * 0.5
        bkit.box(bm,
                 (0.0,
                  RIDGE_Y + sy * (HALF_SPAN - mid * math.cos(PITCH)),
                  # 0.085 below the tile plane. At 0.02 the deck's own top
                  # surface sat proud of the tile undersides and swallowed
                  # them, turning the whole roof back into a smooth plane.
                  EAVE_Z + mid * math.sin(PITCH) - 0.085),
                 (ROOF_HALF_X * 2.0, slope_len() + 0.10, 0.07),
                 rot=(-sy * PITCH, 0.0, 0.0))
    for sy in (-1.0, 1.0):
        for c in range(courses):
            run = min(c * gauge, slope_len())
            y = RIDGE_Y + sy * (HALF_SPAN - run * math.cos(PITCH))
            z = EAVE_Z + run * math.sin(PITCH)
            # The eaves course is doubled in real tiling, and the double line
            # of shadow at the bottom edge is very visible from the ground.
            layers = (0.0, 0.052) if c == 0 else (0.0,)
            for lift in layers:
                for i in range(across):
                    x = -ROOF_HALF_X + tile_w * (i + 0.5) + (tile_w * 0.5 if c % 2 else 0.0)
                    if x > ROOF_HALF_X - 0.02:
                        continue
                    verts = bkit.box(
                        bm, (x, y - sy * 0.055, z + 0.028 + lift),
                        (tile_w * 0.93, 0.20, 0.026),
                        # NEGATIVE sy: a rotation of +pitch about X tips the
                        # tile's up-slope edge the wrong way, standing every
                        # tile on end as a fin you can see daylight between.
                        rot=(-sy * PITCH + rng.uniform(-0.03, 0.03),
                             0.0, rng.uniform(-0.02, 0.02)))
                    bkit.jitter(verts, 0.006, rng)
    # Two dormers on the front slope. Pure silhouette work: an eight-metre
    # unbroken tile field is the biggest single surface on the building and it
    # reads as a slab from the square no matter how good the tiles are. A
    # dormer breaks the ridge line, throws its own shadow, and gives the inn
    # the upstairs rooms a coaching inn is supposed to have.
    for x in DORMER_X:
        bkit.stamp_group(bm, bkit.place((x, DORMER_Y, DORMER_Z)),
                         lambda b: _dormer_tiles(b, rng))

    # Ridge rolls along the top, each a short half-round with its own angle.
    n_ridge = int((ROOF_HALF_X * 2.0) / 0.40)
    for i in range(n_ridge):
        x0 = -ROOF_HALF_X + i * 0.40
        verts = bkit.half_round(bm, (x0, RIDGE_Y, RIDGE_Z + 0.02),
                                (x0 + 0.415, RIDGE_Y, RIDGE_Z + 0.02), 0.115, 6)
        bkit.jitter(verts, 0.008, rng)
    obj = part.build(bevel=0.0, smooth=False)
    # The whole roof sags toward the middle of its span, ridge and tiles alike.
    bm2 = bmesh.new()
    bm2.from_mesh(obj.data)
    bkit.sag(list(bm2.verts), "X", 0.0, ROOF_HALF_X, 0.075)
    bm2.to_mesh(obj.data)
    bm2.free()
    bkit.uv_project(obj, 1.2)
    return obj


# --- Joinery, glass, iron ---------------------------------------------------

#: How far the window frame sits back from the outer wall face. This IS the
#: reveal, and the shadow it throws is most of what reads as a thick wall.
REVEAL = 0.13


def _cames(bm, sw, sh, rng):
    """Lead cames dividing a pane into diamond quarries, clipped to the pane.

    Leaded lights are the most period-correct thing an inn can have and they
    cost almost nothing — a lattice of 14 mm bars. Each came is generated as an
    infinite 45 degree line and then **clipped to the opening**; the first
    version skipped the clip and threw diagonal bars several metres out across
    the plaster, which is the single ugliest thing in the v1 renders.
    """
    hw, hh = sw * 0.5, sh * 0.5
    step = 0.175
    reach = (sw + sh) * 0.75
    n = int(reach / step) + 2
    for sign in (-1.0, 1.0):
        for k in range(-n, n + 1):
            c = k * step * math.sqrt(2.0)
            # Line v = sign*u + c, sampled well outside the pane then clipped.
            p0 = (-reach, sign * -reach + c)
            p1 = (reach, sign * reach + c)
            seg = bkit.clip_segment(p0, p1, -hw, hw, -hh, hh)
            if seg is None:
                continue
            (u0, v0), (u1, v1) = seg
            if math.hypot(u1 - u0, v1 - v0) < 0.05:
                continue
            verts = bkit.beam(bm, (u0, 0.0, v0), (u1, 0.0, v1), 0.016, 0.014)
            bkit.jitter(verts, 0.0015, rng)


def _shutter_leaf(bm, leaf_w, leaf_h, rng):
    """A plank shutter authored from its hinge: boards, ledges, brace.

    Origin is the hinge edge; the leaf runs along +X. Built in local space so
    :func:`bkit.stamp_group` can swing it about the hinge as one rigid body —
    doing this in world coordinates rotated each plank about its own centre
    and fanned the leaf apart, which is what v1 did.
    """
    n = 3
    for i in range(n):
        px = (i + 0.5) * leaf_w / n
        verts = bkit.box(bm, (px, 0.0, 0.0),
                         (leaf_w / n - 0.014, 0.038, leaf_h))
        bkit.jitter(verts, 0.004, rng)
    for dz in (-1.0, 1.0):
        bkit.box(bm, (leaf_w * 0.5, -0.032, dz * leaf_h * 0.33),
                 (leaf_w - 0.02, 0.028, 0.105))
    bkit.beam(bm, (0.03, -0.032, -leaf_h * 0.30),
              (leaf_w - 0.05, -0.032, leaf_h * 0.30), 0.026, 0.085)


def _shutter_iron(bm, leaf_w, leaf_h):
    """Strap hinges and a ring pull for one shutter leaf, same local space."""
    for dz in (-1.0, 1.0):
        bkit.box(bm, (leaf_w * 0.42, 0.026, dz * leaf_h * 0.33),
                 (leaf_w * 0.78, 0.014, 0.052))
        bkit.box(bm, (0.05, 0.026, dz * leaf_h * 0.33), (0.14, 0.016, 0.10))
    bkit.cylinder(bm, (leaf_w - 0.10, 0.05, 0.0), 0.045, 0.018, 10, axis="Y")


def build_openings(rng):
    """Window frames with reveals, leaded lights, shutters, and the door.

    Every window is authored ONCE in its own local space — origin at the
    centre of the opening on the outer wall face, +X across, +Y outward, +Z up
    — and stamped onto whichever elevation needs it. That is what makes eight
    windows on four different walls cost one description instead of four
    hand-transformed copies, and it is why the side elevations can afford the
    same window quality as the front.
    """
    joinery = bkit.Part("inn_joinery")
    glass = bkit.Part("inn_glass")
    iron = bkit.Part("inn_iron")
    bj, bg, bi = joinery.bm, glass.bm, iron.bm
    fy = D * 0.5

    def win_joinery(bm, sw, sh, shutters, ajar):
        for dx in (-1.0, 1.0):
            bkit.box(bm, (dx * (sw * 0.5 - 0.035), -REVEAL, 0.0),
                     (0.07, 0.10, sh + 0.02))
        bkit.box(bm, (0.0, -REVEAL, sh * 0.5 - 0.035), (sw, 0.10, 0.07))
        bkit.box(bm, (0.0, -REVEAL, -sh * 0.5 + 0.035), (sw, 0.10, 0.07))
        bkit.box(bm, (0.0, -REVEAL, 0.0), (0.062, 0.10, sh))       # mullion
        # Sill: sloped, oversailing, with a drip batten under its nose. Sills
        # throw the strongest single shadow on any facade.
        bkit.box(bm, (0.0, 0.04, -sh * 0.5 - 0.05), (sw + 0.30, 0.36, 0.075),
                 rot=(-0.14, 0.0, 0.0))
        bkit.box(bm, (0.0, 0.19, -sh * 0.5 - 0.10), (sw + 0.24, 0.05, 0.055))
        if not shutters:
            return
        leaf_w, leaf_h = sw * 0.5 + 0.055, sh + 0.07
        for dx in (-1.0, 1.0):
            hinge = (dx * (sw * 0.5 + 0.045), 0.055, 0.0)
            swing = ajar if dx > 0 else 0.0
            yaw = (math.pi - swing) if dx > 0 else swing
            bkit.stamp_group(bm, bkit.place(hinge, yaw=yaw),
                             lambda b, w=leaf_w, h=leaf_h: _shutter_leaf(b, w, h, rng))

    def win_glass(bm, sw, sh):
        bkit.box(bm, (0.0, -REVEAL, 0.0), (sw - 0.10, 0.012, sh - 0.10))

    def win_iron(bm, sw, sh, shutters, ajar):
        bkit.stamp_group(bm, bkit.place((0.0, -REVEAL + 0.014, 0.0)),
                         lambda b: _cames(b, sw - 0.11, sh - 0.11, rng))
        if not shutters:
            return
        leaf_w, leaf_h = sw * 0.5 + 0.055, sh + 0.07
        for dx in (-1.0, 1.0):
            hinge = (dx * (sw * 0.5 + 0.045), 0.055, 0.0)
            swing = ajar if dx > 0 else 0.0
            yaw = (math.pi - swing) if dx > 0 else swing
            bkit.stamp_group(bm, bkit.place(hinge, yaw=yaw),
                             lambda b, w=leaf_w, h=leaf_h: _shutter_iron(b, w, h))

    def window(location, yaw, size, shutters=True, ajar=0.0):
        sw, sh = size
        matrix = bkit.place(location, yaw=yaw)
        bkit.stamp_group(bj, matrix,
                         lambda b: win_joinery(b, sw, sh, shutters, ajar))
        bkit.stamp_group(bg, matrix, lambda b: win_glass(b, sw, sh))
        bkit.stamp_group(bi, matrix, lambda b: win_iron(b, sw, sh, shutters, ajar))

    # Ground floor: two shuttered windows on the front, one on each side.
    gz = WIN_SILL + WIN_H * 0.5
    window((-2.55, fy, gz), 0.0, (WIN_W, WIN_H), ajar=0.0)
    window((2.55, fy, gz), 0.0, (WIN_W, WIN_H), ajar=0.62)
    window((W * 0.5, 0.55, gz), math.radians(-90.0), (WIN_W, WIN_H), ajar=0.34)
    window((-W * 0.5, 0.55, gz), math.radians(90.0), (WIN_W, WIN_H), ajar=0.0)
    uz = UPPER_SILL + UWIN_H * 0.5
    for x in (-3.15, -1.05, 1.05, 3.15):
        window((x, FRONT2, uz), 0.0, (UWIN_W, UWIN_H), shutters=False)
    window((W2 * 0.5, 0.2, uz), math.radians(-90.0), (UWIN_W, UWIN_H), shutters=False)
    window((-W2 * 0.5, 0.2, uz), math.radians(90.0), (UWIN_W, UWIN_H), shutters=False)
    for x in (-2.2, 2.2):
        window((x, BACK, uz), math.pi, (UWIN_W, UWIN_H), shutters=False)
    for x in DORMER_X:
        window((x, DORMER_Y, DORMER_Z + 0.52), 0.0, DORMER_WIN, shutters=False)

    # --- The door -----------------------------------------------------------
    dz0 = PLINTH_H - 0.10
    dcz = dz0 + DOOR_H * 0.5
    dy = fy - 0.10
    for i in range(5):
        px = (i - 2) * (DOOR_W / 5.0)
        verts = bkit.box(bj, (px, dy, dcz), (DOOR_W / 5.0 - 0.014, 0.055, DOOR_H))
        bkit.jitter(verts, 0.004, rng)
    for dzf in (-0.36, 0.0, 0.36):
        bkit.box(bj, (0.0, dy - 0.04, dcz + dzf * DOOR_H), (DOOR_W, 0.03, 0.12))
    # Iron: strap hinges with flared ends, ring handle, and a grid of studs.
    for dzf in (-0.33, 0.33):
        bkit.box(bi, (-0.06, dy + 0.032, dcz + dzf * DOOR_H),
                 (DOOR_W * 0.82, 0.016, 0.075))
        bkit.box(bi, (-DOOR_W * 0.5 + 0.10, dy + 0.032, dcz + dzf * DOOR_H),
                 (0.20, 0.018, 0.14))
    bkit.cylinder(bi, (DOOR_W * 0.28, dy + 0.055, dcz + 0.02), 0.075, 0.022, 12, axis="Y")
    bkit.cylinder(bi, (DOOR_W * 0.28, dy + 0.055, dcz + 0.02), 0.052, 0.030, 12, axis="Y")
    bkit.box(bi, (DOOR_W * 0.28, dy + 0.04, dcz + 0.16), (0.10, 0.02, 0.13))
    for r in range(3):
        for c in range(4):
            bkit.cylinder(bi, (-0.40 + c * 0.27, dy + 0.045, dcz - 0.55 + r * 0.55),
                          0.022, 0.020, 6, axis="Y")

    # --- Door lantern -------------------------------------------------------
    # Housing only. The flame and the light it casts are placed by
    # bootstrap_town.gd at LANTERN_LOCAL, because lights are runtime state the
    # day/night cycle drives and a .glb has no business carrying them. A flame
    # with no housing reads as a floating bead by daylight, so the housing has
    # to exist in the model even though nothing lights it there.
    lz = LANTERN_AT[2]
    bkit.box(bi, (LANTERN_AT[0] - 0.20, fy + 0.16, lz + 0.30), (0.42, 0.055, 0.055))
    bkit.box(bi, (LANTERN_AT[0], LANTERN_AT[1], lz), (0.24, 0.24, 0.30))
    bkit.cylinder(bi, (LANTERN_AT[0], LANTERN_AT[1], lz + 0.20), 0.21, 0.13, 4,
                  rot=(0.0, 0.0, math.radians(45.0)))
    for sx in (-1.0, 1.0):
        for sy2 in (-1.0, 1.0):
            bkit.box(bi, (LANTERN_AT[0] + sx * 0.105, LANTERN_AT[1] + sy2 * 0.105, lz),
                     (0.028, 0.028, 0.30))

    # --- Door hood ----------------------------------------------------------
    hood_z = dz0 + DOOR_H + 0.28
    for sx in (-1.0, 1.0):
        bkit.sweep(bj, bkit.arc((sx * 0.78, fy + 0.04, hood_z - 0.62),
                                (sx * 0.62, fy + 0.86, hood_z - 0.04), 0.16, 8,
                                axis=(1.0, 0.0, 0.0)),
                   0.11, 0.15, up=(1.0, 0.0, 0.0))
    for i in range(9):
        yy = fy + 0.06 + i * 0.105
        bkit.box(bj, (0.0, yy, hood_z + 0.20 - i * 0.036), (2.05, 0.115, 0.045),
                 rot=(-0.33, 0.0, 0.0))
    bkit.box(bj, (0.0, fy + 0.03, hood_z + 0.26), (2.15, 0.10, 0.13))

    return (joinery.build(bevel=0.008, segments=1),
            glass.build(bevel=0.0, smooth=False),
            iron.build(bevel=0.005, segments=1))


def build_sign(rng):
    """The Warm Start's signboard, hung CLEAR of the jetty this time.

    The 2026-08-09 survey found the old sign built 0.09-0.19 m *inside* the
    jettied upper storey, invisible from every angle. The bracket here is
    mounted on the ground-floor wall and reaches past the jetty's front face,
    so the board hangs in open air where the square can see it.
    """
    part = bkit.Part("inn_sign")
    iron = bkit.Part("inn_signiron")
    bm, bi = part.bm, iron.bm
    x = -2.55
    wall = FRONT2 + PROUD           # the UPPER storey's face
    arm_z = 3.62
    reach = 1.40
    tip = wall + reach
    # Mounted on the upper storey, not under the jetty. Hanging it from the
    # ground floor is what buried the old one: the jetty projects 0.42 m and
    # any bracket short enough to look sane down there leaves the board in the
    # overhang's shadow. From up here the board hangs almost a metre clear of
    # the jetty face and reads from anywhere in the square.
    bkit.box(bi, (x, wall + reach * 0.5, arm_z), (0.055, reach, 0.05))
    bkit.box(bi, (x, wall - 0.02, arm_z - 0.10), (0.16, 0.10, 0.34))
    # Curved stay under the arm, and a wrought scroll at the tip.
    bkit.sweep(bi, bkit.arc((x, wall + 0.05, arm_z - 0.72),
                            (x, tip - 0.22, arm_z - 0.03),
                            0.22, 10, axis=(1.0, 0.0, 0.0)),
               0.042, 0.042, up=(1.0, 0.0, 0.0))
    scroll = []
    for i in range(11):
        a = i * 0.52
        r = 0.155 * (1.0 - i * 0.055)
        scroll.append((x, tip - 0.05 + r * math.sin(a), arm_z + 0.155 - r * math.cos(a)))
    bkit.sweep(bi, scroll, 0.034, 0.034, up=(1.0, 0.0, 0.0))
    # Cross-bar at the tip, and chains from its ends down to the board.
    #
    # The board hangs ACROSS the bracket, facing out from the wall, not along
    # it. A sign hung the usual way — faces parallel to the street — is right
    # for a building on a street, and wrong for this one: the Warm Start faces
    # an open square, everyone approaches it head-on, and hung the usual way
    # the board is edge-on to every single one of them.
    by, bz = tip - 0.12, arm_z - 0.72
    bkit.box(bi, (x, by, arm_z - 0.02), (1.06, 0.042, 0.042))
    for dx in (-0.44, 0.44):
        bkit.box(bi, (x + dx, by, arm_z - 0.19), (0.020, 0.020, 0.30))
    # Board: a raised border on both faces, and hung very slightly askew.
    board = bkit.box(bm, (x, by, bz), (1.30, 0.075, 0.80), rot=(0.0, 0.03, 0.0))
    for sy in (-1.0, 1.0):
        bkit.box(bm, (x, by + sy * 0.048, bz), (1.14, 0.022, 0.64),
                 rot=(0.0, 0.03, 0.0))
    bkit.jitter(board, 0.004, rng)
    print("sign board (Godot local): Vector3(%.2f, %.2f, %.2f)" % (x, bz, -by))
    return part.build(bevel=0.010, segments=2), iron.build(bevel=0.004, segments=1)


def build_dressing(rng):
    """Bench, barrels, firewood — the things that say somebody lives here."""
    part = bkit.Part("inn_dressing")
    bm = part.bm
    fy = D * 0.5
    # Bench under the front window: worn seat, splayed legs.
    seat = bkit.box(bm, (2.55, fy + 0.62, 0.50), (1.85, 0.42, 0.075))
    bkit.sag(seat, "X", 2.55, 0.92, 0.028)
    for dx in (-0.72, 0.72):
        for dy in (-0.13, 0.13):
            bkit.box(bm, (2.55 + dx, fy + 0.62 + dy, 0.24), (0.085, 0.075, 0.48),
                     rot=(0.0, math.radians(4.0) * (1 if dx > 0 else -1), 0.0))
    bkit.box(bm, (2.55, fy + 0.80, 0.78), (1.75, 0.06, 0.22), rot=(-0.20, 0.0, 0.0))
    # Two barrels. A stave is WIDE around the barrel and THIN through it: the
    # first version had the section the other way round, so every stave stood
    # out radially and the barrels rendered as birdcages.
    for bx, by, tilt in ((-4.05, fy + 0.58, 0.0), (-3.42, fy + 0.86, 0.05)):
        h, r = 0.84, 0.29
        for s in range(14):
            a = s * math.tau / 14.0
            bkit.box(bm, (bx + math.cos(a) * r, by + math.sin(a) * r, h * 0.5),
                     (0.055, 0.14, h), rot=(0.0, tilt, a))
        for hz in (0.13, h * 0.5, h - 0.13):
            bkit.cylinder(bm, (bx, by, hz), r + 0.032, 0.042, 16)
        bkit.cylinder(bm, (bx, by, h - 0.03), r - 0.015, 0.05, 16)
    # Firewood stacked against the wall — from the GROUND up, not floating at
    # waist height, which is where v1 left it.
    for row in range(5):
        for col in range(8):
            bkit.cylinder(bm, (-2.05 + col * 0.132 + (row % 2) * 0.06,
                               fy + 0.30, 0.075 + row * 0.128),
                          0.060 * rng.uniform(0.82, 1.18), 0.60, 7, axis="Y",
                          rot=(0.0, rng.uniform(-0.06, 0.06), 0.0))
    return part.build(bevel=0.008, segments=1)


# --- Assembly ---------------------------------------------------------------

def build():
    bkit.reset_scene()
    rng = bkit.rng_for("warm_start_inn")
    parts = [
        build_stone(rng),
        build_plaster(),
        build_timber(rng),
        build_roof(rng),
        build_chimney(rng),
    ]
    parts.extend(build_openings(rng))
    parts.extend(build_sign(rng))
    parts.append(build_dressing(rng))
    for obj in parts:
        if not obj.data.uv_layers:
            bkit.uv_project(obj, 0.6)
    return parts


#: The look loop's angles. The first three are the quality gate — a building
#: that fails any of them is not finished — and the rest are the places this
#: particular building is most likely to be wrong.
VIEWS = {
    # Whole building, three-quarter: proportion, silhouette, roof mass.
    "01_hero": {"bearing": 34.0, "elev": 4.0, "dist": 30.0,
                "target": (0.0, 0.4, 4.0)},
    # Standing in the square at Kern's eye height: what a player actually sees.
    "02_eye_level": {"bearing": 8.0, "elev": -4.6, "dist": 26.0,
                     "target": (0.0, 0.4, 3.9)},
    # Conversation range at the door — the test the old town failed hardest.
    "03_door": {"bearing": 12.0, "elev": -1.0, "dist": 6.5,
                "target": (0.0, 2.9, 1.75)},
    "04_jetty_under": {"bearing": 26.0, "elev": -9.0, "dist": 7.5,
                       "target": (-1.4, 3.2, 2.9)},
    "05_gable_chimney": {"bearing": 108.0, "elev": 5.0, "dist": 28.0,
                         "target": (-1.0, 0.2, 4.2)},
    "06_window_close": {"bearing": 24.0, "elev": 0.0, "dist": 4.2,
                        "target": (2.55, 3.0, 1.6), "lens": 62.0},
    "07_sign": {"bearing": -22.0, "elev": 2.0, "dist": 8.5,
                "target": (-2.55, 4.1, 3.1)},
    "08_roof_eaves": {"bearing": 44.0, "elev": 12.0, "dist": 17.0,
                      "target": (0.0, 1.0, 6.0)},
}

#: Preview-only colour scheme. Values, not hues, are what decides whether a
#: facade reads at twenty metres, so these are picked for separation in
#: brightness first: near-white plaster, mid roof, dark timber.
PREVIEW = {
    "inn_glass": (0.05, 0.09, 0.12, 0.12),
    "inn_signiron": (0.10, 0.10, 0.11, 0.42),
    "inn_iron": (0.10, 0.10, 0.11, 0.42),
    "inn_sign": (0.30, 0.19, 0.11, 0.72),
    "inn_roof": (0.42, 0.19, 0.13, 0.82),
    "inn_stone": (0.44, 0.43, 0.39, 0.88),
    "inn_chimney": (0.42, 0.41, 0.37, 0.88),
    "inn_plaster": (0.84, 0.80, 0.70, 0.90),
    "inn_timber": (0.19, 0.13, 0.09, 0.76),
    "inn_joinery": (0.24, 0.16, 0.10, 0.72),
    "inn_dressing": (0.34, 0.24, 0.15, 0.80),
    "scale_figure": (0.55, 0.30, 0.26, 0.85),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    render_dir = ""
    highlight = ""
    for i, a in enumerate(argv):
        if a == "--render" and i + 1 < len(argv):
            render_dir = argv[i + 1]
        # Paint one material group magenta and everything else flat grey. When
        # a stray surface shows up in a render, reasoning about which part it
        # belongs to is slower and less reliable than asking the renderer.
        elif a == "--highlight" and i + 1 < len(argv):
            highlight = argv[i + 1]

    parts = build()
    total = bkit.report(parts)
    root = os.getcwd()
    path = bkit.export_glb(parts, os.path.join(root, OUT_DIR), OUT_NAME)
    print("OK %d parts, %d tris, ridge %.2f m -> %s" % (len(parts), total, RIDGE_Z, path))
    # Blender is Z-up and the exporter converts to Godot's Y-up, mapping
    # (x, y, z) -> (x, z, -y). Printing the converted point means the number in
    # bootstrap_town.gd is never hand-derived, which is where sign errors live.
    print("lantern (Godot local): Vector3(%.2f, %.2f, %.2f)"
          % (LANTERN_AT[0], LANTERN_AT[2], -LANTERN_AT[1]))

    if render_dir:
        bkit.setup_studio()
        figure = bkit.human_scale()
        figure.location = (W * 0.5 + 1.15, D * 0.5 + 1.35, 0.0)
        scheme = dict(PREVIEW)
        if highlight:
            scheme = {k: ((1.0, 0.0, 0.75, 0.5) if k == highlight
                          else (0.42, 0.42, 0.42, 0.85))
                      for k in PREVIEW}
        bkit.preview_materials(scheme)
        bkit.render_views(render_dir, VIEWS)


if __name__ == "__main__":
    main()

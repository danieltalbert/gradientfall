"""The Warm Start Inn — Bootstrap's hero building, authored in Blender. v2.

Run::

    blender -b --python tools/blender/build_warm_start_inn.py
    blender -b --python tools/blender/build_warm_start_inn.py -- --render C:/dir
    blender -b --python tools/blender/build_warm_start_inn.py -- --render C:/dir --highlight inn_roof

Writes ``game/assets/models/town/warm_start_inn.glb``. Every material group is
a separate named object inside it; the game assigns shaders by node name
(``src/town/structure_asset.gd``).

WHY v2 EXISTS — THE ROUNDNESS VERDICT, 2026-08-09
-------------------------------------------------
Danny on v1: *"everything you do is geometrically perfect… there's not a lot of
uniqueness or specialness that comes from uneven shapes or roundness."* He is
right, and the cause was structural: v1 was built entirely from boxes, and a
box has eight vertices — `jitter` can shear it but nothing can ever CURVE it.
v2 is built on the organic primitives added to ``bkit`` for exactly this:

* **Walls belly.** Every plaster slab is a subdivided ``grid_box`` displaced
  by smooth noise, pinned at its corners — cob bulges between its bones.
* **Timbers bow.** Every visible member is an ``organic_beam``: rings along a
  curve, with bow, waney edges and taper. Nothing on the frame is die-straight.
* **Stone is round.** Plinth, chimney and quoins are deformed icospheres.
  Rubble made of rectangles was the loudest geometric lie in v1.
* **The roof undulates.** A smooth noise field waves the tile courses and the
  ridge line together — centuries of rafters settling, not a machined plane.
* **The twins are gone.** The two dormers differ in width, height, position
  and window; the windows stray a few centimetres off their grid; the door
  stands off-centre.
* **Round things live here.** A bread-oven bulge on the back wall, a leaning
  cartwheel, hand-thrown pots, stump stools and a slab table, a rope coil,
  proper thrown chimney pots. The odd-but-fitting furniture of a real yard.

Scale is metres against Kern at 1.75 m (STRUCTURE_PIPELINE.md §3). Front is +Y
in Blender; the glTF exporter converts to Godot's -Z forward.
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

W = 9.0                 # ground-floor width  (X)
D = 6.0                 # ground-floor depth  (Y), front face at +Y
WALL_T = 0.28           # panel thickness — this IS the window reveal
PLINTH_H = 0.52         # stone splash course
GF_TOP = 2.62           # top of ground-floor framing
BRESS_H = 0.32          # bressumer beam depth
UF_BOT = GF_TOP + BRESS_H
UF_TOP = 5.15           # top of the upper wall plate
JETTY = 0.42            # upper storey overhang, front and both sides

W2 = W + JETTY * 2.0
FRONT2 = D * 0.5 + JETTY
BACK = -D * 0.5

EAVES = 0.55
VERGE = 0.45
PITCH = math.radians(38.0)
RIDGE_Y = (FRONT2 + BACK) * 0.5
WALL_HALF = (FRONT2 - BACK) * 0.5      # half-span AT THE WALL — sets the ridge
HALF_SPAN = WALL_HALF + EAVES          # half the tile field
EAVE_Z = UF_TOP - EAVES * math.tan(PITCH)
RIDGE_Z = UF_TOP + WALL_HALF * math.tan(PITCH)
ROOF_HALF_X = W2 * 0.5 + VERGE

POST = 0.22
STUD = 0.13
PROUD = 0.055

DOOR_W, DOOR_H = 1.06, 2.08
DOOR_X = 0.34           # off-centre: a built-over-generations house, not a plan
WIN_W, WIN_H = 1.12, 1.16
WIN_SILL = 0.98
UWIN_W, UWIN_H = 0.94, 1.02
UPPER_SILL = UF_BOT + 0.55

#: Ground-floor front windows, nudged off symmetric (v1 had -2.55 / +2.55).
GF_WIN_X = (-2.68, 2.47)
#: Upper front row: four windows a few cm off their grid, one a shade low.
UP_WINS = ((-3.22, 0.00), (-1.02, -0.04), (1.12, 0.02), (3.09, 0.00))

#: The two dormers, deliberately unalike: the west one broad with a proper
#: gable, the east one narrow, lower, and further down the slope — additions
#: from different decades. `run` is metres up the pitch from the eaves.
DORMERS = (
    {"x": -2.45, "w": 1.52, "wall": 1.00, "rise": 0.55, "depth": 1.85,
     "run": 1.30, "win": (0.84, 0.70)},
    {"x": 2.20, "w": 1.12, "wall": 0.80, "rise": 0.38, "depth": 1.55,
     "run": 0.85, "win": (0.62, 0.56)},
)

#: Door lantern position (Blender space); housing modelled here, flame and
#: light placed by bootstrap_town.gd — see the axis-converted print in main().
LANTERN_AT = (DOOR_X + 0.85, D * 0.5 + 0.30, 2.28)

#: The roof's settle: one smooth noise field waves tiles, ridge and verges
#: together. Amplitude must stay below the 0.085 m tile-to-deck gap.
ROOF_NOISE = bkit.Noise3(772)
ROOF_WAVE = 0.045


def roof_wave(x, run):
    """Vertical settle of the roof surface at (x across, run up the slope)."""
    return ROOF_NOISE.signed(x * 0.30, run * 0.42, 0.0) * ROOF_WAVE


REVEAL = 0.13

OUT_DIR = os.path.join("game", "assets", "models", "town")
OUT_NAME = "warm_start_inn.glb"


def slope_len():
    return HALF_SPAN / math.cos(PITCH)


def dormer_yz(d):
    """A dormer's front-face anchor point on the roof slope."""
    y = RIDGE_Y + HALF_SPAN - d["run"] * math.cos(PITCH)
    z = EAVE_Z + d["run"] * math.sin(PITCH)
    return y, z


# --- Boolean plumbing -------------------------------------------------------

def solid(name, centre, size):
    obj = bkit.new_object(name)
    bm = bmesh.new()
    bkit.box(bm, centre, size)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def cut(obj, openings):
    """Difference ``(centre, size)`` boxes out of ``obj``, loudly on failure."""
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


# --- Stonework --------------------------------------------------------------

def stone_face(bm, axis, plane, outward, u0, u1, v0, v1, rng,
               course=0.24, unit=0.44, depth=0.07, taper=0.0):
    """Tile a wall face with courses of ROUND stones — deformed icospheres.

    Same layout logic as v1 (running bond, jittered sizes) but each unit is
    now `bkit.stone`, so every one is a rounded, irregular blob and no two
    share a silhouette. Two constraints learned from the first v2 render:
    stones must stay TUCKED — centred barely proud of the face, most of their
    volume inside the wall — or the plinth reads as boulders bursting out of
    the building; and each stone's radius across the face stays modest, or a
    long unit becomes a megalith.
    """
    made = []
    v = v0
    row = 0
    while v < v1 - 0.001:
        h = min(course * rng.uniform(0.80, 1.20), v1 - v)
        u = u0 - (unit * 0.5 if row % 2 else 0.0)
        while u < u1 - 0.001:
            length = unit * rng.uniform(0.60, 1.25)
            lo, hi = max(u, u0), min(u + length, u1)
            if hi - lo > 0.10:
                d = depth * rng.uniform(0.7, 1.05)
                pull = taper * (v - v0)
                pos = plane + outward * (d * 0.28 - pull)
                cu, cv = (lo + hi) * 0.5, v + h * 0.5
                ru, rv = min((hi - lo) * 0.52, 0.24), h * 0.54
                if axis == "Y":
                    centre = (cu, pos, cv)
                    radii = (ru, d, rv)
                else:
                    centre = (pos, cu, cv)
                    radii = (d, ru, rv)
                made.extend(bkit.stone(bm, centre, radii, rng))
            u += length + 0.02
        v += h + 0.018
        row += 1
    return made


def build_stone(rng):
    """The plinth: a core the building sits on, faced with round rubble."""
    part = bkit.Part("inn_stone")
    bm = part.bm
    bkit.box(bm, (0.0, 0.0, PLINTH_H * 0.5), (W + 0.05, D + 0.05, PLINTH_H))
    hx, hy = (W + 0.05) * 0.5, (D + 0.05) * 0.5
    # The X faces are inset from the corners so the two passes never both
    # drop a stone on the same corner — intersecting corner stones read as a
    # rockfall rather than coursed masonry.
    for axis, plane, outward, a0, a1 in (
            ("Y", hy, 1.0, -hx, hx), ("Y", -hy, -1.0, -hx, hx),
            ("X", hx, 1.0, -hy + 0.22, hy - 0.22),
            ("X", -hx, -1.0, -hy + 0.22, hy - 0.22)):
        stone_face(bm, axis, plane, outward, a0, a1, 0.0, PLINTH_H, rng)
    # Capping course: flat slab stones, each its own shape, tucked to the
    # wall line instead of oversailing it.
    for sy in (-1.0, 1.0):
        u = -hx + 0.2
        while u < hx - 0.2:
            length = rng.uniform(0.45, 0.7)
            bkit.stone(bm, (u + length * 0.5, sy * (hy - 0.04), PLINTH_H + 0.015),
                       (length * 0.5, 0.17, 0.042), rng)
            u += length
    for sx in (-1.0, 1.0):
        u = -hy + 0.2
        while u < hy - 0.2:
            length = rng.uniform(0.45, 0.7)
            bkit.stone(bm, (sx * (hx - 0.04), u + length * 0.5, PLINTH_H + 0.015),
                       (0.17, length * 0.5, 0.042), rng)
            u += length
    # Threshold: one great worn slab, dished by boots, half-buried.
    step = bkit.stone(bm, (DOOR_X, D * 0.5 + 0.34, 0.02), (0.95, 0.42, 0.16), rng)
    bkit.sag(step, "X", DOOR_X, 0.9, 0.03)
    # The bread oven's skirt: a footing ring of stones under the dome on the
    # back wall, and three flat capping stones over its crown, so the cob
    # bulge reads as BUILT — sitting on masonry, shedding rain — rather than
    # as a ball leaning against the house.
    for i in range(7):
        a = math.pi * (0.12 + 0.76 * i / 6.0)
        ox = -2.55 - math.cos(a) * 0.92
        oy = BACK - 0.18 - math.sin(a) * 0.62
        bkit.stone(bm, (ox, oy, 0.14), (0.20, 0.17, 0.15), rng)
    for dx, dyy, r in ((-0.3, -0.05, 0.20), (0.12, -0.22, 0.23), (0.42, 0.02, 0.18)):
        bkit.stone(bm, (-2.55 + dx, BACK - 0.18 + dyy, 1.28), (r, r * 0.85, 0.05), rng)
    return part.build(bevel=0.0, segments=1, smooth_angle=math.radians(46.0))


def build_chimney(rng):
    """The west stack: battered core faced in round rubble, thrown clay pots."""
    part = bkit.Part("inn_chimney")
    bm = part.bm
    top_z = RIDGE_Z + 1.05
    x = -W * 0.5 - 0.42
    base_w, base_d = 1.55, 2.05
    steps = 7
    for i in range(steps):
        z0 = top_z * i / steps
        z1 = top_z * (i + 1) / steps
        pull = 0.045 * i
        bkit.box(bm, (x, 0.0, (z0 + z1) * 0.5),
                 (base_w - pull * 2.0, base_d - pull * 2.0, z1 - z0 + 0.01))
    hx, hy = base_w * 0.5, base_d * 0.5
    # Facing stops 0.9 m below the top so nothing pokes through the two
    # oversailing cap courses — the first v2 render had rubble spilling out
    # around the cap like a collapsed parapet.
    for axis, plane, outward, a0, a1 in (
            ("X", x - hx, -1.0, -hy + 0.2, hy - 0.2),
            ("Y", hy, 1.0, x - hx + 0.1, x + hx - 0.1),
            ("Y", -hy, -1.0, x - hx + 0.1, x + hx - 0.1)):
        stone_face(bm, axis, plane, outward, a0, a1, 0.0, top_z - 0.90, rng,
                   course=0.26, unit=0.46, depth=0.075, taper=0.034)
    bkit.box(bm, (x, 0.0, top_z - 0.42), (base_w + 0.16, base_d + 0.16, 0.14))
    bkit.box(bm, (x, 0.0, top_z - 0.26), (base_w + 0.28, base_d + 0.28, 0.16))
    # Thrown clay pots — lathe profiles with a waist and a rolled lip, one of
    # them tilted a few degrees. v1's were straight cylinders.
    for offset, lean in ((-0.52, 0.0), (0.52, 0.045)):
        pot = bkit.lathe(bm, (x + lean * 3.0, offset, top_z + 0.02),
                         [(0.20, 0.0), (0.155, 0.22), (0.145, 0.42),
                          (0.185, 0.58), (0.205, 0.64), (0.150, 0.66)],
                         segments=12, wobble=0.03, rng=rng)
        if lean:
            for v in pot:
                v.co.x += (v.co.z - top_z) * lean
    obj = part.build(bevel=0.0, segments=1, smooth_angle=math.radians(46.0))
    obj.rotation_euler = (math.radians(1.2), 0.0, 0.0)
    return obj


# --- Plaster ----------------------------------------------------------------

def _slab_object(name, centre, size, noise, belly_axis, openings,
                 cuts=7, amount=0.035):
    """One wall slab that BELLIES, cut as its OWN object before joining.

    ``belly_axis`` is the wall's normal (0=X, 1=Y); pinning the two in-plane
    axes keeps the slab's edges where the neighbouring walls expect them
    while the middle bows in and out like real cob.

    Each slab runs its booleans alone — one manifold grid box against one
    cutter at a time — and the slabs are only merged afterwards. Cutting the
    merged shell was the bug that ate v2's walls: with eight overlapping
    slabs in one object, the exact solver answered a single door cut by
    silently deleting entire walls, and the building rendered hollow.
    """
    obj = bkit.new_object(name)
    bm = bmesh.new()
    verts = bkit.grid_box(bm, centre, size, cuts=cuts)
    pin = tuple(i for i in range(3) if i != belly_axis)
    bkit.warp(verts, amount, 0.55, noise, axis=belly_axis, pin_axes=pin)
    bm.to_mesh(obj.data)
    bm.free()
    if openings:
        cut(obj, openings)
    return obj


def build_plaster(rng):
    """Both storeys' infill, bellied, plus the bread oven on the back wall.

    Assembled from per-slab objects (see `_slab_object` for why), merged into
    one `inn_plaster` at the end so the game still sees a single material
    group.
    """
    noise = bkit.Noise3(rng.randrange(1 << 16))
    fy = D * 0.5
    gf_h = GF_TOP - PLINTH_H
    gz = PLINTH_H + gf_h * 0.5
    hx, hy = W * 0.5, D * 0.5
    uf_h = UF_TOP - UF_BOT
    uz = UF_BOT + uf_h * 0.5
    hx2 = W2 * 0.5
    ymid = (FRONT2 + BACK) * 0.5
    uzs = UPPER_SILL + UWIN_H * 0.5

    slabs = []
    slabs.append(_slab_object(
        "slab_gf_front", (0.0, hy - WALL_T * 0.5, gz), (W, WALL_T, gf_h), noise, 1,
        [((DOOR_X, fy, PLINTH_H + DOOR_H * 0.5 - 0.1),
          (DOOR_W, WALL_T * 4.0, DOOR_H))]
        + [((x, fy, WIN_SILL + WIN_H * 0.5), (WIN_W, WALL_T * 4.0, WIN_H))
           for x in GF_WIN_X]))
    slabs.append(_slab_object(
        "slab_gf_back", (0.0, -hy + WALL_T * 0.5, gz), (W, WALL_T, gf_h), noise, 1,
        []))
    for sx in (-1.0, 1.0):
        slabs.append(_slab_object(
            "slab_gf_side%d" % sx, (sx * (hx - WALL_T * 0.5), 0.0, gz),
            (WALL_T, D - WALL_T * 2, gf_h), noise, 0,
            [((sx * W * 0.5, 0.55, WIN_SILL + WIN_H * 0.5),
              (WALL_T * 4.0, WIN_W, WIN_H))]))
    slabs.append(_slab_object(
        "slab_uf_front", (0.0, FRONT2 - WALL_T * 0.5, uz), (W2, WALL_T, uf_h),
        noise, 1,
        [((x, FRONT2, UPPER_SILL + UWIN_H * 0.5 + dz),
          (UWIN_W, WALL_T * 4.0, UWIN_H)) for x, dz in UP_WINS]))
    slabs.append(_slab_object(
        "slab_uf_back", (0.0, BACK + WALL_T * 0.5, uz), (W2, WALL_T, uf_h),
        noise, 1,
        [((x, BACK, uzs), (UWIN_W, WALL_T * 4.0, UWIN_H)) for x in (-2.2, 2.2)]))
    for sx in (-1.0, 1.0):
        slabs.append(_slab_object(
            "slab_uf_side%d" % sx, (sx * (hx2 - WALL_T * 0.5), ymid, uz),
            (WALL_T, FRONT2 - BACK - WALL_T * 2, uf_h), noise, 0,
            [((sx * W2 * 0.5, 0.2, uzs), (WALL_T * 4.0, UWIN_W, UWIN_H))]))

    # Everything that needs no cutting joins the master part directly.
    part = bkit.Part("inn_plaster")
    bm = part.bm
    # Gables: real wedges, dropped 0.11 clear of the roof plane (v1 lesson).
    for sx in (-1.0, 1.0):
        gx = sx * (W2 * 0.5 - WALL_T * 0.5)
        bkit.wedge(bm, (gx, RIDGE_Y, UF_TOP - 0.11),
                   WALL_HALF * 2.0, RIDGE_Z - UF_TOP + 0.02, WALL_T)
    for d in DORMERS:
        dy, dz = dormer_yz(d)
        bkit.stamp_group(bm, bkit.place((d["x"], dy, dz)),
                         lambda b, dd=d: _dormer_shell(b, dd))

    # THE BREAD OVEN — the round, odd-but-fitting thing this building was
    # missing. A cob half-dome swelling off the back wall by the chimney end,
    # where the inn's hearth would be. Squat — wider than tall — because a
    # taller-than-wide dome reads as an egg leaning on the house, which is
    # exactly what the first attempt looked like. The timber sill beam is
    # split around it in build_timber; cob was always packed OVER the frame.
    oven = bkit.stone(bm, (-2.55, BACK - 0.18, 0.58), (1.05, 0.72, 0.74), rng)
    bkit.warp(oven, 0.04, 1.6, noise)

    # The dormer window openings CAN cut the merged part: dormer shells are
    # isolated boxes that overlap nothing else, so the solver has no
    # self-intersecting input to trip on.
    obj = part.build(bevel=0.0, segments=1, smooth_angle=math.radians(46.0))
    dormer_openings = []
    for d in DORMERS:
        dy, dz = dormer_yz(d)
        dormer_openings.append(((d["x"], dy - 0.06, dz + d["wall"] * 0.52),
                                (d["win"][0], 0.9, d["win"][1])))
    cut(obj, dormer_openings)

    # Merge the pre-cut slabs into the master object.
    merged = bmesh.new()
    merged.from_mesh(obj.data)
    for slab in slabs:
        merged.from_mesh(slab.data)
        bpy.data.objects.remove(slab, do_unlink=True)
    merged.to_mesh(obj.data)
    merged.free()
    bkit.shade_auto_smooth(obj, math.radians(46.0))
    bkit.uv_project(obj, 0.5)
    return obj


# --- Dormers (asymmetric pair) ----------------------------------------------

def _dormer_shell(bm, d):
    hw = d["w"] * 0.5
    bkit.box(bm, (0.0, -0.06, d["wall"] * 0.5), (d["w"] - 0.14, 0.12, d["wall"]))
    for sx in (-1.0, 1.0):
        bkit.box(bm, (sx * (hw - 0.06), -d["depth"] * 0.5, d["wall"] * 0.5),
                 (0.11, d["depth"], d["wall"]))


def _dormer_timber(bm, d, rng):
    hw = d["w"] * 0.5
    for sx in (-1.0, 1.0):
        bkit.organic_beam(bm, (sx * (hw - 0.03), 0.02, 0.0),
                          (sx * (hw - 0.03), 0.02, d["wall"]), 0.10, 0.09,
                          rng, segments=3, bow=0.006)
        bkit.organic_beam(bm, (sx * (hw + 0.16), 0.05, d["wall"] - 0.10),
                          (0.0, 0.05, d["wall"] + d["rise"] + 0.04), 0.16, 0.07,
                          rng, segments=3, bow=0.008)
    bkit.organic_beam(bm, (-hw, 0.02, d["wall"] - 0.055),
                      (hw, 0.02, d["wall"] - 0.055), 0.13, 0.11,
                      rng, segments=3, bow=0.007)


def _dormer_tiles(bm, d, rng):
    hw = d["w"] * 0.5
    pitch = math.atan2(d["rise"], hw)
    bkit.stamp_group(bm, bkit.place((0.0, -0.02, d["wall"] - 0.05),
                                    yaw=math.radians(90.0)),
                     lambda b: bkit.wedge(b, (0.0, 0.0, 0.0), d["w"] - 0.14,
                                          (d["w"] - 0.14) * 0.5 * math.tan(pitch),
                                          0.12))
    slope = math.hypot(hw + 0.14, d["rise"])
    gauge, tile_w = 0.115, 0.20
    for sx in (-1.0, 1.0):
        for c in range(int(slope / gauge) + 1):
            run = min(c * gauge, slope)
            x = sx * (hw + 0.14 - run * math.cos(pitch))
            z = d["wall"] - 0.09 + run * math.sin(pitch)
            for i in range(int(d["depth"] / tile_w) + 2):
                y = 0.16 - i * tile_w
                if y < -d["depth"] - 0.1:
                    continue
                verts = bkit.box(bm, (x, y, z + 0.02),
                                 (0.19, tile_w * 0.93, 0.024),
                                 rot=(0.0, sx * pitch + rng.uniform(-0.03, 0.03),
                                      0.0))
                bkit.jitter(verts, 0.005, rng)
    for i in range(int(d["depth"] / 0.38) + 1):
        bkit.half_round(bm, (0.0, 0.18 - i * 0.38, d["wall"] + d["rise"] + 0.01),
                        (0.0, 0.18 - (i + 1) * 0.38, d["wall"] + d["rise"] + 0.01),
                        0.085, 5)


# --- The frame --------------------------------------------------------------

def build_timber(rng):
    """The frame, every member an organic_beam: bowed, waney, tapered."""
    part = bkit.Part("inn_timber")
    bm = part.bm
    fy = D * 0.5
    face = fy + PROUD
    face2 = FRONT2 + PROUD

    def member(p0, p1, w, h, bow=0.014, segs=5):
        return bkit.organic_beam(bm, p0, p1, w, h, rng, segments=segs,
                                 bow=bow, waney=0.005, taper=rng.uniform(0.9, 1.0))

    def peg(centre, axis="Y"):
        bkit.cylinder(bm, centre, 0.028, PROUD + 0.03, 6, axis=axis)

    # Ground floor, front.
    member((-W * 0.5, face, PLINTH_H + 0.09), (W * 0.5, face, PLINTH_H + 0.09),
           0.20, 0.18)
    bress = member((-W2 * 0.5, face2 - 0.02, GF_TOP + BRESS_H * 0.5),
                   (W2 * 0.5, face2 - 0.02, GF_TOP + BRESS_H * 0.5),
                   0.30, BRESS_H, bow=0.010, segs=7)
    bkit.sag(bress, "X", 0.0, W2 * 0.5, 0.035)
    for x in (-W * 0.5 + POST * 0.5, W * 0.5 - POST * 0.5,
              DOOR_X - DOOR_W * 0.5 - 0.13, DOOR_X + DOOR_W * 0.5 + 0.13):
        member((x, face, PLINTH_H), (x + rng.uniform(-0.02, 0.02), face, GF_TOP),
               POST, POST, bow=0.010)
        peg((x, face, PLINTH_H + 0.28))
        peg((x, face, GF_TOP - 0.24))
    for x in (-3.75, -3.15, -1.95, -1.35, 1.62, 2.02, 3.15, 3.75):
        member((x, face, PLINTH_H + 0.14),
               (x + rng.uniform(-0.025, 0.025), face, GF_TOP), STUD, STUD * 0.8)
    for x in GF_WIN_X:
        for z in (WIN_SILL - 0.09, WIN_SILL + WIN_H + 0.09):
            member((x - WIN_W * 0.5 - 0.22, face, z),
                   (x + WIN_W * 0.5 + 0.22, face, z), 0.16, 0.13)
    member((DOOR_X - DOOR_W * 0.5 - 0.26, face, PLINTH_H + DOOR_H - 0.06),
           (DOOR_X + DOOR_W * 0.5 + 0.26, face, PLINTH_H + DOOR_H - 0.06),
           0.20, 0.17)

    # Curved corner braces, both faces of both front corners.
    for sx in (-1.0, 1.0):
        px = sx * (W * 0.5 - POST * 0.5)
        bkit.sweep(bm, bkit.arc((px, face, GF_TOP - 1.15),
                                (px - sx * 1.15, face, GF_TOP - 0.03),
                                0.20, 10, axis=(0.0, 1.0, 0.0)),
                   0.155, 0.13, up=(0.0, 1.0, 0.0))
        sxf = sx * (W * 0.5 + PROUD)
        bkit.sweep(bm, bkit.arc((sxf, fy - 0.12, GF_TOP - 1.15),
                                (sxf, fy - 1.25, GF_TOP - 0.03),
                                0.20, 10, axis=(1.0, 0.0, 0.0)),
                   0.155, 0.13, up=(1.0, 0.0, 0.0))

    # Jetty: swept ogee corbels and exposed joist ends.
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
    for x in [-4.2 + i * 0.62 for i in range(14)]:
        verts = bkit.box(bm, (x, face2 - 0.16, GF_TOP - 0.02), (0.11, 0.30, 0.13))
        bkit.jitter(verts, 0.006, rng)
    for sx in (-1.0, 1.0):
        member((sx * (W2 * 0.5 - 0.02), BACK, GF_TOP + BRESS_H * 0.5),
               (sx * (W2 * 0.5 - 0.02), FRONT2, GF_TOP + BRESS_H * 0.5),
               0.30, BRESS_H, segs=6)

    # Upper floor, front: posts, close studding, sill rail, wall plate.
    for x in (-W2 * 0.5 + POST * 0.5, W2 * 0.5 - POST * 0.5):
        member((x, face2, UF_BOT), (x + rng.uniform(-0.02, 0.02), face2, UF_TOP),
               POST, POST, bow=0.012)
    for i in range(15):
        x = -W2 * 0.5 + 0.62 + i * 0.62
        member((x, face2, UF_BOT),
               (x + rng.uniform(-0.03, 0.03), face2, UF_TOP), STUD, STUD * 0.8)
    mid = member((-W2 * 0.5, face2, UPPER_SILL - 0.11),
                 (W2 * 0.5, face2, UPPER_SILL - 0.11), 0.20, 0.16, segs=7)
    bkit.sag(mid, "X", 0.0, W2 * 0.5, 0.02)
    plate = member((-W2 * 0.5, face2, UF_TOP - 0.11),
                   (W2 * 0.5, face2, UF_TOP - 0.11), 0.24, 0.22, segs=7)
    bkit.sag(plate, "X", 0.0, W2 * 0.5, 0.03)

    # Side and back elevations.
    for sx in (-1.0, 1.0):
        px = sx * (W * 0.5 + PROUD)
        member((px, BACK, PLINTH_H + 0.09), (px, D * 0.5, PLINTH_H + 0.09),
               0.20, 0.18)
        for y in (BACK + POST * 0.5, D * 0.5 - POST * 0.5):
            member((px, y, PLINTH_H), (px, y + rng.uniform(-0.02, 0.02), GF_TOP),
                   POST, POST)
        for i in range(6):
            y = BACK + 0.86 + i * 0.86
            member((px, y, PLINTH_H + 0.14),
                   (px, y + rng.uniform(-0.03, 0.03), GF_TOP), STUD, STUD * 0.8)
        for z in (WIN_SILL - 0.09, WIN_SILL + WIN_H + 0.09):
            member((px, 0.55 - WIN_W * 0.5 - 0.24, z),
                   (px, 0.55 + WIN_W * 0.5 + 0.24, z), 0.16, 0.13)
    by = BACK - PROUD
    # The back sill runs in two lengths around the bread oven — the dome
    # occupies x -3.6..-1.5 at exactly this height, and a beam lancing
    # through a cob oven is the kind of impossible joint the eye catches.
    member((-W * 0.5, by, PLINTH_H + 0.09), (-3.62, by, PLINTH_H + 0.09),
           0.20, 0.18)
    member((-1.48, by, PLINTH_H + 0.09), (W * 0.5, by, PLINTH_H + 0.09),
           0.20, 0.18)
    member((-W * 0.5, by, GF_TOP - 0.11), (W * 0.5, by, GF_TOP - 0.11), 0.22, 0.20)
    for i in range(10):
        x = -W * 0.5 + 0.82 + i * 0.82
        # The oven swells over this stretch of wall; studs would spear it.
        if -3.4 < x < -1.7:
            continue
        member((x, by, PLINTH_H + 0.14),
               (x + rng.uniform(-0.03, 0.03), by, GF_TOP), STUD, STUD * 0.8)
    for sx in (-1.0, 1.0):
        bx = sx * (W2 * 0.5 + PROUD)
        member((bx, BACK - PROUD, UF_BOT), (bx, BACK - PROUD, UF_TOP), POST, POST)
    member((-W2 * 0.5, BACK - PROUD, UF_BOT + 1.02),
           (W2 * 0.5, BACK - PROUD, UF_BOT + 1.02), 0.20, 0.16, segs=7)
    for i in range(13):
        x = -W2 * 0.5 + 0.72 + i * 0.72
        member((x, BACK - PROUD, UF_BOT),
               (x + rng.uniform(-0.03, 0.03), BACK - PROUD, UF_TOP),
               STUD, STUD * 0.8)

    # Gable framing: tie, collar, king post, raking studs.
    for sx in (-1.0, 1.0):
        gx = sx * (W2 * 0.5 + PROUD)
        member((gx, RIDGE_Y - WALL_HALF, UF_TOP + 0.06),
               (gx, RIDGE_Y + WALL_HALF, UF_TOP + 0.06), 0.26, 0.22, segs=6)
        collar_z = UF_TOP + (RIDGE_Z - UF_TOP) * 0.52
        collar_half = WALL_HALF * 0.48
        member((gx, RIDGE_Y - collar_half, collar_z),
               (gx, RIDGE_Y + collar_half, collar_z), 0.20, 0.17)
        member((gx, RIDGE_Y, UF_TOP + 0.06), (gx, RIDGE_Y, RIDGE_Z - 0.10),
               0.19, 0.19)
        for frac in (0.32, 0.66):
            hs = WALL_HALF * (1.0 - frac)
            for sy in (-1.0, 1.0):
                member((gx, RIDGE_Y + sy * hs, UF_TOP + 0.06),
                       (gx, RIDGE_Y + sy * hs * 0.34,
                        UF_TOP + (RIDGE_Z - UF_TOP) * (1.0 - 0.34) * frac + 0.06),
                       STUD, STUD * 0.8, segs=3)

    for d in DORMERS:
        dy, dz = dormer_yz(d)
        bkit.stamp_group(bm, bkit.place((d["x"], dy, dz)),
                         lambda b, dd=d: _dormer_timber(b, dd, rng))

    # Rafter tails and barge boards, following the settled roof.
    drop = EAVES * math.tan(PITCH)
    for i in range(19):
        x = -W2 * 0.5 + 0.02 + i * (W2 - 0.04) / 18.0
        wob = roof_wave(x, 0.0)
        for sy, wall_y in ((1.0, FRONT2), (-1.0, BACK)):
            bkit.beam(bm, (x, wall_y, UF_TOP + 0.04 + wob),
                      (x, wall_y + sy * EAVES, UF_TOP + 0.04 - drop + wob),
                      0.09, 0.13)
    for sx in (-1.0, 1.0):
        bx = sx * (ROOF_HALF_X - 0.09)
        for sy in (-1.0, 1.0):
            bkit.organic_beam(bm, (bx, RIDGE_Y + sy * HALF_SPAN, EAVE_Z + 0.05),
                              (bx, RIDGE_Y, RIDGE_Z + 0.05), 0.26, 0.10,
                              rng, segments=6, bow=0.015)
    obj = part.build(bevel=0.010, segments=1)
    bkit.uv_project(obj, 0.6)
    return obj


# --- Roof -------------------------------------------------------------------

def build_roof(rng):
    """Tiles course by course, the whole field settled by one noise wave.

    v1's roof sagged with a single global curve, which is still a machined
    shape. Real settle is local: each stretch of rafters gives differently, so
    the courses ripple. `roof_wave` displaces every tile, the ridge rolls and
    the verges from the same field, so they undulate together.
    """
    part = bkit.Part("inn_roof")
    bm = part.bm
    tile_w, gauge = 0.225, 0.128
    courses = int(math.ceil(slope_len() / gauge))
    across = int(math.ceil((ROOF_HALF_X * 2.0) / tile_w)) + 1
    for sy in (-1.0, 1.0):
        mid = slope_len() * 0.5
        bkit.box(bm,
                 (0.0, RIDGE_Y + sy * (HALF_SPAN - mid * math.cos(PITCH)),
                  EAVE_Z + mid * math.sin(PITCH) - 0.085),
                 (ROOF_HALF_X * 2.0, slope_len() + 0.10, 0.07),
                 rot=(-sy * PITCH, 0.0, 0.0))
    for sy in (-1.0, 1.0):
        for c in range(courses):
            run = min(c * gauge, slope_len())
            y = RIDGE_Y + sy * (HALF_SPAN - run * math.cos(PITCH))
            z = EAVE_Z + run * math.sin(PITCH)
            layers = (0.0, 0.052) if c == 0 else (0.0,)
            for lift in layers:
                for i in range(across):
                    x = -ROOF_HALF_X + tile_w * (i + 0.5) + (tile_w * 0.5 if c % 2 else 0.0)
                    if x > ROOF_HALF_X - 0.02:
                        continue
                    wave = roof_wave(x, run)
                    verts = bkit.box(
                        bm, (x, y - sy * 0.055, z + 0.028 + lift + wave),
                        (tile_w * 0.93, 0.20, 0.026),
                        rot=(-sy * PITCH + rng.uniform(-0.03, 0.03),
                             0.0, rng.uniform(-0.02, 0.02)))
                    bkit.jitter(verts, 0.006, rng)
    for d in DORMERS:
        dy, dz = dormer_yz(d)
        bkit.stamp_group(bm, bkit.place((d["x"], dy, dz)),
                         lambda b, dd=d: _dormer_tiles(b, dd, rng))
    # Ridge rolls riding the same wave as the tiles beneath them.
    n_ridge = int((ROOF_HALF_X * 2.0) / 0.40)
    for i in range(n_ridge):
        x0 = -ROOF_HALF_X + i * 0.40
        w0 = roof_wave(x0 + 0.2, slope_len())
        verts = bkit.half_round(bm, (x0, RIDGE_Y, RIDGE_Z + 0.02 + w0),
                                (x0 + 0.415, RIDGE_Y, RIDGE_Z + 0.02 + w0),
                                0.115, 6)
        bkit.jitter(verts, 0.008, rng)
    obj = part.build(bevel=0.0, smooth=False)
    bkit.uv_project(obj, 1.2)
    return obj


# --- Joinery, glass, iron ---------------------------------------------------

def _cames(bm, sw, sh, rng):
    hw, hh = sw * 0.5, sh * 0.5
    step = 0.175
    reach = (sw + sh) * 0.75
    n = int(reach / step) + 2
    for sign in (-1.0, 1.0):
        for k in range(-n, n + 1):
            c = k * step * math.sqrt(2.0)
            seg = bkit.clip_segment((-reach, sign * -reach + c),
                                    (reach, sign * reach + c), -hw, hw, -hh, hh)
            if seg is None:
                continue
            (u0, v0), (u1, v1) = seg
            if math.hypot(u1 - u0, v1 - v0) < 0.05:
                continue
            verts = bkit.beam(bm, (u0, 0.0, v0), (u1, 0.0, v1), 0.016, 0.014)
            bkit.jitter(verts, 0.0015, rng)


def _shutter_leaf(bm, leaf_w, leaf_h, rng):
    n = 3
    for i in range(n):
        px = (i + 0.5) * leaf_w / n
        verts = bkit.box(bm, (px, 0.0, 0.0), (leaf_w / n - 0.014, 0.038, leaf_h))
        bkit.jitter(verts, 0.004, rng)
    for dz in (-1.0, 1.0):
        bkit.box(bm, (leaf_w * 0.5, -0.032, dz * leaf_h * 0.33),
                 (leaf_w - 0.02, 0.028, 0.105))
    bkit.organic_beam(bm, (0.03, -0.032, -leaf_h * 0.30),
                      (leaf_w - 0.05, -0.032, leaf_h * 0.30), 0.026, 0.085,
                      rng, segments=3, bow=0.004)


def _shutter_iron(bm, leaf_w, leaf_h):
    for dz in (-1.0, 1.0):
        bkit.box(bm, (leaf_w * 0.42, 0.026, dz * leaf_h * 0.33),
                 (leaf_w * 0.78, 0.014, 0.052))
        bkit.box(bm, (0.05, 0.026, dz * leaf_h * 0.33), (0.14, 0.016, 0.10))
    bkit.cylinder(bm, (leaf_w - 0.10, 0.05, 0.0), 0.045, 0.018, 10, axis="Y")


def build_openings(rng):
    """Windows, shutters, the door — authored once in local space, stamped."""
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
        bkit.box(bm, (0.0, -REVEAL, 0.0), (0.062, 0.10, sh))
        sill = bkit.box(bm, (0.0, 0.04, -sh * 0.5 - 0.05), (sw + 0.30, 0.36, 0.075),
                        rot=(-0.14, 0.0, 0.0))
        bkit.jitter(sill, 0.006, rng)
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

    gz = WIN_SILL + WIN_H * 0.5
    window((GF_WIN_X[0], fy, gz), 0.0, (WIN_W, WIN_H), ajar=0.0)
    window((GF_WIN_X[1], fy, gz), 0.0, (WIN_W, WIN_H), ajar=0.62)
    window((W * 0.5, 0.55, gz), math.radians(-90.0), (WIN_W, WIN_H), ajar=0.34)
    window((-W * 0.5, 0.55, gz), math.radians(90.0), (WIN_W, WIN_H), ajar=0.0)
    for x, dz in UP_WINS:
        window((x, FRONT2, UPPER_SILL + UWIN_H * 0.5 + dz), 0.0,
               (UWIN_W, UWIN_H), shutters=False)
    uzs = UPPER_SILL + UWIN_H * 0.5
    window((W2 * 0.5, 0.2, uzs), math.radians(-90.0), (UWIN_W, UWIN_H), shutters=False)
    window((-W2 * 0.5, 0.2, uzs), math.radians(90.0), (UWIN_W, UWIN_H), shutters=False)
    for x in (-2.2, 2.2):
        window((x, BACK, uzs), math.pi, (UWIN_W, UWIN_H), shutters=False)
    for d in DORMERS:
        dy, dz = dormer_yz(d)
        window((d["x"], dy, dz + d["wall"] * 0.52), 0.0, d["win"], shutters=False)

    # The door, off-centre, planks warped just enough to read as hand-sawn.
    dz0 = PLINTH_H - 0.10
    dcz = dz0 + DOOR_H * 0.5
    dy = fy - 0.10
    for i in range(5):
        px = DOOR_X + (i - 2) * (DOOR_W / 5.0)
        verts = bkit.box(bj, (px, dy, dcz), (DOOR_W / 5.0 - 0.014, 0.055, DOOR_H))
        bkit.jitter(verts, 0.004, rng)
    for dzf in (-0.36, 0.0, 0.36):
        bkit.box(bj, (DOOR_X, dy - 0.04, dcz + dzf * DOOR_H), (DOOR_W, 0.03, 0.12))
    for dzf in (-0.33, 0.33):
        bkit.box(bi, (DOOR_X - 0.06, dy + 0.032, dcz + dzf * DOOR_H),
                 (DOOR_W * 0.82, 0.016, 0.075))
        bkit.box(bi, (DOOR_X - DOOR_W * 0.5 + 0.10, dy + 0.032, dcz + dzf * DOOR_H),
                 (0.20, 0.018, 0.14))
    bkit.cylinder(bi, (DOOR_X + DOOR_W * 0.28, dy + 0.055, dcz + 0.02),
                  0.075, 0.022, 12, axis="Y")
    bkit.cylinder(bi, (DOOR_X + DOOR_W * 0.28, dy + 0.055, dcz + 0.02),
                  0.052, 0.030, 12, axis="Y")
    bkit.box(bi, (DOOR_X + DOOR_W * 0.28, dy + 0.04, dcz + 0.16), (0.10, 0.02, 0.13))
    for r in range(3):
        for c in range(4):
            bkit.cylinder(bi, (DOOR_X - 0.40 + c * 0.27, dy + 0.045,
                               dcz - 0.55 + r * 0.55), 0.022, 0.020, 6, axis="Y")

    # Door hood on curved brackets, following the door off-centre.
    hood_z = dz0 + DOOR_H + 0.28
    for sx in (-1.0, 1.0):
        bkit.sweep(bj, bkit.arc((DOOR_X + sx * 0.78, fy + 0.04, hood_z - 0.62),
                                (DOOR_X + sx * 0.62, fy + 0.86, hood_z - 0.04),
                                0.16, 8, axis=(1.0, 0.0, 0.0)),
                   0.11, 0.15, up=(1.0, 0.0, 0.0))
    for i in range(9):
        yy = fy + 0.06 + i * 0.105
        verts = bkit.box(bj, (DOOR_X, yy, hood_z + 0.20 - i * 0.036),
                         (2.05, 0.115, 0.045), rot=(-0.33, 0.0, 0.0))
        bkit.jitter(verts, 0.005, rng)
    bkit.box(bj, (DOOR_X, fy + 0.03, hood_z + 0.26), (2.15, 0.10, 0.13))

    # Door lantern housing (light itself is runtime — bootstrap_town.gd).
    lz = LANTERN_AT[2]
    bkit.box(bi, (LANTERN_AT[0] - 0.20, fy + 0.16, lz + 0.30), (0.42, 0.055, 0.055))
    bkit.box(bi, (LANTERN_AT[0], LANTERN_AT[1], lz), (0.24, 0.24, 0.30))
    bkit.cylinder(bi, (LANTERN_AT[0], LANTERN_AT[1], lz + 0.20), 0.21, 0.13, 4,
                  rot=(0.0, 0.0, math.radians(45.0)))
    for sx in (-1.0, 1.0):
        for sy2 in (-1.0, 1.0):
            bkit.box(bi, (LANTERN_AT[0] + sx * 0.105, LANTERN_AT[1] + sy2 * 0.105, lz),
                     (0.028, 0.028, 0.30))

    return (joinery.build(bevel=0.008, segments=1),
            glass.build(bevel=0.0, smooth=False),
            iron.build(bevel=0.005, segments=1))


def build_sign(rng):
    """The signboard, across the bracket, facing the square. Unchanged from
    the v1 fix except the board planks warp slightly."""
    part = bkit.Part("inn_sign")
    iron = bkit.Part("inn_signiron")
    bm, bi = part.bm, iron.bm
    x = -2.55
    wall = FRONT2 + PROUD
    arm_z = 3.62
    reach = 1.40
    tip = wall + reach
    bkit.box(bi, (x, wall + reach * 0.5, arm_z), (0.055, reach, 0.05))
    bkit.box(bi, (x, wall - 0.02, arm_z - 0.10), (0.16, 0.10, 0.34))
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
    by, bz = tip - 0.12, arm_z - 0.72
    bkit.box(bi, (x, by, arm_z - 0.02), (1.06, 0.042, 0.042))
    for dx in (-0.44, 0.44):
        bkit.box(bi, (x + dx, by, arm_z - 0.19), (0.020, 0.020, 0.30))
    board = bkit.box(bm, (x, by, bz), (1.30, 0.075, 0.80), rot=(0.0, 0.03, 0.0))
    for sy in (-1.0, 1.0):
        bkit.box(bm, (x, by + sy * 0.048, bz), (1.14, 0.022, 0.64),
                 rot=(0.0, 0.03, 0.0))
    bkit.jitter(board, 0.005, rng)
    print("sign board (Godot local): Vector3(%.2f, %.2f, %.2f)" % (x, bz, -by))
    return part.build(bevel=0.010, segments=2), iron.build(bevel=0.004, segments=1)


# --- Dressing: the round furniture of a real yard ---------------------------

def build_dressing(rng):
    """Bench, barrels, firewood — and the round things: cartwheel, pots,
    stump stools, a slab table, a rope coil."""
    part = bkit.Part("inn_dressing")
    pottery = bkit.Part("inn_pottery")
    bm, bp = part.bm, pottery.bm
    fy = D * 0.5

    # Bench under the east window, seat worn hollow.
    seat = bkit.box(bm, (2.47, fy + 0.62, 0.50), (1.85, 0.42, 0.075))
    bkit.sag(seat, "X", 2.47, 0.92, 0.028)
    for dx in (-0.72, 0.72):
        for dyy in (-0.13, 0.13):
            bkit.box(bm, (2.47 + dx, fy + 0.62 + dyy, 0.24), (0.085, 0.075, 0.48),
                     rot=(0.0, math.radians(4.0) * (1 if dx > 0 else -1), 0.0))
    bkit.box(bm, (2.47, fy + 0.80, 0.78), (1.75, 0.06, 0.22), rot=(-0.20, 0.0, 0.0))

    # Barrels: staves wide-around/thin-through, hoops, one slightly tilted.
    for bx, byy, tilt in ((-4.05, fy + 0.58, 0.0), (-3.42, fy + 0.86, 0.05)):
        h, r = 0.84, 0.29
        for s in range(14):
            a = s * math.tau / 14.0
            bkit.box(bm, (bx + math.cos(a) * r, byy + math.sin(a) * r, h * 0.5),
                     (0.055, 0.14, h), rot=(0.0, tilt, a))
        for hz in (0.13, h * 0.5, h - 0.13):
            bkit.cylinder(bm, (bx, byy, hz), r + 0.032, 0.042, 16)
        bkit.cylinder(bm, (bx, byy, h - 0.03), r - 0.015, 0.05, 16)

    # Firewood, from the ground up — 9-sided logs pushed unevenly in and out
    # of the stack, because a woodpile's charm is that nobody stacked it well.
    for row in range(5):
        for col in range(8):
            bkit.cylinder(bm, (-2.05 + col * 0.132 + (row % 2) * 0.06,
                               fy + 0.30 + rng.uniform(-0.05, 0.05),
                               0.075 + row * 0.128),
                          0.060 * rng.uniform(0.80, 1.18), 0.60, 9, axis="Y",
                          rot=(0.0, rng.uniform(-0.06, 0.06), 0.0))

    # THE CARTWHEEL, leaning by the door: rim revolved as a closed section,
    # ten spokes, a proper hub. The single most recognisable round object a
    # village yard can own.
    def wheel(b):
        R = 0.62
        bkit.lathe(b, (0.0, 0.0, 0.0),
                   [(R - 0.045, -0.04), (R + 0.045, -0.04),
                    (R + 0.045, 0.04), (R - 0.045, 0.04)],
                   segments=18, closed=True)
        bkit.cylinder(b, (0.0, 0.0, 0.0), 0.09, 0.16, 10)
        for s in range(10):
            a = s * math.tau / 10.0
            bkit.cylinder(b, (math.cos(a) * R * 0.5, math.sin(a) * R * 0.5, 0.0),
                          0.026, R - 0.12, 7,
                          rot=(0.0, math.radians(90.0), a))
    bkit.stamp_group(bm, bkit.place((-1.55, fy + 0.30, 0.60),
                                    pitch=math.radians(78.0), yaw=0.25), wheel)

    # Stump stools and a slab table left of the door — sitting furniture that
    # grew, not joinery. Each stump is a lathed trunk with root flare.
    for sx, sy2, r in ((-0.65, 1.35, 0.20), (-2.15, 1.55, 0.185)):
        bkit.lathe(bm, (sx, fy + sy2, 0.0),
                   [(r + 0.07, 0.0), (r, 0.10), (r * 0.94, 0.30),
                    (r, 0.44), (0.0, 0.46)],
                   segments=14, wobble=0.05, rng=rng)
    bkit.lathe(bm, (-1.42, fy + 1.62, 0.0),
               [(0.30, 0.0), (0.26, 0.30), (0.24, 0.62), (0.0, 0.64)],
               segments=14, wobble=0.04, rng=rng)
    # Table top: a sawn round of trunk, not a rock — lathed, slightly oval.
    top = bkit.lathe(bm, (-1.42, fy + 1.62, 0.63),
                     [(0.50, 0.0), (0.52, 0.03), (0.47, 0.065), (0.0, 0.07)],
                     segments=16, wobble=0.05, rng=rng)
    for v in top:
        v.co.y = fy + 1.62 + (v.co.y - (fy + 1.62)) * 0.9

    # Rope coil by the barrels: three lathed rings, each a hand's width off
    # the last, the frayed end trailing.
    for i, rr in enumerate((0.17, 0.155, 0.165)):
        ring = bkit.lathe(bm, (-3.65, fy + 0.35, 0.025 + i * 0.045),
                          [(rr - 0.022, -0.02), (rr + 0.022, -0.02),
                           (rr + 0.022, 0.02), (rr - 0.022, 0.02)],
                          segments=14, closed=True, wobble=0.06, rng=rng)
        bkit.jitter(ring, 0.008, rng)
    bkit.sweep(bm, [(-3.50, fy + 0.42, 0.03), (-3.25, fy + 0.55, 0.02),
                    (-3.05, fy + 0.50, 0.015)], 0.030, 0.030)

    # Hand-thrown pots by the door and one tipped over by the bench — lathe
    # profiles with real bellies and rolled lips, wobbled so no two match.
    for at, scale in (((DOOR_X - 0.85, fy + 0.42, 0.0), 1.0),
                      ((DOOR_X - 0.62, fy + 0.55, 0.0), 0.72)):
        bkit.lathe(bp, at,
                   [(0.10 * scale, 0.0), (0.155 * scale, 0.12 * scale),
                    (0.145 * scale, 0.26 * scale), (0.095 * scale, 0.36 * scale),
                    (0.115 * scale, 0.40 * scale), (0.085 * scale, 0.42 * scale)],
                   segments=12, wobble=0.05, rng=rng)
    tipped = bkit.lathe(bp, (0.0, 0.0, 0.0),
                        [(0.09, 0.0), (0.14, 0.11), (0.13, 0.24),
                         (0.085, 0.33), (0.10, 0.37), (0.075, 0.39)],
                        segments=12, wobble=0.05, rng=rng)
    matrix = bkit.place((3.55, fy + 0.75, 0.13), pitch=math.radians(96.0), yaw=1.1)
    for v in tipped:
        v.co = matrix @ v.co

    return (part.build(bevel=0.006, segments=1, smooth_angle=math.radians(46.0)),
            pottery.build(bevel=0.0, segments=1, smooth_angle=math.radians(50.0)))


# --- Assembly ---------------------------------------------------------------

def build():
    bkit.reset_scene()
    rng = bkit.rng_for("warm_start_inn_v2")
    parts = [
        build_stone(rng),
        build_plaster(rng),
        build_timber(rng),
        build_roof(rng),
        build_chimney(rng),
    ]
    parts.extend(build_openings(rng))
    parts.extend(build_sign(rng))
    parts.extend(build_dressing(rng))
    for obj in parts:
        if not obj.data.uv_layers:
            bkit.uv_project(obj, 0.6)
    return parts


VIEWS = {
    "01_hero": {"bearing": 34.0, "elev": 4.0, "dist": 30.0,
                "target": (0.0, 0.4, 4.0)},
    "02_eye_level": {"bearing": 8.0, "elev": -4.6, "dist": 26.0,
                     "target": (0.0, 0.4, 3.9)},
    "03_door": {"bearing": 12.0, "elev": -1.0, "dist": 6.5,
                "target": (DOOR_X, 2.9, 1.75)},
    "04_jetty_under": {"bearing": 26.0, "elev": -9.0, "dist": 7.5,
                       "target": (-1.4, 3.2, 2.9)},
    "05_gable_chimney": {"bearing": 108.0, "elev": 5.0, "dist": 28.0,
                         "target": (-1.0, 0.2, 4.2)},
    "06_window_close": {"bearing": 24.0, "elev": 0.0, "dist": 4.2,
                        "target": (2.47, 3.0, 1.6), "lens": 62.0},
    "07_sign": {"bearing": -22.0, "elev": 2.0, "dist": 8.5,
                "target": (-2.55, 4.1, 3.1)},
    "08_roof_eaves": {"bearing": 44.0, "elev": 12.0, "dist": 17.0,
                      "target": (0.0, 1.0, 6.0)},
    "09_back_oven": {"bearing": 196.0, "elev": -2.0, "dist": 12.0,
                     "target": (-2.0, -0.5, 1.6)},
    "10_yard_round": {"bearing": -14.0, "elev": -6.0, "dist": 6.0,
                      "target": (-1.4, 3.6, 0.9)},
}

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
    "inn_pottery": (0.55, 0.32, 0.20, 0.80),
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
        elif a == "--highlight" and i + 1 < len(argv):
            highlight = argv[i + 1]

    parts = build()
    total = bkit.report(parts)
    root = os.getcwd()
    path = bkit.export_glb(parts, os.path.join(root, OUT_DIR), OUT_NAME)
    print("OK %d parts, %d tris, ridge %.2f m -> %s" % (len(parts), total, RIDGE_Z, path))
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

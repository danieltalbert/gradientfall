"""Blender script: author Kern's garments ON his body mesh, in Blender.

Run (after tools/make_kern_base.py has produced the body):

    blender --background assets_src/kern.blend \\
        --python tools/make_kern_garments.py

Writes assets_src/kern_dressed.blend (override with `-- --out <path>`), then
export with tools/export_kern_base.py.

WHY THIS EXISTS
---------------
Kern's clothes used to be assembled from primitives by GDScript at runtime and
fitted over the imported body. That approach hit a hard ceiling, recorded in
docs/DEVLOG.md (2026-07-29): a full-length sleeve was unreachable because the
code-built cloth was rigidly bound to two bones while the body underneath
carries MPFB's smooth multi-bone weights. Under an 86-degree shoulder fold the
deltoid swells past any clearance that does not also balloon the sleeve off the
shoulder entirely. Roughly 40 render-fix cycles went in before it was called.

The fix is structural, and it is the whole idea of this script:

    **A garment is CUT FROM THE BODY'S OWN SURFACE.**

Duplicating body faces carries their vertex groups along, so the garment
inherits the exact same multi-bone weights as the skin beneath it. Cloth and
limb then deform as one — not approximately, but identically, because they are
driven by the same numbers. The sleeve problem cannot recur by construction,
and it costs no runtime fitting code at all.

Authorised by GDD section 10, "THE FIGURE SPLIT" (Danny, 2026-08-02).
Pipeline spec: docs/CHARACTER_PIPELINE.md.

HOW A GARMENT IS BUILT
----------------------
  1. **Region select.** Each vertex scores `sum(include weights) -
     sum(exclude weights)` over the body's BONE vertex groups. MPFB weights
     are normalised, so this yields a smooth anatomical boundary that lands
     where anatomy actually changes — a sleeve ends at the wrist because
     `lowerarm_*` fades into `hand_*` there, not because someone tuned a
     radius. This is what the old runtime COVERED_ZONES radius bands got
     wrong when a band running to r=0.70 deleted Kern's entire arm.
  2. **Smooth.** Cloth does not show abs, nipples or knuckles. A smoothing
     pass erases the anatomy the cut inherited while keeping the silhouette.
  3. **Offset** along vertex normals by the garment's clearance, so cloth sits
     above skin rather than z-fighting it.
  4. **Flare** — a graded outward push that grows toward the hem, so a tunic
     hangs like a tunic instead of reading as body paint.
  5. **Solidify** into real double-sided cloth with thickness.
  6. The body faces the garment fully covers are deleted AT AUTHOR TIME, on
     real geometry, by the same weight mask that cut the garment.

Everything here is deterministic: same .blend in, same garments out.
"""

import os
import sys

try:
    import bmesh
    import bpy
    from mathutils import Vector
except ImportError:  # pragma: no cover - only meaningful inside Blender
    sys.stderr.write(
        "This is a Blender script. Run it as:\n"
        "  blender --background assets_src/kern.blend "
        "--python tools/make_kern_garments.py\n")
    raise SystemExit(2)


BODY_NAME = "KernBody"

# Finger groups are excluded wholesale from sleeves; listing them explicitly
# keeps the sleeve boundary at the wrist rather than creeping onto the hand.
FINGERS = []
for _side in ("l", "r"):
    for _digit in ("index", "middle", "pinky", "ring", "thumb"):
        for _seg in ("01", "02", "03"):
            FINGERS.append("%s_%s_%s" % (_digit, _seg, _side))
HANDS = ["hand_l", "hand_r"] + FINGERS

# --- The garment set --------------------------------------------------------
# `include`/`exclude` map bone vertex-group names to a multiplier. A vertex is
# part of the garment when (include_score - exclude_score) >= `threshold`.
#
# `clearance` is how far the cloth floats above skin, in metres. It is layered
# deliberately: trousers 5 mm sit under the tunic's 9 mm, and boots at 14 mm
# swallow the trouser cuff, so nothing pokes through anything else.
GARMENTS = [
    {
        "name": "KernTunic",
        # Torso + FULL sleeves to the wrist. The sleeve that could not be
        # built by the old pipeline is simply part of the same cut here.
        #
        # The tunic ends at the hip, not mid-thigh. A skirt cut from the body
        # inevitably splits into two tubes because it follows two legs, which
        # renders as flaps rather than cloth; a real hanging skirt is lofted
        # geometry, not a body cut, and is a separate piece of work.
        "include": {
            "spine_01": 1.0, "spine_02": 1.0, "spine_03": 1.0,
            "clavicle_l": 1.0, "clavicle_r": 1.0,
            "pelvis": 0.85,
            "upperarm_l": 1.0, "upperarm_r": 1.0,
            "lowerarm_l": 1.0, "lowerarm_r": 1.0,
        },
        "exclude": dict([("head", 1.0), ("neck_01", 1.0),
                         ("thigh_l", 1.0), ("thigh_r", 1.0)]
                        + [(h, 1.0) for h in HANDS]),
        "threshold": 0.34,
        "clearance": 0.011,
        # Cloth hangs off the chest and blouses at the waist rather than
        # shrink-wrapping the pecs and navel. Extra standoff is applied in
        # proportion to each bone's own weight, so it fades anatomically.
        "clearance_by_group": {"spine_01": 0.016, "spine_02": 0.009,
                               "pelvis": 0.014},
        # Nipples survive heavy smoothing and read straight through a shirt.
        "flatten_groups": {"nipple": 0.009, "nippleTip": 0.014},
        "thickness": 0.0035,
        "smooth": 42,
        "relax": 30,
        "colour": (0.129, 0.310, 0.180, 1.0),   # deep meadow green
        "cover_body": 0.55,
    },
    {
        "name": "KernTrousers",
        "include": {
            "pelvis": 1.0,
            "thigh_l": 1.0, "thigh_r": 1.0,
            "calf_l": 1.0, "calf_r": 1.0,
        },
        "exclude": {"spine_01": 0.8, "spine_02": 1.0, "spine_03": 1.0,
                    "foot_l": 1.0, "foot_r": 1.0,
                    "ball_l": 1.0, "ball_r": 1.0},
        "threshold": 0.35,
        "clearance": 0.009,
        # Looser at the thigh, tapering to the calf so the leg reads as
        # trousered rather than painted.
        "clearance_by_group": {"thigh_l": 0.013, "thigh_r": 0.013,
                               "calf_l": 0.006, "calf_r": 0.006},
        "thickness": 0.003,
        "smooth": 34,
        "relax": 12,
        "colour": (0.157, 0.180, 0.216, 1.0),   # slate wool
        "cover_body": 0.60,
    },
    {
        "name": "KernBoots",
        # Foot + ankle + the lower third of the calf. The old boot shaft
        # stopped 65 mm below the trouser cuff and left a visible hole
        # whenever the knee bent; cutting the shaft from the calf itself and
        # clearing the trousers makes that gap impossible.
        #
        # The heavy smoothing and the big foot standoff are what turn a foot
        # into a boot: at low values the cut renders as a bare foot with
        # individual toes, because that is exactly the surface it was cut from.
        "include": {"foot_l": 1.0, "foot_r": 1.0,
                    "ball_l": 1.0, "ball_r": 1.0,
                    "calf_l": 1.0, "calf_r": 1.0},
        "exclude": {"thigh_l": 1.0, "thigh_r": 1.0},
        "threshold": 0.45,
        # Boots stop mid-calf: keep only the part of the region below 27% of
        # body height. Without this the "boot" climbs the whole shin.
        "z_max_frac": 0.27,
        "clearance": 0.013,
        "clearance_by_group": {"ball_l": 0.010, "ball_r": 0.010,
                               "foot_l": 0.008, "foot_r": 0.008},
        # Toes read as lumps through leather at any smoothing that keeps the
        # boot's own shape; press the nails in explicitly instead.
        "flatten_groups": {"toenails": 0.012},
        "thickness": 0.005,
        "smooth": 40,
        "relax": 14,
        # Leather does not taper to toes: flatten the sole to a real footbed.
        "sole": True,
        "colour": (0.184, 0.106, 0.075, 1.0),   # oiled brown leather
        "cover_body": 0.70,
    },
    {
        "name": "KernBelt",
        # A band at the waist, cut from a narrow height slice of the torso.
        # Clearance must clear the tunic beneath it (11 mm + 3.5 mm of cloth)
        # or it sinks into the garment it is supposed to be cinching.
        "include": {"pelvis": 1.0, "spine_01": 1.0},
        "exclude": {"thigh_l": 1.0, "thigh_r": 1.0,
                    "spine_03": 1.0,
                    "upperarm_l": 1.0, "upperarm_r": 1.0,
                    "lowerarm_l": 1.0, "lowerarm_r": 1.0},
        "threshold": 0.55,
        "z_min_frac": 0.537,
        "z_max_frac": 0.585,
        "clearance": 0.017,
        "thickness": 0.008,
        "smooth": 20,
        "relax": 10,
        "colour": (0.106, 0.071, 0.051, 1.0),   # dark strap leather
        "cover_body": None,                      # a belt hides nothing
    },
]


def log(msg):
    print("[kern-garments] %s" % msg)


def script_args():
    """Args after the '--' separator Blender uses to hand off to the script."""
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []


def out_path():
    args = script_args()
    if "--out" in args:
        return os.path.abspath(args[args.index("--out") + 1])
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(
        here, "..", "assets_src", "kern_dressed.blend"))


def find_body():
    body = bpy.data.objects.get(BODY_NAME)
    if body is None:
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        if not meshes:
            raise SystemExit("[kern-garments] FAIL: no mesh in this .blend")
        body = max(meshes, key=lambda m: len(m.data.vertices))
        log("WARN: no '%s'; using largest mesh '%s'" % (BODY_NAME, body.name))
    return body


def body_metrics(body):
    """Total height and floor height, used by the `z_*_frac` region limits.

    Read off the mesh rather than hardcoded so the script keeps working if
    MACRO in make_kern_base.py is retuned.
    """
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    height = max(zs) - min(zs)
    log("body: height %.3f m, floor z %.3f" % (height, min(zs)))
    return height, min(zs)


def weight_map(body, spec):
    """Per-vertex garment score: include weights minus exclude weights.

    Returns a list indexed by vertex, each value in roughly -1..1. MPFB's
    weights are normalised per vertex, so a score near 1 means "this vertex is
    squarely inside the garment's anatomy" and a score near 0 means "this is a
    boundary vertex" — which is exactly where a hem belongs.
    """
    gi = {g.name: g.index for g in body.vertex_groups}
    inc = {gi[n]: w for n, w in spec["include"].items() if n in gi}
    exc = {gi[n]: w for n, w in spec.get("exclude", {}).items() if n in gi}
    missing = [n for n in spec["include"] if n not in gi]
    if missing:
        log("WARN: %s has no vertex group(s) %s" % (spec["name"], missing))

    scores = []
    for v in body.data.vertices:
        score = 0.0
        for g in v.groups:
            if g.group in inc:
                score += g.weight * inc[g.group]
            if g.group in exc:
                score -= g.weight * exc[g.group]
        scores.append(score)
    return scores


def cut_garment(body, spec, height, floor_z):
    """Duplicate the body and delete everything outside the garment region."""
    obj = body.copy()
    obj.data = body.data.copy()
    obj.name = spec["name"]
    obj.data.name = spec["name"] + "Mesh"
    bpy.context.collection.objects.link(obj)

    scores = weight_map(body, spec)
    threshold = spec["threshold"]
    z_min = floor_z + height * spec["z_min_frac"] if "z_min_frac" in spec else None
    z_max = floor_z + height * spec["z_max_frac"] if "z_max_frac" in spec else None

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    doomed = []
    for i, v in enumerate(bm.verts):
        keep = scores[i] >= threshold
        if keep and z_min is not None and v.co.z < z_min:
            keep = False
        if keep and z_max is not None and v.co.z > z_max:
            keep = False
        if not keep:
            doomed.append(v)
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()

    kept = len(obj.data.vertices)
    if kept == 0:
        raise SystemExit(
            "[kern-garments] FAIL: %s selected 0 vertices — threshold %.2f is "
            "too high for its include set." % (spec["name"], threshold))
    log("%s: %d verts cut from the body" % (spec["name"], kept))
    return obj


def smooth_surface(obj, iterations):
    """Erase the anatomy the cut inherited — cloth hides musculature."""
    if iterations <= 0:
        return
    mod = obj.modifiers.new(name="ClothSmooth", type="SMOOTH")
    mod.factor = 0.6
    mod.iterations = iterations
    apply_modifier(obj, mod.name)


def relax_boundary(obj, iterations):
    """Even out the raw hem left by the cut.

    The region mask ends on a weight isoline, which at vertex resolution is
    visibly ragged — it renders as a torn collar and a chewed hem. Moving each
    boundary vertex toward the midpoint of its two boundary neighbours turns
    that into a clean edge. Only boundary vertices move, so the garment's fit
    over the body is untouched. Must run BEFORE solidify, which closes the rim
    and leaves no boundary to relax.
    """
    if iterations <= 0:
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    boundary = [v for v in bm.verts if v.is_boundary]
    for _ in range(iterations):
        moves = {}
        for v in boundary:
            nbrs = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            nbrs = [n for n in nbrs if n is not None]
            if len(nbrs) < 2:
                continue
            avg = Vector((0.0, 0.0, 0.0))
            for n in nbrs:
                avg += n.co
            moves[v] = v.co.lerp(avg / len(nbrs), 0.5)
        for v, co in moves.items():
            v.co = co
    bm.to_mesh(obj.data)
    bm.free()


def flatten_features(obj, spec):
    """Press dense anatomical features back into the cloth surface.

    General smoothing erases broad anatomy (ribs, abs, the spine) but is slow
    to converge on small dense clusters, so nipples and toenails survive 40+
    iterations and read as bumps through a shirt and lumps through a boot.
    MakeHuman tags those exact clusters with their own vertex groups, so this
    pulls them IN along the normal in proportion to their own weight — a
    targeted fix that leaves the surrounding silhouette alone. Smoothing
    harder would flatten the chest and the toe box with them.
    """
    flatten = spec.get("flatten_groups")
    if not flatten:
        return
    gi = {g.name: g.index for g in obj.vertex_groups}
    idx = {gi[n]: depth for n, depth in flatten.items() if n in gi}
    if not idx:
        return

    per_vert = [0.0] * len(obj.data.vertices)
    for i, v in enumerate(obj.data.vertices):
        pull = 0.0
        for g in v.groups:
            if g.group in idx:
                pull += g.weight * idx[g.group]
        per_vert[i] = pull

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    for i, v in enumerate(bm.verts):
        if per_vert[i] > 0.0:
            v.co -= v.normal * per_vert[i]
    bm.to_mesh(obj.data)
    bm.free()


def offset_cloth(obj, spec):
    """Lift the cloth off the skin along vertex normals.

    `clearance` is the uniform standoff. `clearance_by_group` adds more in
    proportion to a bone's own vertex weight, which is how a garment stops
    reading as body paint: real cloth bridges hollows instead of following
    them, so it stands further off the belly than the ribs and further off the
    toes than the ankle. Weighting the extra standoff by the bone group makes
    it fade out anatomically instead of ending at a hard line.
    """
    base = spec["clearance"]
    extra = spec.get("clearance_by_group", {})
    gi = {g.name: g.index for g in obj.vertex_groups}
    extra_idx = {gi[n]: amount for n, amount in extra.items() if n in gi}

    per_vert = [0.0] * len(obj.data.vertices)
    if extra_idx:
        for i, v in enumerate(obj.data.vertices):
            add = 0.0
            for g in v.groups:
                if g.group in extra_idx:
                    add += g.weight * extra_idx[g.group]
            per_vert[i] = add

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    for i, v in enumerate(bm.verts):
        v.co += v.normal * (base + per_vert[i])
    bm.to_mesh(obj.data)
    bm.free()


def flatten_sole(obj):
    """Give a boot a real footbed instead of the body's arched, toed sole."""
    floor = min(v.co.z for v in obj.data.vertices)
    band = 0.020
    for v in obj.data.vertices:
        if v.co.z < floor + band:
            v.co.z = floor + band * 0.5


def solidify(obj, thickness):
    """Turn the single surface into real cloth with two faces and an edge."""
    mod = obj.modifiers.new(name="ClothThickness", type="SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0            # grow outward, keeping the inner face on the fit
    mod.use_rim = True          # close the hem so it is not a raw open edge
    mod.use_rim_only = False
    apply_modifier(obj, mod.name)


def apply_modifier(obj, name):
    """Apply one modifier with `obj` active — works in background mode."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=name)


def set_material(obj, spec):
    """One material per garment, named so the Godot loader can route it."""
    mat = bpy.data.materials.new(name=spec["name"])
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = spec["colour"]
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.82
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def strip_covered_body(body, specs, height, floor_z):
    """Delete the body faces the garments fully cover, at AUTHOR time.

    The old runtime version of this deleted by radius band and once removed
    Kern's entire arm, leaving his hands floating in space. Here it reuses the
    very mask that cut each garment, so the deleted skin is by definition the
    skin that garment covers — and a vertex is only dropped when it is well
    INSIDE the region (`cover_body` sits above each garment's own threshold),
    which leaves a rim of skin under every hem so no gap can open at a seam.
    """
    doomed_idx = set()
    for spec in specs:
        cover = spec.get("cover_body")
        if cover is None:
            continue
        scores = weight_map(body, spec)
        z_min = (floor_z + height * spec["z_min_frac"]
                 if "z_min_frac" in spec else None)
        z_max = (floor_z + height * spec["z_max_frac"]
                 if "z_max_frac" in spec else None)
        for i, score in enumerate(scores):
            if score < cover:
                continue
            z = body.data.vertices[i].co.z
            if z_min is not None and z < z_min:
                continue
            if z_max is not None and z > z_max:
                continue
            doomed_idx.add(i)

    if not doomed_idx:
        log("body: nothing stripped")
        return

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    doomed = [bm.verts[i] for i in sorted(doomed_idx)]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    log("body: %d covered verts stripped (%d remain)"
        % (len(doomed_idx), len(body.data.vertices)))


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    body = find_body()
    height, floor_z = body_metrics(body)

    built = []
    for spec in GARMENTS:
        obj = cut_garment(body, spec, height, floor_z)
        smooth_surface(obj, spec.get("smooth", 0))
        flatten_features(obj, spec)
        relax_boundary(obj, spec.get("relax", 0))
        offset_cloth(obj, spec)
        if spec.get("sole"):
            flatten_sole(obj)
        solidify(obj, spec["thickness"])
        set_material(obj, spec)
        built.append(obj)
        log("%s: done (%d verts, %d polys)"
            % (obj.name, len(obj.data.vertices), len(obj.data.polygons)))

    strip_covered_body(body, GARMENTS, height, floor_z)

    path = out_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    log("saved %s" % path)
    log("garments: %s" % ", ".join(o.name for o in built))
    log("DONE — next: blender --background \"%s\" --python "
        "tools/export_kern_base.py" % path)


if __name__ == "__main__":
    main()

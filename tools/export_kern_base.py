"""Blender script: turn an MPFB character into game/assets/models/kern_base.glb.

Run it against a .blend that already contains an MPFB human with the GameEngine
rig (see game/assets/models/README.md for the ~6-click recipe that gets you
there):

    blender --background kern.blend --python tools/export_kern_base.py

or, to point somewhere else:

    blender --background kern.blend --python tools/export_kern_base.py -- \
        --out C:/path/to/kern_base.glb

Why this exists: making the character is a handful of GUI clicks, but *exporting
it correctly* is where every base mesh goes wrong -- wrong up-axis, centimetre
units, an A-pose that ruins the retarget, skinning silently off, helper geometry
riding along. Those are exactly the failures tools/check_base_mesh.py reports.
This script makes all of those decisions the same way every time:

  - keeps only the armature + body/eye/teeth meshes, drops MPFB helpers
  - renames meshes so kern_base_model.gd's EYE/TEETH/BROW hints match
  - stands the figure on the origin (feet at Z=0) and scales it to exactly 1.75 m
  - applies transforms so nothing carries a hidden scale into Godot
  - warns loudly if the rest pose is not a T-pose
  - exports .glb with +Y up, skinning on, deform bones only, animation off

Nothing here is Gradientfall-specific beyond the naming and the 1.75 m target,
so it is safe to re-run after tweaking the character.
"""

import math
import os
import sys

try:
    import bpy
    import mathutils
except ImportError:  # pragma: no cover - only meaningful inside Blender
    sys.stderr.write(
        "This is a Blender script. Run it as:\n"
        "  blender --background kern.blend --python tools/export_kern_base.py\n")
    raise SystemExit(2)


TARGET_HEIGHT = 1.75

# Meshes worth keeping, matched case-insensitively against object names.
KEEP_HINTS = ["body", "basemesh", "human", "eye", "cornea", "iris",
              "teeth", "tooth", "tongue", "brow", "lash", "nail"]
# MPFB helper/proxy geometry that must not ship.
DROP_HINTS = ["helper", "joint", "proxy_helper", "clothes_helper"]

EYE_HINTS = ["eye", "cornea", "iris"]
TEETH_HINTS = ["teeth", "tooth", "tongue"]
BROW_HINTS = ["brow", "lash"]

# The GameEngine rig bones the export must carry (mirrors kern_bone_map.gd).
REQUIRED_BONES = ["pelvis", "head", "upperarm_l", "upperarm_r",
                  "thigh_l", "thigh_r"]


def log(msg):
    print("[kern-export] %s" % msg)


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
        here, "..", "game", "assets", "models", "kern_base.glb"))


def find_armature():
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not armatures:
        raise SystemExit(
            "[kern-export] FAIL: no armature in this .blend. Add the MPFB "
            "GameEngine rig first (MPFB > Rig > Add rig > Game engine).")
    if len(armatures) > 1:
        log("WARN: %d armatures found, using '%s'"
            % (len(armatures), armatures[0].name))
    return armatures[0]


def check_rig(armature):
    names = {b.name.lower() for b in armature.data.bones}
    missing = [b for b in REQUIRED_BONES if b not in names]
    if missing:
        raise SystemExit(
            "[kern-export] FAIL: the armature is missing %s. That is not the "
            "GameEngine rig -- in MPFB choose Rig > Add rig > 'Game engine' "
            "(not Default/CMU/Mixamo)." % ", ".join(missing))
    log("rig OK: %d bones, GameEngine naming" % len(armature.data.bones))


def classify(name):
    lower = name.lower()
    if any(h in lower for h in DROP_HINTS):
        return "drop"
    if any(h in lower for h in KEEP_HINTS):
        return "keep"
    return "unknown"


def prune_and_rename(armature):
    """Delete helpers, keep body/eyes/teeth, and normalise names for the loader."""
    kept = []
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            continue
        verdict = classify(obj.name)
        if verdict == "drop":
            log("dropping helper mesh '%s'" % obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        if verdict == "unknown":
            log("WARN: keeping '%s' -- unrecognised name. If that is clothing "
                "or a helper, delete it: clothing is code-built in Godot."
                % obj.name)
        kept.append(obj)

    if not kept:
        raise SystemExit("[kern-export] FAIL: no mesh objects left to export.")

    # kern_base_model.gd matches surfaces by substring, so guarantee the hints
    # are actually present in the exported node names.
    for obj in kept:
        lower = obj.name.lower()
        if any(h in lower for h in EYE_HINTS) and "eye" not in lower:
            obj.name = "eye_" + obj.name
        elif any(h in lower for h in TEETH_HINTS) and "teeth" not in lower:
            obj.name = "teeth_" + obj.name
        elif any(h in lower for h in BROW_HINTS) and "brow" not in lower:
            obj.name = "brow_" + obj.name
    log("keeping %d mesh(es): %s"
        % (len(kept), ", ".join(o.name for o in kept)))
    return kept


def world_bounds(objs):
    lo = mathutils.Vector((math.inf,) * 3)
    hi = mathutils.Vector((-math.inf,) * 3)
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in objs:
        evaluated = obj.evaluated_get(deps)
        for corner in evaluated.bound_box:
            p = evaluated.matrix_world @ mathutils.Vector(corner)
            for k in range(3):
                lo[k] = min(lo[k], p[k])
                hi[k] = max(hi[k], p[k])
    return lo, hi


def normalise_transform(armature, meshes):
    """Scale to 1.75 m and stand the figure on the origin (Blender is Z-up)."""
    lo, hi = world_bounds(meshes)
    height = hi.z - lo.z
    if height <= 1e-6:
        raise SystemExit("[kern-export] FAIL: the body has no height.")
    log("measured height %.4f m" % height)

    factor = TARGET_HEIGHT / height
    if abs(factor - 1.0) > 0.001:
        log("scaling by %.5f to hit %.2f m" % (factor, TARGET_HEIGHT))
        armature.scale = armature.scale * factor

    bpy.context.view_layer.update()
    lo, _hi = world_bounds(meshes)
    if abs(lo.z) > 1e-5:
        log("dropping feet to Z=0 (were at %.4f)" % lo.z)
        armature.location.z -= lo.z
    bpy.context.view_layer.update()

    # Bake the transform so Godot never sees a hidden object scale.
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = world_bounds(meshes)
    log("final: %.4f m tall, feet at Z=%.4f" % (hi.z - lo.z, lo.z))


def _rest_droop(armature):
    """Degrees the left upper arm's REST pose drops below horizontal."""
    bone = armature.data.bones.get("upperarm_l") or \
        armature.data.bones.get("upperarm_r")
    if bone is None:
        return None
    vec = (bone.tail_local - bone.head_local)
    if vec.length < 1e-6:
        return None
    vec.normalize()
    # Blender is Z-up: the arm should run along X with little Z drop.
    return math.degrees(math.asin(max(-1.0, min(1.0, -vec.z))))


def ensure_tpose(armature, meshes):
    """Convert an A-pose rest pose (MakeHuman's default) into a proper T-pose.

    kern_visual's retarget assumes the rest pose is T. MPFB's game_engine rig
    rests in an A-pose, so: pose each arm chain straight out along +/-X, bake
    that pose into every mesh (apply + re-add the Armature modifiers), then
    apply the pose as the new rest pose. This is the canonical Blender
    A-to-T procedure, just scripted so it happens identically every time.
    """
    droop = _rest_droop(armature)
    if droop is None:
        log("WARN: no upperarm bone, skipping the T-pose check")
        return
    log("rest pose: arm drops %.1f deg below horizontal" % droop)
    if abs(droop) <= 8.0:
        log("rest pose is already T enough, leaving it alone")
        return
    log("converting A-pose rest to T-pose...")

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")

    # Straighten each arm chain bone-by-bone (children first read updated
    # parents), aiming every bone dead sideways. Chain order matters.
    for suffix, sign in (("_l", 1.0), ("_r", -1.0)):
        target = mathutils.Vector((sign, 0.0, 0.0))
        for bone_base in ("upperarm", "lowerarm", "hand"):
            pb = armature.pose.bones.get(bone_base + suffix)
            if pb is None:
                continue
            bpy.context.view_layer.update()
            direction = (pb.tail - pb.head)
            if direction.length < 1e-8:
                continue
            rot = direction.normalized().rotation_difference(target)
            pivot = mathutils.Matrix.Translation(pb.head)
            pb.matrix = (pivot @ rot.to_matrix().to_4x4()
                         @ pivot.inverted() @ pb.matrix)
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")

    # Bake the posed shape into the meshes: apply each Armature modifier at
    # the current pose, then re-add it so the mesh stays bound to the rig.
    for obj in meshes:
        arm_mods = [m for m in obj.modifiers if m.type == "ARMATURE"
                    and m.object == armature]
        if not arm_mods:
            continue
        with bpy.context.temp_override(object=obj, active_object=obj,
                                       selected_objects=[obj]):
            for mod in list(arm_mods):
                bpy.ops.object.modifier_apply(modifier=mod.name)
        fresh = obj.modifiers.new(name="Armature", type="ARMATURE")
        fresh.object = armature

    # Finally make the T the rest pose itself.
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    droop = _rest_droop(armature)
    log("rest pose now drops %.1f deg" % (droop if droop is not None else 0.0))
    if droop is not None and abs(droop) > 8.0:
        log("WARN: T-pose conversion did not fully straighten the arms -- "
            "check the result in Blender before using the export.")


def supported_kwargs(op, wanted):
    """Keep only kwargs this Blender's glTF exporter actually declares.

    The exporter's parameter names drift between Blender versions; filtering
    against the operator's RNA keeps one script working across 3.6 and 4.x
    instead of dying on an unexpected keyword.
    """
    try:
        declared = set(op.get_rna_type().properties.keys())
    except Exception:  # pragma: no cover - very old Blender
        return wanted
    out, dropped = {}, []
    for key, value in wanted.items():
        if key in declared:
            out[key] = value
        else:
            dropped.append(key)
    if dropped:
        log("note: this Blender ignores %s" % ", ".join(sorted(dropped)))
    return out


def export(armature, meshes, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = armature

    wanted = {
        "filepath": path,
        "export_format": "GLB",
        "use_selection": True,
        "export_yup": True,          # Godot is Y-up
        "export_apply": True,        # bake modifiers (subsurf etc.)
        "export_skins": True,        # the whole point
        "export_def_bones": True,    # deform bones only, no IK/control helpers
        "export_all_influences": False,
        "export_animations": False,  # we drive the skeleton ourselves
        "export_morph": False,
        "export_materials": "EXPORT",
        "export_cameras": False,
        "export_lights": False,
    }
    kwargs = supported_kwargs(bpy.ops.export_scene.gltf, wanted)
    log("exporting -> %s" % path)
    bpy.ops.export_scene.gltf(**kwargs)
    if not os.path.exists(path):
        raise SystemExit("[kern-export] FAIL: the exporter wrote nothing.")
    log("wrote %.1f MB" % (os.path.getsize(path) / (1024.0 * 1024.0)))


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    armature = find_armature()
    check_rig(armature)
    meshes = prune_and_rename(armature)
    ensure_tpose(armature, meshes)
    normalise_transform(armature, meshes)
    export(armature, meshes, out_path())
    log("done. Now verify it with:")
    log("  python tools/check_base_mesh.py")


if __name__ == "__main__":
    main()

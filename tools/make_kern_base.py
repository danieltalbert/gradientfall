"""Blender script: generate Kern's base body with MPFB, entirely headless.

Run:
    blender --background --python tools/make_kern_base.py

Writes C:/Users/danny/Documents/kern.blend (override with `-- --out <path>`).
Then export with tools/export_kern_base.py and verify with
tools/check_base_mesh.py — see game/assets/models/README.md.

This drives MPFB 2.0.x's documented service layer (HumanService /
TargetService), the same code paths the GUI buttons call:

  1. create_human  — MakeHuman basemesh at metre scale, feet on ground,
     with Kern's macro settings (young adult male, lean athletic)
  2. add_builtin_rig("game_engine")  — the 53-bone pelvis/spine_01/upperarm_l
     rig that src/player/kern/kern_bone_map.gd maps onto
  3. add_mhclo_asset  — separate low-poly eye meshes (+ teeth), rigged to
     the head bone so they follow animation
  4. bake_targets  — freeze the macro shapekeys into plain geometry
  5. delete helpers — strip MakeHuman's invisible fitting cage
  6. save the .blend

Clothing is deliberately NOT added: Kern's tunic/cloak/belt/boots/sword are
code-built in Godot and fitted over the bare body (GDD §1 amendment).
"""

import importlib
import os
import sys

import bpy

MPFB = "bl_ext.blender_org.mpfb"

# Kern's build (MakeHuman macro space, 0..1):
#   gender 0.85     — clearly male without bodybuilder jaw/brow extremes
#   age    0.42     — ~21 years: young adult, still a little boyish
#   muscle 0.60     — athletic, not bulky ("lean athletic" per the spec)
#   weight 0.42     — low body fat
#   height 0.55     — slightly tall; the export script rescales to exactly
#                     1.75 m anyway, this just keeps proportions natural
#   proportions 0.6 — nudged toward idealized (hero silhouette)
MACRO = {
    "gender": 0.85,
    "age": 0.42,
    "muscle": 0.60,
    "weight": 0.42,
    "proportions": 0.60,
    "height": 0.55,
    "cupsize": 0.5,     # inert at this gender setting
    "firmness": 0.5,
    # Light-medium warm skin per Kern's canon look; mostly caucasian blend
    # keeps the facial planes near the BOTW-Link reference.
    "race": {"asian": 0.15, "african": 0.05, "caucasian": 0.80},
}


def log(msg):
    print("[make-kern] %s" % msg)


def out_path():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    if "--out" in args:
        return os.path.abspath(args[args.index("--out") + 1])
    return r"C:\Users\danny\Documents\kern.blend"


def service(name):
    mod = importlib.import_module(MPFB + ".services." + name.lower())
    return getattr(mod, name)


def clear_scene():
    """Empty the default scene (cube, camera, light) so only Kern ships."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras,
                  bpy.data.lights):
        for datum in list(block):
            if datum.users == 0:
                block.remove(datum)
    log("scene cleared")


def main():
    HumanService = service("HumanService")
    LocationService = service("LocationService")
    TargetService = service("TargetService")

    clear_scene()

    # --- 1. The body ---------------------------------------------------------
    log("creating basemesh (this runs the macro targets, ~a minute)...")
    basemesh = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,      # keep fitting groups until assets are on
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,                  # MakeHuman decimetres -> metres
        macro_detail_dict=MACRO,
    )
    basemesh.name = "KernBody"
    log("basemesh created: %s" % basemesh.name)

    # --- 2. The rig ----------------------------------------------------------
    log("adding game_engine rig...")
    armature = HumanService.add_builtin_rig(basemesh, "game_engine",
                                            import_weights=True)
    if armature is None:
        raise SystemExit("[make-kern] FAIL: game_engine rig did not load")
    armature.name = "KernRig"
    bone_names = [b.name for b in armature.data.bones]
    log("rig: %d bones" % len(bone_names))
    for required in ["pelvis", "head", "upperarm_l", "thigh_r"]:
        if required not in bone_names:
            raise SystemExit("[make-kern] FAIL: rig lacks '%s'" % required)

    # --- 3. Eyes + teeth (separate meshes, rigged to the head) ---------------
    user_data = LocationService.get_user_data()
    eyes_mhclo = os.path.join(user_data, "eyes", "low-poly", "low-poly.mhclo")
    teeth_mhclo = os.path.join(user_data, "teeth", "teeth_base",
                               "teeth_base.mhclo")
    if not os.path.exists(eyes_mhclo):
        raise SystemExit(
            "[make-kern] FAIL: no eyes asset at %s. Extract the MakeHuman "
            "system assets pack into MPFB's user data first (the pack loader "
            "in MPFB, or tools docs in game/assets/models/README.md)."
            % eyes_mhclo)

    log("adding eyes (low-poly)...")
    bpy.context.view_layer.objects.active = basemesh
    eyes = HumanService.add_mhclo_asset(
        eyes_mhclo, basemesh, asset_type="Eyes", subdiv_levels=0,
        material_type="MAKESKIN", set_up_rigging=True,
        interpolate_weights=True)
    # Rename so the loader's surface hints match: kern_base_model.gd routes
    # materials by substring ("eye"/"teeth"), and MPFB's default name for the
    # asset object ("KernBody.low-poly") carries neither.
    if eyes is not None and getattr(eyes, "name", None):
        eyes.name = "KernEyes"
        log("eyes object: %s" % eyes.name)

    if os.path.exists(teeth_mhclo):
        log("adding teeth (base)...")
        bpy.context.view_layer.objects.active = basemesh
        teeth = HumanService.add_mhclo_asset(
            teeth_mhclo, basemesh, asset_type="Teeth", subdiv_levels=0,
            material_type="MAKESKIN", set_up_rigging=True,
            interpolate_weights=True)
        if teeth is not None and getattr(teeth, "name", None):
            teeth.name = "KernTeeth"

    # --- 4. Bake shapekeys ---------------------------------------------------
    log("baking macro targets into plain geometry...")
    TargetService.bake_targets(basemesh)

    # --- 5. Delete helper geometry ------------------------------------------
    # The MPFB operator needs the basemesh active; background mode still
    # provides a workable context for it.
    log("deleting helper cage...")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = basemesh
    basemesh.select_set(True)
    try:
        bpy.ops.mpfb.delete_helpers()
    except Exception as exc:  # noqa: BLE001 - report and continue; export
        # prunes helper-looking meshes anyway and the fitting pass can cope
        log("WARN: delete_helpers failed (%s) — continuing, the export "
            "script prunes helper geometry by name" % exc)

    # --- 6. Save -------------------------------------------------------------
    path = out_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    log("saved %s" % path)

    meshes = [o.name for o in bpy.data.objects if o.type == "MESH"]
    log("final meshes: %s" % ", ".join(meshes))
    log("DONE — next: blender --background \"%s\" --python "
        "tools/export_kern_base.py" % path)


if __name__ == "__main__":
    main()

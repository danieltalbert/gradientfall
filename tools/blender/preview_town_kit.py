"""Render a cottage assembled from the Datasedge kit, with a Kern-sized figure.

This is the STRUCTURE_PIPELINE.md §9 quality gate made runnable. Shot 1 of that
gate is the doorway: Kern standing in the opening, head clearing the lintel. If
that is wrong nothing else about the building matters, and it is the one thing
that is invisible until somebody stands next to it.

Run::

    blender -b --python tools/blender/preview_town_kit.py

Writes PNGs beside the kit under ``game/assets/models/town/preview/``.
"""

import importlib.util
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "build_town_kit", os.path.join(HERE, "build_town_kit.py"))
kit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kit)

KERN_H = 1.75
OUT = os.path.join("game", "assets", "models", "town", "preview")


def place(name, part_name, location, rotation_z=0.0):
    """Duplicate a kit part into the scene at a spot."""
    src = bpy.data.objects[part_name]
    obj = src.copy()
    obj.data = src.data.copy()
    obj.name = name
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, rotation_z)
    bpy.context.collection.objects.link(obj)
    return obj


def assemble_cottage():
    """Four walls, a roof, a chimney, a porch and the lean-to that keeps it from
    being symmetrical. 6 x 8 m, which is a one-or-two-room cottage."""
    w, d = 6.0, 8.0
    hw, hd = w * 0.5, d * 0.5
    # South wall carries the door; north and the long sides carry windows.
    place("wall_s", "kit_cob_wall_4m_door", (0.0, -hd, 0.0), 0.0)
    place("wall_n", "kit_cob_wall_6m_window", (0.0, hd, 0.0), 0.0)
    place("wall_w", "kit_cob_wall_4m_window", (-hw, 0.0, 0.0), math.radians(90))
    place("wall_e", "kit_cob_wall_4m", (hw, 0.0, 0.0), math.radians(90))
    place("roof", "kit_thatch_roof_6x8", (0.0, 0.0, 0.36 + kit.STOREY))
    place("chimney", "kit_shared_chimney", (hw - 0.9, hd - 1.2, 0.36 + kit.STOREY))
    place("porch", "kit_shared_porch", (0.0, -hd - 1.0, 0.0))
    place("door", "kit_shared_door_plank", (0.0, -hd - kit.WALL_T * 0.5, 0.0))
    # The irregularity every structure gets (STRUCTURE_PIPELINE.md §4.2): a
    # lean-to on the weather side that nobody planned.
    place("leanto", "kit_shared_leanto", (-hw - 1.2, 1.4, 0.0), math.radians(90))
    place("fence", "kit_shared_fence_4m", (0.0, -hd - 3.6, 0.0))


def add_kern_reference():
    """A 1.75 m capsule where Kern would stand. Deliberately crude — this is a
    measuring stick, not a character."""
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=KERN_H,
                                        location=(0.0, -4.9, KERN_H * 0.5))
    body = bpy.context.active_object
    body.name = "kern_reference"
    mat = bpy.data.materials.new("kern_ref")
    mat.diffuse_color = (0.85, 0.25, 0.15, 1.0)
    body.data.materials.append(mat)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13,
                                         location=(0.0, -4.9, KERN_H - 0.1))
    head = bpy.context.active_object
    head.data.materials.append(mat)


PALETTE = {
    "wall": (0.74, 0.68, 0.55, 1.0),
    "roof": (0.52, 0.42, 0.22, 1.0),
    "wood": (0.34, 0.24, 0.15, 1.0),
}


def tint_scene():
    """Preview-only colours. The exported .glb carries no materials on purpose."""
    mats = {}
    for key, rgba in PALETTE.items():
        mat = bpy.data.materials.new("preview_" + key)
        mat.diffuse_color = rgba
        mat.roughness = 0.9
        mats[key] = mat
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.name.startswith("kern"):
            continue
        name = obj.name
        if "roof" in name:
            key = "roof"
        elif "wall" in name or "leanto" in name or "chimney" in name:
            key = "wall"
        else:
            key = "wood"
        obj.data.materials.clear()
        obj.data.materials.append(mats[key])


def light_and_ground():
    bpy.ops.mesh.primitive_plane_add(size=80.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    mat = bpy.data.materials.new("ground")
    mat.diffuse_color = (0.32, 0.34, 0.22, 1.0)
    ground.data.materials.append(mat)
    # Low side sun: raking light is what reveals bevels and wall thickness.
    bpy.ops.object.light_add(type="SUN", location=(6.0, -8.0, 9.0))
    sun = bpy.context.active_object
    sun.data.energy = 4.0
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = (math.radians(52), 0.0, math.radians(28))
    world = bpy.data.worlds.new("w")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.58, 0.75, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9


def shoot(name, location, look_at, lens=50.0):
    bpy.ops.object.camera_add(location=location)
    cam = bpy.context.active_object
    cam.data.lens = lens
    direction = (bpy.data.objects.new("t", None), )
    # Aim with a Track To constraint against an empty at the target.
    target = bpy.data.objects.new("aim_" + name, None)
    target.location = look_at
    bpy.context.collection.objects.link(target)
    con = cam.constraints.new("TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    out_dir = os.path.join(os.getcwd(), OUT)
    os.makedirs(out_dir, exist_ok=True)
    scene.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered -> %s" % scene.render.filepath)
    bpy.data.objects.remove(cam, do_unlink=True)


def main():
    kit.build_kit()          # parts live in the scene already
    assemble_cottage()
    add_kern_reference()
    light_and_ground()
    tint_scene()
    # The kit parts themselves sit at the origin under the cottage; hide them so
    # they do not photobomb the assembled building.
    for obj in bpy.context.scene.objects:
        if obj.name.startswith("kit_"):
            obj.hide_render = True
    # Gate shot 1: the doorway, with Kern in it. Stand well back and use a long
    # lens — a wide lens up close distorts exactly the proportion being judged.
    shoot("gate1_doorway", (0.0, -14.0, 1.60), (0.0, -4.2, 1.15), lens=85.0)
    # Gate shot 3: the corner at 8 m — bevels, wall thickness, wear at the base.
    shoot("gate3_corner", (9.0, -12.0, 4.0), (0.0, -1.0, 1.8), lens=40.0)
    # Gate shot 2: silhouette. Same building, flat against the sky.
    shoot("gate2_silhouette", (16.0, -16.0, 3.0), (0.0, 0.0, 2.4), lens=55.0)
    print("OK preview")


if __name__ == "__main__":
    main()

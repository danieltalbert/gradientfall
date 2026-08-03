"""Blender script: render the character quality-gate sheet for any figure.

Run:

    blender --background assets_src/kern_dressed.blend \\
        --python tools/render_character_sheet.py -- --outdir C:/abs/dir

Optional:
    --mode solid|silhouette|both   (default both)
    --turn 8                       (also render an N-frame turnaround)
    --res 900
    --hide KernBody,KernTeeth      (comma-separated objects to leave out)
    --only KernTunic,KernBoots     (render ONLY these — everything else hides)

`--hide`/`--only` exist for a specific diagnostic that comes up constantly
when fitting garments: a bump on a clothed torso is either a fold in the
cloth or the body poking THROUGH the cloth, and those two need opposite
fixes. Rendering the garments alone settles it in one frame instead of a
tuning spiral.

WHY THIS EXISTS
---------------
docs/CHARACTER_PIPELINE.md section 7 defines a five-test quality gate that
Danny can enforce without reading code. Two of those tests — the silhouette
test and the turnaround — are pure model checks that do not need the game
running, and iterating on a garment fit through a full Godot boot is slow.
This renders them straight out of the .blend in seconds.

It deliberately uses the WORKBENCH engine, not EEVEE or Cycles:

  - it is the shading modellers actually judge form in — flat studio light
    plus cavity shading, which shows surface direction and creases without
    materials, colour or lighting flattering the result;
  - it renders correctly in `--background` on any machine, with no GPU
    context and no scene lighting to set up;
  - and it is fast enough to iterate a garment fit in a tight loop.

Silhouette mode renders every object pure black on white, which is the
single highest-value test in the gate: a figure that is not readable as a
black shape is not readable at gameplay distance either.
"""

import math
import os
import sys

try:
    import bpy
    from mathutils import Vector
except ImportError:  # pragma: no cover - only meaningful inside Blender
    sys.stderr.write(
        "This is a Blender script. Run it as:\n"
        "  blender --background <file>.blend "
        "--python tools/render_character_sheet.py -- --outdir C:/abs/dir\n")
    raise SystemExit(2)


# Named camera angles, as compass bearings in degrees around the figure.
# 0 faces the model's front (-Y in MakeHuman space, see `orbit` below).
VIEWS = {
    "01_front": 0.0,
    "02_threequarter": 35.0,
    "03_side": 90.0,
    "04_back": 180.0,
}


def log(msg):
    print("[char-sheet] %s" % msg)


def script_args():
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []


def arg(name, default=None):
    args = script_args()
    if name in args:
        return args[args.index(name) + 1]
    return default


def apply_visibility():
    """Honour --hide / --only before anything measures or renders the scene."""
    hide = [n.strip() for n in (arg("--hide") or "").split(",") if n.strip()]
    only = [n.strip() for n in (arg("--only") or "").split(",") if n.strip()]
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        if only:
            obj.hide_render = obj.name not in only
        elif obj.name in hide:
            obj.hide_render = True
    shown = [o.name for o in visible_meshes()]
    if hide or only:
        log("rendering only: %s" % ", ".join(shown))


def visible_meshes():
    return [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render]


def subject_bounds():
    """World-space bounding box of every renderable mesh, as (min, max)."""
    meshes = visible_meshes()
    if not meshes:
        raise SystemExit("[char-sheet] FAIL: no renderable mesh in this .blend")
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    return lo, hi


def setup_scene(res, silhouette):
    """Workbench render settings — see the module docstring for why."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"

    shading = scene.display.shading
    if silhouette:
        # Flat single-colour objects on a white world: pure shape, nothing else.
        shading.light = "FLAT"
        shading.color_type = "SINGLE"
        shading.single_color = (0.0, 0.0, 0.0)
        shading.show_cavity = False
        shading.show_shadows = False
        shading.show_object_outline = False
        scene.world.color = (1.0, 1.0, 1.0)
    else:
        # Studio light + cavity: reads form and creases without materials.
        shading.light = "STUDIO"
        shading.studio_light = "Default"
        shading.color_type = "SINGLE"
        shading.single_color = (0.62, 0.62, 0.64)
        shading.show_cavity = True
        shading.cavity_type = "BOTH"
        shading.show_shadows = True
        shading.show_object_outline = False
        scene.world.color = (0.20, 0.21, 0.24)
    scene.display.render_aa = "8"


def ensure_camera():
    cam_data = bpy.data.cameras.new("SheetCam")
    cam_data.lens = 85.0            # portrait-ish; minimal perspective distortion
    cam = bpy.data.objects.new("SheetCam", cam_data)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


def orbit(cam, bearing_deg, lo, hi):
    """Place the camera at `bearing_deg` around the figure, framing all of it.

    MakeHuman figures face -Y, so bearing 0 puts the camera on -Y looking
    back at the front. Distance is derived from the subject's height and the
    lens so a tall figure and a squat creature both fill the frame.
    """
    centre = (lo + hi) * 0.5
    height = max(hi.z - lo.z, 1e-3)
    width = max(hi.x - lo.x, hi.y - lo.y, 1e-3)
    extent = max(height, width)

    lens = cam.data.lens
    sensor = cam.data.sensor_width
    # Half-angle of the frustum; back off far enough to fit `extent` plus 12%.
    half_fov = math.atan((sensor * 0.5) / lens)
    distance = (extent * 0.56) / math.tan(half_fov) * 1.12

    theta = math.radians(bearing_deg)
    # bearing 0 -> -Y (front), 90 -> +X (the figure's left, camera-right)
    offset = Vector((math.sin(theta), -math.cos(theta), 0.0)) * distance
    cam.location = centre + offset + Vector((0.0, 0.0, height * 0.04))

    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    log("wrote %s" % os.path.basename(path))


def main():
    outdir = arg("--outdir")
    if not outdir:
        raise SystemExit("[char-sheet] FAIL: pass -- --outdir C:/abs/dir")
    outdir = os.path.abspath(outdir)
    os.makedirs(outdir, exist_ok=True)

    mode = arg("--mode", "both")
    res = int(arg("--res", "900"))
    turn = int(arg("--turn", "0"))

    apply_visibility()
    lo, hi = subject_bounds()
    log("subject: %.3f m tall, %d meshes"
        % (hi.z - lo.z, len(visible_meshes())))

    cam = ensure_camera()

    passes = []
    if mode in ("solid", "both"):
        passes.append(("", False))
    if mode in ("silhouette", "both"):
        passes.append(("sil_", True))

    for prefix, silhouette in passes:
        setup_scene(res, silhouette)
        for name, bearing in sorted(VIEWS.items()):
            orbit(cam, bearing, lo, hi)
            render_to(os.path.join(outdir, "%s%s.png" % (prefix, name)))

    if turn > 0:
        setup_scene(res, False)
        for i in range(turn):
            orbit(cam, 360.0 * i / turn, lo, hi)
            render_to(os.path.join(outdir, "turn_%02d.png" % i))

    log("DONE -> %s" % outdir)


if __name__ == "__main__":
    main()

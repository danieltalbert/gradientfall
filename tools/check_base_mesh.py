#!/usr/bin/env python3
"""Validate a Kern base mesh against the spec in game/assets/models/README.md.

Zero dependencies (same rule as validate_content.py). Reads .glb or .gltf and
checks the things that actually break the fitting pass, in the order they bite:

  1. parses as glTF 2.0
  2. carries a skinned armature
  3. the rig answers to kern_bone_map.gd's candidate names
  4. stands ~1.75 m tall, +Y up, in metres
  5. is in a T-pose (arms out along X), not an A-pose
  6. ships separate eye meshes
  7. ships NO clothing (clothing is code-built and fitted over the body)
  8. carries no baked animation (the rest pose is what we retarget onto)

Usage:
    python tools/check_base_mesh.py [path-to-glb]

Defaults to game/assets/models/kern_base.glb. Exit code 0 = usable, 1 = not.
"""

import json
import math
import os
import struct
import sys

# --- The rig contract, mirrored from src/player/kern/kern_bone_map.gd --------
# Keep in step with CANDIDATES there. Order matters only for the report.
CANDIDATES = {
    "Hips": ["pelvis", "Hips", "hips", "mixamorig:Hips"],
    "Spine": ["spine_01", "Spine", "spine", "mixamorig:Spine"],
    "Chest": ["spine_03", "spine_02", "Chest", "chest", "mixamorig:Spine2"],
    "Neck": ["neck_01", "Neck", "neck", "mixamorig:Neck"],
    "Head": ["head", "Head", "mixamorig:Head"],
    "ClavicleL": ["clavicle_l", "shoulder_l", "LeftShoulder", "mixamorig:LeftShoulder"],
    "UpperArmL": ["upperarm_l", "LeftArm", "mixamorig:LeftArm"],
    "ForearmL": ["lowerarm_l", "forearm_l", "LeftForeArm", "mixamorig:LeftForeArm"],
    "HandL": ["hand_l", "LeftHand", "mixamorig:LeftHand"],
    "ClavicleR": ["clavicle_r", "shoulder_r", "RightShoulder", "mixamorig:RightShoulder"],
    "UpperArmR": ["upperarm_r", "RightArm", "mixamorig:RightArm"],
    "ForearmR": ["lowerarm_r", "forearm_r", "RightForeArm", "mixamorig:RightForeArm"],
    "HandR": ["hand_r", "RightHand", "mixamorig:RightHand"],
    "ThighL": ["thigh_l", "LeftUpLeg", "mixamorig:LeftUpLeg"],
    "ShinL": ["calf_l", "shin_l", "LeftLeg", "mixamorig:LeftLeg"],
    "FootL": ["foot_l", "LeftFoot", "mixamorig:LeftFoot"],
    "ThighR": ["thigh_r", "RightUpLeg", "mixamorig:RightUpLeg"],
    "ShinR": ["calf_r", "shin_r", "RightLeg", "mixamorig:RightLeg"],
    "FootR": ["foot_r", "RightFoot", "mixamorig:RightFoot"],
}
# kern_bone_map.is_usable() - without these the loader rejects the mesh.
REQUIRED = ["Hips", "Head", "UpperArmL", "UpperArmR", "ThighL", "ThighR"]

TARGET_HEIGHT = 1.75
HEIGHT_TOLERANCE = 0.06

EYE_HINTS = ["eye", "cornea", "iris"]
# Clothing must NOT be baked in - the tunic/cloak/belt/boots are code-built.
CLOTHING_HINTS = [
    "shirt", "tunic", "pant", "trouser", "shoe", "boot", "cloak", "dress",
    "skirt", "jacket", "coat", "sock", "glove", "hat", "helmet", "armor",
    "armour", "underwear", "brief",
]
# These are fine to ship and shouldn't trip the clothing check.
BODY_PARTS = ["eye", "teeth", "tooth", "tongue", "brow", "lash", "nail",
              "body", "base", "human", "mesh", "highpoly", "proxy"]


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.notes = []

    def error(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)

    def note(self, msg):
        self.notes.append(msg)

    def ok(self):
        return not self.errors


# --- glTF loading -----------------------------------------------------------

def load_gltf(path):
    """Return the glTF JSON dict from a .glb or .gltf file."""
    with open(path, "rb") as fh:
        head = fh.read(4)
        fh.seek(0)
        if head == b"glTF":
            data = fh.read()
            if len(data) < 12:
                raise ValueError("file is too short to be a .glb")
            magic, version, _length = struct.unpack_from("<4sII", data, 0)
            if version != 2:
                raise ValueError("glTF version %d, expected 2" % version)
            offset = 12
            while offset + 8 <= len(data):
                chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
                offset += 8
                chunk = data[offset:offset + chunk_len]
                offset += chunk_len
                if chunk_type == 0x4E4F534A:  # 'JSON'
                    return json.loads(chunk.decode("utf-8"))
            raise ValueError(".glb has no JSON chunk")
        return json.load(open(path, "r", encoding="utf-8"))


# --- 4x4 matrix helpers (glTF matrices are column-major) ---------------------

def mat_identity():
    return [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def mat_mul(a, b):
    """a * b, both column-major 16-float lists."""
    out = [0.0] * 16
    for col in range(4):
        for row in range(4):
            out[col * 4 + row] = sum(
                a[k * 4 + row] * b[col * 4 + k] for k in range(4))
    return out


def mat_from_trs(t, r, s):
    """Compose translation, quaternion (x,y,z,w) and scale into a matrix."""
    x, y, z, w = r
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    rot = [
        1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0,
        2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0,
        2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0,
        0, 0, 0, 1,
    ]
    for col in range(3):
        for row in range(3):
            rot[col * 4 + row] *= s[col]
    rot[12], rot[13], rot[14] = t[0], t[1], t[2]
    return rot


def node_local_matrix(node):
    if "matrix" in node:
        return list(node["matrix"])
    return mat_from_trs(
        node.get("translation", [0.0, 0.0, 0.0]),
        node.get("rotation", [0.0, 0.0, 0.0, 1.0]),
        node.get("scale", [1.0, 1.0, 1.0]),
    )


def transform_point(m, p):
    x, y, z = p
    return (
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    )


def world_transforms(gltf):
    """Map node index -> world matrix, walking every scene root."""
    nodes = gltf.get("nodes", [])
    out = {}

    def walk(idx, parent):
        if idx in out:
            return
        world = mat_mul(parent, node_local_matrix(nodes[idx]))
        out[idx] = world
        for child in nodes[idx].get("children", []):
            walk(child, world)

    roots = set()
    for scene in gltf.get("scenes", []):
        roots.update(scene.get("nodes", []))
    if not roots:
        child_of = set()
        for node in nodes:
            child_of.update(node.get("children", []))
        roots = set(range(len(nodes))) - child_of
    for root in sorted(roots):
        walk(root, mat_identity())
    # Orphans (not reachable from any scene) still get a transform.
    for idx in range(len(nodes)):
        if idx not in out:
            walk(idx, mat_identity())
    return out


# --- Individual checks ------------------------------------------------------

def check_skin(gltf, rep):
    """Return (joint_node_indices, name_to_index) for the largest skin."""
    skins = gltf.get("skins", [])
    if not skins:
        rep.error("no skin/armature - re-export with Skinning ON "
                  "(the mesh must be bound to the rig, not just parented)")
        return [], {}
    skin = max(skins, key=lambda s: len(s.get("joints", [])))
    joints = skin.get("joints", [])
    nodes = gltf.get("nodes", [])
    by_name = {}
    for j in joints:
        name = nodes[j].get("name", "")
        if name:
            by_name.setdefault(name, j)
    rep.note("rig: %d deform bones" % len(joints))
    if len(joints) < 20:
        rep.warn("only %d bones - the GameEngine rig should export ~53. "
                 "Check 'Export deformation bones only' didn't strip too much."
                 % len(joints))
    return joints, by_name


def check_bone_names(by_name, rep):
    """Match the rig against kern_bone_map's candidates. Returns matched dict."""
    matched, unmapped = {}, []
    for our_name, candidates in CANDIDATES.items():
        hit = next((c for c in candidates if c in by_name), None)
        if hit is None:
            unmapped.append(our_name)
        else:
            matched[our_name] = by_name[hit]
    rep.note("bone map: matched %d/%d" % (len(matched), len(CANDIDATES)))
    missing_required = [b for b in REQUIRED if b not in matched]
    if missing_required:
        rep.error("rig is missing bones kern_bone_map requires: %s. "
                  "Export the MPFB **GameEngine** rig (pelvis/spine_01/"
                  "upperarm_l/...)." % ", ".join(missing_required))
    elif unmapped:
        rep.warn("these won't be driven (animation skips them): %s"
                 % ", ".join(unmapped))
    return matched


def mesh_bounds(gltf, rep):
    """World-space bounding box over every mesh, from accessor min/max."""
    accessors = gltf.get("accessors", [])
    meshes = gltf.get("meshes", [])
    worlds = world_transforms(gltf)
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    for idx, node in enumerate(gltf.get("nodes", [])):
        if "mesh" not in node:
            continue
        world = worlds.get(idx, mat_identity())
        for prim in meshes[node["mesh"]].get("primitives", []):
            acc_idx = prim.get("attributes", {}).get("POSITION")
            if acc_idx is None:
                continue
            acc = accessors[acc_idx]
            if "min" not in acc or "max" not in acc:
                continue
            amin, amax = acc["min"], acc["max"]
            # All 8 corners, since the node may rotate.
            for cx in (amin[0], amax[0]):
                for cy in (amin[1], amax[1]):
                    for cz in (amin[2], amax[2]):
                        p = transform_point(world, (cx, cy, cz))
                        for k in range(3):
                            lo[k] = min(lo[k], p[k])
                            hi[k] = max(hi[k], p[k])
    if lo[0] is math.inf or hi[0] == -math.inf:
        rep.error("no POSITION data found - the file has no usable geometry")
        return None
    return lo, hi


def check_scale(bounds, rep):
    lo, hi = bounds
    size = [hi[k] - lo[k] for k in range(3)]
    rep.note("bounds: %.3f wide (X) x %.3f tall (Y) x %.3f deep (Z) m"
             % (size[0], size[1], size[2]))
    # Up-axis check: a T-posing human is legitimately WIDER (arm span, X) than
    # tall, so only Y vs Z is meaningful. A Z-up export puts the height in Z
    # and the ~30 cm body depth in Y.
    if size[2] > size[1] * 1.5:
        rep.error("the model is %.2f m along Z but only %.2f m along Y - it "
                  "was exported Z-up. Re-export with Transform +Y Up."
                  % (size[2], size[1]))
        return
    height = size[1]
    if height < 0.2:
        rep.error("model is %.3f m tall - that looks like centimetre or "
                  "decimetre units. Export in metres." % height)
    elif height > 20.0:
        rep.error("model is %.1f m tall - units are wrong (centimetres?). "
                  "Export in metres." % height)
    elif abs(height - TARGET_HEIGHT) > HEIGHT_TOLERANCE:
        rep.warn("height %.3f m differs from the spec'd %.2f m. Not fatal - "
                 "kern_base_model.measure_height() rescales the code-built "
                 "gear to fit - but the gait was tuned at %.2f m."
                 % (height, TARGET_HEIGHT, TARGET_HEIGHT))
    if abs(lo[1]) > 0.05:
        rep.warn("feet sit at Y=%.3f, not 0 - the character will float or "
                 "sink. Apply the armature transform with the feet on the "
                 "origin before export." % lo[1])


def check_tpose(gltf, matched, rep):
    """Arms out along X = T-pose; arms down at ~45 deg = A-pose."""
    need = ["UpperArmL", "HandL"]
    if not all(b in matched for b in need):
        rep.warn("can't check the rest pose - arm bones didn't map")
        return
    worlds = world_transforms(gltf)
    shoulder = transform_point(worlds[matched["UpperArmL"]], (0, 0, 0))
    hand = transform_point(worlds[matched["HandL"]], (0, 0, 0))
    reach = [hand[k] - shoulder[k] for k in range(3)]
    span = math.sqrt(sum(v * v for v in reach))
    if span < 1e-4:
        rep.warn("arm bones are coincident - can't judge the rest pose")
        return
    droop = math.degrees(math.asin(max(-1.0, min(1.0, -reach[1] / span))))
    droop += 0.0  # normalise -0.0 so the report doesn't read "-0.0 deg"
    rep.note("left arm drops %.1f deg below horizontal in the rest pose" % droop)
    if droop > 25.0:
        rep.error("this is an A-pose (arm %.0f deg below horizontal), not a "
                  "T-pose. Set the rest pose to T before exporting - the "
                  "retarget in kern_visual assumes T." % droop)
    elif droop > 12.0:
        rep.warn("arm is %.0f deg below horizontal - flatter than a clean "
                 "T-pose. Usable, but limb poses will sit slightly low." % droop)


def mesh_names(gltf):
    names = []
    for node in gltf.get("nodes", []):
        if "mesh" in node:
            mesh = gltf["meshes"][node["mesh"]]
            names.append(node.get("name") or mesh.get("name") or "")
    for mesh in gltf.get("meshes", []):
        name = mesh.get("name")
        if name and name not in names:
            names.append(name)
    return [n for n in names if n]


def check_meshes(gltf, rep):
    names = mesh_names(gltf)
    rep.note("meshes: %s" % (", ".join(names) if names else "(unnamed)"))
    lowered = [n.lower() for n in names]
    if not any(any(h in n for h in EYE_HINTS) for n in lowered):
        rep.warn("no mesh looks like an eye. The spec asks for separate eye "
                 "meshes; without them kern_head's code-built eyes are used, "
                 "which won't line up with the imported sockets.")
    clothing = [
        n for n in lowered
        if any(h in n for h in CLOTHING_HINTS)
        and not any(b in n for b in BODY_PARTS)
    ]
    if clothing:
        rep.warn("these look like clothing: %s. Clothing must NOT be baked in "
                 "- the tunic/cloak/belt/boots are code-built and fitted over "
                 "the bare body." % ", ".join(sorted(set(clothing))))


def check_animations(gltf, rep):
    anims = gltf.get("animations", [])
    if anims:
        rep.warn("%d animation(s) baked in. Harmless (we drive the skeleton "
                 "ourselves) but it bloats the file - export with Animation "
                 "off." % len(anims))


# --- Driver -----------------------------------------------------------------

def validate(path):
    rep = Report()
    if not os.path.exists(path):
        rep.error("no file at %s\n"
                  "  Generate it with:  blender --background --python "
                  "tools/make_kern_base.py\n"
                  "  See game/assets/models/README.md for the full recipe."
                  % path)
        return rep
    try:
        gltf = load_gltf(path)
    except Exception as exc:  # noqa: BLE001 - report anything the parse hits
        rep.error("could not read %s as glTF: %s" % (path, exc))
        return rep

    size_mb = os.path.getsize(path) / (1024.0 * 1024.0)
    rep.note("file: %s (%.1f MB)" % (os.path.basename(path), size_mb))

    _joints, by_name = check_skin(gltf, rep)
    matched = check_bone_names(by_name, rep) if by_name else {}
    bounds = mesh_bounds(gltf, rep)
    if bounds:
        check_scale(bounds, rep)
    if matched:
        check_tpose(gltf, matched, rep)
    check_meshes(gltf, rep)
    check_animations(gltf, rep)
    return rep


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.join(here, "..", "game", "assets", "models",
                           "kern_base.glb")
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(default)

    rep = validate(path)
    for note in rep.notes:
        print("  .. %s" % note)
    for warning in rep.warnings:
        print("  !! WARN  %s" % warning)
    for err in rep.errors:
        print("  XX ERROR %s" % err)
    print()
    if rep.ok():
        print("PASS - base mesh is usable. kern_base_model.gd will load it "
              "instead of the procedural body.")
        if rep.warnings:
            print("      (%d warning(s) above are worth a look.)"
                  % len(rep.warnings))
        return 0
    print("FAIL - %d error(s). kern_base_model.gd will fall back to the "
          "procedural body." % len(rep.errors))
    return 1


if __name__ == "__main__":
    sys.exit(main())

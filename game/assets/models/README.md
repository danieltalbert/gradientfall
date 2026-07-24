# Character base meshes

This folder holds the one class of asset in Gradientfall that is **not**
generated in code.

## Why this exists (GDD rule change, 2026-07-21)

The project's standing rule is *"all assets generated in code — no downloaded or
purchased assets."* After a long look-dev pass on Kern, Danny judged that pure
procedural geometry plateaus at "soft stylized figure" for a **face** — body
forms generate fine, faces do not — and the bar for the hero is photoreal,
Link-quality. Danny explicitly approved relaxing the rule **for the player
hero's base body mesh only**.

Everything else about Kern stays code-generated: his clothing, cloak, hair,
gear, sword, the arcane hand-mark and latent threads, all shaders, and all
animation. The imported mesh supplies **only the bare body + head geometry**.

## Provenance and licence

`kern_base.glb` is generated locally with **MPFB** (MakeHuman Plugin For
Blender) using MakeHuman's **CC0 system asset pack**.

- Characters generated with MakeHuman/MPFB are released **CC0 1.0** —
  commercial use, modification and redistribution are all permitted, with no
  attribution required.
  <https://static.makehumancommunity.org/makehuman/faq/can_i_sell_models_created_with_makehuman.html>
- The MPFB *add-on code* is GPL, but that licence does not extend to characters
  exported with it.
- Only the bundled **CC0 system assets** are used. Community assets carry their
  own licences and must not be used here without tracking them.

No third-party or copyrighted character model is used, and nothing from Mixamo
(its licence forbids redistributing the raw mesh files).

## Expected file

    kern_base.glb

If this file is absent the game still runs: `kern_visual.gd` falls back to the
fully procedural body, so the main line never breaks.

## Generation spec (what the mesh must be)

| Property | Value |
| --- | --- |
| Subject | Young adult male, neutral face (reshaped toward Kern in code) |
| Height | **1.75 m** |
| Build | Lean athletic — low body fat, moderate musculature |
| Pose | **T-pose** (rest pose exported, no animation) |
| Scale | Metres, **+Y up** |
| Rig | MPFB **GameEngine**, 53 deform bones, no breasts, no IK/control helpers |
| Eyes | **Separate eye meshes** included |
| Clothing | **None** — clothing is code-built and fitted over the body |
| Format | glTF Binary **`.glb`**, single file, skinning on, deform bones only |

The GameEngine rig's bone names (`pelvis`, `spine_01`, `upperarm_l`,
`lowerarm_l`, `hand_l`, `thigh_l`, `calf_l`, `foot_l`, …) are what
`kern_bone_map.gd` maps the procedural animation onto.

## Blender export settings

`File → Export → glTF 2.0`:

- Format: **glTF Binary (.glb)**
- Include: **Selected Objects** (armature + body + eyes)
- Transform: **+Y Up**
- Mesh: **Apply Modifiers**
- Skinning: **on**; *Export deformation bones only*: **on**;
  *Include all bone influences*: **off**
- Animation: **off**; *Use Current Frame*: **off** (so the rest T-pose exports)
- Images: **Automatic / embedded**

Before exporting, bake shape keys and delete MPFB helpers
(`Operations → Basemesh → Bake shapekeys`, then `Delete helpers`) unless facial
morph targets are wanted, in which case keep the required shape keys.

## Godot import

Open **Advanced Import Settings** on the `.glb`, select the `Skeleton3D`,
create a **BoneMap**, and assign **SkeletonProfileHumanoid**. Verify the limb
mappings and the T-pose before saving.

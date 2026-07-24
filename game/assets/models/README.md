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

## How to actually produce it

Making the character is a short click-path; *exporting it correctly* is where
base meshes go wrong. So the export is scripted — do the clicks, then run two
commands.

### 1. Install (one time)

- **Blender** 3.6 LTS or 4.x — <https://www.blender.org/download/>
- **MPFB2** — <https://static.makehumancommunity.org/mpfb.html>
  (download the add-on zip, then in Blender:
  `Edit → Preferences → Add-ons → Install…` → pick the zip → tick it on)

MPFB2 bundles the CC0 system assets; nothing else needs downloading.

### 2. Build the body (~6 clicks, in the MPFB tab of the 3D view sidebar)

1. **New Human** → *From scratch*. Set the macro sliders: **Gender ~0.85**
   (male), **Age ~0.35** (young adult), **Muscle ~0.6**, **Weight ~0.42**,
   **Height** to taste — the export script rescales to exactly 1.75 m anyway.
2. **Eyes** → add the low-poly eyes asset (separate eye meshes are required).
3. **Rig → Add rig → "Game engine"**. This is the important one: it is the
   53-bone `pelvis`/`spine_01`/`upperarm_l` rig that `kern_bone_map.gd` maps
   onto. *Not* Default, CMU or Mixamo.
4. Leave the rest pose as the **T-pose** MPFB creates. Do not pose it.
5. Add **no clothing** — the tunic, cloak, belt, boots and sword are built in
   code and fitted over the bare body.
6. `Operations → Basemesh → Bake shapekeys`, then **Delete helpers**
   (skip the bake only if you want to keep facial morph targets).
7. Save the .blend, e.g. `kern.blend`.

### 3. Export + verify (two commands)

```
blender --background kern.blend --python tools/export_kern_base.py
python tools/check_base_mesh.py
```

`tools/export_kern_base.py` drops MPFB helper geometry, renames meshes so the
loader's eye/teeth/brow hints match, stands the figure on the origin, scales it
to exactly 1.75 m, applies transforms, warns if the pose isn't a T, and writes
`kern_base.glb` with +Y up / skinning on / deform bones only / animation off.

`tools/check_base_mesh.py` then re-reads the .glb and reports PASS or FAIL
against everything on this page — wrong up-axis, centimetre units, an A-pose,
skinning silently off, a non-GameEngine rig, missing eyes, clothing baked in.
It's zero-dependency and it's the same contract `kern_bone_map.gd` enforces at
runtime, so a PASS here means the fitting pass can start.

### Manual export (if you'd rather not use the script)

`File → Export → glTF 2.0` with: Format **glTF Binary (.glb)**; Include
**Selected Objects** (armature + body + eyes); Transform **+Y Up**; Mesh
**Apply Modifiers**; Skinning **on**, *Export deformation bones only* **on**,
*Include all bone influences* **off**; Animation **off**, *Use Current Frame*
**off** (so the rest T-pose exports); Images **Automatic / embedded**. Then
still run `check_base_mesh.py` — it catches the mistakes this list is long
because of.

## Godot import

Open **Advanced Import Settings** on the `.glb`, select the `Skeleton3D`,
create a **BoneMap**, and assign **SkeletonProfileHumanoid**. Verify the limb
mappings and the T-pose before saving.

## Status (2026-07-24, evening)

`kern_base.glb` **EXISTS and validates** (PASS from `tools/check_base_mesh.py`:
53-bone game_engine rig, 19/19 bones mapped, 1.75 m, Y-up, T-pose, separate
eyes + teeth, no clothing). It was generated fully headlessly:

    blender --background --python tools/make_kern_base.py
    blender --background "C:/Users/danny/Documents/kern.blend" --python tools/export_kern_base.py
    python tools/check_base_mesh.py

`tools/make_kern_base.py` drives MPFB 2.0.x's Python service layer directly
(HumanService/TargetService) -- no GUI clicks needed. It needs Blender 5.x with
the MPFB extension enabled and the MakeHuman CC0 system assets extracted into
MPFB's user data (the one manual download; see the recipe above).

The runtime loader confirms: `KernBoneMap: matched 19/19 bones`,
`KernVisual: base mesh loaded (1.75 m)`. What remains is the FITTING PASS in
`kern_visual.gd`: retarget the procedural animation onto the imported skeleton,
skin-tone the imported body (it has no vertex colors, so the skin shader needs
an albedo fallback), retire the procedural head/body overlay, and refit the
code-built gear to the new body.

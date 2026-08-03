# Character & Creature Pipeline

*Authorised by GDD §10, "THE FIGURE SPLIT" amendment (Danny, 2026-08-02).
This doc specifies how every human, NPC, monster and boss in Gradientfall is
authored. It replaces "build the figure out of primitives in GDScript" as the
project's character method.*

**Scope.** Meshes, rigs, skin weights, face shape keys and material maps for
figures. It does **not** touch the procedural animation stack in `src/anim/`,
which stays in code and is the project's strongest asset.

---

## 0. Why this exists

Every figure in the game was assembled from primitive shapes by GDScript at
runtime: 1,607 lines building 8 monsters in `src/combat/enemy_visual.gd`, one
generator dressing 13 villagers in `src/town/npc_visual.gd`, and for Kern an
imported body with code-built garments welded on.

The ceiling this imposes is recorded in this repo, not theorised. The
2026-07-29 devlog entry concludes, after roughly 40 render-assess-fix cycles,
that a **full-length sleeve for Kern is unreachable**: the code-built cloth is
rigidly bound to two bones while the imported body carries MPFB's smooth
multi-bone weights, so under an 86° shoulder fold the deltoid swells past any
clearance that does not also balloon the sleeve off the shoulder entirely.

That is not a bug awaiting a cleverer session. It is the wrong tool, used
well. A `for` loop cannot sculpt a form, paint a weight gradient, or hold a
shape key. The same argument that lifted the code-only rule for *surfaces* on
2026-07-29 applies to *figures* now.

The scale argument seconds it. `docs/WORLDBOOK.md` Part III budgets **80
monsters and 84 NPCs** plus bosses. At the current density — roughly 200 lines
of shape-assembly GDScript per creature — that is ~16,000 lines of code whose
quality ceiling is "primitives glued together."

---

## 1. What makes a figure read as legit

**Sessions must optimise in this order.** It is not the order people assume,
and getting it backwards is how you spend a week on polygons and still ship
something that reads as creepy.

1. **Silhouette and proportion.** Recognisable as a solid black shape at 20 m.
   This is the single highest-value property and it is nearly free — it is a
   design decision, not a rendering cost.
2. **Animation.** A modest mesh that moves beautifully reads as legit; a
   beautiful mesh that moves stiffly reads as broken, or worse, uncanny.
3. **Deformation** — how the mesh bends when the rig moves. Smooth multi-bone
   weights, no collapsing elbows, no candy-wrapper twists at the wrist.
4. **Material and light response.** Photoreal maps, honest roughness, rim
   light.
5. **Polygon and texture density.** Matters least. Always last.

Gradientfall already scores well on (2): the locomotion pass measured foot
slip 147 → 44 mm/m, ground error 60 → 7.4 mm, and backward-knee frames
8182 → 0. The pipeline below exists to bring (1) and (3) up to meet it.

## 1a. The art target, concretely

Stylized figures, photoreal world (GDD §10). What that means in practice:

- **Take from Breath of the Wild:** simple readable forms; exact silhouettes;
  a limited animation set executed perfectly rather than a large one executed
  loosely; secondary motion on hair, cloth and props; expression carried by
  whole-body pose, not face detail alone; broad colour blocking.
- **Take from Assassin's Creed:** modular outfit combinatorics for crowd
  variety, and one shared human rig underneath every human in the game.
- **Do not take from Assassin's Creed:** realistic skin, realistic facial
  proportion, or anatomical detail density. Without photoscans and mocap that
  road ends in the uncanny valley every time.

---

## 2. The pipeline

Blender 5.2 is installed and already drives a headless, scripted path here —
`tools/make_kern_base.py` builds Kern's body through MPFB's service layer with
no GUI. Everything below extends that proven approach.

```bash
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/<script>.py
```

**Authoring stays scripted and reproducible.** A committed `.glb` must always
be regenerable by re-running its script over committed inputs. No
hand-modelling that only exists in someone's session.

| Stage | Tool | Output |
|---|---|---|
| 1. Base form | Blender script (MPFB for humans, creature kit for monsters) | `.blend` in `assets_src/` |
| 2. Sculpt & subdivide | Blender script + sculpt-brush ops | `.blend` |
| 3. UV layout | Blender script (smart-project + seams) | `.blend` |
| 4. Rig | shared human rig, or auto-rig from the creature kit | `.blend` |
| 5. Weights | multi-bone weight painting / transfer from base | `.blend` |
| 6. Face shape keys | Blender script (humans only) | `.blend` |
| 7. Bake maps | high-poly → low-poly normal / AO bake | `.png` in `game/assets/textures/` |
| 8. Export | glTF, **`export_morph: True`** | `.glb` in `game/assets/models/` |
| 9. Verify | `tools/check_base_mesh.py` extended | pass/fail + turnaround renders |

**`export_morph` must be flipped to `True`.** `tools/export_kern_base.py:374`
currently exports with it `False`, which is precisely why Kern has no face rig
and cannot blink.

## 2a. Garments: cut for fit, author for silhouette

*Written 2026-08-03 from the first real run of this pipeline. Both halves of
this section were paid for in renders; do not re-derive them.*

**PROVEN — cut garments from the body's own surface.**
`tools/make_kern_garments.py` duplicates body faces selected by a bone-weight
mask, so the garment inherits the body's exact multi-bone weights. Cloth and
limb are then driven by identical numbers and cannot separate. The full-length
sleeve that ~40 cycles of the old runtime pipeline could not build came out
correct on the first run, along with trousers from ankle to waist and boots
that reach the toes. The technique also replaces the runtime `COVERED_ZONES`
radius bands: covered skin is deleted at author time by the same mask that cut
the garment, so the class of bug where a band deleted Kern's whole arm cannot
occur.

Region masks should be written against **bone groups**, not heights or radii —
a sleeve ends at the wrist because `lowerarm_*` fades into `hand_*` there. Two
supporting passes earned their keep: `relax_boundary` (a weight isoline is
ragged at vertex resolution and renders as a torn collar) and
`flatten_features` (general smoothing converges too slowly on dense clusters,
so nipples read through a shirt and toenails through a boot even at 40+
iterations; MakeHuman tags both with their own vertex groups, so press those in
specifically rather than smoothing the whole garment flat).

**DISPROVEN — a cut garment alone cannot pass the silhouette test.**
A surface offset 10–15 mm from the body has, by construction, the body's
silhouette. Rendered black, the first fully-clothed Kern read as *a naked
person*: no collar, no cuff, no hem, no belt line, no boot top. It passes the
deformation test and fails gate test 1, which section 1 ranks as the single
highest-value property a figure has. **More clearance does not fix this** — it
inflates the figure without adding a garment edge, and past ~20 mm it reads as
a body stocking one size too big. This is a ceiling of the technique, in the
same way the two-bone binding was a ceiling of the old one.

**THEREFORE — every garment needs authored geometry that departs from the
body.** The cut supplies fit and weights; silhouette has to be built:
  - hanging pieces (tunic skirt, cloak, tabard) as **lofted rings** anchored at
    the waist or shoulders, not cut from the body — a skirt cut from the body
    follows two legs and renders as two flaps;
  - **edge features** — collar band, sleeve cuffs, boot cuffs, a hem roll —
    which is what makes cloth read as tailored rather than sprayed on;
  - and, for anything that should hang or fold, Blender's **cloth modifier**
    with the body as a collision object, simulated and applied, then
    weight-transferred back from the body with a DataTransfer modifier. That
    is the production technique for draped cloth and is where fold detail
    comes from.

Until a garment set carries authored silhouette, it is **not** an improvement
over the blocky runtime garments it replaces and must not be wired into the
game: the old clothes are crude but they have a readable outline, and trading
outline for fit is a net regression at gameplay distance.

---

## 3. The shared human rig

**One rig, one topology, for Kern and all 84 NPCs.** This is the AC crowd
approach and it is what makes 84 villagers affordable at a consistent bar.

- The 53-bone `game_engine` rig from MPFB, already mapped by
  `src/player/kern/kern_bone_map.gd`. Do not fork it per character.
- **Body variation** comes from MPFB macro settings and shape keys baked at
  stage 1 — height, build, age, weight — not from separate meshes.
- **Outfits are modular meshes** authored against that one body: tunics,
  aprons, cloaks, boots, hats. Each is weight-transferred from the body, so
  it deforms with it rather than fighting it.
- **Skin-under-clothes deletion** is a *mesh* operation at author time (delete
  the covered faces), not the runtime `COVERED_ZONES` radius band that once
  deleted Kern's entire arm and left his hands floating in space.
- Every NPC's look is then a data row — body macros, outfit part IDs, colours
  — which fits the existing ContentDB-driven approach in `npc_visual.gd`.

## 4. The creature kit

**80 monsters cannot be 80 bespoke efforts.** Build a parts library once:

- **Parts:** body cores (quadruped, biped, avian, serpentine, blob), heads,
  limbs, horns, antlers, wings, tails, fins, plates.
- **Assembly script:** choose parts, position, boolean-union, remesh to a
  clean single surface, then subdivide.
- **Auto-rig:** derive a skeleton from the assembled parts' anatomy tags, so
  the existing `src/anim/creature_animator.gd` gait engine drives it with no
  per-species animation code.
- **Auto-weight:** heat-map weights from the derived skeleton, then smooth.
- **Bake and export.**

A new monster then costs: pick parts → sculpt-adjust the silhouette → export.
That is how you get 80 creatures at a *consistent* bar, and it keeps the
species character in the silhouette where GDD §10 says it belongs.

The eight existing hand-coded species in `enemy_visual.gd` are the reference
for what each should look like — that file becomes a design document, not a
renderer.

## 5. The face rig

Cheapest large win available. Humans get shape keys for:

- **Blink** (the big one — a face that never blinks reads as dead)
- Brow up / down / angry, mouth smile / frown / open, eye squint
- Six to eight expressions total is enough; BOTW does not use more

Driven from code: involuntary blink on a randomised timer, eye darts (small
saccades toward whatever the head-look spring is tracking), and expression
selection from dialogue/emote state.

## 6. Secondary motion

`src/anim/anim_math.gd` already has exact critically-damped `Spring1` and
`Spring3` integrators, and `creature_animator.gd` already uses them for lean,
landing dip and head-look. Extend the same springs to:

- **Hair** — per-card or per-chain spring, driven by head velocity
- **Cloth** — cloak hem, tunic skirt, driven by pelvis velocity
- **Props** — scabbard sway, pouches, Bit's motion trail

Nothing makes a figure read as alive faster per line of code.

---

## 7. The quality gate

**Danny can enforce every one of these without reading code.** A figure is not
done until all five pass.

1. **Silhouette test.** Render the figure in pure black on white. Is it
   instantly recognisable? Could you tell it from the other creatures?
2. **Turnaround.** 8 frames, 360°. Nothing intersects, nothing floats,
   nothing disappears.
3. **Deformation test.** Extreme poses — arm fully raised, deep crouch, head
   turned 90°. No collapsed joints, no skin poking through cloth. *This is the
   test the current Kern fails, and the one the pipeline exists to pass.*
4. **Motion test.** In motion at walk, run and idle. Does it read as alive?
5. **Gameplay-distance test.** Framed at the real over-the-shoulder camera
   distance, in world lighting — **not** a studio close-up. Studio close-ups
   both flatter and mislead; the player never sees that framing.

Renders go in `docs/progress/` and get committed with the work (iron rule 2).

## 8. Build order

1. **Kern first, as the proof.** Full pipeline end to end: body, shared rig,
   proper multi-bone weights, real garments including the sleeve that could
   not be built, face shape keys, hair with secondary motion. If the pipeline
   works, the sleeve problem simply evaporates.
2. **The shared human rig + outfit modules**, then re-body the 13 Bootstrap
   NPCs.
3. **The creature kit**, then the 8 meadow species.
4. **Scale out** through the WORLDBOOK budget, region by region.

Each step lands committed, documented and eyes-verified per GDD §10 before the
next begins. Quality over speed (CLAUDE.md, prime directive).

## 9. Provenance

Anything brought in records source and licence in
`game/assets/models/README.md`, the same way the MPFB base mesh already does.
CC0 texture maps and HDRIs are permitted (GDD §10, 2026-07-29). Purchased or
non-CC0 packs and downloaded *models* remain forbidden — the hero base mesh is
the one standing exception.

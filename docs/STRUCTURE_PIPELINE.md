# Structure & Architecture Pipeline

*Authorised by GDD §10, Amendment 2026-08-03 — **the structure split**. Danny
asked whether houses, structures and "everything that needs design" would be
better built in Blender. They would. This is how.*

Companion to `docs/CHARACTER_PIPELINE.md`, which did the same for figures.

---

## 0. Why this exists

Every building in Bootstrap is assembled from primitives by a GDScript `for`
loop at runtime — `town_building.gd` is 434 lines that emit boxes, prisms and
cylinders. It works, it boots in 74 ms, and it has a hard ceiling:

> **Nobody can ever open one and make it nicer.**

That is the whole argument. Not that Blender has bevels — though it has bevels,
booleans, arrays, solidify, real UV layouts and custom normals, and GDScript has
none of them. The argument is that a `.blend` is a document a human can sit down
with, and a procedural mesh is not. Bootstrap looked, in Danny's words, like
"different coloured lines" looked on the trees: correct, and not designed.

The trees are the proof of where the line falls. In the same week, bark and
foliage got dramatically better **in code** — because bark is *grown*. It comes
from noise and a rule. A cottage does not.

---

## 1. The line

| Authored in Blender (`.glb`) | Generated in code |
|---|---|
| Buildings, cottages, halls, inns, forges | Terrain and height fields |
| Towns, walls, gates, bridges, docks | Grass, flora, foliage, trees |
| Dungeon architecture and set-pieces | Water, clouds, sky, weather |
| Furniture, signage, carts, crates | Particles and VFX |
| Characters, creatures, NPCs (2026-08-02) | **All shaders** |
| Any prop whose shape is a *decision* | **All animation** |

**The deciding question:** *would a human artist opening this file and nudging it
make it better?*

- Yes → Blender. Proportion, asymmetry, silhouette and wear are judgement calls.
- Defined by a rule, a dataset, noise, or instanced in the millions → code. A
  `.glb` cannot be 2.8 million wind-swayed blades, and Blender has nothing to
  offer a height field.

**Shaders never move.** A Blender material is a preview; the game's look lives in
`assets/shaders/`. Export geometry and UVs, not materials.

**Animation never moves.** `src/anim/` is the project's strongest system.

---

## 2. Honest limits, recorded so no session over-claims

An autonomous session **cannot model by hand.** It drives Blender through its
Python API. That is a real step up — genuine modifiers, genuine UVs, a genuine
export path — but it is **not** an artist's eye, and a session that says
otherwise is lying to the next one.

What this pipeline actually produces is a **base**: correctly-scaled,
correctly-jointed, cleanly-unwrapped structures that Danny or any artist can
open and refine. That refinement is the point of moving, not a fallback.

So: **scripted Blender beats scripted GDScript**, and **hand-modelled beats
both**. All three are in this repo's future and the middle one is where sessions
work today.

---

## 3. Real-world scale, non-negotiable

Wrong scale is the single most common reason a game village reads as a toy, and
it is invisible until a character stands next to it. Kern is **1.75 m**. Every
number below is measured against him.

| Element | Real range | Use |
|---|---|---|
| Door opening | 0.80–0.95 × 2.00–2.10 m | **1.95 m** — Kern must clear it with headroom to spare |
| Floor-to-ceiling, ground floor | 2.3–2.7 m | 2.5 m |
| Window sill height | 0.85–1.00 m | 0.9 m |
| Window opening | 0.7–1.1 × 1.0–1.4 m | 0.9 × 1.2 m |
| Step rise / going | 0.17 / 0.28 m | 0.17 / 0.28 m |
| Handrail height | 0.90–1.10 m | 1.0 m |
| Wall thickness, cob/plaster | 0.35–0.60 m | 0.45 m — **thick walls read as old** |
| Roof pitch, thatch | 45–55° | 50° — thatch must shed water or it reads as a hat |
| Roof pitch, tile | 30–40° | 35° |
| Eaves overhang | 0.4–0.8 m | 0.6 m — the shadow line under an eave is free depth |
| Cottage footprint | 6 × 8 m | one or two rooms |
| Hall / inn footprint | 11 × 16 m | |
| Street width, village | 4–6 m | 5 m |
| Market square | 25–40 m across | |

**The rule:** if a measurement is not on this table, look up the real one. Never
invent a building dimension.

---

## 4. Design principles

These are what separate a designed building from an extruded box. They are the
reason this pipeline exists, so they are not optional.

**1. Silhouette first.** A building must be recognisable as a black shape. Test
it: render the massing with no material. If the inn and the forge have the same
outline, one of them is wrong. Chimneys, dormers, porch roofs, tower stubs and
roof pitch do this work; wall colour does not.

**2. Asymmetry is the difference between built and printed.** Real buildings
have an extension nobody planned, a window that does not line up, a door off
centre, a settled corner. **Every structure gets at least one deliberate
irregularity**, and it must be authored, not random — a lean-to on the north
side because that is where the weather comes from.

**3. Read the material in the joint, not the surface.** Timber frame shows its
posts. Cob shows rounded corners and no sharp arris. Stone shows courses and a
heavier plinth at the base. A wall is a *construction*, and the construction is
what the eye reads at 20 m.

**4. Bevel everything.** Nothing in the real world has a zero-radius edge. A
1–3 cm bevel on every hard edge catches a highlight and is single-handedly the
biggest difference between "3D model" and "object". This is the modifier
GDScript could never have.

**5. Wear lives at the bottom and the openings.** Splash-back on the lowest
0.4 m of a wall, worn thresholds, mud at the gate, moss on the north side, sag
in an old ridge line. Uniform wear reads as noise; placed wear reads as history.

**6. Every building is a mass plus attachments, never one box.** Main mass,
roof, then: chimney, porch, lean-to, steps, buttress, sign, shutters, gutter,
water butt, log pile. The attachments are what make the silhouette.

**7. Negative space is architecture.** Yards, gaps between buildings, the way a
lane narrows. A town is the *space between* the buildings; a row of houses at
even spacing is a street of nothing.

**8. Build a kit, not a set of buildings.** Walls, roofs, doors, windows,
chimneys, porches as interchangeable parts on a shared grid. Twenty buildings
from twelve parts beats twelve bespoke buildings, varies more, and can be
extended by anyone.

---

## 5. The kit and the grid

- **Module grid: 1.0 m** in plan, **0.5 m** vertical. Every part snaps to it, so
  pieces from different sessions still fit.
- **Origin convention:** a part's origin sits at the **centre of its footprint
  on the ground plane**, +X east, −Z north (Godot), +Y up. A wall panel's origin
  is at the base of its outer face.
- **Naming:** `kit_<family>_<part>_<variant>` — `kit_cob_wall_2m_a`,
  `kit_thatch_roof_gable_6m`, `kit_shared_door_plank_a`.
- **One `.glb` per family**, all its parts inside as separate objects, so Godot
  imports one file and GDScript picks parts by node name.

---

## 6. Budgets

Generous, per the hardware decree (§10: RTX 5080 class, spend the budget), but
not unbounded — a village is dozens of instances.

| Thing | Triangle budget |
|---|---|
| Wall / roof panel | ≤ 400 |
| Door, window, shutter | ≤ 300 |
| Chimney, porch, small attachment | ≤ 600 |
| A whole assembled cottage | ≤ 6 000 |
| A whole assembled hall or inn | ≤ 14 000 |
| Bootstrap, all structures | ≤ 250 000 |

Collision is **never** the render mesh. Export a separate convex or box proxy
per building, or let GDScript place primitives — a trimesh collider on a bevelled
cottage is a waste of a physics frame.

---

## 7. Export

- **Format `.glb`**, +Y up, −Z forward, **metres, scale 1.0**, apply all
  transforms and all modifiers.
- **Normals:** custom split normals exported. Shade smooth with an auto-smooth
  angle of 30°, sharp edges marked. Flat-shaded architecture is the other half
  of why buildings read as boxes.
- **UVs:** one channel, unwrapped, no overlap, ~2 px/cm at 2k. A second channel
  only if a lightmap is ever baked.
- **Materials:** export a *name* only. The game assigns `assets/shaders/`
  materials by that name. Never rely on a Blender material reaching the game.
- **No cameras, no lights, no armatures** in a structure `.glb`.
- **Commit** the `.glb`, its `.import`, and its `.uid` (project convention).
- **Commit the generating script too**, under `tools/blender/`. The script is
  the source; the `.glb` is a build artifact that happens to be versioned.

---

## 8. Provenance

Every `.glb` gets a line in `game/assets/models/README.md`: what made it, when,
by which script, and its licence (ours, unless noted). Purchased and non-CC0
packs and downloaded models remain forbidden — the hero base mesh is the single
standing exception.

---

## 9. The quality gate

A structure is done when a non-developer can look at four renders and not wince.
Danny enforces this by eye; no session ticks a box on its own say-so.

1. **Doorway shot** — Kern standing in the opening. Head clears the lintel with
   room; the door is plainly wide enough to walk through. If this is wrong,
   nothing else matters.
2. **Silhouette shot** — the building black against the sky. Is it identifiable?
   Does it differ from its neighbour?
3. **Corner shot at 8 m** — do edges catch light (bevels present), do walls read
   as thick, is there wear at the base?
4. **Street shot at 40 m** — does the town read as a *place*, with depth and
   negative space, rather than as objects on a plane?

**Fail conditions, any one of which sends it back:** a door Kern cannot walk
through · zero-radius edges · paper-thin walls · every building the same
silhouette · uniform spacing · no wear · a roof pitch that would not shed water.

---

## 10. Build order

1. `tools/blender/build_town_kit.py` — the Datasedge cob-and-thatch kit.
2. Bootstrap reassembled from it at its corrected size (see §11).
3. The mill, the gate, fences and yard furniture.
4. Then, per region as each is built, a kit in that region's material language —
   Latent Forest builds in living wood, Tensor Desert in mudbrick and stone,
   Backprop Foundry in iron and slag.

Kits are per-region on purpose. One "generic village kit" reused ten times is
how ten regions end up looking like one.

---

## 11. Bootstrap's size — recorded 2026-08-03

Danny: *"I would imagine it should be bigger if the entire map is 100 km."*
Correct, and the measurements agree:

| | Value |
|---|---|
| Bootstrap as built | 12 buildings over ~50 × 47 m |
| Crossing it at a jog (3.6 m/s) | **14 seconds** |
| BOTW Hateno, for reference | ~250–300 m |
| Distance, town centre → millpond | 97 m |
| Distance, town centre → Perceptron Vault | 117 m |

**Decision: Bootstrap grows to ~150 m across, ~24 structures.** That is 3× the
footprint and roughly a minute to cross — a village rather than a courtyard.

**It cannot go further inside the current meadow.** At 150 m the town's edge is
already at the millpond and closing on the Vault; both should stay a walk away.
The true constraint is not the town, it is that the **meadow heart is 480 m**,
sized back when the town was 50 m.

**Follow-on, not done here:** growing the meadow heart from 480 m to ~1.2 km
would allow a Hateno-scale ~250 m Bootstrap with room around it. That also moves
`GradientPeaks.NEAR_Z` (−240, the shared seam with the meadow's north edge) and
re-scatters all flora, so it is its own session with its own verification.

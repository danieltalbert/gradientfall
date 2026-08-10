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

## 6a. How to actually get detail — the method, proven 2026-08-09

*Written after building the Warm Start Inn, the first structure taken to a
finished standard. Sections 4–6 say what a good building has; this says how a
session that cannot see, cannot sculpt and cannot nudge a vertex gets there
anyway. Everything below is a conclusion from a failure that happened.*

### The diagnosis this answers

Danny's verdict on Bootstrap was "the level of detail is just really bad", and
the measurement agreed: every surface in the town was one flat colour on an
unbevelled `BoxMesh`, with no texture, no wear and no asymmetry anywhere. The
useful question was not "how do we model better" but **why does a session
produce that**, and the answer had five parts. Each has a countermeasure.

| Why detail comes out thin | What fixes it |
|---|---|
| Completion is judged as a **checklist** — walls, roof, door, chimney, done | Judge **visual events per square metre**, not parts present |
| **Iteration count is ~1000× too low** — write 400 lines, render once | A build-and-look loop measured in *seconds* (below) |
| Text is a **lossy medium for visual judgement**; every number comes from reasoning, not from seeing | Render after every change and fix what the render says, not what the arithmetic says |
| **Volume pressure** (80 monsters, 24 structures) pushes toward generators, and a generator makes variations of one idea | Take ONE thing to finished first, and treat its cost as the unit |
| **Nothing gates it** — a cream box with a red roof satisfies the brief | The gate in §9, applied at 3 m, not at 30 m |

### 1. Build the loop before the building

`blender -b --python tools/blender/build_<name>.py -- --render C:/dir` builds
the structure **and renders eight authored angles** in about fifteen seconds.
That single command is the most important thing in this pipeline. Detail is
accumulated by iteration; the loop is the iteration.

`bkit.render_views` takes named viewpoints with their own target and lens.
Frame them deliberately — with a 52 mm lens on 16:9 the vertical field is only
~22°, so an eight-metre building needs close to **thirty metres** of standoff,
roughly twice what intuition suggests. Three of the eight are the gate: whole
building three-quarter, eye level at 1.7 m, and conversation range at a door.

`--highlight <part>` paints one material group magenta and everything else
grey. When a stray surface appears in a render, **ask the renderer which part
it is** rather than reasoning about it. Every time that rule was broken on the
inn, the guess was wrong.

### 2. Detail comes from five specific kinds, not from "more"

1. **Unit geometry.** The plinth is stones, the roof is *tiles*, the chimney is
   courses — ~3,700 individual tiles on one roof. This is the single biggest
   change and most of the triangle count. A roof is the largest unbroken
   surface on any building; a flat plane there is what made every Bootstrap
   building read as cardboard.
2. **Real joinery.** Posts, sill, bressumer, wall plate, close studding, curved
   braces meeting where a carpenter would join them, and pegs at the joints.
   The frame is structure, not stripes painted on plaster.
3. **Depth at every opening.** Walls a real 0.28 m thick with openings
   booleaned through, so each window has a reveal that catches a shadow.
4. **Curves.** `bkit.sweep` along `bkit.arc` — corbel brackets, the wrought
   sign bracket. A curve is the clearest signal a person shaped a thing, and it
   is unreachable from an axis-aligned box at any quantity.
5. **Imperfection.** `bkit.jitter` (3–15 mm) and `bkit.sag`. Dead-straight
   geometry reads as new construction; a village centuries old must not.

### 3. Author sub-assemblies in local space

`bkit.stamp_group(bm, matrix, build)` builds at the origin and places with one
transform. Without it a shutter is loose parts whose positions are written in
world space, so opening the leaf rotates each plank about its own centre and
the assembly fans apart — which is exactly how the inn's first shutters came
out. With it, one window description serves eight windows on four elevations,
which is why the side and back can afford the same quality as the front.

### 4. Value separation decides whether it reads

A facade is read at twenty metres as **light panels between dark bones**. Set
the material values for separation in brightness first and hue second. Keep
grime low everywhere except the plinth: at 0.22–0.34 the inn came out visibly
sootier than every building around it, which reads as a different art style
rather than as weathering.

### 5. Surfaces are procedural, and that is deliberate

`assets/shaders/structure.gdshader` generates plaster tooth, oak grain, per-tile
clay variation and per-stone rubble from noise, with the normal perturbed from
the *same* height field that breaks up the albedo — so the light and the colour
agree about where the surface is low, which is most of what sells a material.

No texture files. This project has none anywhere (see `toon.gdshader`), imported
maps would need provenance tracking, and a tiling map visibly repeats on a
nine-metre wall. Noise costs nothing and never seams.

### 6. Failure modes found on the first building, so nobody re-finds them

- **Derive ridge height from the span AT THE WALL**, never from the eaves span.
  One wrong term there produced four separate visible faults: ridge tiles
  floating in the sky, gable infill striping both verges, and barge boards at
  the wrong pitch.
- **A tile's pitch rotation is `-sy * PITCH`.** The other sign stands every tile
  on end as a fin you can see daylight between.
- **Put a solid deck under the tiles**, ~85 mm below them. Plain tiling has a
  7% gap between neighbours and with nothing behind it the roof is a lattice —
  but set the deck too high and it swallows the tiles instead.
- **Drop gable infill ~90 mm clear of the roof plane.** Built flush, sag and
  tile jitter push the plaster through the tiles.
- **Clip repeating patterns to their panel** (`bkit.clip_segment`). Unclipped
  leaded cames threw diagonal bars metres out across the plaster.
- **Check what a camera is standing inside.** Rotated footprints are not the
  box the plot table reads like: the forge is 9 m wide along *Z*, not *X*.
- **A signboard is painted, so shade it as plaster.** Given oak grain, a small
  flat panel reads as basketwork.
- **Sign lettering is sized to the raised panel**, not the board, and painted
  light-on-dark — at twenty metres it survives on value contrast alone.

### 7. What it cost, as a unit for the other 23

One building: **~150,000 triangles** (the entire previous 17-part town kit was
4,484), 12 material groups, ~55 build-and-look iterations across two passes.
It boots in the same frame budget and lights correctly at night. That is the
number to plan against — not the old kit's.

### 8. ROUNDNESS — the second verdict, and the primitives that answer it

*Danny, reviewing the finished v1: "everything you do is geometrically
perfect… there's not a lot of uniqueness or specialness that comes from uneven
shapes or roundness." He was right, and the cause was structural, not taste:
v1 was built entirely from boxes, and a box has eight vertices — `jitter` can
shear one but nothing can ever CURVE one. Roundness cannot be sprinkled on at
the end; it has to be in the primitives.*

`bkit` now carries organic primitives, and the deciding question for every
element is: **did this thing grow, settle, or get made by hand?** If any of
those, it cannot be a straight box:

| Primitive | What it makes | Where it shows |
|---|---|---|
| `grid_box` + `warp` | Subdivided surface, noise-bellied, corner-pinned | Cob walls bulge between their bones |
| `organic_beam` | Rings along a bowed line, waney edges, taper | Every visible timber; no member is die-straight |
| `stone` | Deformed icosphere | Plinth, chimney, quoins — no flat faces, no right angles |
| `lathe` | Surface of revolution, wobbled | Pots, chimney pots, cartwheel, stump stools |
| `Noise3` field | One smooth settle shared by tiles + ridge + verges | The roof undulates as one surface, not per-tile chaos |

And the composition rules found by iterating on the first building:

- **Break the twins.** Two identical dormers read as a copy-paste even when
  everything else is organic. Differ them in width, height, position and
  window; nudge every window a few cm off its grid; stand the door off-centre.
- **Add one landmark round form.** The bread-oven bulge on the back wall does
  more for "a real place" than any amount of jitter — it is a shape a box
  toolkit simply cannot emit, and the eye knows it.
- **Round filler earns its place.** Cartwheel, thrown pots, rope coil, stump
  stools: the yard furniture of a real inn, all revolved forms.
- **Stones stay TUCKED.** Centre them barely proud of the wall plane with
  most of their volume inside, radius across the face capped (~0.24 m), and
  tumble limited to ~20° — the rotation composes before the non-uniform
  scale, so a free tumble stands flat slabs on their rims like menhirs.
- **Smooth angle follows the geometry.** The default 32° auto-smooth is
  tighter than an 11-segment lathe's face angle; round parts pass ~46° or
  they render faceted.

**The boolean lesson, paid for twice:** never cut openings through a merged
shell of overlapping slabs. The exact solver answers self-intersecting input
by silently deleting entire walls — v2's first build lost the whole
ground-floor back wall to one door cut, and the camera saw in the front door
and out through the back of the house. Cut each slab as its own object against
only its own openings, then merge. (And `--highlight` found it in one frame,
after three reasoned guesses were all wrong.)

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

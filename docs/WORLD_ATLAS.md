# Gradientfall — World Atlas & Scale Proposal

**Status: PROPOSAL — pending Danny's sign-off. Not yet a locked GDD pillar.**
Drafted 2026-07-22 (mountains lane). This is the "layout + plan first" deliverable
before any streaming code is written. Nothing here changes the engine yet.

---

## 0. The decision being recorded

Danny set a new target in chat: the world should feel **humongous — an actual
expedition to cross** — scaled to **~100 km across** in the **"Epic Journey"**
model (dense authored region-cores separated by long procedural wilderness;
fast-travel earned, not given). This is a **GDD-pillar-level change** (GDD §7
currently implies handcrafted regions with modest procedural fill and sets *no*
total size). §5 of this doc drafts the amendment for sign-off.

**Scale reality check (why 100 km, not literal Alaska):**

| | Across (edge) | Area | Run across¹ | Note |
|---|---|---|---|---|
| Current built slice (meadow) | 0.48 km | 0.23 km² | ~1 min | vertical-slice prototype |
| BOTW (reference) | ~8 km | ~60 km² | ~18 min | feels endless at this size |
| **This proposal** | **~100 km** | **~10,000 km²** | **~3.7 h** | ~70× Witcher 3 |
| Alaska (literal) | ~1,300 km | ~1.7M km² | ~48 h | ~170× this proposal |

¹ At Kern's run speed 7.5 m/s, straight line, one edge. Touring the whole area is
far more. Mounts + earned fast-travel are therefore **required systems**, not polish.

**Honest consequence of 100 km:** with ~10 authored cores of a few km² each
(~50–120 km² total), **>98% of the map is procedural wilderness** by area. Between
regions is *meant* to feel remote — long, biome-appropriate wilds with scattered
discoveries (the BOTW "wilderness dotted with dense places" model, stretched out).
A denser total map is a smaller map; this is the deliberate trade for "expedition."

---

## 1. The continent of Aligned — layout

A single connected landmass, **ocean on the west**, the corrupted heart on the
**far east**. The player starts on the western temperate coast and the finale is
the far-eastern **Corpus Citadel** — a genuine **west→east crossing** as the
spine of the whole game. The Citadel is tall and central-east enough to be an
**ever-visible landmark** on the eastern horizon (the BOTW-castle trick): you see
your ending from almost everywhere and walk toward it for 40 hours.

Coordinates below are in kilometres on a 0–100 grid (X = east, Y = north). Region
"core" = the dense authored area; the rest is streamed wilds blending between
biomes.

| Region | Tier | Compass | Core center (km) | Core size | Biome | Campaign |
|---|---|---|---|---|---|---|
| **Convolution Coast** | T2 | far W edge | (8, 46) | strip, ~4 km | ocean, shore, islands | Ch.6 |
| **Datasedge Meadows** | T1 | W (inland of coast) | (20, 38) | ~3 km | grassland (START) | Prologue, Ch.2 |
| **Parameter City** | T3* | S of meadow | (29, 18) | ~4 km | capital, downs, river | Ch.2, Ch.8 |
| **Gradient Peaks** | T3 | N of meadow | (26, 66) | range ~28×22 km | mountains | Ch.7 |
| **The Frozen Cache** | T4 | far N (beyond peaks) | (30, 90) | ~4 km | tundra, ice | Ch.4 |
| **Latent Forest** | T2 | E of meadow (center) | (45, 47) | ~5 km | deep woods | Ch.3 |
| **Overfit Swamp** | T3 | S-center (SE of city) | (49, 23) | ~4 km | bog | Ch.3 |
| **Tensor Desert** | T4 | E (rain-shadow of peaks) | (66, 58) | ~6 km | dunes, matrix ruins | Ch.3, Ch.5-adj |
| **Backprop Foundry** | T5 | far NE | (82, 83) | ~4 km | volcano | Ch.5 |
| **Corpus Citadel** | T5 | far E (the heart) | (87, 50) | ~4 km | Grand Library spire | Ch.9 finale |

\* Parameter City is a safe city inside T3 wilds.

**Why this arrangement (geography that earns itself):**
- The four **established** meadow neighbors (already in-engine as border vistas)
  are preserved: **Gradient Peaks N, Latent Forest E, Convolution Coast W, the
  downs → Parameter City S.**
- **Tundra (Frozen Cache) sits north, beyond the peaks** — cold rises with
  latitude and altitude.
- **Desert (Tensor) sits east in the mountains' rain-shadow** — the peaks wring
  out the weather; their lee is arid. Real orography, on-theme.
- **Volcano (Backprop Foundry) is the far-NE corner** — the most remote, highest
  tier, geologically violent edge; the forge you earn your way to.
- **Overfit Swamp** is the low, humid south-center basin below the forest.
- **The Citadel anchors the far east**, opposite the western start: the corruption
  heart you march on. Hallucination Zones (GDD) bloom outward from it by chapter.

**Biome-transition wilds (what the streamer generates between cores):**
meadow→foothills→alpine→tundra (SW→N); meadow→hedge→deep forest→bog (W→SE);
foothills→rain-shadow scrub→dune sea (peaks→E); temperate→ashland→lava field
(center→NE). Each transition is a heightfield+palette blend between the two
neighbors, so crossings read as continuous country, not tiled zones.

---

## 2. The journey (traversal design)

- **Main-quest route** (chapters tour the whole continent, deliberately): Meadow →
  Parameter City (Ch.2) → {Swamp, Desert, Forest} in any order (Ch.3) → Frozen
  Cache (Ch.4) → Backprop Foundry (Ch.5) → Convolution Coast (Ch.6) → Gradient
  Peaks Summit (Ch.7) → Parameter City (Ch.8) → Corpus Citadel (Ch.9). It
  crisscrosses ~200+ km total — the point is that the world is *big enough to
  crisscross*.
- **On foot**: meadow→capital ≈ 21 km ≈ 48 min run. Coast→Citadel ≈ 78 km ≈ 3 h.
  These are *hikes*, by design.
- **Mounts** (Phase 3-ish): the honest answer to 100 km. A horse-equivalent at
  ~2× run speed halves it; still an expedition.
- **Fast-travel: earned, region-to-region.** Unlock a region's waypoint by
  reaching its shrine/town on foot the first time. No free teleport-anywhere —
  distance must keep meaning something or the scale is wasted.
- **Sightline landmarks**: the Citadel spire (E), the Summit of Gradient Peaks
  (N, 900 m per WORLDBOOK), the Foundry's ash plume (NE), Parameter City's castle
  (S). Always something on the horizon to walk toward.

---

## 3. Engine architecture (what 100 km actually requires)

The current "generate one finite mesh at boot" model (meadow_terrain.gd, and my
gradient_peaks.gd) **does not scale past a few km** and must evolve. Required
systems, roughly in dependency order:

1. **Floating origin.** Godot world coordinates are 32-bit floats; physics jitter
   and rendering error become visible past a few km from origin and unusable at
   100 km. Rebase the world around the player (shift everything back to near-origin
   whenever they stray past a threshold). Non-negotiable; everything else assumes it.
2. **Terrain streaming / chunking.** Replace the single boot mesh with a tile grid
   generated on demand around the player (heightfield → mesh + trimesh collision +
   LOD rings), freeing distant tiles. Target: a fixed budget of live tiles
   regardless of world size.
3. **Procedural generation with authored anchors.** A biome/heightfield generator
   for the wilds, into which the 10 region-cores are **stamped** at their atlas
   coordinates (a core "wins" the height/material inside its radius, blended at the
   rim — exactly the seam-blend technique gradient_peaks.gd already uses at the
   meadow edge). Deterministic by world seed.
4. **LOD + imposters** for distant terrain, trees, and the sightline landmarks
   (the Citadel must render from 78 km as a cheap silhouette).
5. **Fast-travel + mounts + a world map/compass UI.**
6. **Save-format work** (SAVE_VERSION bump + migration): streamed-world state,
   discovered waypoints, per-region flags. Per iron rule 5.

**Reuse — the current work is the template, not throwaway:**
- `get_height(x,z)` as the single source of truth (mesh, collision, scatter all
  sample it) is **exactly** a chunk generator's contract. gradient_peaks.gd and
  meadow_terrain.gd become **region-core stampers** the streamer calls per tile.
- The seam-blend (`_seam_height`, SEAM_BLEND_DEPTH) that marries the peaks to the
  meadow is the same operation that will blend every core into the wilds.
- The mountain/terrain shaders, boulder/tree scatter, and vertex-color banding all
  carry over unchanged.

**Suggested milestone staging (a new Phase-2 foundation track):**
- **M1 — Floating origin + chunk streaming** of one procedural biome (grassland),
  walk 10 km with no jitter/seams, stable tile budget. *Proves the tech.*
- **M2 — Region-core stamping**: drop the existing meadow + Gradient Peaks cores
  into the streamed world at their atlas coords, blended into wilds.
- **M3 — Biome generator** for all transition types + the remaining 8 cores as
  terrain-only stubs (no content yet), placed per the atlas.
- **M4 — Traversal**: mounts, earned fast-travel, world-map UI, LOD landmarks.
- **M5 — Save/load** for the streamed world.
Then Phase-2 region content (per WORLDBOOK) seeds into each core as it's built.

---

## 4. Risks & honest unknowns

- **This is a foundation project, not a setting.** M1–M5 are substantial; expect
  it to dominate a phase. It leaps ahead of the unfinished Phase-1 vertical slice
  (town, quests, dungeon, save/load) — a real sequencing choice for Danny.
- **Performance at scale** (5080-class target helps, but streaming/LOD tuning is
  real work; procedural wilds must stay cheap over 10,000 km²).
- **Emptiness is the enemy.** The design must keep wilds *interesting* (weather,
  discoveries, monster ambushes, vistas) or 100 km becomes a walking simulator.
  Density-per-km of discoveries is the number to protect.
- **Cross-lane impact**: floating origin + streaming touch every system that reads
  world position (grass, combat, Bit, spawner). This is not a mountains-lane-only
  change; it needs coordination across all lanes.

---

## 5. Proposed GDD amendment (for §7, pending sign-off)

> **World scale (added 2026-07-22, Danny-approved):** The continent of Aligned is
> ~100 km across (~10,000 km²), built as **dense authored region-cores in a
> streamed procedural wilderness** ("Epic Journey" model). Crossing it is an
> intended multi-hour expedition; mounts and *earned*, region-to-region
> fast-travel are core systems. This supersedes any assumption of a small,
> fully-handcrafted map. The pillar "a smaller dense world beats a bigger empty
> one" still governs *within* each region-core and the discovery-density of the
> wilds — big is earned by density-per-landmark, not raw area.

---

## 6. Open questions for Danny

1. **Sequencing**: start the streaming foundation now, or finish the Phase-1
   meadow slice (town/quests/dungeon/save) first, then pivot?
2. **Citadel placement**: far-east "ever-visible ending" (this draft) vs. dead-center
   "corruption heart you spiral around"?
3. **Fast-travel generosity**: strict earned-waypoints (this draft) vs. more
   forgiving, given 100 km is a lot to re-cross.
4. **Mounts**: in-scope for the scale foundation, or a later Phase-3 add?

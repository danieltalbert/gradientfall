# Gradientfall — World Map & Placement Book

**Status: WORKING PLAN.** Drafted 2026-08-03 (map lane). This is the layer the
project was missing: `WORLD_ATLAS.md` says *which region sits where*, and
`WORLDBOOK.md` says *what is in each region* — neither says **where inside a
region anything stands**. Nothing could be built on ground nobody had placed.
This book places it.

**Authority:** `GDD.md` pillars → `WORLD_ATLAS.md` (approved layout & scale,
Danny 2026-07-24) → `WORLDBOOK.md` (region contents) → **this book** (positions)
→ briefs. Where this book invents something, §7 lists it explicitly so Danny can
veto a single line without re-reading the whole thing.

**Danny's calls recorded here:** *nest, not stretch* (2026-08-03, chat) — see §1.
Sequencing question from `WORLD_ATLAS.md` §6.1 answered: **map and terrain
first**, Phase-1 systems after.

---

## 1. The nest rule

`WORLD_ATLAS.md` sizes the Datasedge core at ~3 km and the Gradient Peaks at
28 × 22 km. What is actually built is a 480 m meadow and a 948 × 484 m massif —
6× and ~29× smaller. Two ways to reconcile that; Danny chose the second.

- ~~**Stretch**~~ — regrow the built terrain to atlas size. Rejected: it moves
  everything already placed and liked.
- **Nest** — **built geometry never moves.** It becomes the *dense heart* of its
  core, and the core grows outward around it into the wilds.

Three sizes of thing, used consistently for the rest of this book:

| Term | Size | What it is |
|---|---|---|
| **heart** | ≤ 1 km | built, authored by hand, already exists |
| **core** | 3–6 km | authored density around the heart (atlas core size) |
| **wilds** | everything else | streamed procedural, sparse discoveries |

The single most useful consequence of nesting: **the built massif is not the
Gradient Peaks.** The true range sits 16 km further north at atlas (26, 66). What
Kern climbs out of the meadow is its southern outlier — **the First Ridge** —
and the snow giants `border_vistas.gd` already paints *behind* it are the real
peaks. The code renders that relationship correctly today, by accident of good
instinct. Naming it makes it canon.

---

## 2. Coordinates

### 2.1 Two grids and the bridge between them

- **Atlas grid** — kilometres on a 0–100 square. `X` east, `Y` north. This is
  what `WORLD_ATLAS.md` and the world map screen use.
- **Region-local** — metres, Godot convention: `+X` east, **`−Z` north**, `+Y`
  up. Each region's local origin is pinned to its atlas core centre.

```
atlas_km.x = core_km.x + local.x / 1000.0
atlas_km.y = core_km.y - local.z / 1000.0     # -Z is north, so it flips
local.x    = (atlas_km.x - core_km.x) * 1000.0
local.z    = (core_km.y - atlas_km.y) * 1000.0
```

The `-Z` flip is the one that will bite somebody at 2 a.m. It is flipped because
Godot's forward is `-Z` and the whole codebase already treats north as `-Z`
(`gradient_peaks.gd` says so in its header). `world_atlas.gd` implements both
directions so nobody hand-rolls it twice.

### 2.2 Altitude

**Sea level = world Y −14 m.** This number is not invented to be tidy — it is
reverse-derived so that every altitude already in the code becomes a true
elevation with nothing changed:

| Already in code | World Y | → m ASL |
|---|---|---|
| Millpond surface (`water_level`) | −4.47 | **9.5** — an inland pond above the sea ✓ |
| Meadow field, typical | 0 … +12 | 14 … 26 |
| Meadow west edge (the 9 m fall toward the coast) | ≈ −9 | 5 — shelving to a shore just past the box ✓ |
| North seam (`GradientPeaks.SEAM_REF`) | +24 | **38** |
| Built massif ceiling (`GradientPeaks.HIGH_REF`) | +520 | **534** |
| WORLDBOOK's Summit of Gradient Peaks | +886 | **900** ✓ matches the book |

That last row is the proof the nest works: the built massif tops out at 534 m,
the true Summit is 900 m, and they are 16 km apart. A spur and its mountain.

**Elevation bands** (m ASL) used across the continent:

| Band | Range | Where |
|---|---|---|
| Sea & tideflat | −20 … 4 | Convolution Coast, Window Flats |
| Coastal plain | 4 … 40 | west Datasedge, Strideport |
| Meadow & downs | 14 … 90 | Datasedge, the road to the capital |
| Basin (low!) | 8 … 24 | Overfit Swamp — the bog is *below* the meadow |
| Forest floor | 60 … 160 | Latent Forest |
| Desert floor | 40 … 130 | Tensor Desert (Colossus basin dips to 28) |
| Foothills | 160 … 420 | between meadow and the true peaks |
| First Ridge | 38 … 534 | **built** |
| High range | 420 … 900 | Gradient Peaks; Summit 900 |
| Ice plateau | 300 … 560 | Frozen Cache |
| Caldera | 240 (floor) … 640 (rim) | Backprop Foundry |
| The Stacks | 60 … 700 | Corpus Citadel, spire at 700 |

### 2.3 The coastline

**The outline on the existing map artifact does not survive contact with its own
coordinates.** Fitting the drawing's axis labels back to kilometres puts its west
coast at about x = 18 where the atlas puts Convolution Coast's core at x = 8 —
which would leave Strideport, a *harbour town*, ten kilometres out to open sea.
The drawing was a sketch; the coordinates are the approved thing. So the
coastline is re-authored here to fit them, and the artifact gets redrawn from
this list rather than the reverse.

Vertices, clockwise from the southwest corner (km):

```
west   (16,4) (13,12) (11,20) (10,28) (9.6,36) (9.2,44) (10.5,52)
       (12,60) (15,68) (19,76) (24,84) (30,92)
north  (40,94) (52,95) (64,93) (74,90) (82,88) (89,84)
east   (93,76) (95,66) (95.5,56) (94,46) (91,36) (87,27) (81,19) (73,12)
south  (62,7) (50,4) (38,3) (28,3) (21,3)  → closes to (16,4)
```

Sanity checks the old outline failed and this one passes: Strideport (8.6, 46.2)
sits in a bay just off a coast running through x ≈ 9.2 — a harbour ✓ · the Ledger
reaches the sea at (13, 14) exactly where the west coast runs ✓ · Frozen Cache
(30, 90) is 2 km in from a northern tundra shore ✓ · Backprop Foundry (82, 83)
is 5 km in from the northeast ✓ · Corpus Citadel (87, 50) is 7 km in from the
east coast, close enough for its spire to be the last thing you see leaving by
sea ✓ · Parameter City (29, 18) sits 15 km up the Ledger from the south coast,
which is exactly how a capital gets rich.

---

## 3. The waters

Six named waterways. Each earns its name from its region's idea — the map
teaches before a single line of dialogue does.

| Name | From → to | Reaches the sea? | The idea |
|---|---|---|---|
| **The Throughline** | west flank of Gradient Peaks (20.5, 71) → E across the continent → eastern sea at (94, 46) | yes | **The one river that crosses the whole world** (Danny, 2026-08-03). 74 km of an 86 km-wide landmass — as near end-to-end as water manages, since a river cannot begin in the ocean. |
| **The Descent** | Peaks cirques (26, 62) → SW across Datasedge → sea at (10, 44) | yes | Water always takes the steepest path down. The continent's main river, and the one Kern grows up beside. |
| **The Ledger** | southern downs (34, 26) → W through Parameter City → sea (13, 14) | yes | The capital runs on weights and measures; its river keeps the accounts. |
| **The Slow** | Latent Forest south edge (47, 38) → S into Overfit Swamp | **no** — it spreads and repeats | It memorised one bend and made a hundred of it. Oxbows all identical. |
| **The Vanishing** | Peaks east flank (38, 60) → E toward Tensor Desert | **no** — dies in sand ~8 km short | It gets weaker the further it travels from its source and arrives as nothing. The dry channel it leaves is what the Rune Rows are built along. |
| **The Emberflow** | Slagfields (80, 80) → **uphill** to the Great Forge (83, 85) | no | Canon (WORLDBOOK §7): error-flame runs backward, from the failure back to every furnace that contributed. |
| **The Stillwater** | Frozen Cache, (28, 88) → (33, 92) | frozen | A river stopped mid-flow, a standing wave caught in the act. Everything here is preserved exactly as it was left. |

### The divide, and the two channels

Adding the Throughline makes **Gradient Peaks a real continental divide**: the
Descent runs west off the range to the western ocean, the Throughline runs east
off the same range to the eastern one. That is how mountain ranges actually
behave, and it costs nothing to have been true.

It also does something better. The Throughline shares its corridor with **the
Vanishing**, which dries up in the sand a few kilometres short of anywhere. Two
channels running side by side across the same desert — one carrying the whole
way, one fading to nothing — is the vanishing-gradient lesson lying on the
ground where the player walks over it. Nobody has to explain it. You can stand
in the dry bed of one and hear the other.

Elevation along the Throughline descends monotonically: 700 m at the source,
470 at (31, 67), 260 at (41, 63), 140 at (54, 60), 90 crossing Tensor Desert at
Axis Bazaar, 35 passing the Corpus Citadel, sea at (94, 46). Water only ever
runs downhill on this map, which the audit will start checking once the terrain
carries real heights.

**The Descent through Datasedge** (this stretch is buildable now): enters the
core at atlas (20.5, 39.1), runs SW, is tapped by a **leat** that drives the
Mill's wheel and fills the millpond at local (95, 10), then leaves the built box
westward around atlas (19.7, 37.9) and falls to the sea. The millpond is a
*widening on a leat*, not a closed pond — which is why it has a current, why the
mill works, and why Bit calls it "a LOT of water."

---

## 4. The roads

Roads are how a 100 km world stops being a walking simulator: they give the eye
a line to follow and the wilds a reason to have edges.

| Road | Route | Note |
|---|---|---|
| **The Great East Road** | Strideport (8,46) → Bootstrap (20,38) → Latent Forest (45,47) → Tensor Desert (66,58) → Corpus Citadel (87,50) | The spine. 80 km. You can see your ending down it from almost anywhere — walk it for forty hours. |
| **The Capital Way** | Bootstrap (20,38) → Parameter City (29,18) | 21 km, ~48 min on foot. Chapter 2's road. |
| **The Cold Stair** | Descent's Rest (26,66) → over the Saddle → Coldstore (30,90) | Cut steps, not a road. Closes in storms. |
| **The Cinder Track** | Great East Road at (74,62) → Emberworks (82,83) | Slag-ballasted; warm underfoot the last 3 km. |
| **The Bog Causeway** | Parameter City (29,18) → Mirrormoor (49,23) | Planks on stilts. Identical planks. You will count them. |
| **The Old Boundary Line** | Datasedge, NE→SW through the Old Boundary Stones at local (58, −74) | **A road that is no longer a road.** See §7. |

### The Old Boundary Line

The Old Boundary Stones already exist in `meadow_landmarks.gd`, and Bit already
says of them: *"They mark a line nobody can see anymore, and the farmers plow
around them without asking why."* This book makes that line a **disused road** —
a straight NE–SW ghost through the meadow, still readable as a shallow ridge in
the grass and a row of stones, running from nothing to nothing. It is older than
Bootstrap. Following it to either end pays off with a view, not a chest.

That is not new invention; it is existing canon given a shape. It also gives the
terrain generator its first *authored linear feature*, which is a different and
harder thing than a blob, and worth having early.

---

## 5. The Deep — where Kern may swim, and where the sea says no

**Rule:** Kern can swim anywhere. Open water outside a named **safe water** zone
is *the Deep*: it drains hearts on a slow timer, the screen edge goes cold, and
Bit — who is canonically afraid of deep water — gets loud about it. It is not a
wall and it is not instant death. It is the sea declining to be crossed, and a
strong swimmer with full hearts can still reach something they can see.

This satisfies the GDD's "no hard gates" pillar honestly: the ocean is a *soft*
gate made of danger and cleverness, exactly like a high-tier monster.

**Safe water** (no drain):

| Zone | Where | Why |
|---|---|---|
| Convolution Coast shelf | the whole western shore out to 3 km, atlas X ≥ 5 | it is a fishing region; the sea is the content |
| The three Coast islands | (5.5, 48), (6.8, 44.5), (7.4, 41.2) | authored destinations, per the map |
| The Kernel Reef | (6.2, 45.4) | the region's dungeon is underwater by design |
| Window Flats | (9.5, 43) … (11, 49) | the tide-walk zone; being in water is the mechanic |
| The Old Millpond | Datasedge local (95, 10), r 24 | already has `MeadowTerrain.is_deep_water()` waiting for it |
| The Descent, any stretch | the river's channel | rivers are for crossing |
| The Ledger, in the capital | (27, 18) … (31, 18) | city canal; there are steps out |

Everything else that is water is the Deep. The zone list lives in
`world_atlas.gd` as data — adding safe water later is one line, never a code
change.

---

## 6. Region placement

Every named site in `WORLDBOOK.md`, given a position. Coordinates are atlas km
to 3 decimals (1 m precision). **Bold** rows are *built and standing today* —
their positions are read out of the code, not chosen here, and must not move.

Elevations are m ASL. For built sites the elevation is whatever
`get_height()` returns and is marked *as built*.

### 6.1 Datasedge Meadows — core (20, 38), 3 km · T1 · START

Local origin = atlas (20.000, 38.000). Built heart = the 480 m box, atlas
19.760–20.240 × 37.760–38.240.

| Site | Kind | Local (x, z) m | Atlas km | Elev |
|---|---|---|---|---|
| **Bootstrap** | town | (0, 30) | (20.000, 37.970) | *as built* |
| **The Mill** | building | (78.4, 4.0) | (20.078, 37.996) | *as built* |
| **The Old Millpond** | water, r 24 | (95, 10) | (20.095, 37.990) | 9.5 |
| **Seed Vault ruins** | ruin | (−72, −70) | (19.928, 38.070) | *as built* |
| **Whispering Well** | POI | (46, 24) | (20.046, 37.976) | *as built* |
| **Old Boundary Stones** | POI | (58, −74) | (20.058, 38.074) | *as built* |
| **Hivewise Apiary** | POI | (70, −14) | (20.070, 38.014) | *as built* |
| **The Perceptron Vault** | dungeon | (64, 128) | (20.064, 37.872) | *as built*, floor 0.26 |
| **The Iris flats** | flora field | ≈ (−42, −82) | (19.958, 38.082) | *as built* |
| *Shrine of First Light* | **shrine 1** | (152, 58) | (20.152, 37.942) | ~20 |
| *Sunrow Fields* | hamlet | (−620, 340) | (19.380, 37.660) | 22 |
| *Wheelwright's Cross* | road junction | (410, −180) | (20.410, 38.180) | 31 |
| *The Thresher's cut lines* | world boss | (−980, −420) | (19.020, 38.420) | 44 |
| *The First Ridge gate-valley* | pass | (0, −300) | (20.000, 38.300) | 38 → 172 |

**Shrine of First Light** was the one Datasedge site `WORLDBOOK.md` names and
nobody had ever placed. It goes **east of the millpond, on the rise**, inside the
built box — so it can be constructed in the very next terrain session without
touching the streamer. East is not decoration: the prologue ends here, the shrine
faces the sunrise, and the player's first walk with a purpose is toward first
light. Kern wakes in ruins in the northwest and walks east into the morning.

### 6.2 Gradient Peaks — core (26, 66), 28 × 22 km · T3

The true range. The First Ridge (§6.1) is its far southern outlier, 16 km away.

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| Descent's Rest | town | (24.2, 62.8) | 430 |
| The Momentum Mines | dungeon | (27.6, 65.1) | 520 |
| The Saddle | pass | (25.9, 67.4) | 690 |
| Overshoot Ledge | POI / vista | (28.4, 68.0) | 745 |
| **The Summit** (Ninth Engineer's hermitage) | landmark | (26.5, 71.2) | **900** |
| Shrine of the Summit | **shrine 8** | (26.6, 70.6) | 858 |
| The Gradient Wyrm's plateau | world boss | (22.8, 69.3) | 604 |
| The Avalanche Choir corrie | world boss (night/storm) | (29.7, 70.1) | 712 |
| *Cirque of the Descent* | river head | (26.0, 62.0) | 540 |

The built massif's five reserved pads (`gradient_peaks.gd` — a saddle, an
overlook ledge, a summit shoulder, two benches) belong to the **First Ridge**,
not to these. They are named in §6.1's gate-valley entry and stay unclaimed for
Datasedge-tier content.

### 6.3 The Frozen Cache — core (30, 90), 4 km · T4

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| Coldstore | town | (29.4, 89.3) | 372 |
| The Cache Depths | dungeon | (31.1, 90.8) | 340 (entrance) |
| Aurora Fields | POI | (32.6, 92.2) | 410 |
| The Ninety-Year Post Office | POI | (28.9, 88.6) | 366 |
| Preservation Vaults | POI | (30.7, 88.1) | 388 |
| Shrine of the Second Voice | **shrine 4** | (31.8, 91.6) | 402 |
| Aurora Leviathan's sky-lane | world boss | (32.4, 92.0) | *airborne*, 460 |
| *The Stillwater* | frozen river | (28, 88) → (33, 92) | 356 |

### 6.4 Latent Forest — core (45, 47), 5 km · T2

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| Embedding Hollow | town (inside one tree) | (44.3, 46.4) | 108 |
| The Autoencoder Grove | dungeon | (46.2, 48.1) | 96 |
| The Thin Places | ability-gated vaults | (43.1, 48.6), (46.9, 45.2), (44.8, 49.4) | 112 |
| Canopy Post | POI | (45.6, 45.1) | 134 |
| Mosslight Vale | POI | (43.6, 44.8) | 84 |
| Shrine of Deep Roots | **shrine 3** | (44.9, 47.9) | 92 |
| The Feature Stag's range | world boss | (46.8, 46.7) | 120 |

The three Thin Places are given three coordinates on purpose: they are the
Latent Step bonus vaults, and one of the pleasures is realising they are the
*same* vault reached three ways.

### 6.5 Overfit Swamp — core (49, 23), 4 km · T3

The bog is a **basin** — the only region that sits lower than the meadow.

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| Mirrormoor | town (stilts) | (48.4, 22.6) | 12 |
| The Memorization Mire | dungeon | (50.1, 23.9) | 9 |
| The Same Ten Clearings | POI ×10 | ring, r 1.2 km about (49.0, 23.0) | 10–14 |
| Grandma Pye's cottage | POI | (47.9, 24.1) | 15 |
| The One Different Tree | POI | (50.8, 21.7) | 11 |
| The Unsupervised Hydra's centroid pools | world boss | (49.6, 21.9) | 8 |
| Hallucination Zone (Ch.3) | zone | about (49.4, 23.6), r 1.1 km | — |

**Overfit Swamp has no Memory Shrine** — it is the only region of the ten
without one. That is not an oversight in `WORLDBOOK.md`; there are nine shrines
and ten regions, and this is the region that gets left out. Worth knowing before
somebody "fixes" it: a region with nothing of Kern's past in it is the right
place for a bog that remembers everything else far too well.

The Same Ten Clearings are placed as a **ring of ten at equal spacing** — so a
player crossing the bog in a straight line hits them in a repeating rhythm and
feels the joke in their feet before anyone explains it.

### 6.6 Tensor Desert — core (66, 58), 6 km · T4

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| Axis Bazaar | town (grid streets) | (65.2, 57.4) | 96 |
| The Matrix Necropolis | dungeon | (67.4, 59.2) | 78 |
| The Sand-Sunk Library | POI / Ch.3 | (64.1, 59.6) | 62 |
| Rune Rows | door fields | along the Vanishing's dead channel, (61,58.6)→(66,58.1) | 70–110 |
| The Idle Colossus's basin | world boss | (68.1, 56.6) | **28** |
| Shrine of the Broken Scale | **shrine 5** | (66.8, 58.8) | 84 |
| Hallucination Zone (Ch.3) | zone | about (64.6, 58.9), r 1.3 km | — |
| *Ashfall Turn* | waystation | (74.0, 62.0) | 140 |

**Ashfall Turn** exists because the audit (§9) refused to let the Cinder Track
branch off the Great East Road at an anonymous point on the map. It is the last
waystation before the volcano road, and it is where the ash starts.

Rune Rows follow the dead river. A door-field strung along a channel that once
carried water and now carries nothing is the region's whole lesson, standing up.

### 6.7 Backprop Foundry — core (82, 83), 4 km · T5

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| Emberworks | town (caldera) | (81.6, 82.4) | 386 |
| The Chain Rule Works | dungeon | (83.1, 84.2) | 302 |
| The Slagfields | POI | (80.2, 80.9) | 244 |
| Skip-Pipe Junctions | POI ×4 | (81.0,81.8) (81.9,83.0) (82.6,83.9) (83.4,84.8) | 260–330 |
| The Hundred Failures Gallery | POI | (81.9, 82.9) | 392 |
| Shrine of Embers | **shrine 6** | (82.8, 83.6) | 348 |
| Slagheart Colossus arena | world boss | (80.6, 81.4) | 250 |
| The Archivist (duel #1) | lieutenant | (83.1, 84.2) — inside the Works | — |
| *Caldera rim* | landmark | ring r 2.1 km about (82, 83) | 640 |

The four Skip-Pipe Junctions are placed **in a line that skips one** — junction 2
and junction 4 connect directly, over the top of 3. You can see the pipe do it.

### 6.8 Convolution Coast — core (8, 46), ~4 km strip · T2

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| Strideport | town (harbour) | (9.6, 46.3) | 8 |
| The Kernel Reef | dungeon (submerged) | (6.2, 45.4) | −18 |
| The Unsinkable | ghost ship, world boss | (5.9, 47.8) | *afloat* |
| Window Flats | tide-walk | (9.3, 46.0) | −2 … 3 |
| Lighthouse Point | POI | (10.1, 48.9) | 46 |
| Shrine of the Tide | **shrine 7** | (7.1, 44.3) | 22 |
| *Longstride* | island | (5.5, 48.0) | 14 |
| *Halfstride* | island | (6.8, 44.5) | 9 |
| *The Padding* | island | (7.4, 41.2) | 6 |

**Strideport does not sit on its own region's core centre**, and that is
deliberate. Convolution Coast's core (8, 46) is 1.5 km offshore, because for this
region the water *is* the content. But a harbour town needs a harbour, which
needs land, so Strideport sits on the shoreline at (9.6, 46.3). Lighthouse Point
is a headland and gets the same treatment. The Kernel Reef, the Unsinkable, the
three islands and the Shrine of the Tide are all genuinely out in the water, on
purpose — the Shrine of the Tide is a tidal rock, reachable only in the window.

The three islands were already drawn on the map artifact and never named. They
are named for the convolution the region teaches: a full stride, a half stride,
and the padding at the edge where the window runs out of shore. **The Padding** is
mostly not there — a sandbar that is only an island at low tide.

### 6.9 Parameter City — core (29, 18), 4 km · T3 (safe city)

| District / site | Kind | Atlas km | Elev |
|---|---|---|---|
| Castle Normhold | landmark | (29.0, 18.6) | 96 |
| Weights & Measures | district (market) | (28.5, 18.1) | 74 |
| The Regularizer's Court | district | (29.4, 18.2) | 78 |
| Feature Quarter | district (crafts) | (28.7, 17.5) | 70 |
| The Dropout District | district | (29.7, 17.4) | 66 |
| Homestead Terraces | player land | (30.2, 18.8) | 84 |
| Shrine of the Ledger | **shrine 2** | (29.1, 19.1) | 88 |
| The Undercroft of Unused Parameters | dungeon | beneath (29.0, 18.6) | 40 |
| The Unregularized | world boss (outskirts) | (31.4, 16.9) | 58 |

The Undercroft is *directly under the castle*. It is the catacomb of everything
history pruned, and it sits under the throne that did the pruning.

### 6.10 Corpus Citadel — core (87, 50), 4 km · T5

| Site | Kind | Atlas km | Elev |
|---|---|---|---|
| The Index Gate | sealed door — **the game's one hard gate** | (86.8, 50.0) | 120 |
| The Stacks Gardens | refugee camp | (86.1, 49.4) | 96 |
| Corrupted Scriptoria | POI ×3 | (85.8,50.8) (87.2,51.4) (86.4,48.6) | 104–150 |
| Shrine of the First Question | **shrine 9** | (86.9, 49.2) | 112 |
| The Margin Paths | high-tier exploration | rim, r 1.6 km about (87, 50) | 180–420 |
| The Infinite Stacks | final dungeon | within (87.0, 50.2) | 60 … 700 |
| The spire | ever-visible landmark | (87.0, 50.2) | **700** |

The spire at 700 m, 67 km east of Bootstrap, is what the whole map is arranged
around. From the meadow it is roughly 0.6° of arc above the horizon — small, but
never absent. The LOD imposter that draws it from 67 km is `WORLD_ATLAS.md`'s
milestone M4, and it is the single most important object in the render budget.

---

## 7. What is canon, what this book invented

Danny can veto any line in the right column without touching the left.

**Straight from the approved documents — not invented here:**
region coordinates, core sizes, biomes, tiers, chapter assignments (all
`WORLD_ATLAS.md`) · every site *name*, town, dungeon, boss, shrine ability and
revelation, quest chain, material and dataset (all `WORLDBOOK.md`) · the
continent outline, the three island positions, the campaign route (the existing
map artifact) · every **bold** coordinate in §6 (read out of the code).

**Authored by this book — new decisions:**

1. **Sea level = −14 m world Y** (§2.2) — derived to make existing numbers true, but it is a choice.
2. **The First Ridge** — naming the built massif as a southern outlier rather than the range itself (§1).
3. **Six named waterways** (§3) — names, routes, and the idea that the Vanishing dies in the sand and the Slow never reaches the sea.
4. **Six roads** (§4), including reinterpreting the Old Boundary Stones' invisible line as a disused road.
5. **The Deep** and its safe-water list (§5).
6. **Every non-bold coordinate in §6** — ~55 site placements.
7. **New minor place names:** Sunrow Fields, Wheelwright's Cross, Cirque of the Descent, Longstride, Halfstride, The Padding.
8. **Shrine of First Light placed east of the millpond** (§6.1) — the prologue's
   walk goes toward the sunrise. This is the most load-bearing single invention
   in the book, because it is the only one buildable this week.

**Still open, needs Danny:**

- `WORLD_ATLAS.md` §6.3 — fast-travel generosity (strict earned waypoints vs. forgiving).
- `WORLD_ATLAS.md` §6.4 — mounts in the scale foundation, or Phase 3.
- May the project bring in a **CC0 font**? The asset amendment covers texture maps, HDRI and hair cards; it says nothing about typefaces, so none has been added. The map UI is using Godot's built-in until answered.

---

## 8. How this book gets used

- **`game/src/world/world_atlas.gd`** encodes every number here as typed
  constants. The world map screen, the minimap, the swim rule and every future
  terrain stamper read that one file. If this document and that file ever
  disagree, the file is wrong and this document is the fix.
- **Terrain sessions** take one region, read its §6 table, and build the core
  around the heart. Datasedge is the only region with a heart today.
- **Content briefs** draw POI positions from §6 — but note the POI schema
  (`content/schemas/poi.schema.json`) currently has **no position field at all**
  and `additionalProperties: false`, so an approved POI physically cannot carry a
  location. Adding an optional `position` is a content-pipeline change under
  iron rule 5 and is the next thing blocking the 275-POI budget.

---

## 9. The audit

```
godot --headless --script res://src/dev/atlas_audit.gd
```

`game/src/dev/atlas_audit.gd` checks the continent's geometry by machine —
**367 assertions, currently all passing.** A map is a heap of individually
plausible numbers, and every mistake in one is the kind a human only catches by
staring at a drawing for an hour. So it does not get caught by staring.

It verifies: the km↔metre bridge round-trips and north really does increase
atlas `y` · site ids are unique and name real regions · everything that needs
ground has ground, and everything meant to be at sea is at sea · region cores are
on land (Convolution Coast excepted, deliberately) and fit inside the atlas
square · rivers that claim the sea reach it and rivers that die inland do ·
roads terminate at named places · there are nine shrines, one per region, none in
Overfit Swamp · safe water is water · and the Deep drains a three-heart Kern in
25–60 seconds.

**Four real errors on its first run, all fixed above:**

1. **Strideport was 1 km out to open sea.** The harbour town had been placed on
   its region's core centre, and that centre is offshore. Lighthouse Point and
   Window Flats were wrong the same way.
2. **The Aurora Leviathan's sky-lane had drifted out over the northern ocean**,
   away from the aurora it swims in.
3. **The Stillwater was classified as a river that dies inland** — it does not.
   It runs to the shore and is stopped solid the whole way. "Reaches the sea" and
   "dies inland" were not enough states for a frozen river; it now has its own.
4. **The Cinder Track branched off the Great East Road at an anonymous point.**
   Rather than relax the check, the junction got a name: **Ashfall Turn**.

That last one is the argument for having the audit at all. A machine complaining
about a loose end is what put a waystation on the volcano road.

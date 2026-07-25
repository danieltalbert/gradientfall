# Gradientfall Devlog

*Newest entry first. Every session appends: DONE / HALF-FORMED / NEXT UP.*

---

## 2026-07-25 (session, **Godot 4.7.1 running in-sandbox**) — Knowledge charge v1

**THE BIG ONE FIRST — this environment can run Godot.** Every entry below
2026-07-16 says "no Godot here, UNSEEN". That was never true, it was just never
tried: the sandbox's outbound proxy allows GitHub release downloads, so
`Godot_v4.7.1-stable_linux.x86_64` (the same build the live sessions use) drops
straight into a scratch dir and runs. Three verification levels are now open to
any autonomous run, and all three were used on this milestone:
1. `godot --headless --path game --import` — real parse + class-cache pass.
   Catches everything the old hand-rolled smoke-lint could only guess at, and
   it generates the `.uid` files the CLAUDE.md convention wants committed.
2. `godot --headless --path game --fixed-fps 60 res://tests/…tscn` — the game's
   own systems driven for real, exit code 0/1. `--fixed-fps` is load-bearing.
3. `xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720
   --fixed-fps 60 -- --ui-screenshot=DIR` — Mesa llvmpipe renders it in
   software. Slow (~10 s/frame at 720p, so pose in ~30 frames, not 500) and it
   is the **gl_compatibility** renderer, so world lighting is NOT the Forward+
   look — but UI is UI, and screen-space work can finally be looked at.
The binary is NOT committed (110–145 MB); refetch it per session.

**DONE — roadmap milestone 7: Knowledge charge v1 (built, run, and seen)**
New `game/src/knowledge/`: `quiz_bank.gd` (draw policy) and `knowledge_quiz.gd`
(the in-combat director); new `game/src/ui/quiz_card.gd` (the card); new
`game/tests/quiz_selftest.{gd,tscn}`. Wired: `input_setup.gd` (+`quiz_choice_1..4`
on the number row/numpad and the d-pad, +`debug_quiz` on G), `main.gd` (spawns
the director; new `--ui-screenshot=` capture mode), `player_combat.gd` (the
charge payout now reads the question's difficulty), `enemy.gd` (+`is_alive()`).
**`event_bus.gd` was not touched** — Combat v1 had already declared every signal
this needed, which is the boundary working as intended.
- **The loop**: a fight starts → four seconds in, a question rises from the
  bottom of the screen with its answer clock running → 1–4 (or the d-pad,
  clockwise from up) → right answer pays focus, wrong or missed shows the right
  answer *and its explanation* and costs nothing but the charge. Three right
  answers arm the shard-nova; the card says so ("PRESS Q — FOCUS FULL").
- **Deliberate design calls (autonomous, flagged for review):**
  1. **Time does not slow and the world does not pause.** GDD §9 says fights
     happen in-world, in place; a pause would also have meant two owners for
     `Engine.time_scale` (Combat v1's hitstop already owns it).
  2. **Taking a hit dismisses the card** — no penalty, short cooldown. This is
     what makes the charge a *combat* resource: dodge out, make space, then
     answer. It is the one call most likely to want a feel tune.
  3. **A wrong answer costs nothing.** All-ages teaching game: being wrong buys
     you the explanation. A timeout isn't even scored as an answer (no
     `quiz_answered` emit), so Bit never sasses you for a question you were
     never given the chance to answer.
  4. **Bit is not the asker.** She reacts (her quiz barks already existed and
     fire on the signal), but GDD §6 says she serves no mandatory gameplay
     purpose — routing the mechanic through her would have broken that.
  5. **Charge scales with difficulty** (D1 0.34 → D5 0.58) via a ContentDB
     lookup on the quiz id, so the payout rides the existing two-argument
     signal instead of needing a new one.
  6. **Save shape untouched** again — the asked-question history is
     session-lived, so no `SAVE_VERSION` bump. Persisting it (and a "questions
     answered" stat for the compendium) belongs to the save/load milestone.
- **Progress gating** (WORLDBOOK Part III): D1–2 anywhere, D3 after 3 Memory
  Shrines, D4 after 6, D5 at the endgame. The shrines are a Phase 4 milestone,
  so `QuizBank.SHRINE_FLAGS` declares the nine canonical `GameState` flag ids in
  WORLDBOOK order now — the shrine milestone should set those names, not invent
  new ones. Today that means 17 of the 41 approved questions are reachable in
  the meadow, which the boot log prints.
- **Region affinity**: `REGION_TOPICS` leans the meadow toward `ml_basics` and
  `data` (75/25) — a lean, never a lock, and unmapped regions draw from
  everything.

**DONE — verification (the part that used to say UNSEEN)**
- Clean import in Godot 4.7.1: **0 errors, 0 warnings** across the project.
- Clean boot, 400 frames, no errors; `Knowledge charge v1 online: 17
  question(s) reachable in 'datasedge_meadows' (up to difficulty 2).`
- `res://tests/quiz_selftest.tscn`: **27/27 PASS**. It drives the real
  `player.tscn`, the real approved bank, and the live EventBus through: the
  difficulty gate at 0/3/6/9 shrines, 200 draws (no back-to-back repeat, whole
  pool covered, even distribution), the D1/D5 charge payouts, the clamp at
  full, **the special actually spending the meter**, no-question-without-a-fight,
  the grace beat, offer → answer → charge, wrong answers, timeouts,
  hit-interrupts, and silence while focus is full. Two real bugs died here: the
  engagement check used 3D distance (now horizontal, like `Enemy`'s own aggro),
  and the card kept redrawing while hidden.
- **Screenshots** (`docs/progress/milestone7_*.png`): the question mid-countdown,
  a correct verdict with its explanation, the moment focus tops off, and a wrong
  pick showing both the right answer and the mistake. Rendered in software under
  `gl_compatibility` — the card, hearts and meter are exactly what a player sees;
  the *world* behind them is not the Forward+ look (no TAA/SDFGI/volumetrics,
  and that giant pale sun disc is a compatibility artifact, not a regression).

**HALF-FORMED / for a live session**
- **Feel, not correctness, is what's left.** Nobody has played this. The
  numbers most likely to need a human: `FIRST_OFFER_DELAY` (4 s), the answer
  window (8 s at D1 → 14 s at D5), the cooldowns (15 s after a right answer),
  and whether the hit-interrupt is tension or annoyance.
- The card is bottom-centre and fairly large at 720p. It reads well in the
  shots, but a real fight is the judge.
- Content pipeline **deliberately untouched this run** (other sessions own
  milestones 8 and 10, and this brief was milestone-7-only):
  `content/inbox/items/batch_03.json` is waiting for review, and the stale empty
  `content/inbox/quests/batch_02.json` from the 07-18 run is still there.

**NEXT UP** — milestone 9 (quest system + journal) is the unclaimed one; 8 and
10 are owned. Whoever takes the next engine milestone: run the three
verification levels above, and add a `tests/*_selftest.tscn` alongside the work
— the harness pattern is cheap and it caught two bugs in its first hour.

## 2026-07-18 (scheduled autonomous run #2, no Godot) — Combat v1

**DONE — content pipeline**
- Inbox empty this run (this morning's run #1 already merged `batch_02.json` →
  meadow quests). Validator PASS both ways: **approved 70 entries / 0 err**,
  inbox 0. Nothing to merge, reject, or move.
- Brief queue already stocked at **5 unclaimed** (batch_03 items, 04 monsters,
  05 pois, 06 pois_2, 07 lore) — above the ≥3 bar, and already aimed at the
  largest Datasedge Part III gaps, so no new brief was needed this run.
- Aligned `batch_04_meadow_monsters.md` to the engine I just built: added a
  "Combat v1" note steering generators toward `melee`/`ranged`/`swarm` (the
  behaviors with distinct AI now); `ambush`/`flying`/`tank`/`caster` still
  validate but currently play as a basic bruiser. No budget ticks changed
  (nothing merged).

**DONE — roadmap milestone 6: Combat v1 (built, UNSEEN)**
New `game/src/combat/`: `combat_layers.gd` (shared physics-layer bits),
`health.gd` (hearts pool, half-hearts, i-frames), `damage_shards.gd` (the canon
"dissolved into shards" burst), `projectile.gd` (ranged data-bolt), `enemy_visual.gd`
(code-built cel-shaded bodies per behavior + hit-flash/telegraph), `enemy.gd`
(data-driven brain), `monster_spawner.gd`, `player_combat.gd` (the sword kit).
New `game/src/ui/combat_hud.gd`. Wired: `event_bus.gd` (+7 combat signals),
`input_setup.gd` (+attack/block/dodge/special/debug_charge, mouse binder),
`kern_visual.gd` (swing + guard poses, idle-anim yield), `camera_rig.gd` (trauma
shake), `player.gd` (Health + PlayerCombat integration, `apply_hit`, come-apart/
reform), `player.tscn` (+Health, +Combat nodes), `main.gd` (spawns HUD + spawner
in normal play; screenshot mode stays clean).
- **Player kit**: 3-hit light combo with a forgiving buffer + BOTW-ish
  soft-target facing; roll-dodge with i-frames and a cooldown; hold-block that
  chips damage head-on with a tight parry window (full negate + a sliver of
  focus). Movement scales to 0 mid-swing, a crawl while guarding; dodge drives
  velocity directly.
- **Enemy AI**: one `Enemy` reads a ContentDB monster dict (or a sparring cfg)
  and runs melee / ranged / swarm / dummy brains — aggro + leash, wander,
  wind-up telegraph (warm glow), lunge-strike or bolt, recover, stagger on hit,
  and death = shard dissolve + drop roll (→ `GameState.add_item`/EventBus) then
  free (dummies reform). Ranged kites and fires `Projectile`s; swarm charges.
- **Feel**: hit-flash, knockback, brief hitstop (`Engine.time_scale`, restored
  on an ignore-time-scale timer), trauma-based camera shake, shard sparks on
  every hit — GDD §10 juice.
- **Hearts + HUD**: reusable `Health` seeded from `GameState.hearts_max`; a
  deliberately minimal code-drawn HUD (heart row w/ half-hearts, focus sliver,
  damage vignette + low-HP pulse). The full HUD (hearts/Tokens/minimap) is still
  its own later milestone — this is a v0 it will absorb.
- **Deliberate scope calls (autonomous, noted for review):**
  1. Only the swarm Stray Glitchling is approved, so to make melee+ranged AI
     verifiable NOW without inventing canon (that's ChatGPT's briefed job,
     batch_04), the `MonsterSpawner` field-spawns the real Glitchling AND stands
     up a **proving ground** of clearly non-content sparring rigs (`monster_id`
     ""): a straw dummy, a melee construct, a ranged construct. Flag
     `DEBUG_PROVING_GROUND` retires it once batch_04's monsters land.
  2. The **focus / knowledge-charge special** (a shard-nova) is fully built and
     hooked, but its SOURCE stays milestone 7's job: `PlayerCombat` exposes
     `add_charge()` and already listens on `EventBus.quiz_answered`; a dev key
     **F** fills the meter so the special is testable before the quiz UI exists.
  3. **Save shape untouched** — current hearts stay session-runtime for now
     (seeded full from `hearts_max`); persisting them + the migration lands with
     the save/load milestone, so `SAVE_VERSION` was intentionally NOT bumped.
- Static verification (no Godot here): tab/bracket smoke-lint clean across 28
  `.gd` files; every `res://` reference resolves; all 7 new EventBus signals are
  declared and their handlers' arities match; validator PASS.

**HALF-FORMED / cleanup for a live session**
- New scripts have **no `.uid`** (can't run Godot). Scenes load scripts by
  `res://` path so they resolve; a live import must generate + commit the `.uid`s
  (CLAUDE.md convention).
- `content/inbox/quests/batch_02.json` still lingers as `[]` (the sandbox mount
  blocks deletes; harmless — validator sees 0). Delete it in a live session.
- Nothing is mid-flight; the main line runs (statically). No half-wired state.

**UNSEEN (GDD §10 verification rule)** — Combat v1 is a large visible surface no
human/editor has seen. A live session must: import the project (parse errors?),
boot clean, then FIGHT — feel the 3-hit combo + soft-target, roll i-frames,
block/parry, watch enemy telegraphs + shard dissolves + drops, take damage to
the come-apart/reform, and press **F** then the special to see the nova. Only
then does the box tick fully clean.

**GIT** — this environment has **no working git** (`.git` present but empty in the
mount); **nothing is committed**. A live session must review and commit all of the
above as one change per the iron rules. Suggested message:
`Gradientfall: Combat v1 — sword combo/dodge/block, enemy AI (melee/ranged/swarm), hearts + shard-death VFX, spawner + proving ground`.

**NEXT UP** — Phase 1 milestone 7: **Knowledge charge v1** — the in-combat quiz
prompt that feeds the focus meter/special already wired here (scale questions to
campaign progress; on correct → `PlayerCombat.add_charge`). Also merge
batch_03/04/05 when their inbox outputs land.

---

## 2026-07-18 (scheduled autonomous run, no Godot) — Bit the fairy + content

**DONE — content pipeline**
- Reviewed and merged `content/inbox/quests/batch_02.json` (8 quests) →
  `content/approved/quests/meadow_quests.json`. All keepers, essentially
  untouched: five ML-puzzle side quests (cross-validation fish tale, k-NN sheep,
  gradient-descent irrigation, precision/recall goose bell, controlled-change
  bee ribbons) plus the 3-part *Missing Ledger Pages* chain — which dovetails
  beautifully with Elowen Patch's approved dialogue ("the oldest Seed Vault
  records have missing entries") and ends on a held-out-test-set beat ("an
  outside-only comparison… no brave improvising") at the Vault ruins. Canon,
  tone, and cross-refs all clean; validator PASS (approved: 70 entries, 0 err).
- Moved `batch_02_bootstrap_quests.md` queue → done.
- Corrected WORLDBOOK Part III Datasedge ticks to the true approved counts:
  side quests **12 (9✅)** (the prior 3✅ was stale — only 1 quest had actually
  been approved before this merge), monsters **8 (1✅)**, POIs **24 (1✅)**.

**DONE — brief queue (topped to 5 unclaimed)**
- Wrote `batch_06_meadow_pois_2.md` (9 more meadow POIs — the region's largest
  remaining gap: 24 target vs. ~16 after batch_05; instructs no overlap with the
  five taken sites, fresh back-corner discoveries, west-sea/south vistas).
- Wrote `batch_07_meadow_lore.md` (2 meadow lore books — lore had NO brief; 3
  target, 1 approved). Both to the batch_01 self-contained standard, with a
  spoiler guardrail so external generators don't reveal who Kern is.
- Queue now: batch_03 (items), 04 (monsters), 05 (pois), 06 (pois), 07 (lore).

**DONE — roadmap milestone 5: Bit the fairy (built, UNSEEN)**
- New: `src/companion/bit.gd`, `bit_lines.gd`, `bit_landmark.gd`;
  `src/world/meadow_landmarks.gd`. Wired: `main.tscn` (+`Bit`, +`World/Landmarks`),
  `main.gd` (`_landmarks.build` + `_bit.setup`), `event_bus.gd` (+`bit_spoke`,
  +`landmark_named`), `meadow_terrain.gd` (+`is_deep_water()`).
- **Follow**: framerate-independent exp-smoothed hover at Kern's shoulder;
  scout-offset to the left of travel; idle orbit + bob when he's still; snappier
  catch-up past 4.5 m; **canon water-fear** — over the millpond Bit pulls up and
  inward and frets ("You paddle, I'll supervise from up here").
- **Look-at naming**: scans `BitLandmark` group; first time Kern nears one, Bit
  faces it, darts a little toward it, and eagerly names it. 8 landmarks planted
  at MeadowTerrain's canonical spots (Bootstrap, Old Millpond, Seed Vault ruins,
  Whispering Well, Boundary Stones, Hivewise Apiary, + Gradient Peaks & Latent
  Forest vistas). Remembered via `GameState.flags` (no save-format change), and
  these anchors double as drop points for the real POI props later.
- **Hint lines**: in-voice barks (curious/loyal/vain/water-shy per WORLDBOOK
  Part IV; the one allowed "Hey! Listen!" is reserved for the Citadel and is NOT
  used) — greeting, idle+hint pools, and reactions to quiz/item/region events —
  shown on a floating billboard `Label3D` (fade in/out, one at a time; naming &
  water preempt idle) and broadcast on `EventBus.bit_spoke` for the future
  dialogue UI. Visual is code-only: unshaded glow core + additive halo +
  fluttering wings + a soft omni light.

**HALF-FORMED / cleanup for a live session**
- The sandbox mount blocks file *deletes*: `content/inbox/quests/batch_02.json`
  could not be unlinked, so it was emptied to `[]` (validator sees 0 entries —
  harmless). Live session: delete the stray file.
- New scripts have **no `.uid` files** (can't run Godot here). The scene loads
  scripts by `res://` path so it will resolve, but a live import must generate
  the `.uid`s and commit them (CLAUDE.md convention).

**UNSEEN (GDD §10 verification rule)** — Bit has a visible surface and NO human/
editor eyes have seen it. A live session must: (1) open the project so Godot
imports + reports any parse error, (2) confirm clean boot, (3) watch Bit —
follow feel, the water-fear at the pond, landmark naming barks, the floating
label, night glow. Only then does its box tick fully clean.

**GIT** — this environment has no working git (`.git` present but empty in the
mount); **nothing is committed**. Danny / a live session must review and commit
all of the above as one change per the iron rules. Suggested message:
`Gradientfall: Bit the fairy (follow/naming/hints) + merge meadow quest batch + queue POI & lore briefs`.

**NEXT UP** — Phase 1 milestone 6: **Combat v1** (sword combo/dodge/block, enemy
AI melee+ranged, hearts, data-shard death VFX). Also merge batch_03/04/05 when
their inbox outputs land; batch_06/07 await generation.

---

## 2026-07-17 (live session) — richness pass #3: real mountains

**DONE (eyes-verified)**
- Gradient Peaks vista rebuilt: `_build_peak_mesh()` — radial ring meshes
  with per-bearing noise (spurs/gullies), craggy jitter, altitude+slope
  vertex colors (slate rock, dark gullies, snow above a wandering snowline),
  generated normals, toon_soft + SDFGI lighting, fog haze. The triangle
  cutouts are gone; the north horizon reads as an actual snow range.
- GDD §10: added Danny's governing principle — the player's FEELING is the
  metric; illusion/optimization is the craft (his "billions of blades" =
  perceptual infinity, confirmed aligned).

**REMAINING VISUAL BACKLOG** — neon-lime terrain band at the mountain feet
(grazing-angle light greens, again), snow coverage slightly generous, sea
plane pale; then Kern's model. Danny's verdict pending on the overall look.

---

## 2026-07-17 (live session) — visual richness pass #2: THE FIDELITY JUMP

*Danny raised the bar: naturalistic fidelity ("real grass, real trees, every
aspect"), target hardware RTX 5080-class (decreed in GDD §10 — spend the
budget, never optimize for weak hardware at the cost of the look). Aim point
agreed: Ghost of Tsushima × BOTW — naturalistic density, painterly color;
literal photorealism explicitly off-target (code-only assets fail hardest
there).*

**DONE (eyes-verified, 2 rounds)**
- **Infinite fine-grass system** (the Ghost of Tsushima technique):
  `grass_field.gdshader` + `_build_fine_field()` — 400,000 thin 3-segment
  blades in ONE MultiMesh whose instances wrap toroidally around the camera
  in the vertex shader (always dense wherever you stand, zero CPU after
  boot). Terrain bakes height+slope into an RGF texture (`height_texture`,
  free — reuses the mesh grid); blades plant themselves via textureLod,
  die on water/steep/out-of-bounds, and a **gust wave visibly rolls across
  the field** with per-blade flutter, root AO, tip translucency (BACKLIGHT),
  gold swathes, and gust shimmer. Buffer written directly: 400k instances in
  ~98 ms. Old chunky grass reduced to 36k mid-distance accent tufts.
- **Real trees**: rebuilt generator — tapered trunk + 4–5 angled boughs, all
  wearing `bark.gdshader` (procedural wandering ridge-and-groove lines +
  cracks — "lines in the wood"); crown = **1,000 individual leaf quads** per
  variant across ellipsoid clouds at crown + bough ends; `leaf_wind.gdshader`
  draws each leaf's pointed-oval silhouette + midrib analytically, flutters
  leaves individually, bends boughs to the same gust wave as the grass, and
  lets sun through the canopy (BACKLIGHT).
- **High-end pipeline ON** (5080 decree): TAA, SSAO (1.6), **SDFGI real-time
  GI** (5 cascades, 400 m), 4096 directional shadow + soft filter quality 4,
  4096 atlas, anisotropic 4×. Screenshot mode waits ~110 frames for SDFGI/TAA
  convergence. Lighting model shifted realistic-ward: terrain/rocks on new
  `toon_soft.gdshader` (wrapped diffuse, same rim/fill/noise features),
  tufts off toon banding; character keeps true toon+rim.
- Color surgery after round 1 (milky/washed): saturated blade+terrain greens,
  sun energy 1.65/1.8 day keys, saturation 1.16, deeper mountain silhouettes,
  lighter larger leaves.

**HONEST STATE / NEXT VISUAL TARGETS**
- The field FINALLY reads as continuous living grass; dusk is genuinely
  pretty. Biggest remaining offenders: (1) vista mountains are still flat
  triangle cutouts — need real ridge geometry + snow; (2) Kern is still a
  capsule; (3) day tone leans cool/sage — one more warmth pass; (4) town
  site empty (Bootstrap build is its own milestone). Danny judges next.

---

## 2026-07-17 (live session) — visual richness pass #1 (Danny-directed)

*Danny's direction: iterate on THIS area with him as judge until "good
enough," then codify the approved look as the formula for all regions. His
bar: BOTW-level visual engagement. Reference shots from him welcome anytime.*

**DONE (all eyes-verified over 2 screenshot rounds)**
- **Grass 3×**: 108k blades (was 34k), clump-based scatter with per-clump
  coherent hues (BOTW patchiness), wider blades, fade pushed to 165 m.
- **Ground clutter**: 1,200 daisies (white/cream/pink patches) + 750
  half-buried pebbles; terrain albedo gains 2-octave world-space value noise
  (toon shader `noise_amount`) so ground reads mottled, not putty.
- **Sky life**: CloudLayer — 16 low-poly cumulus, altitude 240–380, slow
  drift w/ wraparound, self-tinting day-white → dusk-blush → night-slate.
- **Air**: AmbientMotes — 240 drifting pollen specks following the player;
  reads as fireflies at night.
- **Water v2** (`water.gdshader`): analytic ripple normals, depth-buffer
  shallow→deep color + animated shore foam ring, toon sun glint.
- **Volumetric fog**: enabled for god-ray haze — first attempt (density
  0.006) washed the whole world gray; corrected to 0.0012 w/ minimal ambient
  inject. Lesson: volumetric fog wash is the fastest way to lose saturation.

**VISUAL BACKLOG (known, next richness passes)**
- Mountain silhouettes: more jagged variety + snow caps; day version still
  reads flat gray cardboard. Mid-ground tree presence thin. Grass noon
  highlight slightly neon. Vignette/DOF consideration. Cloud coverage in the
  fixed showcase angles is luck-of-the-draw — consider deterministic cloud
  placement for the town view.

**AWAITING DANNY** — verdict on this round (he judges until "good enough",
then the approved look gets codified into an art formula doc for all regions).

---

## 2026-07-17 (live session) — Phase 1 milestone 4: cel-shaded look-dev

**DONE (built + eyes-verified this session, per GDD §10)**
- `assets/shaders/toon.gdshader`: reusable cel shader — `diffuse_toon`/
  `specular_toon` banding + fresnel rim + sky-tinted shadow fill (keeps toon
  shadows painted, not black), vertex-color albedo with sRGB linearize, plus
  an `albedo_tint` uniform for meshes without vertex colors. Applied to
  terrain, trees, and the character; grass shader gained toon render modes.
- `src/world/sky_cycle.gd` (SkyCycle): day/night cycle — sun arc (east dawn →
  high noon → west dusk → below at night) + a 7-key color script driving sky
  gradient, sun color/energy, ambient, and fog. Deterministic by `hour`;
  runs at day_length=300s in play, pausable for screenshots.
- Character: rim-lit toon material — Kern now pops off the field with a cool
  sky-blue edge (GDD §10 "rim light on characters"). Placeholder capsule
  still, but reads as a character now.
- `main.gd` screenshot mode extended: captures a 4-time-of-day showcase
  (dawn/noon/dusk/night) of the town view alongside the 4 angles.
- Iterated on real screenshots: caught tree crowns rendering white
  (`SurfaceTool.append_from` drops `set_color` — moved trunk/crown color to
  the shader's `albedo_tint`); toned night ambient down to moonlight.
  Verdict on eyes: dusk/dawn skies read genuinely BOTW-ish; the toon pass +
  rim is the promised leap from "programmer terrain."
- Fixed a name collision: inner class `Key` shadowed Godot's built-in `Key`
  enum → renamed `SkyKey`. (Lesson logged: avoid engine-reserved names for
  inner classes.)
- Showcase PNGs saved to `docs/progress/` (milestone4_*).

**NEXT UP** — milestone 5: Bit the fairy companion (follow behavior, look-at
naming, hint lines) — the first character with personality in the world.

---

## 2026-07-17 (live session) — Phase 1 milestone 3: Datasedge Meadows terrain

**DONE (built + eyes-verified this session, per GDD §10)**
- `src/world/meadow_terrain.gd`: 480×480 m procedural heightmap (fbm rolling
  + macro undulation), one `get_height()` all systems trust; Bootstrap town
  site blended flat, millpond carved east, foothills rising toward the peaks
  vista (north), fall toward the sea (west). ArrayMesh + baked vertex colors
  (grass/dry-gold/slope-rock/pond-sand), trimesh collision from the same mesh.
  Two-pass build (heights, then normals from neighbors) → 480m in ~250 ms.
- `assets/shaders/grass_wind.gdshader`: two-band wind sway, root→tip gradient,
  distance-collapse so far blades vanish (no speckle carpet), sRGB-correct.
- `src/world/meadow_flora.gd`: 34k MultiMesh grass, 700 irises in the canon
  western flats (setosa/versicolor/virginica bloom colors — the real Iris
  families, seeded for the future compendium), 69 trees in 12 collision-bearing
  copses. Deterministic seeds.
- `src/world/border_vistas.gd`: the BOTW "something's out there" horizon —
  Gradient Peaks (unshaded haze silhouettes) north, Latent Forest tree-wall
  east, Convolution sea west, southern downs. Fog does the depth work.
- `main.tscn`/`main.gd`: real world assembled; Kern spawns on terrain facing
  Bootstrap; TestSteps retired. **Screenshot dev-mode** added
  (`-- --screenshot=DIR`) so live sessions capture PNGs from 4 angles — this
  is the standing tool for eyes-on verification of visual milestones.
- Iterated visuals 5 passes on real screenshots: fixed washed-out ground
  (vertex colors were being read as linear — set `vertex_color_is_srgb` +
  shader linearize), killed white blade-splat on distant slopes (collapse all
  axes, not just Y), softened mountains to unshaded pastel, tuned palette.

**HONEST STATE (told Danny in chat)**
- This is default Godot lighting, NOT the speced cel-shading — that's the NEXT
  milestone and it's the big visual leap. Character is still the placeholder
  capsule; no town built yet; trees/props are simple. Terrain is the stage,
  not the finished set. Danny recalibrated: expect "beautiful stylized," not
  literal photoreal BOTW (code-generated, no purchased art).

**NEXT UP** — milestone 4: cel-shaded look-dev v1 (toon shader + rim light,
richer sky, day/night cycle). The pass that makes the meadow read as Zelda.

---

## 2026-07-17 (live session) — visual bar elevated by Danny

**DONE**
- Danny's directive (chat, explicit sign-off): visuals must be on par with
  BOTW/Wizard101 — "a fascinating 3D experience that truly feels immersive" —
  and unlimited effort is authorized for it. GDD §10 expanded into a full
  visual mandate: reference targets, non-negotiables checklist (cel shading +
  rim light, painterly volumetric sky with day/night palettes, wind-blown
  grass/living ground cover, water with depth+foam, post stack, juice
  everywhere), and the **verification rule**: headless boots can't see —
  visible-surface milestones need human eyes (editor run + screenshots in
  devlog) before they're clean, and scheduled no-Godot runs must flag visual
  work "unseen." ROADMAP standing rule added: every phase ends with a
  look-dev/polish pass.
- Danny confirmed the Claude/ChatGPT dynamic as-is (canon + engine stay with
  Claude; ChatGPT volume ramps once its v2 prompt is pasted).

---

## 2026-07-17 (live session) — run #2 swept: boot verified, committed

**DONE**
- Run #2's controller boot-verified in Godot 4.7.1. First boot showed parse
  errors ("Could not find type CameraRig") + missing cam_* actions — NOT a
  code bug: new scripts' `class_name`s weren't in the editor's global class
  cache yet. One `--import` scan registered CameraRig/InputSetup/Player;
  second boot fully clean (ContentDB 62 entries, zero errors). Lesson for
  live sessions: **always run `--import` before boot-verifying a run that
  added new script classes.**
- ROADMAP milestone-2 annotation upgraded to verified. All of run #2's work
  committed (controller, camera rig, input setup, sun fix, batch_05 brief,
  approved data-quiz batch).
- Danny asked who owns visual quality → answered in chat: Claude (all
  shaders/meshes/lighting/VFX per AUTONOMY §4); ChatGPT only *describes*
  appearances in content JSON; Danny is the taste authority at phase gates.

**STILL NEEDS DANNY** (carried from run #2's notes below)
- Re-paste v2/v3 prompts into BOTH scheduled tasks — run #2 found ChatGPT
  still executing the v1 quiz-only prompt (no filename suffix, ignored 3
  unclaimed briefs). Canonical text: AUTONOMY.md §2 and §3.
- Merge PR #1.

---

## 2026-07-17 (scheduled run #2) — Phase 1 milestone 2: Kern walks

*Inbox: one ChatGPT daily quiz batch. Milestone built: third-person character
controller. Queue topped up to 4 unclaimed briefs.*

**DONE**
- **Inbox processed:** `daily_2026-07-17.json` (topic: data, rotation correct
  after ml_basics). Validator 20/20; accuracy-reviewed question by question —
  all 20 correct, including the advanced ones (MNAR, kappa paradox, out-of-fold
  target encoding). Difficulty spread exactly 4× each of 1–5; answer positions
  balanced 5/5/5/5. Merged to `approved/quizzes/data_2026-07-17.json`.
  Rejections: none. Full content set: 62 entries, 0 errors. Quiz bank 41/400;
  WORLDBOOK budget line updated.
- **Milestone 2 — third-person controller** (`src/player/`, `scenes/player/`):
  - `player.gd` (CharacterBody3D): camera-relative walk/run/sprint,
    accel/decel split (no ice), BOTW-ish jump arc (floatier rise, heavier
    fall, early-release cut), coyote time (0.12s) + jump buffer (0.15s),
    body turns toward travel via lerp_angle, squash/stretch on jump/land
    (visual-only, skipped for curb-height drops). All tunables are consts.
  - `camera_rig.gd`: top_level orbit rig — yaw on rig, pitch on SpringArm3D
    (clamped), smoothed position follow, mouse capture/release (Esc frees,
    click recaptures), gamepad right-stick look, sprint FOV widen 70→78,
    arm excludes the player's collider (layer 2) so it never clips Kern.
  - `input_setup.gd`: input actions registered in code, idempotently
    (KB+mouse and full gamepad). Decision: kept OUT of project.godot — the
    Object(...) event blobs are the one part of the project file a no-Godot
    sandbox can't lint, while plain GDScript is fully checkable; also fits
    the generated-in-code rule.
  - `player.tscn`: capsule Kern in a patched-cloak green, brow marker for
    facing readability, and the canon **glowing hand-mark** as a small
    emissive sphere (GDD §4). Emits `EventBus.player_spawned`.
  - `main.tscn`: Player instanced; Ground is now a StaticBody3D with
    collision; `TestSteps` placeholder blocks (0.5/1.2/2.2 m staircase +
    pillar) for jump/camera testing — removed when real terrain lands.
    **Fixed the Sun**: its transform rotated +45° about X, aiming the beam
    *upward* (lit the world from below — headless boot verification can't
    see lighting, so run #1's check missed it). Now -45°.
  - Static verification (no Godot here): scene refs/ids/load_steps
    consistent, all res:// paths resolve, node parent paths + @onready
    $paths match the trees, GDScript brace/indent lint clean, every input
    action used is registered, EventBus signals exist. Validator PASS.
- **Queue topped up:** wrote `queue/batch_05_meadow_pois.md` (15 Datasedge
  POIs: Mill, Apiary, Boundary Stones, Vault outer ruins + 11 invented;
  vista rule enforced; rewards restricted to existing item ids). Queue now
  4 unclaimed (02 quests, 03 items, 04 monsters, 05 POIs).

**HALF-FORMED**
- Nothing mid-flight. Controller is self-contained; jump feel numbers await
  a real hands-on-keyboard pass (Danny or live session) to fine-tune.

**NEEDS DANNY / LIVE SESSION (boot + commit)**
- **This sandbox has no Godot and no git** (same as run #1): boot is
  unverified and nothing is committed. Live session: open the editor, expect
  "scaffold boot OK" + controls line + ContentDB 62 entries with zero errors,
  walk/jump/sprint around the TestSteps, then commit everything including
  the editor-generated `.uid` sidecars for the 3 new scripts as
  `Gradientfall: Phase 1 milestone 2 — third-person controller`. ROADMAP's
  "(boot unverified)" note comes off after that.
- **ChatGPT's scheduled task is still running the v1 prompt** — evidence:
  today's file is `daily_2026-07-17.json` (v2 adds a random suffix), and it
  ran the fallback quiz job while 3 briefs sat unclaimed in the queue (v2
  claims briefs first). Re-paste AUTONOMY.md §2 v2. Same for this run's own
  task prompt (§3 v3) — this run followed the repo docs anyway, per
  CLAUDE.md's "trust the docs" rule.

**NEXT UP** — Phase 1 milestone 3: Datasedge Meadows terrain (heightmap +
procedural grass/trees, region border vistas). The TestSteps blocks retire
when it lands.

---

## 2026-07-16 (live session) — WORLDBOOK: the master specification

**DONE**
- `docs/WORLDBOOK.md` — the complete game designed in advance so autonomous
  runs execute a spec instead of improvising: full campaign (9 chapters, 9
  Memory Shrines with abilities + revelations, spoiler-complete backstory,
  3-stage Echo finale with two endings), all 10 regions in detail (identity,
  sites, towns, named key NPCs, dungeon + its teaching mechanic, world bosses,
  named side-quest chains, monster themes, materials, dataset tie-ins),
  content budget tables (141 side quests / 84 NPCs / 80 monsters / 275 items /
  275 POIs / 38 lore / 400 quizzes), and naming/voice rules for all generators.
- AUTONOMY.md §4: explicit two-list division of labor (Claude / ChatGPT /
  Danny), per Danny's request.
- Both daily prompts upgraded to v3: read GDD+WORLDBOOK first; Claude builds
  to spec, authors campaign content directly, ticks budgets, and observes
  **phase gates** (loud playtest flag + 2 content/polish runs, then proceed —
  autonomy never stalls). CLAUDE.md read-first list now includes WORLDBOOK.

**DONE (addendum — gate notification)**
- Phase-gate discovery solved three ways (AUTONOMY.md §5): daily runs now
  create `gradientfall/PHASE_GATE.md` at each gate (playtest checklist +
  "## Feedback" section that runs treat as priority work items); a local
  watcher task (`gradientfall-gate-watcher`, every 3 days) push-notifies
  Danny when the flag file exists; ambient signals (version-bump commit,
  devlog headline) remain.

**NEEDS DANNY**
- Paste the v3 prompts into both scheduled tasks (canonical in AUTONOMY.md
  §2/§3 — also given directly in chat). The Claude prompt gained one gate
  paragraph (step 4b) — re-paste from §3.
- Merge PR #1. Playtest at phase gates when the watcher pings (recommended,
  not blocking).

**NEXT UP** — Phase 1 milestone 2: third-person character controller.

---

## 2026-07-16 (live session) — tag protocol + scaffold verified & committed

**DONE**
- **Scheduled run #1's scaffold verified and committed by this live session**:
  headless import + boot in Godot 4.7.1 — clean import, "scaffold boot OK",
  ContentDB loads 22 entries across 7 types, zero errors. ROADMAP annotation
  upgraded from "boot unverified" to verified. (Scheduled runs have no git in
  their sandbox; live sessions sweep, verify, and commit their work — this is
  now the expected rhythm.)
- **Tag protocol** (Danny's design): Claude and ChatGPT coordinate through
  folder state, no waiting in either direction. Briefs restructured into
  `docs/briefs/queue/` (waiting) and `docs/briefs/done/` (approved);
  batch_01 moved to done/. AUTONOMY.md §1 documents the protocol.
- Claude's schedule prompt v2 (AUTONOMY.md §3): queue top-up is now
  **unconditional step 3** — every run ends with ≥3 unclaimed briefs queued.
  (Run #1 legitimately skipped brief-writing under the old conditional
  wording — Danny caught the starvation gap.)
- ChatGPT's schedule prompt v2 (AUTONOMY.md §2): self-directing worker —
  claims the lowest-numbered unclaimed brief in queue/, executes it, and only
  falls back to the quiz job when the queue is fully claimed. Quiz filenames
  now carry a random suffix so many runs per day never collide.
- Queue seeded with 3 briefs: batch_02 Bootstrap quests, batch_03 meadow
  items, batch_04 meadow monsters.

**DONE (addendum)**
- ChatGPT's first daily quiz batch arrived mid-session (20 ml_basics questions).
  Validator 20/20; accuracy-reviewed question by question — all correct, good
  difficulty spread and balanced answer positions. Merged to
  `approved/quizzes/ml_basics_2026-07-16.json`. Full content set: 42 entries,
  0 errors. Both directions of the pipeline have now run for real.

**NEEDS DANNY**
- Update the **Claude scheduled task's prompt** to AUTONOMY.md §3 v2 (it was
  created from another session; this one can't reach it).
- Update the **ChatGPT scheduled task's prompt** to AUTONOMY.md §2 v2.
- Merge PR #1 (still the prerequisite for agentic runs cloning `main`).

**NEXT UP** — unchanged: Phase 1 milestone 2, third-person character controller.

---

## 2026-07-16 (scheduled run #1) — Phase 1 milestone 1: Godot scaffold

*First autonomous daily run. Inbox: empty (nothing to process; batch_01 was
already merged last session). Milestone built: Godot 4 project scaffold.*

**DONE**
- `game/` created: `project.godot` (Godot 4.3 features, Forward+, 3 autoloads
  registered), `icon.svg` (code-authored perceptron sigil), `.gitignore`
  (`.godot/`), `README.md` (folder conventions), placeholder dirs for
  player/world/ui.
- Autoloads, fully typed GDScript:
  - `EventBus` — global signal hub (region/player/quest/inventory/quiz signals).
  - `GameState` — session state with `SAVE_VERSION = 1` and `to_save_dict()`,
    so every system built from here targets the versioned save shape (rule 5).
  - `ContentDB` — loads `../content/approved/` JSON at boot, id-indexed by the
    7 content types, enforces id prefixes + duplicate detection, reports load
    errors. Decision: editor/debug runs read the repo folder directly via
    `globalize_path`; export packing deferred to the save/load milestone.
- Boot scene `scenes/main/main.tscn` + `src/main/main.gd`: sky, sun, ground
  plane, camera; prints scaffold/ContentDB status to output on run.
- Static verification (no Godot in this environment): all `res://` references
  resolve, tscn load_steps/resource ids consistent, ContentDB load logic
  mirrored in Python loads all 22 approved entries, GDScript brace/indent
  smoke-lint clean, validator PASS (22 entries, 0 errors).

**HALF-FORMED**
- Nothing mid-flight. Scaffold is self-contained.

**NEEDS DANNY (boot + commit)**
- **This run could not launch Godot or reach git** (the automation sandbox
  mounts only `gradientfall/`, no `.git`, no editor). Per the contract this is
  flagged instead of claimed: open `game/project.godot` in Godot 4.3+, confirm
  the output panel shows "scaffold boot OK" + "ContentDB: loaded 22 entries"
  with zero errors, then commit everything **including the generated `.uid`
  files** as `Gradientfall: Phase 1 scaffold — project, autoloads, boot scene`.
- ROADMAP box is ticked with a "(boot unverified)" annotation — strip the
  annotation once you've seen it boot clean.

**NEXT UP**
- Phase 1 milestone 2: third-person character controller (walk/run/jump/camera,
  feel pass) — Kern's first steps in the meadow.
- No new brief needed: `docs/briefs/batch_01_bootstrap_npcs.md` is done and
  merged; the next batch (starter quests/items/monsters/quizzes) should wait
  until the quest/combat systems exist to consume them.

---

## 2026-07-16 (later still, cont.) — first pipeline round-trip ✅

**DONE**
- Agentic ChatGPT delivered Batch 01 (Bootstrap NPCs) to `content/inbox/npcs/`.
  Validator passed 12/12 clean. Reviewed for voice/canon: excellent — correct
  role mix, ML woven as character not vocabulary (Sir Nearest = nearest-neighbor,
  Nessa Fold's seam proverb = generalization, Cedric's sheep clusters), punny
  surnames matching the Maxwell Pool convention, Mayor cameos, purple-glow
  rumors handled per canon. Approved essentially untouched.
- Merged to `content/approved/npcs/bootstrap_townsfolk.json`. Bootstrap now has
  13 dialogued NPCs (mayor + 12). Full set validates: 22 entries, 0 errors.
- **The pipeline works end to end.** External generation → inbox → validate →
  review → approved, proven with real content.

**NEXT UP** — unchanged: Phase 1, Godot scaffold. Bootstrap's cast is now ready
to drop into the town whenever the dialogue system lands.

---

## 2026-07-16 (later still) — autonomy: agentic ChatGPT surface chosen

**DONE**
- Danny chose **agentic ChatGPT / Codex with repo access** as the content surface
  (not plain paste-the-JSON). AUTONOMY.md §2 updated: stored Danny's refined quiz
  prompt as canonical, documented Codex write-scope boundary (`content/inbox/`
  only, no commit/push, no code/canon/approved) so Codex and the daily Claude run
  never collide, and flagged the hard prerequisite that `main` must carry the
  `gradientfall/` tree (Codex clones the default branch).

**BLOCKING / NEEDS DANNY**
- **Merge PR #1 to main** (https://github.com/danieltalbert/danieltalbert/pull/1).
  Until then `main` is just the README and any Codex run clones an empty repo.

**NEXT UP** — unchanged: Phase 1, Godot scaffold in `gradientfall/game/` first.

---

## 2026-07-16 (later) — Phase 0 addendum: autonomy setup

**DONE**
- `docs/AUTONOMY.md`: canonical prompts for (1) ChatGPT batch kickoff, (2) a
  standing ChatGPT scheduled task generating daily quiz batches, (3) the prompt
  Danny pastes into a fresh Claude session to build the recurring schedule.
- Batch 01 brief rewritten fully self-contained (schema + worked example inline)
  so Danny pastes one thing. All future briefs follow this standard.
- Danny's local model is 14B → retired from the pipeline by mutual agreement.
- Branch pushed to GitHub; PR opened to bring stale `main` current (it only had
  the README; all Neural Quest + Gradientfall work was local to this branch).

**NEXT UP** — unchanged: Phase 1, Godot scaffold in `gradientfall/game/` first.

---

## 2026-07-16 — Phase 0: Foundation

**DONE**
- Design locked with Danny across three Q&A rounds. Full record in GDD.md — key
  calls: Godot 4 / BOTW-style cel-shaded look on stylized geometry / hybrid
  real-time + knowledge-charge combat / Neural Quest sequel / homestead + crafting
  (no freeform voxel building) / education woven into everything / handcrafted
  regions + procedural fill / all-ages / phase-by-phase merges / ~30% campaign,
  70% free-roam, no hard gates except Corpus Citadel interior / 40–80 hr target.
- Creative canon approved: Kern the Vaultborn (hero, secretly the First Model),
  Echo the Unaligned (rogue-LLM villain, autocompletes the world), Bit (fairy
  companion), King Reginald the Well-Regularized, 10 regions, town of Bootstrap.
- Docs written: GDD, ROADMAP, CONTENT_PIPELINE, CLAUDE.md (session contract).
- Content pipeline built: 7 JSON schemas, validator (`tools/validate_content.py`,
  zero deps), seed content for every type (all cross-refs resolve), inbox dirs,
  first ChatGPT brief in `docs/briefs/`.

**HALF-FORMED**
- Nothing. Clean state.

**NEXT UP (Phase 1 start)**
- Godot 4 project scaffold in `gradientfall/game/`, then third-person controller
  + camera. See ROADMAP Phase 1 checklist, top to bottom.
- Danny may run the first ChatGPT batch (`docs/briefs/batch_01_bootstrap_npcs.md`)
  any time — check `content/inbox/` at session start.

**WORKFLOW NOTES**
- Danny drives ChatGPT batches on his own schedule using briefs; validator gates,
  Claude reviews voice/canon and merges to approved/.
- Local model participation: deferred, pipeline is model-agnostic; a test batch's
  rejection rate will decide.
- Repo note: GitHub `main` only has the README; all Neural Quest + Gradientfall
  work lives on the `claude/*` session-branch lineage. Worth a PR to main soon.

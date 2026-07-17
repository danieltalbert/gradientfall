# Gradientfall Devlog

*Newest entry first. Every session appends: DONE / HALF-FORMED / NEXT UP.*

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

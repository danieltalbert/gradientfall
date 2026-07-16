# Gradientfall Devlog

*Newest entry first. Every session appends: DONE / HALF-FORMED / NEXT UP.*

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

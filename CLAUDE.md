# Gradientfall — builder's contract

This folder is **Neural Quest: Gradientfall**, a 3D open-world Godot 4 game built
across many sessions. The repo carries all project state — trust these docs over
memory of past conversations.

## The one canonical workspace (check this before touching anything)
- **Work here and nowhere else:** `C:\Users\danny\danieltalbert`, branch
  **`main`**. One tree, one branch. `main` == `origin/main` is the real,
  playable state; there are no side branches to reconcile.
- **Stale copies exist on disk — never open, edit, or judge the game from
  them.** Snapshots under `C:\Users\danny\Documents\Codex\...\gradientfall\`
  are frozen 2026-07-20 captures predating the photoreal grass work (old
  1.4M-blade spiky grass, no terrain cull fix → the "gray hollow ground").
  Each is marked `STALE_DO_NOT_USE.md`. Mistaking one of these for the real
  project has already cost this project real time.
- **Confirm before building or judging visuals:**
  ```
  git branch --show-current && git log --oneline -1
  ```
  Expect `main`. If it isn't, stop and fix that before anything else.

## Read first, every session
1. `docs/DEVLOG.md` — last entry says exactly where things stand and what's next
2. `docs/ROADMAP.md` — current phase + checkboxes
3. `docs/GDD.md` — the locked design (changes need Danny's sign-off)
4. `docs/WORLDBOOK.md` — the master specification: every region, campaign
   chapter, dungeon, boss, quest chain, and content budget. Build what it
   says; don't invent what it already specifies. (`docs/AUTONOMY.md` §4 says
   who does what.)

## The iron rules
1. **Never commit a half-wired state — but never LEAVE work uncommitted either.**
   Every session ends with: game runs clean from the editor, docs updated to
   match reality, and **all work committed AND pushed to `origin/main`**. If a
   feature is mid-flight at session end, it gets stashed behind a flag or
   reverted — the main line always runs.
   - "Other lanes are mid-flight, I'll let a later sweep commit it" is **not**
     an acceptable ending. That reasoning stranded a full day of finished
     photoreal-grass work outside version control and sent later sessions to
     stale copies. If lanes are interleaved, commit the whole tree as one
     verified snapshot (parse-check, then `git add -A`) and say so in the message.
   - **Commit whole, consistent snapshots, not single files.** Committing one
     file of a two-file change has already landed a caller on `main` without
     its definition. Parse-check first, then commit everything together.
   - Uncommitted work is invisible to every future session. Treat "it's on my
     disk" as "it does not exist."
2. **Docs are updated in the same commit as the work.** Checkboxes in ROADMAP.md,
   a dated entry in DEVLOG.md ("done / half-formed / next up").
3. **GDD is locked.** Design pillar changes require Danny's explicit sign-off.
   Implementation details are builder's discretion.
4. **Content flows through the pipeline.** All quests/NPCs/items/monsters/quizzes/
   lore/POIs live as JSON under `content/approved/` and must pass
   `python tools/validate_content.py`. Externally-generated content lands in
   `content/inbox/` first — see `docs/CONTENT_PIPELINE.md`. Never hand-fix inbox
   files silently; fix-and-note or reject.
5. **Save compatibility.** The save format carries a `save_version` int. Any change
   to save structure bumps it and adds a migration. Never strand a player's file.

## Conventions
- **Engine:** Godot 4.x, GDScript, statically typed everywhere (`var x: int`,
  typed funcs). All assets generated in code — no downloaded/purchased assets.
- **Game project root:** `gradientfall/game/` (created in Phase 1).
- **Naming:** snake_case files/dirs; PascalCase node names & class_name; content
  IDs prefixed (`q_`, `npc_`, `item_`, `mon_`, `quiz_`, `lore_`, `poi_`).
- **Region IDs** (canonical, used everywhere): `datasedge_meadows`,
  `gradient_peaks`, `latent_forest`, `overfit_swamp`, `tensor_desert`,
  `frozen_cache`, `backprop_foundry`, `convolution_coast`, `parameter_city`,
  `corpus_citadel`.
- **Commits:** `Gradientfall: <what>` — same style as Neural Quest history.
  Phase completions get a version-bump commit.
- **Godot `.uid` files are committed**, same as scenes.

## Division of labor
- **Claude:** all engine code, canon/voice, content review + merges to `approved/`.
- **ChatGPT (Danny's schedule):** bulk content generation from briefs in
  `content/briefs/`, output dropped in `content/inbox/`.
- **Local model (optional, unproven):** may attempt simple bulk content the same
  way; the validator's rejection rate decides if it stays.

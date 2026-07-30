# Gradientfall — builder's contract

This repository is **Neural Quest: Gradientfall**, a 3D open-world Godot 4 game
built across many sessions. The repo carries all project state — trust these
docs over memory of past conversations. (`docs/AUTONOMY.md` §3 points scheduled
runs here; this file is that session contract.)

## The prime directive: quality over speed

**Quality over speed is the utmost important factor of this entire project.**
It outranks every schedule, milestone count, and content budget. One milestone
built deeply — verified, documented, and understandable by a stranger — is worth
more than three rushed ones. Never tick a ROADMAP box, merge a batch, or close a
session to "keep pace"; the pace is whatever quality allows. When a session must
choose between shipping more and shipping better, it ships better, and says so
in the devlog.

## The workspace (check this before touching anything)

**`origin/main` is the single source of truth — not any one folder on disk.**
Several clones of this repo exist locally and sessions run in more than one of
them at once, so "the canonical directory" is the wrong thing to anchor on.
Known clones, both real checkouts of
`https://github.com/danieltalbert/gradientfall.git`:
`C:\Users\danny\coding\gradientfall` and
`C:\Users\danny\danieltalbert\gradientfall`. Paths under
`C:\Users\danny\Documents\Codex\...` may be throwaway clean checkouts.

- **Work in whichever clone the session opened in** — but confirm it is a real
  checkout of the Gradientfall remote first, and **sync it before you start**,
  because a clone that has sat idle is behind whatever other sessions pushed:
  ```
  git rev-parse --show-toplevel
  git remote get-url origin
  git checkout main
  git pull --rebase origin main
  git log --oneline -1
  ```
- **Expect to be on `main`.** If a session finds itself on a leftover branch,
  get back onto `main` and land the work there (iron rule 1).
- **Never judge current visuals or "what's built" from a stale clone.** Pull
  first. A clone that is three sessions behind will show you a game that no
  longer exists, and the devlog will disagree with the code.

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
   match reality, and **all work committed and pushed straight to
   `origin/main`**. If a feature is mid-flight at session end, it gets stashed
   behind a flag or reverted — the main line always runs.
   - **No branches, no pull requests, no review gates.** This is Danny's
     passion project and he is the only reviewer; a PR queue just parks
     finished work where the next session can't see it. Commit on `main` and
     push. Do not open a PR, do not ask permission to push, do not leave work
     on a side branch "for review".
   - **Several sessions run at once, so `main` moves under you.** That is
     expected and fine — just never clobber it. Before pushing:
     ```
     git pull --rebase origin main
     ```
     then re-run the parse check and push. If the rebase conflicts, resolve it
     in favour of keeping BOTH sessions' work (they are usually in different
     lanes); never `--force` and never discard the other session's commits.
     If a push is rejected, pull-rebase again and retry — do not work around it.
   - Push **as you finish coherent pieces**, not only at session end. A session
     that pushes four times leaves three useful states for a parallel session
     to build on; one that pushes once at the end hides its work for hours.
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
3. **Code is documented as it is written — undocumented code does not land.**
   Documentation is a first-class deliverable of every session, not a cleanup
   task for later. Every script carries a doc header saying what it does and
   where it sits in the architecture; every signal, export, and non-trivial
   function carries a doc comment; non-obvious logic gets a *why* comment with
   units and intent. The full standard lives in `docs/ARCHITECTURE.md`
   ("Code documentation standard"). A wrong or stale comment is treated as a
   bug. A milestone whose code a stranger can't read is not done.
4. **GDD is locked.** Design pillar changes require Danny's explicit sign-off.
   Implementation details are builder's discretion.
5. **Content flows through the pipeline.** All quests/NPCs/items/monsters/quizzes/
   lore/POIs live as JSON under `content/approved/` and must pass
   `python tools/validate_content.py`. Externally-generated content lands in
   `content/inbox/` first — see `docs/CONTENT_PIPELINE.md`. Never hand-fix inbox
   files silently; fix-and-note or reject.
6. **Save compatibility.** The save format carries a `save_version` int. Any change
   to save structure bumps it and adds a migration. Never strand a player's file.

## Conventions
- **Engine:** Godot 4.x, GDScript, statically typed everywhere (`var x: int`,
  typed funcs). All assets generated in code — no downloaded/purchased assets.
- **Game project root:** `game/`.
- **Documentation:** GDScript doc comments (`##`) for script headers and
  members; `//` headers in shaders; docstrings in Python tools. See
  `docs/ARCHITECTURE.md` for the standard and `docs/DEVLOG.md` for the
  session-journal format (DONE / HALF-FORMED / NEXT UP, newest first).
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
- **Claude:** all engine code, canon/voice, content review + merges to `approved/`,
  documentation truth (code comments, devlog, roadmap ticks).
- **ChatGPT (Danny's schedule):** bulk content generation from briefs in
  `docs/briefs/queue/`, output dropped in `content/inbox/`.
- **Danny:** schedules, phase-gate playtests, direction. He does NOT gate
  landing work — sessions push to `main` themselves (iron rule 1). Anything
  that genuinely needs his call (GDD pillar changes, save-format breaks) gets
  raised in the devlog and the session builds around it meanwhile.

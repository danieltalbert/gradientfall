# Gradientfall Devlog

*Newest entry first. Every session appends: DONE / HALF-FORMED / NEXT UP.*

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

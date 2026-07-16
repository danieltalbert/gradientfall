# Gradientfall Devlog

*Newest entry first. Every session appends: DONE / HALF-FORMED / NEXT UP.*

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

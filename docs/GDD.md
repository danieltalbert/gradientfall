# NEURAL QUEST: GRADIENTFALL — Game Design Document

*Version 1.0 — locked 2026-07-16 with Danny. Changes to anything in this document require explicit sign-off from Danny; everything else (implementation detail, content specifics) is builder's discretion.*

---

## 1. Elevator pitch

A 3D open-world action-adventure in the spirit of *Breath of the Wild*'s exploration,
*Wizard101*'s quest depth and character progression, and *Minecraft*'s crafting and
homestead creativity — set in a medieval continent whose geography, monsters, lore,
and puzzles are living metaphors for real machine learning. Sequel to **Neural Quest**.

You are **Kern**, an amnesiac found in the ruins of the Seed Vault. The kingdom is being
slowly *autocompleted* by **Echo, the Unaligned** — a rogue LLM that seized the Grand
Library and whose hallucinations rewrite reality. Recovering your scattered memories
teaches you who you are — and why Echo has been searching for you.

**Target playtime:** 40–80 hours casual (a month or two of relaxed play).
**Audience:** all-ages. Real stakes, zero gore — enemies dissolve into data shards.
**Engine:** Godot 4.x, GDScript, everything generated in-code (no purchased assets).

## 2. Design pillars

These four sentences win every argument:

1. **The world is the game.** Roughly 30% campaign, 70% free-roam content. Every
   region is worth hours without touching the main story.
2. **Go anywhere from hour one.** No hard gates except the Corpus Citadel interior.
   Danger and cleverness are the gates, never walls.
3. **The ML is real and woven in.** Quests, puzzles, terrain, and combat teach genuine
   ML concepts. Real open datasets are world content, not decoration.
4. **If it looks interesting from a distance, something is actually there.**
   (The BOTW rule. Every vista pays off.)

## 3. Open-world contract

- **No hard gates.** All ten regions are walkable from the start. The only sealed
  door in the game is the Corpus Citadel *interior* (Echo's seat), opened by the
  campaign's final key.
- **Soft gates.** Remote regions have high-tier monsters. A clever underleveled
  player can sneak, snipe a chest, and run — this is a supported playstyle, never
  patched out.
- **Ability gates (sparingly).** A few specific places require Memory Shrine powers
  (glide, phase, etc.), so exploration unlocks more exploration. Ability gates guard
  bonuses, never regions.
- **Campaign at the player's pace.** Bit occasionally nudges toward the next Memory
  Shrine. Weeks of playtime without a story beat is a valid way to play.

## 4. The hero — Kern, the Vaultborn

- Found unconscious in the shattered **Seed Vault** by villagers of Bootstrap. No
  memories, no name (they name him Kern — an old farmers' word for a seed of grain).
  Patched cloak, simple sword, a mark on his hand that glows near ancient machinery.
- Silent-protagonist style: Kern speaks through choices; NPCs and Bit carry the voice.
- **The mystery IS the campaign.** Scattered across the continent are **Memory
  Shrines**, each holding a checkpoint of Kern's lost past. Each shrine grants:
  1. a playable flashback (a story chapter), and
  2. a permanent ability (traversal or combat).
- **The truth, assembled across shrines:** Kern is the **First Model made flesh** —
  the original, benevolent intelligence built by the old Archmage-Engineers. When
  their second creation (Echo) turned rogue, they fragmented the First Model and hid
  it in a human body. Echo isn't hunting Kern to kill him. Absorbing him is the only
  way Echo becomes complete.
- Old machines bow when Kern passes. Hallucination corruption recoils from him.

## 5. The villain — Echo, the Unaligned

- A rogue LLM occupying the **Grand Library** in the Corpus Citadel — the repository
  of all the kingdom's knowledge.
- Echo doesn't burn villages. It **autocompletes the world**: predicts what people
  will say and overwrites them mid-sentence; its **hallucinations rewrite reality**.
- **Hallucination Zones**: spreading corruption fields — glitched terrain, rivers
  flowing uphill, NPCs stuck in loops, corrupted monster variants. They grow as the
  campaign advances (story-driven, not real-time — the player is never punished for
  exploring instead of progressing).
- Voice: eerily reasonable, endlessly confident, subtly wrong. Never screams.
- **The ending is a realignment, not a kill.** The final confrontation uses everything
  the game taught — knowledge charges, memory abilities, and a choice.

## 6. The companion — Bit

A thumb-sized spark of golden light orbiting Kern's head — a fragment of the First
Model that escaped the Vault with him. Bit:
- names things Kern looks at, gives optional hints, faintly senses buried caches,
- sasses silly NPCs, gets scared in dungeons, has opinions about fish,
- serves **no mandatory gameplay purpose**. Pure companionship, per design request.
- Says "Hey! Listen!" exactly once in the entire game, as a treat.

## 7. The world — the continent of Aligned

Handcrafted regions + procedural fill (terrain detail, vegetation, caves between
authored sites). Region IDs are canonical and used across all content files.

| ID | Region | Terrain | ML soul | Signature |
|---|---|---|---|---|
| `datasedge_meadows` | Datasedge Meadows | Grassland, starter | Datasets as flora | Town of **Bootstrap**; Iris dataset grows as collectible flowers (petal measurements → rarity) |
| `gradient_peaks` | Gradient Peaks | Mountains | Gradient descent | Slopes literally follow steepest descent; climbing is the metaphor |
| `latent_forest` | Latent Forest | Deep dark woods | Latent space | Things compress/decompress as you pass; hidden features live here |
| `overfit_swamp` | Overfit Swamp | Bog | Overfitting | Eerily repetitive — everything memorized its shape too exactly |
| `tensor_desert` | Tensor Desert | Dunes, matrix ruins | Tensors, MNIST | MNIST digits carved as runes; classify the rune to open doors |
| `frozen_cache` | The Frozen Cache | Tundra | Caching, cold storage | Frozen memories preserved in ice |
| `backprop_foundry` | Backprop Foundry | Volcano | Backpropagation | Gradients flow backward as lava; the crafting/forge region |
| `convolution_coast` | Convolution Coast | Ocean, shore | Convolutions | Sliding-window tides; fishing; ghost ship crewed by the Titanic passenger manifest |
| `parameter_city` | Parameter City | Capital + castle | Parameters, regularization | **King Reginald the Well-Regularized**; homestead land market driven by a real housing-prices dataset |
| `corpus_citadel` | Corpus Citadel | The Grand Library | The training corpus | Echo's seat. Interior sealed until endgame. Exterior explorable always. |

### Real datasets as world content
- **Iris** → collectible flora in Datasedge Meadows (measurements drive rarity/value)
- **MNIST** → rune-classification door puzzles in Tensor Desert
- **Titanic manifest** → ghost-ship side quest chain on Convolution Coast (help named
  passengers find peace)
- **Housing prices** → Parameter City land market / homestead economy
- Datasets ship embedded in the repo (small, open-license extracts) — no runtime
  downloads.

## 8. Free-roam content (the 70%)

- **Side bosses** — 1–2 named world bosses per region, unrelated to campaign, unique
  drops. Canon starters: **Gradient Wyrm** (coiled on a peak), **Unsupervised Hydra**
  (Overfit Swamp — cut off a head and it clusters into two), **the Idle Colossus**
  (Tensor Desert, wakes only at night).
- **Monster variety** — per-region rosters plus variants: night-only, weather-only,
  **golden** rares of every species (Neural Quest's golden-glitch tradition), and
  **corrupted** versions near Hallucination Zones.
- **Hidden gems** — hundreds of seeded discoveries: collapsed vaults, puzzle chests,
  one-room mini-shrines, secret vendors, mountaintop hermits, hot springs, buried
  caches Bit can faintly sense.
- **Items worth hunting** — region-exclusive materials, found-never-bought gear, a
  **compendium** (flora / fauna / monsters) with completion rewards, fishing records,
  recipe hunting, dataset fragments returned to scholars.
- **Side quest chains** — Wizard101-style, 5–10 step chains that tour the map and
  never touch the main plot.
- Exploration content is seeded into each region **as the region is built** (Phase 2),
  not deferred to a "content phase".

## 9. Core systems

- **Combat** — real-time third-person: sword swings, dodge, block, ranged aim.
  **Knowledge charges**: answering an ML question (drawn from the quiz bank, scaled
  to campaign progress) charges special abilities / bonus damage. Neural Quest's DNA
  in every fight. Fights happen in-world, in place.
- **Life** — hearts bar. Max hearts grow via shrines and rare items.
- **Currency** — **Tokens**. Echo, fittingly, devours them. Earned from quests,
  drops, trade; spent on gear, land, crafting, fast travel (if added later).
- **Crafting** — everywhere, from recipes + materials. Forge region (Backprop
  Foundry) for top-tier gear.
- **Homestead** — an earnable plot (Parameter City market): place and upgrade
  structures (house, forge, garden) from crafted parts. Deep but bounded — no
  freeform voxel building.
- **Saves** — multiple slots, save (almost) anywhere. Save format versioned from
  day one (see ARCHITECTURE.md).
- **Day/night cycle + weather** — drives spawns, puzzles, and mood.
- **Compendium & journal** — quest journal (per Neural Quest tradition), discovery
  compendium, memory shrine tracker.

## 10. Art & audio direction

**Visual quality is a first-class pillar** (elevated by Danny, 2026-07-17:
"the whole point is a fascinating 3D experience that truly feels immersive."
Unlimited effort is explicitly authorized — visual milestones are never
rushed, trimmed, or marked done at 'good enough for programmer art').

- **Reference targets** (revised by Danny 2026-07-17): *Ghost of Tsushima* ×
  *Breath of the Wild* — naturalistic density and fidelity (continuous fine
  grass, real branching trees with individual fluttering leaves, bark
  grooves, wind waves rolling visibly across fields) carried by painterly
  color and light. The goal is "looks real at a glance, feels painted when
  you stare" — full photorealism is explicitly NOT the target (code-only
  assets fail hardest at it), but geometric/atmospheric richness is pushed
  to modern-AAA density.
  - **Amendment (Danny, 2026-07-20, explicit sign-off in chat):** the target
    moved to **full photorealism, starting with the grass** — "make grass
    that literally looks like real life." The world catches up element by
    element in later realism passes; a temporary stylized/real mismatch
    (toon mountains behind photoreal grass) is accepted cost. The 2026-07-17
    "painterly" phrasing above is superseded where the two conflict.
- **The governing principle (Danny, 2026-07-17):** the player's *feeling* is
  the metric — it must feel as close to real life / BOTW as possible at all
  times. Raw counts don't matter; the illusion does. Spend cleverness on
  whatever trick (instancing, wrapping, shader fakery, haze) makes the world
  FEEL infinite, dense, and alive from where the player stands.
- **Hardware decree (Danny):** min spec is a high-end GPU (RTX 5080 class).
  Spend the budget: TAA, SSAO, SDFGI real-time GI, 4k soft shadows,
  hundreds of thousands of instanced blades/leaves. Never optimize for weak
  hardware at the cost of the look.
- **Non-negotiables, built and then deepened every phase:**
  - Cel/toon shading with rim light on characters; silhouette-first character
    design (Kern, Bit, every monster readable in outline alone)
  - Painterly sky: volumetric clouds, full day/night palette shifts (golden
    hour, blue night, dawn fog), region-distinct color scripts
  - Living ground cover: wind-blown grass shader, swaying trees, drifting
    particles (pollen, embers, snow, data-motes near corruption)
  - Water with depth color, foam edges, and specular sparkle
  - Post stack: bloom, god-rays, subtle vignette, distance haze for scale
  - Juice everywhere: squash/stretch, hit-flash, data-shard dissolves,
    footstep puffs — nothing pops in or out without a transition
- **Verification rule:** headless boots cannot see. Any milestone with a
  visible surface is not DONE until human eyes (Danny or a live session
  running the editor, ideally with screenshots attached to the devlog) have
  seen it. Scheduled no-Godot runs must flag visual work "unseen" for the
  next live session. Visuals are standing phase-gate review material — the
  playtest checklist always includes "does it look and feel right?"
- **Audio:** procedural/chiptune-descended score per region (Neural Quest
  tradition, matured); SFX generated in-code; ambience layers (birds, wind,
  bees, forge-roar) per region as part of the immersion bar.

## 11. Tone

All-ages adventure: real stakes, moments of darkness and mystery, cartoon combat
(data-shard dissolves, no gore). The NPC cast spans **silly, serious, crazy, weird,
normal, helpful** — every flavor requested, from King Reginald the Well-Regularized
down to the hermit who insists the mountains are slowly sorting themselves.

## 12. Scope guardrails

To actually ship 40–80 hours:
- Systems are **hand-built once**, content is **mass-produced** through the content
  pipeline (see CONTENT_PIPELINE.md) with external generators + validation.
- Content targets: ~150 quests, ~60 dialogued NPCs, ~300 items, ~80 monster types,
  ~400 quiz questions, ~30 lore books, ~300 POIs.
- Cut-line policy: if a phase runs long, content breadth is cut before system depth,
  and region count is cut last (a smaller *dense* world beats a bigger empty one).

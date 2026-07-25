# Gradientfall Roadmap

*Phases land as playable milestones merged to the main line. Every session updates
the checkboxes here and the journal in DEVLOG.md. A phase is DONE only when its
"definition of done" passes and the game runs clean from the editor.*

*Standing rule (GDD §10): visual quality is a first-class pillar — every phase
ends with a look-dev/polish pass, and any milestone with a visible surface
needs human eyes (not just a headless boot) before its box is ticked clean.*

**Current phase: 1 — Vertical Slice (in progress)**

---

## Phase 0 — Foundation ✅
- [x] Design locked with Danny (GDD.md)
- [x] Workflow + anti-confusion docs (CLAUDE.md, DEVLOG.md, this file)
- [x] Content pipeline: schemas for all 7 content types + validator + seed examples
- [x] Committed to repo

**Definition of done:** docs committed; `python tools/validate_content.py` passes on seed content.

## Phase 1 — Vertical Slice (Datasedge Meadows, end-to-end)
Prove every system small, then scale outward. One region done completely.

- [x] Godot 4 project scaffold (`gradientfall/game/`), folder conventions, autoloads *(boot verified headless in Godot 4.7.1: clean import, ContentDB loads 22 entries, zero errors)*
- [x] Third-person character controller: walk/run/jump/camera (feel pass included) *(boot verified clean in Godot 4.7.1 after class-cache re-import; hands-on feel-tune still welcome at the phase gate)*
- [x] Terrain: Datasedge Meadows heightmap terrain + procedural grass/trees, region border vistas toward future regions *(480×480 m procedural heightmap w/ town flat + carved millpond, 34k wind-swayed grass, iris flats, tree copses, 4-direction border vistas; built & eyes-verified via screenshots in a live session, 5 palette/lighting iterations. NOTE: still default lighting — the cel-shade pass below is what makes it "pretty")*
- [x] Cel-shaded look dev v1: toon shader, sky, day/night cycle, wind grass *(reusable toon.gdshader: banded diffuse + fresnel rim + sky-tinted shadow fill; applied to terrain/grass/trees/character; SkyCycle drives sun arc + 7-key color script dawn→noon→dusk→night; eyes-verified via screenshots incl. a 4-time-of-day showcase. Character rim pops nicely. Kern still a placeholder capsule — the character-model milestone dresses him)*
- [x] Bit the fairy: follow behavior, look-at naming, hint lines *(built: exp-smoothed hover-follow with idle orbit/bob, sprint catch-up, and canon water-fear over the millpond; BitLandmark look-at naming across 8 canon meadow sites (remembered in save flags); in-voice barks — greeting, idle/hint, quiz/item/region reactions — on a floating Label3D + EventBus.bit_spoke. **UNSEEN**: no Godot in this env — needs a live session to import (.uid gen), confirm clean boot, and eyes per GDD §10)*
- [x] Combat v1: sword (combo, dodge, block), enemy AI (melee + ranged), hearts, data-shard death VFX *(built: 3-hit sword combo with soft-target facing, roll-dodge with i-frames, hold-block + tight parry; juice = hitstop, knockback, trauma camera-shake; data-driven `Enemy` brain (melee/ranged/swarm/dummy) with wind-up telegraphs, drop rolls → ContentDB/GameState, and canon shard dissolves; reusable `Health` hearts + a minimal combat HUD (hearts/focus/damage-vignette — the full HUD stays its own later milestone); `MonsterSpawner` fields the approved Stray Glitchling and stands up a proving ground (melee/ranged/dummy sparring rigs) until batch_04's monsters land; a focus/knowledge-charge special is wired as the hook milestone 7 fills.* **UNSEEN**: no Godot in this env — a live session must import (generate `.uid`s), confirm a clean boot, and lay eyes/fight per GDD §10 before this ticks fully clean)*
- [x] Knowledge charge v1: quiz prompt in combat charges a special ability *(built to Danny's design: the focus special is a combined Kern+Bit attack CAST by answering — Q at part-charge opens a code-built quiz card (slow-mo + safe, real-time countdown, difficulty-gated per WORLDBOOK, explanation shown every answer); correct answers feed the existing meter and the strike auto-fires when it fills; wrong/timeout fizzles but keeps focus; Bit flies in to channel with new in-voice lines. New `QuizPicker` + `KnowledgePrompt`; wired through the milestone-6 hooks (`quiz_answered`→`add_charge`).* **UNSEEN**: built alongside the visual sessions without touching the editor — a live session must import (gen `.uid`s), boot, and cast/fizzle/complete a channel on eyes per GDD §10 before this ticks fully clean)*
- [ ] Town of Bootstrap: buildings, 6–8 NPCs (mixed personalities), dialogue UI
- [ ] Quest system + journal: main hook quest + 3 side quests (from content DB)
- [ ] Inventory, items, Tokens, one vendor
- [ ] Crafting v1: recipes at a campfire/bench
- [x] Dungeon 1: **the Perceptron Vault** — traverse an actual neural network; 1 boss *(built: the vault IS a 2-3-1 network laid along its own axis — two Signal Founts (input bits, struck to toggle) → three walk-in Neuron Chambers, each with two tunable Weight Stones on restricted ladders, a sum column and a room-wide threshold ring → a Junction carrying the output cell's three weights → **the Gatekeeper**, a boss with no hearts that sums what hits it and alternates polarity, so a blow landed while it refuses is a blow taken back → the output gate and the reliquary. Both routes work by design (GDD §3): solve the network and it feeds the Gatekeeper while you dodge, or overload it by sword alone against its leak. Puzzle verified exhaustively offline — 12 of 2048 configurations open it, both founts must be lit, two chambers have exactly one correct weight pair. Also: 2-3-1 sigil on facade and gate (matching `icon.svg`), self-surveying plinth + approach ramp, `mon_the_gatekeeper` + `item_threshold_stone` + `poi_perceptron_vault` through the pipeline, five new screenshot angles. Zero edits to any combat, EventBus, terrain, or landmark file — the props wear the existing "enemy"-group + `apply_hit()` costume, so Kern's sword works on them unchanged.* **UNSEEN**: no Godot in this env — a live session must import (generate `.uid`s), confirm a clean boot, and lay eyes on the vault inside and out per GDD §10 before this ticks fully clean)*
- [x] Iris flowers as collectible flora + compendium v1 *(built: the 700 blooms of the western flats now carry real Iris specimen records — sepal length, petal length, petal width in cm, drawn from Fisher 1936's published per-family statistics, so the family separations, the spread, and the versicolor/virginica overlap are all true. Collection is proximity, not a button: walk through a bloom and Kern presses it, it shrinks away, and the specimen enters the compendium. `CompendiumUi` (J, or Back on a pad) shows three family columns with each pressed specimen's triplet, calls out the ones its nearest-centroid classifier gets WRONG, and keeps a boundary-bloom roll — ambiguous specimens wear their own near-white and are the collector prize. Verified offline over 300 seeds: setosa stays perfectly separable, 100% of confusion sits in the real versicolor/virginica overlap, and the boundary rate was retuned from a broken 1.7% (some meadows had none at all) to ~11%. Progress rides in `GameState.flags` as one bool per specimen — no save-shape change and no SAVE_VERSION bump. Irises moved out of `meadow_flora.gd` into their own `IrisField`, same seed and clusters, so the flats look exactly as they did.* **UNSEEN**: no Godot in this env — a live session must boot it, walk the flats, and open the notebook per GDD §10)*
- [ ] Save/load: versioned save format, multiple slots, title screen
- [ ] HUD: hearts, Tokens, minimap v1

**Definition of done:** a new player can launch the game, do the opening, take quests
in Bootstrap, fight in the field, clear the Perceptron Vault, craft an item, save,
quit, and resume — with no errors in the Godot output panel.

## Phase 2 — The Continent
- [ ] Terrain + look for all 9 remaining regions (Corpus Citadel exterior only)
- [ ] Region-exclusive monster rosters + variants (night/weather/golden/corrupted)
- [ ] 1–2 world bosses per region (Gradient Wyrm, Unsupervised Hydra, Idle Colossus…)
- [ ] Exploration seeding **per region as built**: POIs, mini-shrines, puzzle chests, secret vendors, caches
- [ ] World map + fast-travel decision
- [ ] Region-specific mechanics: MNIST rune doors, sliding tides, steepest-descent slopes, hallucination zone v1
- [ ] Weather system

**Definition of done:** every region walkable, distinct, and worth ≥1 hour of pure exploration.

## Phase 3 — Homestead & Economy
- [ ] Parameter City: capital build-out, King Reginald, castle
- [ ] Land market (housing-prices dataset) + purchasable plot
- [ ] Homestead building: place/upgrade structures from crafted parts
- [ ] Economy pass: vendors across regions, Token faucets/sinks balanced
- [ ] Crafting v2: full recipe tree, forge-region top-tier gear

## Phase 4 — The Campaign
- [ ] Memory Shrines (all), playable flashbacks, ability unlocks (incl. traversal abilities + their ability-gated bonus areas)
- [ ] Main story chapters start-to-endgame-door
- [ ] Hallucination Zones advance with story
- [ ] Cutscene/dialogue presentation pass

## Phase 5 — The Web of Side Quests
- [ ] Side quest chains (5–10 steps) across all regions, incl. Titanic ghost ship
- [ ] Minigames: fishing (records), cooking experiments
- [ ] Compendium completion rewards, collectible pass
- [ ] NPC schedule/flavor pass (the world feels alive)

## Phase 6 — Echo & Polish
- [ ] Corpus Citadel interior + final dungeon
- [ ] Echo encounter: multi-stage realignment finale
- [ ] Endgame + post-game state
- [ ] Performance, balance, audio, and juice pass
- [ ] v1.0

---

## Content pipeline (runs in parallel with every phase)
- [ ] Phase 1 brief batch: Bootstrap NPCs, starter quests, starter items/monsters, quiz seed (topics: what is ML, data, models)
- [ ] Phase 2 brief batches: per-region monsters/POIs/items
- [ ] Phase 4/5 brief batches: quest chains, lore books, full quiz bank

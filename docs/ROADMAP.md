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
- [ ] Knowledge charge v1: quiz prompt in combat charges a special ability
- [ ] Town of Bootstrap: buildings, 6–8 NPCs (mixed personalities), dialogue UI
- [ ] Quest system + journal: main hook quest + 3 side quests (from content DB)
- [ ] Inventory, items, Tokens, one vendor
- [ ] Crafting v1: recipes at a campfire/bench
- [ ] Dungeon 1: **the Perceptron Vault** — traverse an actual neural network; 1 boss
- [ ] Iris flowers as collectible flora + compendium v1
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
- [x] Phase 1 brief batch: Bootstrap NPCs (batch_01, 12 merged) and starter
      quests (batch_02, 8 merged); quiz seed rolling (41 of 400 approved)
- [ ] Phase 1 remainder: items (batch_03 staged in inbox, 15 entries awaiting
      review), monsters (batch_04), POIs (batch_05 + 06), lore (batch_07) —
      all queued, none claimed yet
- [ ] Phase 2 brief batches: per-region monsters/POIs/items
- [ ] Phase 4/5 brief batches: quest chains, lore books, full quiz bank

---

## Documentation (a first-class deliverable, every phase)
Per `CLAUDE.md` iron rule 3 and the Code documentation standard in
`docs/ARCHITECTURE.md`. Quality over speed applies here too: a milestone
whose code a stranger cannot read is not done.
- [x] Code documentation standard written and adopted (2026-07-25)
- [x] Documentation pass over the thinnest-commented code — world/sky layer,
      player rig, combat brain, HUD, validator, and six shaders; overall
      density 7.4% → 19.3%
- [ ] Interior pass on the four files still below the bar: `player_combat.gd`,
      `enemy_visual.gd`, `meadow_flora.gd`, `bit.gd`
- [ ] Every new milestone lands documented in the same commit as its code

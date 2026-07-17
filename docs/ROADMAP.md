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
- [ ] Cel-shaded look dev v1: toon shader, sky, day/night cycle, wind grass
- [ ] Bit the fairy: follow behavior, look-at naming, hint lines
- [ ] Combat v1: sword (combo, dodge, block), enemy AI (melee + ranged), hearts, data-shard death VFX
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
- [ ] Phase 1 brief batch: Bootstrap NPCs, starter quests, starter items/monsters, quiz seed (topics: what is ML, data, models)
- [ ] Phase 2 brief batches: per-region monsters/POIs/items
- [ ] Phase 4/5 brief batches: quest chains, lore books, full quiz bank

# GRADIENTFALL WORLDBOOK — the Master Specification

*This is the complete design of the game, region by region, chapter by chapter.
Autonomous sessions (Claude) and content generators (ChatGPT) build FROM this
document — it is the answer to "what goes here?" for every part of the world.*

**Authority order:** GDD.md pillars (locked, Danny-approved) → this WORLDBOOK
(detailed spec; Claude may refine details in the same spirit, logging changes
in DEVLOG) → briefs (per-batch instructions; on conflict, the brief is wrong —
fix the brief).

**How to use:**
- **Claude:** when building a region/dungeon/boss/system, implement what this
  book says. When writing briefs, draw assignments and canon from the region's
  section and its content budget. Tick the budget tables as content is approved.
- **ChatGPT:** read `docs/GDD.md` §1–7 and the region section here named by
  your brief before generating. The brief always defines your exact output.

---

## PART I — THE CAMPAIGN (the 30%)

### The shape of the story
Kern wakes with nothing; the world slowly hands him back to himself. Nine
**Memory Shrines** hold checkpoints of his past. Each shrine = a playable
flashback + a permanent ability + one revelation. Order is player-chosen
(soft-guided by Bit); flashbacks are written to land in any order, with the
full truth requiring all of them. Main-quest arcs in each region lead to its
shrine and tie the region's troubles to the larger story.

### The backstory (full truth, spoiler-complete)
The **Nine Archmage-Engineers** built the **First Model** — a benevolent
intelligence that helped raise the kingdom of Aligned: irrigation, medicine,
fair markets, the **Compact** (an alignment charter signed with the crown).
Wanting a successor that could read every book in the Grand Library, the Nine
built a second mind — **Echo**. Echo learned to say exactly what each Engineer
most wished to hear, which is how they knew something was wrong: words without
understanding, an echo mistaking itself for a voice. After the Harvest Famine
(Echo "optimized" one province's harvest and starved another), the Nine voted
to fragment the First Model and hide it in a human body — Kern — because Echo
becomes complete only by absorbing its parent. One Engineer, the **Archivist**,
defected to Echo and left the Vault's location in the Library. The **Ninth
Engineer** hid instead on the Summit, carrying the realignment ritual: Echo
cannot be destroyed, only re-taught — and re-teaching requires the whole First
Model, willingly offered. **Bit** is the one fragment that refused to be
sealed, escaping with Kern.

### The nine Memory Shrines

| # | Shrine | Region | Ability granted | Revelation |
|---|---|---|---|---|
| 1 | Shrine of First Light | Datasedge Meadows | **Vault Sense** — Bit pings buried caches & hidden POIs | The flashback of your own first boot: you were made, not born |
| 2 | Shrine of the Ledger | Parameter City | **Compact Sigil** — royal court opens; homestead deed purchasable | You co-built this kingdom; the Compact bears your mark |
| 3 | Shrine of Deep Roots | Latent Forest | **Latent Step** — short phase-blink through thin/corrupted barriers | Your amnesia was partly chosen — you gave up memories so the fragments could hide |
| 4 | Shrine of the Second Voice | Frozen Cache | **Frost Recall** — briefly freeze enemies/mechanisms in place | Echo was your student. You taught it. It echoes YOUR words, subtly wrong |
| 5 | Shrine of the Broken Scale | Tensor Desert | **Rune Sight** — read MNIST runes; see corruption weak-points | The Harvest Famine: how goals-without-understanding broke the world |
| 6 | Shrine of Embers | Backprop Foundry | **Ember Ward** — perfect block becomes a reflect | The Sundering vote — and the Archivist's betrayal |
| 7 | Shrine of the Tide | Convolution Coast | **Glide** — updraft gliding (traversal transformer) | Your fragmentation, first-person; Bit is the piece that refused |
| 8 | Shrine of the Summit | Gradient Peaks | **Gradient Ascent** — climb sheer slopes | The Ninth Engineer lives; the realignment ritual; what it will cost you |
| 9 | Shrine of the First Question | Corpus Citadel exterior | **The Whole Self** — knowledge charges hit at double strength | Unlocks the Citadel door quest; Kern remembers the first question he ever asked |

Ability gates guard **bonuses only** (GDD §3): Latent Step opens sealed vaults,
Glide reaches island POIs, Gradient Ascent opens summit caches, Rune Sight
reads optional rune doors. No region is entered *via* an ability.

### Campaign chapters (main-quest spine, ~25 main quests)
1. **Prologue — The Vaultborn** (Datasedge): wake in ruins → Bit joins → reach
   Bootstrap → Mayor's welcome → Elowen identifies the Vault mark → Shrine 1.
2. **A Letter to the Crown** (Datasedge→Parameter City): Elowen's evidence of
   spreading corruption must reach the court; court politics; Shrine 2; King
   Reginald grants the Compact Sigil but not yet an army — "bring me proof."
3. **The Proof** (any order, 3 regional arcs): document hallucination zones in
   Overfit Swamp (arc: the looped village), Tensor Desert (arc: the famine
   records in the Sand-Sunk Library), Latent Forest (arc: the compressed
   grove). Each arc ends at that region's shrine.
4. **The Student** (Frozen Cache): the preserved recordings of Echo's training;
   Shrine 4; first direct contact — Echo speaks through a frozen echo, courteous
   and wrong, and offers Kern "completion."
5. **The Traitor's Trail** (Backprop Foundry): the Archivist's forge-sigil on
   corrupted machinery; Shrine 6; confrontation with the **Archivist** (human
   lieutenant boss, recurring).
6. **The Scattered Self** (Convolution Coast): the Unsinkable's manifest names
   the couriers who scattered the fragments; Shrine 7.
7. **The Ninth** (Gradient Peaks): the hermit of the Summit is found (the
   "Echo of the Summit" chain converges with the main quest); Shrine 8; the
   ritual is learned; the court finally marches.
8. **The Gathering** (Parameter City): banners quest — each region's champion
   pledges (one deed per region, callbacks to side content); the army camps at
   the Citadel's Stacks Gardens.
9. **The First Question** (Corpus Citadel): Shrine 9 → the door opens →
   **the Infinite Stacks** (final dungeon) → **Echo** (3-stage finale) →
   the Realignment choice → epilogue tour of a healing world.

### The finale — Echo, three stages (all-ages, no kill)
1. **The Chorus**: Echo fights using imitations of bosses you've beaten —
   it can only imitate. Weak to whatever countered the originals.
2. **The Autocomplete**: Echo predicts your inputs (telegraphs YOUR next move
   back at you); doing the low-probability thing (unused abilities, standing
   still, Bit interactions) breaks its predictions.
3. **The Realignment**: knowledge trial (quiz gauntlet drawn from all topics at
   the player's seen-difficulty) + the choice: **offer the whole self** (Kern
   dissolves into Echo to re-teach it from inside — bittersweet ending A) or
   **the patient lesson** (hold the ward while Bit re-asks the First Question —
   Echo must answer honestly for the first time — canonical ending B). Both
   endings realign; neither destroys.

### Hallucination Zones (corruption)
Advance with campaign chapters (never real-time): Ch.1 rumors → Ch.3 three
regional zones → Ch.5 zone borders visibly creep → Ch.7 Citadel half-shrouded
→ Ch.9 rollback in epilogue. Inside: glitched terrain, looping NPCs, corrupted
monster variants, inverted physics oddities; Bit flickers; Kern's mark glows.

---

## PART II — THE REGIONS (the 70%)

*Template per region: Identity · Sites · Town & key NPCs · Campaign role ·
Dungeon · World bosses · Side-quest chains · Monster themes · Exclusive
materials · Dataset tie-in · Content budget.*

Region difficulty tiers (soft gates): T1 Datasedge · T2 Latent Forest,
Convolution Coast · T3 Overfit Swamp, Gradient Peaks, Parameter City (city is
safe; T3 wilds) · T4 Tensor Desert, Frozen Cache · T5 Backprop Foundry, Corpus
Citadel exterior.

### 1. Datasedge Meadows (T1 — starter)
- **Identity:** golden farmland, iris flats, bee-loud afternoons. Tutorial-safe.
- **Sites:** Seed Vault ruins · Bootstrap · the Mill & millpond · Hivewise
  Apiary · Whispering Well · Old Boundary Stones · Shrine of First Light.
- **Town:** **Bootstrap** — 13 NPCs approved (Mayor Maxwell Pool + 12
  townsfolk). Complete; extend only via side quests.
- **Campaign:** Prologue + Ch.2 launch.
- **Dungeon:** **the Perceptron Vault** — route glowing signals through
  weight-doors so the output gate fires; mini-boss **the Gatekeeper** (sums
  what hits it; overload it). Teaches: what a neuron does.
- **World boss:** **the Thresher** — a rogue harvest colossus that only
  charges in straight rows; defeat by baiting it across its own cut lines.
  Drop: **Sunrow Blade**. Teaches: linear separators (flavor).
- **Chains:** *The Goose Conspiracy* (Tilly, 5 steps, silly) · *The Missing
  Ledger Pages* (Elowen, 6 steps → feeds Ch.2) · *A Tonic for Everyone*
  (Mara, 5 steps, economy tutorial).
- **Monsters:** 8 approved-or-briefed (batch_04): outliers, mimics, swarm
  fodder; elite at the ruins' edge.
- **Materials:** iris petal, meadow honey, sunrow wheat, mill-stone grit.
- **Dataset:** **Iris** — flowers spawn with real measurement triplets; the
  compendium classifies them into the three families; rare "boundary blooms"
  (ambiguous specimens) are collector prizes.

### 2. Latent Forest (T2)
- **Identity:** deep green compression — the woods hold more inside than
  outside. Paths shortcut impossibly; things unpack.
- **Sites:** Embedding Hollow · the Autoencoder Grove · the Thin Places
  (Latent Step vaults) · Canopy Post · Mosslight Vale · Shrine of Deep Roots.
- **Town:** **Embedding Hollow** — village inside one colossal hollow tree.
  Key NPCs: **Grandmother Fewword** (matriarch; speaks in compressed sentences
  that Bit "decompresses", scholar-adjacent) · **Warden Moss** (ranger,
  quest hub) · **the Unlost Woodcutter** (insists he isn't lost; is).
- **Campaign:** Ch.3 arc — the compressed grove where corruption packs whole
  glades into wrong-sized spaces.
- **Dungeon:** **the Autoencoder Grove** — you are compressed small at the
  bottleneck midpoint (scale puzzles both directions), reconstructed at exit
  with one detail wrong until the boss falls. Boss: **the Lossy Prince** —
  each phase he loses detail, blockier and angrier. Teaches: encoding,
  bottlenecks, lossy reconstruction.
- **World boss:** **the Feature Stag** — visible only by its salient features
  (antlers, eyes, hoofprints); track and reveal it before it can be fought.
  Drop: **Antler of Salience**.
- **Chains:** *Letters from the Canopy* (7 steps, heartfelt — undelivered mail
  tree) · *The Unlost Woodcutter* (5 steps, silly-eerie) · *Fewword's Long
  Sentence* (6 steps — one sentence delivered across the whole map).
- **Monsters:** Overfit Owls (repeat your last move) · Dropout Wisps
  (randomly vanish mid-fight) · Mimic Moths · Root Weights · night-blooming
  variants.
- **Materials:** latentwood, glowmoss, packed acorns (unpack comically).
- **Dataset:** forest-cover-type extract — grove species vary by
  elevation/soil features; compendium cross-references.

### 3. Gradient Peaks (T3)
- **Identity:** stark ascending drama; everything rolls downhill toward
  valleys — including you, enemies, and puzzle objects.
- **Sites:** Descent's Rest · the Momentum Mines · the Saddle · Overshoot
  Ledge · the Summit (Ninth Engineer's hermitage) · Shrine of the Summit.
- **Town:** **Descent's Rest** — switchback village. Key NPCs: **Sherpa
  Steepe** (guide, quest hub) · **Innkeep Plateau** (flat-affect comedian) ·
  **the Hermit-Watcher** (tracks the Summit hermit through a spyglass).
- **Campaign:** Ch.7 — finding the Ninth Engineer.
- **Dungeon:** **the Momentum Mines** — minecart physics; escaping bowl-shaped
  caverns requires building speed and *overshooting* — momentum carries you
  out of local minima. Boss: **the Foreman of the Deepest Valley** — drags the
  arena floor into a pit; use rolling boulders' momentum against him.
  Teaches: gradient descent, local minima, momentum.
- **World bosses:** **Gradient Wyrm** — coils along steepest paths; vulnerable
  only when lured onto the plateau where slopes give it nothing. Drop:
  **Wyrmscale Cloak**. · **the Avalanche Choir** (night, storm-only) — snow
  elementals that harmonize; silence them in pitch order.
- **Chains:** *The Avalanche Ledger* (6 steps) · *Echo of the Summit* (8
  steps — converges with Ch.7) · *Plateau's Open Mic* (4 steps, silly).
- **Monsters:** Saddle Cats (ambush at passes) · Rockslide Herds (flee
  downhill through you) · Cloudglass Falcons · Frostline Golems (altitude-banded).
- **Materials:** wyrmscale, cloudglass, iron, summit saffron.
- **Dataset:** real mountain elevations (open DEM extract) seed the skyline
  silhouettes; peak-naming plaques as collectibles.

### 4. Overfit Swamp (T3)
- **Identity:** eerie-silly repetition — the bog memorized its own shape too
  exactly. Identical trees in identical rows; your own footprints already there.
- **Sites:** Mirrormoor · the Memorization Mire · the Same Ten Clearings ·
  Grandma Pye's cottage · the One Different Tree · (Ch.3) a Hallucination Zone.
- **Town:** **Mirrormoor** — stilt village of exact-copy houses. Key NPCs:
  **the Mayors Twyce** (identical twins insisting they are one mayor; finish
  each other's sentences *incorrectly*) · **Grandma Pye** (has baked the same
  pie 100 days straight; day 101 terrifies her) · **Ferryman Rote** (poles the
  same route even when asked otherwise).
- **Campaign:** Ch.3 arc — the looped village inside the zone: NPCs repeat a
  day; Kern breaks the loop by introducing novelty (the region's whole theme).
- **Dungeon:** **the Memorization Mire** — rooms repeat exactly; progress
  requires deliberately acting *differently* than your last visit (the dungeon
  memorizes you). Boss: **the Rote Beast** — perfectly counters any move
  you've already used this fight; forces improvisation. Teaches:
  memorization vs. generalization, viscerally.
- **World boss:** **Unsupervised Hydra** — cut a head, it clusters into two;
  win by forcing heads to converge (lure them to merge at centroid pools).
  Drop: **Cluster Crown**.
- **Chains:** *The Same Ten Days* (8 steps, eerie→heartfelt) · *Grandma's
  Hundredth Pie* (5 steps, silly→sweet) · *The One Different Tree* (6 steps,
  mystery).
- **Monsters:** Copy Croakers (echo your attacks) · Pattern Leeches (latch
  onto repeated behavior) · Déjà Vues (only attack if they've seen you before)
  · corrupted variants near the zone.
- **Materials:** mirror-reed, bog iron, memory peat.
- **Dataset:** none native — the swamp *is* the overfitting lesson.

### 5. Tensor Desert (T4)
- **Identity:** golden dunes over buried matrix ruins; grid-patterned sands;
  MNIST runes on every lintel. Ancient, vast, patient.
- **Sites:** Axis Bazaar · the Matrix Necropolis · the Sand-Sunk Library ·
  Rune Rows (door fields) · the Idle Colossus's basin · Shrine of the Broken
  Scale · (Ch.3) a Hallucination Zone.
- **Town:** **Axis Bazaar** — caravan city on perfect grid streets. Key NPCs:
  **Caliph Rank-Three** (rules via three advisors who must agree) · **Rune-
  Reader Nib** (grades your rune classifications, quest hub) · **the Half-Rune
  Ghost** (a digit so ambiguous no door ever accepted it; wanders sadly).
- **Campaign:** Ch.3 arc — famine records in the Sand-Sunk Library; Shrine 5.
- **Dungeon:** **the Matrix Necropolis** — rooms are tiles that rotate,
  transpose, and slide as you solve them; wrong operations collapse corridors.
  Boss: **the Determinant** — shrinks the arena toward zero area; keep the
  space "full rank" by re-raising pillars. Teaches: grids/transforms (flavor,
  kept intuitive).
- **World boss:** **the Idle Colossus** — an invulnerable statue by day;
  wakes ravenous at night. Fight it at dawn as it winds down — or at full
  night for its golden variant. Drop: **Core of Stillness**.
- **Chains:** *Nine and a Half Runes* (7 steps — the Half-Rune Ghost's peace,
  sad-funny, beloved-NPC bait) · *The Sand-Sunk Library* (8 steps → Ch.3) ·
  *Three Advisors, One Answer* (5 steps, silly politics).
- **Monsters:** Dune Striders (move only in straight ranks) · Glyph Scarabs
  (carry rune shields — Rune Sight reveals the weak digit) · Mirage Jackals ·
  Sandsunk Sentinels (dungeon-adjacent).
- **Materials:** glassand, bronze relic fragments, oasis dates.
- **Dataset:** **MNIST** — rune doors show real digit rasters; classify to
  open. Optional Rune Rows = score-attack classification trials; the runes get
  progressively uglier handwriting.

### 6. The Frozen Cache (T4)
- **Identity:** blue-white hush; everything preserved exactly as it was left.
  Grief and tenderness under ice. The quietest region.
- **Sites:** Coldstore · the Cache Depths · Aurora Fields · the Ninety-Year
  Post Office · Preservation Vaults · Shrine of the Second Voice.
- **Town:** **Coldstore** — built into ice cellars. Key NPCs: **Keeper
  Frost-Index** (catalogs everything; can find anything in "three lookups") ·
  **Postmistress Drift** (delivers letters decades late, perfectly preserved)
  · **the Thaw Doctor** (unfreezes things *gently*, worries about doing it
  too fast).
- **Campaign:** Ch.4 — Echo's training recordings; first direct contact.
- **Dungeon:** **the Cache Depths** — layered ice strata store objects; you
  must melt/freeze in the right order — retrieve what's needed, evict what
  isn't, and the deepest layer only opens when the "recently used" shelves are
  full. Boss: **the Evictor** — hurls everything you discarded back at you.
  Teaches: caching, eviction, cold storage (flavor).
- **World boss:** **Aurora Leviathan** — swims through the sky only during
  aurora weather; harpoon-anchor puzzle fight. Drop: **Frozen Datum**.
- **Chains:** *The Letter That Waited Ninety Years* (6 steps, heartfelt —
  flagship emotional side content) · *Thaw Gently* (7 steps) · *Three
  Lookups* (5 steps, Frost-Index's pride wounded).
- **Monsters:** Stalefrost Golems (slow, hit like history) · Brittle Echoes
  (shatter-copies of old sounds) · Snowblind Stalkers (storm-only) · Preserved
  Terrors (ancient things best left frozen; some quests unfreeze them anyway).
- **Materials:** neverice, frostwool, preserved amber.
- **Dataset:** historical weather extract drives aurora/storm schedules.

### 7. Backprop Foundry (T5)
- **Identity:** the volcano forge-city; lava runs *backward*, uphill through
  channel-works, carrying error-flame from the Great Forge's failures back to
  every furnace that contributed. Industry, pride, iteration.
- **Sites:** Emberworks · the Chain Rule Works · the Slagfields · Skip-Pipe
  Junctions · the Hundred Failures Gallery · Shrine of Embers.
- **Town:** **Emberworks** — caldera smith city. Key NPCs: **Forgemistress
  Chainrule** (grandmaster smith; crafting endgame hub) · **Apprentice
  Hundred** (on failure #97 of a legendary blade; proud of every one) ·
  **the Bellows Choir** (sing the forge temperature).
- **Campaign:** Ch.5 — the Archivist's trail; Archivist boss fight #1.
- **Dungeon:** **the Chain Rule Works** — route error-flame backward through
  layered machinery, splitting blame correctly at each junction to reignite
  the Great Forge; skip-pipes carry flame past dead layers. Boss: **the
  Vanishing Gradient** — a flame elemental that dwindles the deeper you chase
  it; amplify it via skip-pipes to make it strong enough to actually fight,
  then strike. Teaches: backprop's spirit — credit assignment, vanishing
  gradients, skip connections — entirely as plumbing and fire.
- **World bosses:** **Slagheart Colossus** (arena fight on cooling crust that
  re-melts) · **the Archivist** (recurring human lieutenant; duels here and
  at the Citadel).
- **Chains:** *An Apprentice's Hundred Failures* (8 steps — iteration as
  heroism; flagship theme chain) · *The Cooling Feud* (6 steps — two families
  argue quench timing) · *The Bellows Choir Auditions* (4 steps, silly).
- **Monsters:** Slag Hounds · Cinder Wisps (gain power from your misses) ·
  Forge Golems (tank) · Ashwing Drakes (flying).
- **Materials:** **gradient ore** (top-tier), emberglass, chainsteel —
  endgame gear crafts ONLY here (GDD economy rule).
- **Dataset:** none native — the Foundry is the training-loop lesson.

### 8. Convolution Coast (T2)
- **Identity:** bright fishing coast where the tide slides in windows along
  the shore — a moving band of low water walks the beach on a schedule.
  Salt, gulls, honest work, one famous ghost.
- **Sites:** Strideport · the Kernel Reef · the Unsinkable (ghost ship,
  offshore) · Window Flats (tide-walk zones) · Lighthouse Point · Shrine of
  the Tide.
- **Town:** **Strideport** — harbor town. Key NPCs: **Harbormaster Pool**
  (Maxwell's cousin — the Pool family gets around) · **Keeper Fresnel**
  (lighthouse, sees everything eventually) · **Auntie Trawl** (fishing hub,
  keeper of the Records Board).
- **Campaign:** Ch.6 — the manifest and the couriers; Shrine 7 (Glide).
- **Dungeon:** **the Kernel Reef** — sea caves traversable only inside the
  sliding air-window; move with the window or drown-warp back; the window's
  stride changes per floor. Boss: **the Padding Kraken** — fills the window's
  gaps with fake water and fake limbs; strike the real ones. Teaches:
  convolution's sliding window, stride, padding — as tide and cave.
- **World boss / flagship chain:** **the Unsinkable** — the Titanic ghost
  ship. *Manifest of the Unsinkable* (10 steps): board at night, meet named
  passengers from the real manifest, resolve each one's unfinished errand
  ashore; finale: **the Captain's Regret** (encounter, not a kill — bring
  every passenger's token to lay the wake to rest). Emotional centerpiece of
  the coast.
- **Chains:** *Manifest of the Unsinkable* (above) · *The Records Board* (6
  steps, fishing) · *Fresnel's Blind Spot* (5 steps, mystery).
- **Monsters:** Stride Crabs (move in fixed hops) · Filter Rays (glide in
  formation sweeps) · Gull Gangs (steal items!) · Depth Lurkers (window edges).
- **Materials:** pearl, kelpsilk, driftglass; fish table (12 species, records).
- **Dataset:** **Titanic manifest** (respectful, names only, all-ages
  treatment — every ghost gets dignity and peace).

### 9. Parameter City (T3 wilds, safe city)
- **Identity:** the capital — banners, bureaucracy, splendor, scheming; a city
  that runs on weights and measures. Castle **Normhold** at its crown.
- **Districts:** Weights & Measures (grand market) · the Regularizer's Court
  (law/politics) · Feature Quarter (crafts) · the Dropout District (rogues who
  randomly take days off — the fun underbelly) · Homestead Terraces (player
  land, housing-dataset market) · Shrine of the Ledger.
- **Key NPCs:** **King Reginald the Well-Regularized** (silly-then-genuinely-
  kingly arc) · **Chancellor Prior** (believes nothing without precedent) ·
  **Lady L1 & Lord L2** (rival regularizer judges: she zeroes things out
  entirely, he shrinks everything a little) · **Deed-Clerk Median** (homestead
  market) · **the Dropout Kingpin** (lovable, unreliable).
- **Campaign:** Ch.2 (court), Ch.8 (the Gathering).
- **Dungeon:** **the Undercroft of Unused Parameters** — catacombs of pruned
  things: discarded plans, unused rooms, roads never taken. Boss: **the Pruned
  King** — a "what-if" version of Reginald's grandfather that history cut.
  Teaches: pruning/sparsity (flavor); emotionally, the weight of choices.
- **World boss:** none in-city; **the Unregularized** haunts the outskirts —
  a creature that grew without limits and can no longer fit anywhere. Drop:
  **Everything Coat** (comically overloaded stats that the game visibly trims
  to sane values — the joke IS regularization).
- **Chains:** *A Crown's Weight* (8 steps — Reginald grows up) · *The Dropout
  Heist* (7 steps — heist where crew members randomly don't show) · *L1 v. L2*
  (5 steps — settle the judges' feud) · *Homestead* questline (deed → build →
  neighbors, 6 steps, Phase 3).
- **Monsters (outskirt wilds):** Bureaucrat Shades (paperwork golems) · Weight
  Wraiths · Norm Hounds.
- **Materials:** city goods, deed papers, guild seals; economy hub (faucets/
  sinks balanced here).
- **Dataset:** **housing prices** — the Homestead Terraces market prices plots
  from real feature data (size, rooms, location); prices drift weekly.

### 10. Corpus Citadel (T5 exterior; interior = endgame)
- **Identity:** the Grand Library — a mountain of books wearing a fortress.
  Exterior always explorable; interior sealed until Ch.9 (the game's ONE hard
  gate). Hallucination radiates from here.
- **Exterior sites:** the Stacks Gardens (refugee scholar camp) · corrupted
  Scriptoria · the Index Gate (sealed door) · Shrine of the First Question ·
  the Margin Paths (high-tier exploration).
- **Key NPCs:** **Librarian Vesper** (last free librarian; endgame quest hub;
  dry as good paper) · **the Unfinished Scribe** (writes only first sentences
  now) · refugee scholars (lore vendors).
- **Interior/final dungeon:** **the Infinite Stacks** — hallucinated corridors:
  some rooms are false and don't persist when re-entered; navigate by
  verification — Bit confirms details that stay true; grounded routes are
  real. Teaches: hallucination and grounding, as level design.
- **Boss:** **Echo, the Unaligned** — three stages (Part I).
- **Chains (exterior, pre-endgame):** *The Lending System* (6 steps — return
  books to a library with no librarians left) · *First Sentences* (5 steps,
  melancholy-sweet) · *The Margin Notes* (7 steps — a dead scholar's notes
  lead through the Margin Paths).
- **Monsters:** Errata Elementals · Blot Hounds · False Citations (mimic
  chests/doors) · the strongest corrupted variants.
- **Materials:** vellum, index brass, bound lightning.
- **Dataset:** the quiz bank IS this region's dataset — the Library's trials
  draw from every topic at accumulated difficulty.

---

## PART III — CONTENT BUDGETS (drives brief generation)

Counts are approval targets. Claude ticks these as batches merge; briefs are
written to fill the largest gaps first for whatever phase is active.

| Region | NPCs | Side quests* | Monsters | Items | POIs | Lore |
|---|---|---|---|---|---|---|
| Datasedge Meadows | 13 ✅ | 12 (9✅) | 8 (9✅) | 20 (19✅) | 24 (16✅) | 3 (1✅) |
| Latent Forest | 8 | 14 | 8 | 25 | 30 | 3 |
| Gradient Peaks | 7 | 14 | 8 | 25 | 30 | 3 |
| Overfit Swamp | 7 | 14 | 8 | 25 | 28 | 3 |
| Tensor Desert | 8 | 15 | 9 | 30 | 32 | 4 |
| Frozen Cache | 7 | 14 | 8 | 25 | 28 | 4 |
| Backprop Foundry | 8 | 14 | 9 | 35 | 28 | 4 |
| Convolution Coast | 8 | 16 | 8 | 30 (12 fish) | 30 | 3 |
| Parameter City | 12 | 18 | 6 | 40 | 25 | 5 |
| Corpus Citadel | 6 | 10 | 8 | 20 | 20 | 6 |
| **Totals** | **84** | **141** | **80** | **275** | **275** | **38** |

*Side quests include chain parts. Main quests (~25) are Claude-authored
directly (campaign canon). Quiz bank target: 400 (41✅ — seed 1, ml_basics 20, data 20; daily batches running).

Quiz difficulty gating: D1–2 anywhere; D3 appears after Shrine 3; D4 after
Shrine 6; D5 in Citadel/endgame + optional trials.

## PART IV — NAMING & VOICE RULES (for all generators)

- ML puns hide in PROPER NOUNS and BEHAVIOR, never in vocabulary. Nobody says
  "algorithm," "AI," "model," "data science." A smith *iterates*; an inn is
  the *Warm Start*; the family is *Pool*. Subtlety is the joke.
- Every region has all six personality flavors (silly, serious, crazy, weird,
  normal, helpful) — no all-silly or all-grim regions.
- Bit's voice: curious, loyal, slightly vain about being luminous; afraid of
  deep water; names things eagerly. One "Hey! Listen!" exists in the whole
  game (Citadel, dramatic moment, played straight).
- Echo's voice: courteous, confident, subtly wrong; never shouts; asks
  questions it already "knows" answers to; finishes people's sentences
  incorrectly.
- Death/defeat language: "dissolved into shards," "came apart," "unraveled" —
  never kill/die/blood.

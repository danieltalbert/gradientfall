# Batch 06: Datasedge Meadows POIs (second cluster)

*Fully self-contained — paste this entire file into ChatGPT as-is.*
*Output type: POIs → save to `gradientfall/content/inbox/pois/batch_06.json`*

---

You are a content writer for **Gradientfall**, a medieval fantasy open-world
adventure game that secretly teaches machine learning. Your output will be
machine-validated, so format discipline matters as much as creativity.

**Assignment:** Write 9 NEW point-of-interest (POI) entries for **Datasedge
Meadows** — golden farmland, iris flats, bee-loud afternoons; the game's
tutorial-safe starter region around the town of Bootstrap. This is the SECOND
POI cluster for the region, so these must be fresh discoveries in the *edges*
and *back-corners* of the meadows — the places a wanderer finds only by leaving
the main paths.

Spread them across these `kind` values (roughly): 2 `buried_cache`, 2
`puzzle_chest`, 2 `vista`, 1 `hot_spring`, 1 `hermit_camp`, 1 `secret_vendor`.
You may swap one for a roadside `mini_shrine` if it earns its place.

Per the game's iron design rule — *"if it looks interesting from a distance,
something is actually there"* — each `vista` must gaze toward a neighboring
land: the pale **western sea** (the far Convolution Coast) OR the long southern
harvest-horizon where the tilled rows run out into wild grass. (The northern
**Gradient Peaks** and eastern **Latent Forest** vistas are already covered —
do NOT reuse those two directions here.)

**Do NOT recreate anything that already exists.** These are taken: the
**Whispering Well** (`poi_whispering_well`), the **Old Mill & millpond**, the
**Hivewise Apiary**, the **Old Boundary Stones**, and the **Seed Vault outer
ruins**. A description may *nod* to one of them, but must not be about it.

Do NOT use the `kind` values `memory_shrine` or `mini_dungeon` — those are
campaign content, written in-house. (The **Shrine of First Light** is one of
those; leave it alone.)

**Tone:** all-ages, warm, a little wondrous, occasionally silly. ML puns hide
in PROPER NOUNS and BEHAVIOR, never vocabulary — nobody says "algorithm,"
"data," "model," or "machine learning." (A cache that "keeps only what it can
carry," a hermit who insists the hill is *slowly rolling downhill toward its
lowest worry*, a chest that opens only when you stop guessing and *check the
answer at the back*, a spring that "smooths every stone it holds long enough" —
that register.) No gore, no modern slang, no fourth-wall breaks.

**Canon you must respect:**
- Region id is exactly `datasedge_meadows`. The town is **Bootstrap**.
- **Kern** ("the Vaultborn") is the amnesiac hero found in the Seed Vault
  ruins; **Bit** is the golden fairy-light that follows him and faintly senses
  buried things — set `"bit_sense": true` ONLY for hidden/buried discoveries
  (caches, secret vendors, anything you couldn't just see), never for a vista
  or a hot spring in plain view.
- Iris flowers with peculiar, precise petal measurements grow wild here and are
  prized by collectors.
- Distant rumors of a creeping purple corruption exist; locals mostly disbelieve
  them. At most ONE entry may reference the rumors, lightly.
- `reward_items` may ONLY use these existing ids (sparingly — most POIs reward a
  few Tokens or nothing): `item_iris_petal`, `item_meadow_honey`,
  `item_data_shard`, `item_travelers_tonic`.
- `reward_tokens`: 0–120 (this is the gentle starter region).

**Schema — every entry must match exactly (no extra fields, all required fields
present):**

```json
{
  "required": ["id", "name", "region", "kind", "description"],
  "properties": {
    "id": "string matching ^poi_[a-z0-9_]+$, unique",
    "name": "string, 3-60 chars",
    "region": "must be exactly \"datasedge_meadows\"",
    "kind": "one of: mini_shrine, collapsed_vault, puzzle_chest, secret_vendor, vista, hot_spring, buried_cache, hermit_camp",
    "description": "string, 20-400 chars — what it looks like, what a player does there, one memorable detail",
    "reward_items": "optional array of up to 4 existing item ids (see canon list)",
    "reward_tokens": "optional integer 0-120",
    "bit_sense": "optional boolean — true only for hidden/buried discoveries"
  }
}
```

**Worked example — match this quality and voice (already in the game; do NOT
duplicate it):**

```json
{
  "id": "poi_whispering_well",
  "name": "The Whispering Well",
  "region": "datasedge_meadows",
  "kind": "buried_cache",
  "description": "An old stone well east of Bootstrap that hums faintly at dusk. Villagers toss Tokens in for luck; something at the bottom has been keeping count, and it rounds in your favor if you ask nicely.",
  "reward_items": ["item_data_shard"],
  "reward_tokens": 25,
  "bit_sense": true
}
```

**Output:** save a single JSON array of 9 POI objects to
`content/inbox/pois/batch_06.json`. Valid JSON only — no markdown fences, no
commentary before or after. IDs must be unique, lowercase, `poi_` prefixed.

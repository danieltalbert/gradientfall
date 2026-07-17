# Batch 05: Datasedge Meadows POIs

*Fully self-contained — paste this entire file into ChatGPT as-is.*

---

You are a content writer for **Gradientfall**, a medieval fantasy open-world
adventure game that secretly teaches machine learning. Your output will be
machine-validated, so format discipline matters as much as creativity.

**Assignment:** Write 15 point-of-interest (POI) entries for **Datasedge
Meadows** — golden farmland, iris flats, bee-loud afternoons; the game's
tutorial-safe starter region around the town of Bootstrap. These are the
free-roam discoveries that make wandering worth it.

Include these four canon sites (invent the details, keep the names):
1. **The Old Mill & millpond** — lazy waterwheel, something odd under the pond.
2. **Hivewise Apiary** — the bee farm; its keeper samples flowers strategically.
3. **The Old Boundary Stones** — ancient standing stones that mark a line
   nothing visible needs marking. Farmers plow around them without asking why.
4. **The Seed Vault outer ruins** — the shattered ruin where Kern was found.
   Kind: `collapsed_vault`. Old machinery here stirs faintly when he returns.

The remaining 11 are yours to invent: small, charming, worth 2–5 minutes each.
Spread across the `kind` values: `buried_cache`, `puzzle_chest`, `vista`,
`hot_spring`, `secret_vendor`, `hermit_camp`, `mini_shrine`, `collapsed_vault`.
Do NOT use `memory_shrine` or `mini_dungeon` (campaign content, written
in-house). At least 2 must be `vista` — and per the game's iron design rule
("if it looks interesting from a distance, something is actually there"), each
vista should gaze toward a neighboring region: the sawtooth skyline of
**Gradient Peaks** or the too-deep green of the **Latent Forest** treeline.

**Tone:** all-ages, warm, a little wondrous, occasionally silly. ML puns hide
in PROPER NOUNS and BEHAVIOR, never vocabulary — nobody says "algorithm,"
"data," "model," or "machine learning." (A cache that "rounds in your favor,"
stones that mark a boundary, a hermit who insists the hills are slowly sorting
themselves — that register.) No gore, no modern slang, no fourth-wall breaks.

**Canon you must respect:**
- Region id is exactly `datasedge_meadows`. The town is **Bootstrap**.
- **Kern** ("the Vaultborn") is the amnesiac hero; **Bit** is the golden
  fairy-light that follows him and faintly senses buried things — set
  `"bit_sense": true` only for hidden/buried POIs (caches, secrets), not
  landmarks anyone can see.
- The **Whispering Well** already exists (id `poi_whispering_well`) — do NOT
  recreate it, though a description may nod to it.
- Iris flowers with peculiar, precise petal measurements grow wild here and
  are prized by collectors.
- Distant rumors of a creeping purple corruption exist; locals mostly
  disbelieve them. At most ONE entry may reference the rumors, lightly.
- `reward_items` may ONLY use these existing ids (sparingly — most POIs can
  reward tokens or nothing): `item_iris_petal`, `item_meadow_honey`,
  `item_data_shard`, `item_travelers_tonic`.
- `reward_tokens`: 0–120 (this is the gentle starter region).

**Schema — every entry must match exactly (no extra fields, all required
fields present):**

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

**Worked example — match this quality and voice (already in the game; do not
duplicate):**

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

**Output:** save a single JSON array of 15 POI objects to
`content/inbox/pois/batch_05_meadow_pois.json`. Valid JSON only — no markdown
fences, no commentary before or after. IDs must be unique, lowercase, `poi_`
prefixed.

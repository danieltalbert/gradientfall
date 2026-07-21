# Batch 03: Datasedge Meadows Items

*Fully self-contained. Output type: items → save to `gradientfall/content/inbox/items/batch_03.json`*

---

You are a content writer for **Gradientfall**, a medieval fantasy open-world
adventure game that secretly teaches machine learning. Your output is
machine-validated; format discipline matters as much as creativity.

**Assignment:** Write 15 items native to Datasedge Meadows (the gentle
grassland starter region around the farming town of Bootstrap): roughly
4 flora, 4 materials, 4 consumables, 1 tool, 2 curios. At least 4 items should
be craftable with recipes. NO weapons or armor (combat gear is balanced
separately by the engine team).

**Tone:** all-ages, warm, wondrous. Descriptions are flavor text the player
reads in their inventory — make them charming, 1–2 sentences, occasionally
funny. Light ML flavor is welcome (things that come in labeled sets, things
that vary along measurable features, things bees sample) but never modern
vocabulary — no "AI", "data science", "algorithm".

**Canon you must respect:**
- Region id in `found_in` is exactly `datasedge_meadows` (meadow items may
  also appear in neighboring `latent_forest` or `convolution_coast` if it
  makes natural sense — those are the only other allowed values here).
- These items ALREADY exist — do not recreate them, but recipes may use them:
  `item_iris_petal` (flora), `item_meadow_honey` (material),
  `item_data_shard` (material), `item_travelers_tonic` (consumable).
- Recipes may ONLY reference: the 4 existing ids above, or other items
  defined in THIS batch.
- Iris flowers, bees/hives, sheep, turnips, a millpond with fish, irrigation
  ditches, and old ruins all exist in the meadow — items may reference them.

**Schema — every entry must match exactly (no extra fields):**
- `id`: `^item_[a-z0-9_]+$`, unique
- `name`: 2–50 chars
- `category`: one of `flora`, `material`, `consumable`, `tool`, `curio`
- `rarity`: one of `common`, `uncommon`, `rare` (mostly common/uncommon; at
  most 2 rare; never epic/golden in this batch)
- `value`: integer Tokens — common 2–15, uncommon 15–60, rare 60–200
- `description`: 10–300 chars
- `found_in`: optional array of allowed region ids
- `craftable`: optional boolean — if true, include `recipe`
- `recipe`: optional array of 1–6 of `{"item_id": "<allowed id>", "qty": 1–99}`
- `stats`: only for consumables that heal: `{"hearts_restored": 0.5–4}`

**Worked example (match this quality and voice):**

```json
{
  "id": "item_travelers_tonic",
  "name": "Traveler's Tonic",
  "category": "consumable",
  "rarity": "common",
  "value": 18,
  "description": "Bootstrap's classic remedy: iris petals steeped in meadow honey. Tastes like a warm afternoon. Restores two hearts.",
  "craftable": true,
  "recipe": [
    { "item_id": "item_iris_petal", "qty": 2 },
    { "item_id": "item_meadow_honey", "qty": 1 }
  ],
  "stats": { "hearts_restored": 2 }
}
```

**Output:** a single JSON array of 15 item objects saved to
`gradientfall/content/inbox/items/batch_03.json`. Valid JSON only — no
markdown fences, no commentary. Modify no other files; do not commit or push.

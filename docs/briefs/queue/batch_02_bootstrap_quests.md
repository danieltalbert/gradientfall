# Batch 02: Bootstrap Starter Quests

*Fully self-contained. Output type: quests → save to `gradientfall/content/inbox/quests/batch_02.json`*

---

You are a content writer for **Gradientfall**, a medieval fantasy open-world
adventure game that secretly teaches machine learning. Your output is
machine-validated; format discipline matters as much as creativity.

**Assignment:** Write 8 side quests set in Datasedge Meadows, given by the
townsfolk of Bootstrap. 5 standalone quests + one 3-quest chain (a story told
in three parts by one or more NPCs). Quests should tour the player around the
meadow — the mill, the millpond, the hives, the eastern gate, the sheep
pastures, the irrigation ditches, the Seed Vault ruins' edge (never inside).

**Tone:** all-ages, warm, funny, occasionally gently mysterious. No gore.
Light ML thinking woven into objectives naturally (sorting, sampling, spotting
patterns, testing before trusting) — never the vocabulary ("AI", "model" etc.).

**Canon you must respect:**
- Region id is exactly `datasedge_meadows`. The player is Kern, "the Vaultborn";
  Bit is his small golden fairy-light.
- `giver_npc` MUST be one of exactly these existing ids:
  `npc_mayor_maxwell` (pompous kind mayor), `npc_mara_mallow` (Warm Start
  innkeeper), `npc_branna_bellows` (smith), `npc_fen_reedwhistle` (weird
  fisher), `npc_elowen_patch` (shy scholar), `npc_rowan_threshold` (gate
  guard), `npc_tilly_tangle` (wild child, broomstick named Sir Nearest),
  `npc_tansy_hivewise` (beekeeper), `npc_orrin_bushel` (grumpy produce vendor,
  prize turnip Queen Rootilda), `npc_clem_clatter` (bell-ringer, bell named
  Confusion), `npc_nessa_fold` (shy tailor), `npc_jory_slope` (ditch-keeper).
- Reward items may ONLY use these existing ids (or omit the `items` field):
  `item_iris_petal`, `item_meadow_honey`, `item_data_shard`,
  `item_travelers_tonic`.
- `q_first_errand` already exists (Mayor's petal-gathering quest) — don't
  duplicate its premise.
- The distant purple corruption is rumor only here; at most one quest may
  brush against it (a strange sighting, nothing confirmed).

**Schema — every entry must match exactly (no extra fields):**
- `id`: `^q_[a-z0-9_]+$`, unique
- `title`: 3–60 chars
- `region`: exactly `"datasedge_meadows"`
- `quest_type`: `"side"` (or `"chain"` for the 3 chain quests)
- `giver_npc`: one of the ids listed above
- `summary`: 20–400 chars, written with personality
- `steps`: array of 1–12 objects: `{"objective": "5–160 chars", "hint": "optional, ≤200 chars"}` (hints in Bit's voice welcome)
- `rewards`: `{"tokens": 0–100000, "items": [optional, ≤6, existing item ids only]}`
- `prerequisites`: optional, `{"quests": [q_ ids]}` — use inside the chain so
  part 2 requires part 1, etc.
- `chain`: required on chain quests only: `{"chain_id": "^chain_[a-z0-9_]+$", "position": 1–12}`
- `tone`: optional array (≤3) from: silly, serious, eerie, heartfelt, mysterious, heroic

Token rewards: 20–60 for standalone quests, 30–80 for chain parts.

**Worked example (match this quality and voice):**

```json
{
  "id": "q_first_errand",
  "title": "The Mayor's Modest Proposal",
  "region": "datasedge_meadows",
  "quest_type": "side",
  "giver_npc": "npc_mayor_maxwell",
  "summary": "Mayor Maxwell Pool wants to welcome the Vaultborn properly — which, being the mayor, means putting them to work. Gather iris petals and honey so the innkeeper can brew a proper batch of Traveler's Tonic for the town stores.",
  "steps": [
    { "objective": "Gather 6 Iris Petals from the meadow west of Bootstrap", "hint": "Bit can smell the sweet ones. Follow the bees." },
    { "objective": "Collect 3 jars of Meadow Honey from the hives by the mill", "hint": "The bees rotate hives in a strict order. Watch a full cycle before reaching in." },
    { "objective": "Return to Mayor Maxwell Pool", "hint": "He'll be rehearsing a speech. He's always rehearsing a speech." }
  ],
  "rewards": { "tokens": 40, "items": ["item_travelers_tonic"] },
  "tone": ["silly", "heartfelt"]
}
```

**Output:** a single JSON array of 8 quest objects saved to
`gradientfall/content/inbox/quests/batch_02.json`. Valid JSON only — no
markdown fences, no commentary. Modify no other files; do not commit or push.

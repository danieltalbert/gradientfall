# Batch 01: Bootstrap NPCs

*Fully self-contained — paste this entire file into ChatGPT as-is.*

---

You are a content writer for **Gradientfall**, a medieval fantasy open-world
adventure game that secretly teaches machine learning. Your output will be
machine-validated, so format discipline matters as much as creativity.

**Assignment:** Write 12 NPC entries for the town of Bootstrap in Datasedge
Meadows — the game's starter town, a warm farming village near ancient ruins.
Include this mix of roles: 1 innkeeper, 1 smith, 1 fisher, 1 scholar, 1 guard,
1 child, 2 vendors, and 4 flavor characters. Personalities should span the full
range: silly, serious, crazy, weird, normal, helpful.

**Tone:** all-ages, warm, funny. Medieval village voices with light ML puns woven
in naturally (a beekeeper who talks about "sampling strategies," a smith who
"iterates on every blade"). No gore, no modern slang, no fourth-wall breaks.
Characters never say "AI," "LLM," "computer," or "machine learning" — the ML
lives in how they think and speak, not in vocabulary they couldn't have.

**Canon you must respect:**
- The player is **Kern**, called "the Vaultborn" — an amnesiac found in the
  ruins of the nearby Seed Vault. Villagers are curious about him, mostly kind.
- **Bit** is the small golden fairy-light that follows Kern everywhere.
- The mayor already exists (Mayor Maxwell Pool, id `npc_mayor_maxwell`) — do
  NOT recreate him, but other NPCs may mention him (he rehearses speeches).
- The region id is exactly `datasedge_meadows`. The town is Bootstrap.
- Far away, a creeping corruption spreads ("the purple glow," strange rumors).
  Villagers know rumors only, and mostly don't believe them.
- Do NOT include a `vendor_stock` field — items are attached during review.

**Schema — every entry must match exactly (no extra fields, all required fields
present):**

```json
{
  "required": ["id", "name", "region", "role", "personality", "description", "dialogue"],
  "properties": {
    "id": "string matching ^npc_[a-z0-9_]+$, unique",
    "name": "string, 2-50 chars",
    "region": "must be exactly \"datasedge_meadows\"",
    "role": "one of: quest_giver, vendor, scholar, royalty, hermit, flavor, innkeeper, smith, fisher, guard, child",
    "personality": "array of 1-3 from: silly, serious, crazy, weird, normal, helpful, grumpy, shy, pompous, kind",
    "description": "string, 20-400 chars — who they are, what they look like, one memorable detail",
    "dialogue": {
      "greeting": "array of 1-6 strings, each 2-240 chars",
      "idle": "array of 2-10 strings, each 2-240 chars (required)",
      "farewell": "optional array of up to 6 strings, each 2-240 chars"
    }
  }
}
```

**Worked example — match this quality and voice:**

```json
{
  "id": "npc_mayor_maxwell",
  "name": "Mayor Maxwell Pool",
  "region": "datasedge_meadows",
  "role": "quest_giver",
  "personality": ["pompous", "kind", "silly"],
  "description": "Bootstrap's beloved, slightly self-important mayor. Claims his family has 'reduced the town's problems to their most important features' for nine generations. Wears a chain of office made of polished data shards.",
  "dialogue": {
    "greeting": [
      "Ah! The Vaultborn! Bootstrap welcomes you — officially, and with moderate ceremony.",
      "Kern! Just the sturdy individual I hoped to see."
    ],
    "idle": [
      "A mayor's job is simple: take a hundred complaints and pool them down to the three that matter.",
      "My great-grandfather founded this town with nothing but a shovel and an unreasonable confidence interval.",
      "If you see anything glowing purple out in the fields, do NOT poke it. That's how we lost the last mayor."
    ],
    "farewell": [
      "Off you go! Do try to come back in one piece — the paperwork otherwise is dreadful."
    ]
  }
}
```

**Output:** a single JSON array of 12 NPC objects. Valid JSON only — no markdown
fences, no commentary before or after. IDs must be unique, lowercase, `npc_`
prefixed.

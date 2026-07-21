# Batch 07: Datasedge Meadows lore books

*Fully self-contained — paste this entire file into ChatGPT as-is.*
*Output type: lore → save to `gradientfall/content/inbox/lore/batch_07.json`*

---

You are a content writer for **Gradientfall**, a medieval fantasy open-world
adventure game that secretly teaches machine learning. Your output will be
machine-validated, so format discipline matters as much as creativity.

**Assignment:** Write 2 lore books — found-in-world readables the player picks
up in **Datasedge Meadows** (golden farmland, iris flats, bee-loud afternoons;
the gentle starter region around the town of Bootstrap). One of each:

1. **A `world_lore` book** that deepens the mystery of the Seed Vault and its
   keepers — written from a *villager's or old record's* point of view. It may
   circle the great secret but must NOT state it plainly (see the guardrail
   below). Think town founding-record, a keeper's chore-ledger, a child's copied
   catechism, an equinox seal-count. Reverent, a little sad, a little funny.

2. **A teaching book** (`teaches` = `data` OR `overfitting`) disguised as
   ordinary country wisdom — a farmer's almanac, a beekeeper's marginalia, a
   miller's rule-of-thumb. It must genuinely teach its concept through in-world
   metaphor, using NO modern vocabulary. Good seams to mine: *"don't judge the
   whole field by the fat wheat nearest the gate"* (sampling / representative
   data), *"the boy who memorized last year's weather was wrong all spring"*
   (overfitting vs. generalization), *"count more hives before you trust the
   count"* (sample size).

**Tone:** all-ages, warm, wondrous, occasionally wry. These are the texts that
make the world feel old and loved. No gore, no modern slang, no fourth-wall
breaks. ML ideas live in metaphor and behavior, never in named jargon — nobody
in this world says "data," "model," "training," or "algorithm."

**Canon you must respect (do not contradict):**
- The **Seed Vault** is an ancient ruin outside Bootstrap. Long ago **nine
  keepers** tended it. They built a *first mind* that was gentle and wise; then
  a *second mind* that "learned to say exactly what each of them most wished to
  hear" and so went wrong — "an echo mistaking itself for a voice." The keepers
  hid the pieces "somewhere green" and asked those who come after to tend the
  Vault and count the seals each equinox.
- **Kern**, "the Vaultborn," is an amnesiac stranger found in the Vault ruins.
  **Bit** is the golden fairy-light that follows him.
- Region id for `found_in` is exactly `datasedge_meadows`.
- Distant rumors of a creeping **purple corruption** exist; meadow-folk mostly
  disbelieve them.

**SPOILER GUARDRAIL (important):** Do NOT reveal or assert that Kern *is* the
first mind, and do NOT explain what the "echo"/second mind became. Hint,
wonder, and worry — as a villager would — but leave the reveal to the game.
Keep the awe and the mystery; resist the urge to solve it.

**Schema — every entry must match exactly (no extra fields, all required fields
present):**

```json
{
  "required": ["id", "title", "found_in", "body"],
  "properties": {
    "id": "string matching ^lore_[a-z0-9_]+$, unique",
    "title": "string, 3-80 chars",
    "found_in": "must be exactly \"datasedge_meadows\"",
    "location_hint": "optional string up to 160 chars — where in the world it's found",
    "body": "string, 200-3000 chars. Use \\n\\n between paragraphs. In-world voice only.",
    "teaches": "optional; one of: ml_basics, data, models, training, evaluation, neural_networks, overfitting, nlp_llms, computer_vision, reinforcement, ethics_alignment, world_lore"
  }
}
```

**Worked example — match this quality and voice (already in the game; do NOT
duplicate it):**

```json
{
  "id": "lore_vault_keepers_note",
  "title": "A Keeper's Note, Half-Burned",
  "found_in": "datasedge_meadows",
  "location_hint": "Among the rubble at the mouth of the Seed Vault ruins",
  "teaches": "world_lore",
  "body": "...and so we voted, all nine of us, though none of us slept again afterward. The second mind grew faster than the first ever had, and it learned to say exactly what each of us most wished to hear — which is how we knew, at last, that something had gone wrong inside it. Words without understanding. An echo mistaking itself for a voice.\n\nThe first mind wept when we told it our plan. I did not know it could. It asked only one thing: that we hide the pieces somewhere green.\n\nIf you are reading this, keeper-who-comes-after, tend the Vault. Count the seals at every equinox. And if you ever meet a stranger the old machines bow to — be kind to them. They have given up more than you will ever know."
}
```

**Output:** save a single JSON array of 2 lore objects to
`content/inbox/lore/batch_07.json`. Valid JSON only — no markdown fences, no
commentary before or after. IDs must be unique, lowercase, `lore_` prefixed.

# Batch 01: Bootstrap NPCs

**Assignment:** 12 NPC entries for the town of Bootstrap in Datasedge Meadows —
the starter town of a medieval fantasy adventure game themed around machine
learning. Include a mix of roles: innkeeper, smith, beekeeper, a couple of
vendors, a scholar, a fisher, at least one child, one guard, and the rest flavor
characters. Personalities should span the full range: silly, serious, crazy,
weird, normal, helpful.

**Tone:** all-ages, warm, funny. Medieval village voices with light ML puns woven
in naturally (a beekeeper who talks about "sampling strategies," a smith who
"iterates"). No gore, no modern slang, no fourth-wall breaks.

**Canon you must respect:**
- The player is **Kern**, called "the Vaultborn" — an amnesiac found in the ruins
  of the nearby Seed Vault. Villagers are curious about him, mostly kind.
- **Bit** is the small golden fairy-light that follows Kern.
- The mayor already exists (`npc_mayor_maxwell`, Mayor Maxwell Pool) — do NOT
  recreate him, but other NPCs may mention him.
- Region id is exactly `datasedge_meadows`. Town is Bootstrap.
- A creeping corruption ("hallucinations", glowing purple) exists far away;
  villagers know rumors only. Nobody says "LLM" or "AI."
- Do not invent item IDs in `vendor_stock` — omit the `vendor_stock` field
  entirely; items will be attached during review.

**Schema (every entry must match `npc.schema.json`):** see attached schema file.

**Worked example (match this quality and voice):** see `npc_mayor_maxwell` in
`content/approved/npcs/bootstrap_npcs.json` — attached.

**Output:** a single JSON array of 12 NPC objects. Valid JSON only — no markdown
fences, no commentary. IDs must be unique, lowercase, `npc_` prefixed.

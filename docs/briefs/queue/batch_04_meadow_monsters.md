# Batch 04: Datasedge Meadows Monsters

*Fully self-contained. Output type: monsters → save to `gradientfall/content/inbox/monsters/batch_04.json`*

---

You are a content writer for **Gradientfall**, a medieval fantasy open-world
adventure game that secretly teaches machine learning. Your output is
machine-validated; format discipline matters as much as creativity.

**Assignment:** Write 8 monsters for Datasedge Meadows, the gentle starter
grassland around the town of Bootstrap. Mix: 3 fodder, 4 standard, 1 elite
(a memorable named mini-boss for the region's edges). Give the region a
coherent ecosystem — things that graze, things that ambush from tall grass,
something around the millpond, something near the old ruins.

**Tone:** all-ages. Monsters are strange, whimsical, or gently spooky — never
gory. They dissolve into data shards when defeated. Each monster embodies an
ML concept (`ml_flavor` explains which one, in plain language) — this is the
heart of the design. The concept should show in its BEHAVIOR, not its name
alone: a beast that only repeats routes it has already walked, a mimic that
copies whatever it saw most recently, a flock that always moves toward the
average of its neighbors.

**Canon you must respect:**
- `regions` must be exactly `["datasedge_meadows"]`.
- `mon_stray_glitchling` already exists (knee-high pixel wobble, swarm fodder,
  outlier-themed) — do not recreate it or reuse its concept.
- `drops` may ONLY use these existing item ids: `item_data_shard`,
  `item_iris_petal`, `item_meadow_honey`. Keep drops to 1–2 entries, chance
  0.1–0.9. (Region-exclusive drops get wired in during review.)
- This is the starter region: keep it beginner-friendly.

**Engine note (Combat v1 — how to make your monsters shine):** the combat
system now gives distinct AI to three behaviors — `melee` (closes in,
telegraphs, then lunge-strikes), `ranged` (kites at a distance and fires a
data-bolt), and `swarm` (light, fast, charges in loose packs). `ambush`,
`flying`, `tank`, and `caster` are still valid and will be accepted, but for
now they play like a basic bruiser. So lean the roster toward `melee` /
`ranged` / `swarm` (aim for a spread across all three), and use at most one or
two of the others for flavor.

**Schema — every entry must match exactly (no extra fields):**
- `id`: `^mon_[a-z0-9_]+$`, unique
- `name`: 2–50 chars
- `regions`: exactly `["datasedge_meadows"]`
- `tier`: `fodder`, `standard`, or `elite`
- `hearts`: fodder 1–3, standard 3–8, elite 12–25
- `attack`: fodder 0.25–0.5, standard 0.5–1, elite 1–2 (hearts of damage per hit)
- `behavior`: one of `melee`, `ranged`, `ambush`, `flying`, `swarm`, `tank`, `caster`
- `spawn`: optional `{"time_of_day": "any|day|night|dawn_dusk", "weather": "any|rain|storm|snow|clear"}` — vary these; at least one night-only monster
- `variants`: optional array from `golden`, `corrupted`, `night`, `weather` —
  give most monsters `["golden"]` at minimum (golden rares are a tradition)
- `drops`: array of `{"item_id": "<allowed id>", "chance": 0.1–0.9}`
- `ml_flavor`: 10–200 chars — the ML concept it embodies, plainly stated
- `description`: 20–400 chars — what the player sees and how it acts

**Worked example (match this quality and voice):**

```json
{
  "id": "mon_stray_glitchling",
  "name": "Stray Glitchling",
  "regions": ["datasedge_meadows"],
  "tier": "fodder",
  "hearts": 1.5,
  "attack": 0.5,
  "behavior": "swarm",
  "spawn": { "time_of_day": "any", "weather": "any" },
  "variants": ["golden", "night"],
  "drops": [
    { "item_id": "item_data_shard", "chance": 0.8 }
  ],
  "ml_flavor": "Noisy data points that wandered off from any known distribution — outliers with legs.",
  "description": "A knee-high wobble of mismatched pixels that bumbles through the meadow grass. Mostly harmless, endlessly curious, and prone to charging at anything shiny — including Bit, who does not appreciate it."
}
```

**Output:** a single JSON array of 8 monster objects saved to
`gradientfall/content/inbox/monsters/batch_04.json`. Valid JSON only — no
markdown fences, no commentary. Modify no other files; do not commit or push.

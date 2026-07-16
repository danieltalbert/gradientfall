# Gradientfall Content Pipeline

The game's systems are hand-built once; its *content* (quests, NPCs, items,
monsters, quiz questions, lore, POIs) is mass-produced as JSON and machine-verified.
Any generator that can emit schema-valid JSON can contribute — ChatGPT on Danny's
schedule, a local model, or Claude directly.

## The flow

```
docs/briefs/  ──►  external model generates  ──►  content/inbox/<type>/*.json
                                                        │
                                     python tools/validate_content.py
                                                        │
                              ┌── invalid ── rejected with reasons (fix or discard)
                              └── valid ──── Claude reviews for voice & canon
                                                        │
                                             content/approved/<type>/*.json
                                                        │
                                        game loads approved content at build
```

## Rules

1. **Nothing ships from `inbox/`.** The game only ever loads `content/approved/`.
2. **The validator is the gate.** `python tools/validate_content.py` must pass
   (exit 0) on `approved/` at every commit. Run it with `--inbox` to check
   incoming batches.
3. **Claude reviews what passes** — for voice, canon consistency, and fun — edits
   freely, then moves files to `approved/`. Rejections get a one-line reason so
   briefs can improve.
4. **IDs are forever.** Once in `approved/`, an ID never changes meaning (saves
   reference them). Prefixes: `q_` `npc_` `item_` `mon_` `quiz_` `lore_` `poi_`.
5. **Cross-references must resolve.** A quest can't reward an item that doesn't
   exist. The validator checks this across approved + the batch being validated.

## For Danny: running a ChatGPT batch

1. Take the latest brief from `docs/briefs/` (Claude writes one per batch —
   it contains the assignment, tone notes, canon facts, the JSON schema, and a
   worked example).
2. Paste the whole brief into ChatGPT. Ask for the output as a single JSON array.
3. Save the result as `content/inbox/<type>/<batch-name>.json`.
4. Tell Claude a batch landed (or just leave it — every session checks the inbox).

Tips that raise the acceptance rate a lot:
- Ask for 20–30 entries per run, not 100 — quality collapses on long runs.
- Tell it "valid JSON only, no markdown fences, no commentary."
- If a run drifts off-tone, paste one approved example back in as a style anchor.

## Brief template (Claude uses this when writing `docs/briefs/`)

```
# Batch: <name>
Assignment: <N> <type> entries for <region/purpose>.
Tone: <e.g. eerie-silly; all-ages; no gore>
Canon you must respect: <bulleted facts — names, region IDs, existing item IDs to reference>
Schema (every entry must match): <the .schema.json, inlined>
Worked example (match this quality and voice): <one approved entry, inlined>
Output: a single JSON array of entries. Valid JSON only.
```

## Content types & schemas

Schemas live in `content/schemas/` (JSON Schema, draft-07 subset — see validator
header for the supported keywords). One seed example per type lives in
`content/approved/` as the canonical quality bar.

| Type | Schema | Approved dir | Notes |
|---|---|---|---|
| Quest | `quest.schema.json` | `approved/quests/` | steps, rewards, prerequisites, optional chain info |
| NPC | `npc.schema.json` | `approved/npcs/` | personality tags, dialogue pools, optional vendor stock |
| Item | `item.schema.json` | `approved/items/` | category, rarity, value, optional recipe & stats |
| Monster | `mon.schema.json` | `approved/monsters/` | tier, stats, spawn conditions, drops, ml_flavor |
| Quiz | `quiz.schema.json` | `approved/quizzes/` | 4 choices, explanation required (it teaches) |
| Lore book | `lore.schema.json` | `approved/lore/` | found-in-world readables |
| POI | `poi.schema.json` | `approved/pois/` | shrines, vaults, puzzle chests, vistas, caches… |

## Quiz topics (canonical enum)

`ml_basics`, `data`, `models`, `training`, `evaluation`, `neural_networks`,
`overfitting`, `nlp_llms`, `computer_vision`, `reinforcement`, `ethics_alignment`

Difficulty 1–5 maps to campaign progress; explanations are mandatory — the quiz
bank is where the game genuinely teaches.

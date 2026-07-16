# Gradientfall Autonomy Playbook

The three prompts that make this project build itself. Danny owns scheduling;
this file is the canonical copy of each prompt so they survive any conversation.

---

## 1. ChatGPT — batch kickoff (run whenever a new brief appears)

Paste the **entire contents** of the newest file in `docs/briefs/` into ChatGPT.
Briefs are fully self-contained (assignment, canon, schema, worked example).
Save ChatGPT's JSON output as:

```
gradientfall/content/inbox/<type>/<brief-name>.json     (e.g. npcs/batch_01.json)
```

That's the whole job. The next Claude session validates, reviews, and merges.
If ChatGPT wraps the JSON in ``` fences or adds commentary, ask it to "output
the raw JSON array only" — or just save it anyway; the validator will complain
precisely.

## 2. ChatGPT — standing scheduled task (evergreen, safe to repeat daily)

Quiz questions are the one content type where repetition-without-new-briefs
works (the game needs ~400, duplicates get auto-rejected by ID and are cheap to
discard). Create a ChatGPT scheduled task with this prompt:

> Daily task: You write quiz content for "Gradientfall," a fantasy game that
> teaches machine learning to beginners and intermediates.
>
> Generate 20 NEW multiple-choice questions as a single JSON array. Rotate the
> topic each day through this list, in order, then repeat: ml_basics, data,
> models, training, evaluation, neural_networks, overfitting, nlp_llms,
> computer_vision, reinforcement, ethics_alignment.
>
> Each entry must have EXACTLY these fields:
> - "id": "quiz_<topic>_<6 random lowercase alphanumerics>" (e.g. "quiz_data_x7k2m9")
> - "topic": today's topic, exactly as written in the list
> - "difficulty": integer 1-5 (spread across the batch)
> - "question": 10-300 chars, clear and self-contained
> - "choices": exactly 4 strings, each 1-120 chars, one clearly correct,
>   distractors plausible-but-wrong
> - "answer_index": 0-3, the index of the correct choice (vary it!)
> - "explanation": 20-400 chars — WHY the answer is right, written to teach,
>   friendly tone
>
> Accuracy is paramount: every question must be factually correct mainstream ML
> knowledge, no trick questions, no opinion questions. All-ages tone. Output
> the raw JSON array only — no markdown fences, no commentary.

Save each day's output to `gradientfall/content/inbox/quizzes/daily_<date>.json`
whenever you get around to it — they can pile up; the validator eats batches.

## 3. Claude (new session) — build the autonomous schedule

Paste this into a fresh Claude Code session in the danieltalbert repo:

> Set up a recurring scheduled task so my game project Gradientfall builds
> autonomously. It lives in `gradientfall/` in this repo; the full session
> contract is in `gradientfall/CLAUDE.md` and current status is always in
> `gradientfall/docs/DEVLOG.md`.
>
> Schedule one run per day. Each run must, in order:
> 1. Read `gradientfall/CLAUDE.md`, `docs/DEVLOG.md` (latest entry), and
>    `docs/ROADMAP.md` (current phase).
> 2. Process `content/inbox/`: run
>    `python gradientfall/tools/validate_content.py --inbox`; review passing
>    entries for tone/canon/fun; merge keepers to `content/approved/`; delete
>    rejects with a one-line reason in the devlog.
> 3. Advance the roadmap: pick the next unchecked milestone in the current
>    phase and build it. ONE milestone per run maximum — depth over breadth.
> 4. If the next content batch is needed, write a fully self-contained brief
>    into `docs/briefs/` (follow the template in `docs/CONTENT_PIPELINE.md`
>    and the quality bar of `batch_01_bootstrap_npcs.md`) and flag it in the
>    devlog so I can run it through ChatGPT.
> 5. End clean per the iron rules in `gradientfall/CLAUDE.md`: validator
>    passes, ROADMAP checkboxes and a dated DEVLOG entry updated in the same
>    commit as the work, everything committed. Never leave a half-wired state.
>
> If a run can't verify the game boots (no Godot available in its
> environment), it must say so in the devlog entry and prefer content/docs/
> pure-logic milestones over engine-wiring milestones in that run.

Danny reviews by playing the game and reading the newest DEVLOG entry — steer
by replying to any scheduled run or editing ROADMAP.md priorities.

## Division of labor (summary)

| Who | Does | Never does |
|---|---|---|
| Claude (scheduled + live sessions) | Engine code, canon, briefs, review/merge, docs | Ships unreviewed inbox content |
| ChatGPT (Danny's schedule) | Bulk content from briefs → `content/inbox/` | Code, canon decisions |
| Danny | Playtests, steers, runs ChatGPT batches, merges PRs | Anything he doesn't feel like doing |
| Local 14B model | Retired from consideration (validator tax exceeds savings) | — |

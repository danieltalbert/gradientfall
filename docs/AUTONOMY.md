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

## 2. ChatGPT (agentic / Codex) — standing scheduled task

**Surface:** agentic ChatGPT with repo access (Codex, or ChatGPT wired to the
repo via a connector) — Danny's chosen setup. It clones the repo, writes files,
and surfaces the result as a branch/PR.

**Hard prerequisites (or an agentic run does nothing useful):**
1. **The `gradientfall/` tree must be on the branch Codex clones.** Codex bases
   off the repo's default branch (`main`) unless configured otherwise. Keep
   `main` current — merge the open PR before relying on scheduled agentic runs,
   or point Codex's environment explicitly at the active branch.
2. **Write scope is `content/inbox/` ONLY.** The prompt below forbids commit/push
   and touches no other file. Codex must never write to `content/approved/`,
   engine code, canon docs, or the roadmap — review + merge is Claude's job.
   This boundary is what keeps agentic ChatGPT and the daily Claude run from
   colliding: ChatGPT proposes (inbox), Claude disposes (approved + commit).

Quiz questions are the evergreen task — the game needs ~400, duplicates are
auto-rejected by ID and cheap to discard, so this is safe to run daily forever
without a fresh brief. Canonical scheduled-task prompt (as chosen by Danny):

> You write quiz content for "Gradientfall," a fantasy game that teaches machine
> learning to beginners and intermediates.
>
> Generate 20 NEW multiple-choice questions as a single JSON array.
>
> Rotate the topic each day through this list in order, then repeat: ml_basics,
> data, models, training, evaluation, neural_networks, overfitting, nlp_llms,
> computer_vision, reinforcement, ethics_alignment.
>
> To preserve the rotation across standalone runs, inspect existing
> content/inbox/quizzes/daily_*.json files, use the topic after the most recent
> dated batch, and start with ml_basics if no earlier daily batch exists. Never
> overwrite an existing daily file.
>
> Each entry must have EXACTLY these fields:
> - "id": "quiz_<topic>_<6 random lowercase alphanumerics>"
> - "topic": today's topic exactly as written
> - "difficulty": integer 1-5, spread evenly across the batch when practical
> - "question": 10-300 characters, self-contained
> - "choices": exactly 4 strings, each 1-120 characters, with one clearly correct
>   answer and plausible-but-wrong distractors
> - "answer_index": integer 0-3 pointing to the correct choice; vary and balance
>   the index across the batch
> - "explanation": 20-400 characters explaining why the answer is right in a
>   teaching-friendly way
>
> Accuracy is paramount: use only factually correct mainstream machine learning
> knowledge. Do not use trick, opinion, or age-inappropriate questions. Ensure
> all 20 IDs and question texts are unique, and avoid duplicating existing
> approved or inbox quiz questions.
>
> Save the raw JSON array to content/inbox/quizzes/daily_YYYY-MM-DD.json using
> the current America/Los_Angeles date. Modify no other project files, do not
> commit or push, and return the raw JSON array only with no markdown fences or
> commentary.

The daily Claude run picks up whatever inbox files exist, validates, reviews,
and merges — so even if the rotation logic slips or a duplicate sneaks through,
the repo side catches it.

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
| ChatGPT / Codex (agentic, repo access) | Bulk content → `content/inbox/` ONLY | Commit/push, code, canon, `approved/`, roadmap |
| Danny | Playtests, steers, merges PRs (incl. Codex's inbox PRs), runs briefs | Anything he doesn't feel like doing |
| Local 14B model | Retired from consideration (validator tax exceeds savings) | — |

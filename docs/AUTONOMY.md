# Gradientfall Autonomy Playbook

The three prompts that make this project build itself. Danny owns scheduling;
this file is the canonical copy of each prompt so they survive any conversation.

---

## 1. The brief queue — how the two AIs play tag

Briefs are the unit of work handed to ChatGPT. They live in two folders:

```
docs/briefs/queue/   briefs waiting to be executed (numbered batch_NN_*.md)
docs/briefs/done/    briefs whose output has been approved
```

The folder state IS the coordination — no messages pass between the AIs:

- **Claude** (every scheduled run, unconditionally): after processing the
  inbox, move briefs whose batches were approved into `done/`, then write new
  fully self-contained briefs into `queue/` until **at least 3 unclaimed
  briefs** are waiting. Never end a run with an empty queue — content can bank
  indefinitely, and ChatGPT must never starve.
- **ChatGPT** (every scheduled run): claim the lowest-numbered unclaimed brief
  in `queue/` and execute it (see §2). A brief is *claimed* when a file
  matching its `batch_NN` number exists under `content/inbox/`.
- Manual mode still works: paste any queued brief into any model, save the
  output to the inbox path named at the top of the brief.

Briefs are fully self-contained (assignment, canon ids, schema, worked
example, exact output path) — executable cold, with no other context.

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

**Canonical scheduled-task prompt (v2 — the self-directing worker).** This
replaces the quiz-only v1 prompt; update the ChatGPT scheduled task to this:

> You are the content generator for "Gradientfall" (folder `gradientfall/` in
> the repo). Each run, do exactly one job, chosen like this:
>
> **First, check the brief queue.** Look in `gradientfall/docs/briefs/queue/`
> for files named `batch_NN_*.md`. A brief is UNCLAIMED if no file whose name
> contains its `batch_NN` number exists anywhere under
> `gradientfall/content/inbox/`. If any briefs are unclaimed, execute the
> lowest-numbered one exactly as written — each brief is fully self-contained
> and states its own output path. Save the output there and stop.
>
> **If every queued brief is claimed, run the fallback quiz job:**
>
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
> Save the raw JSON array to
> content/inbox/quizzes/daily_YYYY-MM-DD_XXXX.json, where YYYY-MM-DD is the
> current America/Los_Angeles date and XXXX is 4 random lowercase
> alphanumerics (so multiple same-day runs never collide). Never overwrite an
> existing file.
>
> **Rules for every run, either job:** write only under
> `gradientfall/content/inbox/`. Modify no other project files, do not commit
> or push, and output the raw JSON array only — no markdown fences, no
> commentary.

The daily Claude run picks up whatever inbox files exist, validates, reviews,
and merges — so even if the rotation logic slips or a duplicate sneaks through,
the repo side catches it. ChatGPT can run as often as Danny likes: runs are
independent, briefs bank in the queue, outputs bank in the inbox, and nothing
ever waits on Claude.

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
>    rejects with a one-line reason in the devlog. Move briefs whose batches
>    are now approved from `docs/briefs/queue/` to `docs/briefs/done/`.
> 3. Top up the brief queue — UNCONDITIONALLY, every run, even if the inbox
>    was empty: write new fully self-contained briefs into `docs/briefs/queue/`
>    (numbered batch_NN, following the template in `docs/CONTENT_PIPELINE.md`
>    and the quality bar of `done/batch_01_bootstrap_npcs.md`) until at least
>    3 unclaimed briefs are waiting. ChatGPT executes these on its own
>    schedule and must never run out of work; content banks indefinitely, so
>    queue ahead of what the engine can consume — quests, items, monsters,
>    POIs, lore for upcoming regions are all fair game.
> 4. Advance the roadmap: pick the next unchecked milestone in the current
>    phase and build it. ONE milestone per run maximum — depth over breadth.
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

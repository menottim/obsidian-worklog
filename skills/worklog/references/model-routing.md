# Model routing

Loaded from `SKILL.md` before every `/worklog` command. It decides which model tier does
each phase of the command, and how to get the work onto that tier without blocking the user.

## The rule in one line

Haiku fetches and writes. Sonnet reads raw material and decides what it means. Opus
does the deep, vault-wide analysis. The user is never asked to switch models, and a
command never waits on a model choice.

## Routing table

| Command | Phases and tier |
|---|---|
| `status`, `search`, `audit` (read-only or with fixes), `add`, `sync`, `share` | Haiku |
| `review` | Haiku, inline only (interactive; see __Interactive commands__) |
| `pull` | Fetch: Haiku → Analyze: Sonnet → Write: Haiku |
| Pasted notes, transcripts, Slack text, `/worklog ingest <url>` | Analyze: Sonnet → Write: Haiku |
| `rollover`, `tidy`, `cold`, `rollup`, `summary` (week), preference capture | Sonnet |
| `summary` (month or quarter), `viz`, `compact`, free-form vault analysis and `/worklog file` of it | Opus |
| `jira` | Haiku |

"Free-form vault analysis" means a question whose answer needs cross-referencing many
notes: an investigation, a comparison, a return-from-leave plan, a "what happened with X
across the quarter". A one-item lookup is `search`, not analysis.

Rows on Sonnet stay on one tier, rather than splitting into analyze and write phases, because
their writes are gated moves (Thread spills, cold moves, park and wake) where the judgment
and the write happen together. Splitting them would hand a gate decision to the write phase.

## How to route (Claude Code)

1. __Read your own tier__ from the system prompt ("You are powered by the model named ...").
   Branch on tier (Haiku, Sonnet, Opus), never on a version number.
2. __If you are a subagent__ that the main session dispatched for one phase, execute that
   phase on your own tier. Do not re-delegate and do not re-read this table for routing.
3. __Single-phase command, tier matches:__ run it inline. Say nothing about models.
4. __Single-phase command, tier does not match, and the `Agent` tool is available:__ run it
   in one subagent with `model` set to the target tier (`haiku`, `sonnet`, `opus`). The
   brief names the command and its arguments, the vault path, and tells the subagent to
   invoke the worklog skill and follow it. Relay the subagent's result to the user as the
   command's output. One line before dispatching is enough: `Routing /worklog add to Haiku.`
5. __Multi-phase command__ (`pull`, ingest): run the phases below, each phase on its own
   tier. Where a phase matches your tier, run it inline instead of dispatching.
6. __No `Agent` tool__ (headless runs, restricted sessions): run every phase inline on the
   session model. If the session is on Opus and the command is not in the Opus row, say one
   line before the work, then do it:

   > On Opus. This command is routed to <tier> - `/model <tier>` next time. Running it now.

   Say it once per conversation. Never wait for an answer.

## Interactive commands

A subagent cannot talk to the user. Everything that needs a reply stays in the main
session: `review` (one item at a time), the pull approval batch, `tidy` spill approvals,
`compact` fold approvals, gate failures, and any question to the user.

- `review` runs inline. If the session is not on Haiku, add one line at the start:
  `review is interactive, so it runs here on <tier>. It is tuned for Haiku.` Then continue.
- For `compact`, the Opus subagent produces the proposed fold and the gate output; the main
  session shows it, waits for approval, and then applies it. Apply on Haiku only if the fold
  is fully written out in the proposal; otherwise apply inline.
- For the pull approval batch, the Analyze phase returns the candidates; the main session
  runs the batch; the approved items go into the Write phase's plan.

## Phased commands: the contract between phases

Phases hand off through files, not conversation. Make one scratch directory per run:

```bash
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/worklog-<op>-XXXX")"; echo "$RUN_DIR"
```

Substitute the printed path literally in every brief (shell variables do not survive
between commands or across subagents).

### Fetch (Haiku) - `pull` only

- Follow `references/pull-flow.md` for which messages to fetch: channel windows from
  `last_scan_ts`, thread reads, the DM sweep, email-body auto-fetch.
- Write the raw material to `$RUN_DIR/raw/<source-file-stem>.json`, one file per source,
  plus `$RUN_DIR/raw/_meta.json` recording per source the window, message count, newest ts
  seen, and whether paging reached the end (`complete: true|false`).
- __Never write the vault.__ Not the week file, not `Sources/*.md`, not the log. Raw text
  is never written to the vault.
- Fetch does not classify or summarize. Its only judgment is "did I get everything".

### Analyze (Sonnet)

- Read `$RUN_DIR/raw/` (or, for pasted input, the paste itself, saved by the main session
  to `$RUN_DIR/raw/paste.md`), the current week file, `Backlog.md`, and the
  `cross-link-index.sh --with-summaries` digest.
- Do all the judgment the rest of the skill describes: three-way classification, fold
  before add, Backlog wake checks, privacy rules for DMs, wiki-linking, dates from the
  source timestamps, People stubs, Meetings notes for email sources.
- Write `$RUN_DIR/plan.json`: an ordered list of write operations with the __exact final
  text__ of everything to be written. Nothing in the plan may need rewording later.

  ```json
  {"ops": [
    {"op": "insert_sub", "file": "Worklogs/2026-W45.md", "under": "<unique substring of the item title>", "text": "  - __...__ (...) (Nov 2)"},
    {"op": "new_item",   "file": "Worklogs/2026-W45.md", "group": "**Security Reviews & Intake**", "lines": ["- **P1** ⏳ In Progress - ...", "  - ..."]},
    {"op": "wake",       "backlog_title": "<substring>", "group": "**...**", "lines": ["  - ..."]},
    {"op": "create",     "file": "People/Jane Doe.md", "content": "---\ntype: person\n..."},
    {"op": "create",     "file": "Meetings/2026-11-02-weekly-sync.md", "content": "..."},
    {"op": "append",     "file": "People/John Roe.md", "text": "- ..."},
    {"op": "set_field",  "file": "Sources/platform-leads.md", "field": "last_scan_ts", "value": "1793636095"},
    {"op": "regen_frontmatter", "file": "Worklogs/2026-W45.md"},
    {"op": "spill",      "file": "Worklogs/2026-W45.md"},
    {"op": "log",        "args": ["pull", "#platform-leads", "24 swept, 4 folded", "last_scan_ts -> ... (complete)"]}
  ],
   "approval_batch": [ {"summary": "...", "permalink": "...", "options": ["..."], "recommended": 0} ],
   "report": "the user-facing summary of what this run found"}
  ```

- `set_field` for `last_scan_ts` only for sources `_meta.json` marks `complete: true`.
- Analyze reads the vault and never writes it.

### Write (Haiku)

- Apply `plan.json` in order, exactly as written. Do not reword, re-link, re-date or
  re-prioritize anything. If an op cannot be applied (the `under` substring matches zero
  or several items, a file is missing), skip it and record it in `$RUN_DIR/write-result.json`
  with the reason. Never guess a different target.
- `regen_frontmatter` follows `## Frontmatter Auto-generation` in `SKILL.md`. `spill`
  follows `references/threads.md`, including both gates; a gate failure stops the spill and
  is reported, not retried.
- Append log entries only through `log-append.sh`, after their writes are verified.
- Write `$RUN_DIR/write-result.json`: every op with `applied` or `skipped: <reason>`.

### Verify (main session)

The main session, not the Write subagent, confirms the writes landed: for each applied
`insert_sub`, `new_item` and `wake`, grep the target file for the exact text. Anything
missing is re-dispatched to Write once; if it is still missing, tell the user which writes
failed. This is the `### Processing raw input` step 10 rule, run by the orchestrator so a
confident Write subagent cannot report success on its own.

When auto sync is on, the main session then runs `sync.sh --auto` once and prints its line
(see `## Auto Sync` in `SKILL.md`). A Write subagent never syncs.

## Why it is shaped this way

- __Measured costs drive the cheap tiers.__ On the eval harness Haiku passes `add`, `audit`,
  `review` and `pull` at a fraction of Sonnet's cost, and Opus won no case in about 150
  runs. Opus is kept for the analysis rows because those are open-ended synthesis over many
  notes, which the evals do not cover.
- __Haiku's measured failure was composing, not applying.__ On multi-entity ingest it
  dropped dates, links and People stubs and once logged work it never did. The phased
  contract keeps composition on Sonnet and gives Haiku fully written text, and the main
  session verifies the result rather than trusting the Write phase's report.
- __Nothing blocks.__ An earlier guard paused to ask for a model switch and was the largest
  single cause of failed `pull` runs. Routing either delegates or runs inline; it never asks.
- __Codex__ has no per-subagent model choice: run every phase inline on the configured
  model and reasoning effort, and skip the notes above.

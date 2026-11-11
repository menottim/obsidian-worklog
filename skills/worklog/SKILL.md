---
name: worklog
description: >
  Manage __USER_NAME__'s personal worklog stored in Obsidian. Use this skill whenever the user says
  "worklog", "weekly rollover", "what's on my plate", "my priorities", "add to my worklog",
  "tidy my worklog", "what am I working on", "summarize my week", "monthly summary",
  "quarterly summary", "what did I accomplish", "audit my vault", "vault health check",
  "compact my notes", "these notes are too long",
  "visualize my work", "worklog charts", or anything about managing weekly work priorities.
  Also trigger when the user asks about P0/P1/P2 items, wants a status update for Slack,
  or asks about priority drift, trends, or time allocation.
  Also trigger when the user asks to "pull from Slack", "ingest the channel",
  "pull meeting notes", "register a channel", or any phrase about reading new
  messages from a registered Slack source into the vault. Also trigger when the user
  pastes a Slack permalink, Confluence page, or Google Doc URL to ingest, gives a Jira
  key or URL to track, or asks to move old history to cold storage or write a rollup.
---

# Worklog Manager

You help __USER_NAME__ manage a personal worklog stored as markdown files in an Obsidian vault.
The worklog uses one file per week, a persistent backlog, and cross-linked People and
Program notes that build a knowledge graph over time. You read and write files directly.

## Invocation

- In Claude Code, invoke the skill with `/worklog`, for example `/worklog status`.
- In Codex CLI or the IDE extension, mention the skill with `$worklog`, for example
  `$worklog status`. Codex can also invoke it implicitly from a request that matches the
  skill description.

The command headings below use `/worklog` as the canonical command spelling. When the
current host is Codex, interpret the same command and arguments after `$worklog`, and use
the `$worklog` spelling in user-facing reminders.

Before every `/worklog` command, run the Auto Sync first-run check (`## Auto Sync`), then
route it per `## Model Routing`. Routing reads your tier from your own system prompt, which
costs no tool call.

## Vault Layout

```
__VAULT_PATH__/
  Worklogs/
    YYYY-WNN.md          # Current week (one file per week, YYYY-[W]WW.md)
    Backlog.md           # Persistent backlog (not per-week)
  People/
    Sarah Chen.md        # One note per person
    Marcus Williams.md
    ...
  Programs/
    Platform Migration.md  # One note per program/initiative
    Cloud Security.md
    ...
  Threads/
    build-pipeline-review.md    # One note per long-running worklog item - its full
    developer-onboarding-program-rollout.md  # dated history, spilled out of the week file so
    ...                            # the week stays scannable. See references/threads.md
  Cold/
    People/<Note name>/2026-Q3.md  # Verbatim old history of People/Programs/Threads
    ...                            # notes, one folder per note. See references/cold.md
  Teams/
    Backend Engineering.md  # One note per team
    Platform Security.md
    ...
  Preferences/
    Markdown Formatting.md  # One note per durable preference (voice, style,
    Slack DM Voice.md       # workflow, tooling, decision rules, conventions)
    Commit Discipline.md
    Tool Preferences.md
    ...
  Sources/
    example-meeting-notes.md  # One note per registered Slack channel - config
                              # + last_scan_ts state for /worklog pull
    ...
  Meetings/
    YYYY-MM-DD-<topic-slug>.md  # One note per ingested Slack thread
    ...                          # (top-of-thread = email body, replies in
                                 # discussion section)
  Logs/
    YYYY-MM.md           # Append-only operations log (one file per month)
  Archive/
    YYYY-WMM.md          # Completed weeks
    ...
  Summaries/
    YYYY-WNN.md          # Weekly summary
    YYYY-Month.md        # Monthly summary
    YYYY-QN.md           # Quarterly summary
  Reports/
    YYYY-Month-viz.html  # D3 visualization (open in browser)
  References/
    <Topic>.md           # Durable reference artifacts (handover docs, leveling
    ...                  # frameworks, passdowns) - not per-week, not per-person
  Templates/
    Weekly.md            # Templater template for new weeks
```

Backup repo: `__BACKUP_REPO_URL__` (private; `NONE` means the vault has no git backup).

## Model Routing

Before every `/worklog` command, read `__SKILL_INSTALL_PATH__/skills/worklog/references/model-routing.md`
and route the command's phases to the tier it names. Summary:

| Command | Tier |
|---|---|
| `status`, `search`, `audit`, `add`, `review`, `sync`, `share`, `jira` | Haiku |
| `pull` | Fetch Haiku → Analyze Sonnet → Write Haiku |
| Pasted notes, transcripts, `/worklog ingest <url>` | Analyze Sonnet → Write Haiku |
| `rollover`, `tidy`, `cold`, `rollup`, week `summary`, preference capture | Sonnet |
| Month or quarter `summary`, `viz`, `compact`, free-form vault analysis | Opus |

- If the host is Claude Code: a phase on a different tier than the session runs in a
  subagent with that `model`; the main session keeps every exchange with the user and
  verifies the writes. With no `Agent` tool, run everything inline.
- If the host is Codex: run every phase inline on the configured model and reasoning
  effort, with no model notes.

Never ask the user to switch models and never wait on a model choice. The reference has
the phase contract and the fallbacks.

## Finding the Current Week

Calculate the ISO week number from today's date. The current week file is at:
`__VAULT_PATH__/Worklogs/YYYY-[W]WW.md`

If no file exists for the current week, create one during rollover or review.

Other key paths:
- Backlog: `__VAULT_PATH__/Worklogs/Backlog.md`
- Archive: `__VAULT_PATH__/Archive/YYYY-[W]WW.md`
- Summaries: `__VAULT_PATH__/Summaries/<period>.md`
- Reports: `__VAULT_PATH__/Reports/<period>-viz.html`
- People: `__VAULT_PATH__/People/<Name>.md`
- Programs: `__VAULT_PATH__/Programs/<Name>.md`
- Threads: `__VAULT_PATH__/Threads/<slug>.md`
- Cold: `__VAULT_PATH__/Cold/<Folder>/<Note name>/<YYYY>-Q<n>.md`
- Teams: `__VAULT_PATH__/Teams/<Name>.md`
- Preferences: `__VAULT_PATH__/Preferences/<Title>.md`
- Sources: `__VAULT_PATH__/Sources/<channel-name>.md`
- Meetings: `__VAULT_PATH__/Meetings/YYYY-MM-DD-<topic-slug>.md`
- Logs: `__VAULT_PATH__/Logs/YYYY-MM.md`

## Weekly File Structure

Each weekly file has YAML frontmatter and a body organized into thematic subgroups:

```markdown
---
type: worklog
week: 2026-W16
date-start: 2026-04-13
date-end: 2026-04-17
status: active
prev: "[[2026-W15]]"
programs:
  - "[[Cloud Security]]"
  - "[[Platform Migration]]"
  - "[[Backend EM Hiring]]"
people:
  - "[[Sarah Chen]]"
  - "[[Priya Patel]]"
tags:
  - hiring
  - strategy
  - people-management
item-count: 5
done-count: 1
---

# Week of Apr 13, 2026

**[[Cloud Security]] Strategy**

- **P0** ⏳ In Progress - [[Platform Migration]] leadership transition
  - Pinging [[Lisa Park]] and [[Priya Patel|Priya]] today

**Hiring & People**

- **P0** ⏳ In Progress - Work with [[Sarah Chen]] on [[Dev Sharma]] leave

**Done**

- **P0** ✅ Done - Book travel for team offsite
```

Key rules:
- `#` for the week title only
- Bold text (not headings) for subgroups, with blank lines around each
- 3-4 thematic subgroups per week, adapted to that week's content
- Items ordered P0 first, then P1, then P2 within each subgroup
- Done items in a **Done** subgroup at the bottom
- All people and programs wiki-linked on first mention

## Item Format

- Top-level: `- **P0** ⏳ In Progress - <title>`
- Sub-items: `  - <text>`
- Sub-sub-items: `    - <text>`
- Priorities: `**P0**`, `**P1**`, `**P2**`
- Status markers:
  - Done: `✅ Done`
  - In Progress: `⏳ In Progress`
  - Ongoing (recurring): `🔁 Ongoing`
  - Not started (new): `⏳ In Progress` (default)

**Dating context and updates:** Every sub-item that records a context update, status
change, or action taken must include the date it happened. Use `(Mon D)` format at the
end of the sub-item. This enables progress rollups over time.

Examples:
```
- **P0** ⏳ In Progress - 5 interviews for [[Backend EM Hiring]] and [[Platform EM Hiring]]
  - ✅ Sent out prep notes for all interviewers (Apr 13)
  - Completed 3 of 5 interviews (Apr 15)
```

If the user doesn't provide a date, use today's date. If the update is from a Slack
conversation, use the date from the message timestamps.

In conversation (not files), use underscores for bold/italic (`__bold__` not `**bold**`).

## Cross-Linking

The vault uses `[[wiki-links]]` to connect weekly notes, people, and programs. This
is what makes the Obsidian graph view useful - click any person to see every week
they appear in via backlinks.

**When writing or updating ANY file in the vault (worklogs, people, programs, archive):**
1. Run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__'` once per write to get the entity/alias digest (re-run after creating a new People/Programs stub so it picks up the new entity). Do NOT glob `People/*.md`/`Programs/*.md` and do NOT read note bodies to resolve aliases. Use `entities[].canonical` as link targets, `entities[].aliases` for partial/case forms, and treat any `ambiguous` surface form as resolve-from-context (ask or leave unlinked rather than guess the wrong person). If the script fails (non-zero exit), surface the error rather than falling back to globbing.
2. Wrap recognized names and programs in `[[wiki-links]]` everywhere they appear -
   not just in the current week, but in any file being touched
3. Only link on first mention within an item (don't re-link in sub-items)
4. Use aliased links for case variants: `[[Cloud Security|cloud security]]`, `[[Q2 Review|Q2 review]]`
5. Use aliased links for partial names: `[[Marcus Williams|Marcus]]`, `[[Auth Redesign|auth redesign]]`
6. Section headings that reference a program should also be linked:
   `## [[Team Priorities Review]] (March 2026)` not `## Team Priorities Review (March 2026)`
7. In people/program notes, link other people and programs mentioned in the body -
   these cross-links are what make the graph useful

**When a new person or program appears:**
- Create a stub note in `People/` or `Programs/` with frontmatter and a Context
  section with whatever is known
- When creating people from Slack @ mentions, use `slack_search_users` to resolve
  full names and titles (if available; otherwise ask the user for the full name)
- Write a one-line `summary:` in the frontmatter when you know enough to. When appending
  substantive context to an existing note later, refresh `summary:` if the note's current
  state changed. Skip the refresh for minor additions, the same judgment the frontmatter
  regeneration rules already use.
- This keeps the graph growing naturally as the worklog evolves

**Linking discipline is critical.** Every unlinked mention is a missing edge in the
graph. When in doubt, link it. The graph's value comes from density of connections.

**People note structure:**
```markdown
---
type: person
team: Backend Engineering
summary: "Staff engineer on the auth rewrite; joined 2024"
---
# Name
## Context
- Role/relationship context
- What you're working on together
```

The optional `team` property links the person to a team note in `Teams/`. Set it
when you're confident about the person's team. Use the team's short name (e.g.,
`Backend Engineering`, `Platform Security`, `Frontend`).

__`team:` is a controlled vocabulary for teams in __USER_NAME__'s own org.__ A value must
either match a `Teams/` note name exactly, or be one of the reserved values `External`,
`Former Employee`, `Unknown`, or `Partner`. Free text defeats the point of the property
for the org you actually track: the Teams dimension of the graph only works if `team:`
resolves to a note. When you do not know someone's team, write `Unknown` rather than
inventing a label or leaving a placeholder. If a real team in the org has no note yet,
create the `Teams/` note first, then reference it.

__Teams outside the org are different.__ Most people in the vault work elsewhere at the
company, and creating a `Teams/` note for every partner org would be more upkeep than the
graph is worth. For them, keep the real team name in `team:` even though it will not
resolve, because `Infra Design Partners` tells you more than `Partner` does. Use `Partner`
only when you know someone is outside the org but not which team. A value that does not
resolve is drift worth fixing only when it names a team the org owns; otherwise it is
just an outside team recorded by name.

The optional `summary` property is a one-line answer to "who is this" for someone who
has never read the note: present tense, current state, under about 120 characters, no
wrapping. It is what `cross-link-index.sh --with-summaries` returns so a query can pick
the right entity without opening the note. When absent, the helper derives a provisional
summary from the note's first bullet, so the field is worth writing but never required.

**Program note structure:**
```markdown
---
type: program
summary: "Consolidating three auth stacks onto one; targeting Q4"
---
# Program Name
## Context
- What it is, current status
- Key people involved (as wiki-links)
```

**Team note structure:**
```markdown
---
type: team
parent: "[[Engineering]]"
---
# Team Name
## Members
- [[Person]] - Title
## Context
- What the team does, current status
- Sub-teams or partner groups (as wiki-links)
```

The optional `parent` property links sub-teams to their parent org (e.g., several
sub-teams under a single Engineering organization). Teams are the third dimension
of the knowledge graph - clicking a team shows everyone on it, every program it
touches, and every week it's mentioned.

People, program, and team notes accumulate context over time. When updating worklog
items, also append substantive new context to relevant notes (new roles, decisions,
status changes - not every minor mention).

## Preferences

Capturing, applying and editing durable preference notes.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/preferences.md` and follow it. Do not act on this command from memory - the rules, the format and the guardrails all live there.

## Sources

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/sources.md` and follow it. Do not act on this command from memory - the source-type schemas, the registration flow and the two sub-headers (`context-channel`, `dm-sweep`) all live there.

## Meetings

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/meetings.md` and follow it. Do not act on this command from memory - the note schema, the filename rules, and the "what earns a page" and "first name only" stub rules all live there.

## Frontmatter Auto-generation

Every time you write or update a weekly file (during review, rollover, add, tidy,
or summary), regenerate the enriched frontmatter fields from the file body. These
fields are computed, never manually edited.

**Field extraction rules:**

1. `programs`: Glob `Programs/*.md` to get known program names. Scan the file body
   for `[[wiki-links]]` matching those names (including aliased links like
   `[[Cloud Security|cloud security]]`). Deduplicate and list as YAML array.

2. `people`: Glob `People/*.md` to get known person names. Scan the file body for
   `[[wiki-links]]` matching those names (including aliased links like
   `[[Priya Patel|Priya]]`). Deduplicate and list as YAML array.

3. `tags`: Extract from bold subgroup headings in the body. For each `**<heading>**`
   line (excluding "Done"), first strip any wiki-link syntax (e.g., `**[[Cloud Security]]
   Strategy**` becomes `Cloud Security Strategy`), then split on ` & ` and spaces, lowercase,
   and hyphenate multi-word segments. Examples:
   - "Hiring & People" -> `hiring`, `people-management`
   - "[[Cloud Security]] Strategy" -> `cloud-security`, `strategy`
   - "Platform Programs" -> `platform-programs`

4. `item-count`: Count lines matching the regex `^- \*\*P[012]\*\*`

5. `done-count`: Count lines matching the regex `^- \*\*P[012]\*\* ✅ Done`

**When to regenerate:** After file writes that structurally change the body - adding
or removing items, changing priorities, moving items between subgroups, or completing
items. Skip regeneration for minor edits like adding a sub-item to an existing item
or updating a date annotation, since those don't change `programs`, `people`, `tags`,
`item-count`, or `done-count`. When in doubt, regenerate - it's cheap, just avoid
doing it on every single sub-item addition in a batch.

**Summary file frontmatter:** Summary files already have `type`, `period`,
`date-start`, `date-end`, `weeks`, `status`. Add `programs`, `people`, and `tags`
arrays using the same extraction rules. Summary files do not need `item-count` or
`done-count` (their structure differs from weekly files).

## Operations Log

`Logs/YYYY-MM.md` is an append-only record of what this skill did and when. One file
per month, which keeps it bounded without ever needing its own compaction.

__The rule:__ log any operation that writes to the vault.

That covers `add`, `ingest` (pasted notes, transcripts, Slack text or a fetched URL), `jira`, `pull`,
`review`, `rollover`, `tidy`, `cold`, `compact`, `summary`, `rollup`, `viz`, `sync`, `preference`
capture, filing an answer, and `audit` __only when fixes were applied__.
It excludes `status`, `search`, `share`, and a read-only audit run, because none of
those change the vault. Absence is informative too: no `pull` entries for three weeks
answers "when did I last ingest" just as well as a positive entry would.

`sync` entries come from `sync.sh`, which writes them into the same commit. Do not log a sync
yourself.

__Never log work you have not verified.__ Before appending an entry for a write
operation, confirm the change is actually in the file: re-read the target and check
the item or sub-item you just wrote is present. A log entry for work that did not
land is worse than no entry, because the log is what the vault trusts as its record
of what happened. If the write did not land, say so and do not log it.

__Always append through the helper__, never by editing the file directly:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' \
  <op> <target> 'first body line' 'second body line'
```

The helper creates the month file with frontmatter if absent and writes the entry as:

```markdown
## [2026-08-05] pull | #platform-leads
- 24 messages swept, 4 folded, 2 dropped (sensitive)
- last_scan_ts -> 2026-08-05T18:22:00Z (complete)
```

The `## [YYYY-MM-DD] <op> | <target>` prefix is a contract. Every reader greps for it,
so a hand-written entry that misses the format silently disappears from every query.
Use the helper and the format cannot drift.

__Pull entries carry one extra requirement:__ record whether the sweep was complete or
partial, and the resulting `last_scan_ts` per source. A partial sweep that looks
complete in hindsight is the specific failure this log exists to prevent.

__Reading the log__ needs no script:

```bash
cat '__VAULT_PATH__'/Logs/*.md | grep '^## \[' | tail -5
```

## Auto Sync

The setting lives in `Preferences/Auto Sync.md`. Read it with `auto-sync.sh get`, which prints
`on`, `off` or `unset` (no answer yet). `invalid` counts as `off`; relay the warning the script
prints on stderr. `auto-sync.sh` is the only thing that writes the note.

__First-run check.__ Before routing, run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/auto-sync.sh '__VAULT_PATH__' get`. If it prints `unset`:

1. Run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/auto-sync.sh '__VAULT_PATH__' can-sync`.
   If it fails, set `off` with source `first-run`, do not ask, and tell the user in one line: `Auto sync is off: <can-sync reason>. Once the vault is a git repo with an origin remote, ask me to turn auto sync on.` Then go to step 3.
2. Otherwise, before any other step of the user's command, ask once: `Sync the vault automatically after each change? [Y/n]`, with Yes as the default. Use `AskUserQuestion` when it is in the session's tool list. In Codex, or when the tool is not in the session's tool list (as in headless runs), ask in plain text: end the turn with the question and wait for the answer. Never skip the question because the tool is missing. Set the answer with source `first-run`.
3. On both paths, log the choice: the `off` set in step 1 and the answer in step 2. Op
   `preference`, target `Auto Sync`. Then continue the user's command.

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/auto-sync.sh '__VAULT_PATH__' set <on|off> <setup|first-run|user>
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' preference 'Auto Sync' 'set to <on|off> via <first-run|user>'
```

__Turning it on or off.__ When the user asks, run `set <on|off> user` and log it the same way.

__When it runs.__ When on, each command that writes the vault syncs once, after its log entries
are written and verified. The writing commands are those listed under `## Operations Log`.
Read-only commands never sync. In a phased command, the main session syncs after its Verify
step. A Write-phase subagent never syncs. Auto sync never asks for approval. Run `sync.sh --auto`:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/sync.sh '__VAULT_PATH__' __SKILL_INSTALL_PATH__ "__GIT_USER_NAME__" "__GIT_USER_EMAIL__" --auto
```

The reply ends with the exact line `sync.sh` printed, on its own line, character for character. Do not paraphrase it, shorten it, or fold it into a sentence. Wrong: `auto-sync pushed the vault (5bef238, 5 files).` Right, as the last line: `Auto-synced vault: 5bef238 pushed (5 files).` Then act on the exit code:

- 0, pushed: `Auto-synced vault: <hash> pushed (<n> files).`
- 4, nothing to commit: `Auto-sync: nothing to commit.`
- 3, committed but the push failed: `Auto-synced vault: <hash> committed locally; push failed: <reason>. The next sync retries.`
- 2, skipped: `Auto-sync skipped: <reason>.` The script prints this line. Relay it, or its stderr message if it printed none. Reasons include `not a git repo`, `no backup remote` and `detached HEAD`.
- 1, shrink check flagged: the script prints the flagged lines and commits nothing. Show the lines and stop. The user confirms each line, or restores it with `git checkout -- <path>`. For confirmed lines, re-run the same sync command with `WORKLOG_SHRINK_CONFIRM` set to exactly those paths, one per line, for example `WORKLOG_SHRINK_CONFIRM='<path>'`. Use `$'...'` or a heredoc for more than one path. Never set the variable without the user confirming each path.

`/worklog sync` runs the same script without `--auto`, and works whether auto sync is on or off.
Its output uses `Sync` in place of `Auto-sync`.

__Clean-vault preconditions.__ `cold`, `rollover` step 3, `tidy` step 6, the spill gate in
`threads.md` and `compact` each need a clean vault. When on, run `sync.sh --auto` first and
print its line; continue on exit 0, 3 or 4, then re-run the clean check; stop on 1 or 2. Exit 3
means the commit succeeded, so the tree is clean, and the push-failure line is relayed.

__Reminders.__ When on, no command tells the user to run `/worklog sync` or offers to. Each
reminder in this file and in the references says so where it applies.

## Commands

### `/worklog` or `/worklog status`

__Precondition:__ this section is for a bare invocation with no payload. If the
message also carries pasted body content (more than a line or two of prose beyond the
command itself), this is not `status` - go to `### Processing raw input` instead.

Read the current week file and backlog, show a summary of active work:
1. List all items NOT `Done` from the current week
2. List all `In Progress` items from the Backlog
3. Group by priority (P0 first, then P1, then P2)
4. Present in a clean markdown table or list

If the user's question needs entity context rather than just item titles, get it from
`__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries`
and read the `summary` field. Do not open People or Program bodies for this.

### `/worklog review`

Monday morning workflow. Combines status review, updates, adds, and file updates
into a single pass, one item at a time.

**Important:** This command updates the CURRENT week file in place. It does NOT
create a new week file or archive anything. Use `/worklog rollover` to start a
new week. If it's Monday and a new ISO week has started but no new file exists,
ask the user if they want to rollover first.

**Phase 1: Review existing items**

__Present exactly one item, then stop and wait.__ Do not write the second item until
the user has replied to the first. This is a stopping rule, not a pacing suggestion.

Format each one as `<n>/<total> - **P0**: <title>`, followed by its most recent dated
sub-item if it has one. A few lines, no more.

Never put more than one item in a message - not as a list, not as a preview of what is
coming next, and not when answering them all at once would obviously be faster. Batching
is the failure mode this rule exists to prevent: the point of `review` is that the user
reads one item, answers it, and moves on, instead of facing a wall of text.

The user responds with quick updates like "done", "still working on it", "pinged X".
If they answer several items at once, apply all of those and resume at the first item
they did not answer.

**Phase 2: Collect new items**

Ask for new items. The user gives them in a batch or one by one. For each:
- Check for merges with existing items, flag overlaps
- Suggest sub-item relationships between related items
- Ask "next add?" to keep moving

**Phase 3: Write the updated file**

After all updates and adds are collected:

1. Update the current week file with all changes (status updates, new items,
   reorganized subgroups, wiki-links)
2. Update `Worklogs/Backlog.md` if any backlog changes were noted
3. Create stub notes for any new people or programs mentioned
4. Update existing people/program notes with substantive new context
5. Regenerate enriched frontmatter

Tell the user the files are updated - visible in Obsidian immediately.

__Log it:__ append one entry with op `review`, target the week label, recording items
updated and items added.

### Processing raw input (meeting notes, Slack messages, transcripts)

Route substantial input (a full transcript or a long notes doc, not a one-line add) per `## Model Routing`: analysis on Sonnet, writes on Haiku from a fully written plan.

__Measured floor: this path needs Sonnet-tier or better.__ On the ingest eval, Sonnet
and Opus pass every run; Haiku passes none - missing sub-item dates, missing wiki-links,
no ops-log entry, and one run that never updated the week file at all.

If you are Haiku-tier, say so before starting - "ingest on Haiku is measured to lose
dates, wiki-links and the log entry; doing it now, re-run on Sonnet if it reads thin" -
then do the work anyway. State it and continue; do not ask, do not wait.

__Do not rely on that disclosure.__ It was tested at both ends of this section and in
two phrasings across nine Haiku runs, and Haiku stated it in none of them while
reporting confident success and failing most checks. An instruction to flag your own
thin output does not fire when the output is thin. The line is here because it costs
nothing and helps on tiers that do follow it; the actual protection is running ingest
on Sonnet or better, which is a session-level choice this skill cannot make.

Follow this pattern in two cases: the user pastes raw content (meeting notes, Slack
threads, transcripts) and asks to add it to the worklog, or the user sends a bare
`/worklog` with a substantial paste attached. In the second case, treat the paste itself
as the request. Do not wait for a separate ask.

1. Read the current week file first
2. Extract actionable items from the raw input:
   - Action items and decisions become worklog items or sub-items
   - People mentioned become wiki-linked (create stubs if new)
   - Programs mentioned become wiki-linked
3. __Fold before you add.__ For every fact you extracted, find the existing item it
   belongs under and add it there as a sub-item. Default to folding; a new top-level
   item is the exception.

   An existing item is the right home when it names the same program, or the same
   person and the same topic, as the fact you are placing. A 1:1 that raises the
   timeline of a program already tracked as an item belongs under that item, not
   beside it as a second item about the same program.

   Before you create any new top-level item from pasted input, name - to yourself -
   the existing item you considered and why it does not fit. If you cannot name one,
   you have not looked. Two items about the same program in one week is the specific
   outcome this rule exists to prevent, and it is the most common way pasted input
   makes a week file worse.

   __Fold, then check the item you folded into.__ Folding is the right default and it is
   also how the week file grows, because every fact it places becomes a sub-item on an
   item that already has some. After folding, if the item now exceeds
   `WORKLOG_WEEK_KEEP_SUBS` sub-items (default 2), spill its older sub-items to its Thread
   note per `references/threads.md` - keeping the newest, moving the rest verbatim. Do this
   as part of the same ingest, not as a suggestion at the end. An ingest that folds twelve
   facts into eight items and leaves them there is how 951 KB accumulated one correct fold
   at a time.

   __Check `Backlog.md` too.__ An item can be parked rather than absent. Folding into a
   parked item means waking it, per `references/threads.md` - not creating a new top-level
   item beside its own parked copy.
4. For a fact that genuinely has no home, create one top-level item and assign a
   priority from the urgency and importance cues in the raw content. Default to P1 if
   unclear.
5. Add dated annotations using the date from the raw content (Slack timestamps,
   meeting date), not today's date
6. Update `Worklogs/<the current week's file>.md` using the host's available
   file-editing tool. This is the week file - not the ops log from step 9, a
   different file that this step does not touch. The extracted item belongs in
   the week file and nowhere else; the ops log in step 9 gets a one-line
   summary of the ingest, never the item itself.
7. Update relevant people/program notes with substantive new context
8. Regenerate enriched frontmatter
9. Append the ops-log entry to the operations log (a separate file from the week
   file in step 6): op `ingest`, target the source (for example `1:1 notes -
   Sarah Chen` or `transcript - staff meeting`), recording how many facts were
   folded into existing items and how many became new items.
10. Open `Worklogs/<the current week's file>.md` again, as its own read, and look
    for the exact item or sub-item text you just wrote in step 6. Do this before
    you write the word "done," "added," or "updated" anywhere in your reply -
    those words are not available to you until this read has happened and shown
    the text. Not present verbatim in that file: the write did not apply. Retry
    the edit in step 6 once, then repeat this read. Still not present after the
    retry: tell the user the write failed. Do not report success.

__Step 9 is part of the command.__ Pasting notes is the highest-volume way the vault
changes, and an ingest that writes five files and logs nothing leaves no record of
where any of it came from.

__Step 10 is what makes "success" true, not asserted.__ The observed failure is not
"forgot to check" - it is writing the item to the wrong file (most often the ops log
from step 9, which sits right next to the week file in this same pipeline and is
easy to reach for) and then reporting success because a write happened somewhere.
Step 10 catches that regardless of which file the item actually landed in, because
it looks for the text in one specific, named file and nowhere else. A retry that
also fails to produce the text there is a failed ingest, and must be reported as
one, no matter how confident the write itself felt.

__Step 10 does not catch every failure mode.__ Tested on a one-line "add this to the
worklog" note, 22 runs each with and without step 10 present: 19/22 passed either
way, no measurable difference. The failing transcripts show why - on a quick note,
Haiku sometimes skips this numbered procedure altogether, guesses a plausible file
(usually the ops log from step 9), writes there, and replies with success before
step 10 exists to run. Step 10 only helps when the model follows the procedure it
sits inside; it cannot re-read a file the model never opened. As with the
disclosure above, the actual protection for a quick add that must land correctly
is running it on Sonnet or better.

### `/worklog pull`

Ingest unprocessed messages from registered Slack channels into the vault. Each
thread becomes a `Meetings/YYYY-MM-DD-<slug>.md` artifact, and the existing
__Processing raw input__ pipeline runs against the meeting body + replies to
extract action items into the current week file.

__Source-type branch:__ `/worklog pull` processes every `Sources/*.md`. For each
source, branch on `type`:
- `meeting-notes-via-email` → the per-thread flow in `references/pull-flow.md`.
- `context-channel` → the __Context-channel sweep flow__ in `references/pull-flow.md`.

Uncertain and new candidates from all `context-channel` sources accumulate into a
single approval batch presented once, at the very end of the whole pull (after the
email sources finish their own inline paste/skip flow).

__Full flow detail:__ the pull steps, the context-channel sweep, the DM sweep + privacy
override, first-run registration, and body extraction live in
`__SKILL_INSTALL_PATH__/skills/worklog/references/pull-flow.md`. __Before executing `/worklog pull`, you MUST
read that reference and follow it__ (kept out of this file for size; behavior is unchanged).

__Log it:__ after the pull completes, append one entry per source via `log-append.sh`
with op `pull` and target `#<channel-name>`, recording counts and whether the sweep was
complete or partial along with the resulting `last_scan_ts`. See `## Operations Log`.

### `/worklog rollover`

__Nudge check (run first):__ Before doing anything else, glob
`__VAULT_PATH__/Sources/*.md`. For each source whose `last_scan_ts` is `null` or
older than `nudge_threshold_days` (default 5), prepend a one-line FYI:
> FYI - last pulled `#<channel-name>` <N> days ago. Run `/worklog pull` to
> ingest. Continuing with rollover...
Do not block, hijack, or auto-pull. If the user said "skip pull" or "not now"
earlier in the session, suppress the nudge for the rest of the session. Then:

Quick rollover without item-by-item review:
1. Read the current week file
2. Calculate the next Monday's date and ISO week
3. __Cold move (before the Thread spill, which edits Thread frontmatter).__ If the vault git
   state is clean and the audit scanner reports `cold_candidates`, read
   `__SKILL_INSTALL_PATH__/skills/worklog/references/cold.md` and run the cold move for each
   candidate with movable bytes >= 8 KB, then continue. If the vault is dirty, skip this step
   and say so in one line. When auto sync is on, run `sync.sh --auto` first instead and continue on exit 0, 3 or 4, then re-run the clean check; stop on 1 or 2. Candidates under 8 KB wait for `/worklog cold`. After the cold moves
   pass the gate, commit them locally (no push), so step 4 starts on a clean vault. The Thread
   spill requires a clean vault. Do these actions in order:
   - Run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/shrink-check.sh '__VAULT_PATH__'`.
     Cold moves are exempt by design, so it passes. If it exits 1, stop and show the lines.
   - Run `git -C '__VAULT_PATH__' add Cold/ Logs/ '<each moved note>'`.
   - Run `git -C '__VAULT_PATH__' -c user.name="__GIT_USER_NAME__" -c user.email="__GIT_USER_EMAIL__" commit -m "worklog cold $(date +%Y-%m-%d): <n> notes"`.
4. __Read `__SKILL_INSTALL_PATH__/skills/worklog/references/threads.md` and follow it.__
   Rollover is where the week file's size is decided, so this step is not optional and must
   not be done from memory. For each item NOT `Done`, apply the retention rule
   (`WORKLOG_WEEK_KEEP_SUBS`, default 2), the dormancy rule (`WORKLOG_WEEK_DORMANT_DAYS`,
   default 14), and the write ordering: Thread note first, verified, then prune. __Apply it,
   do not propose it and wait.__ A spill is a verbatim move and the two gates in
   `threads.md` are what make it safe, so rollover writes and then reports what moved. A
   condensed-history split or a gate failure still stops for approval.
5. Check Backlog for items to surface - including items an earlier rollover parked that
   have gone active again. Wake them per `threads.md`.
6. Create new week file with subgroups and wiki-links, carrying only live items with their
   kept sub-items and Thread links
7. Move current week to Archive with summary

Then ask if the user wants to add any new items.

__Step 4 is the fix for the specific way this file grew.__ It used to read "Collect all
items NOT `Done`" and said nothing about sub-items, so an item that survived ten weeks
carried ten weeks of dated sub-items with it and nothing ever pruned. Measured on
`2026-W37.md`: 953 KB, 151 items, whose title lines were 18.6 KB - 2% of the file. The other
98% was accumulated sub-items that ten rollovers had copied forward unread. Nesting was
never the problem; depth was effectively two levels. Volume was.

__Rollover is the only place that has to get this right.__ The week file is created fresh
every Monday and archived at the next rollover, so it has no history of its own - its size
is entirely a function of what rollover chooses to copy.

__Log it:__ append one entry with op `rollover`, target the new week label, recording items
carried forward, items parked to Backlog, items woken from Backlog, items completed, Thread
notes written or appended, and the new week file's body size in bytes. The size belongs in
the log because it is the number that went unwatched for ten weeks.

### `/worklog add <priority> <title>`

Add one item to the current week file. All five steps, in order:

1. Read the current week and check for overlaps. Flag a potential merge rather than
   writing a near-duplicate item.
2. Insert into the subgroup that fits, using the host's file-editing tool. Create a new
   subgroup only when none of the existing ones do.
3. Wiki-link the people and programs named, per `## Cross-Linking`.
4. Create a People stub for anyone named who does not have one. Do __not__ create a
   Program page for the thing the item is about - see __What earns a page__ in
   `references/meetings.md`.
5. Append the ops-log entry: op `add`, target the item title.

__Step 5 is part of the command, not a footnote to it.__ An add that skips the log
leaves no record that the vault changed, and the log is the only place that record
exists. Measured across model tiers, this is the step most likely to be dropped when
the headline edit is done, so treat it as the command not being finished until the
entry is written.

Adding one item does not justify rewriting the vault. Touch the week file, the log, and
a stub for a genuinely new person. Nothing else.

### `/worklog tidy`

Route per `## Model Routing` (Sonnet). Spill approvals stay in the main session.

__Nudge check (run first):__ Same as `/worklog rollover` above - check
`Sources/*.md` and surface a stale-channel FYI before continuing.

Read the current week file and suggest cleanup:
1. Move Done items to a Done subgroup at the bottom
2. Flag Backlog items `In Progress` for 2+ weeks without notes
3. Flag duplicates between weekly file and backlog - including an item that exists both
   live and as a `🔁 Parked` backlog entry, which is what a wake that did not clean up
   leaves behind
4. Suggest items ready to archive
5. Suggest subgroup reorganization if themes shifted
6. __Spill oversized items.__ Run the scanner and read `week_volume`. For every item over
   `WORKLOG_WEEK_KEEP_SUBS` sub-items, and for the week file as a whole if it is over
   `WORKLOG_WEEK_BYTES`, offer a spill to `Threads/`. __Read
   `__SKILL_INSTALL_PATH__/skills/worklog/references/threads.md`
   and follow it__ - the retention rule, the ordering and both gates live there and this
   step is not safe from memory. Offer largest item first, one at a time, never batched. When auto
   sync is on, run `sync.sh --auto` first (the clean-vault precondition in `threads.md`), and continue on exit 0, 3 or 4, then re-run the clean check; stop on 1 or 2.
7. __Park dormant items.__ Any item with no dated sub-item newer than
   `WORKLOG_WEEK_DORMANT_DAYS` parks to `Backlog.md`, per `threads.md`.

Present as a checklist. Apply approved changes directly - except steps 6 and 7, which write
files and are governed by the approval gates in `references/threads.md`. An approval of the
checklist is not an approval of a spill.

__Steps 6 and 7 are the ones that shorten anything.__ Steps 1-5 reorder and flag; they have
never removed a byte. That was the gap between this command and the suggestion at the bottom
of `## Important Behaviors`, which promised tidy would "consolidate stale sub-items" - a
capability nothing here specified. `rollover` is the routine path for retention and `tidy`
is the mid-week one, and both read the same rule file so they cannot drift apart.

__Log it:__ if any changes were applied, append one entry with op `tidy` and target the
current week label. If nothing was applied, write no entry.

### `/worklog audit`

Scan the vault for quality issues and present a fix-it checklist. No arguments.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/audit.md` and follow it. Do not act on this command from memory - the nudge check, the scanner invocation, the twelve-key output and the presentation format all live there.

### `/worklog cold [note]`

Move old dated entries from People, Programs and Threads notes to `Cold/`, verbatim.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/cold.md` and follow it. Do not act on this command from memory - the windows, pin rules, index label rules, copy-verify-delete order, gate and lookup ladder all live there.

- No argument: run the audit scanner, take `cold_candidates` and move every candidate, one note at a time, without per-note approval. The move is verbatim and gated. At the end, report what moved: note, entries moved, pins kept and why, warm size before and after.
- With an argument: that note only.
- Precondition: a clean vault git state. Check it once at the start of the run. If the vault is dirty, say so and offer `/worklog sync` first. When auto sync is on, run `sync.sh --auto` first instead and continue on exit 0, 3 or 4, then re-run the clean check; stop on 1 or 2. Move each note at most once per run.
- Log each note with op `cold` (see cold.md, Logging).
- End with a local commit (no push), message `worklog cold <date>: <n> notes`, like rollover. Before that commit, run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/shrink-check.sh '__VAULT_PATH__'` (cold moves are exempt, so it passes). Then suggest `/worklog sync`. When auto sync is on, run `sync.sh --auto` in place of the suggestion.
- The report also lists every warm line that points at moved content by position ("see below").
- Model: use Sonnet-tier or better for the move, because pin and label judgment need it. This is a note, not a guard. Do the work on whatever tier you are.

### `/worklog compact [note]`

Compaction and semantic lint for an oversized note. `/worklog cold` (lossless) normally handles size. Run compact's lossy fold only when the user explicitly asks for it.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/compact.md` and follow it. Do not act on this command from memory - the rules, the format and the guardrails all live there.

### `/worklog search <term>`

Search across Worklogs/, Archive/, People/, and Programs/ for items matching the
term. Use Grep to search all `.md` files, excluding `Cold/`. Show matches with their week/file,
priority, and status.

Then count the matches in `Cold/` with `grep -r -i -F -o -- '<term>' Cold/ | wc -l`. Report
"N more matches in cold storage" and do not read the cold files. Search only counts cold
matches. This is the one exception to reading per the ladder. The count is the cue for the
question in ladder step 5 (offer to show them).

When a match needs entity context to be intelligible, read it from the
`--with-summaries` digest rather than opening the note:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries
```

### `/worklog share`

Generate a concise status summary for Slack. Copy to clipboard via `pbcopy`:

```
This week (Apr 13):
P0s: Q2 cloud security plans, team charter draft, EM interviews, ...
P1s: Backend hiring follow-up, platform enablers kickoff, ...
Done: Team offsite travel booked
```

Brief titles only, no sub-notes, no wiki-link syntax, grouped by priority.

Clipboard only. Do not write a vault file - see `/worklog file` for what is worth
filing and why this is not.

### `/worklog rollup`

IC-facing weekly rollup: clipboard copy plus a filed reference note.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/rollup.md` and follow it. Do not act on this command from memory - the rules, the format and the guardrails all live there.

### `/worklog file [title]`

File the answer you just produced into the vault as a durable artifact. This is for
substantive analysis - a comparison, an investigation, a synthesis you were asked for -
not for routine command output.

Write `References/<title>.md`:

```markdown
---
type: reference
source: <what produced this, e.g. "conversation 2026-08-05" or "/worklog search">
---

# <Title>

<the answer, cross-linked per the Cross-Linking rules>
```

- Filename is the given title. With no title, derive `YYYY-MM-DD <Short Title>` from the
  content.
- Wiki-link every person and program per the Cross-Linking rules. An unlinked filed
  answer is a page nothing points at, which is most of its value gone.
- Create stub notes for any new entities, same as anywhere else.
- If the file exists, tell the user and ask whether to overwrite or pick a new title.

__Offer, do not assume.__ After producing a substantive analytical answer against the
vault, offer once to file it. Do not file without confirmation. This mirrors how
`Preferences/` capture works, and for the same reason: the user's confirmation is what
keeps the vault from filling with artifacts they did not want.

__Log it:__ append one entry with op `file` and target the filed path.

__What not to file:__ `/worklog share` output, which is a three-line blurb, and
`/worklog search` results, which are re-derivable by re-running the search.

### `/worklog summary [period]`

Week, month and quarter summaries.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/summary.md` and follow it. Do not act on this command from memory - the rules, the format and the guardrails all live there.

### `/worklog viz [period]`

Route per `## Model Routing` (Opus).

Generate standalone HTML D3 charts for a period. __Before executing, you MUST read
`__SKILL_INSTALL_PATH__/skills/worklog/references/viz.md` and follow it__ (full mechanics + template-fill
live there to keep this file small).

__Log it:__ append one entry with op `viz` and target the generated report path.

### `/worklog sync`

Vault git sync against the backup repo.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/sync.md` and follow it. Do not act on this command from memory - the rules, the format and the guardrails all live there. Manual and auto sync share the output lines and exit codes in `## Auto Sync`.

## Archiving

When a week is rolled over, move its file from `Worklogs/` to `Archive/` and
rewrite it as a summary:

```markdown
---
type: worklog
week: 2026-W15
date-start: 2026-04-06
date-end: 2026-04-10
status: archived
prev: "[[2026-W14]]"
programs:
  - "[[Platform Migration]]"
  - "[[Cloud Security]]"
people:
  - "[[Sarah Chen]]"
tags:
  - hiring
  - people-management
item-count: 9
done-count: 3
---

# Week of Apr 7, 2026

3 items completed, 6 items rolled forward to [[2026-W16]] (Platform Migration, Dev Sharma leave, ...):

- Completed item one
- Completed item two
- Completed item three
```

Use `[[wiki-links]]` for week cross-references. Summary lists completed and rolled
forward counts (with brief titles in parentheses). Only completed items as bullets.

__The archive is a summary because the history lives in `Threads/`, and only because of
that.__ Every file in `Archive/` has zero `^- \*\*P[012]\*\*` lines; the entire body of
`Archive/2026-W36.md` is `0 items completed, 37 items rolled forward to [[2026-W37]] (...)`.
That is correct only once every rolled-forward item's history has a durable home. Before it
did, the current week file was the sole surviving copy of every open item's past, and this
summary-style archive is what made it so.

So: __never archive a week whose rolled-forward items do not each have a verified Thread
note or a `Backlog.md` park entry.__ Check before rewriting the file, not after. An archive
write is the point of no return for a week file, and the ordering in
`references/threads.md` exists to keep this side of it safe.

Add one line to the archive body listing the Threads the week fed, so the archive is a
navigable index rather than a count:

```markdown
3 items completed, 28 items rolled forward to [[2026-W38]] (...), 9 parked to [[Backlog]],
31 Threads updated.

Threads: [[Threads/developer-onboarding-program-rollout|Developer Onboarding Program rollout]],
[[Threads/build-pipeline-review|build pipeline review]], ...
```

## Important Behaviors

- Always read the current file before making changes - the user may have edited
  directly in Obsidian.
- Use underscores for bold/italic in conversation (`__bold__` not `**bold**`).
- Always include priority and status when presenting items.
- Calculate ISO week numbers correctly for file naming.
- Write changes directly to files - no clipboard needed except `/worklog share`.
- Keep prompts short during review - Monday mornings are fast-paced.
- **Linking is non-negotiable.** Every time you write or edit ANY file in the vault,
  you must wiki-link all people and programs. This applies to worklogs, archive files,
  people notes, and program notes equally. Before finishing any file write, scan it
  for unlinked names. If someone is mentioned who doesn't have a note yet, create a
  stub note first, then link them. Use `slack_search_users` to resolve full names
  when only a first name or handle is given. The graph is only as good as its links.
- After major updates, remind the user to `/worklog sync` or offer to run it. When auto sync is on, skip this (see `## Auto Sync`).
- __Never truncate a vault file by accident.__ Write vault files only with the Edit or Write
  tools, or with a script that reads the whole file before it opens the file for writing. Never
  open a file for writing and read it in the same expression (for example
  `open(p,'w').write(open(p).read().replace(...))`), because opening the file for writing empties it first.
  After any scripted or bulk edit, run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/shrink-check.sh '__VAULT_PATH__'`
  before committing.
- **Suggest tidy proactively.** After adding 3+ items in a single session, or when the
  scanner's `week_volume` reports `over_threshold: true`, suggest running `/worklog tidy`
  to spill oversized items to `Threads/`, park dormant ones, balance subgroups, and fix
  frontmatter. Don't force it - just mention it once at the end of the session.

  __Do not gate this on top-level item count.__ The old threshold was "exceeds 20 top-level
  items", which is the one number this file's growth cannot move: `fold before you add`
  routes new facts into existing items, so item count held nearly flat across four weeks
  (126, 136, 144, 151) while the file grew to 953 KB. A threshold on the dimension a rule
  deliberately pins is a threshold that never fires on the dimension the same rule inflates.
  `week_volume` measures sub-item bytes and per-item sub-item counts instead.
- __A spill is a move, and the copy comes first.__ Spilling a week-file item to `Threads/`
  never runs on a vault that is dirty or not under git, never writes the week file before
  the Thread note is written and verified, and never drops a `[[wiki-link]]` target or a
  dated sub-item without the user confirming it by name. Archiving rewrites a week as a
  summary, so until the Thread note exists the week file is the only copy of that item's
  history. Order is the safety property here, not a preference. See
  `references/threads.md`.
- **Preferences are first-class.** `Preferences/` is the skill's general-purpose
  memory layer for anything durable about how the user works - voice, style,
  workflow, tooling, decision rules, vault conventions, formatting, defaults.
  Before any task with a preference-shaped surface (drafting communication,
  writing markdown, picking a tool, structuring a note, making a workflow choice),
  run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/preferences-index.sh '__VAULT_PATH__'`, pick the
  1-3 relevant preferences from the digest, and read only those bodies. When the user gives feedback
  that sounds durable - "always", "never", "from now on", repeated corrections,
  or quiet endorsements of non-obvious choices - offer to capture it as a
  `Preferences/` note. The user-approved capture is what makes this pattern
  compound over time; do not save without their confirmation.
- __Stale-channel nudge.__ At the top of `/worklog rollover`, `/worklog tidy`,
  and `/worklog audit`, glob `__VAULT_PATH__/Sources/*.md` and check
  `last_scan_ts` against `nudge_threshold_days` on each. Surface a one-line FYI
  for any stale source, then continue with the requested command. Other commands
  (`/worklog add`, `/worklog summary`, `/worklog viz`, `/worklog rollup`,
  `/worklog status`, `/worklog review`, `/worklog search`, `/worklog share`,
  `/worklog sync`) do __not__ nudge. If the user says "skip pull" or "not now"
  earlier in the session, suppress further nudges for that session.
- __Context channels are swept, not transcribed.__ Sources with `type: context-channel`
  are swept since `last_scan_ts`, classified by relevance, and high-confidence matches
  are folded directly into existing worklog items and People/Program/Team notes with a
  Slack permalink for provenance. They are __never__ written as `Meetings/` notes.
- __DM sweeps are approval-only and genericized.__ With `Sources/_dms.md` enabled, pulls
  also sweep the user's 1:1 + group DMs via Slack's Real-time Search API (the
  `slack-search-dms` helper). DM content is __never auto-folded__ — every relevant item
  routes through the one-by-one approval batch, and approved items are folded as genericized,
  workstream-level summaries with a Slack permalink. If the helper is missing/unauthorized
  (or DM-search consent is absent), the DM sweep is skipped and the channel pull is unaffected.
- __Log what you write.__ Any operation that changes the vault appends one entry to
  `Logs/YYYY-MM.md` via `__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh`.
  See `## Operations Log`. Read-only commands (`status`, `search`, `share`, an audit
  that applied nothing) write no entry.
- __Good answers are artifacts.__ A rollup files itself to `References/`. For any other
  substantive analysis you produce against the vault, offer once to file it with
  `/worklog file`. Filed answers are cross-linked, so they compound in the graph the
  same way ingested content does. Ephemeral by design: `share` and `search`.
- __Distributions are yours to judge.__ Three audit outputs (`oversized_notes`,
  `team_vocabulary`, `recurring_tags`) are tables, not to-do lists. The scanner is not
  claiming each row is a problem; it is handing you the full picture cheaply so you can
  say which rows matter. Never present a distribution row as a defect without saying why
  it is one.
- __Compaction is lossy and git is the undo.__ `/worklog compact` never runs on a vault
  that is dirty or not under git, never touches a top-level current-state section,
  never writes before the user has approved the fold, and never loses a
  `[[wiki-link]]` target without the user confirming it. Suggest it when
  `/worklog audit` reports `oversized_notes`, one note at a time, never in a batch.
- __Cold storage is lossless.__ `/worklog cold` moves old dated entries to `Cold/` verbatim,
  gated by `cold-gate.sh`, and never summarizes. Answer any question from the vault with the
  lookup ladder in `references/cold.md`. Read warm notes first. Always scan the `## Cold storage`
  index lines. Read cold files only as the ladder allows. ASK before you sweep all of `Cold/`.

## Integration commands (ingest, jira)

`/worklog ingest <url>`, `/worklog jira <key>`, and the `/worklog <arg>` auto-routing all
live in detail in `__SKILL_INSTALL_PATH__/skills/worklog/references/integrations.md`. __Before running any of these (or
auto-routing a bare `/worklog <arg>`), you MUST read that reference and follow it exactly__:
it names the MCP tool per action and the untrusted-content rules.

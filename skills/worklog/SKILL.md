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
  messages from a registered Slack source into the vault.
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

The vault is backed up to `__BACKUP_REPO_URL__` (private).

## Model Guard

Some worklog commands are heavy, single-shot synthesis and are more reliable on a more capable model. Before running one of those commands (each such section says "run the Model Guard first"), do this check:

1. Determine the current host from your system context.
2. If the host is Codex: proceed silently on the configured model and reasoning effort.
   Do not present the Claude-specific model choices below. If the result actually
   truncates or loses fidelity, explain that and suggest retrying with a more capable
   model or higher reasoning effort.
3. If the host is Claude Code:
   - Determine your model tier from your own context. Claude Code states this in your
     system prompt (for example, "You are powered by the model named ...").
   - Whatever the tier: __do the work.__ Never stop to ask the user to switch models, and
     never wait for an answer before starting.
   - If you are below the top tier and the result looks thin for the input - a long
     transcript summarized to a few lines, entities you could not resolve, a sweep you
     had to truncate - say so in one line at the end, after the work is done:

     > Ran this on `<your model>`. If the result reads thin, re-running on the most
     > capable Opus available at high effort may do better.

   - Say it once per conversation at most. If the result looks complete, say nothing.

Branch on tier, never on a version number. "The most capable Opus available" stays true
across releases; a named version goes stale and then misroutes every session after it.

This is advisory and never a gate. It does not fire for `add`, `review`, `audit`,
`rollover`, `pull`, single-item edits, or a week or month summary.

__Why it works this way.__ An earlier version paused and asked the user to switch to a
named model before doing anything. Measured against the eval fixtures, that guard was the
largest single cause of failed runs on `pull`: six of the eight non-Opus failures across
cases 16 and 18 were the guard firing and halting with no work done, and the one Sonnet
run where it did not fire scored a clean 8 of 8. A guard that trades a correct cheap run
for no run at all costs more than the model it was trying to avoid.

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
`Former Netflix`, `Unknown`, or `Partner`. Free text defeats the point of the property
for the org you actually track: the Teams dimension of the graph only works if `team:`
resolves to a note. When you do not know someone's team, write `Unknown` rather than
inventing a label or leaving a placeholder. If a real team in the org has no note yet,
create the `Teams/` note first, then reference it.

__Teams outside the org are different.__ Most people in the vault work elsewhere at the
company, and creating a `Teams/` note for every partner org would be more upkeep than the
graph is worth. For them, keep the real team name in `team:` even though it will not
resolve, because `Infra Product Design` tells you more than `Partner` does. Use `Partner`
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

The `Sources/` directory is the registry for Slack channels (and, in the future,
other content sources) that the skill ingests on demand via `/worklog pull`. One
file per registered channel, named after the channel without the leading `#`
(e.g., `Sources/example-meeting-notes.md`).

This is config + state. The frontmatter is machine-read; the body is human-readable
notes about the source.

__Source note structure:__

```markdown
---
type: meeting-notes-via-email
channel_name: "#example-meeting-notes"
channel_id: C0XXXXXXX
nudge_threshold_days: 5
last_scan_ts: null
first_scan_lookback_days: 14
---

# #example-meeting-notes

Notes about this source - what it is, who posts to it, anything worth remembering
about ingesting from this channel.
```

__Frontmatter fields:__

- `type`: source-type identifier. Supported values: `meeting-notes-via-email`
  (per-thread Meetings flow) and `context-channel` (sweep-and-classify flow, see
  below). The parser logic for `/worklog pull` is keyed off this value.
- `channel_name`: the human-readable Slack channel name with the `#` prefix.
- `channel_id`: the Slack channel ID (e.g., `C0XXXXXXX`). Resolved during
  registration via `slack_search_channels`.
- `nudge_threshold_days`: integer. If `last_scan_ts` is older than this, the
  stale-channel nudge fires on rollover/tidy/audit. Default 5.
- `last_scan_ts`: ISO 8601 timestamp of the last successful pull. `null` on first
  run (until the first pull completes). Updated per-thread during a pull, so a
  partial pull crash is resumable.
- `first_scan_lookback_days`: how many days back to look on first run. Default
  14. Ignored once `last_scan_ts` is non-null.

__When the user creates a new source manually:__ they may write a `Sources/<channel>.md`
by hand. Validate frontmatter on next `/worklog pull` and ask the user to fill in
any missing fields.

__Adding a new source inline:__ if the user says "register `#another-channel` as a
source" (or similar phrasing), resolve the channel ID via `slack_search_channels`,
write the new `Sources/<channel-name>.md` with template defaults, then run a first
pull against just that source.

__Registering a context channel:__ when the user says "register `#X` as a context
channel" (or hands over a list of important channels to sweep), resolve each via
`slack_search_channels`, confirm, and write `Sources/<channel-name>.md` with
`type: context-channel`, `last_scan_ts: null`, `first_scan_lookback_days: 7`,
`nudge_threshold_days: 5`. One file per channel (preserves per-channel state). The
list is the input to registration, not a stored config blob. Then run the first sweep
for the newly-registered channel(s).

### Source type: `context-channel`

A second source type for __high-traffic human-discussion channels__ you want swept
for worklog-relevant context (not forwarded-email meeting notes). Same registry,
same `Sources/<channel-name>.md` file shape — only `type` and the lookback default
differ:

```yaml
---
type: context-channel
channel_name: "#infrasec-leads"
channel_id: C0XXXXXXX
nudge_threshold_days: 5
last_scan_ts: null              # null on first run; advances per processed message
first_scan_lookback_days: 7     # smaller default than email sources (high-traffic)
---

# #infrasec-leads

Human-readable notes about this channel — what it's for, who's in it, why it's
worth sweeping.
```

Field semantics are identical to `meeting-notes-via-email` except:
- `type: context-channel` selects the sweep-and-classify pull flow (see `/worklog pull`).
- `first_scan_lookback_days` defaults to __7__ (not 14): a busy channel's first sweep
  over two weeks is large. Tunable per channel.

There are no `Meetings/` notes for this type — relevant content folds directly into
worklog items and People/Program/Team notes, with a Slack permalink for provenance.

### Source type: `dm-sweep`

A third source type that sweeps the user's Slack __direct messages and group DMs__
(MPIMs). DMs are searched (not enumerated), so there is __one__ config file for the whole
sweep, `Sources/_dms.md`:

```yaml
---
type: dm-sweep
enabled: true
include_1on1: true              # search im conversations
include_groups: true            # search mpim (group DM) conversations
last_scan_ts: null              # global baseline; first run = now − first_scan_lookback_days
first_scan_lookback_days: 3
nudge_threshold_days: 5
query: ""                       # optional salience query override; empty = built-in default
max_results: 100                # pagination cap and volume-guardrail threshold
exclude_users: []               # user IDs whose 1:1 DMs are dropped from results
exclude_conversations: []       # conversation IDs (im/mpim) dropped from results
---

# Direct Messages

Search-based DM + group-DM sweep via Slack's Real-time Search API. One global
`last_scan_ts`, incremental by message timestamp. DM content is __never auto-folded__:
everything routes through the approval batch and is folded only on approval, as a
genericized workstream-level summary.
```

Notes:
- A single global `last_scan_ts` governs the whole sweep (a message is new if
  `ts > last_scan_ts`, filtered server-side via the search `after` parameter — no local
  re-filtering needed); there is no per-conversation state.
- Discovery uses the `slack-search-dms` helper (Slack `assistant.search.context`), which
  returns only relevant DM messages with permalinks, surrounding thread context, and a bot
  flag. No enumeration or per-conversation reads.
- `include_1on1` / `include_groups` select the search `channel_types` (`im` and/or `mpim`).
- `query` overrides the built-in salience query; `max_results` caps pagination and is the
  volume-guardrail threshold (default 100).
- Requires one-time scopes `search:read.public` + `search:read.im` + `search:read.mpim` and
  in-client DM-search consent (see `docs/SETUP-SLACK.md`).

## Meetings

The `Meetings/` directory holds one markdown note per ingested Slack thread. These
are durable artifacts: a permanent, searchable record of every meeting whose notes
posted to a registered `Sources/*.md` channel. Linked into the knowledge graph
through wiki-links to participants and programs.

__Filename:__ `Meetings/YYYY-MM-DD-<topic-slug>.md`

- `YYYY-MM-DD` is the email-send date or the top-of-thread Slack timestamp,
  rendered in __the user's local timezone__ (matches how weekly files are dated).
- `<topic-slug>` is kebab-case from the email subject. Lowercase. Strip
  non-alphanumeric characters except hyphens. Cap at ~50 chars.
- On collision (same date + same slug), append `-2`, `-3`, etc.

__Meeting note structure:__

```markdown
---
type: meeting
date: 2026-05-04
source_channel: "#example-meeting-notes"
source_channel_id: C0XXXXXXX
slack_thread_ts: "1714694400.123456"
slack_last_reply_ts: "1714780800.654321"
slack_thread_url: https://example.slack.com/archives/C0X.../p171...
participants:
  - "[[Sarah Chen]]"
  - "[[Marcus Williams]]"
programs:
  - "[[Hiring]]"
status: ingested
---

# <Email Subject>

> [!info] Slack thread in [[Sources/example-meeting-notes|#example-meeting-notes]] · [open in Slack](https://...)
> Original sender: <name> · Posted 2026-05-04 09:00 PT

## Notes

<email body - meeting notes verbatim, lightly cleaned up: strip email-client
chrome (signatures, "On <date> X wrote:" quote blocks, unsubscribe footers),
keep the substantive content>

## Discussion

### 2026-05-04 09:15 — [[Sarah Chen]]
<reply>

### 2026-05-04 11:42 — [[Marcus Williams]]
<reply>

## Extracted Items

- See [[YYYY-WNN]] for items added to this week's worklog
```

__Frontmatter fields:__

- `type`: always `meeting` for files in this directory.
- `date`: YYYY-MM-DD of the email-send date or top-of-thread ts (user's local TZ).
- `source_channel`, `source_channel_id`: which `Sources/*.md` produced this note.
- `slack_thread_ts`: the top-level message's Slack timestamp - the unique thread
  identifier. Used by `/worklog pull` to look up "have we ingested this thread."
- `slack_last_reply_ts`: timestamp of the most recent reply ingested. Equals
  `slack_thread_ts` if the thread has no replies yet. Updated on every pull that
  appends new replies.
- `slack_thread_url`: deep link to the thread in Slack.
- `participants`: wiki-linked array of people who appear in the thread. Sourced
  from thread repliers + names mentioned in the email body. Use
  `slack_search_users` to resolve full names per the existing Cross-Linking rules.
- `programs`: wiki-linked array of programs mentioned in the thread.
- `status`: `ingested` once the meeting note + extraction are complete. Reserved
  for future statuses.

__Discussion section subheadings:__ `### YYYY-MM-DD HH:MM — [[Author]]` in the user's
local timezone, chronological order (oldest first). New replies appended to the
end of the section preserve chronological order naturally.

__User edits are preserved:__ on subsequent pulls, only the `## Discussion` section
is appended to and `slack_last_reply_ts` is updated. The `## Notes` section and
any user-added content elsewhere in the file is never overwritten. If the user
deletes a Meetings note, the next pull recreates it from scratch (because the
`slack_thread_ts` no longer matches any frontmatter).

__No frontmatter auto-generation:__ Meetings notes are not subject to the
Frontmatter Auto-generation rules below (those apply to weekly, archive, and
summary files). The participant/program wiki-link extraction for Meetings
frontmatter happens once at write time and is not regenerated on every edit.

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

That covers `add`, `pull`, `review`, `rollover`, `tidy`, `compact`, `summary`, `viz`,
`sync`, `preference` capture, filing an answer, and `audit` __only when fixes were applied__.
It excludes `status`, `search`, `share`, and a read-only audit run, because none of
those change the vault. Absence is informative too: no `pull` entries for three weeks
answers "when did I last ingest" just as well as a positive entry would.

__Always append through the helper__, never by editing the file directly:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' \
  <op> <target> 'first body line' 'second body line'
```

The helper creates the month file with frontmatter if absent and writes the entry as:

```markdown
## [2026-08-05] pull | #infrasec-leads
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

## Commands

### `/worklog` or `/worklog status`

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

Before processing a substantial input (a full transcript or a long notes doc, not a one-line add), run the Model Guard (see `## Model Guard`).

When the user pastes raw content (meeting notes, Slack threads, transcripts) and
asks to add it to the worklog, follow this pattern:

1. Read the current week file first
2. Extract actionable items from the raw input:
   - Action items and decisions become worklog items or sub-items
   - People mentioned become wiki-linked (create stubs if new)
   - Programs mentioned become wiki-linked
3. Check for overlaps with existing items - prefer adding sub-items to existing
   items over creating duplicates (e.g., if a meeting discussed an ongoing hiring
   effort, add context as sub-items under the existing hiring item)
4. For each new top-level item, assign a priority based on urgency/importance
   cues in the raw content. Default to P1 if unclear.
5. Add dated annotations using the date from the raw content (Slack timestamps,
   meeting date), not today's date
6. Update the current week file using the host's available file-editing tool
7. Update relevant people/program notes with substantive new context
8. Regenerate enriched frontmatter

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
3. Collect all items NOT `Done`
4. Check Backlog for items to surface
5. Create new week file with subgroups and wiki-links
6. Move current week to Archive with summary

Then ask if the user wants to add any new items.

__Log it:__ append one entry with op `rollover`, target the new week label, recording
items carried forward and items completed.

### `/worklog add <priority> <title>`

Add a new item to the current week file. Check for overlaps with existing items
and flag potential merges. Use the host's available file-editing tool to insert into the
appropriate subgroup
(or create a new subgroup if needed). Wiki-link any people or programs. Create stub
notes for new entities.

__Log it:__ append one entry with op `add`, target the item title.

### `/worklog tidy`

Before proceeding, run the Model Guard (see `## Model Guard`).

__Nudge check (run first):__ Same as `/worklog rollover` above - check
`Sources/*.md` and surface a stale-channel FYI before continuing.

Read the current week file and suggest cleanup:
1. Move Done items to a Done subgroup at the bottom
2. Flag Backlog items `In Progress` for 2+ weeks without notes
3. Flag duplicates between weekly file and backlog
4. Suggest items ready to archive
5. Suggest subgroup reorganization if themes shifted

Present as a checklist. Apply approved changes directly.

__Log it:__ if any changes were applied, append one entry with op `tidy` and target the
current week label. If nothing was applied, write no entry.

### `/worklog audit`

__Nudge check (run first):__ Same as `/worklog rollover` above - check `Sources/*.md` and
surface a stale-channel FYI before continuing.

__Operational health (run second):__ read the last 10 log entries:

```bash
cat '__VAULT_PATH__'/Logs/*.md | grep '^## \[' | tail -10
```

Surface two conditions alongside the vault findings: a `pull` entry recorded as partial,
and no `pull` entries at all in a window where the stale-source nudge is firing. Read
before writing, so an audit run never reports on itself. If `Logs/` does not exist yet,
skip this step silently.

Scan the vault for quality issues and present a fix-it checklist. No arguments.

__Run the scanner__ - it computes all nine checks in bash so no `People`/`Programs`
bodies load into context:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/audit-scan.sh '__VAULT_PATH__'
```

It prints JSON with nine keys. Six are __findings__, each entry an item to fix:
`stale_people`, `orphan_programs`, `stuck_items`, `missing_links`, `empty_stubs`,
`frontmatter_gaps`. Read __only__ this output - do not glob or read `People`/`Programs`
bodies yourself. The `stuck_items` and `missing_links` checks are heuristic; review each
and drop obvious misfires before presenting.

Three are __distributions__, not findings. Each is a compact table where the judgment is
yours, not the scanner's, because correctness is not decidable in bash:

- `oversized_notes` - findings-shaped, actually: `{file, lines, compacted}` for every
  note over `WORKLOG_COMPACT_LINES` (default 250). `compacted` is the note's frontmatter
  value or null, so a note that was compacted and has grown again is distinguishable from
  one never compacted. Offer `/worklog compact <file>` for each.
- `team_vocabulary` - `{value, notes, resolves, candidate?}` for every distinct `team:`
  value on People notes. `resolves` is `exact`, `substring`, or `none` against the
  `Teams/` note names. Propose merge groups from this and let the user approve them one
  at a time; do not rewrite `team:` values unasked. A value resolving `none` is often
  correct: `External`, `Former Netflix`, `Unknown`, and `Partner` are reserved, and a team
  outside the org is recorded by name on purpose, since a `Teams/` note for every partner
  org would be more upkeep than the graph is worth. Treat `none` as drift only when the
  value names a team the org owns, which is what merge groups are for.
- `recurring_tags` - `{tag, files, has_page}` for tags appearing in 3 or more weekly or
  archive files. Judge which recurring themes deserve a `Programs/` or `References/`
  page. Most do not: `strategy`, `growth`, `leadership`, and `team-health` are themes,
  not programs. Suggest a page only where the tag names a specific effort with an owner
  or an end state.

Present the findings grouped by check type, each with a suggested action, e.g.:

```
Vault audit results:

Stale people (not mentioned in 4+ weeks):
- People/Jordan Lee.md - last seen in W19
  Suggested: archive, update context, or remove if no longer relevant

Stuck items (3+ weeks without update):
- "Figure out Q2 plans across Cloud Security" - P0 since W14
  Suggested: add a status update or reprioritize

Missing links:
- Worklogs/2026-W23.md:23 "Tom" -> [[Tom Rivera|Tom]]

Frontmatter gaps:
- Archive/2026-W11.md: missing programs, people

Oversized notes (over 250 lines):
- People/Christine Chalmers.md - 1536 lines, never compacted
  Suggested: /worklog compact "People/Christine Chalmers.md"

Team vocabulary (86 values, 7 resolve exactly):
- "Security, Privacy & Assurance" (7 notes) and "SPA" (2 notes) look like one org
  Suggested: merge both into a Teams/ note, or map to the reserved set

Recurring tags without a page:
- spa-leadership-transition (6 weeks) - names a specific effort, page looks warranted
- strategy (16 weeks) - a theme, no page needed
```

The user picks which fixes to apply. Apply approved fixes directly with Edit/Write; for
frontmatter gaps, regenerate using the Frontmatter Auto-generation rules. The check
definitions live in `scripts/audit-scan.sh` — do not re-derive them here.

If the user approved and you applied any fixes, append one log entry naming what was
fixed. If nothing was applied, write no entry.

### `/worklog compact [note]`

Compaction and semantic lint for an oversized note.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/compact.md` and follow it. Do not act on this command from memory - the rules, the format and the guardrails all live there.

### `/worklog search <term>`

Search across Worklogs/, Archive/, People/, and Programs/ for items matching the
term. Use Grep to search all `.md` files. Show matches with their week/file,
priority, and status.

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

Before proceeding, run the Model Guard (see `## Model Guard`).

Generate standalone HTML D3 charts for a period. __Before executing, you MUST read
`__SKILL_INSTALL_PATH__/skills/worklog/references/viz.md` and follow it__ (full mechanics + template-fill
live there to keep this file small).

__Log it:__ append one entry with op `viz` and target the generated report path.

### `/worklog sync`

Vault git sync against the backup repo.

Read `__SKILL_INSTALL_PATH__/skills/worklog/references/sync.md` and follow it. Do not act on this command from memory - the rules, the format and the guardrails all live there.

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
- After major updates, remind the user to `/worklog sync` or offer to run it.
- **Suggest tidy proactively.** After adding 3+ items in a single session, or when
  the current week file exceeds 20 top-level items, suggest running `/worklog tidy`
  to keep subgroups balanced, consolidate stale sub-items, and fix frontmatter.
  Don't force it - just mention it once at the end of the session.
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

## Netflix-specific commands (this fork only)

`/worklog ingest <url>`, `/worklog whois <name|email>`, `/worklog jira <key>`, and the
`/worklog <arg>` auto-routing all live in detail in
`__SKILL_INSTALL_PATH__/skills/worklog/references/netflix-commands.md`. __Before running any of these (or
auto-routing a bare `/worklog <arg>`), you MUST read that reference and follow it exactly__ —
it names the exact MCP tool per action and the untrusted-content rules.

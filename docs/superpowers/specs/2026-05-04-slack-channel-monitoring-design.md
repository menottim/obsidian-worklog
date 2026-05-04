---
title: Slack Channel Inbox — Design
date: 2026-05-04
status: draft
feature: slack-channel-monitoring
---

# Slack Channel Inbox — Design

Add a new capability to the `worklog` skill that pulls unprocessed messages from a designated Slack channel into the user's Obsidian vault. The initial scope is narrow: one source type — __meeting-notes-via-email__ — where each thread starts with an automated post containing a forwarded email (meeting notes from a Google Group) and continues with human discussion.

The skill is the reader of Slack, not just a consumer of pasted content. State of "what has been processed" lives in the vault as markdown-with-frontmatter, consistent with the rest of the skill.

## Goals

- Pull on demand: a single command ingests new threads and new replies to known threads from a registered channel.
- Persistent meeting-note artifacts: each thread becomes a `Meetings/` markdown file the user can search, link, and reference indefinitely.
- Action-item flow continuity: the existing __Processing raw input__ pipeline (extract items into the current week, link People/Programs, date everything) runs against pulled content with no changes.
- Proactive nudge: when a session-level worklog ritual happens (rollover, tidy, audit) and the channel hasn't been pulled in a while, the skill surfaces a soft reminder.

## Non-goals (v1)

- Multiple source __types__ (general discussion, announcement channels). Stay narrow; design does not preclude adding types later.
- Background or scheduled pulls. The skill runs only inside an active session; the nudge is the cadence mechanism.
- Bidirectional sync (writing reactions, replies, or any state back to Slack).
- A polished multi-channel UX. Multiple channels can be registered (each gets its own `Sources/` file), but the v1 command treats them as a flat list.

## Architecture

Two new vault concepts and one new command.

### Sources/

`Sources/<channel-name>.md` — registry of registered channels. One file per channel. Carries channel-level state.

```yaml
---
type: meeting-notes-via-email
channel_name: "#example-meeting-notes"
channel_id: C0XXXXXXX
nudge_threshold_days: 5
last_scan_ts: null            # null on first run; advances per pull
first_scan_lookback_days: 14
---

# #example-meeting-notes

Notes about this source — what it is, who posts to it, anything the user
wants to remember about ingesting from this channel.
```

The body of the file is human-readable notes about the source; only frontmatter is machine-read.

### Meetings/

`Meetings/YYYY-MM-DD-<topic-slug>.md` — one file per ingested thread. Carries per-thread state in frontmatter.

```yaml
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

<email body — meeting notes verbatim, lightly cleaned up>

## Discussion

### 2026-05-04 09:15 — [[Sarah Chen]]
<reply>

### 2026-05-04 11:42 — [[Marcus Williams]]
<reply>

## Extracted Items

- See [[YYYY-WNN]] for items added to this week's worklog
```

__Filename rules:__
- `YYYY-MM-DD` from the email date or top-of-thread Slack timestamp, rendered in the user's local timezone (matches how weekly files are dated).
- `<topic-slug>` is kebab-case from the email subject. Cap at ~50 chars. On collision (same date + same slug), append `-2`, `-3`, etc.
- Date/time subheadings under `## Discussion` (`### 2026-05-04 09:15 — [[Author]]`) also render in the user's local timezone.

### Command

`/worklog pull` — new command. Reads `Sources/*.md`, fetches new content from each registered channel, writes/updates `Meetings/` files, runs the existing item-extraction pipeline against the new content, updates `last_scan_ts`.

## Pull flow

1. Read all `Sources/*.md`. (v1 will typically have one.)
2. For each source:
   1. Use `slack_read_channel` to list top-level messages with `ts > last_scan_ts`. On first run (`last_scan_ts` is null), look back `first_scan_lookback_days` (default 14).
   2. For each thread:
      1. Use `slack_read_thread` to fetch full thread (top-level message + all replies).
      2. Look up `slack_thread_ts` in existing `Meetings/*.md` frontmatter.
      3. __New thread__ (no match):
         - Create `Meetings/YYYY-MM-DD-<slug>.md` with frontmatter and body per schema above.
         - Run __Processing raw input__ pipeline (SKILL.md §"Processing raw input") against the meeting body + replies → action items into current week file, People/Programs wiki-linked and updated, dated annotations using actual Slack timestamps.
      4. __Existing thread, new replies__ (match found, replies after `slack_last_reply_ts`):
         - Append the new replies to `## Discussion` with chronological date/time/author subheadings.
         - Update `slack_last_reply_ts` in frontmatter.
         - Run extraction on the appended content only.
   3. Update `last_scan_ts` on `Sources/<channel>.md` to the current time.
3. Print a summary: _N new threads, M updated, K items extracted to [[YYYY-WNN]]_.

## Source registration (first run)

When `/worklog pull` runs and `Sources/` is empty:

1. Skill: _"You don't have any channels registered yet. Which channel should I monitor?"_
2. User: name or `#channel-name`.
3. Skill resolves channel ID via `slack_search_channels`. Shows match for confirmation.
4. Skill writes `Sources/<channel-name>.md` with the template above (`last_scan_ts: null`, defaults for thresholds).
5. Skill proceeds with the first pull.

Subsequent runs skip registration and pull directly.

Adding additional channels in v1: the user creates a new `Sources/<channel-name>.md` by hand (copying the template from an existing one or asking the skill to write one), or asks the skill to register a new channel inline ("register `#another-channel` as a source"). The skill recognizes that phrasing and writes the file. There is no dedicated `/worklog source add` command in v1 — see Out of scope.

## Item extraction (re-uses existing pipeline)

The Meetings note is the durable artifact. Action items still flow into the current week file via the existing __Processing raw input__ section of `skills/worklog/SKILL.md`:

1. Extract actionable items + decisions → current week file, with priority assigned (default P1 if unclear).
2. Wiki-link people and programs; create stubs for unknown entities.
3. Date annotations use the Slack timestamp from the thread/reply, not today's date.
4. Update relevant People/Programs notes with substantive new context.
5. Regenerate enriched frontmatter on touched notes.

No new extraction logic. The pull command's job is to fetch and shape; the extraction pipeline is already there.

## Nudge behavior

At the top of these commands — `/worklog rollover`, `/worklog tidy`, `/worklog audit` — read each `Sources/*.md`. If `last_scan_ts` is `null` or older than `nudge_threshold_days` (default 5), prepend a one-line FYI before continuing with the requested command:

> FYI — last pulled `#example-meeting-notes` 7 days ago. Run `/worklog pull` to ingest new threads. Continuing with rollover...

Other commands (`/worklog add`, `/worklog summary`, `/worklog viz`, `/worklog rollup`) do not nudge.

If the user explicitly says "skip pull" or "not now" earlier in the session, suppress nudges for the rest of the session.

Threshold rationale: 5 days catches "missed a couple of days" without nagging on a daily Mon/Tue cadence. Configurable per-source via `nudge_threshold_days` in `Sources/<channel>.md`.

## Error handling & edge cases

- __Slack MCP not installed/available__ — fail fast with a clear message: _"This needs a Slack MCP plugin. Install one and re-run."_ Don't fall back to anything fancy.
- __Channel not found or ambiguous__ during registration — show top fuzzy matches from `slack_search_channels`. Ask user to pick or correct.
- __Email file content not readable as a file__ — Slack message bodies for forwarded-email-to-channel posts may render as a file attachment, a styled card, or rendered text depending on the integration. If the file body isn't directly fetchable, fall back to the bot's posted message text and warn once per pull: _"Couldn't extract email file body for thread X — used Slack-rendered text instead. Fidelity may be lower."_ This unblocks v1 even if file-attachment fetching turns out to be flaky in the available MCP tools.
- __Rate limit / partial pull__ — advance `last_scan_ts` per thread (not per pull), so a crash halfway through resumes cleanly on the next invocation.
- __User deleted a Meetings note__ — the next pull recreates it because the `slack_thread_ts` no longer matches any frontmatter. By design.
- __User edited a Meetings note__ — only `## Discussion` is appended to and `slack_last_reply_ts` is updated. The `## Notes` section and any user-added content elsewhere is never overwritten.
- __Thread with no replies__ — Meetings note is created with an empty `## Discussion` section; `slack_last_reply_ts` equals `slack_thread_ts`.
- __Tombstone messages__ (deleted in Slack after we ingested) — leave the Meetings note alone; we do not "un-ingest." Note the gap if it ever matters.

## Testing

### Eval scenarios (evals.json)

- __Idempotency__ — simulated channel with 3 threads. Run `/worklog pull` twice. Expect: first run creates 3 Meetings notes and N items; second run creates/changes nothing.
- __Thread evolution__ — same channel; add a reply to thread 2 between pulls. Second pull should append exactly one reply under `## Discussion` for thread 2, update `slack_last_reply_ts`, extract any items in that reply, and leave threads 1 and 3 untouched.
- __First-run registration__ — empty `Sources/`. Pull triggers registration flow; user provides channel; Source file written; pull proceeds.
- __Nudge__ — Source with `last_scan_ts` set to 7 days ago. `/worklog rollover` should surface the nudge; `/worklog add` should not.

### Manual smoke

Register the real channel, run `/worklog pull`, then verify:
- Meetings notes match the schema; participants and programs are wiki-linked correctly.
- Items appear in the current week file with Slack-timestamp dates, not today's date.
- People/Programs notes have new dated annotations from the meeting content.
- A second pull immediately after produces no changes.

## Out of scope (v1)

- Multiple source types beyond `meeting-notes-via-email`.
- Auto-trigger via cron, scheduled tasks, or background polling.
- Writing reactions, replies, or any state back to Slack.
- A `/worklog pull #specific-channel` filter argument. The flat all-sources iteration is enough for v1; trivial to add later.
- A separate `/worklog source add` registration command. v1 prompts inline on first pull; if multi-source registration becomes friction, lift to its own command later.

## Open questions for the implementation plan

These are not design decisions — they're things to validate during implementation:

1. Which Slack MCP tool actually returns file-attachment content for forwarded-email posts in this user's environment? `slack_read_channel`, `slack_read_thread`, or do we need a separate fetch? The fallback path covers either way, but the happy-path test should pin this down.
2. How does the channel's automated bot identify itself in `user`/`bot_id` fields? We may want to filter so only bot-posted top-of-thread messages are treated as "meeting starts" — anything else might be a side conversation.
3. What's the right `participants` extraction policy for the meeting note? Top-of-thread is the bot, so participants come from thread repliers + names mentioned in the email body. The existing People-resolution logic via `slack_search_users` handles the @mention case; the email body case may need a lightweight pass.

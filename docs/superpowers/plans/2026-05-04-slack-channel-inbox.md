# Slack Channel Inbox Implementation Plan

> __For agentic workers:__ REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

__Goal:__ Add a `/worklog pull` command and supporting vault structure that ingests unprocessed threads (each starting with an automated email-to-channel post) from a registered Slack channel into the user's Obsidian vault.

__Architecture:__ Two new vault directories (`Sources/`, `Meetings/`) with markdown-with-frontmatter as the state model — vault is the source of truth. New `/worklog pull` command iterates registered Sources, fetches new threads via Slack MCP tools, writes Meetings notes, and feeds the existing __Processing raw input__ pipeline for action-item extraction. Stale-channel nudge is added at the top of `/worklog rollover`, `/worklog tidy`, and `/worklog audit`.

__Tech Stack:__ Markdown + YAML frontmatter (no executable code in the skill itself). Slack MCP tools (`slack_read_channel`, `slack_read_thread`, `slack_search_channels`). Obsidian wiki-link conventions. Plan file edits all go to `skills/worklog/SKILL.md`, `examples/`, `README.md`, `evals/evals.json`, `.claude-plugin/plugin.json`.

__Note on testing:__ This skill has no executable code — "tests" are eval scenarios in `evals/evals.json` (a hand-curated list of prompts + expected behaviors). The TDD adaptation: write the eval first (defines the expected user-facing behavior), confirm SKILL.md doesn't yet document that behavior (the test "fails"), then update SKILL.md so a Claude session reading it would behave as expected (the test "passes"). End-to-end verification at the end is a manual smoke test against the real registered channel.

__Reference design spec:__ `docs/superpowers/specs/2026-05-04-slack-channel-monitoring-design.md`

---

## File Structure

__Modify:__
- `skills/worklog/SKILL.md` — main skill file. Add Sources/Meetings sections, new `/worklog pull` command, nudge behavior on rollover/tidy/audit, Important Behaviors update, vault layout update, trigger-phrase additions in the description frontmatter.
- `evals/evals.json` — add 5 new eval scenarios for the new feature.
- `README.md` — Vault Structure, What You Get, Commands list, FAQ entry.
- `.claude-plugin/plugin.json` — version bump to 5.3.0, description update.

__Create:__
- `examples/source-note.md` — template for a `Sources/<channel>.md` file.
- `examples/meeting-note.md` — template for a `Meetings/YYYY-MM-DD-<slug>.md` file.

__Do not touch:__
- `setup.sh` — does not currently create `Teams/` or `Preferences/` either; lazy creation by the skill is the established convention. Adding `Sources/`/`Meetings/` to setup.sh would be an unrelated refactor.
- Existing example files (`weekly-file.md`, `archive-file.md`, `summary-file.md`, `person-note.md`, `program-note.md`).

---

## Task 1: Add eval scenarios for the new feature

__Files:__
- Modify: `evals/evals.json`

- [ ] __Step 1: Read the existing evals.json to understand format__

Run: `cat evals/evals.json`
Expected: a JSON object with `skill_name: "worklog"` and an `evals` array of 7 objects, each having `id`, `prompt`, `expected_output`, and `issue_tested` keys. Highest existing id is 7.

- [ ] __Step 2: Add 5 new eval scenarios__

Edit `evals/evals.json`. Replace the closing `]` of the `evals` array (and the trailing `}`) with the following appended scenarios. The final file should still be valid JSON.

```json
,
    {
      "id": 8,
      "prompt": "/worklog pull",
      "expected_output": "On first run with empty Sources/ directory: should walk the user through registering one channel - ask for channel name, resolve via slack_search_channels, write Sources/<channel-name>.md with type=meeting-notes-via-email, channel_id, last_scan_ts=null, nudge_threshold_days=5, first_scan_lookback_days=14. Then proceed with the first pull.",
      "issue_tested": "First-run registration flow when no Sources/ files exist"
    },
    {
      "id": 9,
      "prompt": "/worklog pull (run a second time within seconds, no new Slack content)",
      "expected_output": "Should be idempotent: no new Meetings/ files created, no existing files modified, no items added to current week file. Should advance Sources/<channel>.md last_scan_ts to current time. Summary should report 0 new threads, 0 updated, 0 items extracted.",
      "issue_tested": "Idempotency - re-running pull with no new Slack content must not duplicate or rewrite anything"
    },
    {
      "id": 10,
      "prompt": "/worklog pull (with 1 existing Meetings/ note that has new replies in Slack since last_scan_ts)",
      "expected_output": "Should look up slack_thread_ts in existing Meetings/*.md frontmatter, find the match, fetch only replies after slack_last_reply_ts, append them to ## Discussion with chronological date/author subheadings in user's local timezone, update slack_last_reply_ts in frontmatter, and run extraction on the appended content only. Should NOT rewrite ## Notes or any other existing content. Should NOT create a new Meetings note for the same thread_ts.",
      "issue_tested": "Thread evolution - existing threads with new replies append cleanly without overwriting"
    },
    {
      "id": 11,
      "prompt": "/worklog rollover (with Sources/<channel>.md last_scan_ts older than 5 days)",
      "expected_output": "Should prepend a one-line FYI before continuing with rollover: 'FYI - last pulled #channel-name N days ago. Run /worklog pull to ingest. Continuing with rollover...' Then perform the normal rollover. Should NOT block, hijack the command, or auto-pull.",
      "issue_tested": "Stale-channel nudge surfaces on rollover when threshold exceeded"
    },
    {
      "id": 12,
      "prompt": "/worklog add P1 sync with Sarah about hiring (with Sources/<channel>.md last_scan_ts older than 5 days)",
      "expected_output": "Should add the item normally without surfacing the stale-channel nudge. /worklog add is not in the nudge-eligible command set; only rollover, tidy, and audit are.",
      "issue_tested": "Stale-channel nudge does NOT surface on commands outside the nudge-eligible set"
    }
  ]
}
```

The full evals array should now contain 12 objects (id 1-12).

- [ ] __Step 3: Verify evals.json is still valid JSON__

Run: `python3 -c "import json; json.load(open('evals/evals.json')); print('valid')"`
Expected: `valid`

- [ ] __Step 4: Commit__

```bash
git add evals/evals.json
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "Add eval scenarios for /worklog pull and nudge behavior"
```

---

## Task 2: Update Vault Layout and key paths in SKILL.md

__Files:__
- Modify: `skills/worklog/SKILL.md` (Vault Layout block at lines ~21-55, key paths list at lines ~66-74)

- [ ] __Step 1: Update the Vault Layout code block__

In `skills/worklog/SKILL.md`, find this block (starts around line 21):

```
__VAULT_PATH__/
  Worklogs/
    YYYY-WNN.md          # Current week (one file per week, YYYY-[W]WW.md)
    Backlog.md           # Persistent backlog (not per-week)
  People/
```

After the `Preferences/` block and __before__ the `Archive/` block, insert two new blocks. The complete updated layout should read:

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
  Archive/
    YYYY-WMM.md          # Completed weeks
    ...
  Summaries/
    YYYY-WNN.md          # Weekly summary
    YYYY-Month.md        # Monthly summary
    YYYY-QN.md           # Quarterly summary
  Reports/
    YYYY-Month-viz.html  # D3 visualization (open in browser)
  Templates/
    Weekly.md            # Templater template for new weeks
```

- [ ] __Step 2: Update the key paths list__

Find the `Other key paths:` block (around line 66). It currently reads:

```markdown
Other key paths:
- Backlog: `__VAULT_PATH__/Worklogs/Backlog.md`
- Archive: `__VAULT_PATH__/Archive/YYYY-[W]WW.md`
- Summaries: `__VAULT_PATH__/Summaries/<period>.md`
- Reports: `__VAULT_PATH__/Reports/<period>-viz.html`
- People: `__VAULT_PATH__/People/<Name>.md`
- Programs: `__VAULT_PATH__/Programs/<Name>.md`
- Teams: `__VAULT_PATH__/Teams/<Name>.md`
- Preferences: `__VAULT_PATH__/Preferences/<Title>.md`
```

Append two new lines:

```markdown
- Sources: `__VAULT_PATH__/Sources/<channel-name>.md`
- Meetings: `__VAULT_PATH__/Meetings/YYYY-MM-DD-<topic-slug>.md`
```

- [ ] __Step 3: Verify the changes__

Run: `grep -n "Sources/\|Meetings/" skills/worklog/SKILL.md | head -10`
Expected: matches in both the layout block and the key paths list.

- [ ] __Step 4: Commit__

```bash
git add skills/worklog/SKILL.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "SKILL.md: add Sources/ and Meetings/ to vault layout"
```

---

## Task 3: Add Sources section to SKILL.md

__Files:__
- Modify: `skills/worklog/SKILL.md` (insert new top-level section)

- [ ] __Step 1: Locate the insertion point__

Run: `grep -n "^## Preferences\|^## Frontmatter Auto-generation" skills/worklog/SKILL.md`
Expected: shows the line numbers of `## Preferences` and `## Frontmatter Auto-generation`.

The new `## Sources` section goes __between Preferences (and its sub-sections) and Frontmatter Auto-generation__, immediately before the Frontmatter Auto-generation section. The Preferences section ends at the line just before `## Frontmatter Auto-generation`.

- [ ] __Step 2: Insert the Sources section__

Insert this section directly above the line `## Frontmatter Auto-generation`:

```markdown
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

- `type`: source-type identifier. v1 supports only `meeting-notes-via-email`. The
  parser logic for `/worklog pull` is keyed off this value.
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
```

- [ ] __Step 3: Verify the insertion__

Run: `grep -n "^## Sources\|^## Frontmatter Auto-generation\|^## Preferences" skills/worklog/SKILL.md`
Expected: `## Preferences`, `## Sources`, `## Frontmatter Auto-generation` appear in that order with `## Sources` between the other two.

- [ ] __Step 4: Commit__

```bash
git add skills/worklog/SKILL.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "SKILL.md: add Sources section documenting channel registry"
```

---

## Task 4: Add Meetings section to SKILL.md

__Files:__
- Modify: `skills/worklog/SKILL.md` (insert new top-level section after Sources)

- [ ] __Step 1: Insert the Meetings section__

Insert this section directly after the `## Sources` section (and before `## Frontmatter Auto-generation`):

```markdown
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
```

- [ ] __Step 2: Verify the insertion__

Run: `grep -n "^## Sources\|^## Meetings\|^## Frontmatter Auto-generation" skills/worklog/SKILL.md`
Expected: `## Sources`, `## Meetings`, `## Frontmatter Auto-generation` in that order.

- [ ] __Step 3: Commit__

```bash
git add skills/worklog/SKILL.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "SKILL.md: add Meetings section documenting meeting note schema"
```

---

## Task 5: Add `/worklog pull` command section

__Files:__
- Modify: `skills/worklog/SKILL.md` (insert new command section)

- [ ] __Step 1: Locate the insertion point__

The new `### /worklog pull` section goes inside the `## Commands` section, immediately after `### Processing raw input (meeting notes, Slack messages, transcripts)` and before `### /worklog rollover`. This places it next to the related extraction logic, since it re-uses that pipeline.

Run: `grep -n "^### Processing raw input\|^### \`/worklog rollover\`" skills/worklog/SKILL.md`
Expected: shows the line numbers; insert between them.

- [ ] __Step 2: Insert the /worklog pull section__

Insert this section between the `### Processing raw input ...` section and the `### /worklog rollover` section:

```markdown
### `/worklog pull`

Ingest unprocessed messages from registered Slack channels into the vault. Each
thread becomes a `Meetings/YYYY-MM-DD-<slug>.md` artifact, and the existing
__Processing raw input__ pipeline runs against the meeting body + replies to
extract action items into the current week file.

__Pull flow:__

1. Glob `__VAULT_PATH__/Sources/*.md`. If empty, walk the user through registering
   one channel (see __First-run registration__ below) and continue with that
   channel only.
2. For each source file, parse the frontmatter (`channel_id`, `last_scan_ts`,
   `first_scan_lookback_days`). Compute the lookback window:
   - If `last_scan_ts` is `null`: window starts `first_scan_lookback_days` ago.
   - Otherwise: window starts at `last_scan_ts`.
3. Use `slack_read_channel` to list top-level messages in `channel_id` posted
   after the window start.
4. For each top-level message (a thread):
   1. Use `slack_read_thread` to fetch the full thread (top message + all replies).
   2. Glob `__VAULT_PATH__/Meetings/*.md` and grep frontmatter for a match on
      `slack_thread_ts`.
   3. __New thread__ (no match):
      - Compute the meeting note filename: `YYYY-MM-DD-<topic-slug>.md` per the
        rules in the Meetings section. Date is the top-of-thread ts in user's
        local timezone; slug is from the email subject.
      - On filename collision, append `-2`, `-3`, etc. until unique.
      - Build the Meetings note body per the schema in the Meetings section.
        - `## Notes`: extract the email body from the top-of-thread post (see
          __Email body extraction__ below). Lightly clean up: strip email-client
          chrome (signatures, quoted reply blocks, unsubscribe footers); preserve
          substantive content.
        - `## Discussion`: each reply becomes a `### YYYY-MM-DD HH:MM — [[Author]]`
          subheading (user's local TZ, chronological), followed by the reply text.
          Resolve author names via `slack_search_users` if only a handle/ID is
          available.
        - `## Extracted Items`: leave as a single line pointing to the current
          week file: `- See [[YYYY-WNN]] for items added to this week's worklog`.
      - Build frontmatter per the schema in the Meetings section. Set
        `slack_last_reply_ts` equal to `slack_thread_ts` if the thread has no
        replies; otherwise to the timestamp of the latest reply.
      - Resolve participants: union of (thread repliers, names @-mentioned in the
        email body, names in the email body's "Attendees:" / "Participants:"
        section if present). Wiki-link all; create stub People notes for any
        unknown names per existing Cross-Linking rules.
      - Resolve programs: glob `Programs/*.md` for known names; scan the meeting
        body for matches; wiki-link.
      - Write the new `Meetings/YYYY-MM-DD-<slug>.md`.
      - Run the __Processing raw input__ pipeline (above) against the meeting
        body + replies, treating the meeting date as the source date for action
        items. Items go into the __current__ week file (the user's actual current
        week, not the meeting's week, since the meeting's week may be in the
        archive). Sub-item dated annotations use the actual Slack timestamps from
        the thread, not today's date.
   4. __Existing thread, new replies__ (match found, replies after
      `slack_last_reply_ts`):
      - Open the matched `Meetings/*.md` with the Edit tool.
      - For each reply with `ts > slack_last_reply_ts`, append a
        `### YYYY-MM-DD HH:MM — [[Author]]` subheading to the end of the
        `## Discussion` section, followed by the reply text.
      - Update the frontmatter: set `slack_last_reply_ts` to the timestamp of
        the most recent reply just appended. Update `participants` if any new
        people appeared (preserve existing entries).
      - Run the __Processing raw input__ pipeline against __only the appended
        replies__, not the full meeting again. This avoids duplicating items.
   5. __Existing thread, no new replies__ (match found, no replies after
      `slack_last_reply_ts`): skip. No file changes.
   6. After processing each thread, advance `last_scan_ts` on the source file to
      the timestamp of that thread (or that reply, for thread-evolution updates).
      This makes a mid-pull crash resumable.
5. After all threads are processed for a source, set `last_scan_ts` to the
   current time (now).
6. Repeat for the next source file.
7. Print a summary:
   - `<N> new threads ingested` (with the new Meetings note paths)
   - `<M> threads updated` (with thread titles)
   - `<K> items extracted to [[YYYY-WNN]]`
   - For each source pulled, the new `last_scan_ts`.

__First-run registration:__

When `Sources/` is empty (or the user explicitly asks to register a new channel):

1. Ask: "Which channel should I monitor? (give the channel name, with or without
   the leading #)"
2. Use `slack_search_channels` to resolve the name to a channel ID. If multiple
   matches, present the top results and let the user pick.
3. Confirm with the user: "Register `#<channel>` (id `C0XXXXXXX`) as a
   `meeting-notes-via-email` source?"
4. On confirmation, write `__VAULT_PATH__/Sources/<channel-name>.md` (channel name
   without the `#`, kebab-case), populated from the template in the Sources
   section: `type: meeting-notes-via-email`, `channel_name`, `channel_id`,
   `nudge_threshold_days: 5`, `last_scan_ts: null`, `first_scan_lookback_days: 14`,
   plus a brief body line about what the channel is.
5. Proceed with the first pull (lookback = `first_scan_lookback_days` days).

__Email body extraction:__

The top-of-thread post in a `meeting-notes-via-email` channel is an automated
post from Slack's email-to-channel integration (or a similar bot). Depending on
how the integration renders the email, the body may be:

(a) A file attachment (`.eml` or similar) on the message - in which case it may
    not be directly readable through the available Slack MCP tools.
(b) The email body inlined as the message text.
(c) A styled card / Slack Block Kit message containing the email body.

Try the message text first (simplest case). If the body looks empty or
truncated, fall back to whatever message preview / file content is available
through the Slack MCP tool response. If the email body is not accessible at
all in this environment, warn once per pull:

> Couldn't extract email file body for thread `<title>` - used Slack-rendered
> text instead. Fidelity may be lower.

Continue ingesting the thread with whatever text is available. The thread
replies are always normal Slack messages and never have this problem.

__Errors and edge cases:__

- __Slack MCP not available:__ fail with: "This needs a Slack MCP plugin. Install
  one and re-run." Do not silently skip.
- __Channel not found / ambiguous__ during registration: show the top matches
  from `slack_search_channels` and let the user pick.
- __Rate limit hit mid-pull:__ `last_scan_ts` advances per thread, so the next
  pull resumes from where we left off. Tell the user it was partial.
- __Manually-deleted Meetings note:__ next pull recreates it (no match on
  `slack_thread_ts`).
- __Manually-edited Meetings note:__ on next pull, only `## Discussion` is
  appended to and `slack_last_reply_ts` is updated. `## Notes` and any user
  additions elsewhere are preserved.
- __Thread with no replies:__ Meetings note is created with an empty
  `## Discussion` section; `slack_last_reply_ts` equals `slack_thread_ts`.
- __Tombstone (deleted in Slack after ingestion):__ leave the existing Meetings
  note alone. Do not "un-ingest."
```

- [ ] __Step 3: Verify the insertion__

Run: `grep -n "^### \`/worklog" skills/worklog/SKILL.md | head -20`
Expected: `### \`/worklog pull\`` appears between `### Processing raw input` (which is not in backticks) and `### \`/worklog rollover\``.

Also run: `grep -n "^### Processing raw input\|^### \`/worklog pull\`\|^### \`/worklog rollover\`" skills/worklog/SKILL.md`
Expected: those three sections appear in that order with no other content between them except the body of each section.

- [ ] __Step 4: Commit__

```bash
git add skills/worklog/SKILL.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "SKILL.md: add /worklog pull command for Slack channel ingest"
```

---

## Task 6: Add nudge behavior to rollover/tidy/audit and Important Behaviors

__Files:__
- Modify: `skills/worklog/SKILL.md`

- [ ] __Step 1: Add nudge note to /worklog rollover__

Find the `### /worklog rollover` section. It currently begins with:

```markdown
### `/worklog rollover`

Quick rollover without item-by-item review:
```

Replace those three lines with:

```markdown
### `/worklog rollover`

__Nudge check (run first):__ Before doing anything else, glob
`__VAULT_PATH__/Sources/*.md`. For each source whose `last_scan_ts` is `null` or
older than `nudge_threshold_days` (default 5), prepend a one-line FYI:
> FYI - last pulled `#<channel-name>` <N> days ago. Run `/worklog pull` to
> ingest. Continuing with rollover...
Do not block, hijack, or auto-pull. If the user said "skip pull" or "not now"
earlier in the session, suppress the nudge for the rest of the session. Then:

Quick rollover without item-by-item review:
```

- [ ] __Step 2: Add nudge note to /worklog tidy__

Find the `### /worklog tidy` section. It currently begins with:

```markdown
### `/worklog tidy`

Read the current week file and suggest cleanup:
```

Replace those three lines with:

```markdown
### `/worklog tidy`

__Nudge check (run first):__ Same as `/worklog rollover` above - check
`Sources/*.md` and surface a stale-channel FYI before continuing.

Read the current week file and suggest cleanup:
```

- [ ] __Step 3: Add nudge note to /worklog audit__

Find the `### /worklog audit` section. It currently begins with:

```markdown
### `/worklog audit`

Scan the vault for quality issues and present a fix-it checklist. No arguments.
```

Replace those three lines with:

```markdown
### `/worklog audit`

__Nudge check (run first):__ Same as `/worklog rollover` above - check
`Sources/*.md` and surface a stale-channel FYI before continuing.

Scan the vault for quality issues and present a fix-it checklist. No arguments.
```

- [ ] __Step 4: Add a behaviors bullet about the nudge surface area__

Find the `## Important Behaviors` section near the end of the file. Append a new
bullet to the end of the bulleted list (keep the trailing newline at end of file):

```markdown
- __Stale-channel nudge.__ At the top of `/worklog rollover`, `/worklog tidy`,
  and `/worklog audit`, glob `__VAULT_PATH__/Sources/*.md` and check
  `last_scan_ts` against `nudge_threshold_days` on each. Surface a one-line FYI
  for any stale source, then continue with the requested command. Other commands
  (`/worklog add`, `/worklog summary`, `/worklog viz`, `/worklog rollup`,
  `/worklog status`, `/worklog review`, `/worklog search`, `/worklog share`,
  `/worklog sync`) do __not__ nudge. If the user says "skip pull" or "not now"
  earlier in the session, suppress further nudges for that session.
```

- [ ] __Step 5: Verify the changes__

Run: `grep -B1 -A3 "Nudge check" skills/worklog/SKILL.md`
Expected: three matches (rollover, tidy, audit) plus the Important Behaviors mention.

Run: `grep -n "Stale-channel nudge" skills/worklog/SKILL.md`
Expected: one line in the Important Behaviors section.

- [ ] __Step 6: Commit__

```bash
git add skills/worklog/SKILL.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "SKILL.md: add stale-channel nudge to rollover/tidy/audit"
```

---

## Task 7: Update skill description trigger phrases

__Files:__
- Modify: `skills/worklog/SKILL.md` (frontmatter at top)

- [ ] __Step 1: Read the current frontmatter__

Run: `head -15 skills/worklog/SKILL.md`
Expected: shows the YAML frontmatter with `name: worklog` and a multi-line `description:` listing trigger phrases.

- [ ] __Step 2: Add new trigger phrases__

Edit the description block. The current description (paraphrased) ends with `priority drift, trends, or time allocation.`

Append to the end of the existing description (before the closing `---`):

```yaml
  Also trigger when the user asks to "pull from Slack", "ingest the channel",
  "pull meeting notes", "register a channel", or any phrase about reading new
  messages from a registered Slack source into the vault.
```

The full updated frontmatter will read:

```yaml
---
name: worklog
description: >
  Manage __USER_NAME__'s personal worklog stored in Obsidian. Use this skill whenever the user says
  "worklog", "weekly rollover", "what's on my plate", "my priorities", "add to my worklog",
  "tidy my worklog", "what am I working on", "summarize my week", "monthly summary",
  "quarterly summary", "what did I accomplish", "audit my vault", "vault health check",
  "visualize my work", "worklog charts", or anything about managing weekly work priorities.
  Also trigger when the user asks about P0/P1/P2 items, wants a status update for Slack,
  or asks about priority drift, trends, or time allocation.
  Also trigger when the user asks to "pull from Slack", "ingest the channel",
  "pull meeting notes", "register a channel", or any phrase about reading new
  messages from a registered Slack source into the vault.
---
```

- [ ] __Step 3: Verify__

Run: `grep -A1 "pull from Slack" skills/worklog/SKILL.md | head -3`
Expected: matches in the frontmatter.

- [ ] __Step 4: Commit__

```bash
git add skills/worklog/SKILL.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "SKILL.md: add trigger phrases for /worklog pull"
```

---

## Task 8: Create examples/source-note.md

__Files:__
- Create: `examples/source-note.md`

- [ ] __Step 1: Create the file__

Write the following to `examples/source-note.md`:

```markdown
---
type: meeting-notes-via-email
channel_name: "#example-meeting-notes"
channel_id: C0EXAMPLE0
nudge_threshold_days: 5
last_scan_ts: "2026-05-04T09:14:32Z"
first_scan_lookback_days: 14
---

# #example-meeting-notes

Channel where weekly leadership-team meeting notes are forwarded from a Google
Group as email attachments. Each new meeting becomes a top-of-thread post; the
team responds in-thread with follow-ups, decisions, and action items.

This source is ingested via `/worklog pull` into `Meetings/YYYY-MM-DD-<slug>.md`.
Stale-channel nudge fires on `/worklog rollover` / `tidy` / `audit` if
`last_scan_ts` is older than 5 days.
```

- [ ] __Step 2: Verify__

Run: `cat examples/source-note.md`
Expected: the file content matches what was written.

- [ ] __Step 3: Commit__

```bash
git add examples/source-note.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "examples: add source-note.md template"
```

---

## Task 9: Create examples/meeting-note.md

__Files:__
- Create: `examples/meeting-note.md`

- [ ] __Step 1: Create the file__

Write the following to `examples/meeting-note.md`:

```markdown
---
type: meeting
date: 2026-05-04
source_channel: "#example-meeting-notes"
source_channel_id: C0EXAMPLE0
slack_thread_ts: "1714813200.123456"
slack_last_reply_ts: "1714824120.654321"
slack_thread_url: https://example.slack.com/archives/C0EXAMPLE0/p1714813200123456
participants:
  - "[[Sarah Chen]]"
  - "[[Marcus Williams]]"
  - "[[Priya Patel]]"
programs:
  - "[[Platform Migration]]"
  - "[[Cloud Security]]"
status: ingested
---

# Weekly Platform Sync — May 4

> [!info] Slack thread in [[Sources/example-meeting-notes|#example-meeting-notes]] · [open in Slack](https://example.slack.com/archives/C0EXAMPLE0/p1714813200123456)
> Original sender: Jordan · Posted 2026-05-04 09:00 PT

## Notes

Agenda:
- [[Platform Migration]] status: stage promotion blocked on BGP regression
- [[Cloud Security]] review checkpoint scheduled for May 14
- Q2 hiring update: 2 offers out, both pending response

Discussion summary: [[Marcus Williams]] confirmed the BGP config drift fix is up
for review (PR #2147), expecting merge by Tuesday May 12. If merged on time,
stage promotion stays on schedule for May 15. [[Priya Patel]] flagged that the
[[Cloud Security]] review needs the traffic-shaping RFC delivered by May 11 to
keep the May 14 checkpoint on track. [[Sarah Chen]] raised observability gap on
the developer portal rollout and will follow up offline with SRE.

Action items:
- [[Marcus Williams]]: drive BGP fix to merge by May 12
- [[Priya Patel]]: deliver traffic-shaping RFC by May 11
- [[Sarah Chen]]: sync with SRE on observability hooks (offline)

## Discussion

### 2026-05-04 09:15 — [[Sarah Chen]]
Quick clarification on the observability gap - the missing hooks are on the new
metrics pipeline only, the legacy path is fine. Does that change urgency?

### 2026-05-04 09:42 — [[Marcus Williams]]
For BGP - PR is #2147. SRE review queued. If anyone has cycles to look it's
appreciated, otherwise normal turnaround is fine.

### 2026-05-04 11:42 — [[Priya Patel]]
RFC draft is in the doc, should have it ready for review by EOD May 10. Will
ping in this thread when it's up.

## Extracted Items

- See [[2026-W19]] for items added to this week's worklog
```

- [ ] __Step 2: Verify__

Run: `cat examples/meeting-note.md`
Expected: the file content matches what was written.

- [ ] __Step 3: Commit__

```bash
git add examples/meeting-note.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "examples: add meeting-note.md template"
```

---

## Task 10: Update README.md

__Files:__
- Modify: `README.md`

- [ ] __Step 1: Add to "What You Get"__

Find the bulleted list under `## What You Get`. Append after the existing
"Preferences as first-class citizens" bullet:

```markdown
- __Slack channel inbox__ -- register a Slack channel where meeting notes get
  forwarded (e.g., from a Google Group), and `/worklog pull` ingests
  unprocessed threads into `Meetings/` notes plus extracts action items into the
  current week. The skill nudges you on `/worklog rollover` / `tidy` / `audit`
  if a registered channel hasn't been pulled in over 5 days
```

- [ ] __Step 2: Add to Vault Structure__

Find the section that documents the directory structure (likely under
`## Vault Structure`). It currently lists `Worklogs/`, `People/`, `Programs/`,
`Teams/`, `Preferences/`, etc. Add entries for `Sources/` and `Meetings/`
following the same format used for the existing dirs. Match the surrounding
style; if entries are formatted as `__Worklogs/__ -- <description>`, use the
same format. The two new entries (descriptions):

- `__Sources/__ -- registered Slack channels for `/worklog pull`. One file per
  channel; frontmatter holds `channel_id`, `last_scan_ts`, and nudge threshold.
- `__Meetings/__ -- one file per ingested Slack thread (top-of-thread email +
  in-thread discussion). Linked into the knowledge graph via wiki-linked
  participants and programs.

- [ ] __Step 3: Add to Commands list__

Find the `## Commands` section. Add a new entry for `/worklog pull` near the
related commands (e.g., between `/worklog add` and `/worklog rollover`, or
wherever the README places ingestion-related commands). Match the existing
command-list format. Description:

`/worklog pull` -- ingest unprocessed threads from registered Slack channels into
`Meetings/` notes plus extract action items into the current week file. On first
run with no `Sources/`, walks you through registering a channel.

- [ ] __Step 4: Update FAQ if applicable__

If a FAQ section exists, add an entry. Skip this step if no FAQ section is
present:

> __Q: How do I add a new Slack channel to monitor?__
> Run `/worklog pull`. If `Sources/` is empty, the skill walks you through
> registering the channel: it asks for the channel name, resolves the channel
> ID via Slack search, writes a `Sources/<channel>.md` config file, and runs
> the first pull. To add another channel later, just say "register
> `#another-channel` as a source."

> __Q: What if I delete a meeting note by accident?__
> The next `/worklog pull` will recreate it from the Slack thread, since the
> vault is the source of truth for what's been ingested and a missing file
> means "not yet processed."

> __Q: What if I edit a meeting note?__
> Your edits are preserved. Subsequent pulls only append new replies under
> `## Discussion` and update `slack_last_reply_ts` in the frontmatter. The
> `## Notes` section and anything else you add is never overwritten.

- [ ] __Step 5: Verify__

Run: `grep -n "Slack channel inbox\|Sources/\|Meetings/\|/worklog pull" README.md | head -20`
Expected: multiple matches across What You Get, Vault Structure, Commands, and FAQ (if added).

- [ ] __Step 6: Commit__

```bash
git add README.md
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "README: document Slack channel inbox feature"
```

---

## Task 11: Bump plugin.json version and update description

__Files:__
- Modify: `.claude-plugin/plugin.json`

- [ ] __Step 1: Read current plugin.json__

Run: `cat .claude-plugin/plugin.json`
Expected: shows current version `5.2.1` and the description string.

- [ ] __Step 2: Edit plugin.json__

Replace the entire file content with:

```json
{
  "name": "obsidian-worklog",
  "version": "5.3.0",
  "description": "Obsidian worklog manager - weekly planning, knowledge graph (people, programs, teams), priority tracking, D3 visualizations, AI summaries, IC-facing weekly rollups, durable preferences (voice, style, workflow, tooling, decision rules), and Slack channel inbox (ingest meeting-notes-via-email threads into Meetings/ artifacts plus current-week action items)",
  "author": {
    "name": "Menotti Minutillo",
    "email": "menottim@users.noreply.github.com"
  },
  "keywords": [
    "worklog",
    "obsidian",
    "tasks",
    "priorities",
    "weekly-planning",
    "knowledge-graph",
    "visualization",
    "preferences",
    "slack-ingest"
  ]
}
```

Changes:
- `version`: `5.2.1` -> `5.3.0` (minor bump for new feature, matches the v5.2.0
  precedent of bumping minor for the Teams/Preferences feature add).
- `description`: appended Slack channel inbox phrase.
- `keywords`: appended `slack-ingest`.

- [ ] __Step 3: Verify the JSON is valid__

Run: `python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('valid')"`
Expected: `valid`.

Run: `grep '"version"' .claude-plugin/plugin.json`
Expected: `"version": "5.3.0",`

- [ ] __Step 4: Commit__

```bash
git add .claude-plugin/plugin.json
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "v5.3.0: bump version and update description for Slack channel inbox"
```

---

## Task 12: Manual end-to-end smoke test

__Files:__
- None (this is a verification task, not a code change).

This task cannot be automated since the skill is markdown documentation that an
LLM session reads and acts on. Manual verification is the substitute for an
integration test. The user runs the skill against a real registered channel and
confirms each step produces the expected output.

- [ ] __Step 1: Reload the skill in Claude Code__

If running in an active session, the version bump in plugin.json invalidates
the cache. Either restart the session or use whatever reload mechanism the
host environment provides. The skill's frontmatter trigger phrases will pick up
"pull from Slack" / "ingest the channel" / `/worklog pull`.

- [ ] __Step 2: Run /worklog pull on an empty Sources/__

Open a fresh Claude Code session in the vault. Run:

```
/worklog pull
```

Expected: the skill notices `Sources/` is empty (or doesn't exist) and prompts:
"Which channel should I monitor?" Provide the real channel name. The skill
should resolve via `slack_search_channels`, ask for confirmation, then write
`__VAULT_PATH__/Sources/<channel-name>.md` and proceed with the first pull.

Verify after registration:
- File exists at `__VAULT_PATH__/Sources/<channel-name>.md`.
- Frontmatter has correct `channel_id`, `type: meeting-notes-via-email`,
  `nudge_threshold_days: 5`, `first_scan_lookback_days: 14`,
  `last_scan_ts: null` (will advance to current time after first pull
  completes).

- [ ] __Step 3: Verify first-pull artifacts__

After the first pull completes:
- Glob `Meetings/*.md` - should have one file per ingested thread from the
  past `first_scan_lookback_days` (default 14).
- Pick one Meetings note and verify:
  - Filename matches `YYYY-MM-DD-<topic-slug>.md`.
  - Frontmatter is complete: `slack_thread_ts`, `slack_last_reply_ts`,
    `slack_thread_url`, `participants`, `programs`, `status: ingested`.
  - Body has `## Notes`, `## Discussion`, `## Extracted Items` sections.
  - All people and programs are wiki-linked (no bare names that match known
    People/Programs notes).
- Check the current week file (`Worklogs/YYYY-WNN.md`):
  - New action items appear with appropriate priorities.
  - Sub-item dated annotations use the actual Slack timestamps from the
    thread, not today's date (look for `(Mon D)` markers matching the meeting
    date, not today).
  - People/Programs mentioned in the meetings have new dated context entries
    in their notes.
- Check `Sources/<channel>.md` - `last_scan_ts` should be a recent ISO 8601
  timestamp.

- [ ] __Step 4: Verify idempotency__

Run `/worklog pull` again immediately. Expected: summary reports 0 new threads,
0 updated, 0 items extracted. No file changes (verify via `git status` in the
vault if it's a git repo, or `find Meetings/ -newer Sources/<channel>.md`).
`Sources/<channel>.md` `last_scan_ts` advances to the new "now."

- [ ] __Step 5: Verify thread evolution__

Have someone (or yourself) post a new reply to a thread in the Slack channel.
Wait a minute, then run `/worklog pull`. Expected:
- Summary reports 0 new threads, 1 updated, K items extracted (K could be 0
  if the reply has no actionable content).
- The matched `Meetings/*.md` has a new `### YYYY-MM-DD HH:MM — [[Author]]`
  subheading at the end of `## Discussion`, with the reply text.
- Frontmatter `slack_last_reply_ts` advances. Other frontmatter fields
  (especially `## Notes`) are unchanged.

- [ ] __Step 6: Verify the nudge surfaces on rollover (if you can simulate)__

Manually edit `Sources/<channel>.md` to set `last_scan_ts` to a value 7+ days
in the past. Run `/worklog rollover`. Expected: a one-line FYI prepended to
the response, then normal rollover behavior. Restore `last_scan_ts` after the
test (or just run `/worklog pull` again to advance it).

- [ ] __Step 7: Verify the nudge does NOT surface on /worklog add__

With the same stale `last_scan_ts`, run `/worklog add P1 test item`. Expected:
no FYI prefix; the item is added normally.

- [ ] __Step 8: Mark eval results in evals/evals.json__

This step is informational - the file isn't changed in code. After this
manual smoke test, the eval scenarios in evals/evals.json (ids 8-12) have
been validated against a real channel.

- [ ] __Step 9: Commit (if any cleanup files were touched)__

If the smoke test surfaced any documentation gaps and you patched them, commit
those fixes:

```bash
git status
# If changes:
git add -p   # review and stage
git -c user.name="menottim" -c user.email="menottim@users.noreply.github.com" commit -m "<describe the fix>"
```

If the smoke test passed cleanly with no fixes needed, no commit is required.

---

## Task 13: Final review and push decision

__Files:__
- None (this is a coordination task).

- [ ] __Step 1: Review the commit log for the feature__

Run: `git log --oneline 0a2d9ad^..HEAD`
Expected: shows the design spec commit (0a2d9ad) plus all the implementation
commits added by Tasks 1-11 (and optionally Task 12). Each commit message
should be specific and self-contained.

- [ ] __Step 2: Confirm the working tree is clean__

Run: `git status`
Expected: `nothing to commit, working tree clean` (modulo any pre-existing
untracked files like `.superpowers/`, `presentation/`, the older
`docs/superpowers/specs/2026-04-14-presentation-design.md` - those are
intentionally left alone).

- [ ] __Step 3: Decide whether to push__

Ask the user: "All tasks complete. Push to `origin/main`?"

If yes:
```bash
git push origin main
```

If the user wants to tag the release:
```bash
git tag -a v5.3.0 -m "v5.3.0: Slack channel inbox"
git push origin v5.3.0
```

If no, leave the commits local and tell the user the implementation is ready
on local `main`, ahead of `origin/main` by N commits.

---

## Self-Review checklist (run after writing this plan, fix inline)

This list documents the self-review pass. The plan author runs this against
the spec, fixes anything inline, then signals ready for execution.

- __Spec coverage:__ Walk each section of `2026-05-04-slack-channel-monitoring-design.md`
  and confirm a task implements it.
  - Architecture (Sources/, Meetings/, /worklog pull): Tasks 2, 3, 4, 5.
  - Pull flow (6 steps): Task 5.
  - Source registration (5 steps): Task 5 (First-run registration sub-section).
  - Meeting note schema (filename, frontmatter, body): Task 4 + Task 9 (example).
  - Item extraction (re-uses existing): Task 5 references the existing
    Processing raw input section; no new pipeline added (correct per spec).
  - Nudge behavior (rollover/tidy/audit, 5-day default): Task 6.
  - Error handling (7 cases): Task 5 (Errors and edge cases sub-section).
  - Testing (eval scenarios + manual smoke): Task 1 (evals) + Task 12 (smoke).
  - Out of scope: not implemented (correct).
  - Open questions: addressed in Task 12 manual smoke (validates email body
    extraction in real environment, bot ID handling, participant extraction).

- __Placeholder scan:__ No "TBD", "TODO", "implement later", "fill in details",
  or "similar to Task N" patterns. Every code/text block is the actual content.
  Verified.

- __Type / naming consistency:__
  - `slack_thread_ts` (string) used consistently across spec and plan.
  - `slack_last_reply_ts` (string) used consistently.
  - `last_scan_ts` (ISO 8601 timestamp) used consistently in Sources frontmatter.
  - `nudge_threshold_days: 5` is the documented default everywhere.
  - `first_scan_lookback_days: 14` is the documented default everywhere.
  - `meeting-notes-via-email` is the source-type identifier everywhere.
  - Filename patterns: `Sources/<channel-name>.md` (no `#` prefix);
    `Meetings/YYYY-MM-DD-<topic-slug>.md`.
  - Section headings inside Meetings: `## Notes`, `## Discussion`,
    `## Extracted Items` - identical across Tasks 4, 5, and 9.

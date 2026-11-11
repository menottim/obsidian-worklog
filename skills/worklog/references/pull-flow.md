# /worklog pull — full flow

(Loaded on demand by SKILL.md.)

__Phases:__ in Claude Code this flow runs in three phases per `references/model-routing.md`:
Fetch (Haiku) does steps that read Slack and saves raw material to the run directory without
touching the vault; Analyze (Sonnet) does the classification, folding, Meetings-note and DM
judgment below and writes a plan with exact text; Write (Haiku) applies that plan, including
`last_scan_ts` updates and log entries. The steps below describe what happens, whichever
phase does it. With no `Agent` tool, run them inline in order.

__Codex capability preflight:__ Before reading or writing pull state, confirm that the
current Codex host exposes tools that can perform all four Slack operations used below:
list channel messages over a time window, read a complete thread, resolve a channel by
name, and resolve a user by ID or handle. Tool names may be namespaced by the installed
Slack connector. If any operation is unavailable, stop without advancing `last_scan_ts`
and name the missing capability. Offer `$worklog ingest <slack-permalink>` for one-off
thread ingestion. Do not substitute semantic/RAG Slack search for incremental channel
enumeration: it is not exhaustive and would make the cursor state unsafe. Claude Code
keeps its existing Slack tool flow unchanged.

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
   3. __New thread__ (no match): get the email body, then ingest.
      - __ALWAYS try auto-fetch first__ by running this exact command:
        ```bash
        ~/.config/obsidian-worklog/bin/slack-fetch-file <file_id>
        ```
        where `<file_id>` is the ID of the top-of-thread file attachment from
        `slack_read_thread`. Do __NOT__ skip this step. Do __NOT__ check
        whether the helper is "configured" or "set up" first - just run it.
        The helper handles all configuration checks internally (token file
        readable, network reachable, file visible) and reports failure via
        non-zero exit codes with a clear stderr message. The helper prints
        the body (HTML for `text/html` files, raw bytes for others) to
        stdout on success.
      - __On exit code 0__ (helper succeeded, body on stdout): use that
        output as the source body. __Skip the prompt step below entirely__
        and proceed straight to "With the body" below.
      - __On any non-zero exit__ (helper missing, token missing/expired,
        `not_visible`, `access_denied`, network error, no file attachment
        on the top-of-thread post, etc.): only __then__ fall back to
        prompting:
        - Show the user a one-block summary of this thread:
          - Date: top-of-thread ts in user's local timezone (e.g., `2026-05-01`).
          - Subject: from the file attachment name (or the message text if any).
          - Posted by: bot/integration name (typically `Slackbot`).
          - Slack permalink (constructed from `channel_id` + `slack_thread_ts`).
          - Attached file: `<filename>` (`<MIME type>`, `<size>`).
          - Auto-fetch error if any (one line, e.g., `auto-fetch failed: not_visible`).
        - Ask: _"Paste the email body to ingest, or say 'skip' (advances
          `last_scan_ts` past this thread; won't be prompted again). For
          multiple new threads, you can also say 'skip all remaining' to bail
          out of the pull and resume later."_
      - __With the body (from auto-fetch OR user paste)__:
        - Compute the meeting note filename: `YYYY-MM-DD-<topic-slug>.md` per
          the rules in `references/meetings.md`. Date is the top-of-thread ts in
          user's local timezone; slug is kebab-case from the email subject.
        - On filename collision, append `-2`, `-3`, etc. until unique.
        - Build the Meetings note body per the schema in `references/meetings.md`:
          - `## Notes`: the body, lightly cleaned. If HTML, convert to plain
            markdown (strip tags, preserve paragraph breaks, headings, lists,
            and links). Strip email-client chrome (signatures, "On <date> X
            wrote:" quote blocks, unsubscribe footers, tracking pixels,
            `Forwarded message` headers). Preserve substantive content.
          - `## Discussion`: each reply from `slack_read_thread` becomes a
            `### YYYY-MM-DD HH:MM — [[Author]]` subheading (user's local TZ,
            chronological), followed by the reply text. Resolve author names
            via `slack_search_users` if only a handle/ID is available. If the
            thread has no replies, leave `## Discussion` empty.
          - `## Extracted Items`: a single line linking to the current week
            file: `- See [[YYYY-WNN]] for items added to this week's worklog`.
        - Build frontmatter per the schema in `references/meetings.md`. Set
          `slack_last_reply_ts` equal to `slack_thread_ts` if the thread has
          no replies; otherwise to the timestamp of the latest reply.
        - Resolve participants: union of (thread repliers from
          `slack_read_thread`, names @-mentioned in the body, names in the
          body's "Attendees:" / "Participants:" section if present).
          Wiki-link all; create stub People notes for unknown names per the
          existing Cross-Linking rules.
        - Resolve programs and people from the digest, not from a glob. Run it once
          per pull and reuse the result across every thread and unit; re-run only
          after creating a new People or Programs stub, since that is the one thing
          that changes the entity set:
          `__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries`.
          Use `entities[].canonical` as link targets, `entities[].aliases` for
          partial and case forms, and `entities[].summary` when you need to judge
          whether the body is really about that entity. Treat `summary_source:
          "derived"` as provisional (it is just the note's first bullet); read the
          note body instead when a derived summary is what the decision rests on.
          Treat anything in `ambiguous` as resolve-from-context. Scan the body for
          matches; wiki-link. Do not glob `Programs/*.md` and do not read note bodies.
        - Write the new `Meetings/YYYY-MM-DD-<slug>.md`.
        - Run the __Processing raw input__ pipeline (above) against the body
          + replies, treating the meeting date as the source date for action
          items. Items go into the __current__ week file (the user's actual
          current week, not the meeting's week, since the meeting's week may
          be in the archive). Sub-item dated annotations use the actual
          Slack timestamps from the thread, not today's date.
      - __On 'skip'__ (manual-paste fallback only):
        - Do __not__ create a Meetings note (skeletons rot).
        - Advance `last_scan_ts` on the source file past this thread's ts so
          the next pull won't re-prompt.
        - Note in session output: `Skipped: <date> <subject>`.
      - __On 'skip all remaining'__ (manual-paste fallback only):
        - Do not advance `last_scan_ts` for the threads that haven't been
          shown yet; leave them for the next pull.
        - Stop the pull and print whatever summary is available so far.
   4. __Existing thread, new replies__ (match found, replies after
      `slack_last_reply_ts`):
      - Open the matched `Meetings/*.md` with the host's available file-editing tool.
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

For `context-channel` sources, the summary additionally reports, per channel:
`N scanned · M auto-folded · J surfaced for approval · K dropped`, then itemizes each
auto-fold (one line: summary → target item, with permalink) so any mis-classification
is visible and can be undone, followed by the approval-batch outcomes.

For the DM sweep, the summary reports `N results · M surfaced for approval · K dropped`
(DMs never report auto-folds, since none are auto-folded), followed by the approval-batch
outcomes. If the helper was unavailable, report `DM sweep skipped: <reason>` and nothing
else for DMs.

__Context-channel sweep flow:__

For each source with `type: context-channel`:

1. Compute the window: messages with `ts > last_scan_ts`. On first run
   (`last_scan_ts` is null), look back `first_scan_lookback_days` (default 7).
   Incremental only — never re-read messages already past `last_scan_ts`.
2. `slack_read_channel` to list top-level messages in the window. Exclude bots
   (`include_bots=false`); include the user's own messages. For each top-level
   message with replies, `slack_read_thread` to fetch the full thread.
3. Build the working set of __conversation units__: a unit is a thread (parent +
   its replies) or a standalone message. The thread is the unit of analysis.
4. __Volume guardrail:__ if a channel yields more than ~100 units, STOP and tell the
   user the count and the window, and ask whether to proceed, narrow the window, or
   skip this channel. Never silently truncate.
5. Classify each unit three ways (see __Three-way classification__).
6. Apply high-confidence matches immediately (see __What auto-fold writes__). Stage
   uncertain + new units for the approval batch.
7. Advance `last_scan_ts` per processed unit (resumable across a crash), then to the
   current time at the end of the channel.

__Three-way classification__ - judge each unit against the vault. Read the current
week, Backlog, and `Archive/` directly. For person and program identity, use the digest:
`__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries`,
which gives every person and program with its aliases and a one-line summary. Run it
once per pull and reuse the result across every unit; re-run only after creating a new
People or Programs stub, since that is the one thing that changes the entity set. Do not
glob `People/` or `Programs/`, and open one of those note bodies only when a unit
plausibly concerns that entity and its summary is not enough to decide; treat
`summary_source: "derived"` as provisional (it is just the note's first bullet) and read
the note body instead when that is what the decision rests on. The digest does NOT cover
teams: read `Teams/` directly for team identity, which is small enough to read directly:

- __High-confidence match → auto-fold.__ The unit clearly concerns one specific
  existing worklog item, person, program, or team: it names the program/initiative,
  continues a thread already tracked as an item, or is the same people advancing the
  same topic.
- __Weak/uncertain match, OR genuinely new-but-worth-tracking → approval batch.__
  Weak = topically adjacent but not clearly the same item, could attach to more than
  one item, or concerns a tracked person/program without obviously-actionable
  context. New-worthy = matches nothing but is a decision, ownership change, risk,
  ask, commitment, or status change worth tracking. __Never force-fit a weak match —
  always ask.__ When torn between auto-fold and ask, choose ask.
- __Noise → drop silently.__ Banter, logistics, unrelated chatter, FYIs with no
  bearing on tracked work.

__What auto-fold writes__ — same shape as the __Processing raw input__ pipeline:

- A dated sub-item under the matched worklog item:
  `  - <concise summary> ([#channel-name](<slack-permalink>), <Mon D>)` — date from
  the Slack message timestamp (user's local TZ), wiki-linking known
  people/programs/teams and creating stubs per the Cross-Linking rules.
- Substantive context appended to a matched Person/Program/Team note when the unit is
  about that entity.
- Summarize, do not transcribe; the genericize-at-the-public-boundary rule applies
  later, at publish time. The Slack permalink is the provenance (no `Meetings/` note).
- Regenerate enriched frontmatter only if a top-level item was added/changed; pure
  sub-item adds skip regeneration.

__Approval batch (human-in-the-loop)__ — after every source is swept (email +
context), collect all uncertain/new candidates and present them __one at a time, each
with its own explicit options__. This is the user's default for any multi-item input
request: do NOT dump a single consolidated free-text checklist and ask for a bulk
reply. Use the host's available structured-choice interaction when one exists. In
Claude Code this may be `AskUserQuestion`; in Codex, use a concise plain-text question
and wait when no structured-choice tool is available. Never depend on one host's tool
name. Iterate until every candidate has its own decision.

Each item shows its source channel, date, a one-line summary, and the Slack permalink,
with a small set of routing options — for example:
- Attach as a sub-item under `[[matched item]]` (for an uncertain match)
- New `P?` item under `<subgroup>`
- Add to the Backlog
- Drop

__Check `Backlog.md` and `Threads/` before you offer or create any new top-level item.__ A
parked item is absent from the week file but not absent from the vault. A new item beside its
own parked copy is a duplicate that splits one history across two Threads. This applies to every
path that can create an item: this batch, an approved DM, and a context-channel unit that
matches nothing in the week file. For each candidate that would become a new item, do two
searches:

- Search `Worklogs/Backlog.md` for a parked entry on the same program, person and topic.
- Search `Threads/` titles for the same program, person and topic.

On a match, offer __Wake `[[parked item]]`__ as the recommended option in place of "New `P?`
item". To wake the item:

- Move the title back into the week file.
- Set its Thread to `status: live`.
- Keep the newest `WORKLOG_WEEK_KEEP_SUBS` entries plus the new fact as sub-items. If the warm
  Thread has fewer entries, read the newest from the Thread's cold files per
  `references/cold.md`.
- Remove the Backlog entry.

This follows `references/threads.md`. If the candidate is related but not the same item, say so
in the option text and let the user choose. Never write a new Thread whose title names the same
item as an existing one. Append to the existing Thread.

Lead with the most likely option and mark it recommended; the user picks per item and
can override the priority, subgroup, or target. After the responses, apply the
approved additions (dated with the Slack timestamp, wiki-linked, permalink provenance)
and regenerate frontmatter only if any top-level items were added.

__DM sweep flow:__

If `Sources/_dms.md` exists and is `enabled: true`, run this after all channel sources
(its candidates join the same end-of-pull approval batch):

1. Compute the `after` timestamp: `last_scan_ts` if set, else `now − first_scan_lookback_days`
   (default 3 days), as a UNIX timestamp.
2. Enumerate new DMs chronologically. Do __not__ rely on topic queries: relevance-ranked search
   returns a small capped set and silently misses group DMs (a same-day group DM was missed
   this way: 1 in-window result against 28 for the same window with fan-out).

   __Primary: the Slack search tool with no keywords.__ Call the host's Slack search tool
   (Claude Code: `slack_search_public_and_private`) with `filters: "is:dm"`,
   `channel_types: "im,mpim"` (narrow to one type when `include_1on1`/`include_groups` is
   false; if both are false, skip the DM sweep and log `DM sweep skipped: no channel types
   selected`), `after: <last_scan_ts unix>`, `sort: "timestamp"`, `sort_dir: "asc"`,
   `include_context: false`, `response_format: "concise"`. Follow `cursor` until it comes back
   empty. This is a complete chronological listing, not a ranked sample. Each result gives
   the conversation, author, text and time; fetch surrounding thread context with
   `slack_read_channel` / `slack_read_thread` only for units that look relevant.
   Advance `last_scan_ts` to the newest message seen __only if paging reached an empty
   cursor__. If a page errors, report the sweep as partial and do not advance it.

   __Fallback: the `slack-search-dms` helper.__ If the Slack search tool is not in your tool list,
   run the helper. Run it unconditionally; do not pre-check whether it is configured. Run it
   and branch on the exit code, the same pattern as `slack-fetch-file`. Never skip the DM
   sweep because the search tool is missing. The helper is relevance-ranked,
   so never run it as a single query. Pass many narrow queries on stdin, one per line: the
   `_dms.md` `query` if non-empty, names of people in the current week file's `people:`
   frontmatter, and names of active Programs. With no stdin it uses a built-in topic list,
   which is a floor, not the goal. Set `SLACK_DM_CHANNEL_TYPES` from `include_1on1` /
   `include_groups`. It prints one JSON object per in-window result, then a summary line
   `{"queries":N,"failed_queries":N,"candidates":N,"in_window":N,"newest_seen":"ts"}`. On any
   non-zero exit, print a one-line skip note with stderr and skip the DM sweep. There is no
   cursor. If `failed_queries > 0`, report the sweep as partial and do not advance
   `last_scan_ts`. A fan-out sweep can still miss messages, so say "fan-out" in the log.
3. __Volume guardrail:__ if `in_window` exceeds `max_results` (default 100), ask (proceed / narrow
   the window / skip) before classifying. Never silently truncate.
4. Filter results: drop any whose `channel_id` is in `exclude_conversations`; drop any whose
   `author_user_id` is in `exclude_users`. (Bots are already excluded by the search; treat any
   result with `is_author_bot: true` as a second-guard drop.)
5. Each remaining result is a unit. Its `content` is the matched message; `context_messages`
   (before/after, thread-limited) supplies surrounding thread context for classification and
   for writing a genericized summary. `permalink` is the provenance; `message_ts` is the date;
   `author_user_id` / `author_name` identify the person to wiki-link.
6. Classify each unit against the __entire vault__ using the three-way rubric above, with the
   DM privacy override below.
7. Advance `last_scan_ts` to the current time after the sweep completes. On a partial failure
   (a failed query or network error), do __not__ advance `last_scan_ts`; report the partial sweep
   so the next pull re-covers the window (re-surfaced units are harmless since nothing folds
   without approval).

__DM privacy override (differs from channels):__
- __DM content is never auto-folded.__ Every relevant DM unit — high-confidence match
  included — goes into the approval batch. High-confidence ones lead with the recommended
  "attach as a sub-item under `[[matched item]]`" option; weak/new ones offer attach / new
  `P?` item / Backlog / drop (new standalone items are allowed). Noise is dropped silently.
- On approval, fold a __genericized, workstream-level summary__ — no verbatim 1:1 quotes,
  no personal detail beyond what the item needs (honors the user's "no DM quotes in public
  artifacts" rule even though the vault is private). Provenance: the `permalink` to the DM
  message. Dated with `message_ts`; wiki-linked; frontmatter regenerated only if a top-level
  item is added.

__First-run registration:__

When `Sources/` is empty (or the user explicitly asks to register a new channel):

1. Ask: "Which channel should I monitor? (give the channel name, with or without
   the leading #)"
2. Use `slack_search_channels` to resolve the name to a channel ID. If multiple
   matches, present the top results and let the user pick.
3. Confirm with the user: "Register `#<channel>` (id `C0XXXXXXX`) as a
   `meeting-notes-via-email` source?"
4. On confirmation, write `__VAULT_PATH__/Sources/<channel-name>.md` (channel name
   without the `#`, kebab-case), populated from the template in
   `references/sources.md`: `type: meeting-notes-via-email`, `channel_name`, `channel_id`,
   `nudge_threshold_days: 5`, `last_scan_ts: null`, `first_scan_lookback_days: 14`,
   plus a brief body line about what the channel is.
5. Proceed with the first pull (lookback = `first_scan_lookback_days` days).

__Body extraction:__

For larger HTML emails (generally >5-10KB or with rich formatting), Slack's
email-to-channel integration posts forwarded emails as `.html` (or `.eml`)
file attachments on bot messages. The email body lives __inside__ the file,
not in the message text. Most Slack MCP tools return file metadata only (ID,
name, MIME type, size) and don't expose file body content directly.

__Default behavior: auto-fetch via the helper script.__ The skill's pull flow
(step 4.3 above) __always__ shells out to:

```bash
~/.config/obsidian-worklog/bin/slack-fetch-file <file_id>
```

This calls Slack's `files.info` API to get `url_private_download`, fetches
the body with `Authorization: Bearer <token>`, and prints it to stdout on
exit code 0. The helper handles all configuration checks internally and
returns non-zero on any failure (token missing/expired, file not visible,
network error). The skill checks the exit code and proceeds:

- __Exit 0__: use the body, run the existing __Processing raw input__
  pipeline against it. No user prompt.
- __Non-zero exit__: fall back to prompting the user to paste the body
  inline. Surface the helper's stderr message (one line) so the user knows
  what went wrong.

This is unconditional. The skill does __not__ check "is the helper
configured" or "does the token exist" before trying — it just runs the
command and branches on the result. If the helper isn't installed at all,
the run will exit non-zero with "command not found" and the manual-paste
fallback engages.

__Setup for new users:__ see `docs/SETUP-SLACK.md` in the repo for the
~5-minute walkthrough — register a Slack app at `api.slack.com/apps` with
`files:read` scope, store the resulting `xoxp-` user token at
`~/.config/obsidian-worklog/slack-token` (chmod 600), and drop in the
~30-line helper script. After that, every `/worklog pull` ingests bodies
automatically.

__Thread replies__ are never affected by this — replies are normal Slack
messages and `slack_read_thread` returns their full text. Body extraction
only applies to the top-of-thread email content.

__Errors and edge cases:__

- __Slack MCP not available:__ fail with: "This needs a Slack MCP plugin. Install
  one and re-run." Do not silently skip.
- __Channel not found / ambiguous__ during registration: show the top matches
  from `slack_search_channels` and let the user pick.
- __User pastes empty / clearly-non-meeting content:__ ask once for confirmation
  (e.g., "That looks short - are you sure that's the full body?"). On second
  confirm, proceed; the resulting Meetings note may be sparse but that's the
  user's call.
- __Rate limit hit mid-pull (Slack API):__ `last_scan_ts` advances per thread,
  so the next pull resumes from where we left off. Tell the user it was partial.
- __Manually-deleted Meetings note:__ next pull will re-prompt the user to
  paste the body again (the `slack_thread_ts` no longer matches anything in
  `Meetings/*.md`, so the thread is treated as new). If the user wants to
  permanently skip a thread without ingesting, use 'skip' in step 4.3 - that
  advances `last_scan_ts` past the thread's ts so it's never re-prompted.
- __Manually-edited Meetings note:__ on next pull, only `## Discussion` is
  appended to and `slack_last_reply_ts` is updated. `## Notes` and any user
  additions elsewhere are preserved.
- __Thread with no replies:__ Meetings note is created with an empty
  `## Discussion` section; `slack_last_reply_ts` equals `slack_thread_ts`.
- __Tombstone (deleted in Slack after ingestion):__ leave the existing Meetings
  note alone. Do not "un-ingest."

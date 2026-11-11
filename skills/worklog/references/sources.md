# Sources

Loaded on demand from `SKILL.md`. Everything the command needs is here.


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
channel_name: "#platform-leads"
channel_id: C0XXXXXXX
nudge_threshold_days: 5
last_scan_ts: null              # null on first run; advances per processed message
first_scan_lookback_days: 7     # smaller default than email sources (high-traffic)
---

# #platform-leads

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

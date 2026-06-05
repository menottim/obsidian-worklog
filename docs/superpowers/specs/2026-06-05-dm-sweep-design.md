---
title: DM Sweep for /worklog pull — Design
date: 2026-06-05
status: draft
feature: dm-sweep
extends: 2026-06-04-context-channel-pull-design.md
---

# DM Sweep for `/worklog pull` — Design

Extend `/worklog pull` to also sweep the user's Slack __direct messages and group DMs__
(MPIMs) since the last sweep, classify them against the worklog, and surface anything
relevant. DMs are the user's most sensitive surface, so this mode is deliberately more
conservative than the context-channel sweep: __nothing from a DM is ever auto-folded__ —
every DM-derived item goes through the one-by-one approval batch, and approved items are
folded as genericized, workstream-level summaries.

Builds directly on the context-channel sweep
([2026-06-04-context-channel-pull-design.md](2026-06-04-context-channel-pull-design.md)):
same classification rubric, same approval-batch UX, same `last_scan_ts` incrementality.

## Goals

- "Any DM I'm part of": on each pull, sweep all 1:1 DMs and group DMs (MPIMs) the user
  belongs to, for messages since the last DM sweep.
- Relevance-first: classify each DM conversation's new content against the entire vault,
  same rubric as the context-channel sweep.
- Privacy by default: __no auto-fold for DM content__. Every relevant DM item — even a
  high-confidence match — is presented in the approval batch one-by-one with options, and
  approved items are folded as genericized workstream-level summaries (no verbatim 1:1
  quotes), per the user's standing "no DM quotes in public artifacts" rule.
- Zero-friction once set up: after a one-time token-scope re-auth + helper install, DM
  sweeping just happens as part of `/worklog pull`.
- Fail safe: if the enumeration helper is missing/unauthorized, the DM sweep is skipped
  with a one-line note and the channel pull is unaffected.

## Non-goals (v1)

- Per-conversation tuning (per-DM lookback windows, per-DM nudges). One global DM-sweep
  config + one global `last_scan_ts`.
- Auto-fold of DM content (explicitly excluded by design).
- Writing anything back to Slack.
- Sweeping channels the user is in but that aren't DMs (those are the context-channel
  sources).
- Verbatim transcription of DM content into the vault (genericized summaries only).

## Architecture

One new config source, one new helper (enumeration only), a branch in the pull flow, and
a privacy-hardened variant of the existing classify→approve path.

### Config source: `Sources/_dms.md`

DMs are auto-enumerated, so unlike channel sources there is __one__ config file (leading
underscore sorts it first and signals "not a single channel"):

```yaml
---
type: dm-sweep
enabled: true
include_1on1: true
include_groups: true
last_scan_ts: null              # global baseline; first run = now − first_scan_lookback_days
first_scan_lookback_days: 3
nudge_threshold_days: 5
exclude_users: []               # user IDs/names whose 1:1 DMs are never swept
exclude_conversations: []       # specific conversation IDs (im/mpim) to skip
---

# Direct Messages

Auto-enumerated DM + group-DM sweep. One global last_scan_ts; incremental by message
timestamp. DM content is never auto-folded — everything routes through the approval batch.
```

A __single global `last_scan_ts`__ governs the whole sweep (a message is "new" if its
`ts > last_scan_ts`). No per-conversation state map.

### Helper: `~/.config/obsidian-worklog/bin/slack-list-dms`

The only capability the MCP tools lack is __enumerating__ the user's DM conversations
(there is no `conversations.list` MCP tool). A small helper (sibling to `slack-fetch-file`)
fills that gap:

- Reads the token from `~/.config/obsidian-worklog/slack-token`.
- Calls Slack `users.conversations` with `types=im,mpim`, `exclude_archived=true`
  (paginating as needed).
- Prints one conversation per line: `<conversation_id>\t<im|mpim>\t<member_ids_csv>`.
- Exit 0 on success; non-zero with a one-line stderr message on any failure (token
  missing/expired, missing scope, network).

__Reading__ each DM's messages does __not__ need the helper — the existing Slack MCP
(`slack_read_channel` by conversation ID, `slack_read_thread` for group-DM threads) already
reads DMs (proven: it read the Maddie/Astha group DM earlier this project). So the new
token scopes are only `im:read` + `mpim:read` (for enumeration). One-time re-authorize.

### Pull-flow integration

In `/worklog pull`, after all `Sources/*.md` channel sources are processed, if
`Sources/_dms.md` exists and `enabled: true`:

1. Run `slack-list-dms`. On non-zero exit, print a one-line skip note (with the helper's
   stderr) and __skip the DM sweep__; the rest of the pull is unaffected.
2. Filter the conversation list: drop `exclude_conversations`; for `im` entries, drop any
   whose member is in `exclude_users`; honor `include_1on1`/`include_groups`.
3. Compute the window: `ts > last_scan_ts` (first run: `now − first_scan_lookback_days`,
   default 3).
4. For each conversation: `slack_read_channel` since the window (bots excluded); expand
   group-DM threads via `slack_read_thread` as needed. Build conversation units.
5. __Volume guardrail:__ if total DM units exceed ~100, STOP and ask (proceed / narrow /
   skip), same as channels. Never silently truncate.
6. Classify each unit against the __entire vault__ using the context-channel three-way
   rubric — with one override: __DM units never auto-fold__ (see Privacy).
7. Advance `last_scan_ts` to now after the sweep completes.

### Classification + privacy (the deliberate departure)

The three-way rubric (high-confidence match / weak-or-new / noise) still runs, but the
__action__ differs for DMs:

- __High-confidence match → approval batch__ (not auto-fold), pre-filled with the
  recommended "attach as sub-item under `[[matched item]]`" option.
- __Weak/uncertain or genuinely-new → approval batch__, same as channels (attach / new
  `P?` item / Backlog / drop). New standalone items are allowed (same as channels).
- __Noise → drop silently.__

DM items join the __same consolidated end-of-pull approval batch__ as the context-channel
uncertain/new items, presented one-by-one with options (the user's default). On approval:

- Fold a __genericized, workstream-level summary__ — no verbatim 1:1 quotes, no personal
  detail beyond what the worklog item needs. (Departs from the channel sweep, which may
  summarize more literally.)
- Provenance: a Slack permalink to the DM message (private; only the user can open it).
- Dated with the Slack timestamp; wiki-linked; frontmatter regenerated only if a top-level
  item was added.

### Registration / setup

- `Sources/_dms.md` is created on request ("enable DM sweeping" / "register DMs") or
  hand-written. Validated on next pull.
- One-time setup (documented in `docs/SETUP-SLACK.md`): re-authorize the Slack app with
  `im:read` + `mpim:read` added to the existing `files:read` token, and install the
  `slack-list-dms` helper (~30 lines, `curl` + `jq`).
- Until the helper is installed/authorized, `_dms.md` can exist but the sweep is skipped
  with a one-line note each pull.

## Error handling & edge cases

- __Helper missing / unauthorized / wrong scope__ — skip DM sweep, one-line note with the
  stderr; channel pull continues.
- __Enumeration succeeds, a conversation read fails__ — skip that conversation with a note;
  continue the rest; `last_scan_ts` still advances at the end (that conversation's missed
  window is small and re-checked next pull only for `ts > last_scan_ts`, so note it).
- __Idempotency__ — second pull with no new DM activity: zero units, zero batch entries,
  `last_scan_ts` advances. No writes.
- __Excluded conversations__ — never read (filtered before any `slack_read_channel` call),
  so their content never enters context.
- __Bots / Slackbot / app DMs__ — excluded.
- __Volume__ — guardrail prompt, never silent truncation.
- __Sensitivity__ — even with everything batched, the user can `drop` any item; nothing
  DM-derived is written without explicit approval.

## Testing

### Eval scenarios (evals.json)

- __DM branch runs after channels__ — with `_dms.md` enabled and the helper present, a pull
  sweeps channels then DMs; DM items join the same approval batch; nothing DM-derived is
  auto-folded.
- __No auto-fold for DMs__ — a DM thread that clearly matches a tracked item is presented in
  the batch (recommended: attach), NOT written silently.
- __Genericized fold__ — on approving a DM item, the folded sub-item is workstream-level
  with a permalink, containing no verbatim personal quote.
- __Helper missing → graceful skip__ — helper absent/non-zero: DM sweep skipped with a note,
  channel pull completes normally.
- __Exclusions honored__ — a conversation in `exclude_conversations` (and a 1:1 with an
  `exclude_users` member) is never read.
- __Idempotency__ — re-run with no new DM activity: no writes, `last_scan_ts` advances.
- __Volume guardrail__ — >100 DM units → prompt, no silent truncation.

### Manual smoke

With the helper installed and scopes granted, enable `_dms.md` (3-day backfill), run
`/worklog pull`, and verify: DMs are enumerated; relevant items appear in the approval
batch (never auto-folded); an approved item lands as a genericized sub-item with a working
permalink; a second pull is a no-op.

## Files changed

- `skills/worklog/SKILL.md` — new `dm-sweep` source type in the Sources schema; a
  "DM sweep flow" subsection under `/worklog pull`; the no-auto-fold + genericize privacy
  rules; helper reference; summary additions; Important Behaviors note.
- `~/.config/obsidian-worklog/bin/slack-list-dms` — new enumeration helper (delivered as a
  documented snippet in `SETUP-SLACK.md`; not committed as an executable secret-adjacent
  file unless the repo already ships helper sources).
- `docs/SETUP-SLACK.md` — add the `im:read`/`mpim:read` re-auth + `slack-list-dms` install.
- `.claude-plugin/plugin.json` — bump `5.5.0` → `5.6.0`; description mentions DM sweep.
- `evals/evals.json` — add the scenarios above.
- `README.md` — note DM sweeping (privacy-first) under the Slack section.
- __Propagation:__ rsync fork → marketplace, __then substitute the 6 template placeholders__
  (per `worklog-fork-template-propagation` — never raw-rsync the template into the live
  install), then `/reload-plugins`.

## Out of scope (v1)

- Per-DM config / per-DM nudges / per-conversation `last_scan_ts`.
- Auto-fold of DM content.
- Enumerating DMs via anything other than the helper (no MCP `conversations.list` exists).
- A standalone `/worklog pull-dms` command (DM sweep is part of the normal pull).

## Open questions for the implementation plan

Not design decisions — validate during implementation:

1. Exact Slack API + scopes for `users.conversations` enumeration (confirm `im:read` +
   `mpim:read` suffice for `types=im,mpim`, member-of, with pagination).
2. Whether `slack_read_channel` reliably reads a 1:1 by the other user's ID vs the `im`
   conversation `D…`/`C…` ID returned by `users.conversations` (the helper should emit the
   form `slack_read_channel` accepts; validate with one real DM).
3. Whether to cap auto-itemization in the pull summary when many DMs are swept (reuse the
   context-channel summary's collapse-past-N behavior).

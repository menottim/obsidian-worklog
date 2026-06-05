---
title: Context-Channel Pull — Design
date: 2026-06-04
status: draft
feature: context-channel-pull
extends: 2026-05-04-slack-channel-monitoring-design.md
---

# Context-Channel Pull — Design

Add a second Slack source type to the `worklog` skill's `/worklog pull` command:
__context-channel__. Where the existing `meeting-notes-via-email` type treats one
thread as one meeting and persists a `Meetings/` note per thread, a context-channel
is a high-traffic human-discussion channel the user cares about. On every pull, the
skill sweeps each context-channel for everything since the last pull, classifies each
conversation against the existing worklog, __auto-folds high-confidence matches__ as
dated context, __batches uncertain and genuinely-new items for human approval__, and
__silently drops noise__.

This is the "add a type later" extension the original Slack Channel Inbox design
([2026-05-04-slack-channel-monitoring-design.md](2026-05-04-slack-channel-monitoring-design.md))
explicitly anticipated ("Multiple source types … design does not preclude adding types
later"). It reuses that design's substrate wholesale: the `Sources/` registry, the
`last_scan_ts` state machine, the stale-channel nudge, and `/worklog sync`.

## Goals

- One command, two modes: `/worklog pull` continues to process `meeting-notes-via-email`
  sources unchanged, and __additionally__ sweeps every registered `context-channel`.
- Relevance-first ingestion: pulled discussion is matched against the __entire vault__
  (current week, Backlog, archives, People/, Programs/, Teams/) and folded into the
  thing it relates to, rather than dumped as standalone notes.
- High-confidence auto-fold: discussion that clearly continues a tracked item/person/
  program is added as a dated sub-item (or appended note context) without a prompt —
  but is __itemized in the end-of-pull summary__ so nothing lands invisibly.
- Human-in-the-loop for anything uncertain or new: weak matches and genuinely-new-but-
  worthwhile threads are never force-fit; they are collected into __one consolidated
  approval batch__ at the end of the pull.
- Noise stays out: pure chatter that matches nothing and isn't worth tracking is dropped.
- No new artifact type: the worklog items and People/Program/Team notes are the record.
  Provenance is a Slack permalink embedded in each folded sub-item.

## Non-goals (v1)

- Per-thread durable artifacts for context-channels (no `Meetings/` notes for this type —
  too noisy for high-traffic channels; the user chose "worklog edits + chat summary").
- Catching late replies buried in threads whose parent message predates `last_scan_ts`
  (see Known limitations). The sweep targets new threads and threads with recent
  top-level activity; it is a context sweep, not a system of record.
- Background/scheduled pulls. Same as the base design: pulls run inside an active session.
- Bidirectional sync to Slack.
- ML-grade relevance scoring. Classification is the model's judgment against the vault,
  guided by the heuristics below — not a numeric threshold.

## Architecture

One new source `type`, a branch in the pull loop, a three-way classifier, and a
consolidated approval batch. No new vault folders.

### New source type: `context-channel`

`Sources/<channel-name>.md` reuses the existing frontmatter fields with a new `type`:

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
worth sweeping. Frontmatter only is machine-read.
```

The only schema difference from `meeting-notes-via-email` is the `type` value and a
smaller `first_scan_lookback_days` default (7 vs 14), since "all messages and threads"
over two weeks of a busy channel is a large first sweep. Tunable per channel.

### Pull loop branch

`/worklog pull` already iterates `Sources/*.md`. The only structural change: when
processing each source, branch on `type`:

- `meeting-notes-via-email` → existing per-thread flow (unchanged).
- `context-channel` → the sweep + classify flow below.

Uncertain/new candidates from __all__ context-channels accumulate into a single batch
presented once, at the very end of the whole pull (after email sources finish their
own inline flow).

## Context-channel sweep flow

For each `context-channel` source:

1. Compute the window: messages with `ts > last_scan_ts`. On first run (`last_scan_ts`
   is null), look back `first_scan_lookback_days` (default 7). __Incremental only__ —
   never re-reads messages already past `last_scan_ts`.
2. `slack_read_channel` to list top-level messages in the window (bots excluded by
   default; the user's own messages included). For each top-level message that has
   replies, `slack_read_thread` to fetch the full thread.
3. Build the working set of __conversation units__ — a unit is a thread (parent + its
   replies) or a standalone message. The thread is the unit of analysis and of
   classification.
4. Volume guardrail: if a channel yields an unusually large number of units (> ~100),
   __stop and tell the user__ the count and the window, and ask whether to proceed,
   narrow the window, or skip this channel. Never silently truncate.
5. Classify each unit (three-way, below) against the entire vault.
6. Apply high-confidence matches immediately (auto-fold). Stage uncertain + new units
   for the approval batch.
7. Advance `last_scan_ts` per processed unit (resumable across a crash), then to "now"
   at the end of the channel.

### Three-way classification

Each unit is judged against the whole vault — current week, Backlog, Archive/,
People/, Programs/, Teams/:

- __High-confidence match → auto-fold.__ The unit clearly concerns one specific existing
  worklog item, person, program, or team: it names the program/initiative, continues a
  thread already tracked as an item, or is the same people advancing the same topic.
  Action: write the context where it belongs (see "What auto-fold writes").
- __Weak/uncertain match, OR genuinely new-but-worth-tracking → batch for approval.__
  Weak = topically adjacent but not clearly the same item, could plausibly attach to
  more than one item, or concerns a tracked person/program without obviously-actionable
  context. New-worthy = matches nothing but represents a decision, ownership change,
  risk, ask, commitment, or status change the user would plausibly want tracked.
  __Never force-fit a weak match — always ask.__
- __Noise → drop silently.__ Banter, logistics, unrelated team chatter, FYIs with no
  bearing on the user's tracked work.

Classification is the model's judgment; the heuristics above are the rubric. When torn
between "auto-fold" and "ask," prefer "ask" (per the user's "don't force-fit weak
matches" instruction).

### What auto-fold writes

High-confidence matches are written the same way the manual __Processing raw input__
pipeline writes context today:

- A dated sub-item under the matched worklog item:
  `  - <concise summary> ([#channel-name](<slack-permalink>), <Mon D>)`
  — date is the Slack message timestamp (user's local TZ), wiki-linking all known
  people/programs/teams, creating stubs for new entities per the existing Cross-Linking
  rules.
- Substantive context appended to a matched Person/Program/Team note when the unit is
  about that entity.
- Provenance: the Slack permalink in the sub-item is the traceable source (this replaces
  the `Meetings/` note for context-channels).
- Summarize, don't transcribe: fold a concise summary, not the verbatim thread. The
  genericize-at-the-vault→public-artifact boundary rule still applies later, at publish
  time; the private vault may hold the detail.

Touched weekly files get enriched frontmatter regenerated only when a top-level item is
added/changed (per the existing Frontmatter Auto-generation rules); pure sub-item adds
skip regeneration.

## The approval batch (human-in-the-loop)

> __Amendment (2026-06-05):__ per user preference, the approval batch presents staged items __one at a time, each with its own explicit options__ (`AskUserQuestion`-style, up to 4 per prompt), not the single consolidated free-text checklist described below. This is the default for any multi-item input request. Shipped in `SKILL.md` (commit `cd0368a`).

After every source has been swept (email + all context-channels), if any uncertain or
new candidates were staged, present __one consolidated numbered checklist__ in chat:

```
Context-channel pull — N items need your call:

1. [#infrasec-leads · Jun 4] <one-line summary>
   → Might relate to [[GCP CSPM tool evaluation]] — attach as sub-item? (uncertain match)
   permalink: <url>

2. [#side-team · Jun 3] <one-line summary>
   → No match. Looks new — suggest P1 under "SPA Programs": "<proposed title>". Add?
   permalink: <url>

…
Reply e.g.: "add 1; 2 as P2 under Cloud Security; skip 3; 4 attach to [[Triage SIDE]]"
```

Each entry carries: source channel, date, a one-line summary, the proposed action
(attach to `[[item]]` as sub-item / new `P?` item under `<subgroup>` / new Backlog item),
and the permalink. The user approves / rejects / edits (priority, subgroup, item-vs-
sub-item, target) in __bulk free text__ — the same interaction shape as `/worklog review`.

This is a chat checklist, not `AskUserQuestion` (batches routinely exceed that tool's
4-option cap; a checklist scales and supports edits).

On the user's response: apply approved additions (dated with the Slack timestamp,
wiki-linked, permalink provenance), then regenerate enriched frontmatter if any
top-level items were added.

## Registration

Extends the existing inline-registration flow with a type choice:

1. User: "register `#infrasec-leads` as a context channel" (or gives a list of channels).
2. Skill resolves each via `slack_search_channels`, confirms the match.
3. Skill writes `Sources/<channel-name>.md` with `type: context-channel`,
   `last_scan_ts: null`, `first_scan_lookback_days: 7`, default `nudge_threshold_days: 5`.
4. Proceeds with the first sweep for the newly-registered channel(s).

When the user hands over a list of "most important channels," the skill registers one
`Sources/<channel>.md` per channel (preserving per-channel `last_scan_ts` state). The
list is the input to registration, not a stored config blob.

## Nudge, sync, summary (reused)

- __Nudge__: context-channels participate in the existing stale-channel nudge on
  `/worklog rollover`, `/worklog tidy`, `/worklog audit`, identical to email sources.
- __Sync__: `Sources/*.md` config commits to the vault repo via `/worklog sync`, which
  already backs up `SKILL.md` into the vault's `.skills/worklog/`. This is what makes the
  feature "part of the vault setup."
- __Pull summary (chat)__: per context-channel, report
  _N scanned · M auto-folded · J surfaced for approval · K dropped as noise_, then
  __itemize each auto-fold__ (summary + target item + permalink) so the user can spot and
  undo any mis-fold, then the approval-batch results, then the new `last_scan_ts` per
  source.

## Error handling & edge cases

- __Slack MCP unavailable__ — fail fast (same message as base design).
- __Channel not found / ambiguous__ at registration — show `slack_search_channels` matches.
- __Large window / first run__ — volume guardrail above: warn and ask before deep
  analysis; never silently cap (honors the user's no-silent-truncation rule).
- __Rate limit / partial pull__ — `last_scan_ts` advances per processed unit, so a
  crash resumes cleanly.
- __Idempotency__ — guaranteed by incremental `ts > last_scan_ts`. A second pull
  immediately after produces no new units, no auto-folds, no batch.
- __Thread spanning pulls__ — only replies with `ts > last_scan_ts` are classified on a
  later pull; the parent is fetched for context if needed but already-folded content is
  not re-added.
- __Bots__ — excluded by default (`include_bots=false`); context-channels are human
  discussion.
- __Privacy__ — verbatim capture is permitted in the private vault, but auto-folds are
  summarized for readability; the genericize boundary remains at publish time.

## Known limitations (v1)

- Late replies to threads whose parent predates `last_scan_ts` may be missed if
  `slack_read_channel` doesn't surface the parent in the window. Acceptable for a context
  sweep. Revisit with a search-based reply catch-up if it proves lossy in practice.
- Classification quality is model judgment; the auto-fold-itemization in the summary is
  the safety net that lets the user catch mis-classifications.

## Testing

### Eval scenarios (evals.json)

- __Type branch__ — one `meeting-notes-via-email` source and one `context-channel` source
  registered. `/worklog pull` runs the email flow for the first and the sweep flow for the
  second; neither interferes with the other.
- __Auto-fold high-confidence__ — context-channel with a thread that names a tracked
  program. Expect a dated sub-item added under the matching worklog item with a permalink,
  and the auto-fold listed in the summary. No prompt.
- __Batch uncertain + new__ — context-channel with (a) a weakly-related thread and (b) a
  clearly-new decision thread. Expect both staged into the end-of-pull approval batch,
  nothing written until the user responds; bulk response applies edits correctly.
- __Noise dropped__ — context-channel with pure banter. Expect zero writes, counted as
  dropped in the summary.
- __Idempotency__ — run the pull twice. Second run: no new units, no writes.
- __Volume guardrail__ — channel window with > 100 units. Expect a warn-and-ask, not a
  silent cap.

### Manual smoke

Register one real high-traffic channel with a small `first_scan_lookback_days`, run
`/worklog pull`, and verify: high-confidence context lands under the right items with
working permalinks; the approval batch lists uncertain/new candidates with sensible
proposed actions; bulk approve/edit/skip applies correctly; a second immediate pull is a
no-op.

## Files changed

- `skills/worklog/SKILL.md` — `/worklog pull` gains the `type` branch; new
  "Context-channel sweep flow," "Three-way classification," and "Approval batch"
  subsections; `Sources/` schema documents the `context-channel` type; registration and
  summary text updated; new edge cases.
- `.claude-plugin/plugin.json` — bump `5.4.1` → `5.5.0` (new feature); description
  mentions context-channel relevance sweep.
- `evals/evals.json` — add the eval scenarios above.
- `README.md` — "What You Get" + FAQ updated for the two source types.
- (Vault, via `/worklog sync`) — `Sources/<channel>.md` files for the user's channel list.

## Out of scope (v1)

- `Meetings/`-style per-thread notes for context-channels.
- A `/worklog pull #channel` single-channel filter argument (trivial to add later).
- A dedicated `/worklog source add` command (inline registration is enough).
- Numeric/configurable relevance thresholds.
- Search-based late-reply catch-up (see Known limitations).

## Open questions for the implementation plan

Not design decisions — to validate while implementing:

1. Does `slack_read_channel` over a window reliably surface threads whose parent is
   inside the window but whose latest reply is what's new? Confirms the reply-catch-up
   limitation's real-world impact.
2. Best prompt structure to make the model's three-way classification consistent — a
   single pass per unit, or a cheap "is this worklog-relevant at all?" pre-filter before
   the match-vs-new judgment to save tokens on busy channels.
3. Whether to cap the auto-fold itemization in the summary when many units auto-fold
   (e.g., collapse to counts + a link list past N), keeping the summary readable.

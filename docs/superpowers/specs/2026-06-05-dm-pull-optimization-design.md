---
title: DM Pull Optimization (search-based discovery) — Design
date: 2026-06-05
status: draft
feature: dm-sweep-search
extends: 2026-06-05-dm-sweep-design.md
---

# DM Pull Optimization for `/worklog pull` — Design

Replace the DM sweep's enumerate-and-read discovery phase with a single (paginated)
`assistant.search.context` call (Slack's Real-time Search API) scoped to direct messages
and group DMs. The downstream classify, approval-batch, and genericized-fold flow is
unchanged. This is a discovery-layer swap, not a rewrite of the privacy model.

Builds on the original DM sweep ([2026-06-05-dm-sweep-design.md](2026-06-05-dm-sweep-design.md)).

## Motivation

A 2026-06-05 smoke test of the shipped DM sweep (v5.6.0) exposed a scalability wall and
two broken API assumptions:

- The enumeration helper `slack-list-dms` returns __1504 conversations__ (430 1:1, 1074
  group). Slack's `users.conversations` returns __no last-activity timestamp__, so there
  is no cheap way to know which conversations had messages in the window. The shipped flow
  must `slack_read_channel` every conversation since `last_scan_ts` to find new activity,
  which is ~1504 MCP reads __per pull__ (not just the first). The `>100 units` volume
  guardrail fires only after that read phase, so it caps folding, not read cost. The
  feature is not practically executable at this DM volume.
- The shipped flow specifies reading with `include_bots=false`, but the MCP
  `slack_read_channel` tool exposes no such parameter. App and bot DMs (for example
  Envoy visitor notifications) are returned and must be filtered some other way.

Probing during the smoke test established the fix. The helper token already carries the
granular DM search scopes `search:read.im` and `search:read.mpim`. The Real-time Search
API method `assistant.search.context` (shipped 2026-02-17) is purpose-built for an AI app
to retrieve relevant DM content with a natural-language query and explicit date filters,
returning permalinks, surrounding thread context, and a per-message bot flag. The only
gap is one missing scope: `assistant.search.context` returned `missing_scope`,
`needed: search:read.public` (which is the required base scope for the Real-time Search
API even when only DMs are queried), plus a one-time in-client user consent for DM search.

## Decisions (from brainstorming)

- __Primary discovery mechanism: the modern Real-time Search API__ (`assistant.search.context`),
  not legacy `search.messages` (which would need the broad `search:read` and search all
  channels) and not an optimized read-based path.
- __Query strategy: a single broad salience query (MVP)__, not per-program targeted
  queries and not a hybrid. The query is tunable via config; a future hybrid mode is left
  open but out of scope here.
- __No read-based fallback.__ If the search scope or consent is absent, the DM sweep skips
  with a one-line note (same fail-safe posture as a missing helper today). This was a
  deliberate search-primary choice, not hybrid.

## Goals

- Make the DM sweep executable: one (paginated) API call instead of ~1504 reads per pull.
- Preserve the privacy model exactly: DM content is never auto-folded; every relevant unit
  routes through the one-by-one approval batch; approved items fold as genericized,
  workstream-level summaries with a Slack permalink.
- Preserve incrementality: a single global `last_scan_ts` drives the `after` date filter.
- Move the volume guardrail before the expensive work (cap on result pages, asked up front).
- Solve the bot-filter gap natively (the search API excludes bots and exposes
  `is_author_bot`).
- Fail safe: search unavailable (missing scope, not consented, AI Search not enabled,
  network) skips the DM sweep with a one-line note; the channel pull is unaffected.

## Non-goals (this iteration)

- Per-program or per-item targeted queries (hybrid recall mode). The `query:` config field
  and a future mode leave the door open.
- A read-based fallback path.
- Any change to `meeting-notes-via-email` or `context-channel` source flows.
- Writing anything back to Slack.
- Verbatim transcription of DM content into the vault (genericized summaries only, unchanged).

## Recall tradeoff (explicit)

Enumerate-and-read gave completeness (every new message seen, then judged). Search gives
relevance (what the query ranks highly, capped at the page limit). For a "do not miss an
important DM" feature, the query design is the recall guarantee. The MVP accepts the broad
salience query as that guarantee, tunable via the `query:` config field. If recall proves
insufficient in practice, the next iteration adds targeted per-program queries (hybrid),
deduping by `message_ts`.

## Architecture

One new helper (search, replacing enumeration), a rewritten DM-sweep branch in the pull
flow, two new config fields, and a setup change (one scope plus consent). The
classify, approval-batch, and genericize-fold path is untouched.

```
OLD:  slack-list-dms (1504 convos)  ->  slack_read_channel each since last_scan_ts (~1504 calls)
      ->  build units  ->  volume guardrail (too late)  ->  classify  ->  approval  ->  genericize-fold

NEW:  slack-search-dms (1 broad query, after:last_scan_ts, im+mpim, bots off)
      ->  paginate <= max_results  ->  units (message + context_messages)
      ->  classify  ->  approval  ->  genericize-fold
```

### Helper: `~/.config/obsidian-worklog/bin/slack-search-dms`

Sibling to `slack-fetch-file` and `slack-list-dms`, same user token at
`~/.config/obsidian-worklog/slack-token`, `curl` plus `jq`.

- Args: `<after_unix_ts>` (required), `<cursor>` (optional, for pagination).
- Calls `assistant.search.context` with:
  - `query` = the salience query (passed in via env or arg, sourced from `_dms.md`).
  - `channel_types` = the configured subset of `im,mpim`.
  - `content_types=messages`.
  - `include_context_messages=true` (surrounding thread context, thread-limited).
  - the `after` UNIX timestamp filter.
  - bots excluded (the API supports a bot include/exclude filter).
  - `limit=20` (the API maximum per page).
  - `cursor` when provided.
- Output: one JSON object per result line on stdout with at least
  `{channel_id, message_ts, author_user_id, is_author_bot, permalink, content, context_messages}`.
  The final stdout line is a JSON object `{"next_cursor": "<value-or-empty-string>"}` so the
  caller paginates deterministically (empty string means no more pages).
- Exit 0 on success. Non-zero with a one-line stderr message on `missing_scope`,
  not-consented, AI-Search-not-enabled, or network failure.
- Optional preflight: `assistant.search.info` to detect "AI Search not enabled" and report
  it as a clean skip reason rather than a generic error.

Note: a user token (`xoxp-`) does not require `action_token` (that is bot-token only), so
this fits the existing helper-script pattern with no event plumbing.

`slack-list-dms` is retired from the sweep (no enumeration needed). The file stays in place
but unused; mark it deprecated in a header comment and in `SETUP-SLACK.md`.

### The broad salience query

A natural-language query (which triggers semantic search) such as:

> Direct messages with decisions, requests, commitments, blockers, risks, or status
> updates relevant to my ongoing work.

Stored as a `query:` field in `_dms.md` so it is tunable without editing the skill. The
date filter is passed explicitly as the `after` parameter, not embedded in natural
language, per Slack's guidance that explicit filters are more reliable than extracted ones.

### Pull-flow integration (`SKILL.md`, "DM sweep flow")

Rewrite the DM-sweep branch. After all channel sources, if `Sources/_dms.md` exists and
`enabled: true`:

1. Compute `after` = `last_scan_ts`; first run (`last_scan_ts` null) = now minus
   `first_scan_lookback_days` (default 3).
2. Run `slack-search-dms <after>` with the configured query and `channel_types`. Paginate
   via `next_cursor` up to `max_results` (default 100, which is 5 pages of 20). On any
   non-zero exit, print a one-line skip note with the helper stderr and skip the DM sweep;
   the rest of the pull is unaffected.
3. Volume guardrail (now cheap and early): if `next_cursor` is still non-empty at the cap,
   STOP and ask (proceed / narrow the window / skip) before classifying. Never silently
   truncate. Because results are relevance-ranked, the first pages are the most relevant.
4. Apply exclusions: drop results whose `channel_id` is in `exclude_conversations`; drop
   results whose `author_user_id` is in `exclude_users`; honor `include_1on1` /
   `include_groups` by selecting `channel_types`.
5. Each remaining result is a unit; its `context_messages` supply thread context for
   classification and genericized summarization.
6. Classify each unit against the entire vault using the three-way rubric, with the DM
   privacy override (unchanged from the original DM sweep): never auto-fold; every relevant
   unit goes to the approval batch; high-confidence matches lead with the recommended
   "attach as sub-item under [[matched item]]" option; weak or new units offer attach /
   new P? item / Backlog / drop; noise is dropped silently.
7. On approval, fold a genericized, workstream-level summary (no verbatim 1:1 quotes) with
   the `permalink` as provenance, dated with the Slack message timestamp, wiki-linked;
   regenerate frontmatter only if a top-level item was added.
8. Advance `last_scan_ts` to now after the sweep completes.

DM candidates join the same consolidated end-of-pull approval batch as the context-channel
uncertain/new candidates, presented one-by-one with options.

### Config source: `Sources/_dms.md`

Keep all current fields (`type: dm-sweep`, `enabled`, `include_1on1`, `include_groups`,
`last_scan_ts`, `first_scan_lookback_days`, `nudge_threshold_days`, `exclude_users`,
`exclude_conversations`). `include_1on1` / `include_groups` now select `channel_types`
rather than filtering an enumeration. Add two fields:

- `query:` (optional) the salience query string. Defaults to the query above if absent.
- `max_results:` (optional, default 100) the pagination cap and guardrail threshold.

`last_scan_ts` semantics are unchanged (a single global baseline driving the `after`
filter).

### Setup changes (`docs/SETUP-SLACK.md`)

One-time, documented as a short addendum:

- Add `search:read.public` to the app's User Token Scopes, alongside the already-granted
  `search:read.im` and `search:read.mpim`.
- Reinstall / reauthorize the app so the new scope takes effect on the token.
- Complete the in-client user consent for DM and MPIM search (required before the API
  returns DM results).
- Install the `slack-search-dms` helper.
- Verify with `assistant.search.info` that the workspace has Slack AI Search enabled.
- Note that `slack-list-dms` is deprecated and no longer used by the sweep.

## Error handling and edge cases

- __Missing `search:read.public` / not consented / AI Search not enabled__: helper exits
  non-zero; DM sweep skips with a one-line note; channel pull continues.
- __Network error mid-pagination__: stop paginating, classify what was retrieved, and do
  not advance `last_scan_ts` (so the next pull re-covers the same window and nothing is
  missed). Report the partial sweep to the user. Re-covering may re-surface already-seen
  units in the next approval batch; that is acceptable since nothing folds without approval.
- __Idempotency__: a re-run with no new matches returns zero units, zero batch entries,
  and advances `last_scan_ts`. No writes.
- __Excluded conversations / users__: filtered from results before classification, so their
  content is summarized only if it slips the filter (it should not), never folded without
  approval regardless.
- __Bots / Slackbot / app DMs__: excluded by the API bot filter; `is_author_bot` is a
  second guard if any slip through.
- __Volume__: guardrail prompt at the `max_results` cap, never silent truncation.
- __Sensitivity__: unchanged. Everything is batched for approval; nothing DM-derived is
  written without explicit approval; approved items are genericized.

## Testing

### Eval scenarios (`evals.json`)

Replace the enumeration-based DM scenarios (21-27) with search-based equivalents:

- __Search returns hits, all route to approval__ (no auto-fold for any DM unit, including
  high-confidence matches).
- __Genericized fold on approval__ with a working permalink and no verbatim 1:1 quote.
- __Missing scope / not consented -> graceful skip__ with a one-line note; channel pull
  completes.
- __Exclusions honored__: a result whose `channel_id` is in `exclude_conversations`, and
  one whose `author_user_id` is in `exclude_users`, are dropped before classification.
- __Volume cap -> guardrail prompt__: `next_cursor` still set at `max_results`; STOP and
  ask, no silent truncation.
- __Idempotency__: re-run with no new hits: no writes, `last_scan_ts` advances.
- __Bot filtering__: an `is_author_bot` result is dropped.

### Manual smoke

Add `search:read.public` and complete consent, install `slack-search-dms`, run
`/worklog pull`, and verify: one search call surfaces relevant DMs into the approval batch
(never auto-folded); an approved item folds as a genericized sub-item with a working
permalink; a second run is a no-op.

## Files changed

- `~/.config/obsidian-worklog/bin/slack-search-dms` (new helper; delivered as a documented
  snippet in `SETUP-SLACK.md`, consistent with how `slack-fetch-file` and `slack-list-dms`
  are delivered).
- `skills/worklog/SKILL.md`: rewrite the "DM sweep flow" subsection (search-based discovery,
  pagination, early guardrail, exclusions applied to results, native bot filter); update the
  `dm-sweep` source-type notes and the "DM sweeps are approval-only and genericized" Important
  Behavior; reference the new helper; note `slack-list-dms` deprecated.
- `Sources/_dms.md` (vault) and the documented template: add `query:` and `max_results:`;
  clarify `include_1on1` / `include_groups` now select `channel_types`.
- `docs/SETUP-SLACK.md`: add the `search:read.public` scope, reauthorize, in-client consent,
  `slack-search-dms` install, `assistant.search.info` verification, and the `slack-list-dms`
  deprecation note.
- `.claude-plugin/plugin.json`: bump `5.6.0` -> `5.7.0`; description mentions search-based DM
  sweep.
- `evals/evals.json`: replace DM scenarios with the search-based set above.
- `README.md`: update the DM-sweep note to describe search-based discovery and the one-time
  `search:read.public` plus consent setup.
- Propagation: rsync fork to the live install, then substitute the 6 template placeholders
  (per the template-propagation rule), then `/reload-plugins`. Install the new helper
  alongside.

## References

- assistant.search.context method: https://docs.slack.dev/reference/methods/assistant.search.context/
- Real-time Search API guide: https://docs.slack.dev/apis/web-api/real-time-search-api/
- Slack MCP server and Real-time Search API announcement (2026-02-17): https://docs.slack.dev/changelog/2026/02/17/slack-mcp/
- search:read.im scope: https://docs.slack.dev/reference/scopes/search.read.im/
- search:read.mpim scope: https://docs.slack.dev/reference/scopes/search.read.mpim/
- search:read.public scope: https://docs.slack.dev/reference/scopes/search.read.public/

# Search-based DM Pull Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the DM sweep's enumerate-and-read discovery (~1504 Slack reads per pull) with a single paginated `assistant.search.context` call scoped to DMs.

**Architecture:** A new `slack-search-dms` helper calls Slack's Real-time Search API (user token, no `action_token`) with a broad salience query plus `after:last_scan_ts`, `channel_types=im,mpim`, `include_bots=false`. The `SKILL.md` DM-sweep flow consumes its JSON results, applies exclusions, runs the existing classify -> approval-batch -> genericized-fold path unchanged, and advances `last_scan_ts`. `slack-list-dms` is retired from the sweep.

**Tech Stack:** Bash + `curl` + `jq` (helper); markdown skill instructions (`SKILL.md`); JSON eval scenarios (`evals/evals.json`); the worklog Obsidian vault.

**Spec:** `docs/superpowers/specs/2026-06-05-dm-pull-optimization-design.md`

**Branch:** `dm-pull-search-optimization` (already created; the spec commit `6f602f1` is the base).

---

## Prerequisite (manual, one-time, not automatable in code)

Slack scope grants and in-client consent happen in the Slack web UI, so this is a documented prerequisite, not a plan task. The helper smoke tests in Task 2 are written to pass both before and after this is done.

- In the Slack app at `api.slack.com/apps` -> OAuth & Permissions -> User Token Scopes, add `search:read.public` (the token already has `search:read.im` and `search:read.mpim`).
- Reinstall / reauthorize the app; re-store the `xoxp-` token at `~/.config/obsidian-worklog/slack-token` (chmod 600) if it changed.
- Complete the in-client consent prompt for DM/MPIM search inside the Slack client.
- Verify availability:

```bash
TOKEN="$(tr -d '[:space:]' < ~/.config/obsidian-worklog/slack-token)"
curl -sS -X POST https://slack.com/api/assistant.search.info \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Expected once enabled: `{"ok": true, ...}`. Until then, the feature degrades to a clean skip (Task 5 handles this), so implementation can proceed regardless.

---

## File Structure

- `~/.config/obsidian-worklog/bin/slack-search-dms` — NEW helper (search). Source of truth is the snippet committed into `docs/SETUP-SLACK.md`; a copy is installed locally for testing. Single responsibility: one paginated search call, JSON out.
- `docs/SETUP-SLACK.md` — MODIFY the "Optional: DM sweep setup" section (scope, consent, helper snippet, deprecate `slack-list-dms`).
- `skills/worklog/SKILL.md` — MODIFY three regions: `dm-sweep` source-type block (~472-505), the DM summary line (~842-845), the "DM sweep flow" + privacy override (~916-951), and the "DM sweeps are approval-only" Important Behavior (~1542-1547).
- `Sources/_dms.md` (in the vault `/Users/mminutillo/Documents/Obsidian Vault/Sources/_dms.md`) — MODIFY: add `query:` and `max_results:`.
- `evals/evals.json` — MODIFY: replace scenarios 21-27 with search-based equivalents.
- `README.md` — MODIFY two lines (~35, ~397).
- `.claude-plugin/plugin.json` — MODIFY: version 5.6.0 -> 5.7.0 + description.

---

## Task 1: Confirm starting state

**Files:** none (read-only checks)

- [ ] **Step 1: Confirm on the feature branch with the spec committed**

Run:
```bash
cd ~/obsidian-worklog && git branch --show-current && git log -1 --oneline
```
Expected: branch `dm-pull-search-optimization`; HEAD is `6f602f1 docs: spec for search-based DM pull optimization`.

- [ ] **Step 2: Confirm current version is 5.6.0**

Run:
```bash
grep '"version"' ~/obsidian-worklog/.claude-plugin/plugin.json
```
Expected: `"version": "5.6.0",`

---

## Task 2: Write the `slack-search-dms` helper

**Files:**
- Create (local install for testing): `~/.config/obsidian-worklog/bin/slack-search-dms`
- The committed copy lives in `docs/SETUP-SLACK.md` (Task 3).

- [ ] **Step 1: Write the helper to the local bin and chmod it**

```bash
mkdir -p ~/.config/obsidian-worklog/bin
cat > ~/.config/obsidian-worklog/bin/slack-search-dms <<'SCRIPT'
#!/usr/bin/env bash
# slack-search-dms <after_unix_ts> [cursor]
# Searches the user's DMs + group-DMs via Slack's Real-time Search API
# (assistant.search.context). Token at ~/.config/obsidian-worklog/slack-token.
# Env overrides: SLACK_DM_QUERY (salience query), SLACK_DM_CHANNEL_TYPES (default im,mpim).
# Prints one compact JSON result object per line to stdout, then a final line
# {"next_cursor":"<value-or-empty>"}. Exit 0 on success; non-zero + one-line stderr on
# missing scope / not consented / network error.
set -euo pipefail

AFTER="${1:?usage: slack-search-dms <after_unix_ts> [cursor]}"
CURSOR="${2:-}"
TOKEN_FILE="${SLACK_TOKEN_FILE:-$HOME/.config/obsidian-worklog/slack-token}"
QUERY="${SLACK_DM_QUERY:-Direct messages with decisions, requests, commitments, blockers, risks, or status updates relevant to my ongoing work}"
CHANNEL_TYPES="${SLACK_DM_CHANNEL_TYPES:-im,mpim}"

[[ -r "$TOKEN_FILE" ]] || { echo "slack-search-dms: token file not readable at $TOKEN_FILE" >&2; exit 3; }
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
[[ -n "$TOKEN" ]] || { echo "slack-search-dms: empty token" >&2; exit 3; }

args=( -sS -X POST "https://slack.com/api/assistant.search.context"
  -H "Authorization: Bearer $TOKEN"
  -H "Content-Type: application/x-www-form-urlencoded"
  --data-urlencode "query=$QUERY"
  --data-urlencode "channel_types=$CHANNEL_TYPES"
  --data-urlencode "content_types=messages"
  --data-urlencode "include_context_messages=true"
  --data-urlencode "include_bots=false"
  --data-urlencode "after=$AFTER"
  --data-urlencode "limit=20" )
[[ -n "$CURSOR" ]] && args+=( --data-urlencode "cursor=$CURSOR" )

resp="$(curl "${args[@]}")" || { echo "slack-search-dms: network error calling assistant.search.context" >&2; exit 4; }

if [[ "$(printf '%s' "$resp" | jq -r '.ok')" != "true" ]]; then
  echo "slack-search-dms: slack api error: $(printf '%s' "$resp" | jq -r '.error // "unknown_error"')" >&2
  exit 5
fi

printf '%s' "$resp" | jq -c '.results.messages[]? | {channel_id, message_ts, author_user_id, author_name, is_author_bot, permalink, content, context_messages}'
printf '%s' "$resp" | jq -c '{next_cursor: (.response_metadata.next_cursor // "")}'
SCRIPT
chmod 700 ~/.config/obsidian-worklog/bin/slack-search-dms
```

- [ ] **Step 2: Test the missing-token error path (deterministic, no scope needed)**

Run:
```bash
SLACK_TOKEN_FILE=/tmp/nope-$$ ~/.config/obsidian-worklog/bin/slack-search-dms 1780000000; echo "exit=$?"
```
Expected: stderr `slack-search-dms: token file not readable at /tmp/nope-...` and `exit=3`.

- [ ] **Step 3: Test the live call and branch on current scope state**

Run:
```bash
~/.config/obsidian-worklog/bin/slack-search-dms "$(date -v-3d +%s)"; echo "exit=$?"
```
Expected BEFORE the prerequisite scope/consent: stderr `slack-search-dms: slack api error: missing_scope` and `exit=5` (clean skip-able failure, which is the fail-safe contract).
Expected AFTER the prerequisite: one compact JSON object per matching DM message on stdout, then a final `{"next_cursor":"..."}` line, and `exit=0`. Confirm each result has `channel_id`, `message_ts`, `permalink`, `content`.

- [ ] **Step 4: Validate the stdout is well-formed JSON lines**

Run:
```bash
~/.config/obsidian-worklog/bin/slack-search-dms "$(date -v-3d +%s)" 2>/dev/null | jq -e . >/dev/null && echo "valid json lines" || echo "no json (expected if scope not yet granted)"
```
Expected: `valid json lines` once scope is granted; otherwise the no-json branch (acceptable pre-prerequisite).

No commit in this task — the helper is committed as a doc snippet in Task 3 (the repo does not track `~/.config` files).

---

## Task 3: Update `docs/SETUP-SLACK.md`

**Files:**
- Modify: `docs/SETUP-SLACK.md` (replace the entire "## Optional: DM sweep setup" section, currently lines ~208-262)

- [ ] **Step 1: Replace the "Optional: DM sweep setup" section**

Find the section beginning with `## Optional: DM sweep setup` and ending at the end of the file, and replace the whole section with:

````markdown
## Optional: DM sweep setup

To let `/worklog pull` also sweep your 1:1 and group DMs, do two one-time things. The
sweep uses Slack's Real-time Search API (`assistant.search.context`) to retrieve only
DM messages relevant to your work, so it makes one search call instead of reading every
conversation.

### 1. Add search scopes to your Slack user token

In your Slack app at `api.slack.com/apps` -> OAuth & Permissions -> User Token Scopes, add:

- `search:read.public` (required base scope for the Real-time Search API)
- `search:read.im` (search your 1:1 DMs)
- `search:read.mpim` (search your group DMs)

Then reinstall the app to your workspace and update the `xoxp-` token at
`~/.config/obsidian-worklog/slack-token` (chmod 600). Inside the Slack client, complete the
one-time consent prompt that authorizes DM/MPIM search. Verify the workspace has Slack AI
Search enabled:

```bash
TOKEN="$(tr -d '[:space:]' < ~/.config/obsidian-worklog/slack-token)"
curl -sS -X POST https://slack.com/api/assistant.search.info \
  -H "Authorization: Bearer $TOKEN" | jq .
```

If this returns `"ok": true`, you are set. If it returns `missing_scope` or a not-enabled
error, finish the scope/consent steps above; until then `/worklog pull` skips the DM sweep
with a one-line note and the rest of the pull is unaffected.

### 2. Install the `slack-search-dms` helper

Save this as `~/.config/obsidian-worklog/bin/slack-search-dms` and `chmod 700` it:

```bash
#!/usr/bin/env bash
# slack-search-dms <after_unix_ts> [cursor]
# Searches the user's DMs + group-DMs via Slack's Real-time Search API
# (assistant.search.context). Token at ~/.config/obsidian-worklog/slack-token.
# Env overrides: SLACK_DM_QUERY (salience query), SLACK_DM_CHANNEL_TYPES (default im,mpim).
# Prints one compact JSON result object per line to stdout, then a final line
# {"next_cursor":"<value-or-empty>"}. Exit 0 on success; non-zero + one-line stderr on
# missing scope / not consented / network error.
set -euo pipefail

AFTER="${1:?usage: slack-search-dms <after_unix_ts> [cursor]}"
CURSOR="${2:-}"
TOKEN_FILE="${SLACK_TOKEN_FILE:-$HOME/.config/obsidian-worklog/slack-token}"
QUERY="${SLACK_DM_QUERY:-Direct messages with decisions, requests, commitments, blockers, risks, or status updates relevant to my ongoing work}"
CHANNEL_TYPES="${SLACK_DM_CHANNEL_TYPES:-im,mpim}"

[[ -r "$TOKEN_FILE" ]] || { echo "slack-search-dms: token file not readable at $TOKEN_FILE" >&2; exit 3; }
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
[[ -n "$TOKEN" ]] || { echo "slack-search-dms: empty token" >&2; exit 3; }

args=( -sS -X POST "https://slack.com/api/assistant.search.context"
  -H "Authorization: Bearer $TOKEN"
  -H "Content-Type: application/x-www-form-urlencoded"
  --data-urlencode "query=$QUERY"
  --data-urlencode "channel_types=$CHANNEL_TYPES"
  --data-urlencode "content_types=messages"
  --data-urlencode "include_context_messages=true"
  --data-urlencode "include_bots=false"
  --data-urlencode "after=$AFTER"
  --data-urlencode "limit=20" )
[[ -n "$CURSOR" ]] && args+=( --data-urlencode "cursor=$CURSOR" )

resp="$(curl "${args[@]}")" || { echo "slack-search-dms: network error calling assistant.search.context" >&2; exit 4; }

if [[ "$(printf '%s' "$resp" | jq -r '.ok')" != "true" ]]; then
  echo "slack-search-dms: slack api error: $(printf '%s' "$resp" | jq -r '.error // "unknown_error"')" >&2
  exit 5
fi

printf '%s' "$resp" | jq -c '.results.messages[]? | {channel_id, message_ts, author_user_id, author_name, is_author_bot, permalink, content, context_messages}'
printf '%s' "$resp" | jq -c '{next_cursor: (.response_metadata.next_cursor // "")}'
```

Test it (3-day window): `~/.config/obsidian-worklog/bin/slack-search-dms "$(date -v-3d +%s)"`
prints JSON result lines then a `{"next_cursor":...}` line. A non-zero exit (missing scope,
bad token, network) makes `/worklog pull` skip the DM sweep gracefully.

### Deprecation: `slack-list-dms`

The earlier `slack-list-dms` enumeration helper and the `im:read` / `mpim:read` scopes are no
longer used by the DM sweep (search replaces enumeration). You can leave them in place or
remove `~/.config/obsidian-worklog/bin/slack-list-dms`; the sweep does not call it.
````

- [ ] **Step 2: Verify the section parses and the helper snippet matches the installed copy**

Run:
```bash
cd ~/obsidian-worklog
grep -q "assistant.search.context" docs/SETUP-SLACK.md && echo "snippet present"
# Extract the fenced helper from the doc and diff against the installed copy:
awk '/^#!\/usr\/bin\/env bash/{f=1} f{print} /^printf .*next_cursor/{if(f)exit}' docs/SETUP-SLACK.md > /tmp/doc-helper.sh
diff <(sed -n '1,/next_cursor/p' ~/.config/obsidian-worklog/bin/slack-search-dms) /tmp/doc-helper.sh && echo "helper matches" || echo "REVIEW: doc vs installed differ"
```
Expected: `snippet present` and `helper matches` (or a reviewed, intentional diff).

- [ ] **Step 3: Commit**

```bash
cd ~/obsidian-worklog
git add docs/SETUP-SLACK.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "docs(setup): search-based DM sweep setup (search scopes + slack-search-dms helper)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Update the `dm-sweep` source-type block in `SKILL.md`

**Files:**
- Modify: `skills/worklog/SKILL.md` (the `### Source type: \`dm-sweep\`` block, ~472-505)

- [ ] **Step 1: Replace the config example and Notes**

In the `### Source type: \`dm-sweep\`` block, replace the YAML example body and the `Notes:` list so the block reads:

````markdown
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
  `ts > last_scan_ts`, passed as the search `after` filter); there is no per-conversation
  state.
- Discovery uses the `slack-search-dms` helper (Slack `assistant.search.context`), which
  returns only relevant DM messages with permalinks, surrounding thread context, and a bot
  flag. No enumeration or per-conversation reads.
- `include_1on1` / `include_groups` select the search `channel_types` (`im` and/or `mpim`).
- `query` overrides the built-in salience query; `max_results` caps pagination and is the
  volume-guardrail threshold (default 100).
- Requires one-time scopes `search:read.public` + `search:read.im` + `search:read.mpim` and
  in-client DM-search consent (see `docs/SETUP-SLACK.md`).
````

- [ ] **Step 2: Verify no stale enumeration language remains in the block**

Run:
```bash
sed -n '/^### Source type: `dm-sweep`/,/^## Meetings/p' ~/obsidian-worklog/skills/worklog/SKILL.md | grep -n "auto-enumerated\|users.conversations\|slack-list-dms\|im:read\|mpim:read" && echo "REVIEW: stale text remains" || echo "clean"
```
Expected: `clean`.

- [ ] **Step 3: Commit**

```bash
cd ~/obsidian-worklog
git add skills/worklog/SKILL.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "feat(pull): dm-sweep source type uses search (query + max_results config)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Rewrite the DM sweep flow, summary, and Important Behavior in `SKILL.md`

**Files:**
- Modify: `skills/worklog/SKILL.md` (the `__DM sweep flow:__` + `__DM privacy override...__` region ~916-951; the DM summary paragraph ~842-845; the `__DM sweeps are approval-only and genericized.__` behavior ~1542-1547)

- [ ] **Step 1: Replace the `__DM sweep flow:__` block (through the end of the privacy override, before `__First-run registration:__`)**

````markdown
__DM sweep flow:__

If `Sources/_dms.md` exists and is `enabled: true`, run this after all channel sources
(its candidates join the same end-of-pull approval batch):

1. Compute the `after` timestamp: `last_scan_ts` if set, else `now − first_scan_lookback_days`
   (default 3 days), as a UNIX timestamp.
2. Search DMs by running the helper (unconditionally; do not pre-check "is it configured" —
   run it and branch on exit code, same pattern as `slack-fetch-file`). Pass the `after`
   timestamp; set the salience query via `SLACK_DM_QUERY` if `_dms.md` `query` is non-empty,
   and `SLACK_DM_CHANNEL_TYPES` from `include_1on1`/`include_groups` (`im`, `mpim`, or both):
   ```bash
   SLACK_DM_CHANNEL_TYPES="im,mpim" ~/.config/obsidian-worklog/bin/slack-search-dms <after_unix_ts>
   ```
   It prints one JSON result object per line, then a final `{"next_cursor":"..."}` line. On
   any non-zero exit, print a one-line skip note with the helper's stderr and __skip the DM
   sweep__; the rest of the pull is unaffected. Paginate by re-running with the returned
   `next_cursor` as the second argument until it is empty or `max_results` results have been
   collected.
3. __Volume guardrail (checked up front):__ if `next_cursor` is still non-empty after
   collecting `max_results` results (default 100), STOP and ask (proceed / narrow the window /
   skip). Never silently truncate. Results are relevance-ranked, so earlier pages matter most.
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
   (network error mid-pagination), do __not__ advance `last_scan_ts`; report the partial sweep
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
````

- [ ] **Step 2: Replace the DM summary paragraph (the `For the DM sweep, the summary reports ...` paragraph)**

````markdown
For the DM sweep, the summary reports `N results · M surfaced for approval · K dropped`
(DMs never report auto-folds, since none are auto-folded), followed by the approval-batch
outcomes. If the helper was unavailable, report `DM sweep skipped: <reason>` and nothing
else for DMs.
````

- [ ] **Step 3: Replace the `__DM sweeps are approval-only and genericized.__` Important Behavior bullet**

````markdown
- __DM sweeps are approval-only and genericized.__ With `Sources/_dms.md` enabled, pulls
  also sweep the user's 1:1 + group DMs via Slack's Real-time Search API (the
  `slack-search-dms` helper). DM content is __never auto-folded__ — every relevant item
  routes through the one-by-one approval batch, and approved items are folded as genericized,
  workstream-level summaries with a Slack permalink. If the helper is missing/unauthorized
  (or DM-search consent is absent), the DM sweep is skipped and the channel pull is unaffected.
````

- [ ] **Step 4: Verify no stale read-based language remains in the DM flow**

Run:
```bash
cd ~/obsidian-worklog
grep -n "slack-list-dms\|enumerate the user's DMs\|For each conversation, .slack_read_channel\|total DM units exceed" skills/worklog/SKILL.md && echo "REVIEW: stale DM-flow text remains" || echo "clean"
```
Expected: `clean`.

- [ ] **Step 5: Commit**

```bash
cd ~/obsidian-worklog
git add skills/worklog/SKILL.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "feat(pull): search-based DM sweep flow (one call, early guardrail, native bot filter)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Update the live `Sources/_dms.md` config

**Files:**
- Modify: `/Users/mminutillo/Documents/Obsidian Vault/Sources/_dms.md`

- [ ] **Step 1: Rewrite the frontmatter + body to match the new schema**

Overwrite the file with:

```markdown
---
type: dm-sweep
enabled: true
include_1on1: true
include_groups: true
last_scan_ts: null
first_scan_lookback_days: 3
nudge_threshold_days: 5
query: ""
max_results: 100
exclude_users: []
exclude_conversations: []
---

# Direct Messages

Search-based DM + group-DM sweep via Slack's Real-time Search API. One global
`last_scan_ts`, incremental by message timestamp. DM content is never auto-folded:
everything routes through the approval batch and is folded only on approval, as a
genericized workstream-level summary.
```

- [ ] **Step 2: Verify it is valid YAML frontmatter**

Run:
```bash
awk '/^---$/{n++; next} n==1{print}' "/Users/mminutillo/Documents/Obsidian Vault/Sources/_dms.md" | grep -E "^(query|max_results):" && echo "new fields present"
```
Expected: both `query:` and `max_results:` lines printed, then `new fields present`.

No repo commit here (vault is a separate git repo, synced via `/worklog sync`). Note it for the propagation step.

---

## Task 7: Replace eval scenarios 21-27 in `evals/evals.json`

**Files:**
- Modify: `evals/evals.json` (objects with `id` 21 through 27)

- [ ] **Step 1: Replace the seven objects (ids 21-27) with the search-based set**

Replace the array elements 21-27 with:

```json
    {
      "id": 21,
      "prompt": "/worklog pull (Sources/_dms.md enabled, slack-search-dms helper present and scope/consent granted, plus context-channel sources)",
      "expected_output": "Should process channel sources, then run the DM sweep after them: call slack-search-dms with after=last_scan_ts and channel_types from include_1on1/include_groups, paginate via next_cursor, classify each result against the vault. DM candidates join the SAME end-of-pull approval batch as context-channel uncertain/new items. NOTHING from a DM is auto-folded.",
      "issue_tested": "DM-sweep branch runs after channels via search; DM items batch, never auto-fold"
    },
    {
      "id": 22,
      "prompt": "/worklog pull (a DM search result clearly matches a tracked worklog item)",
      "expected_output": "Should present the DM match in the approval batch with a recommended 'attach as sub-item under [[item]]' option - NOT write it silently. Unlike a context-channel high-confidence match, a DM high-confidence match is never auto-folded.",
      "issue_tested": "DM high-confidence match goes to approval batch, not auto-fold"
    },
    {
      "id": 23,
      "prompt": "/worklog pull then approve a DM-derived item from the batch",
      "expected_output": "On approval, the folded sub-item is a genericized, workstream-level summary (no verbatim 1:1 quote, no personal detail beyond the item's need), dated with the result's message_ts, wiki-linked, with the result's permalink for provenance.",
      "issue_tested": "Approved DM items fold as genericized summaries with provenance"
    },
    {
      "id": 24,
      "prompt": "/worklog pull (Sources/_dms.md enabled but slack-search-dms missing, scope absent, or consent not granted so the helper returns non-zero)",
      "expected_output": "Should run the helper, get a non-zero exit (e.g. missing_scope), print a one-line 'DM sweep skipped: <reason>' note, and continue/complete the rest of the pull normally. Must NOT block or fail the whole pull.",
      "issue_tested": "Helper missing/unauthorized/not-consented -> DM sweep skipped gracefully"
    },
    {
      "id": 25,
      "prompt": "/worklog pull (_dms.md has exclude_users and exclude_conversations populated)",
      "expected_output": "Search results whose channel_id is in exclude_conversations, and whose author_user_id is in exclude_users, are dropped before classification - their content never enters the approval batch. include_1on1/include_groups are honored by selecting channel_types.",
      "issue_tested": "DM exclusions filter search results before classification"
    },
    {
      "id": 26,
      "prompt": "/worklog pull (run twice with no new DM activity)",
      "expected_output": "Second run: search with after=last_scan_ts returns no results, no batch entries, no writes; last_scan_ts advances to now. Idempotent.",
      "issue_tested": "DM-sweep idempotency via global last_scan_ts as the search after filter"
    },
    {
      "id": 27,
      "prompt": "/worklog pull (DM search yields more than max_results results, next_cursor still set at the cap)",
      "expected_output": "Should hit the volume guardrail up front: stop and tell the user the count and window, ask whether to proceed / narrow / skip. No silent truncation.",
      "issue_tested": "DM-sweep volume guardrail at max_results - no silent truncation"
    }
```

- [ ] **Step 2: Validate JSON**

Run:
```bash
cd ~/obsidian-worklog && jq -e '.evals | length' evals/evals.json && jq -e '[.evals[].id] == ([range(1;28)])' evals/evals.json && echo "json valid, ids 1-27 contiguous"
```
Expected: `27`, `true`, `json valid, ids 1-27 contiguous`.

- [ ] **Step 3: Commit**

```bash
cd ~/obsidian-worklog
git add evals/evals.json
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "test: search-based DM-sweep eval scenarios (21-27)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Update `README.md`

**Files:**
- Modify: `README.md` (the Slack-channel-inbox bullet ~line 35; the DM privacy line ~line 397)

- [ ] **Step 1: Update the DM clause in the Slack-channel-inbox bullet**

In the long bullet that ends with the DM description, replace the final clause
(`The pull can also sweep your 1:1 + group DMs (opt-in via ... the \`slack-list-dms\` helper); DM content is never auto-folded ...`) with:

```markdown
The pull can also sweep your 1:1 + group DMs (opt-in via `Sources/_dms.md` + a one-time `search:read.public`/`search:read.im`/`search:read.mpim` re-auth, in-client DM-search consent, and the `slack-search-dms` helper); it uses Slack's Real-time Search API to retrieve only relevant DM messages, and DM content is never auto-folded -- every relevant item routes through the approval batch and is folded as a genericized summary with a private Slack permalink
```

- [ ] **Step 2: Update the DM privacy answer (~line 397)**

Replace that line with:

```markdown
Only if you opt in with `Sources/_dms.md` and install the `slack-search-dms` helper (plus the search scopes and DM-search consent). Even then, no DM content is ever written without your explicit approval, and approved items are genericized (no verbatim quotes) with a private Slack permalink.
```

- [ ] **Step 3: Verify the stale helper name is gone**

Run:
```bash
grep -n "slack-list-dms\|im:read./mpim:read" ~/obsidian-worklog/README.md && echo "REVIEW: stale text" || echo "clean"
```
Expected: `clean`.

- [ ] **Step 4: Commit**

```bash
cd ~/obsidian-worklog
git add README.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "docs: README describes search-based DM sweep

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Bump plugin version 5.6.0 -> 5.7.0

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Read the current file**

Run:
```bash
cat ~/obsidian-worklog/.claude-plugin/plugin.json
```

- [ ] **Step 2: Set `version` to `5.7.0` and update the description to mention search-based DM sweep**

Edit `.claude-plugin/plugin.json`: change `"version": "5.6.0",` to `"version": "5.7.0",`. If the description mentions the DM sweep, ensure it reads as search-based (e.g. "...search-based DM sweep..."); otherwise leave the description text as-is apart from the version.

- [ ] **Step 3: Validate JSON and version**

Run:
```bash
cd ~/obsidian-worklog && jq -e '.version == "5.7.0"' .claude-plugin/plugin.json && echo "version bumped"
```
Expected: `true`, `version bumped`.

- [ ] **Step 4: Commit**

```bash
cd ~/obsidian-worklog
git add .claude-plugin/plugin.json
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "chore: bump obsidian-worklog to 5.7.0 (search-based DM sweep)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Propagate to the live install and run the manual smoke test

**Files:**
- The live install copies (marketplace, cache/5.7.0, vault `.skills/worklog`) and the local helper.

- [ ] **Step 1: Rsync the fork to the marketplace install, then substitute the 6 template placeholders**

This follows the worklog-fork-template-propagation rule: never raw-copy the template (it leaves `__VAULT_PATH__` tokens). Substitute after copying.

```bash
SRC=~/obsidian-worklog
DST=~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
rsync -a --delete --exclude '.git' "$SRC/" "$DST/"
# Substitute the 6 placeholders in the installed SKILL.md:
sed -i '' \
  -e 's#__VAULT_PATH__#/Users/mminutillo/Documents/Obsidian Vault#g' \
  -e 's#__USER_NAME__#Menotti#g' \
  -e 's#__GIT_USER_NAME__#mminutillo#g' \
  -e 's#__GIT_USER_EMAIL__#mminutillo@netflix.com#g' \
  -e 's#__SKILL_INSTALL_PATH__#/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog#g' \
  -e 's#__BACKUP_REPO_URL__#github.netflix.net/mminutillo/obsidian-vault#g' \
  "$DST/skills/worklog/SKILL.md"
```

- [ ] **Step 2: Verify no placeholders remain and the version is 5.7.0 in the install**

Run:
```bash
DST=~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
grep -c "__VAULT_PATH__\|__USER_NAME__\|__GIT_USER_NAME__\|__GIT_USER_EMAIL__\|__SKILL_INSTALL_PATH__\|__BACKUP_REPO_URL__" "$DST/skills/worklog/SKILL.md"
jq -r .version "$DST/.claude-plugin/plugin.json"
```
Expected: `0` then `5.7.0`.

- [ ] **Step 3: Sync to the cache copy keyed by version and the vault `.skills` copy**

```bash
DST=~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
mkdir -p ~/.claude/plugins/cache/personal/obsidian-worklog/5.7.0
rsync -a --delete --exclude '.git' "$DST/" ~/.claude/plugins/cache/personal/obsidian-worklog/5.7.0/
cp "$DST/skills/worklog/SKILL.md"      "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/SKILL.md"
cp "$DST/.claude-plugin/plugin.json"   "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/plugin.json"
```

- [ ] **Step 4: Reload plugins so the Skill tool picks up 5.7.0**

In Claude Code, run `/reload-plugins` (or restart the session). Confirm the worklog skill base directory resolves to the `5.7.0` cache path on next invocation.

- [ ] **Step 5: Manual smoke test (requires the prerequisite scope/consent)**

After completing the Prerequisite section:
1. Run `/worklog pull`.
2. Verify the DM sweep issues one search call (paginated), not per-conversation reads.
3. Verify relevant DMs appear in the end-of-pull approval batch and nothing DM-derived is auto-folded.
4. Approve one item; verify it folds as a genericized sub-item with a working permalink, dated with the Slack `message_ts`.
5. Run `/worklog pull` again immediately; verify the DM sweep is a no-op (no new results, no writes) and `last_scan_ts` advanced.
6. If scope/consent is NOT yet granted, verify the pull prints `DM sweep skipped: ... missing_scope` and completes the channel portion normally.

- [ ] **Step 6: Push the branch**

```bash
cd ~/obsidian-worklog && git push -u origin dm-pull-search-optimization
```

---

## Self-Review (completed by plan author)

- __Spec coverage:__ helper (Tasks 2,3) ✓; broad salience query as default + `query` override (Tasks 2,4,6) ✓; pull-flow rewrite with early guardrail + exclusions + native bot filter (Task 5) ✓; `_dms.md` `query`/`max_results` (Tasks 4,6) ✓; SETUP-SLACK scope/consent/helper/deprecation (Task 3) ✓; evals replaced (Task 7) ✓; README (Task 8) ✓; version bump (Task 9) ✓; propagation with placeholder substitution (Task 10) ✓; fail-safe skip on missing scope (Tasks 2 step 3, 5 step 1, 7 id 24) ✓; partial-failure no-advance (Task 5 step 1) ✓.
- __Placeholder scan:__ no TBD/TODO; all code blocks complete; the only manual step (Slack scope/consent) is explicitly called out as a non-automatable prerequisite with a verification command.
- __Type/name consistency:__ helper output fields (`channel_id`, `message_ts`, `author_user_id`, `author_name`, `is_author_bot`, `permalink`, `content`, `context_messages`) and `response_metadata.next_cursor` are used consistently across the helper (Task 2/3), the flow (Task 5), and the evals (Task 7). Config field names (`include_1on1`, `include_groups`, `query`, `max_results`, `exclude_users`, `exclude_conversations`) match across Tasks 4, 6, 5, 7.

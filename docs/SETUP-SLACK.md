# Slack Setup

This guide connects the worklog skill to Slack. It covers four features:

| Feature | Command | What it needs |
|---------|---------|---------------|
| Channel pull | `/worklog pull` | A Slack MCP server (required) |
| Email body auto-fetch | `/worklog pull` | A Slack user token with `files:read` and the `slack-fetch-file` helper (optional) |
| DM sweep | `/worklog pull` | The Slack MCP search tool, or the `slack-search-dms` helper with `search:read.*` scopes (optional, opt-in) |
| One-thread ingest | `/worklog ingest <permalink>` | A Slack MCP server |

Terms in this guide:

- A __source__ is one note in `Sources/` in your vault. Each note tells `/worklog pull` what to read.
- A __helper__ is a small Bash script in `~/.config/obsidian-worklog/bin`. The skill runs it directly.
- A __user token__ is a Slack OAuth token that starts with `xoxp-`. It has your own channel access.

## 1. Connect a Slack MCP server

`/worklog pull` and `/worklog ingest` read Slack through a Slack MCP server. The skill uses these tools:

- `slack_read_channel` lists the top-level messages in a channel.
- `slack_read_thread` reads a full thread.
- `slack_search_channels` finds a channel ID from a channel name.
- `slack_search_users` finds a full name from a user ID or handle.
- `slack_search_public_and_private` lists your DMs for the DM sweep.

Install a Slack MCP plugin in your host before the first pull. If no Slack MCP is available, the pull stops with this message:

```
This needs a Slack MCP plugin. Install one and re-run.
```

__Codex:__ before a pull, the skill checks that the host can do four operations. These are: list channel messages in a time window, read a full thread, find a channel by name, and find a user by ID or handle. If one operation is missing, the pull stops and names it. The pull does not move `last_scan_ts`. The skill does not use semantic or RAG Slack search as a replacement, because that search does not return every message. For one thread, use `$worklog ingest <slack-permalink>`.

## 2. Register your sources

The skill supports three source types. Each type has its own flow.

| Source type | `type:` value | File | What the pull does |
|-------------|---------------|------|--------------------|
| Forwarded-email meeting notes | `meeting-notes-via-email` | `Sources/<channel-name>.md` | Writes one `Meetings/` note per thread, then extracts items |
| Context channel | `context-channel` | `Sources/<channel-name>.md` | Reads new messages, sorts them into three groups, and adds the relevant ones to your vault |
| DM sweep | `dm-sweep` | `Sources/_dms.md` (one file) | Finds new DMs and group DMs, then asks you about each relevant one |

To register a meeting-notes channel:

1. Run `/worklog pull` when `Sources/` is empty, or tell the skill to register a channel.
2. Give the channel name.
3. Confirm the channel ID that the skill finds.

The skill writes the source note with `first_scan_lookback_days: 14`. See [examples/source-note.md](../examples/source-note.md).

To register a context channel, tell the skill "register `#channel-name` as a context channel". You can give a list of channels. The skill writes one file per channel with `first_scan_lookback_days: 7`.

To turn on the DM sweep, see [DM sweep](#dm-sweep).

### How a meeting-notes pull works

Slack's email-to-channel integration posts large forwarded emails as `.html` or `.eml` file attachments. The email body is in the file, not in the message text. Most Slack MCP tools return only the file metadata.

For each new thread, the skill does these steps:

1. It runs `~/.config/obsidian-worklog/bin/slack-fetch-file <file_id>`.
2. If the helper exits with 0, the skill uses its output as the email body.
3. If the helper exits with any other code, the skill shows a summary of the thread and asks you to paste the body. You can also say `skip` or `skip all remaining`.

The skill always runs the helper first. It does not check the setup before it runs the helper. A missing helper gives a non-zero exit, and the skill asks you to paste.

The skill then writes `Meetings/YYYY-MM-DD-<topic-slug>.md`. See [examples/meeting-note.md](../examples/meeting-note.md). Thread replies are normal Slack messages, so they never need the helper. On later pulls, the skill adds only new replies to `## Discussion`.

### How a context-channel pull works

The skill reads each thread or standalone message since `last_scan_ts`. It puts each one into one of three groups:

- __High-confidence match:__ the skill adds it to the matching item or note immediately. The skill lists each of these in the pull summary, so you can undo a wrong one.
- __Weak match, or new and worth tracking:__ the skill asks you about it at the end of the pull.
- __Noise:__ the skill ignores it.

The skill writes no `Meetings/` note for a context channel. A Slack permalink records where each fact came from. If a channel has more than about 100 threads and messages, the skill stops and asks you what to do.

## 3. Create a personal Slack app (optional)

Do this step only for email body auto-fetch or the DM helper. The channel pull and the MCP DM sweep do not need a token.

1. Go to <https://api.slack.com/apps>.
2. Click __Create New App__, then __From scratch__.
3. Type an app name, for example `obsidian-worklog-fetcher`.
4. Select the workspace that has your source channels.
5. In the left sidebar, click __OAuth & Permissions__.
6. Under __User Token Scopes__, add the scopes from the table below. Do not add Bot Token Scopes.
7. Click __Install to Workspace__, then click __Allow__.
8. Copy the __User OAuth Token__. It starts with `xoxp-`.

| Scope | Needed for |
|-------|------------|
| `files:read` | `slack-fetch-file` (email body auto-fetch) |
| `search:read.public` | `slack-search-dms`. This is the base scope for the Real-time Search API. |
| `search:read.im` | `slack-search-dms`, to search your 1:1 DMs |
| `search:read.mpim` | `slack-search-dms`, to search your group DMs |

Use a user token, not a bot token (`xoxb-`). A user token can read every channel that you are a member of. A bot token can read a channel only after you invite the bot to it.

If you add scopes later, install the app again. Then copy the new token. Store it again (step 4).

If your workspace requires admin approval, Slack shows __Request to Install__. Submit the request. See [App approval](#app-approval).

## 4. Store the token

Run these commands. Replace `xoxp-...` with your token.

```bash
mkdir -p ~/.config/obsidian-worklog
umask 077
printf '%s' 'xoxp-...' > ~/.config/obsidian-worklog/slack-token
chmod 600 ~/.config/obsidian-worklog/slack-token
```

Both helpers read the token from `~/.config/obsidian-worklog/slack-token`. To use a different file, set `SLACK_TOKEN_FILE` in the environment that runs Claude Code or Codex. The helpers do not read the macOS Keychain.

## 5. Install the helpers

The skill runs the helpers from the fixed path `~/.config/obsidian-worklog/bin`. Each helper needs `curl` and `jq`.

### `slack-fetch-file`

This helper calls Slack's `files.info` to get the download URL. Then it downloads the file body with the token.

```bash
mkdir -p ~/.config/obsidian-worklog/bin
cat > ~/.config/obsidian-worklog/bin/slack-fetch-file <<'SCRIPT'
#!/usr/bin/env bash
# slack-fetch-file <file_id>
# Reads the body of a Slack file. Token at ~/.config/obsidian-worklog/slack-token.
# Prints body to stdout. Exits non-zero on auth/not-found/network error.
set -euo pipefail

FILE_ID="${1:?usage: slack-fetch-file <file_id>}"
TOKEN_FILE="${SLACK_TOKEN_FILE:-$HOME/.config/obsidian-worklog/slack-token}"

if [[ ! -r "$TOKEN_FILE" ]]; then
  echo "slack-fetch-file: token file not found or unreadable: $TOKEN_FILE" >&2
  exit 2
fi

TOKEN="$(cat "$TOKEN_FILE")"
META="$(curl -fsS -H "Authorization: Bearer $TOKEN" \
  "https://slack.com/api/files.info?file=$FILE_ID")" || {
  echo "slack-fetch-file: files.info request failed for $FILE_ID" >&2
  exit 3
}

OK=$(echo "$META" | jq -r .ok)
if [[ "$OK" != "true" ]]; then
  ERR=$(echo "$META" | jq -r .error)
  echo "slack-fetch-file: files.info returned error: $ERR" >&2
  exit 4
fi

URL=$(echo "$META" | jq -r '.file.url_private_download // .file.url_private')
if [[ -z "$URL" || "$URL" == "null" ]]; then
  echo "slack-fetch-file: no download URL in files.info response" >&2
  exit 5
fi

curl -fsSL -H "Authorization: Bearer $TOKEN" "$URL"
SCRIPT
chmod 700 ~/.config/obsidian-worklog/bin/slack-fetch-file
```

### `slack-search-dms`

The skill uses this helper only when the Slack MCP search tool is not available. See [DM sweep](#dm-sweep).

The interface:

- Argument: one Unix timestamp. The helper returns only messages newer than it.
- Input: search queries on stdin, one per line. With no stdin, it uses a built-in topic list.
- Output: one JSON object per message, then one summary line.
- Exit code: 0 if one or more queries succeeded. Non-zero on a setup error or if every query failed.

Save this as `~/.config/obsidian-worklog/bin/slack-search-dms`. Then run `chmod 700` on it.

```bash
#!/usr/bin/env bash
# slack-search-dms <after_unix_ts>
#
# Searches the user's DMs + group-DMs via Slack's Real-time Search API
# (assistant.search.context). Token at ~/.config/obsidian-worklog/slack-token.
#
# QUERIES: read from stdin, one per line (blank lines and '#' comments ignored).
# With no stdin queries, falls back to the single built-in salience query.
#
# WHY FAN-OUT: assistant.search.context is relevance-ranked, returns no
# next_cursor, and caps each query's result set well below `limit` (one fixed
# query returned 13 results spanning three years, newest two weeks old, at
# limit=20, 50 and 100 alike). Its `after` parameter filters that already-tiny
# set rather than shifting the search window, so a single-query incremental
# sweep reports 0 by construction and silently misses recent DMs that are
# indexed and reachable under a more specific query. So: many narrow queries,
# no `after` sent to the API, window enforced locally on message_ts.
#
# Prints one compact JSON object per unique in-window result to stdout, then a
# final summary line:
#   {"queries":N,"failed_queries":N,"candidates":N,"in_window":N,"newest_seen":"ts"}
# Exit 0 if at least one query succeeded; non-zero on config error or total failure.
set -uo pipefail

AFTER="${1:?usage: slack-search-dms <after_unix_ts>   (queries on stdin, one per line)}"
TOKEN_FILE="${SLACK_TOKEN_FILE:-$HOME/.config/obsidian-worklog/slack-token}"
CHANNEL_TYPES="${SLACK_DM_CHANNEL_TYPES:-im,mpim}"
LIMIT="${SLACK_DM_LIMIT:-100}"
MAX_QUERIES="${SLACK_DM_MAX_QUERIES:-80}"
DEFAULT_QUERY="${SLACK_DM_QUERY:-Direct messages with decisions, requests, commitments, blockers, risks, or status updates relevant to my ongoing work}"

[[ "$AFTER" =~ ^[0-9]+$ ]] || { echo "slack-search-dms: after must be a unix timestamp, got '$AFTER'" >&2; exit 2; }
[[ -r "$TOKEN_FILE" ]] || { echo "slack-search-dms: token file not readable at $TOKEN_FILE" >&2; exit 3; }
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
[[ -n "$TOKEN" ]] || { echo "slack-search-dms: empty token" >&2; exit 3; }

# --- collect queries -------------------------------------------------------
queries=()
if [[ ! -t 0 ]]; then
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    [[ -z "$line" || "$line" == \#* ]] && continue
    queries+=( "$line" )
    (( ${#queries[@]} >= MAX_QUERIES )) && break
  done
fi
# No stdin queries: fan out over a built-in topic list. A single query is relevance-ranked
# and capped, so it missed a same-day group DM; never fall back to one query.
if (( ${#queries[@]} == 0 )); then
  queries=( "$DEFAULT_QUERY" "decision" "agree" "follow up" "action item" "can you" "please" "draft" \
    "meeting" "today" "tomorrow" "this week" "risk" "blocker" "approve" "review" "models" "model review" \
    "org" "team" "reorg" "hiring" "headcount" "planning" "OKR" "priority" "escalate" "update" "thanks" \
    "sounds good" "let's" "I will" "we should" "security" "privacy" "AI" "vendor" "leadership" )
fi

RAW="$(mktemp)"; trap 'rm -f "$RAW"' EXIT
failed=0

for q in "${queries[@]}"; do
  for attempt in 1 2 3; do
    resp="$(curl -sS --max-time 45 -X POST "https://slack.com/api/assistant.search.context" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "query=$q" \
      --data-urlencode "channel_types=$CHANNEL_TYPES" \
      --data-urlencode "content_types=messages" \
      --data-urlencode "include_context_messages=true" \
      --data-urlencode "include_bots=false" \
      --data-urlencode "limit=$LIMIT" 2>/dev/null)"
    if [[ -z "$resp" ]]; then
      (( attempt == 3 )) && { echo "slack-search-dms: network error on query: ${q:0:60}" >&2; failed=$((failed+1)); }
      sleep $(( attempt * 2 )); continue
    fi
    ok="$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null)"
    if [[ "$ok" == "true" ]]; then
      printf '%s' "$resp" | jq -c --arg q "$q" \
        '.results.messages[]? | {channel_id, message_ts, author_user_id, author_name, is_author_bot, permalink, content, context_messages, matched_query:$q}' >> "$RAW"
      break
    fi
    err="$(printf '%s' "$resp" | jq -r '.error // "unparseable_response"' 2>/dev/null)"
    if [[ "$err" == "ratelimited" && $attempt -lt 3 ]]; then sleep $(( attempt * 5 )); continue; fi
    echo "slack-search-dms: slack api error '$err' on query: ${q:0:60}" >&2
    failed=$((failed+1)); break
  done
  sleep 0.3
done

if (( failed == ${#queries[@]} )); then
  echo "slack-search-dms: every query failed (${failed}/${#queries[@]})" >&2
  exit 5
fi

# --- dedupe, window-filter locally, report --------------------------------
jq -s -c --argjson after "$AFTER" --argjson nq "${#queries[@]}" --argjson nf "$failed" '
  ( . | unique_by([.channel_id, .message_ts]) )                    as $uniq
  | ( $uniq | map(.message_ts | tonumber) | max )                  as $newest
  | ( $uniq | map(select((.message_ts | tonumber) > $after)) )      as $win
  | ( $win[] | del(.matched_query) ),
    {queries:$nq, failed_queries:$nf, candidates:($uniq|length),
     in_window:($win|length), newest_seen:(($newest // 0) | tostring)}
' "$RAW"
```

The skill sets `SLACK_DM_CHANNEL_TYPES` from `include_1on1` and `include_groups` in `Sources/_dms.md`.

## 6. Allow the helpers in Claude Code

Claude Code asks for permission before it runs a command from a new path. In `/focus` mode, or with `skipAutoPermissionPrompt`, Claude Code denies these requests without a prompt. The skill then falls back to manual paste, and the DM helper does not run.

To prevent this, add the helpers to the Bash allowlist in `~/.claude/settings.json`:

```json
"permissions": {
  "allow": [
    "Bash(~/.config/obsidian-worklog/bin/slack-fetch-file:*)",
    "Bash(~/.config/obsidian-worklog/bin/slack-search-dms:*)"
  ]
}
```

You can also type `/permissions` in Claude Code and add the same two entries.

Restart Claude Code after you edit `settings.json`. Claude Code reads its settings only when a session starts.

### Codex permissions

Codex does not use `~/.claude/settings.json`.

1. Keep the vault in the writable workspace of the session.
2. Approve the helper command when Codex asks.
3. Let the active permission profile reach `slack.com`. Both helpers call the Slack API directly.
4. Restart Codex after you change its permission or MCP configuration.

Use the narrowest command and network approval that works. Full machine access is not necessary. See [SETUP-CODEX.md](SETUP-CODEX.md) for the general Codex setup.

## 7. Test the setup

Test `slack-fetch-file`. Get a file ID from the thread summary that `/worklog pull` shows. Then run:

```bash
~/.config/obsidian-worklog/bin/slack-fetch-file F0XXXXXXX | head -c 500
```

If the command prints HTML or text, the helper works.

Test the Real-time Search API for `slack-search-dms`:

```bash
TOKEN="$(tr -d '[:space:]' < ~/.config/obsidian-worklog/slack-token)"
curl -sS -X POST https://slack.com/api/assistant.search.info \
  -H "Authorization: Bearer $TOKEN" | jq .
```

If the output has `"ok": true`, the API is available. The workspace must have Slack AI Search turned on. In the Slack client, accept the one-time prompt that allows DM and group DM search.

Test `slack-search-dms` with a 3-day window:

```bash
# macOS
~/.config/obsidian-worklog/bin/slack-search-dms "$(date -v-3d +%s)"
# Linux
~/.config/obsidian-worklog/bin/slack-search-dms "$(date -d '3 days ago' +%s)"
```

The helper prints JSON result lines, then a summary line with `queries`, `failed_queries`, `candidates`, `in_window`, and `newest_seen`.

## DM sweep

The DM sweep reads your 1:1 DMs and group DMs. It runs only when `Sources/_dms.md` exists and has `enabled: true`. There is one file for the whole sweep, because the skill searches DMs and does not keep state for each conversation.

```yaml
---
type: dm-sweep
enabled: true
include_1on1: true              # search im conversations
include_groups: true            # search mpim (group DM) conversations
last_scan_ts: null              # global baseline; first run = now - first_scan_lookback_days
first_scan_lookback_days: 3
nudge_threshold_days: 5
query: ""                       # optional salience query override; empty = built-in default
max_results: 100                # pagination cap and volume-guardrail threshold
exclude_users: []               # user IDs whose 1:1 DMs are dropped from results
exclude_conversations: []       # conversation IDs (im/mpim) dropped from results
---

# Direct Messages

Notes to yourself about what this sweep is for.
```

To stop the sweep, delete the file or set `enabled: false`. To skip some people or conversations, add their IDs to `exclude_users` or `exclude_conversations`.

The skill finds new DMs in one of two ways:

1. __Slack MCP search tool (primary).__ In Claude Code this is `slack_search_public_and_private`. The skill searches with `is:dm` and no keywords, sorted by time, and reads every page. This gives a full list. It needs no token and no helper.
2. __`slack-search-dms` helper (fallback).__ The skill uses the helper only when the search tool is not available. The skill sends many narrow queries on stdin: the `query` value, the names in the current week's `people:`, and active program names. A ranked search can miss messages, so the skill records the sweep as "fan-out" in the log.

The skill does not move `last_scan_ts` after a partial sweep. A sweep is partial if a search page fails or if `failed_queries` is more than 0. The next pull then reads the same window again.

Two rules apply to all DM content:

- The skill never adds DM content to the vault without your approval. It asks you about each relevant DM at the end of the pull.
- When you approve a DM, the skill writes a general summary of the work with a permalink. It does not copy the message text.

If the window has more than `max_results` results, the skill stops and asks you what to do. It does not cut the list.

## One-thread ingest

To ingest one Slack thread without registering a source, run:

```
/worklog ingest https://<workspace>.slack.com/archives/<channel_id>/p<digits>
```

The skill reads the thread with `slack_read_thread` and writes a `Meetings/` note with the same Slack fields as a pull. A later `/worklog pull` finds that note and does not ingest the thread again. If you give the link of a reply, the skill uses the `thread_ts` in the link. See `skills/worklog/references/integrations.md` for the full rules.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `This needs a Slack MCP plugin. Install one and re-run.` | No Slack MCP server is connected. | Install a Slack MCP plugin. Then restart the host. |
| Codex stops and names a missing capability. | The Slack connector cannot do one of the four required operations. | Use a connector that has all four operations. For one thread, use `$worklog ingest <slack-permalink>`. |
| The skill asks you to paste each email body. | `slack-fetch-file` is missing, the token is missing, or Claude Code blocked the command. | Do steps 3 to 6. Check the allowlist entry. Restart Claude Code. |
| `not_visible` or `access_denied` | The token is correct, but you cannot see the file. | Join the source channel. |
| `not_authed` or `invalid_auth` | The token is wrong, expired, or revoked. | Copy the token again from __OAuth & Permissions__. Do step 4 again. |
| `DM sweep skipped: <reason>` | The search tool is not available, and the helper failed. Usually the cause is `missing_scope`, no DM search consent, or Slack AI Search is off. | Add the `search:read.*` scopes. Install the app again. Accept the consent prompt. Run the `assistant.search.info` test. |
| `DM sweep skipped: no channel types selected` | `include_1on1` and `include_groups` are both `false`. | Set one of them to `true`. |
| The DM sweep is reported as partial. | A search page or query failed. | Run `/worklog pull` again. The skill reads the same window again. |
| The pull stops and asks about volume. | A context channel has more than about 100 threads and messages, or the DM window has more than `max_results`. | Continue, use a smaller window, or skip the source. |

The rest of the pull continues when the DM sweep is skipped.

## App approval

Some workspaces require admin approval for new apps, including personal apps.

- __Personal or small workspaces:__ usually no approval is necessary.
- __Larger organizations:__ an admin or an approval bot reviews the request. `files:read` is a read-only user scope, so approval is usually fast.
- __Strict workspaces:__ follow the process of your organization.

While you wait, `/worklog pull` continues to work. The skill asks you to paste each email body.

## Token rotation and revocation

User tokens do not expire by default. You or an admin can revoke a token at any time.

- __To revoke the token yourself:__ in Slack, go to __Profile__, then __Apps__. Find your app and click __Remove app__.
- __If an admin revokes the token:__ the next pull shows `not_authed`. Install the app again and do step 4 again.

After revocation, the skill falls back to manual paste. Ingestion does not stop.

## Remove auto-fetch

To use manual paste only, run:

```bash
rm ~/.config/obsidian-worklog/slack-token
rm ~/.config/obsidian-worklog/bin/slack-fetch-file
```

The skill then asks you to paste each email body. Without the token, the DM helper also fails. The DM sweep still runs if the Slack MCP search tool is available.

## Deprecated: `slack-list-dms`

The DM sweep does not use the old `slack-list-dms` helper or the `im:read` and `mpim:read` scopes. You can remove `~/.config/obsidian-worklog/bin/slack-list-dms`.

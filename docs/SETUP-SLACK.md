# Slack Auto-Fetch Setup (optional)

The `/worklog pull` command can __automatically fetch__ email bodies from a Slack
channel when forwarded emails arrive as `.html` file attachments (which is what
Slack's email-to-channel integration does for emails larger than ~5-10KB).
Setting this up is __optional__: without it, the skill falls back to prompting
you to paste each body inline, which works fine but takes more keystrokes per
pull.

If you want auto-fetch, follow this guide once. Five minutes of setup, then
every future `/worklog pull` ingests bodies automatically.

## What you'll need

- A Slack workspace where you can install personal apps (this may require admin
  approval at your org; see [App Approval Process](#app-approval-process) below).
- About 5 minutes.

## 1. Create a personal Slack app

Go to <https://api.slack.com/apps> and click __Create New App__ → __From scratch__.

- __App Name__: `obsidian-worklog-fetcher` (or anything you like).
- __Pick a workspace__: select the workspace where your meeting-notes channel lives.

## 2. Add the `files:read` scope

In the left sidebar, go to __OAuth & Permissions__ → __Scopes__.

- Under __User Token Scopes__, click __Add an OAuth Scope__ and add `files:read`.
- That's the only scope you need. Skip __Bot Token Scopes__ entirely.

> __Why user-token (`xoxp-...`), not bot-token (`xoxb-...`)?__ User tokens
> inherit your channel access. If you're a member of a channel, the token can
> read files in it. Bot tokens require an explicit `/invite @your-bot` to each
> channel, which is extra friction with no benefit when you're the only user.

## 3. Install the app to your workspace

Still on __OAuth & Permissions__, scroll up and click __Install to Workspace__.

Slack will show a permissions confirmation page listing `files:read` and your
workspace name. Click __Allow__.

> __At workspaces with admin approval:__ if your workspace requires admin
> approval for new apps, you'll see a "Request to Install" button instead of
> direct approval. Submit the request; an admin will review and approve. The
> `files:read` scope is read-only, scoped to your own access, and one of the
> most common scopes, so approval is usually fast.

## 4. Copy the user OAuth token

After installation, scroll back up on the __OAuth & Permissions__ page. You'll
see __OAuth Tokens__ at the top with __User OAuth Token__, a long string
starting with `xoxp-`. Copy it.

## 5. Store the token

Open a terminal and run (replace `xoxp-...` with the token you copied):

```bash
mkdir -p ~/.config/obsidian-worklog
umask 077
printf '%s' 'xoxp-...' > ~/.config/obsidian-worklog/slack-token
chmod 600 ~/.config/obsidian-worklog/slack-token
```

Or, on macOS, use Keychain instead:

```bash
security add-generic-password -s obsidian-worklog -a slack-token -w 'xoxp-...'
```

If you use Keychain, you'll need to adjust the helper script in step 6 to
read from Keychain instead of the file.

## 6. Install the helper script

The script reads the token, calls Slack's `files.info` to get a download URL,
then fetches the file body with the Bearer auth header. It's ~30 lines of
plain Bash; no dependencies beyond `curl` and `jq` (both standard on macOS,
available via package manager on Linux).

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

## 7. Smoke-test the setup

Pick any file ID from the channel you registered as a worklog source. You can
find one by running `/worklog pull` once and copying a `file_id` from the
thread summary the skill prints. Then:

```bash
~/.config/obsidian-worklog/bin/slack-fetch-file F0XXXXXXX | head -c 500
```

If it prints HTML or text, the helper itself is working.

If it prints an error like `not_visible` or `access_denied`, the token is
valid but the file isn't visible to you (maybe it's in a private channel
you're not a member of). Check that you're a member of the source channel.

If it prints `not_authed` or `invalid_auth`, the token is wrong or expired.
Re-copy from the OAuth & Permissions page and rewrite step 5.

## 8. Allow Claude Code to invoke the helper

Even with the helper installed, Claude Code prompts for permission each time
it tries to run a bash command from a path it hasn't seen before. If you
operate in `/focus` mode or with `skipAutoPermissionPrompt`, those prompts
get silently denied, and the skill falls back to manual paste even though
auto-fetch is fully set up.

Add the helper path to your Bash allowlist in `~/.claude/settings.json`:

```json
"permissions": {
  "allow": [
    "Bash(~/.config/obsidian-worklog/bin/slack-fetch-file:*)"
  ]
}
```

Or, easier: type `/permissions` in Claude Code and add
`Bash(~/.config/obsidian-worklog/bin/slack-fetch-file:*)` via the UI.

Restart Claude Code after editing settings.json: settings load on session
start, not mid-session. The next `/worklog pull` will use auto-fetch
automatically.

## App Approval Process

Some Slack workspaces require admin approval before new apps can be installed,
including personal-use apps. Common scenarios:

- __Personal/small workspaces__: usually no approval needed, install is instant.
- __Larger orgs with security policies__: an "App Approval Bot" or admin review
  process intercepts the install request. `files:read` is a read-only,
  user-scoped, low-risk scope, so approval is typically fast (hours to days).
- __Compliance-heavy workspaces__: may have a stricter review (security/IT
  ticket). Follow your org's process.

If approval at your org takes a long time, the skill's manual-paste fallback
keeps `/worklog pull` working in the meantime, so you don't have to wait.

## Token rotation and revocation

User tokens don't expire by default but can be revoked at any time:

- __You revoke__: go to your Slack workspace → __Profile__ → __Apps__ → find
  `obsidian-worklog-fetcher` → __Remove app__. Token is invalidated immediately.
- __Workspace admin revokes__: same effect; you'll see `not_authed` errors on
  next pull and need to re-install + re-store the token.

The skill detects auth errors and falls back to manual paste, so a revoked
token doesn't block ingestion.

## Removing auto-fetch

If you want to go back to manual paste only:

```bash
rm ~/.config/obsidian-worklog/slack-token
rm ~/.config/obsidian-worklog/bin/slack-fetch-file
```

The skill detects the missing helper and prompts for paste on every thread.

## Optional: DM sweep setup

To let `/worklog pull` also sweep your 1:1 and group DMs, do two one-time things. The
sweep uses Slack's Real-time Search API (`assistant.search.context`) to retrieve only
DM messages relevant to your work, so it makes one search call instead of reading every
conversation.

### 1. Add search scopes to your Slack user token

In your Slack app at `api.slack.com/apps` → OAuth & Permissions → User Token Scopes, add:

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

ok="$(printf '%s' "$resp" | jq -r '.ok' 2>/dev/null)" || ok=""
if [[ "$ok" != "true" ]]; then
  err="$(printf '%s' "$resp" | jq -r '.error // "unknown_error"' 2>/dev/null || true)"
  [[ -n "$err" ]] || err="unparseable_response"
  echo "slack-search-dms: slack api error: $err" >&2
  exit 5
fi

printf '%s' "$resp" | jq -c '.results.messages[]? | {channel_id, message_ts, author_user_id, author_name, is_author_bot, permalink, content, context_messages}'
printf '%s' "$resp" | jq -c '{next_cursor: (.response_metadata.next_cursor // "")}'
```

Test it (3-day window): `~/.config/obsidian-worklog/bin/slack-search-dms "$(date -v-3d +%s)"   # macOS; Linux: date -d '3 days ago' +%s`
prints JSON result lines then a `{"next_cursor":...}` line. A non-zero exit (missing scope,
bad token, network) makes `/worklog pull` skip the DM sweep gracefully.

### 3. Opt in with `Sources/_dms.md`

The helper alone does nothing. The DM sweep only runs when this file exists in your vault
and is `enabled: true`. Unlike channel sources there is one file for the whole sweep, since
DMs are searched rather than enumerated, so there is no per-conversation state to keep:

```yaml
---
type: dm-sweep
enabled: true
include_1on1: true              # search im conversations
include_groups: true            # search mpim (group DM) conversations
last_scan_ts: null              # global baseline; first run = now - first_scan_lookback_days
first_scan_lookback_days: 3
nudge_threshold_days: 5
query: ""                       # optional salience override; empty uses the built-in
max_results: 100                # pagination cap and volume-guardrail threshold
exclude_users: []               # user IDs whose 1:1 DMs are dropped from results
exclude_conversations: []       # conversation IDs (im/mpim) dropped from results
---

# Direct Messages

Notes to yourself about what this sweep is for.
```

Delete the file, or set `enabled: false`, and `/worklog pull` stops reading DMs entirely.
Use `exclude_users` and `exclude_conversations` to carve out specific people or threads
while leaving the rest of the sweep on.

Two behaviors worth knowing before you enable it. Nothing found in a DM is ever auto-folded
the way a context-channel match is: every relevant unit goes through the end-of-pull
approval batch, and what gets written on approval is a genericized, workstream-level
summary with a permalink, not a verbatim quote. And if pagination is still returning a
cursor after `max_results` results, the pull stops and asks rather than silently
truncating.

### Deprecation: `slack-list-dms`

The earlier `slack-list-dms` enumeration helper and the `im:read` / `mpim:read` scopes are no
longer used by the DM sweep (search replaces enumeration). You can leave them in place or
remove `~/.config/obsidian-worklog/bin/slack-list-dms`; the sweep does not call it.

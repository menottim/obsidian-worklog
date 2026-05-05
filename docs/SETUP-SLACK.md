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
  approval at your org — see [App Approval Process](#app-approval-process) below).
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
> inherit your channel access — if you're a member of a channel, the token can
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
> most common scopes — approval is usually fast.

## 4. Copy the user OAuth token

After installation, scroll back up on the __OAuth & Permissions__ page. You'll
see __OAuth Tokens__ at the top with __User OAuth Token__ — a long string
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

If it prints HTML or text, you're done. The next `/worklog pull` will use
auto-fetch automatically.

If it prints an error like `not_visible` or `access_denied`, the token is
valid but the file isn't visible to you (maybe it's in a private channel
you're not a member of). Check that you're a member of the source channel.

If it prints `not_authed` or `invalid_auth`, the token is wrong or expired.
Re-copy from the OAuth & Permissions page and rewrite step 5.

## App Approval Process

Some Slack workspaces require admin approval before new apps can be installed,
including personal-use apps. Common scenarios:

- __Personal/small workspaces__: usually no approval needed, install is instant.
- __Larger orgs with security policies__: an "App Approval Bot" or admin review
  process intercepts the install request. `files:read` is a read-only,
  user-scoped, low-risk scope — approval is typically fast (hours to days).
- __Compliance-heavy workspaces__: may have a stricter review (security/IT
  ticket). Follow your org's process.

If approval at your org takes a long time, the skill's manual-paste fallback
keeps `/worklog pull` working in the meantime — you don't have to wait.

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

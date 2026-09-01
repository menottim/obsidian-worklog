# Netflix Onboarding (this fork only)

This document is specific to the Netflix-internal fork at `github.netflix.net/mminutillo/obsidian-worklog`. The public fork at `github.com/menottim/obsidian-worklog` does not include this.

If you're a Netflix engineer, this walkthrough adds the internal integrations: Slack thread fetching via Netflix's paved-path MCP, internal doc ingestion (Coda / Confluence / Google Docs), Jira ticket pull, and Whitepages/Pandora people enrichment.

## Prerequisites

- The standard worklog prerequisites (Claude Code or Codex, Obsidian, a vault); see the main [README](../README.md)
- A Netflix `@netflix.com` git identity
- `newt` on PATH (Netflix dev tooling). Install via `https://manuals.netflix.net/view/newt` if missing.

## What this gets you

| Worklog function | Without Netflix MCPs | With Netflix MCPs |
|------------------|---------------------|-------------------|
| `/worklog pull` (Slack thread ingest) | Personal Slack OAuth app + `xoxp-` token + custom Bash helper | Slack thread fetching via Core Tools MCP, no personal app needed |
| Ingesting meeting notes | Paste body inline each time | `/worklog ingest <coda-or-confluence-url>`, body fetched via Netflix Search Data |
| Creating People notes | Name only, you fill in context manually | `/worklog whois <name>`, title, manager, team auto-populated from Pandora |
| Finding past discussions | Manual Slack search | Slack RAG via Netflix Search API can surface past threads on a topic |
| Tracking Jira-tracked work | Paste ticket details inline | `/worklog jira <KEY>`, pulls status, title, owner |
| Looking up Netflix internals | Web search Manuals manually | Manuals RAG via Core Tools surfaces authoritative answers |

## Step 1: make the Core Tools profile available

Claude Code users can use the existing strict setup path below. Codex users should first
run `newt --app-type=dev-profiles join --profile=genai-core-tools`, then run
`./setup-codex.sh`; see [SETUP-CODEX.md](SETUP-CODEX.md). Restart the selected host after
the profile or MCP configuration changes.

### Claude Code: setup.sh runs `newt join` automatically (strict mode)

The Netflix-detection block in `setup.sh` runs this for you when it sees an `@netflix.com` git email:

```bash
newt --app-type=dev-profiles join --profile=genai-core-tools
```

If the join fails, `setup.sh` aborts before declaring "Setup complete!", so the script never leaves you with a partial install. If you're already joined (verified via `newt --app-type=dev-profiles resolve`), the script skips the join step.

This installs (or makes available via `/mcp` in Claude Code) the canonical Netflix-internal MCP server `core-tools`, which exposes these exact tool IDs that the worklog skill pins to:

| Tool ID | Purpose | Used by |
|---------|---------|---------|
| `mcp__core-tools__fetch-slack-thread` | Get full thread content + metadata for any Slack thread you have access to | `/worklog ingest <slack-permalink>` |
| `mcp__core-tools__netflix_search_data` | Fetch the body of an internal doc by URL (Coda, Google Docs, Confluence) | `/worklog ingest <doc-url>` |
| `mcp__core-tools__netflix_search_api` | Cross-search Slack + Manuals + Confluence + Pandora | `/worklog whois <name>` and people-resolution inside `/worklog ingest` |
| `mcp__core-tools__manuals_get_page_content` | Fetch a single Manuals page | Available; not currently pinned to a worklog command |
| `mcp__core-tools__rag-manuals-prod` / `rag-slack-prod` / `dgw_rag_generic` | RAG search variants | Available; not currently pinned |

After `setup.sh` exits 0, restart Claude Code once. The MCPs load on session start, not mid-session.

## Step 2: verify additional MCPs (recommended)

The worklog skill specifically benefits from these. Check each via `/mcp`; install via the [MCP catalog](https://genai.netflix.net/mcp-servers/all) if missing.

| MCP | Worklog function | Priority |
|-----|------------------|----------|
| __Atlassian__ (Jira + Confluence) | `/worklog jira`, ingesting Confluence pages | High |
| __NECP__ (Netflix Engineering Context Provider) | Resolving Netflix-specific terms in raw input | High |
| __Slack__ | `/worklog pull` thread reading | High (likely already installed) |
| __Jenkins__ (`netflix-ci-official`) | CI status as worklog context | Medium |
| __Atlas Metrics__ | Tracking dashboard alerts as items | Medium |
| __Spinnaker__ | Linking Programs to their Spinnaker apps | Low; skill-level usage usually fine |
| __Chronos Timeline__ | "Did the deploy happen this week?" context | Low |
| __Incident Management__ (PagerDuty + incident.io) | Tracking incident response work | Situational |

The Tier 1 MCPs (Atlassian, NECP, Slack) cover ~90% of the worklog's Netflix-specific value. Tier 2 is opt-in based on what your work actually touches.

## Step 3: identity and backup defaults

The fork's `setup.sh` detects `@netflix.com` git emails and:

- Resolves your authoritative GHE login via `gh api user --jq .login` (with `GH_HOST=github.netflix.net`); never guesses from `$(whoami)`
- Defaults backup repo to `https://github.netflix.net/<your-ghe-login>/<vault-basename>.git`, using __HTTPS, not SSH__, because port 22 to github.netflix.net is blocked on many Netflix networks (the `insteadOf` git config rewrites the URL to the `git.netflix.net` proxy at push time)
- Verifies the GHE repo exists via `gh repo view`. If it doesn't, prompts to create it via `gh repo create --private` and aborts if you decline

One-time Netflix GHE setup (you may already have this):
- Visit `go/authorizecm` to authorize Netflix Git Credential Manager
- Install Netflix-GCM on your GHE account so HTTPS pushes work without per-push auth prompts

If you ran `setup.sh` before this Netflix block existed, re-run it on a clean checkout: `git checkout skills/worklog/SKILL.md && ./setup.sh`

## Step 4: how Pandora identity flows into People notes

When `/worklog whois <name>` is invoked, the skill:

1. Announces: `Using mcp__core-tools__netflix_search_api to resolve <input> against Pandora`
2. Calls that exact tool with the input as the query
3. Filters results for Pandora source entries; surfaces a numbered list if multiple, asks you to pick if disambiguation is needed, errors out if zero matches
4. Updates frontmatter of `People/<Full Name>.md` with email, title, team, manager (wiki-linked), pandora_id, status
5. Body content is preserved on merge (your accumulated context bullets are never overwritten)

The "announce-which-tool" pattern applies to every Netflix command. You'll always see which MCP tool was called on which input; there's no silent enrichment.

## Step 5: ingesting Netflix-internal documents

`/worklog ingest <url>` accepts:

- Coda docs (`https://coda.io/d/...` or `https://coda.netflix.net/d/...`)
- Confluence pages (`https://confluence.netflix.com/...` or `netflix.atlassian.net/wiki/...`)
- Google Docs (`https://docs.google.com/document/d/...`)
- Slack thread permalinks (`https://*.slack.com/archives/.../p...`)

The skill routes by URL pattern (deterministic, no fallback chains):
- Slack permalinks -> `mcp__core-tools__fetch-slack-thread` -> treat as Meeting note
- Coda / Confluence (confluence.netflix.com) / Google Docs -> `mcp__core-tools__netflix_search_data`
- `netflix.atlassian.net/wiki/` Confluence pages -> `mcp__plugin_atlassian_atlassian__getConfluencePage`
- Anything else -> error with a hint to paste body inline; no implicit fallback to a different MCP

The fetched body flows through the same "raw input" extraction logic the skill already uses for pasted content: extract items, link people/programs, add to current week, create a `Meetings/` note if it's meeting-shaped.

## Step 6: Slack auto-fetch helper (optional)

The public skill's [`SETUP-SLACK.md`](SETUP-SLACK.md) walkthrough sets up a personal Slack app with `files:read` scope to fetch email-attachment bodies. At Netflix:

- This still works. `files:read` is read-only and user-scoped, and Slack admins typically approve it quickly
- Admin approval at Netflix may take a few business days. The manual-paste fallback keeps the feature working in the meantime
- Alternative: use `/worklog ingest <slack-permalink>` to pull individual threads via Core Tools MCP instead of running a periodic `/worklog pull`. This avoids the personal-app path entirely for one-off ingestions

If you want full `/worklog pull` automation, the personal-app path is still the cleanest. The Core Tools MCP doesn't (currently) expose file-body extraction for email attachments.

## Troubleshooting

__`/mcp` shows no core-tools server after `newt join`__
- Restart Claude Code (MCP servers load on session start)
- Verify membership: `newt --app-type=dev-profiles list` should show `genai-core-tools`

__`/worklog whois` returns no match__
- Check spelling; Pandora is case-insensitive but punctuation-sensitive
- For ambiguous first names, try `firstname.lastname@netflix.com` instead

__`/worklog ingest` fails with "no access" on a Confluence URL__
- You may need to be added to the space; check with the page owner
- Verify by opening the URL in a browser first. If you can read it there, Netflix Search Data should also reach it

__`/worklog pull` falls back to manual paste even after Slack setup__
- Likely the Bash allowlist issue documented in `SETUP-SLACK.md` step 8
- In `/focus` mode the helper-script invocation is silently denied; add `Bash(~/.config/obsidian-worklog/bin/slack-fetch-file:*)` to your `~/.claude/settings.json` allowlist

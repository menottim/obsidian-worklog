# Netflix Onboarding (this fork only)

This document is specific to the Netflix-internal fork at `github.netflix.net/mminutillo/obsidian-worklog`. The public fork at `github.com/menottim/obsidian-worklog` does not include this.

If you're a Netflix engineer, this walkthrough adds the integrations that make worklog feel native: Slack thread fetching via Netflix's paved-path MCP, internal doc ingestion (Coda / Confluence / Google Docs), Jira ticket pull, and Whitepages/Pandora people enrichment.

## Prerequisites

- The standard worklog prerequisites (Claude Code, Obsidian, a vault) - see the main [README](../README.md)
- A Netflix `@netflix.com` git identity
- `newt` on PATH (Netflix dev tooling). Install via `https://manuals.netflix.net/view/newt` if missing.

## What this gets you

| Worklog function | Without Netflix MCPs | With Netflix MCPs |
|------------------|---------------------|-------------------|
| `/worklog pull` (Slack thread ingest) | Personal Slack OAuth app + `xoxp-` token + custom Bash helper | Slack thread fetching via Core Tools MCP - no personal app needed |
| Ingesting meeting notes | Paste body inline each time | `/worklog ingest <coda-or-confluence-url>` - body fetched via Netflix Search Data |
| Creating People notes | Name only, you fill in context manually | `/worklog whois <name>` - title, manager, team auto-populated from Pandora |
| Finding past discussions | Manual Slack search | Slack RAG via Netflix Search API can surface past threads on a topic |
| Tracking Jira-tracked work | Paste ticket details inline | `/worklog jira <KEY>` - pulls status, title, owner |
| Looking up Netflix internals | Web search Manuals manually | Manuals RAG via Core Tools surfaces authoritative answers |

## Step 1: join the `genai-core-tools` profile

One command opts you into Netflix's paved-path MCP bundle:

```bash
newt --app-type=dev-profiles join --profile=genai-core-tools
```

This installs (or makes available via `/mcp` in Claude Code) the canonical Netflix-internal MCPs:

- __Netflix Search API__ - cross-search Slack + Manuals + Confluence
- __Netflix Search Data__ - fetch the full body of any internal doc by URL
- __Manuals RAG__ - retrieval-augmented search of `manuals.netflix.net`
- __Slack RAG__ - retrieval-augmented search of help channels and discussions
- __Fetch Slack Thread__ - get full thread content + metadata for any Slack thread you have access to

After joining, restart Claude Code. Verify with `/mcp` - you should see the core-tools server listed.

## Step 2: verify additional MCPs (recommended)

The worklog skill specifically benefits from these. Check each via `/mcp`; install via the [MCP catalog](https://genai.netflix.net/mcp-servers/all) if missing.

| MCP | Worklog function | Priority |
|-----|------------------|----------|
| __Atlassian__ (Jira + Confluence) | `/worklog jira`, ingesting Confluence pages | High |
| __NECP__ (Netflix Engineering Context Provider) | Resolving Netflix-specific terms in raw input | High |
| __Slack__ | `/worklog pull` thread reading | High (likely already installed) |
| __Jenkins__ (`netflix-ci-official`) | CI status as worklog context | Medium |
| __Atlas Metrics__ | Tracking dashboard alerts as items | Medium |
| __Spinnaker__ | Linking Programs to their Spinnaker apps | Low - skill-level usage usually fine |
| __Chronos Timeline__ | "Did the deploy happen this week?" context | Low |
| __Incident Management__ (PagerDuty + incident.io) | Tracking incident response work | Situational |

The Tier 1 MCPs (Atlassian, NECP, Slack) cover ~90% of the worklog's Netflix-specific value. Tier 2 is opt-in based on what your work actually touches.

## Step 3: identity and backup defaults

The fork's `setup.sh` detects `@netflix.com` git emails and offers Netflix-appropriate defaults:

- Backup repo default: `git@github.netflix.net:<your-username>/<vault-name>.git` (instead of GitHub.com)
- Reminder about Netflix Git Credential Manager: visit `go/authorizecm` and install the Netflix-GCM app on your GHE account (one-time)

If you ran `setup.sh` before this Netflix block existed, re-run it on a clean checkout to pick up the new prompts.

## Step 4: how Pandora identity flows into People notes

When `/worklog whois <name>` is invoked, the skill:

1. Resolves the name via `netflix_search_api` against Pandora (the authoritative org directory that powers Whitepages)
2. Pulls: full name, title, manager (resolved to a wiki-link), team, manager-chain to L-level
3. Creates or enriches `People/<Full Name>.md` with this metadata in the frontmatter
4. Adds a context bullet noting when the person first appeared in your worklog

Disambiguation (multiple matches) prompts you to pick. See [NETFLIX-COMMANDS.md](NETFLIX-COMMANDS.md) for details.

## Step 5: ingesting Netflix-internal documents

`/worklog ingest <url>` accepts:

- Coda docs (`https://coda.io/d/...` or `https://coda.netflix.net/d/...`)
- Confluence pages (`https://confluence.netflix.com/...` or `netflix.atlassian.net/wiki/...`)
- Google Docs (`https://docs.google.com/document/d/...`)
- Slack thread permalinks (`https://*.slack.com/archives/.../p...`)

The skill routes by URL pattern:
- Slack permalinks -> `Fetch Slack Thread` (Core Tools) -> treat as Meeting note
- Coda / Confluence / Google Docs -> Netflix Search Data -> treat as raw meeting notes
- Anything else -> error with a hint to paste body inline

The fetched body flows through the same "raw input" extraction logic the skill already uses for pasted content: extract items, link people/programs, add to current week, create a `Meetings/` note if it's meeting-shaped.

## Step 6: Slack auto-fetch helper (optional)

The public skill's [`SETUP-SLACK.md`](SETUP-SLACK.md) walkthrough sets up a personal Slack app with `files:read` scope to fetch email-attachment bodies. At Netflix:

- This still works - `files:read` is read-only and user-scoped, and Slack admins typically approve it quickly
- Admin approval at Netflix may take a few business days - the manual-paste fallback keeps the feature working in the meantime
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
- Verify by opening the URL in a browser first - if you can read it there, Netflix Search Data should also reach it

__`/worklog pull` falls back to manual paste even after Slack setup__
- Likely the Bash allowlist issue documented in `SETUP-SLACK.md` step 8
- In `/focus` mode the helper-script invocation is silently denied; add `Bash(~/.config/obsidian-worklog/bin/slack-fetch-file:*)` to your `~/.claude/settings.json` allowlist

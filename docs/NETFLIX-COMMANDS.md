# Netflix-specific worklog commands

These commands exist only in the Netflix fork (`github.netflix.net/mminutillo/obsidian-worklog`). They depend on Netflix-internal MCPs - see [SETUP-NETFLIX.md](SETUP-NETFLIX.md) for installation.

## `/worklog ingest <url>`

Fetches the body of a Netflix-internal document and processes it as raw input to the current week.

__Accepts:__
- Coda: `https://coda.io/d/...` or `https://coda.netflix.net/d/...`
- Confluence: `https://confluence.netflix.com/...` or `https://netflix.atlassian.net/wiki/...`
- Google Docs: `https://docs.google.com/document/d/...`
- Slack thread permalink: `https://*.slack.com/archives/.../p...`

__Routing (pinned tool IDs, no fallbacks):__
| URL pattern | Exact MCP tool ID |
|-------------|---------------------|
| `*.slack.com/archives/.../p*` | `mcp__core-tools__fetch-slack-thread` |
| `coda.io`, `coda.netflix.net` | `mcp__core-tools__netflix_search_data` |
| `confluence.netflix.com` | `mcp__core-tools__netflix_search_data` |
| `netflix.atlassian.net/wiki/` | `mcp__plugin_atlassian_atlassian__getConfluencePage` |
| `docs.google.com/document/` | `mcp__core-tools__netflix_search_data` |

Before each call, the skill announces `Using <tool-id> to fetch <url>` so you can see which path was taken.

__Behavior:__
1. Routes by URL pattern, fetches the body
2. If the doc is meeting-shaped (has a date in title, attendee list, action items section), creates a `Meetings/YYYY-MM-DD-<slug>.md` note
3. Extracts action items, decisions, and follow-ups
4. Wiki-links all people and programs mentioned (creating stubs for new ones)
5. Adds extracted items to the current week file under the right subgroup

__Errors:__
- Unsupported URL pattern: prompts you to paste the body inline instead
- No access: surface the access error verbatim and link to the URL so you can request access
- Empty doc / no extractable content: report what was fetched and ask if you want to proceed anyway

__Example:__
```
/worklog ingest https://confluence.netflix.com/display/SECURITY/2026-05-12+Migration+Sync
```
Pulls the Confluence page, extracts the action items, links attendees as People, creates `Meetings/2026-05-12-migration-sync.md`, adds the items to the current week.

## `/worklog whois <name-or-email>`

Resolves a person via Pandora (Netflix's identity directory) and creates or enriches their People/ note with org metadata.

__Accepts:__
- Full name: `Jane Smith`
- Partial name: `Jane S` (prompts for disambiguation if multiple matches)
- Email: `jane.smith@netflix.com`
- Pandora username: `jsmith`

__Behavior:__
1. Announces: `Using mcp__core-tools__netflix_search_api to resolve <input> against Pandora`
2. Invokes that exact tool with query=`<input>`; filters results for Pandora source entries
3. If multiple matches, surfaces a numbered list with title and team for each, prompts you to pick
4. Creates or updates `People/<Full Name>.md` with frontmatter:
   ```yaml
   email: firstname.lastname@netflix.com
   title: Senior Software Engineer
   team: Platform Infrastructure
   manager: "[[Manager Name]]"
   manager_chain: ["[[L1 Manager]]", "[[L2 Manager]]"]
   pandora_id: jsmith
   ```
4. If a People note already exists, merge: update frontmatter, preserve all body content (your accumulated context bullets)
5. Wiki-link the manager - creates a stub `People/<Manager Name>.md` if missing
6. Append a context bullet: `- _[YYYY-MM-DD]_ Org metadata refreshed from Pandora`

__Errors:__
- No match: "No Pandora match for '<input>'. Check spelling or try `firstname.lastname@netflix.com`."
- Stale identity (person no longer at Netflix): mark frontmatter `status: former` and add bullet noting end date if available

__Example:__
```
/worklog whois Sarah Chen
```
Pulls Sarah's title, team, and manager. Updates `People/Sarah Chen.md`. If her manager `Alex Park` doesn't have a note, creates a stub `People/Alex Park.md` wiki-linked from Sarah's `manager:` field.

## `/worklog jira <ticket-key>`

Pulls a Jira issue's current state and adds it as a worklog item under the appropriate subgroup.

__Accepts:__
- Ticket key: `WISSE-123`, `SIDE-456`, `INFRASEC-789`, etc.
- Full URL: `https://netflix.atlassian.net/browse/WISSE-123`

__Behavior:__
1. Announces: `Using mcp__plugin_atlassian_atlassian__getJiraIssue to pull <KEY>`
2. Invokes that exact tool - reads title, status, assignee, priority, labels, parent/epic link
3. Determines worklog priority deterministically:
   - Command flag `-p0` / `-p1` / `-p2` always wins if present
   - Otherwise: Jira priority `Highest` -> __P0__, `High` -> __P1__, anything else -> __P2__
   (The earlier "In Progress with deadline this week -> P0" rule was removed for determinism. Use `-p0` explicitly if you want that override.)
3. Picks subgroup by epic label, or by Jira project if no epic
4. Adds to current week with the standard worklog item format:
   ```markdown
   - __P1__ ⏳ In Progress - [WISSE-123](https://netflix.atlassian.net/browse/WISSE-123): Migrate legacy auth flow
     - _[YYYY-MM-DD]_ Pulled from Jira: assignee `jsmith`, sprint `2026-W20`
   ```
5. If the assignee is on your team / a known person in `People/`, wiki-link them
6. If the epic is in `Programs/`, wiki-link it; otherwise create a stub

__Errors:__
- No access to ticket: surface the error and the URL so you can request access
- Closed/resolved ticket: ask if you want to add it as `✅ Done` (useful for "this got resolved this week, log it") or skip

__Example:__
```
/worklog jira WISSE-1234
```
Pulls WISSE-1234, adds it under the right subgroup as a P1 In-Progress item with the title and ticket link.

```
/worklog jira WISSE-1234 -p0
```
Same but forces P0 priority regardless of Jira priority.

## Interaction with existing commands

The Netflix commands are __additive__ - they don't change existing behavior:

- `/worklog pull` works the same way (paved-path Slack MCP if available, otherwise the personal-app fallback)
- `/worklog summary` / `viz` / `rollup` / etc. operate on whatever's in the vault, regardless of how items got there
- The Knowledge Graph (People, Programs, Teams) is populated the same way by all three new commands - they just hydrate it from authoritative Netflix sources instead of relying on you to type everything in

## When NOT to use these

- `/worklog ingest` is for one-off doc fetches. For ongoing Slack-channel monitoring, `/worklog pull` is still the right tool.
- `/worklog whois` is for people you'll work with repeatedly. For someone mentioned once in a meeting, the existing wiki-link-as-stub flow is lighter-weight.
- `/worklog jira` is for tickets that need to surface in your weekly view. Don't bulk-import a whole project backlog - that's noise.

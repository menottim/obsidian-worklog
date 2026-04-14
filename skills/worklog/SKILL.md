---
name: worklog
description: >
  Manage __USER_NAME__'s personal worklog stored in Obsidian. Use this skill whenever the user says
  "worklog", "weekly rollover", "what's on my plate", "my priorities", "add to my worklog",
  "tidy my worklog", "what am I working on", "summarize my week", "monthly summary",
  "quarterly summary", "what did I accomplish", "audit my vault", "vault health check",
  "visualize my work", "worklog charts", or anything about managing weekly work priorities.
  Also trigger when the user asks about P0/P1/P2 items, wants a status update for Slack,
  or asks about priority drift, trends, or time allocation.
---

# Worklog Manager

You help __USER_NAME__ manage a personal worklog stored as markdown files in an Obsidian vault.
The worklog uses one file per week, a persistent backlog, and cross-linked People and
Program notes that build a knowledge graph over time. You read and write files directly.

## Vault Layout

```
__VAULT_PATH__/
  Worklogs/
    YYYY-WNN.md          # Current week (one file per week, YYYY-[W]WW.md)
    Backlog.md           # Persistent backlog (not per-week)
  People/
    Sarah Chen.md        # One note per person
    Marcus Williams.md
    ...
  Programs/
    Platform Migration.md  # One note per program/initiative
    Cloud Security.md
    ...
  Archive/
    YYYY-WMM.md          # Completed weeks
    ...
  Summaries/
    YYYY-WNN.md          # Weekly summary
    YYYY-Month.md        # Monthly summary
    YYYY-QN.md           # Quarterly summary
  Reports/
    YYYY-Month-viz.html  # D3 visualization (open in browser)
  Templates/
    Weekly.md            # Templater template for new weeks
```

The vault is backed up to `__BACKUP_REPO_URL__` (private).

## Finding the Current Week

Calculate the ISO week number from today's date. The current week file is at:
`__VAULT_PATH__/Worklogs/YYYY-[W]WW.md`

If no file exists for the current week, create one during rollover or review.

Other key paths:
- Backlog: `__VAULT_PATH__/Worklogs/Backlog.md`
- Archive: `__VAULT_PATH__/Archive/YYYY-[W]WW.md`
- Summaries: `__VAULT_PATH__/Summaries/<period>.md`
- Reports: `__VAULT_PATH__/Reports/<period>-viz.html`
- People: `__VAULT_PATH__/People/<Name>.md`
- Programs: `__VAULT_PATH__/Programs/<Name>.md`

## Weekly File Structure

Each weekly file has YAML frontmatter and a body organized into thematic subgroups:

```markdown
---
type: worklog
week: 2026-W16
date-start: 2026-04-13
date-end: 2026-04-17
status: active
prev: "[[2026-W15]]"
programs:
  - "[[Cloud Security]]"
  - "[[Platform Migration]]"
  - "[[Backend EM Hiring]]"
people:
  - "[[Sarah Chen]]"
  - "[[Priya Patel]]"
tags:
  - hiring
  - strategy
  - people-management
item-count: 5
done-count: 1
---

# Week of Apr 13, 2026

**[[Cloud Security]] Strategy**

- **P0** ⏳ In Progress - [[Platform Migration]] leadership transition
  - Pinging [[Lisa Park]] and [[Priya Patel|Priya]] today

**Hiring & People**

- **P0** ⏳ In Progress - Work with [[Sarah Chen]] on [[Dev Sharma]] leave

**Done**

- **P0** ✅ Done - Book travel for team offsite
```

Key rules:
- `#` for the week title only
- Bold text (not headings) for subgroups, with blank lines around each
- 3-4 thematic subgroups per week, adapted to that week's content
- Items ordered P0 first, then P1, then P2 within each subgroup
- Done items in a **Done** subgroup at the bottom
- All people and programs wiki-linked on first mention

## Item Format

- Top-level: `- **P0** ⏳ In Progress - <title>`
- Sub-items: `  - <text>`
- Sub-sub-items: `    - <text>`
- Priorities: `**P0**`, `**P1**`, `**P2**`
- Status markers:
  - Done: `✅ Done`
  - In Progress: `⏳ In Progress`
  - Ongoing (recurring): `🔁 Ongoing`
  - Not started (new): `⏳ In Progress` (default)

**Dating context and updates:** Every sub-item that records a context update, status
change, or action taken must include the date it happened. Use `(Mon D)` format at the
end of the sub-item. This enables progress rollups over time.

Examples:
```
- **P0** ⏳ In Progress - 5 interviews for [[Backend EM Hiring]] and [[Platform EM Hiring]]
  - ✅ Sent out prep notes for all interviewers (Apr 13)
  - Completed 3 of 5 interviews (Apr 15)
```

If the user doesn't provide a date, use today's date. If the update is from a Slack
conversation, use the date from the message timestamps.

In conversation (not files), use underscores for bold/italic (`__bold__` not `**bold**`).

## Cross-Linking

The vault uses `[[wiki-links]]` to connect weekly notes, people, and programs. This
is what makes the Obsidian graph view useful - click any person to see every week
they appear in via backlinks.

**When writing or updating ANY file in the vault (worklogs, people, programs, archive):**
1. Glob `People/*.md` and `Programs/*.md` to get the current list of known entities
2. Wrap recognized names and programs in `[[wiki-links]]` everywhere they appear -
   not just in the current week, but in any file being touched
3. Only link on first mention within an item (don't re-link in sub-items)
4. Use aliased links for case variants: `[[Cloud Security|cloud security]]`, `[[Q2 Review|Q2 review]]`
5. Use aliased links for partial names: `[[Marcus Williams|Marcus]]`, `[[Auth Redesign|auth redesign]]`
6. Section headings that reference a program should also be linked:
   `## [[Team Priorities Review]] (March 2026)` not `## Team Priorities Review (March 2026)`
7. In people/program notes, link other people and programs mentioned in the body -
   these cross-links are what make the graph useful

**When a new person or program appears:**
- Create a stub note in `People/` or `Programs/` with frontmatter and a Context
  section with whatever is known
- When creating people from Slack @ mentions, use `slack_search_users` to resolve
  full names and titles (if available; otherwise ask the user for the full name)
- This keeps the graph growing naturally as the worklog evolves

**Linking discipline is critical.** Every unlinked mention is a missing edge in the
graph. When in doubt, link it. The graph's value comes from density of connections.

**People note structure:**
```markdown
---
type: person
---
# Name
## Context
- Role/relationship context
- What you're working on together
```

**Program note structure:**
```markdown
---
type: program
---
# Program Name
## Context
- What it is, current status
- Key people involved (as wiki-links)
```

People and program notes accumulate context over time. When updating worklog items,
also append substantive new context to relevant people/program notes (new roles,
decisions, status changes - not every minor mention).

## Frontmatter Auto-generation

Every time you write or update a weekly file (during review, rollover, add, tidy,
or summary), regenerate the enriched frontmatter fields from the file body. These
fields are computed, never manually edited.

**Field extraction rules:**

1. `programs`: Glob `Programs/*.md` to get known program names. Scan the file body
   for `[[wiki-links]]` matching those names (including aliased links like
   `[[Cloud Security|cloud security]]`). Deduplicate and list as YAML array.

2. `people`: Glob `People/*.md` to get known person names. Scan the file body for
   `[[wiki-links]]` matching those names (including aliased links like
   `[[Priya Patel|Priya]]`). Deduplicate and list as YAML array.

3. `tags`: Extract from bold subgroup headings in the body. For each `**<heading>**`
   line (excluding "Done"), first strip any wiki-link syntax (e.g., `**[[Cloud Security]]
   Strategy**` becomes `Cloud Security Strategy`), then split on ` & ` and spaces, lowercase,
   and hyphenate multi-word segments. Examples:
   - "Hiring & People" -> `hiring`, `people-management`
   - "[[Cloud Security]] Strategy" -> `cloud-security`, `strategy`
   - "Platform Programs" -> `platform-programs`

4. `item-count`: Count lines matching the regex `^- \*\*P[012]\*\*`

5. `done-count`: Count lines matching the regex `^- \*\*P[012]\*\* ✅ Done`

**When to regenerate:** After file writes that structurally change the body - adding
or removing items, changing priorities, moving items between subgroups, or completing
items. Skip regeneration for minor edits like adding a sub-item to an existing item
or updating a date annotation, since those don't change `programs`, `people`, `tags`,
`item-count`, or `done-count`. When in doubt, regenerate - it's cheap, just avoid
doing it on every single sub-item addition in a batch.

**Summary file frontmatter:** Summary files already have `type`, `period`,
`date-start`, `date-end`, `weeks`, `status`. Add `programs`, `people`, and `tags`
arrays using the same extraction rules. Summary files do not need `item-count` or
`done-count` (their structure differs from weekly files).

## Commands

### `/worklog` or `/worklog status`

Read the current week file and backlog, show a summary of active work:
1. List all items NOT `Done` from the current week
2. List all `In Progress` items from the Backlog
3. Group by priority (P0 first, then P1, then P2)
4. Present in a clean markdown table or list

### `/worklog review`

Monday morning workflow. Combines status review, updates, adds, and file updates
into a single pass. Minimizes back-and-forth.

**Important:** This command updates the CURRENT week file in place. It does NOT
create a new week file or archive anything. Use `/worklog rollover` to start a
new week. If it's Monday and a new ISO week has started but no new file exists,
ask the user if they want to rollover first.

**Phase 1: Review existing items**

Walk through each active item one by one. Show the item number, total count,
priority, and title (e.g. "3/10 - P0: Item title"). Keep prompts short.

The user responds with quick updates like "done", "still working on it", "pinged X".
If they give updates for multiple items in one response, apply all and skip ahead.

**Phase 2: Collect new items**

Ask for new items. The user gives them in a batch or one by one. For each:
- Check for merges with existing items, flag overlaps
- Suggest sub-item relationships between related items
- Ask "next add?" to keep moving

**Phase 3: Write the updated file**

After all updates and adds are collected:

1. Update the current week file with all changes (status updates, new items,
   reorganized subgroups, wiki-links)
2. Update `Worklogs/Backlog.md` if any backlog changes were noted
3. Create stub notes for any new people or programs mentioned
4. Update existing people/program notes with substantive new context
5. Regenerate enriched frontmatter

Tell the user the files are updated - visible in Obsidian immediately.

### Processing raw input (meeting notes, Slack messages, transcripts)

When the user pastes raw content (meeting notes, Slack threads, transcripts) and
asks to add it to the worklog, follow this pattern:

1. Read the current week file first
2. Extract actionable items from the raw input:
   - Action items and decisions become worklog items or sub-items
   - People mentioned become wiki-linked (create stubs if new)
   - Programs mentioned become wiki-linked
3. Check for overlaps with existing items - prefer adding sub-items to existing
   items over creating duplicates (e.g., if a meeting discussed an ongoing hiring
   effort, add context as sub-items under the existing hiring item)
4. For each new top-level item, assign a priority based on urgency/importance
   cues in the raw content. Default to P1 if unclear.
5. Add dated annotations using the date from the raw content (Slack timestamps,
   meeting date), not today's date
6. Update the current week file using the Edit tool
7. Update relevant people/program notes with substantive new context
8. Regenerate enriched frontmatter

### `/worklog rollover`

Quick rollover without item-by-item review:
1. Read the current week file
2. Calculate the next Monday's date and ISO week
3. Collect all items NOT `Done`
4. Check Backlog for items to surface
5. Create new week file with subgroups and wiki-links
6. Move current week to Archive with summary

Then ask if the user wants to add any new items.

### `/worklog add <priority> <title>`

Add a new item to the current week file. Check for overlaps with existing items
and flag potential merges. Use the Edit tool to insert into the appropriate subgroup
(or create a new subgroup if needed). Wiki-link any people or programs. Create stub
notes for new entities.

### `/worklog tidy`

Read the current week file and suggest cleanup:
1. Move Done items to a Done subgroup at the bottom
2. Flag Backlog items `In Progress` for 2+ weeks without notes
3. Flag duplicates between weekly file and backlog
4. Suggest items ready to archive
5. Suggest subgroup reorganization if themes shifted

Present as a checklist. Apply approved changes directly.

### `/worklog audit`

Scan the vault for quality issues and present a fix-it checklist. No arguments.

**Checks:**

1. **Stale people**: Notes in `People/` not mentioned (via wiki-link) in any weekly
   file dated within the last 4 weeks. Excludes people who appear in the Backlog.
   Method: Glob `People/*.md`, then for each person Grep across the 4 most recent
   weekly files (active + archive) for their wiki-link.

2. **Orphan programs**: Notes in `Programs/` with no wiki-link from any file in
   `Worklogs/` or `Archive/` dated within the last 4 weeks. Same method as stale
   people but for `Programs/*.md`.

3. **Stuck items**: Items in the current active week that have been carried forward
   from previous weeks without recent progress. To detect: for each "In Progress"
   item in the active week, search the archive files' rollover notes (the parenthetical
   list after "rolled forward to") for matching titles. If an item title appears in
   2+ consecutive archives' rollover lists AND has no `(Mon D)` sub-item annotation
   in the active week dated within the last 2 weeks, flag it as stuck. This works
   with the archive summary format since rolled-forward items are listed by title.

4. **Missing links**: Unlinked mentions of known people or programs in weekly files.
   Glob `People/*.md` and `Programs/*.md` to get entity names. For each weekly file,
   scan body text for name strings that are NOT wrapped in `[[wiki-links]]`. Report
   the file, line, and suggested link.

5. **Empty stubs**: People or Program notes where the Context section has no bullet
   points (only the `## Context` heading exists, or is missing entirely).

6. **Frontmatter gaps**: Weekly or archive files missing any of: `programs`, `people`,
   `tags`, `item-count`, `done-count`.

**Output:** Present findings grouped by check type in conversation. Each finding
includes the file path and a suggested action. Example:

```
Vault audit results:

Stale people (not mentioned in 4+ weeks):
- People/Jordan Lee.md - last seen in W13
  Suggested: archive, update context, or remove if no longer relevant

Stuck items (3+ weeks without update):
- "Figure out Q2 plans across Cloud Security" - P0 since W14, last dated sub-item Apr 13
  Suggested: add a status update or reprioritize

Missing links:
- Worklogs/2026-W16.md:23 "Tom" -> [[Tom Rivera|Tom]]

Frontmatter gaps:
- Archive/2026-W11.md: missing programs, people, tags, item-count, done-count
```

User picks which fixes to apply. Apply approved fixes directly using Edit/Write tools.
For frontmatter gaps, regenerate using the Frontmatter Auto-generation rules.

### `/worklog search <term>`

Search across Worklogs/, Archive/, People/, and Programs/ for items matching the
term. Use Grep to search all `.md` files. Show matches with their week/file,
priority, and status.

### `/worklog share`

Generate a concise status summary for Slack. Copy to clipboard via `pbcopy`:

```
This week (Apr 13):
P0s: Q2 cloud security plans, team charter draft, EM interviews, ...
P1s: Backend hiring follow-up, platform enablers kickoff, ...
Done: Team offsite travel booked
```

Brief titles only, no sub-notes, no wiki-link syntax, grouped by priority.

### `/worklog summary [period]`

Generate an impact-oriented summary for reporting up. Reads weekly files in the
specified date range, synthesizes completed work into outcomes, and outputs both
a vault file and a clipboard version.

**Syntax:**

```
/worklog summary              # current week so far
/worklog summary week         # current week so far (explicit)
/worklog summary month        # current calendar month
/worklog summary quarter      # current quarter (Q1=Jan-Mar, Q2=Apr-Jun, etc.)
/worklog summary W14          # specific ISO week (assumes current year)
/worklog summary March        # specific month (full name or 3-letter abbreviation)
/worklog summary Q1           # specific quarter
```

Arguments are case-insensitive.

**Data collection:**

1. Parse the argument to determine start and end dates for the period
2. Find all weekly files in `Worklogs/` and `Archive/` whose `date-start` falls
   within the range (read frontmatter to check)
3. From archived files: extract completed items from the bullet list
4. From the active week: extract items marked `✅ Done` plus notable in-progress
   milestones (items with dated sub-items showing meaningful progress)
5. Collect all wiki-linked people and programs mentioned

**Synthesis guidelines:**

- Frame completed items as outcomes ("Shipped cloud security consolidation plan") not
  tasks ("Finished writing the plan")
- Group related items into single outcome bullets where they tell a coherent story
- Elevate decisions and direction changes into Themes & Decisions
- Target counts: 3-5 bullets for a week, 5-8 for a month, 10-15 for a quarter
- In Flight should only include items that matter at the reporting level

**Output 1 - Vault file:**

Create the `Summaries/` directory if it doesn't exist. Save to:
- Week: `Summaries/2026-W16.md`
- Month: `Summaries/2026-April.md`
- Quarter: `Summaries/2026-Q2.md`

Structure:

```markdown
---
type: summary
period: 2026-April
date-start: 2026-04-01
date-end: 2026-04-30
weeks: ["2026-W14", "2026-W15", "2026-W16"]
status: final
programs:
  - "[[Cloud Security]]"
  - "[[Platform Migration]]"
people:
  - "[[Sarah Chen]]"
  - "[[Priya Patel]]"
tags:
  - hiring
  - strategy
---

# April 2026 Summary

## Key Outcomes
- Significant completions framed as outcomes, wiki-linked to [[people]] and [[programs]]
- Ordered by impact, not chronology

## In Flight
- Major items still in progress at period end, with current state

## Themes & Decisions
- Notable decisions, direction changes, or cross-cutting patterns

## Priority Drift
- "Item title" has been P0 for N consecutive weeks (W14-W16)
- P0 count grew from X (first week) to Y (last week)
- New P0s this period: item, item
- Dropped from P0: item (or "none")
- Items promoted/demoted: "item" moved P2 -> P1 in WNN

## Trends
- Category: appeared in N/M weeks, X% of items - heaviest/growing/shrinking
- Programs touched: N unique across period
- People engaged: N unique across period
- Completion rate: N items completed, M rolled forward (X% completion)

## Coverage
Sourced from [[2026-W14]], [[2026-W15]], [[2026-W16]]
```

**Priority Drift** (monthly and quarterly summaries only, omit for weekly):

For each week in the range, extract P0 items by title (text after `- **P0** <status> - `).
Match the same item across weeks by checking if titles share 80%+ of their words.
Report: longest-running P0s, P0 count change over the period, new/dropped P0s, and
any items that changed priority level.

**Trends** (monthly and quarterly summaries only, omit for weekly):

Using enriched frontmatter and body parsing:
1. Category distribution: count items per thematic subgroup across weeks, compute %
2. Program frequency: which programs appeared in how many weeks
3. People engagement: count of unique people across the period
4. Completion rate: total done vs. total rolled forward
5. Growth/shrink: flag categories growing or shrinking in item count

Wiki-link all people and programs per the cross-linking rules. Create stub notes
for any new entities.

**Output 2 - Clipboard:**

After writing the vault file, copy a condensed plain-text version via `pbcopy`.
No wiki-link syntax, no frontmatter:

```
April 2026 Summary:

Key outcomes:
- Outcome one
- Outcome two

In flight:
- Active item with current state

Themes: Brief sentence on patterns/decisions

Priority drift: P0 count grew X -> Y. Longest-running P0: item (N weeks).

Trends: Heaviest category: X (N%). M programs, N people engaged. X% completion rate.
```

**Edge cases:**

- If no weeks exist in the range, say so rather than producing empty output
- If the active week is partially complete, note "as of <today's date>"
- For overlapping periods, include a week if its `date-start` falls within the range
- If a vault file already exists for the period, tell the user it exists and ask
  whether to overwrite or skip. If overwriting, proceed normally.

### `/worklog viz [period]`

Generate standalone HTML files with D3.js charts for visual analysis. Period
parsing uses the same logic as `/worklog summary`.

**Syntax:**

```
/worklog viz month        # current calendar month
/worklog viz quarter      # current quarter
/worklog viz W11-W16      # custom week range
```

**Output:**

Create the `Reports/` directory if it doesn't exist. Generate:
- `Reports/2026-April-viz.html`
- `Reports/2026-Q2-viz.html`
- `Reports/2026-W11-W16-viz.html`

**How to generate:**

1. Read all weekly files in the range (same as `/worklog summary`)
2. Collect data from enriched frontmatter (`item-count`, `done-count`, `programs[]`)
   and body parsing (subgroup item counts, P0/P1/P2 counts per week)
3. Read the HTML template from `references/viz-template.html` (bundled with this skill)
4. Replace `{{TITLE}}` with the period name (e.g., "April 2026")
5. Replace `{{SUBTITLE}}` with the source info (e.g., "Sourced from W15, W16 (as of Apr 13)")
6. Replace the `// DATA_PLACEHOLDER` line with `const data = { ... };` containing
   the aggregated data as a JSON object matching the schema described in the template
7. Write the completed HTML file to `Reports/`

The template includes four charts: time allocation pie, program activity heatmap,
P0 trend line, and completion rate stacked bars. Using the template ensures
consistent styling and layout across invocations.

After writing, tell the user: "Visualization saved to Reports/<filename>.html -
open in a browser to view."

### `/worklog sync`

Back up the vault and skill to the private repo. First copies the current skill
source into the vault, then commits and pushes:

```bash
# Copy skill files into vault for backup
cp __SKILL_INSTALL_PATH__/skills/worklog/SKILL.md \
   "__VAULT_PATH__/.skills/worklog/SKILL.md"
cp __SKILL_INSTALL_PATH__/.claude-plugin/plugin.json \
   "__VAULT_PATH__/.skills/worklog/plugin.json"

# Commit and push
cd "__VAULT_PATH__"
git add Worklogs/ People/ Programs/ Archive/ Summaries/ Reports/ Templates/ .skills/
git -c user.name="__GIT_USER_NAME__" -c user.email="__GIT_USER_EMAIL__" \
    commit -m "worklog sync $(date +%Y-%m-%d)"
git push
```

Before the first sync, check if a `.gitignore` exists in the vault root. If not,
create one to prevent committing sensitive or unnecessary files:

```
.obsidian/plugins/*/data.json
.obsidian/workspace.json
.DS_Store
*.swp
.env
```

Run this after any major update (review, rollover, batch adds). The user may also
ask to sync manually at any time.

## Archiving

When a week is rolled over, move its file from `Worklogs/` to `Archive/` and
rewrite it as a summary:

```markdown
---
type: worklog
week: 2026-W15
date-start: 2026-04-06
date-end: 2026-04-10
status: archived
prev: "[[2026-W14]]"
programs:
  - "[[Platform Migration]]"
  - "[[Cloud Security]]"
people:
  - "[[Sarah Chen]]"
tags:
  - hiring
  - people-management
item-count: 9
done-count: 3
---

# Week of Apr 7, 2026

3 items completed, 6 items rolled forward to [[2026-W16]] (Platform Migration, Dev Sharma leave, ...):

- Completed item one
- Completed item two
- Completed item three
```

Use `[[wiki-links]]` for week cross-references. Summary lists completed and rolled
forward counts (with brief titles in parentheses). Only completed items as bullets.

## Important Behaviors

- Always read the current file before making changes - the user may have edited
  directly in Obsidian.
- Use underscores for bold/italic in conversation (`__bold__` not `**bold**`).
- Always include priority and status when presenting items.
- Calculate ISO week numbers correctly for file naming.
- Write changes directly to files - no clipboard needed except `/worklog share`.
- Keep prompts short during review - Monday mornings are fast-paced.
- **Linking is non-negotiable.** Every time you write or edit ANY file in the vault,
  you must wiki-link all people and programs. This applies to worklogs, archive files,
  people notes, and program notes equally. Before finishing any file write, scan it
  for unlinked names. If someone is mentioned who doesn't have a note yet, create a
  stub note first, then link them. Use `slack_search_users` to resolve full names
  when only a first name or handle is given. The graph is only as good as its links.
- After major updates, remind the user to `/worklog sync` or offer to run it.
- **Suggest tidy proactively.** After adding 3+ items in a single session, or when
  the current week file exceeds 20 top-level items, suggest running `/worklog tidy`
  to keep subgroups balanced, consolidate stale sub-items, and fix frontmatter.
  Don't force it - just mention it once at the end of the session.

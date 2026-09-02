# `/worklog summary [period]`

Loaded on demand from `SKILL.md`. Everything the command needs is here.


For a quarter summary, run the Model Guard (see `## Model Guard` in `SKILL.md`) before proceeding. (Week and month summaries are lighter and do not need it.)

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
5. Collect all wiki-linked people and programs mentioned. For any entity that needs
   context in the synthesis, read its `summary` from
   `__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries`. Do not read People or
   Program bodies.

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

__Log it:__ append one entry with op `summary` and target the period label.

**Edge cases:**

- If no weeks exist in the range, say so rather than producing empty output
- If the active week is partially complete, note "as of <today's date>"
- For overlapping periods, include a week if its `date-start` falls within the range
- If a vault file already exists for the period, tell the user it exists and ask
  whether to overwrite or skip. If overwriting, proceed normally.

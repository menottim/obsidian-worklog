# `/worklog audit`

Loaded on demand from `SKILL.md`. Everything the command needs is here.


__Nudge check (run first):__ Same as `/worklog rollover` above - check `Sources/*.md` and
surface a stale-channel FYI before continuing.

__Operational health (run second):__ read the last 10 log entries:

```bash
cat '__VAULT_PATH__'/Logs/*.md | grep '^## \[' | tail -10
```

Surface two conditions alongside the vault findings: a `pull` entry recorded as partial,
and no `pull` entries at all in a window where the stale-source nudge is firing. Read
before writing, so an audit run never reports on itself. If `Logs/` does not exist yet,
skip this step silently.

Scan the vault for quality issues and present a fix-it checklist. No arguments.

__Run the scanner__ - it computes all twelve checks in bash so no `People`/`Programs`
bodies load into context:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/audit-scan.sh '__VAULT_PATH__'
```

It prints JSON with twelve keys. Six are __findings__, each entry an item to fix:
`stale_people`, `orphan_programs`, `stuck_items`, `missing_links`, `empty_stubs`,
`frontmatter_gaps`. Read __only__ this output - do not glob or read `People`/`Programs`
bodies yourself. The `stuck_items` and `missing_links` checks are heuristic; review each
and drop obvious misfires before presenting.

Four are __distributions__, not findings. Each is a compact table where the judgment is
yours, not the scanner's, because correctness is not decidable in bash:

- `oversized_notes` - findings-shaped, actually: `{file, lines, compacted}` for every
  `People/`, `Programs/` or `Threads/` note over its threshold - `WORKLOG_COMPACT_LINES`
  (default 250) for the first two, `WORKLOG_THREAD_LINES` (default 400) for Threads, since
  a Thread being long is its purpose. `compacted` is the note's frontmatter value or null,
  so a note that was compacted and has grown again is distinguishable from one never
  compacted. Offer `/worklog compact <file>` for each, one at a time, never batched.
- `team_vocabulary` - `{value, notes, resolves, candidate?}` for every distinct `team:`
  value on People notes. `resolves` is `exact`, `substring`, or `none` against the
  `Teams/` note names. Propose merge groups from this and let the user approve them one
  at a time; do not rewrite `team:` values unasked. A value resolving `none` is often
  correct: `External`, `Former Employee`, `Unknown`, and `Partner` are reserved, and a team
  outside the org is recorded by name on purpose, since a `Teams/` note for every partner
  org would be more upkeep than the graph is worth. Treat `none` as drift only when the
  value names a team the org owns, which is what merge groups are for.
- `recurring_tags` - `{tag, files, has_page}` for tags appearing in 3 or more weekly or
  archive files. Judge which recurring themes deserve a `Programs/` or `References/`
  page. Most do not: `strategy`, `growth`, `leadership`, and `team-health` are themes,
  not programs. Suggest a page only where the tag names a specific effort with an owner
  or an end state.

- `cold_candidates` - `{path, movable_bytes, total_bytes, sections}` for each `People/`,
  `Programs/` or `Threads/` note with at least `WORKLOG_COLD_MIN_KB` (default 4) KB of movable
  content. Movable content is:
  - dated `##` sections older than the folder's window (`WORKLOG_COLD_DAYS_PEOPLE` and
    `_PROGRAMS` 60, `WORKLOG_COLD_DAYS_THREADS` 30)
  - any `## History` section
  - dated `###` subsections under an undated container `##`

  The list is largest first. Say which notes would gain most, then suggest `/worklog cold`.
  These are not defects: pins can keep some entries warm. The scanner counts bytes before pins,
  so a candidate can be all pinned, and the move skips it. See `references/cold.md`.

One is a __gauge__ on the active week file:

- `week_volume` - `{file, body_bytes, items, sub_items, bytes_per_item, items_over_sub_cap,
  largest_item_bytes, largest_item, over_threshold, limits}`, or `null` when there is no
  active week. `over_threshold` is true when the body exceeds `WORKLOG_WEEK_BYTES` (default
  40000) or the largest single item exceeds `WORKLOG_WEEK_ITEM_BYTES` (default 6000). Offer
  `/worklog tidy` - specifically its spill and park steps - not `/worklog compact`: a week
  file has no `##` headings for compaction to classify, and the remedy is spilling items to
  `Threads/` and parking dormant ones. See `references/threads.md`.

  Every numeric field comes back `null` with `over_threshold: true` and a `note` when the
  week file's frontmatter has no closing delimiter. The body cannot be measured in that
  state, and reporting zeros would say "empty and fine" about a file that might be enormous.
  Fix the frontmatter, then re-run.

  `items_over_sub_cap` is reported but is __not__ a trigger: rules 3 and 4 in
  `references/threads.md` deliberately keep more than `WORKLOG_WEEK_KEEP_SUBS` on an item
  carrying open actions or undated lines, so gating on it would flag correct output.

  __Read `bytes_per_item`, not `items`.__ Item count is the number this file's growth cannot
  move, because "fold before you add" routes every new fact into an existing item. Measured
  across four weeks: 126, 136, 144, 151 items while the file grew to 953 KB. The gauge
  exists to watch the other axis.

`cold_integrity` is a seventh __findings__ key. It holds `{path, problem}` rows, and the list is
empty when the vault is healthy. Each row is a defect to fix. A row reports one of these
problems:

- a `[[Cold/...]]` link in a `## Cold storage` section whose target file is missing
- a `Cold/` file with no `parent:` frontmatter key
- a `Cold/` file that no warm note links to

Fix the link, add the key, or restore the index line.

Present the findings grouped by check type, each with a suggested action, e.g.:

```
Vault audit results:

Stale people (not mentioned in 4+ weeks):
- People/Jordan Lee.md - last seen in W19
  Suggested: archive, update context, or remove if no longer relevant

Stuck items (3+ weeks without update):
- "Figure out Q2 plans across Cloud Security" - P0 since W14
  Suggested: add a status update or reprioritize

Missing links:
- Worklogs/2026-W23.md:23 "Tom" -> [[Tom Rivera|Tom]]

Frontmatter gaps:
- Archive/2026-W11.md: missing programs, people

Week file volume:
- Worklogs/2026-W37.md - 944,282 bytes, 151 items (6,253 bytes/item), 2,020 sub-items
  129 items over the 3-sub-item cap; largest is 34,825 bytes ("Developer Onboarding Program rollout")
  Suggested: /worklog tidy - spill oversized items to Threads/, park dormant ones

Oversized notes (over 250 lines, or 400 for Threads):
- People/Morgan Chambers.md - 1536 lines, never compacted
  Suggested: /worklog compact "People/Morgan Chambers.md"

Team vocabulary (86 values, 7 resolve exactly):
- "Platform & Reliability" (7 notes) and "PRA" (2 notes) look like one org
  Suggested: merge both into a Teams/ note, or map to the reserved set

Cold storage candidates (60-day window; 30 for Threads):
- People/Morgan Chambers.md - 212 KB of 240 KB movable in 31 sections
  Suggested: /worklog cold

Cold storage integrity:
- Threads/ai-fluency.md - link target missing: Cold/Threads/ai-fluency/2026-Q2
  Suggested: fix the link or restore the file

Recurring tags without a page:
- leadership-transition (6 weeks) - names a specific effort, page looks warranted
- strategy (16 weeks) - a theme, no page needed
```

The user picks which fixes to apply. Apply approved fixes directly with Edit/Write; for
frontmatter gaps, regenerate using the Frontmatter Auto-generation rules. The check
definitions live in `scripts/audit-scan.sh` — do not re-derive them here.

If the user approved and you applied any fixes, append one log entry naming what was
fixed. If nothing was applied, write no entry.

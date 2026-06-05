---
title: Worklog Cost-Optimization Program — Design
date: 2026-06-05
status: draft
feature: worklog-cost-optimization
---

# Worklog Cost-Optimization Program — Design

Cut token cost on the worklog skill's heaviest commands and on the per-call base tax, with
__zero behavior change__: command outputs, prompts, and the privacy model stay identical;
only what gets loaded into the model changes. Three independent sub-projects, designed as
one program (v5.8.0) and implemented in sequence.

## Motivation (measured, 2026-06-05)

A static context-load measurement against the real vault (token estimate = bytes / 4,
input/context only) found the cost concentrated in two places, not where structure alone
suggested:

| Command | ~input tokens | Dominated by |
|---|--:|---|
| `audit` | ~312,000 | all 262 People (~202K) + 71 Programs (~76K) bodies |
| `summary`/`viz` quarter | ~45,000 | all 2026 weekly files (~13 today) |
| `pull` (classify) | ~36,000 | SKILL.md (~21K) + current week (~15K) |
| `status`/`review`/`add` | ~35,000 | SKILL.md (~21K) + week (~15K) |

Two findings drive the program:

1. __`audit` is ~10x every other command__ because its read set is essentially "all People
   + Programs bodies" — yet all six audit checks are already defined mechanically in
   `SKILL.md`. None need file bodies in the model.
2. __`SKILL.md` is ~21K tokens loaded on every call__ (~1,712 lines / ~84KB) — about 60% of a
   typical command's cost before any work. The `Commands` (34KB) and `Netflix-specific
   commands` (13KB) sections load even for `/worklog status`, which never uses them.

A hidden third cost: the "before any preference-shaped task, glob `Preferences/*.md` and
apply" rule now spans 58 files / ~40K tokens.

Subagent fanout and model tiering were considered and rejected for this iteration: at
today's volumes the win is "stop loading bodies you can grep," not "parallelize the
reasoning."

## Goals

- `audit`: ~312K → ~26K input tokens (~92% reduction), findings identical to today.
- Base tax: ~21K → ~10K per `/worklog` call via progressive disclosure (moderate level).
- Preferences: ~40K of bodies → a few-KB digest plus only the 1-3 relevant bodies.
- Zero behavior change: every command's output, prompts, and privacy guarantees unchanged.
- No new runtime dependencies (bash + `jq`/`grep`/`awk`, matching existing helpers).

## Non-goals (this program)

- Subagent fanout or per-task model tiering.
- A persistent generated vault index (scan on-demand instead).
- Moving `summary`/`viz` aggregation off the model (only ~45K today; revisit when the
  archive is much larger).
- Any change to command outputs, prompts, the approval/fold flow, or the privacy model.

## Cross-cutting architecture

- __Helpers live in the plugin__ at `skills/worklog/scripts/` (repo-tracked, versioned with
  the skill). They scan only the vault — no secrets — so unlike the Slack helpers in
  `~/.config/obsidian-worklog/bin/` (token-bearing, delivered via `SETUP-SLACK.md`), they
  belong in the repo. The skill invokes them via the existing `__SKILL_INSTALL_PATH__`
  template placeholder (the marketplace install path, already used by `/worklog sync`):
  `__SKILL_INSTALL_PATH__/scripts/<name>.sh '__VAULT_PATH__'`. Both placeholders are
  substituted on install, so the live `SKILL.md` carries real absolute paths. (Shorthand
  `<skill-base>/scripts/...` below means exactly this.) The scripts exist in every propagated
  copy — marketplace, cache, and vault `.skills` — so the marketplace path always resolves.
- __Scan on-demand, no persistent index.__ Each helper reads file bodies in bash on every
  run; the model never sees them. No cache, no staleness, always fresh. A persistent index
  would save only negligible bash runtime while adding invalidation complexity.
- __Helpers are portable / placeholder-free.__ They take the vault path as an argument, so
  the scripts themselves contain no `__VAULT_PATH__` and need no substitution on propagation.
- __Behavior-preserving + verified.__ Each helper is validated against the real vault and its
  output diffed against what the model produces today before it is trusted.
- __Stack:__ bash + `jq` + `grep`/`awk`. No new dependencies.

## Sub-project A — Audit deterministic helper

### Component: `skills/worklog/scripts/audit-scan.sh '<vault>'`

Computes the six audit checks exactly as defined in today's `SKILL.md`, emitting structured
findings (JSON) to stdout. Definitions (unchanged from the current spec):

1. __Stale people__ — `People/*.md` whose name (or alias) is not wiki-linked in any
   `Worklogs/`+`Archive/` file dated within the last 4 weeks; exclude people referenced in
   `Backlog.md`.
2. __Orphan programs__ — `Programs/*.md` not wiki-linked from any `Worklogs/`+`Archive/`
   file dated within the last 4 weeks.
3. __Stuck items__ — active-week `In Progress` items whose title appears in 2+ consecutive
   archives' rollover lists AND has no `(Mon D)` dated sub-item in the active week within the
   last 2 weeks. Title matching is normalized (lowercased, punctuation-stripped, 80%+ word
   overlap). This is the one mildly-fuzzy check; the model reviews findings before presenting.
4. __Missing links__ — known `People`/`Programs` names appearing in weekly body text NOT
   wrapped in `[[...]]`. Output file + line + suggested link.
5. __Empty stubs__ — `People`/`Programs` notes whose `## Context` section has no bullet points
   (only the heading, or missing entirely).
6. __Frontmatter gaps__ — `Worklogs`/`Archive` files missing any of `programs`, `people`,
   `tags`, `item-count`, `done-count`.

Output schema (JSON):
```json
{
  "stale_people": [{"file": "People/Jordan Lee.md", "last_seen": "W19"}],
  "orphan_programs": [{"file": "Programs/Foo.md"}],
  "stuck_items": [{"title": "...", "since": "W14", "last_dated": "Apr 13"}],
  "missing_links": [{"file": "Worklogs/2026-W23.md", "line": 23, "text": "Tom", "suggest": "[[Tom Rivera|Tom]]"}],
  "empty_stubs": [{"file": "People/X.md"}],
  "frontmatter_gaps": [{"file": "Archive/2026-W11.md", "missing": ["programs","people"]}]
}
```

### SKILL.md change

Rewrite `### /worklog audit`: keep the nudge check; replace the inline check methods with
"run `<skill-base>/scripts/audit-scan.sh '<vault>'`, then present its findings using the
output format below, suggest actions, and apply approved fixes (Edit/Write; regenerate
frontmatter via the existing rules)." The check *definitions* live in the script (mirrored
in a short comment block at the top of the script for maintainability). The model reads only
the JSON findings (~few KB) — never People/Programs bodies.

### Verification

Run `audit-scan.sh` on the real vault; manually spot-check at least one finding per check
type against the files; confirm the presented audit output matches today's format and the
findings are correct.

## Sub-project B — SKILL.md progressive disclosure (moderate)

Move three rarely-loaded blocks from `SKILL.md` into `skills/worklog/references/`, each
replaced inline by a short stub that __requires__ loading the reference before executing:

- `references/viz.md` — the `/worklog viz` mechanics + template-fill steps.
- `references/netflix-commands.md` — the entire "Netflix-specific commands (this fork only)"
  section: argument auto-routing, `/worklog ingest`, `/worklog whois`, `/worklog jira`, and
  the cross-command enrichment rules.
- `references/pull-flow.md` — the detailed `/worklog pull` flow: pull steps, the
  context-channel sweep flow, the DM sweep flow + privacy override, first-run registration,
  and body extraction.

Inline stub pattern (one per moved command/section), e.g. under `### /worklog viz`:
> Before executing, you MUST read `<skill-base>/references/viz.md` and follow it. (Detail
> lives there to keep this file small.)

Stays inline: vault layout, item format, cross-linking rules, frontmatter auto-generation,
preferences (as modified by C), archiving, important behaviors, the common quick commands
(`status`, `review`, `rollover`, `add`, `tidy`, `search`, `share`, `rollup`, `summary`,
`sync`), the source-type schema summary, dispatch logic, and the stubs.

Base tax ~21K → ~10K per call. Behavior unchanged because the agent loads the reference on
demand; the "you MUST read" stub keeps reliability high.

### Verification

For each moved command, confirm it still executes identically (the agent loads the reference
and behaves as before). `grep` `SKILL.md` for any cross-reference now pointing into moved
content and repoint it at the reference file. `wc -c SKILL.md` confirms the size cut.

## Sub-project C — Preferences index

### Component: `skills/worklog/scripts/preferences-index.sh '<vault>'`

Scans `Preferences/*.md` and emits a compact digest — per preference: filename/title, the
`applies-to` frontmatter tags, and the one-line `## The Rule` text. ~a few KB for 58
preferences vs ~40K of bodies.

Output (one record per preference, JSON lines or a compact table):
```json
{"title": "Markdown Formatting", "applies_to": ["markdown"], "rule": "Use underscore bold, no em dashes."}
```

### SKILL.md change

In the Preferences section + the "Preferences are first-class" Important Behavior, change the
apply step to: "Before a preference-shaped task, run
`<skill-base>/scripts/preferences-index.sh '<vault>'` to get the index; select the 1-3
relevant preferences by `applies-to`/title/rule; read __only those__ full bodies." The model
loads the digest plus the handful that actually apply, not all 58.

### Verification

Run `preferences-index.sh`; confirm every preference appears in the index. Confirm a sample
drafting task selects the correct preference(s) from the index and reads only those bodies.

## Testing (program-level)

- Per sub-project verification above.
- __Cross-cutting:__ re-run the static load measurement (the same `bytes/4` model) before and
  after, and confirm: `audit` ~312K → ~26K; base tax ~21K → ~10K; preferences path ~40K → a
  few KB + relevant bodies.
- Confirm no command's *output* changed: run `audit` and one preference-touching command,
  compare the presented result to today's behavior.

## Files changed

- `skills/worklog/scripts/audit-scan.sh` (new), `skills/worklog/scripts/preferences-index.sh`
  (new).
- `skills/worklog/references/viz.md`, `references/netflix-commands.md`,
  `references/pull-flow.md` (new; content moved out of `SKILL.md`).
- `skills/worklog/SKILL.md` — `/worklog audit` rewritten to call the scanner; the three moved
  blocks replaced by "MUST read reference" stubs; the Preferences apply-step rewritten to use
  the index. No other behavioral text changes.
- `.claude-plugin/plugin.json` — bump `5.7.0` → `5.8.0`; description notes the cost-optimized
  audit + on-demand command detail.
- `README.md` — brief note that audit/preferences use bundled scanner scripts and that
  command detail is loaded on demand.

## Propagation

Same recipe as 5.7.0 (rsync fork → marketplace; substitute the 6 placeholders; copy to
`cache/personal/obsidian-worklog/5.8.0/`; update the vault `.skills/worklog` copy; reload),
with __one addition__: the placeholder substitution must now also run over
`references/*.md` (the moved pull-flow content carries `__VAULT_PATH__`). The
`scripts/*.sh` files are placeholder-free (vault passed as an argument) and need no
substitution; ensure they are copied with the executable bit set.

## Implementation order (one program, sequential)

1. A (audit helper) — biggest win, establishes the scripts/ pattern.
2. C (preferences index) — reuses the scripts/ pattern.
3. B (progressive disclosure) — done last so the audit-rewrite and preferences-rewrite text
   is already in `SKILL.md` before sections move; B also moves the `pull-flow` content (which
   A and C do not touch). Avoids editing the same regions twice.

Each step is independently verifiable; the version bump + propagation happen once at the end.

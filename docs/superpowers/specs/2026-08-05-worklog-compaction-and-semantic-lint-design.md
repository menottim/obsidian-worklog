# Worklog: note compaction and semantic lint

__Date:__ 2026-08-05
__Status:__ design approved, plan pending
__Target version:__ 5.12.0
__Depends on:__ `2026-08-05-worklog-ops-log-and-entity-summaries-design.md` (5.11.0), for
`scripts/log-append.sh` and the `summary:` frontmatter field.

## Context

Two problems, one shared read.

__Notes grow without bound.__ People and Programs notes accumulate append-only context
by design, and nothing ever compacts them. Measured 2026-08-05 across 314 People and 86
Programs notes: mean People note is about 37 lines, but the tail is long and growing.
`People/Christine Chalmers.md` is 1,536 lines (1,483 in June 2026).
`People/Astha Singhal.md` is 852. Five notes exceed 250 lines. Every read of one of
those is a large context cost for information that is mostly historical.

__Lint checks shape, never meaning.__ All six existing `/worklog audit` checks are
structural: stale people, orphan programs, stuck items, unlinked mentions of known
entities, empty stubs, frontmatter gaps. Nothing notices that a note contradicts itself
or that a claim has been superseded. Concrete live example: `People/Astha Singhal.md`
correctly records in its body that WISSE dissolved and that SPA was renamed
Infrastructure & Security, while its own frontmatter still reads
`team: Security, Privacy & Assurance`.

These are one project because compaction requires the model to read the whole note, and
that read is exactly when contradictions and superseded claims are visible. Detecting
them separately would mean paying for the read twice.

### Enabling premise

Confirmed with the user 2026-08-05: they rarely if ever edit the markdown directly
anymore. The vault is effectively LLM-owned, which is what makes lossy rewriting
acceptable at all. Two consequences:

- Lossy folding of old history is permitted, because there is no hand-authored prose
  whose exact wording carries intent the model cannot see.
- Git remains the undo. The vault is a git repo synced regularly (three `worklog sync`
  commits in the two days before this spec was written, working tree clean). Every
  compaction is recoverable via `git diff` and `git checkout`.

The existing "always read the current file before making changes - the user may have
edited directly in Obsidian" behavior stays. The premise is that direct edits are rare,
not that they are impossible.

## Compaction

### Trigger

`/worklog compact [note]`. Explicit, one note at a time, because the fold is lossy and
reads best when the user can sanity-check what got summarized.

`/worklog audit` gains an `oversized_notes` check that lists candidates. It is a pure
line count, no heuristic:

- `WORKLOG_COMPACT_LINES` (default __250__) is the threshold.
- At 250, five notes qualify today: Christine Chalmers (1536), Astha Singhal (852),
  Brian Gaines (451), Rachel Taylor (335), Laura Haller (334). The other 309 People
  notes and all 86 Programs notes are untouched.

Env-var configuration follows the existing convention in `cross-link-index.sh`
(`CROSSLINK_DOM_RATIO`, `CROSSLINK_DOM_ABS`).

With no argument, `/worklog compact` runs the check and offers candidates one at a time
with explicit options, per the user's batch-input preference.

### Target shape

```markdown
---
type: person
team: Infrasec
summary: "Director WISSE; departed Netflix Jun 24 2026"
compacted: 2026-08-05
---

# Astha Singhal

## Role
<current state, verbatim, never folded>

## 1:1 Doc
<current state, verbatim, never folded>

## Recent

### Jun 22, 2026 - org restructure
<verbatim>

## History

- Mar-May 2026: SPA "blocking innovation" narrative, team health, [[Cloud Security EM
  Hiring|CloudSec EM]] loop (5 1:1s folded)
- 2025: <folded>
```

`compacted:` records the last compaction date so a later run knows not to re-fold
anything already inside the retention window.

### Fold rules

__What is a foldable entry:__ a section whose heading contains a date, at any heading
level. Real notes use `## May 29, 2026 - 1:1 (substantive, multi-topic)` with `###`
subsections beneath, so the rule cannot assume a fixed level.

__Never fold a section whose heading has no date.__ This single rule replaces an
enumerated list of protected section names and covers `## Role`, `## Context`,
`## 1:1 Doc`, `## Members`, and anything similar added later. Undated sections carry
current state, which is the answer to "who or what is this" and the entire reason the
note exists.

__Retention window:__ `WORKLOG_COMPACT_KEEP_DAYS` (default __90__). Dated sections newer
than the window move under `## Recent` verbatim. Older ones fold into `## History`.

__What a fold preserves:__ dates, decisions, status changes, facts that changed, and
every `[[wiki-link]]`. __What a fold drops:__ verbatim quotes, meeting play-by-play,
and sub-sub-detail that only supported a conclusion already stated.

__History granularity:__ one bullet per month, or per coherent theme where a theme spans
months. Prefer themes; they read better and compress harder.

### Link preservation is a hard gate

A fold that silently drops `[[wiki-links]]` deletes graph edges, which is the one kind of
damage the vault cannot self-heal: the audit's `missing_links` check only finds unlinked
mentions in recent weekly files, not edges that vanished from a People note.

Before and after each compaction, compute the set of __canonical link targets__:

```bash
grep -o '\[\[[^]]*\]\]' "$note" \
  | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/|.*$//' \
  | sort -u
```

Normalizing to the canonical target (stripping the alias after `|`) is deliberate: a
fold may legitimately reword an alias while keeping the same target, and that is not a
lost edge.

Any target present before and absent after must be reported and explicitly confirmed
before the write is kept. Not a warning, a gate.

### Git precondition

Before writing, check `git -C "$VAULT" status --porcelain`. If the vault is dirty, offer
to run `/worklog sync` first so the pre-compaction version is committed and recoverable.
This is what makes lossy folding safe, and it costs nothing in practice given the current
sync cadence.

### Outputs per compaction

1. The rewritten note.
2. A refreshed `summary:` in frontmatter (the field introduced in 5.11.0). Compaction
   always authors a real one, replacing any derived value.
3. `compacted:` set to today.
4. A contradiction report: internal contradictions and claims superseded by newer
   entries, __reported not auto-fixed__. The user decides.
5. A dropped-link report, empty in the normal case.
6. One log entry via `log-append.sh`:

```markdown
## [2026-08-05] compact | People/Astha Singhal.md
- 852 -> 210 lines; 9 dated entries folded to ## History
- contradiction: frontmatter team says "Security, Privacy & Assurance"; body records rename to Infrastructure & Security
- links preserved: 34/34
```

## Semantic lint

### Why these emit distributions, not findings

Both new checks were prototyped against the live vault before being specified, and the
findings-shaped version failed on both.

`recurring_tags` as a findings check: 23 tags appear in 3 or more weekly or archive
files; 21 have no matching Programs note; of those, roughly 2 plausibly deserve a page.
`strategy`, `growth`, `leadership`, and `team-health` are themes and should never become
Programs notes. A 21-finding list at about 90% false positive is worse than no check.

`team_vocabulary` as a findings check: of 86 distinct `team:` values across 314 People
notes, __7 resolve exactly__ to one of the 16 `Teams/` notes and 20 resolve by substring.
As a per-note dangling-reference list that is roughly 300 findings.

So both emit a compact distribution instead: tens of rows, fully deterministic, no
threshold tuning, and the judgment lands on the model with complete information rather
than on a regex with partial information. This keeps the skill's existing division of
labor (bash does the O(vault) scan, the model reasons over a digest) and extends it to
checks where correctness is not decidable in bash.

### Check: `oversized_notes` (findings)

Structural and decidable, so it emits findings directly:

```json
[{"file": "People/Christine Chalmers.md", "lines": 1536, "compacted": null}]
```

`compacted` carries the frontmatter value if present, so an already-compacted note that
has grown again is distinguishable from one never compacted.

### Check: `team_vocabulary` (distribution)

Every distinct `team:` value with its note count and how it resolves:

```json
[{"value": "Security, Privacy & Assurance", "notes": 7, "resolves": "none"},
 {"value": "Cloud Infrastructure Security", "notes": 5, "resolves": "substring",
  "candidate": "CIS - Cloud Infrastructure Security"},
 {"value": "Detection & Response", "notes": 3, "resolves": "exact"}]
```

`resolves` is one of `exact`, `substring`, `none`. `candidate` is present only for
`substring`. Values are compared with surrounding quotes and trailing whitespace
stripped, which matters: an early prototype produced a spurious mismatch because of
exactly that.

The model reads about 86 rows and proposes merge groups. The user approves.

### Check: `recurring_tags` (distribution)

Tags appearing in 3 or more weekly or archive files, with counts and whether a matching
Programs note exists:

```json
[{"tag": "hiring", "files": 19, "has_page": false},
 {"tag": "spa-leadership-transition", "files": 6, "has_page": false}]
```

Verified that `tags:` frontmatter survives archiving, so this has real history to work
with. Subgroup headings were considered as the signal instead and rejected: archiving
rewrites weekly files as flat completed-item lists, discarding subgroup structure, so
every heading appears exactly once across the archive and the signal is gone.

The model picks which recurring themes deserve promotion to a Programs or References
note. Roughly 23 rows today.

### Cross-note contradiction detection

Out of scope, deliberately. Doing it properly means reading all 400 notes, which is the
exact cost the 5.8.0 optimization removed. Per-note detection during compaction covers
the cases that matter, since a note that contradicts itself is both the most common case
and the most consequential. This limit is stated rather than papered over.

## The `team:` vocabulary cleanup

Included as a rollout step of this spec, not a separate project, because
`team_vocabulary` is what makes it tractable.

The cleanup is not only merges. It needs a convention decision first, or the check stays
permanently noisy: 86 values include legitimately non-team values (`External`,
`Former Netflix`, `HR`, `Finance`, `AWS`, `Talent Acquisition`) and 7 notes whose team is
literally `?`.

Proposed convention: a `team:` value must either match a `Teams/` note name exactly, or
be one of a small reserved set (`External`, `Former Netflix`, `Unknown`). `team_vocabulary`
then reports only genuine drift, which keeps the check useful long term instead of
returning 60 rows forever.

Cleanup sequence:

1. Land the convention in SKILL.md's People note section.
2. Run `team_vocabulary`, group the 86 values into merge groups (roughly 15 to 20:
   all SIDE variants, all SPA and Infrastructure & Security variants, all
   Detection variants, the acronym-versus-full-name pairs).
3. Present one group at a time with explicit options per the batch-input preference.
4. Apply approved merges with `Edit`; create `Teams/` notes for groups with enough
   members to warrant one; map the rest to the reserved set.
5. One log entry recording values before and after.

Expected outcome: 86 values reduced to roughly the 16 existing `Teams/` notes plus a
handful of new ones plus 3 reserved values, and the Teams dimension of the graph becomes
usable for the first time.

## Testing

New `tests/audit-scan.test.sh`, against `tests/fixtures/crosslink-vault` extended with
fixtures for each new check:

- `oversized_notes`: a note above threshold is reported with the correct line count; a
  note below is absent; `WORKLOG_COMPACT_LINES` override is honored; a note with
  `compacted:` set carries that value through
- `team_vocabulary`: exact, substring, and none resolutions each classified correctly;
  quoted and trailing-whitespace values normalized; the `?` value handled without
  crashing
- `recurring_tags`: the 3-file threshold is a floor not a ceiling; `has_page` is correct
  for both cases; a vault with no archive returns an empty array
- the six existing checks return unchanged output (regression guard, since the new keys
  are additive to the same JSON object)

Compaction is model judgment, so it gets eval cases:

- an undated section is byte-identical after compaction
- a dated section inside the retention window is byte-identical
- every canonical link target present before is present after
- a note whose body contradicts its frontmatter produces a contradiction report and no
  auto-fix
- a `summary:` is authored (not derived) and `compacted:` is set
- compaction on a dirty vault offers to sync before writing

## Rollout

1. Bump `.claude-plugin/plugin.json` to 5.12.0.
2. Republish into `personal-plugins` with the Python `str.replace` placeholder pass,
   covering `scripts/` and `references/`.
3. `/plugin marketplace update personal`, confirm "1 plugin bumped", restart.
4. Verify by running the __exact substituted command string__ SKILL.md emits for the new
   scanner path (the 5.8.1 lesson).
5. Run `/worklog audit` and confirm the three new outputs appear alongside the six
   existing checks.
6. Run the `team:` vocabulary cleanup (above).
7. Compact the five oversized notes, one at a time, confirming the link gate on each.
8. `/worklog sync`.

## Out of scope

__Semantic search.__ Grep handles literal search adequately at 314 People, 86 Programs,
103 Meetings. Conceptual search ("what did we decide about contractor classification")
is where grep fails, and a local hybrid BM25 plus vector index would fix it. Not worth a
dependency yet. Stated as a known ceiling.

__Raw-source preservation for context-channel and DM sweeps.__ Neither writes a
`Meetings/` note by design, so the folded claim plus a Slack permalink is the only record;
if the message is edited or channel access is lost, the derivation is unreproducible. A
genuine fidelity gap, but it is a decision about the ingest contract, not about
compaction.

__Public repo parity.__ Compaction and both lint checks are Netflix-agnostic and are
candidates for the public repo, but the strip-and-sync workflow remains undefined.

## Provenance

The semantic lint direction came from comparing this skill against "LLM Wiki" by Andrej
Karpathy: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

Specifically his Lint operation, which names contradictions between pages, stale claims
superseded by newer sources, and important concepts mentioned but lacking their own page.
The compaction design, the undated-section rule, the link-preservation gate, and the
distributions-not-findings decision are this skill's own, driven by its existing cost
model and by prototyping both checks against the live vault.

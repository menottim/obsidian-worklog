# Worklog: operations log, entity summaries, filed answers

__Date:__ 2026-08-05
__Status:__ design approved, plan pending
__Target version:__ 5.11.0
__Companion spec:__ `2026-08-05-worklog-compaction-and-semantic-lint-design.md` (5.12.0)

## Context

The worklog skill is one instantiation of a general pattern: an LLM incrementally
builds and maintains a persistent, interlinked markdown knowledge base instead of
re-deriving answers from raw sources on every query. A comparison against Karpathy's
statement of that pattern (see Provenance) surfaced three capabilities the pattern
includes and this skill does not. All three are small. All three address gaps that
have already cost something.

__1. There is no operations log.__ The vault records artifacts (weekly files, Meetings
notes, Summaries) but nothing records what the skill did and when. Questions that
should be trivial are currently unanswerable from the vault: was the last pull
complete or a scoped smoke, what was approved and what was dropped in the last DM
sweep, what has this skill actually done this month. In June 2026 a scoped DM-sweep
smoke deliberately left `last_scan_ts` at null, and the only surviving record of that
decision was an external memory file.

__2. The entity digest knows names, not meaning.__ `cross-link-index.sh` resolves
aliases across 314 People and 86 Programs notes, but carries no information about what
any entity is. Zero of the 400 notes have a one-line summary field. So selection is
cheap and comprehension still costs a full note read. The underlying principle in the
source pattern is index first, drill in second; this skill applied it to names and
skipped it for meaning.

__3. Answers do not compound.__ `/worklog rollup` states explicitly: "Do not save it as
a vault file - this is a one-shot, ephemeral message." `/worklog share` is
clipboard-only. `/worklog search` output goes nowhere. So a rollup that took real
editorial judgment survives only as a Slack paste. `/worklog summary` is the one
command that files its output, which demonstrates the plumbing already exists.

## Scope

Three changes, one branch, version 5.11.0. Ordered by dependency: none of the three
depends on the others, but item 1 introduces the log helper that the companion spec
writes to, so it lands first.

Out of scope for this spec: note compaction, semantic lint, and the `team:` vocabulary
cleanup. All three live in the companion spec.

## Item 1: operations log

### Storage

One file per month at `Logs/YYYY-MM.md`. Monthly files are bounded by construction, so
the log never needs its own compaction pass, which matters because unbounded growth is
the exact problem the companion spec exists to solve.

Frontmatter, consistent with the rest of the vault:

```yaml
---
type: log
month: 2026-08
---
```

### Entry format

```markdown
## [2026-08-05] pull | #infrasec-leads
- 24 messages swept, 4 folded, 2 dropped (sensitive)
- last_scan_ts -> 2026-08-05T18:22:00Z (complete)
```

The `## [YYYY-MM-DD] <op> | <target>` prefix is a contract, not a suggestion. It is
what makes the log greppable without a reader script:

```bash
cat "$VAULT"/Logs/*.md | grep '^## \[' | tail -5
```

Body lines are freeform one-per-outcome bullets.

### Helper: `scripts/log-append.sh`

```
log-append.sh <vault> <op> <target> [body-line ...]
```

Creates `Logs/YYYY-MM.md` with frontmatter if absent, then appends one entry. Uses the
current date for both the filename and the entry prefix. Read-write (the only helper
in the skill that writes), bash 3.2, no dependencies beyond coreutils.

The helper exists specifically so the entry format cannot drift. Every consumer of the
log is a grep against that fixed prefix, so a single malformed entry written by hand
silently drops out of every query. Prose instructions in SKILL.md do not provide that
guarantee; a helper does.

Exit codes: 0 on success, 2 on usage error or unwritable vault. Callers surface a
non-zero exit rather than silently continuing, matching the existing
`cross-link-index.sh` contract.

### What gets logged

One rule, stated as a rule rather than an enumeration so it cannot go stale:

> Log any operation that writes to the vault.

That covers `pull`, `rollover`, `tidy`, `summary`, `viz`, `sync`, `compact` (companion
spec), filed answers (item 3), and `audit` __only when fixes were applied__. It excludes
`status`, `search`, `share`, and a read-only audit run, none of which change the vault.

The single-clause form is deliberate. An earlier draft added "plus any lint pass that
reports findings," which would have logged every read-only audit run and turned the log
into a record of questions asked rather than changes made. Absence is still
informative: no pull entries for three weeks answers "when did I last ingest" as well as
a positive entry would.

__Pull entries carry an additional requirement.__ Every pull entry must record whether
the sweep was complete or partial, and the resulting `last_scan_ts` per source. This is
the specific gap that produced the June 2026 confusion, and it is the one case where
the log's absence caused a real loss of state knowledge.

### Consumers

- On demand, by grep, as shown above. No reader script.
- `/worklog audit` reads the last 10 entries and reports operational health alongside
  its existing findings: a pull recorded as partial, or no pull entries at all in a
  window where the stale-source nudge is firing. The read happens before audit's own
  entry would be written, so a run never reports on itself.

`/worklog status` deliberately does not read the log. Status runs constantly and the
log is not part of answering "what is on my plate."

### Sync

`Logs/` must be added to the `git add` allowlist in `/worklog sync`. SKILL.md line 1128
already documents that this allowlist is explicit, that a missing directory is silently
never staged, and that `Teams/`, `References/`, and `Preferences/` have each been missed
this way. A new directory that is never backed up is worse than no directory.

## Item 2: entity summaries

### The field

An optional one-line `summary:` in People and Programs frontmatter:

```yaml
---
type: person
team: Infrasec
summary: "Director WISSE; departed Netflix Jun 24 2026"
---
```

Guidance: one line, no wrapping, under about 120 characters, present-tense current
state. It answers "who or what is this" for someone who has never read the note.

### Digest change

`cross-link-index.sh` gains a `--with-summaries` flag. Without the flag, output is
byte-identical to today. With it, each entity gains a `summary` field:

```json
{
  "canonical": "Astha Singhal",
  "type": "person",
  "aliases": ["Astha"],
  "summary": "Director WISSE; departed Netflix Jun 24 2026",
  "summary_source": "declared"
}
```

The flag is required rather than always-on because the plain digest runs on every
single vault write, making it the hottest path in the skill. Summaries across 400
entities add roughly 10K tokens, which would partly undo the 5.8.0 work that took the
audit path from about 312K to about 26K.

### No backfill

When `summary:` is absent, the script __derives__ a provisional summary in bash from the
note's first content bullet (first bullet under the first `##` section after
frontmatter), truncated to 120 characters, and marks `summary_source: "derived"`.

This means coverage is complete from day one with no backfill project. A one-time model
pass over all 400 notes was considered and rejected at roughly 200K tokens for an
outcome the derived fallback covers adequately. Real summaries accumulate
incrementally: the model writes or refreshes `summary:` whenever it touches a note, and
compaction (companion spec) always emits one.

`summary_source` is part of the contract so a consumer can tell a derived guess from an
authored line.

### Call sites

- Cross-Linking step 1 (the write path): plain call, unchanged.
- Query and selection paths: `--with-summaries`. Specifically `/worklog status`,
  `/worklog search`, `/worklog summary`, and the pull classify step in
  `references/pull-flow.md`, which currently globs `People/*.md`.

Wiring the pull classify step to the digest also closes a carried defect: that flow
still globs `People/*.md` directly rather than using the helper shipped in 5.9.0.

### Maintenance rule

Added to Cross-Linking: when appending substantive context to a People or Programs
note, refresh `summary:` if the note's current state changed. Do not refresh for minor
additions. This mirrors the existing frontmatter regeneration guidance, which already
distinguishes structural changes from minor edits.

## Item 3: filed answers

### Rollup

`/worklog rollup` keeps its `pbcopy` output and additionally writes
`References/YYYY-WNN Rollup.md`:

```yaml
---
type: reference
subtype: rollup
period: 2026-W31
source: /worklog rollup
---
```

Two renderings of one artifact. The clipboard version strips `[[wiki-links]]` for Slack;
the filed version keeps them, so the rollup appears in the graph and in backlinks on
every program it names. That link density is the entire reason to file it rather than
keep it ephemeral.

The existing include and exclude content rules are unchanged and apply to both
renderings. Filing does not relax the filter: performance commentary, 1:1 specifics,
and candidate details stay out of the filed copy too, because `References/` is synced to
the backup repo.

### New command: `/worklog file [title]`

Writes the current substantive answer into `References/<title>.md` with `type:
reference`, a `source:` field naming what produced it, and full cross-linking per the
existing rules. Filename is the given title, or a date-prefixed slug derived from the
content if no title is given.

Triggered by an offer, not automatically. After producing a substantive analytical
answer against the vault, offer to file it once. This matches the existing Preferences
capture pattern, where nothing durable is written without confirmation.

### Deliberately not filed

- `/worklog share`, a three-line status blurb. Filing weekly would add 52 files a year
  of noise to `References/`.
- `/worklog search`, whose output is re-derivable by re-running the search.

## Testing

New `tests/log-append.test.sh`:
- creates the month file with correct frontmatter when absent
- appends to an existing month file without duplicating frontmatter
- entry prefix matches `^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] `
- multiple body lines are preserved in order
- exits 2 on missing arguments and on an unwritable vault path

Extend `tests/cross-link-index.test.sh`:
- default output is unchanged (no `summary` key present)
- `--with-summaries` with a declared `summary:` yields `summary_source: "declared"`
- `--with-summaries` with no declared summary derives from the first content bullet and
  yields `summary_source: "derived"`
- an empty stub with no bullets yields an empty summary rather than failing
- a summary containing quotes, colons, and a `|` character survives JSON encoding

Run against `tests/fixtures/crosslink-vault`, extended with one note carrying a declared
summary and one empty stub. Existing 30 assertions must still pass.

Filed answers and the log-writing rule are model behavior, so they get eval cases
rather than unit tests: a rollup produces both clipboard and filed artifacts with links
present in the filed copy only; a pull writes exactly one log entry recording
completeness.

__Existing eval 9 must be amended.__ It asserts that re-running `/worklog pull` with no
new Slack content modifies nothing. Once the log exists, a zero-result pull writes one
log entry, because "the sweep ran and found nothing" is itself state worth recording and
is precisely what distinguishes a completed sweep from one that never happened. Eval 9's
expectation becomes: no `Meetings/` files created or modified, no items added to the
current week, `last_scan_ts` advanced, and __exactly one__ log entry recording 0 new
threads. Left unamended, this change would read as an idempotency regression.

Eval 3 (`/worklog audit`) is behavioral rather than a JSON-shape assertion, so the
additive audit key in the companion spec does not affect it.

## Rollout

Per the distribution pipeline:

1. Bump `.claude-plugin/plugin.json` to 5.11.0.
2. `git archive HEAD | tar -x` into `personal-plugins/plugins/obsidian-worklog/`.
3. Substitute the 6 placeholders with a Python `str.replace` pass, covering `scripts/`
   and `references/` as well as SKILL.md.
4. Commit to `personal-plugins`.
5. `/plugin marketplace update personal`, confirm "1 plugin bumped".
6. Restart Claude Code; the cache is version-keyed.
7. Verify `log-append.sh` by running the __exact substituted string__ SKILL.md emits, not
   an equivalent path. This is the 5.8.1 lesson: every static review and propagation
   smoke passed while the literal emitted command was broken.

Public repo parity is not addressed here. The log, summary field, and filed answers are
all Netflix-agnostic and are candidates for the public repo, but the strip-and-sync
workflow remains undefined and out of scope.

## Provenance

The three gaps this spec closes were identified by comparing the skill's design against
"LLM Wiki" by Andrej Karpathy:
https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

Specifically: `log.md` as a chronological append-only record with a greppable prefix,
`index.md` as a content-oriented catalog read before drilling into pages, and the
observation that good query answers should be filed back into the wiki so explorations
compound like ingests. The monthly-file storage, the helper-enforced format, the
flag-gated digest, and the derived-summary fallback are adaptations to this skill's
existing cost model, not part of the source pattern.

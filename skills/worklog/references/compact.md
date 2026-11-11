# `/worklog compact [note]`

Loaded on demand from `SKILL.md`. Everything the command needs is here.


__`/worklog cold` normally handles size__ (`references/cold.md`). It moves old entries
verbatim and loses nothing. Run the lossy fold below only when the user explicitly asks for it.
Threads are compactable, but they normally go cold instead.

Fold a note's old history into a summary so the note stops growing without bound. Lossy
by design and explicit by design: you run it on one note at a time and the user sees what
was folded.

__Measured floor: Opus holds up across the board; Haiku holds on straightforward folds but
not on the harder edges.__ Across the seven compact eval cases that have an assertion script
(case 33 has none yet and cannot be measured), two reps each: Opus passed every run, 14/14.
Haiku also passed every run on the four cases testing straightforward classification and
folding (32, 34, 35, 36): 8/8. On the three harder cases - retention-window immutability
across repeat compactions (37), marker-set splitting (38), and re-approval after a revision
(39) - Haiku failed 4 of 6 runs, and the failures were not all the same kind. Two were
reasoning bugs: a newly-aged entry left sitting in `## Recent` past its retention window,
and a stricter marker collapsed into an entry that should have kept it separate. Two were
approval-gate lapses: a fold written and committed without ever pausing to show the
proposal, and a revised fold written under the earlier, pre-revision approval instead of
asking again.

If you are Haiku-tier, treat both kinds of risk as live on these three cases: check the
retention-window math and marker sets by hand rather than trusting the first answer, and
hold every approval gate as a hard stop even when the classification feels right. The safer
choice for a note carrying handling markers, sitting mid-revision, or being compacted for a
second time is running compact on Sonnet or better - a session-level choice this skill
cannot make on its own.

With no argument, run the scanner, read `oversized_notes`, and offer the candidates one
at a time with explicit options (largest first). Do not batch them.

__Precondition: the vault git state must be clean.__

```bash
if ! git -C '__VAULT_PATH__' rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "vault is not a git repository: refusing to compact"
else
  git -C '__VAULT_PATH__' status --porcelain
fi
```

If the first command fails, the vault is not under git and there is no undo. __Do not
compact.__ Tell the user the vault is not under git and that there is no undo, then stop.
Say nothing else about it: no offer to run `git init`, no forward-looking description of
what `git init` or `/worklog sync` would unlock, no path forward of any kind. That decision
belongs to the user, unprompted, and this refusal is unconditional either way. If the
second prints anything, the vault is dirty:
offer to run `/worklog sync` first, then re-run this check rather than assuming the sync
cleaned everything, since the sync `git add` list is an explicit allowlist that can leave
files unstaged. When auto sync is on, run `sync.sh --auto` in place of the offer, and continue on exit 0, 3
or 4, then re-run the clean check; stop on 1 or 2. Git history is the only undo for a lossy fold, so an unclean or
un-versioned vault means an unrecoverable rewrite. If the user declines to sync, or if
the re-run still reports the vault dirty, __do not compact.__ Say which files are
outstanding and stop.

__Read the whole note.__ This is the one operation that legitimately loads a full note
body, and it is why contradiction detection rides along here rather than as its own pass.

__Target shape:__

```markdown
---
type: person
team: Northwind Platform
summary: "Director, Platform Ops; left the company Mar 3 2026"
compacted: 2026-08-05
---

# Nadia Okafor

## Role
<current state, verbatim>

## Recent

## Mar 1, 2026 - org restructure
<verbatim>

## History

- Mar-May 2026: roadmap negotiation, team health, [[Platform EM Hiring|Platform EM]] loop (5 1:1s folded)
- 2025: <folded>
```

Every frontmatter key already present is preserved verbatim. Compaction only adds
`summary:` and `compacted:`; it never removes or rewrites another key, including when
one of them is the claim your contradiction report is about.

__Definitions.__ Three terms, used precisely below, plus a scoping note for the two
headings this operation writes itself.

- A __dated entry__ records what happened at a particular time: a meeting, a message,
  an event, a decision as it was taken. `## May 29, 2026 - 1:1`,
  `## Ines's Direct Response (Mar 10)`, and `## ✅ Feedback DM sent (Mar 17)` are
  all dated entries, whether the date leads the heading, trails it, or sits in the
  middle.
- A __current-state section__ states what is true now, even when its heading carries a
  date recording when that was last checked. `## Role (HR system, confirmed 2026-07-30)`,
  `## Org position as of Feb 2026`, `## Security review state (as of Feb 9 2026)`,
  `## Context`, `## 1:1 Doc`, `## Members`, and `## OOO` are all current state. The test
  is what the section is for, not where the date sits: an account of a moment is a
  dated entry, a statement of the present with a provenance stamp is not.
- A __handling marker__ is an explicit restriction or release label appearing anywhere
  in a heading, matched case-insensitively: `🔒`, `vault-only`, `confidential`,
  `ultra-confidential`, `confidence-bound`, `HIGH SENSITIVITY`, `sensitive`,
  `surfaceable`, `shareable`. It counts whether it sits in a parenthetical or in the
  heading's descriptive title. A date, a time, an attribution, or an editorial aside
  such as `(significant)` or `(per X's recap)` is not a marker and does not affect fold
  structure.
- `## Recent` and `## History` are structural headings this operation creates and
  manages; they are neither dated entries nor current-state sections.

__Threads are in scope; week files are not.__ A `Threads/<slug>.md` note is built to the
shape these rules classify: a `## Context` current-state section that rule 1 protects, and
`## <Mon D, YYYY> - <label>` dated entries that rule 2 travels whole. Nothing here changes
for a Thread, and the scanner lists them under `oversized_notes` at `WORKLOG_THREAD_LINES`
(default 400) rather than `WORKLOG_COMPACT_LINES`, because a Thread being long is its
purpose.

A week file is not compactable and must never be passed to this command. By spec it uses
`#` for the title only and __bold text, not headings__, for subgroups (see
`## Weekly File Structure`), so there are zero `##` sections to classify and this algorithm
has nothing to act on. A week file's size is a retention problem, not a folding problem: it
is recreated from scratch every Monday, so the fix is `/worklog rollover` copying forward
less. See `references/threads.md`.

__Precedence.__ When two rules below disagree, the earlier one wins.

1. __Top-level current-state sections are never moved and never folded.__ They stay in
   their original relative order and at their original heading level. They are the
   answer to "who or what is this" and the reason the note exists. This protects a
   current-state section that stands on its own; a current-state section nested inside
   a dated entry is part of that entry and travels with it under rule 2. A dated entry
   nested inside a top-level current-state section stays with its parent: the parent's
   protection covers its whole subtree. Compaction never reaches into a current-state
   container to fold its children.
2. __A dated entry travels whole.__ Everything nested beneath it moves or folds with
   it, including any current-state sections nested beneath it, which are part of the
   entry rather than independent, whatever the child headings look like and whatever
   markers they carry. Never promote a dated child out of a dated parent: it severs
   the context that made it intelligible.
3. __Handling markers split History bullets__, but never override 1 or 2.

__Fold rules.__

1. Classify every section as a dated entry or current state, per the definitions. When a
   heading's date cannot be resolved confidently, or when you cannot confidently tell
   whether a section records a moment or states a present fact, treat the section as
   current state and leave it alone.

   __Resolving imprecise dates, biased toward keeping.__ A heading with no year inherits
   the year from the nearest surrounding dated entry that carries a year, in either
   direction, or from the note's most recent dated entry if there is none. A heading
   with month precision is treated as the last day of that month. Every one of these
   leans toward keeping content verbatim, which is the safe direction for a lossy
   operation.

2. Dated entries newer than `WORKLOG_COMPACT_KEEP_DAYS` (default 60) move under
   `## Recent`, newest first, with their heading text and heading level unchanged and
   their nested children intact. Do not demote or renumber headings: a `##` entry stays
   a `##` entry under `## Recent`.

   __Why 60 and not 90.__ Measured against the three largest People notes on 2026-08-06,
   a 90-day window did almost nothing, because this vault's mass sits in the last three
   months: it folded 0 sections on a 335-line note, 5 on another 335-line note, and 6 of
   49 dated sections on a 1,536-line note. The 60-day boundary is where the previous
   month's content becomes foldable on all three. Treat the default as a starting point
   rather than a rule: a note whose content is concentrated in one dense month has a
   cliff rather than a gradient, so check what a window actually folds before running it,
   and say so if the answer is nothing.

   __A shorter window is more aggressive, not just more effective.__ This is a lossy
   operation, and content two months old can still be live: an entry describing a
   conversation that has been deferred is not history yet. When the note is about an
   unresolved situation rather than closed work, lengthen the window or leave it alone.
   The threshold check is `WORKLOG_COMPACT_LINES`, not this one; a note being large is
   not evidence that its content is old.

3. Dated entries older than the window fold into `## History` bullets, newest first.

   __What a fold preserves:__ dates, decisions, status changes, facts that changed,
   every `[[wiki-link]]`, and every handling marker together with any stated confidence
   boundary. __What a fold drops:__ verbatim quotes, meeting play-by-play, and detail
   that only supported a conclusion already stated.

   __Group by theme, split by marker.__ Prefer grouping several entries into one
   thematic bullet; themes read better and compress harder. An entry's handling-marker
   set is the union of the markers on its own heading and on every heading nested
   beneath it. A `(vault-only)` entry containing an `(ULTRA-CONFIDENTIAL)` child has
   the set `{vault-only, ULTRA-CONFIDENTIAL}` and cannot share a bullet with a plain
   `(vault-only)` entry. Only entries whose handling-marker sets are __identical__ may
   share a bullet, and that bullet carries exactly that set. An entry marked
   `(vault-only)` and one marked `(vault-only, HIGH SENSITIVITY)` do not share a bullet
   even though one set contains the other, and an unmarked entry never shares a bullet
   with a marked one. Splitting costs a little readability; merging would relabel
   content its author deliberately marked, and this note's author marks an entry
   `surfaceable` precisely so it can leave the vault.

   Losing a handling marker is not compression, it is a disclosure risk. The marker is
   the only record in the note that the content is restricted, and `/worklog search`
   reads People notes directly, as does anyone opening the vault. Once it is gone
   nothing downstream can know the content was ever marked.

4. `## Recent` and `## History` go at the end of the note, after the last current-state
   section, in that order.

5. If the note already has `compacted:` set, existing `## History` bullets are
   __immutable__: do not re-fold or re-summarize them. A new fold is added as its own
   bullet even when it continues a theme an existing bullet already covers, because
   re-summarizing summarized text degrades it a little more on every pass. The
   retention window is relative to today, not to the previous compaction, so entries
   that have aged past it since the last pass move from `## Recent` into `## History`
   now.

__Show the fold before writing it.__ Present the proposed `## History` bullets verbatim,
since those are what replaces content, plus a plain list of the headings moving to
`## Recent` and the headings staying put. Do not paste the `## Recent` content itself:
nothing there is being given up, it is moving unchanged. Do not substitute a summary for
the History bullets, which are exactly the thing the user needs to see before agreeing to
lose the detail behind them. Wait for approval before touching the file. If either gate
then finds a problem, a dropped link target or an unexplained vanished heading, revise
the proposal, show the revised History bullets again, and wait for approval again.

__An approval covers the exact bullets the user was shown, and nothing else.__ The moment
a bullet changes, for any reason, the approval you were holding is void. Show the new
bullets and stop. Concretely: __never revise and write in the same turn.__ Finding the
problem yourself, fixing it, and writing because the gates now pass is the specific
failure here - the user ends up with bullets they never read, and the fact that the
revision was an improvement is beside the point. Measured on the eval fixture, this is
what a capable model does by default: it caught a dropped `[[wiki-link]]`, revised
correctly, and wrote in the same turn on the earlier approval.
Re-run both comparisons against the revised proposal. Repeat until the user has approved
the bullets they are actually getting, the heading comparison is clean, and either the
link comparison is clean or they have explicitly confirmed the specific link targets that
will be lost, then write. Silence is not confirmation, and a target or heading dropped
without being named to the user is never acceptable.

__Link preservation is a hard gate, not a warning.__ A fold that drops `[[wiki-links]]`
deletes graph edges, and nothing else in the vault will notice: the `missing_links` audit
check only finds unlinked mentions in recent weekly files, not edges that vanished from a
People note. Before writing, capture the canonical link targets. Both the link gate and
the heading gate below run against the same materialized proposal, so create it first and
note its path:

```bash
PROPOSED="$(mktemp)"; echo "$PROPOSED"
```

Write the proposed full note body to the literal path this prints before running either
gate, and delete it only after both have run. Shell variables set in one command do not
survive into the next, so substitute that literal path everywhere `$PROPOSED` appears
below, in both the link comparison and the heading comparison, rather than trusting the
variable to still be set:

```bash
LB="$(mktemp)"; LA="$(mktemp)"
grep -o '\[\[[^]]*\]\]' "<note>" | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/|.*$//' \
  | sort -u > "$LB"
grep -o '\[\[[^]]*\]\]' "$PROPOSED" | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/|.*$//' \
  | sort -u > "$LA"
comm -23 "$LB" "$LA"   # any output = targets that would be lost
rm -f "$LB" "$LA"
```

The gate requires materializing the proposal to a temp file and running the identical
pipeline on it, never comparing by eye. Normalizing to the canonical target by stripping
everything after `|` is deliberate: rewording an alias while keeping the target is not a
lost edge. Any target present before and absent after must be reported and explicitly
confirmed by the user before the write happens. If they do not confirm, do not write.

__Every heading must survive too, unless you can name the bullet it moved into.__ The
link gate compares `sort -u`'d targets, so a whole section, its heading included, can
vanish clean, as long as its links happen to still be present elsewhere in the note. On
a note where the default window puts most of the note in `## Recent`, such as the
1,536-line `Ines Duarte.md`, the model is re-emitting roughly 1,380 lines
verbatim, and a silently truncated rewrite is exactly what the link gate cannot see. Run
the same comparison shape against headings, right after the link gate, against that same
materialized path:

```bash
HB="$(mktemp)"; HA="$(mktemp)"
grep -oE '^#{1,6} .*' "<note>" | sort > "$HB"
grep -oE '^#{1,6} .*' "$PROPOSED" | sort > "$HA"
comm -23 "$HB" "$HA"   # any output = a heading that would vanish
rm -f "$HB" "$HA" "$PROPOSED"
```

Every heading this prints must be one you deliberately folded into a named `## History`
bullet, and you must be able to say which bullet. Any other missing heading is
unexplained loss: content vanished that nobody chose to give up, unlike a dropped link,
so there is no confirmation path here. Fix the proposal and re-run both comparisons
before writing.

__Outputs:__

1. The rewritten note.
2. A real `summary:` in frontmatter, authored not derived. Compaction always writes one,
   unless the existing `summary:` itself contradicts the body, in which case report that
   alongside the other contradictions rather than silently replacing it.
3. `compacted:` set to today's date.
4. __A contradiction report.__ While holding the whole note, flag internal contradictions
   and claims that newer entries supersede. Report them; do not auto-fix. Frontmatter
   that disagrees with the body is the most common case and the most consequential.
5. A dropped-link report, empty in the normal case.
6. One log entry, via the helper shown below.
7. __Reconcile the line-count drop against what was folded before calling it done.__ A
   shrinking note is not by itself success: sum the pre-fold line counts of the
   sections that moved into `## History`, and the note's total drop must not exceed
   what those sections explain. If it drops by more than the folded sections account
   for, verbatim content vanished that no fold covers, and that is a failed compaction
   regardless of whether the result now lands under `WORKLOG_COMPACT_LINES`: do not
   report `compacted:` as done, say so in your summary and the log entry instead, and
   treat it the same as a heading-gate failure. Unlike a heading-gate failure, this check
   runs after the write, so the note is already on disk: tell the user it can be restored
   with `git -C '__VAULT_PATH__' checkout -- <note>`, which is exactly why the git-clean
   precondition exists. If the drop is fully accounted for but
   the note is still over the threshold, say so explicitly in your summary and in the
   log entry, with the before and after line counts and the threshold. Recommend a
   shorter `WORKLOG_COMPACT_KEEP_DAYS` for that note and ask whether to re-run with it.
   A note that is still oversized after compaction must not be reported as done:
   `compacted:` records that a pass happened, not that the note is now small.

Compacting more than one note in a session: run `/worklog sync` between them. When auto sync is on, each run's own sync does this. Each
fold should land as its own recoverable commit before the next compaction starts, or
the next note's precondition check finds this one's uncommitted dirt and stalls.

__A worked example of the cliff, measured 2026-08-06.__ `People/Nadia Okafor.md` is 853
lines and every one of its 29 dated headings falls between Apr 22 and May 29. At the old
90-day default only the three Apr 22 entries were outside the window: 44 lines folded and
the note stayed at 809, barely touched. At the 60-day default the cutoff crosses the whole
block at once and all 29 fold, 814 lines, leaving about 39. There is no setting between
those that folds a moderate amount, because the content is not spread across the window,
it is one month sitting on one side of it.

That is the check to run before compacting, not after: see what a window actually folds.
Nothing and almost-everything are both real answers, and the second one deserves saying
out loud before the write, because 814 lines becoming a handful of bullets is the largest
single act of summarization this command can perform on that note.

Log it either way:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' compact '<note path>' \
  '853 -> 809 lines, still over the 250 threshold; 3 dated entries folded to ## History' \
  'contradiction: frontmatter team says "Northwind Platform"; body records rename to Core Infrastructure' \
  'at KEEP_DAYS=60 all 29 dated entries fold instead (814 lines); confirm before re-running' \
  'links preserved: 76/76; headings accounted for: 3 folded, 0 unexplained'
```

which renders as:

```markdown
## [2026-08-06] compact | People/Nadia Okafor.md
- 853 -> 809 lines, still over the 250 threshold; 3 dated entries folded to ## History
- contradiction: frontmatter team says "Northwind Platform"; body records rename to Core Infrastructure
- at KEEP_DAYS=60 all 29 dated entries fold instead (814 lines); confirm before re-running
- links preserved: 76/76; headings accounted for: 3 folded, 0 unexplained
```

A note still over the threshold must not read as done, which is what rule 7 requires. But
the recommendation to shorten the window is a question to ask, not an instruction to
follow: on this note it is the difference between touching nothing and folding 95% of it.

__What this does not do:__ cross-note contradiction detection. Comparing claims across
all 400 notes means reading all 400 notes, which is the exact cost the scanners exist to
avoid. A note that contradicts itself is both the common case and the consequential one,
and that is what this catches. Say so plainly rather than implying broader coverage.

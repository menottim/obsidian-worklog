# `Threads/` and week-file retention

Loaded on demand from `SKILL.md` by `/worklog rollover` and `/worklog tidy`. Everything
either command needs about spilling history out of the week file is here.

__Why this exists.__ "Fold before you add" (see `### Processing raw input`) routes every
extracted fact into an existing item as a sub-item. That is correct - two items about the
same program in one week is worse - but it means the week file's growth all lands on the
one dimension nothing was measuring. Measured on `2026-W37.md`: 151 top-level items whose
title lines are 18.6 KB, carrying 2,020 sub-items totalling 925 KB. Item count held nearly
flat for four weeks (126, 136, 144, 151) while the file grew to 953 KB. The rule that keeps
item count flat is the rule that inflates sub-item volume, so it needs a counterweight, not
a repeal.

__The counterweight is that the week file is a live list, not a ledger.__ It holds the
items actually worked that week, each showing its newest few dated sub-items and a link to
its full history. Everything else lives in `Threads/`.

__Threads age out.__ Entries in a Thread that are older than `WORKLOG_COLD_DAYS_THREADS` (30 days)
move to `Cold/` verbatim, as `references/cold.md` describes. Spills into Threads are unaffected.
Rollover and tidy still write new dated entries to the Thread note as described here.

## Thread notes

One note per long-running item: `Threads/<slug>.md`, holding that item's full dated
history.

__Slug rules.__ From the item title: strip `[[wiki-link]]` syntax down to its display text,
lowercase, replace every run of non-alphanumeric characters with a single hyphen, strip
leading and trailing hyphens, cap at 60 characters at a hyphen boundary. On collision
append `-2`, `-3`. Same shape as `Meetings/` slugs, minus the date prefix, because a Thread
is not an event.

__Check for a near-duplicate slug before creating one.__ Several items name the same
program from different angles. Two Threads for what is really one item is "fold before you
add" failing one level down.

__Shape:__

```markdown
---
type: thread
title: "Build pipeline redesign review"
opened: 2026-07-14
last-active: 2026-09-08
status: live
week: "[[2026-W37]]"
programs:
  - "[[Build Pipeline]]"
people:
  - "[[Ana Lindqvist]]"
summary: "design review for the new build runner; decision owner and staffing still open"
compacted: null
---

# Build pipeline redesign review

## Context

- What this item is and where it stands now.
- The open ask, the owner, the date it is due.

## Sep 8, 2026 - still unresolved

- <verbatim sub-item text>

## Aug 12, 2026 - team migrating onto the new runner, Oct 1 deadline

- <verbatim sub-item text, nested children intact>
```

__Frontmatter:__

- `type`: always `thread`.
- `title`: the item title with wiki-link syntax stripped. The filename is a slug; this is
  what a human reads.
- `opened`: date of the oldest dated entry. `last-active`: date of the newest. When the
  item is not in the week file, `last-active` is what dormancy is judged on.
- `status`: `live` (in the current week file), `parked` (in `Backlog.md`), or `closed` (the
  item completed; the Thread stays as the record).
- `week`: wiki-link to the week file currently carrying it. Present only when `status: live`.
- `programs`, `people`: extracted from the body by the `## Frontmatter Auto-generation`
  rules. __These are the displaced graph edges.__ When sub-item mass leaves the week file,
  the `[[wiki-link]]` targets inside it leave too, and this is where they land. A Thread
  without them is a spill that quietly deleted edges.
- `summary`: one line, present tense, under about 120 characters. Same convention as People
  and Program notes.
- `compacted`: `null` until `/worklog compact` folds the note.

__A Thread is not an entity and does not go in `cross-link-index.sh`.__ Threads are
per-item logs; People and Programs are the things items are about. Putting thread titles
into the alias reducer would add surface forms that are all ambiguous against the programs
they name. Link a Thread explicitly, never by alias resolution.

__A Thread does not replace or absorb a Program note.__ The Program note says what the
initiative is and where it stands; the Thread is the dated log of one worklog item. An item
about a program links both. Do not migrate a Program note's narrative into a Thread, and do
not promote a Thread to a Program page - __What earns a page__ in `references/meetings.md`
is deliberately strict and this does not change it. Threads exist precisely so history has
somewhere to go that is not a Program page.

__Threads are built to be compactable.__ A `## Context` current-state section plus
`## <Mon D, YYYY> - <label>` dated entries is exactly the shape `references/compact.md`
classifies: rule 1 protects `## Context`, rule 2 travels each dated entry whole, and
`## Recent` / `## History` go at the end. This is not incidental. A Thread grows without
bound the same way the week file did, and the only reason it is safe to move mass into one
is that `/worklog compact` can then hold it. Never write a Thread's history as flat bullets
under one heading; that shape is uncompactable, which is the mistake that made a week file
impossible to compact in the first place.

## What carries forward, per item

Two settings, because measured on `2026-W37.md` neither alone is sufficient:

- `WORKLOG_WEEK_KEEP_SUBS` (default 2) - the newest dated sub-items to keep in the week
  file, per item.
- `WORKLOG_WEEK_DORMANT_DAYS` (default 14) - an item with no dated sub-item newer than this
  is dormant and parks.

__Why both.__ A day window alone does not work on this vault. Sub-items dated within 7 days
still total 100 sub-items and 47 KB; within 14 days, 521 and 240 KB. The mass sits in the
recent past, the same cliff `compact.md` documents for `People/Nadia Okafor.md`, so the
window is a switch rather than a dial. A count cap alone would truncate a genuinely hot item
and keep three stale sub-items on a cold one. So the window decides which items are live and
the cap decides how much of a live item shows.

__Why 2.__ Measured on the W37 spill, which kept 20 live items: keeping 2 gives a 28 KB
body, keeping 3 gives 45 KB. This vault's sub-items average about 600 bytes, so each extra
kept sub-item costs roughly 12 KB across a live list, and 3 puts a normal week over the
40 KB gauge threshold on its own. 2 plus rule 3 is enough in practice: the newest status,
its predecessor, and every open obligation regardless of age.

The number is a function of how long sub-items are. If they get shorter, raise it.

__Per live item, in order:__

1. Keep the title line verbatim, including its priority and status marker.
2. Keep the newest `WORKLOG_WEEK_KEEP_SUBS` dated sub-items verbatim, newest first, with
   their nested children intact. A sub-item travels whole - never promote a nested child out
   of its parent, for the same reason `compact.md` rule 2 forbids it.
3. Keep, in addition and regardless of date, any sub-item that states an __open action or an
   unmet commitment__ - a line that contains `⚠️`, `__Action:` (both `__Action:__ <text>` and
   `__Action: <text>__`), `Owed:`, or `__<name> committed`, anywhere in the line or in its
   nested children. These markers are examples: any line that states an open obligation
   counts, bolded or not (`owes`, `will send`, `to follow up`). These are the reason the item is still on the board. Dropping one
   below the fold turns a live obligation into history, which is the one failure mode this
   whole mechanism must not introduce. Bias toward keeping, the same direction every
   ambiguous case in `compact.md` leans.
4. Keep every undated sub-item, unless it is a condensed-history bullet (see below). An
   undated line has no evidence it is old, and guessing is how facts vanish.
5. Add one final sub-item: `  - Full history: [[Threads/<slug>|<N> earlier entries]]`.
6. Everything not kept becomes a `## <Mon D, YYYY> - <label>` dated entry in the Thread
   note, newest first, __verbatim__. A spill is a move, not a summary. Summarizing is
   `/worklog compact`'s job and it runs on the Thread later, under its own approval gate.

An item with `WORKLOG_WEEK_KEEP_SUBS` or fewer sub-items has nothing to displace and gets no
Thread note. Do not create an empty Thread; `audit` will report it as an empty stub forever,
which is why __What earns a page__ is strict about Programs.

Undated sub-items that do move go under `## Context` as bullets, never under an invented
date. `2026-W37.md` alone carries 469 undated sub-items; dating them by guess is worse than
leaving them undated.

## Dormancy and parking

__An item is dormant when it has a dated sub-item, and the newest one is older than
`WORKLOG_WEEK_DORMANT_DAYS`__ (default 14), counted from the new week's Monday. Not "no
update this week" - one quiet week is normal and re-parking an item every other week churns
the file. Two is a signal.

__An item with no dated sub-item at all is not dormant.__ It is unmeasured, and the two read
the same to a date check while meaning opposite things: a freshly added item and an item
nobody has touched in three months both have zero dates on them. Parking on that is a guess,
and it guesses against a brand new item. Leave it live and let it acquire a date. The same
reasoning as rule 4 keeping undated sub-items: absence of a date is not evidence of age.

Dormant items park in `Worklogs/Backlog.md`, which already exists for exactly this and
already carries the convention on about 45 items:

```markdown
- **P2** 🔁 Parked - Log retention policy review ([[Jamie Ortega]] proposal)
  - Long-term retention posture; surface when a decision is needed; parked from [[2026-W19]] (May 4)
```

Reuse it exactly. No new state, no new file, no new status marker.

__To park an item:__

1. Write its Thread note first, and verify it (see __Ordering__ below).
2. Set the Thread's `status: parked` and remove its `week:` key.
3. Add one entry to `Backlog.md`: the title verbatim with its status changed to `🔁 Parked`,
   plus __exactly two sub-items__ - its newest dated sub-item verbatim, and
   `  - Parked from [[<week>]] (Mon D). Full history: [[Threads/<slug>]]`. Two, not the full
   stack: parked items today keep everything they accumulated, which is how `Backlog.md`
   becomes the next runaway file.
4. Remove the item from the week file.

__To wake an item__ - it is worked again, or a pull or paste produces a fact about it - move
the title back into the week file, set the Thread's `status: live` and `week:`, keep the
newest `WORKLOG_WEEK_KEEP_SUBS` entries from the Thread as sub-items, and remove the
`Backlog.md` entry. If the warm Thread has fewer entries than that, read the newest from its
cold files per `references/cold.md`. Waking is not a new command; it is what `add`, `review`, `pull` and
__Processing raw input__ do when the item they are folding into is parked. __Check
`Backlog.md` before creating a new top-level item__, or a woken item becomes a duplicate of
itself.

Use the dated-progress regex already in `stuck_items()` (`scripts/audit-scan.sh`),
`\([A-Z][a-z][a-z] [0-9]{1,2}\)`, as the "has recent dated progress" test rather than
writing a second one.

## Ordering, and why it is not negotiable

Every file in `Archive/` has zero `^- \*\*P[012]\*\*` lines. The entire body of
`Archive/2026-W36.md` is `0 items completed, 37 items rolled forward to [[2026-W37]] (...)`.
Archiving keeps only completed items as bullets, so the current week file is the __sole
surviving copy__ of every open item's history. Pruning it before the Thread note exists and
has been verified does not lose detail, it deletes the only copy.

So, per item, in this order and no other:

1. Write the Thread note.
2. Verify it - re-read the Thread, confirm the spilled text is present, then run both gates
   below.
3. Only then edit the week file.

Never batch step 3 ahead of step 2 for later items in the same batch, and never write a
Thread and prune its item in the same edit.

__Preconditions, mirroring `compact.md`:__ the vault must be under git and clean. Run the
same check `compact.md` opens with. If the vault is not under git, __do not spill__ - say
there is no undo and stop, offering nothing further. If it is dirty, offer `/worklog sync`
and re-run the check. When auto sync is on, run `sync.sh --auto` instead and continue on exit 0, 3
or 4, then re-run the clean check; stop on 1 or 2 (see `## Auto Sync` in `SKILL.md`).

__Materialize the proposal before gating it.__ Write the proposed new week-file body to
`<PROPOSED_DIR>/week.md` and each proposed Thread to `<PROPOSED_DIR>/<slug>.md` first. Shell
variables do not survive between commands, so substitute the literal path this prints:

```bash
PROPOSED_DIR="$(mktemp -d)"; echo "$PROPOSED_DIR"
```

__Gate 1: link preservation.__ A spill that drops `[[wiki-link]]` targets deletes graph
edges and nothing downstream notices - `missing_links` finds unlinked mentions, not edges
that vanished.

```bash
LB="$(mktemp)"; LA="$(mktemp)"
grep -o '\[\[[^]]*\]\]' '__VAULT_PATH__/Worklogs/<week>.md' \
  | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/|.*$//' | sort -u > "$LB"
cat <PROPOSED_DIR>/*.md '__VAULT_PATH__/Worklogs/Backlog.md' \
  | grep -o '\[\[[^]]*\]\]' \
  | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/|.*$//' | sort -u > "$LA"
comm -23 "$LB" "$LA"   # any output = targets that would be lost
rm -f "$LB" "$LA"
```

Any target present before and absent after must be reported and explicitly confirmed by the
user before the write. If they do not confirm, do not write.

__Gate 2: dated-fact survival.__ Gate 1 compares `sort -u`'d targets, so a whole sub-item
can vanish clean as long as its links appear elsewhere - the same blind spot the heading
gate covers in `compact.md`. A spill is a verbatim move, which makes a stricter gate
available than compaction can use: every sub-item line must still exist somewhere in the
union.

```bash
SB="$(mktemp)"; SA="$(mktemp)"
norm(){ sed -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/^#\{1,6\} //' -e 's/[[:space:]]*$//' \
        | grep -v '^$' | sort -u; }
grep -E '^[[:space:]]+- ' '__VAULT_PATH__/Worklogs/<week>.md' | norm > "$SB"
cat <PROPOSED_DIR>/*.md '__VAULT_PATH__/Worklogs/Backlog.md' | norm > "$SA"
comm -23 "$SB" "$SA"   # any output = a dated fact that would vanish
rm -f "$SB" "$SA"
```

This must print nothing. Unlike a dropped link there is __no confirmation path__: a sub-item
missing here is content nobody chose to give up. Fix the proposal and re-run both gates.

The one legitimate exception is a condensed-history bullet being split into several dated
entries (see below), which by construction is not verbatim. Name every such bullet to the
user with its replacement entries shown, and approve them individually.

__When to stop for approval, and when not to.__ This is not the same answer as
`compact.md`, and the difference is that compaction rewrites content while a spill only
moves it:

- __`/worklog rollover` applies retention without prompting.__ Run the gates, write the
  Threads, prune the week file, then report what moved: items spilled, sub-items moved and
  their date range, items parked. The safety here is the ordering and the two gates, not a
  human reading a list. Rollover is a weekly routine over every open item, so a per-item
  prompt would mean twenty approvals every Monday, and the realistic outcome of that is the
  command not being run. The old behavior of carrying everything forward is what produced a
  953 KB week file, so friction on this path has a known cost.
- __`/worklog tidy` stops for approval__, per item, largest first. Tidy is an ad-hoc
  mid-week call on a specific item rather than a scheduled pass, so the judgment of whether
  this item should shed history now is the user's.
- __A condensed-history split always stops for approval__, named individually with its
  replacement entries shown, on either path. That one is not a verbatim move: it re-shapes
  text, which is the thing approval exists for.
- __A gate failure always stops__, on every path. If either gate flags a line, show it
  verbatim and wait, whatever command you are in.

Where you do stop: __never revise and write in the same turn__. Fix the proposal, show it
again, and wait again. An approval covers the exact content the user was shown and nothing
else. This is the specific failure `compact.md` measured a capable model committing by
default.

__After the write, reconcile.__ The week file's byte drop must not exceed the byte total of
the sub-items that moved plus the sub-items that parked. If it drops by more than that,
content vanished that no spill accounts for: say so, do not report the spill as done, and
tell the user it is restorable with
`git -C '__VAULT_PATH__' checkout -- Worklogs/<week>.md`, which
is exactly why the git-clean precondition exists.

Delete `<PROPOSED_DIR>` only after both gates and the reconciliation have run.

## Condensed-history bullets

`2026-W37.md` carries 28 bullets of the form `Earlier context (Jun 2 - Jul 27), condensed at
the Aug 26 tidy (full detail in git history)`, totalling 36.9 KB. The longest is 3,320 bytes,
one unbroken paragraph with five `__bolded__` inline sub-headings covering about eight
distinct dated topics.

__`(full detail in git history)` is not a pointer, it is a dead end.__ Nothing inside
Obsidian can follow it: no backlink, no search hit, no click. It records that detail existed
and makes it unreachable from the tool the vault is read in.

When you meet one, split it and replace the pointer:

1. Split at the inline `__bold__` sub-headings and the dated clauses inside them, one
   `## <Mon D, YYYY> - <topic>` Thread entry per distinct dated topic. Date each entry from
   the dates in its own text, not from the bullet's range. Where a clause carries no date,
   use the nearest date in the same clause and say `(approximately)` in the entry body - the
   same imprecise-date resolution `compact.md` uses, biased toward keeping.
2. Preserve every `[[wiki-link]]` and every handling marker - `vault-only`, `confidential`,
   `🔒`. The longest bullet contains `(Mar 3, vault-only)`. Losing a marker is not
   compression, it is a disclosure risk, and `compact.md`'s reasoning applies verbatim: once
   it is gone, nothing downstream can know the content was ever marked. A marker on one
   clause travels to the entry that clause becomes, and to no other.
3. Never re-condense. These bullets are already one lossy pass; a second pass on summarized
   text degrades it again, the same reason `compact.md` rule 5 makes existing `## History`
   bullets immutable.
4. Do not write a new `(full detail in git history)` anywhere, ever. If detail must move, it
   moves to a Thread and the week file links to it.

## Logging

Append through `log-append.sh`, never by editing the log directly. Two ops:

- `spill`, target the week file or the Thread path. Record items spilled, sub-items moved
  and their date range, Threads created versus appended, bytes before and after, and both
  gate results.
- `park`, target `Worklogs/Backlog.md`. Record how many items parked, from which week, and
  the Thread each points at.

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' \
  spill 'Worklogs/2026-W37.md' \
  '9 items spilled, 412 sub-items moved (Jun 2 - Aug 18); 9 Threads created, 0 appended' \
  '953,425 -> 781,004 bytes; drop of 172,421 accounted for by 172,421 bytes of moved sub-items' \
  'links preserved 512/512; dated sub-items 412 moved, 0 unexplained'
```

A spill that failed a gate gets an entry saying so, not a silent retry.

## Why there is no week-file `compact` path

`compact` classifies `##`-level sections into `## Recent` and `## History`. A week file has
one `#` and bold subgroups by spec (see `## Weekly File Structure`), so there are zero
classifiable sections and the algorithm has no input.

More to the point, a week file is created fresh every Monday and archived at the next
rollover, so its size is entirely determined by what rollover copies forward. A People note
accumulates across years with no equivalent reset, which is why it needs compaction. Get
rollover's retention right and there is nothing left for a week-file fold to do. `tidy`
covers the growth that happens between Mondays, reusing this file rather than duplicating a
fold algorithm. Compaction still gets its job one level down, on the Threads, which is the
whole trade.

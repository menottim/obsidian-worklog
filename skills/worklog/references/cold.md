# Cold storage

Loaded on demand from `SKILL.md`. Everything needed to move old history out of a note, and to
answer questions that may reach into that history, is here.

__Purpose.__ Cold storage is lossless tiering. Old dated entries in `People/`, `Programs/` and
`Threads/` move __verbatim__ to `Cold/`. Nothing is summarized. The __warm note__ is the note in
`People/`, `Programs/` or `Threads/`. It keeps four things: its current state, its recent
entries, its pinned entries and a one-line-per-entry index that points at the cold files. The
__cold files__ are the files in `Cold/`. A script, the __gate__ (`cold-gate.sh`), checks that each
move lost nothing. Lossy compaction (`/worklog compact`) loses context that later questions
need. Note size is a retrieval problem, not a storage problem. To fix it, read less by default
and keep a path to all history.

## Windows and scope

Each folder has its own window, measured from today. Set the window with these environment
variables:

| Folder | Variable | Default |
| --- | --- | --- |
| `People/` | `WORKLOG_COLD_DAYS_PEOPLE` | 60 |
| `Programs/` | `WORKLOG_COLD_DAYS_PROGRAMS` | 60 |
| `Threads/` | `WORKLOG_COLD_DAYS_THREADS` | 30 |

An entry moves when its date is older than the window. Only `People/`, `Programs/` and
`Threads/` are in scope. `Meetings/`, `References/`, `Summaries/` and `Archive/` are records and
never move. Worklog week files follow the retention rules in `threads.md`.

## What moves

- A __dated entry__ is a `##` section whose heading contains a date. The date can be leading,
  trailing or in parentheses (`## Jul 30, 2026 - ...`, `## Sync notes (Sep 1, 2026)`). The date
  forms are:
  - `Mon D, YYYY`
  - `Mon D` with no year (the year is the most recent past occurrence)
  - `Mon YYYY` (dated as the last day of that month)
  - ISO `YYYY-MM-DD`

  A range is dated by its end day. The scanner uses the same rules. A dated entry moves whole,
  with everything nested beneath it, up to the next heading of the same or higher level.
- Inside an undated `##` section that is not a current-state section (for example
  `## Meeting Notes` holding `### Jul 2, 2026 - 1:1`), each dated `###` subsection is a dated
  entry. It moves whole, up to the next `###` or higher heading. The container `##` heading line
  stays warm. In the cold file, the moved `###` sections go under a
  `## <container heading>` line.
- A `## History` section of already-folded bullets (from `/worklog compact`) moves whole as one
  unit and goes to `folded-history.md`. Its bullets are immutable, so pins do not split it. Two
  rules decide when it moves:
  - It stays warm while any of its bullets carries an open-obligation marker (see Pins).
  - Otherwise it moves whole once the section is older than the window. The newest dated bullet
    decides the age. If the bullets are undated, the note's `compacted:` date decides.

`cold_candidates` (the audit scanner) counts these bytes before pins, so a candidate can turn out
to be all pinned. In that case the move leaves the note untouched and reports it as skipped. Do
not try to detect pins in the scanner.

After a move, a warm line can refer to moved content by position ("see below", "recap below",
"as above", "detail under X below"). Leave the line unchanged (the gate requires it). The move
report lists every such warm line so the user can fix it.

## What never moves

- Current-state sections, including their `###` children. The names are exactly: Role, Context,
  Current Focus, Current State, Status, OOO, 1:1 Doc and Members. A heading matches when it is
  the name alone, or the name followed by `(`, `-` or `:` (case-insensitive). A date in that
  suffix does not change this: `## Current State (May 4, 2026)` never moves.
  `## Role Definition Landed (May 1, 2026)` is not a current-state section.
- Undated sections stay, except that dated `###` children of an undated non-current-state `##`
  container move (see above).
- Frontmatter and the H1.
- The structural headings `## Recent` and `## History` themselves. Keep the heading line in the
  warm note. If its section is now empty, leave it empty.
- Pinned entries (below).

## Pins

A pinned entry stays warm regardless of age. Report each pin and the reason. Pin an entry when
it matches one of these conditions:

- It contains an open action or unmet commitment: a line with `⚠️`, `➡️`, `__Action:`,
  `Action on __USER_NAME__`, `Open on __USER_NAME__`, `Actions on`, `Owed:`,
  `__USER_NAME__ action`, or an unchecked `- [ ]`. These markers are examples. Any line that
  states an open obligation pins, bolded or not, with or without the user's name: `owes`,
  `to do`, `Action:`, `Actions.`, `next step`, `open ... action`. `⚠️` pins too. Over-pinning is
  accepted because it is the safe side.
- It has a `__<name> committed` line that names a deliverable or date. The warm note's
  current-state sections or later entries do not show it as delivered. A bare past commitment
  does not pin.

A pinned item is resolved, and does not pin, when the note shows it done in any of these places:

- a later entry
- `## Context`, `## Status` or `## Current Focus`
- a `✅`, `done`, `resolved` or `closed` marker on the same item in the same entry

A marker resolves an item only when it means completed. Negated or conditional uses ("not
done", "once resolved") do not count. Each move re-evaluates pins, so an entry pinned last time
can move this time.

Also pin an entry when it matches one of these conditions:

- It is about the person's growth, comp, retention discussion, 360 or talent assessment (People notes
  only). Pin only when the heading or first bold lead-in names one of these, or it is the
  entry's main subject. A passing mention does not pin.
- It carries `pin` or `pinned` as a tag or frontmatter key, or in its heading as a whole word
  (not inside other words such as "unpinned").

## Layout

Cold files live at `Cold/<Folder>/<Note name>/<YYYY>-Q<n>.md`. Each file holds one calendar
quarter of the entries' dates (Jul-Sep is Q3, Apr-Jun is Q2). A moved `## History` goes to
`folded-history.md`. Example: `Cold/People/Jordan Rivera/2026-Q3.md`.

Cold file frontmatter:

```yaml
---
type: cold
parent: "[[Jordan Rivera]]"
period: 2026-Q3
moved: 2026-10-07
entries: 7
---
```

Body: `# <Note name>: cold storage <period>`, then the moved sections verbatim, newest first,
headings unchanged. Container `###` entries go under their `## <container heading>` line, one
entry per `###`.

The warm note gets a final section:

```markdown
## Cold storage

Entries older than <cutoff date, Mon D, YYYY>, moved verbatim. Read on demand.

- Jul 16, 2026 - 1:1: onboarding plan, roadmap review → [[Cold/People/Jordan Rivera/2026-Q3|2026-Q3]]
- Sep 1, 2026 - Program team sync on the vendor mapping → [[Cold/People/Jordan Rivera/2026-Q3|2026-Q3]]
```

The date is the window cutoff for that move (today minus the folder window). A later move can
add entries to an existing index. In that case, do not change the existing "Entries older than"
line, because the gate requires every base line to survive. Add a new line right below it:
`Later move: entries older than <cutoff date, Mon D, YYYY>, moved <YYYY-MM-DD>.`

Write one line per moved entry, newest first. Same-day entries keep file order. For
`folded-history.md`, write one line per History bullet and build it the same way from the
bullet.

## Index label rules

Never write a new summary: every label is copied text. The label must name the __topic__,
because a later query routes on it. Build it in order:

1. If the heading has a label, use it.
   - For a leading date (`## Jul 16, 2026 - 1:1: onboarding plan...`), the label is the text after
     the date.
   - For a trailing or parenthesized date (`## Vendor sync (Sep 1, 2026)`), the label is the
     heading text without the date. Put the date at the front of the index line.
   - If the label names only a meeting type (1:1, sync, check-in, standup, meeting, review, call,
     recap) and no subject, it is weak. Append the first clause of the following text as in
     step 3, regardless of word count.
2. Otherwise take the entry's first `__bold__` lead-in phrase, verbatim. A handling marker is not
   a lead-in. Skip to the next phrase and keep the marker on the line. If the heading label or
   the lead-in is 4 words or fewer, append the first clause of the following text the same way
   as step 3 (verbatim, cap about 140 characters, never cut inside links or backticks).
   "Following text" means the text after the lead-in, so the lead-in is not repeated.
3. If that lead-in is only a date or time (`__May 26, 2026__`, `__Apr 29, 2026 1:1__`), or there
   is no lead-in, append the first clause of the text after it, verbatim: up to the first `.` or
   `;`, capped at about 140 characters at a word boundary. Ignore a `.` inside a link or URL when
   you find the first clause.

When you cut text, never stop inside a `[[...]]`, `[...](...)` or backtick span. End before the
span starts or after it closes. If the cut falls just before a link, drop a dangling opening
parenthesis. Copy a handling marker (`🔒`, `sensitive`,
`vault-only`, `ULTRA-CONFIDENTIAL`, `confidence-bound`) onto the index line if it appears
anywhere in the moved entry, not only in the heading or lead-in.

## Order: copy, verify, delete, gate

Precondition: the vault git state is clean, so the gate can compare against HEAD. Check this
once at the start of a run, not per note. Move each note at most once per run. A standalone
`/worklog cold` ends with a local commit (no push), message `worklog cold <date>: <n> notes`,
like rollover.

The gate compares frontmatter to HEAD. A cold move must therefore run on a note whose
frontmatter is unchanged since the last commit. Inside `/worklog rollover`, the cold move runs
__before__ the Thread spill step, because that step edits Thread frontmatter. The cold move runs
on a clean vault. Step 3 ends with a local commit of the cold moves (no push, message
`worklog cold <date>: <n> notes`), so the Thread spill also starts clean.

1. Write the cold file(s).
2. Re-read them and check that every moved section is present verbatim.
3. Only then remove the sections from the warm note and add the index.
4. Run the gate:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/cold-gate.sh '__VAULT_PATH__' '<note>' '<cold file>' ...
```

The gate must print `PASS`. It checks that:

- the note's frontmatter is unchanged.
- every non-blank base line survives verbatim in the note plus cold files, with the same line
  counts (a dropped duplicate fails).
- the prior content of an existing cold file is intact.
- every wiki-link target survives.
- every cold file is linked from the note and has a `parent:` equal to the note.

The gate refuses a note that is already committed, unless `WORKLOG_COLD_BASE` names the
pre-move revision. The gate does not check order. On `FAIL`, fix the problem and run the gate
again. If you cannot fix it, restore the note with
`git -C '__VAULT_PATH__' checkout -- '<note>'`, delete the cold files and report.

__A note that already has a `## Cold storage` section.__ Do these steps:

1. Add the `Later move:` line below the existing cutoff line.
2. Append the new index lines below the existing ones, newest first.
3. Add the entries to the right quarter file. Create the file, or append to it, and keep
   newest-first order.

When you append to a quarter file:

- Add the new count to `entries:`.
- Set `moved:` to the latest move date.
- Put container `###` entries under the existing `## <container>` heading, one entry per `###`.

Do not rewrite existing index lines or cold entries.

Example after two moves: the cutoff line, then `Later move:` lines in move order, a blank line,
then index lines newest first.

```markdown
## Cold storage

Entries older than Jul 9, 2026, moved verbatim. Read on demand.
Later move: entries older than Aug 8, 2026, moved 2026-10-07.
Later move: entries older than Sep 7, 2026, moved 2026-11-06.

- Aug 2, 2026 - Vendor sync: renewal terms → [[Cold/People/Jordan Rivera/2026-Q3|2026-Q3]]
- Jul 16, 2026 - 1:1: onboarding plan → [[Cold/People/Jordan Rivera/2026-Q3|2026-Q3]]
- Jun 12, 2026 - Hiring loop debrief → [[Cold/People/Jordan Rivera/2026-Q2|2026-Q2]]
```

## Logging

After the gate passes, log through the helper (op `cold`, target the note):

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' \
  cold '<note>' '<n> entries moved' 'warm <before> -> <after> bytes' 'gate: PASS'
```

## Lookup ladder

Applies to any question answered from the vault: status, search, ad hoc questions. Go only as
deep as the question needs. Record each file opened and its size.

1. __Warm.__ Read the relevant notes, excluding `Cold/`. Draft an answer. Do not open cold files
   "to be thorough".
2. __Cold index, always scanned.__ The `## Cold storage` section is part of the warm note. Scan
   every index line, even when step 1 produced an answer. A warm entry on the same topic does
   not prove it is the entry the question means: an older decision or a different event can be
   in cold storage. If an index line matches the question's subject, go to step 3 for that line
   and reconcile. Answer from the entry the question asks about. Mention the other entry if both
   are relevant.
3. __Targeted cold read, automatic.__ Open a cold file without asking when one of these is true:
   - The question names a date or period older than the window.
   - An index line clearly matches the subject.

   Budget: 30 KB of text actually read per question. Count the bytes of the sections or grep
   output you read, not the file size. Locate the section first (grep the date or a label
   phrase) and read only that section.
4. __Per-note keyword grep, automatic.__ If steps 1-3 did not answer it, grep only the cold files
   linked from the starting note for the question's distinctive terms (names, acronyms, nouns):
   `grep -i -n -C1`. The output counts toward the budget. Read a matching section in full if
   needed. No permission is needed because the grep stays inside one note's own history.
5. __Ask.__ If you still did not find the answer, or the next step would exceed the budget, stop
   and ask: `The answer may be in cold storage (<files>, <total KB>). Search it?` A "not found"
   answer always carries this question. An answer that infers absence also carries it ("nobody
   took it over", "it never happened", "no replacement was named"). Such an answer does not
   quote a line that says so. Absence that the notes do not state is a not-found answer.
6. __Subagent sweep__, only after a yes: a subagent searches all cold files and returns a cited
   answer.

## Why these rules

A pilot on a real private vault moved a 50 KB People note to about 16 KB warm, and the gate
passed. A 12-question retrieval test passed 12/12 after two rule fixes. The index-scan rule
(step 2) fixed a confident wrong answer. In that case a warm entry on the same topic hid an
older decision in cold storage. The per-note grep (step 4) fixed a topic that was missing from a
truncated index label. The label rules (topic names, copied text, no cuts inside links) came
from the same two failures.

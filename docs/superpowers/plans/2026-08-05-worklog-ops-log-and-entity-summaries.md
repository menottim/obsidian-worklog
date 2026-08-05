# Worklog Ops Log, Entity Summaries, and Filed Answers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the worklog skill an append-only operations log, one-line entity summaries behind an opt-in digest flag, and a way to file query answers back into the vault so explorations compound.

**Architecture:** Three independent additions to an existing Claude Code skill plugin. The skill is a single large `SKILL.md` prompt plus three read-only bash helper scripts that do O(vault) scans off-model and return JSON digests. This plan adds a fourth helper (the only write-capable one), extends one existing helper with an opt-in flag, and edits `SKILL.md` prose. No application runtime, no package manager, no build step.

**Tech Stack:** bash 3.2 (macOS system bash), `jq`, `awk`, `sed`, `grep`, `wc`. Tests are plain bash scripts with an `assert_eq` helper. Markdown for the skill body.

**Spec:** `docs/superpowers/specs/2026-08-05-worklog-ops-log-and-entity-summaries-design.md`

## Global Constraints

- **bash 3.2 only.** macOS ships bash 3.2.57 and the helpers must run under it. No `mapfile`/`readarray`, no associative arrays (`declare -A`), no `${var^^}`/`${var,,}`, no `&>>`. Use `while IFS= read -r` loops instead of `mapfile`. Existing helpers already follow this; match them.
- **Helpers take the vault path as the first positional argument.** Never read a vault path from the environment or hardcode one.
- **Exit code 2** for usage errors and for a missing or unusable vault directory, with a message on stderr prefixed by the script name. Exit 0 on success.
- **All JSON is emitted through `jq`**, never by string concatenation. `jq` handles escaping of quotes, backslashes, and unicode in vault content.
- **`log-append.sh` is the only write-capable helper.** `audit-scan.sh`, `cross-link-index.sh`, and `preferences-index.sh` stay strictly read-only.
- **`cross-link-index.sh` default output must remain byte-identical.** It runs on every vault write and is the hottest path in the skill. New fields appear only with `--with-summaries`.
- **`SKILL.md` and `references/*.md` are templates and must stay templates.** They contain 6 placeholder tokens (`__VAULT_PATH__`, `__USER_NAME__`, `__GIT_USER_NAME__`, `__GIT_USER_EMAIL__`, `__BACKUP_REPO_URL__`, `__SKILL_INSTALL_PATH__`). Never substitute real values into the repo. `setup.sh` does that at install time.
- **`__SKILL_INSTALL_PATH__` is the plugin ROOT.** Scripts are addressed as `__SKILL_INSTALL_PATH__/skills/worklog/scripts/<name>.sh`. Getting this wrong is the 5.8.1 bug.
- **Prose style in `SKILL.md`:** no em-dashes (use hyphens or rewrite), underscores for bold in conversational output (`__bold__`), asterisks for bold inside vault files (`**P0**`). Match the surrounding file.
- **Commit identity:** `git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" commit ...`. Do not configure identity globally.
- **Never push to the `upstream` remote.** `upstream` is the public repo `github.com/menottim/obsidian-worklog` and this work has not been scrubbed for it. `origin` (`git.netflix.net/mminutillo`) is the only push target.
- **Target version:** 5.11.0 in `.claude-plugin/plugin.json`, bumped once in the final task.

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `skills/worklog/scripts/log-append.sh` | Append one formatted entry to `Logs/YYYY-MM.md`, creating the month file with frontmatter if absent. The only write-capable helper. |
| `tests/log-append.test.sh` | Unit tests for the log helper: file creation, append, prefix format, body lines, exit codes. |
| `tests/fixtures/summary-vault/` | Small fixture vault exercising the three summary cases (declared, derived, none). Separate from `crosslink-vault` so existing assertions stay untouched. |
| `tests/fixtures/crosslink-default.golden.json` | Golden capture of `cross-link-index.sh` default output against `crosslink-vault`, proving the flag change did not alter the hot path. |

**Modified:**

| Path | Change |
|---|---|
| `skills/worklog/scripts/cross-link-index.sh` | Add `--with-summaries` flag; emit `summary` and `summary_source` per entity when set. |
| `tests/cross-link-index.test.sh` | Add golden-file regression assertion and the `--with-summaries` cases. Existing assertions unchanged. |
| `skills/worklog/SKILL.md` | New `## Operations Log` section; log call-outs in the command sections; `Logs/` in the Vault Layout and the `/worklog sync` allowlist; `--with-summaries` at query call sites; `summary:` in the People and Program note structures; rollup filing; new `/worklog file` command. |
| `skills/worklog/references/pull-flow.md` | Replace the `People/*.md` glob in the classify step with the digest call. |
| `evals/evals.json` | Amend eval 9 (pull idempotency) for the log entry; add eval cases for filing and log writes. |
| `.claude-plugin/plugin.json` | Version 5.10.1 to 5.11.0. |

---

### Task 1: `log-append.sh` helper

**Files:**
- Create: `skills/worklog/scripts/log-append.sh`
- Test: `tests/log-append.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `log-append.sh <vault> <op> <target> [body-line ...]`. Writes `<vault>/Logs/$(date +%Y-%m).md`. Creates the file with `type: log` / `month:` frontmatter and an `# Operations log YYYY-MM` heading if absent. Appends `## [YYYY-MM-DD] <op> | <target>` followed by one `- <line>` per body argument, then a blank line. Exit 0 on success, 2 on fewer than 3 arguments, on a missing vault directory, or on any write failure. Task 3 and the companion plan's compaction task both call it.

- [ ] **Step 1: Write the failing test**

Create `tests/log-append.test.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for log-append.sh. Each case runs against a throwaway vault.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="$HERE/../skills/worklog/scripts/log-append.sh"
FAILS=0

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

MONTH="$(date +%Y-%m)"
DAY="$(date +%Y-%m-%d)"

# --- creates the month file with frontmatter ---
V="$(mktemp -d)"
"$HELPER" "$V" pull '#infrasec-leads' '24 messages swept' >/dev/null
LOG="$V/Logs/$MONTH.md"
assert_eq "month file created"   "$([ -f "$LOG" ] && echo yes)" "yes"
assert_eq "frontmatter type"     "$(sed -n '2p' "$LOG")" "type: log"
assert_eq "frontmatter month"    "$(sed -n '3p' "$LOG")" "month: $MONTH"
assert_eq "entry prefix"         "$(grep -c "^## \[$DAY\] pull | #infrasec-leads$" "$LOG")" "1"
assert_eq "body line"            "$(grep -c '^- 24 messages swept$' "$LOG")" "1"

# --- appends without duplicating frontmatter ---
"$HELPER" "$V" compact 'People/Astha Singhal.md' '852 -> 210 lines' 'links preserved: 34/34' >/dev/null
assert_eq "one frontmatter block" "$(grep -c '^type: log$' "$LOG")" "1"
assert_eq "two entries"           "$(grep -c '^## \[' "$LOG")" "2"
assert_eq "multi body line 1"     "$(grep -c '^- 852 -> 210 lines$' "$LOG")" "1"
assert_eq "multi body line 2"     "$(grep -c '^- links preserved: 34/34$' "$LOG")" "1"
assert_eq "body order preserved"  \
  "$(grep -n '^- 852\|^- links' "$LOG" | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//' | awk '{print ($1 < $2) ? "ok" : "wrong"}')" "ok"

# --- greppable prefix contract ---
assert_eq "prefix grep works"     "$(cat "$V"/Logs/*.md | grep -c '^## \[')" "2"
rm -rf "$V"

# --- entry with no body lines ---
V2="$(mktemp -d)"
"$HELPER" "$V2" sync vault >/dev/null
assert_eq "no-body entry"         "$(grep -c "^## \[$DAY\] sync | vault$" "$V2/Logs/$MONTH.md")" "1"
rm -rf "$V2"

# --- exit codes ---
"$HELPER" >/dev/null 2>&1;               assert_eq "no-arg exit 2"      "$?" "2"
"$HELPER" /tmp pull >/dev/null 2>&1;     assert_eq "two-arg exit 2"     "$?" "2"
"$HELPER" /no/such/vault a b >/dev/null 2>&1; assert_eq "bad-vault exit 2" "$?" "2"

RO="$(mktemp -d)"; chmod 555 "$RO"
"$HELPER" "$RO" pull x >/dev/null 2>&1;  assert_eq "unwritable exit 2"  "$?" "2"
chmod 755 "$RO"; rm -rf "$RO"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'
```

- [ ] **Step 2: Run test to verify it fails**

```bash
chmod +x tests/log-append.test.sh
./tests/log-append.test.sh
```

Expected: every assertion fails, because `skills/worklog/scripts/log-append.sh` does not exist. The first lines will be shell errors about the missing helper followed by `FAIL:` lines.

- [ ] **Step 3: Write the implementation**

Create `skills/worklog/scripts/log-append.sh`:

```bash
#!/usr/bin/env bash
# log-append.sh <vault> <op> <target> [body-line ...] — append one entry to Logs/YYYY-MM.md.
# The only WRITE-capable helper in the skill. Monthly files keep the log bounded.
# The "## [YYYY-MM-DD] <op> | <target>" prefix is a contract: every consumer greps for it.
# bash 3.2; coreutils only.
set -euo pipefail

[ "$#" -ge 3 ] || { echo "log-append: usage: log-append.sh <vault> <op> <target> [body-line ...]" >&2; exit 2; }
VAULT="$1"; OP="$2"; TARGET="$3"; shift 3
[ -d "$VAULT" ] || { echo "log-append: vault dir not found: $VAULT" >&2; exit 2; }

DAY="$(date +%Y-%m-%d)"
MONTH="$(date +%Y-%m)"
DIR="$VAULT/Logs"
FILE="$DIR/$MONTH.md"

mkdir -p "$DIR" 2>/dev/null || { echo "log-append: cannot create $DIR" >&2; exit 2; }

if [ ! -f "$FILE" ]; then
  {
    printf -- '---\n'
    printf 'type: log\n'
    printf 'month: %s\n' "$MONTH"
    printf -- '---\n\n'
    printf '# Operations log %s\n\n' "$MONTH"
  } > "$FILE" 2>/dev/null || { echo "log-append: cannot write $FILE" >&2; exit 2; }
fi

{
  printf '## [%s] %s | %s\n' "$DAY" "$OP" "$TARGET"
  for line in "$@"; do printf -- '- %s\n' "$line"; done
  printf '\n'
} >> "$FILE" 2>/dev/null || { echo "log-append: cannot append to $FILE" >&2; exit 2; }
```

Note the two `printf --` uses: the format strings `---\n` and `- %s\n` both start with a hyphen and would otherwise be parsed as options.

- [ ] **Step 4: Run test to verify it passes**

```bash
chmod +x skills/worklog/scripts/log-append.sh
./tests/log-append.test.sh
```

Expected: `All tests passed`.

- [ ] **Step 5: Verify under system bash 3.2 explicitly**

```bash
/bin/bash --version | head -1
/bin/bash ./tests/log-append.test.sh
```

Expected: version reports 3.2.x, and the suite still prints `All tests passed`. If it fails here but passed in step 4, a bash 4+ builtin leaked in.

- [ ] **Step 6: Commit**

```bash
git add skills/worklog/scripts/log-append.sh tests/log-append.test.sh
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(worklog): log-append.sh helper for the monthly operations log"
```

---

### Task 2: Wire the operations log into `SKILL.md`

**Files:**
- Modify: `skills/worklog/SKILL.md` (Vault Layout around line 24-69; key paths around line 97-107; new section after `## Frontmatter Auto-generation`, before `## Commands` at line 669; `/worklog audit` at line 806; `/worklog sync` at line 1108-1134; `## Important Behaviors` at line 1187)
- Modify: `evals/evals.json` (eval 9)

**Interfaces:**
- Consumes: `log-append.sh <vault> <op> <target> [body-line ...]` from Task 1.
- Produces: the `## Operations Log` section that Task 5 and the companion plan reference by name.

- [ ] **Step 1: Add `Logs/` to the Vault Layout block**

In the fenced layout block, after the `Meetings/` entry and before `Archive/`, insert:

```
  Logs/
    YYYY-MM.md           # Append-only operations log (one file per month)
```

- [ ] **Step 2: Add the Logs path to the key-paths list**

In the `Other key paths:` list (currently ending with the `Meetings:` line), append:

```markdown
- Logs: `__VAULT_PATH__/Logs/YYYY-MM.md`
```

- [ ] **Step 3: Add the `## Operations Log` section**

Insert immediately before `## Commands`:

```markdown
## Operations Log

`Logs/YYYY-MM.md` is an append-only record of what this skill did and when. One file
per month, which keeps it bounded without ever needing its own compaction.

__The rule:__ log any operation that writes to the vault.

That covers `pull`, `rollover`, `tidy`, `summary`, `viz`, `sync`, `compact`, filing an
answer, and `audit` __only when fixes were applied__. It excludes `status`, `search`,
`share`, and a read-only audit run, because none of those change the vault. Absence is
informative too: no `pull` entries for three weeks answers "when did I last ingest"
just as well as a positive entry would.

__Always append through the helper__, never by editing the file directly:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' \
  <op> <target> 'first body line' 'second body line'
```

The helper creates the month file with frontmatter if absent and writes the entry as:

```markdown
## [2026-08-05] pull | #infrasec-leads
- 24 messages swept, 4 folded, 2 dropped (sensitive)
- last_scan_ts -> 2026-08-05T18:22:00Z (complete)
```

The `## [YYYY-MM-DD] <op> | <target>` prefix is a contract. Every reader greps for it,
so a hand-written entry that misses the format silently disappears from every query.
Use the helper and the format cannot drift.

__Pull entries carry one extra requirement:__ record whether the sweep was complete or
partial, and the resulting `last_scan_ts` per source. A partial sweep that looks
complete in hindsight is the specific failure this log exists to prevent.

__Reading the log__ needs no script:

```bash
cat '__VAULT_PATH__'/Logs/*.md | grep '^## \[' | tail -5
```
```

- [ ] **Step 4: Add the log-read to `/worklog audit`**

In the `### /worklog audit` section, immediately after the nudge-check paragraph and before `Scan the vault for quality issues`, insert:

```markdown
__Operational health (run second):__ read the last 10 log entries:

```bash
cat '__VAULT_PATH__'/Logs/*.md | grep '^## \[' | tail -10
```

Surface two conditions alongside the vault findings: a `pull` entry recorded as partial,
and no `pull` entries at all in a window where the stale-source nudge is firing. Read
before writing, so an audit run never reports on itself. If `Logs/` does not exist yet,
skip this step silently.
```

- [ ] **Step 5: Add the audit log-write, conditional on applied fixes**

At the end of the `### /worklog audit` section, after the sentence ending `do not re-derive them here.`, append:

```markdown
If the user approved and you applied any fixes, append one log entry naming what was
fixed. If nothing was applied, write no entry.
```

- [ ] **Step 6: Add `Logs/` to the sync allowlist**

In the `### /worklog sync` code block, change the `git add` line to include `Logs/`:

```bash
git add Worklogs/ People/ Programs/ Teams/ Archive/ Summaries/ Reports/ References/ Templates/ Sources/ Meetings/ Logs/ Preferences/ .skills/
```

Then in the paragraph that begins `__The `git add` list must cover every directory`, change the sentence listing previously-missed directories to:

```markdown
`Teams/`, `References/`, and `Preferences/` have each been missed this way, and `Logs/`
was added with this rule in mind.
```

- [ ] **Step 7: Add the log to Important Behaviors**

At the end of the `## Important Behaviors` list, append:

```markdown
- __Log what you write.__ Any operation that changes the vault appends one entry to
  `Logs/YYYY-MM.md` via `__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh`.
  See `## Operations Log`. Read-only commands (`status`, `search`, `share`, an audit
  that applied nothing) write no entry.
```

- [ ] **Step 8: Add log call-outs to each writing command**

Append one line to the end of each of these command sections. The `<op>` value is the
command name without the slash.

In `### /worklog pull`, after the `__Full flow detail:__` paragraph:

```markdown
__Log it:__ after the pull completes, append one entry per source via `log-append.sh`
with op `pull` and target `#<channel-name>`, recording counts and whether the sweep was
complete or partial along with the resulting `last_scan_ts`. See `## Operations Log`.
```

In `### /worklog rollover`, after `Then ask if the user wants to add any new items.`:

```markdown
__Log it:__ append one entry with op `rollover`, target the new week label, recording
items carried forward and items completed.
```

In `### /worklog tidy`, after `Present as a checklist. Apply approved changes directly.`:

```markdown
__Log it:__ if any changes were applied, append one entry with op `tidy` and target the
current week label. If nothing was applied, write no entry.
```

In `### /worklog summary [period]`, at the end of the `**Output 2 - Clipboard:**` block:

```markdown
__Log it:__ append one entry with op `summary` and target the period label.
```

In `### /worklog viz [period]`, after the existing sentence:

```markdown
__Log it:__ append one entry with op `viz` and target the generated report path.
```

In `### /worklog sync`, after the `.gitignore` paragraph:

```markdown
__Log it:__ append one entry with op `sync` and target `vault`, recording the commit
subject. Append it before staging so the entry is included in the same commit.
```

- [ ] **Step 9: Amend eval 9 for the log write**

In `evals/evals.json`, replace eval 9's `expected_output` with:

```
Should be idempotent apart from the log: no new Meetings/ files created, no existing Meetings/ files modified, no items added to the current week file. Should advance Sources/<channel>.md last_scan_ts to current time. Should append exactly one Logs/YYYY-MM.md entry with op `pull` recording 0 new threads and a complete sweep. Summary should report 0 new threads, 0 updated, 0 items extracted.
```

Leave `issue_tested` as is and append to it: ` (log entry is the one permitted write on a zero-result pull)`.

- [ ] **Step 10: Verify the placeholders and the template invariant**

```bash
grep -c '__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh' skills/worklog/SKILL.md
grep -n '/Users/mminutillo' skills/worklog/SKILL.md
python3 -c "import json; json.load(open('evals/evals.json')); print('evals.json parses')"
```

Expected: the first prints a count of 2 or more; the second prints nothing, proving no real path leaked into the template; the third prints `evals.json parses`.

- [ ] **Step 11: Commit**

```bash
git add skills/worklog/SKILL.md evals/evals.json
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(worklog): wire the operations log into SKILL.md; amend eval 9"
```

---

### Task 3: `cross-link-index.sh --with-summaries`

**Files:**
- Modify: `skills/worklog/scripts/cross-link-index.sh` (arg parsing at lines 7-10; Stage 1 at lines 23-33; assembly at lines 130-152)
- Create: `tests/fixtures/summary-vault/` (4 notes)
- Create: `tests/fixtures/crosslink-default.golden.json`
- Modify: `tests/cross-link-index.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `cross-link-index.sh <vault> [--with-summaries]`. With the flag, every object in `.entities[]` gains `summary` (string, possibly empty) and `summary_source` (one of `"declared"`, `"derived"`, `"none"`). Without it, output is byte-identical to 5.10.1. Task 4 wires the call sites.

- [ ] **Step 1: Capture the golden default output before touching the script**

```bash
./skills/worklog/scripts/cross-link-index.sh tests/fixtures/crosslink-vault \
  > tests/fixtures/crosslink-default.golden.json
wc -c tests/fixtures/crosslink-default.golden.json
```

Expected: a non-empty byte count. This file is the regression guard for the hot path, so it must be captured from the unmodified script.

- [ ] **Step 2: Create the summary fixture vault**

```bash
mkdir -p tests/fixtures/summary-vault/People tests/fixtures/summary-vault/Programs
```

`tests/fixtures/summary-vault/People/Declared Sam.md`:

```markdown
---
type: person
summary: "Director of Platform; joined 2024"
---

# Declared Sam

## Context

- This bullet must NOT win over the declared summary.
```

`tests/fixtures/summary-vault/People/Derived Dana.md`:

```markdown
---
type: person
---

# Derived Dana

## Context

- Staff engineer on the auth rewrite
- Second bullet, must be ignored
```

`tests/fixtures/summary-vault/People/Bare Stub.md`:

```markdown
---
type: person
---

# Bare Stub
```

`tests/fixtures/summary-vault/Programs/Quoted Program.md`:

```markdown
---
type: program
summary: 'Migration with "quotes", a colon: and a | pipe'
---

# Quoted Program

## Context

- Body bullet.
```

- [ ] **Step 3: Write the failing tests**

Append to `tests/cross-link-index.test.sh`, immediately before the final `if [ "$FAILS" -gt 0 ]` block:

```bash
# --- default output is unchanged (hot-path regression guard) ---
GOLDEN="$HERE/fixtures/crosslink-default.golden.json"
assert_eq "default output matches golden" \
  "$(printf '%s\n' "$OUT" | diff -q - "$GOLDEN" >/dev/null 2>&1 && echo same || echo differs)" "same"
assert_eq "default has no summary key" "$(jq_ '[.entities[] | has("summary")] | any')" "false"

# --- --with-summaries ---
SFIX="$HERE/fixtures/summary-vault"
SOUT="$("$HELPER" "$SFIX" --with-summaries)"
sjq() { printf '%s' "$SOUT" | jq -c "$1"; }
sel() { printf '.entities[] | select(.canonical=="%s")' "$1"; }

assert_eq "sum: valid json"  "$(printf '%s' "$SOUT" | jq -e . >/dev/null 2>&1 && echo ok)" "ok"
assert_eq "sum: declared wins" \
  "$(sjq "$(sel 'Declared Sam') | .summary")" '"Director of Platform; joined 2024"'
assert_eq "sum: declared source" \
  "$(sjq "$(sel 'Declared Sam') | .summary_source")" '"declared"'
assert_eq "sum: derived from first bullet" \
  "$(sjq "$(sel 'Derived Dana') | .summary")" '"Staff engineer on the auth rewrite"'
assert_eq "sum: derived source" \
  "$(sjq "$(sel 'Derived Dana') | .summary_source")" '"derived"'
assert_eq "sum: bare stub empty" \
  "$(sjq "$(sel 'Bare Stub') | .summary")" '""'
assert_eq "sum: bare stub source none" \
  "$(sjq "$(sel 'Bare Stub') | .summary_source")" '"none"'
assert_eq "sum: metachars survive json" \
  "$(sjq "$(sel 'Quoted Program') | .summary")" '"Migration with \"quotes\", a colon: and a | pipe"'
assert_eq "sum: every entity has a source" \
  "$(sjq '[.entities[] | has("summary_source")] | all')" "true"

# --- flag does not disturb the existing shape ---
assert_eq "sum: aliases still present" "$(sjq "$(sel 'Derived Dana') | .aliases")" '["Derived"]'
assert_eq "sum: meta still present"    "$(sjq '.meta.people')" "3"

# --- unknown option rejected ---
"$HELPER" "$FIX" --nonsense >/dev/null 2>&1; assert_eq "unknown flag exit 2" "$?" "2"
# --- flag order does not matter ---
assert_eq "flag before vault" \
  "$("$HELPER" --with-summaries "$SFIX" | jq -c "$(sel 'Bare Stub') | .summary_source")" '"none"'
```

- [ ] **Step 4: Run tests to verify the new ones fail**

```bash
./tests/cross-link-index.test.sh
```

Expected: the 30 pre-existing assertions PASS, `default output matches golden` PASSes (the script is still unmodified), and every `sum:` assertion FAILs because `--with-summaries` is not implemented. `unknown flag exit 2` also fails, because the current script silently treats `--nonsense` as the vault path and exits 2 for the wrong reason. Confirm it is reported as a FAIL, not a PASS, before continuing.

If `unknown flag exit 2` passes accidentally, note it and continue; step 6 makes the reason correct.

- [ ] **Step 5: Replace the argument parsing**

In `skills/worklog/scripts/cross-link-index.sh`, replace lines 7-10:

```bash
[ "${1:-}" ] || { echo "usage: cross-link-index.sh <vault-path>" >&2; exit 2; }
VAULT="$1"
[ -d "$VAULT" ] || { echo "cross-link-index: vault dir not found: $VAULT" >&2; exit 2; }
cd "$VAULT"
```

with:

```bash
WITH_SUMMARIES=0
VAULT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-summaries) WITH_SUMMARIES=1 ;;
    -*) echo "cross-link-index: unknown option: $1" >&2; exit 2 ;;
    *)  [ -n "$VAULT" ] || VAULT="$1" ;;
  esac
  shift
done
[ -n "$VAULT" ] || { echo "usage: cross-link-index.sh <vault-path> [--with-summaries]" >&2; exit 2; }
[ -d "$VAULT" ] || { echo "cross-link-index: vault dir not found: $VAULT" >&2; exit 2; }
cd "$VAULT"
```

A `while` loop over positionals rather than an array, because `"${#ARR[@]}"` on an empty array trips `set -u` under bash 3.2.

- [ ] **Step 6: Add the summary extraction functions and TSV**

After the existing `: > "$ENTS"; : > "$TUP"; : > "$OBS"` line, add `SUMS` to the temp files:

```bash
SUMS="$TMP/sums.tsv"      # canonical \t source \t summary
: > "$SUMS"
```

Then immediately before `# --- Stage 1: entities`, add the two extractors:

```bash
# --- Summary extraction (only used with --with-summaries) ---
# Declared: a frontmatter `summary:` line. Wins outright.
summary_declared(){ # <file>
  awk 'BEGIN{fm=0}
       /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
       fm==1 && /^summary:/{ s=$0; sub(/^summary:[[:space:]]*/,"",s)
                             gsub(/^["'\'']|["'\'']$/,"",s); print s; exit }' "$1"
}
# Derived: first body bullet after the frontmatter. Never reads frontmatter list items.
summary_derived(){ # <file>
  awk 'BEGIN{fm=0}
       /^---[[:space:]]*$/{fm++; next}
       (fm==0 || fm>=2) && /^[[:space:]]*-[[:space:]]+/{
         s=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",s); print s; exit }' "$1" | cut -c1-120
}
```

- [ ] **Step 7: Populate the TSV inside Stage 1**

In the Stage 1 loop, after the existing `printf '%s\t%s\n' "$name" "$type" >> "$ENTS"` line, add:

```bash
    if [ "$WITH_SUMMARIES" = "1" ]; then
      s="$(summary_declared "$f")"; src="declared"
      if [ -z "$s" ]; then s="$(summary_derived "$f")"; src="derived"; fi
      [ -n "$s" ] || src="none"
      s="$(printf '%s' "$s" | tr -d '\t')"     # protect the TSV separator
      printf '%s\t%s\t%s\n' "$name" "$src" "$s" >> "$SUMS"
    fi
```

- [ ] **Step 8: Merge the summaries into the final JSON**

After the `ENTJSON=` assignment, add:

```bash
SUMJSON='{}'
if [ "$WITH_SUMMARIES" = "1" ]; then
  SUMJSON="$(jq -R -s '
    split("\n") | map(select(length>0) | split("\t"))
    | reduce .[] as $r ({}; .[$r[0]] = {summary: ($r[2] // ""), summary_source: $r[1]})' "$SUMS")"
fi
```

Then in the final `jq -n` invocation, add two arguments before the filter:

```bash
  --argjson sums "$SUMJSON" \
  --argjson withsum "$WITH_SUMMARIES" \
```

and change the `entities:` mapping so the last pipeline stage becomes:

```
      | if (.alias_notes | length) == 0 then del(.alias_notes) else . end
      | if $withsum == 1
        then . + ($sums[.canonical] // {summary: "", summary_source: "none"})
        else . end)),
```

`--argjson withsum "$WITH_SUMMARIES"` passes the shell's `0`/`1` as a JSON number, which is why the guard compares against `1` rather than using truthiness.

- [ ] **Step 9: Run the tests**

```bash
./tests/cross-link-index.test.sh
/bin/bash ./tests/cross-link-index.test.sh
```

Expected: `All tests passed` under both, including `default output matches golden`. If the golden assertion fails, the flag change altered the hot path and must be corrected before proceeding; do not regenerate the golden file to make it pass.

- [ ] **Step 10: Sanity-check against the real vault**

```bash
V="/Users/mminutillo/Documents/Obsidian Vault"
./skills/worklog/scripts/cross-link-index.sh "$V" | jq '.meta'
./skills/worklog/scripts/cross-link-index.sh "$V" --with-summaries \
  | jq -c '[.entities[] | select(.summary_source=="declared")] | length,
           ([.entities[] | select(.summary_source=="derived")] | length),
           ([.entities[] | select(.summary_source=="none")] | length)'
```

Expected: `meta` reports about 314 people and 86 programs; the second command prints three counts. `declared` should be 0 at this point (no note has the field yet), with the rest split between `derived` and `none`. A non-zero `declared` count means a stray field already exists and is worth a look, not a failure.

- [ ] **Step 11: Commit**

```bash
git add skills/worklog/scripts/cross-link-index.sh tests/cross-link-index.test.sh \
        tests/fixtures/summary-vault tests/fixtures/crosslink-default.golden.json
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(cross-link): --with-summaries flag with declared/derived/none sourcing"
```

---

### Task 4: Wire `--with-summaries` into the skill and close the People glob

**Files:**
- Modify: `skills/worklog/SKILL.md` (People note structure around line 216-231; Program note structure around line 232-241; Cross-Linking step 1 at line 195; `### /worklog status` at line 671; `### /worklog search` at line 849; `### /worklog summary` data collection around line 975)
- Modify: `skills/worklog/references/pull-flow.md` (the classify step that globs `People/*.md`)

**Interfaces:**
- Consumes: `cross-link-index.sh <vault> [--with-summaries]` from Task 3.
- Produces: no new interface. Prose only.

- [ ] **Step 1: Locate the glob in the pull flow**

```bash
grep -n "People/\*\.md\|Programs/\*\.md" skills/worklog/references/pull-flow.md skills/worklog/SKILL.md
```

Record the line numbers. The classify step in `pull-flow.md` is the carried defect this task closes; the `Frontmatter Auto-generation` globs in `SKILL.md` (around lines 637 and 642) are a __different__ operation and stay as they are, because they need the full name list rather than a digest.

- [ ] **Step 2: Add `summary:` to the People note structure**

Replace the People note structure block with:

```markdown
**People note structure:**
```markdown
---
type: person
team: Backend Engineering
summary: "Staff engineer on the auth rewrite; joined 2024"
---
# Name
## Context
- Role/relationship context
- What you're working on together
```
```

Then after the existing paragraph about the `team` property, add:

```markdown
The optional `summary` property is a one-line answer to "who is this" for someone who
has never read the note: present tense, current state, under about 120 characters, no
wrapping. It is what `cross-link-index.sh --with-summaries` returns so a query can pick
the right entity without opening the note. When absent, the helper derives a provisional
summary from the note's first bullet, so the field is worth writing but never required.
```

- [ ] **Step 3: Add `summary:` to the Program note structure**

Replace the Program note structure block with:

```markdown
**Program note structure:**
```markdown
---
type: program
summary: "Consolidating three auth stacks onto one; targeting Q4"
---
# Program Name
## Context
- What it is, current status
- Key people involved (as wiki-links)
```
```

- [ ] **Step 4: Add the maintenance rule to Cross-Linking**

In the `**When a new person or program appears:**` list, after the `slack_search_users` bullet, add:

```markdown
- Write a one-line `summary:` in the frontmatter when you know enough to. When appending
  substantive context to an existing note later, refresh `summary:` if the note's current
  state changed. Skip the refresh for minor additions, the same judgment the frontmatter
  regeneration rules already use.
```

- [ ] **Step 5: Point the query commands at the flag**

In `### /worklog status`, after step 4 of the numbered list, add:

```markdown
If the user's question needs entity context rather than just item titles, get it from
`__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries`
and read the `summary` field. Do not open People or Program bodies for this.
```

In `### /worklog search <term>`, after the existing paragraph, add:

```markdown
When a match needs entity context to be intelligible, read it from the
`--with-summaries` digest rather than opening the note:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries
```
```

In `### /worklog summary [period]`, in the `**Data collection:**` list, replace item 5:

```markdown
5. Collect all wiki-linked people and programs mentioned. For any entity that needs
   context in the synthesis, read its `summary` from
   `cross-link-index.sh '__VAULT_PATH__' --with-summaries`. Do not read People or
   Program bodies.
```

- [ ] **Step 6: Replace the glob in the pull classify step**

In `skills/worklog/references/pull-flow.md`, at the line found in step 1, replace the instruction to glob `People/*.md` with:

```markdown
Get known entities from
`__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__' --with-summaries`.
Use `entities[].canonical` as link targets, `entities[].aliases` for partial and case
forms, `entities[].summary` when you need to judge whether a message is about that
person or program, and treat anything in `ambiguous` as resolve-from-context. Do not
glob `People/*.md` and do not read note bodies.
```

- [ ] **Step 7: Verify no stray real paths and that the glob is gone**

```bash
grep -n '/Users/mminutillo' skills/worklog/SKILL.md skills/worklog/references/pull-flow.md
grep -n "glob \`People/\*\.md\`\|Glob \`People/\*\.md\`" skills/worklog/references/pull-flow.md
grep -c 'with-summaries' skills/worklog/SKILL.md skills/worklog/references/pull-flow.md
```

Expected: the first two print nothing; the third reports 4 or more in `SKILL.md` and 1 in `pull-flow.md`.

- [ ] **Step 8: Commit**

```bash
git add skills/worklog/SKILL.md skills/worklog/references/pull-flow.md
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(worklog): summary: frontmatter and --with-summaries call sites; drop People glob in pull classify"
```

---

### Task 5: File answers back into the vault

**Files:**
- Modify: `skills/worklog/SKILL.md` (`### /worklog rollup` at lines 868-951; new `### /worklog file` section after it; `### /worklog share` at line 855; `## Important Behaviors` at line 1187)
- Modify: `evals/evals.json` (two new cases)

**Interfaces:**
- Consumes: `log-append.sh` from Task 1 and the `## Operations Log` section from Task 2.
- Produces: the `/worklog file` command. No script interface.

- [ ] **Step 1: Add the eval cases first**

In `evals/evals.json`, append two entries to the `evals` array. Use ids 30 and 31 (the array currently ends at 29):

```json
{
  "id": 30,
  "prompt": "/worklog rollup",
  "expected_output": "Should copy a Slack-mrkdwn version to the clipboard via pbcopy with no [[wiki-link]] syntax, AND write References/YYYY-WNN Rollup.md with type: reference, subtype: rollup, period, and source frontmatter. The filed copy must KEEP wiki-links so the rollup lands in the graph. The same include/filter content rules apply to both renderings: no performance commentary, no 1:1 specifics, no candidate names in either. Should append one Logs/ entry with op `file`.",
  "issue_tested": "Filed answers compound - a rollup must survive as a vault artifact, and filing must not relax the audience filter"
},
{
  "id": 31,
  "prompt": "/worklog share",
  "expected_output": "Should copy a brief priority-grouped status blurb to the clipboard and write NO vault file. Filing a share is explicitly out of scope; 52 of these a year would be noise in References/. Should append no Logs/ entry.",
  "issue_tested": "Not every output is worth filing - share and search stay ephemeral"
}
```

- [ ] **Step 2: Verify the evals file still parses**

```bash
python3 -c "
import json
d=json.load(open('evals/evals.json'))
ids=[e['id'] for e in d['evals']]
assert len(ids)==len(set(ids)), 'duplicate eval ids: %r' % ids
print('evals ok, count', len(ids), 'max id', max(ids))
"
```

Expected: `evals ok, count 31 max id 31`.

- [ ] **Step 3: Add filing to `/worklog rollup`**

In `### /worklog rollup`, replace the `**Output:**` block:

```markdown
**Output:**

After generating the message, copy it to the clipboard via `pbcopy` and tell the user the
message is ready to paste.

__Then file it.__ Write `References/YYYY-WNN Rollup.md`:

```markdown
---
type: reference
subtype: rollup
period: 2026-W31
source: /worklog rollup
---

# W31 Rollup (Jul 27-31)

<the same content, with [[wiki-links]] kept>
```

Two renderings of one artifact. The clipboard version strips `[[wiki-links]]` because
Slack cannot render them; the filed version keeps them, which is the entire reason
filing is worth doing - the rollup then shows up in backlinks on every program it
names, and the judgment that went into it compounds instead of evaporating.

__Filing does not relax the filter.__ The include and exclude rules above apply to both
renderings. `References/` is synced to the backup repo, so performance commentary, 1:1
specifics, and candidate details stay out of the filed copy too.

If a file already exists for the period, tell the user and ask whether to overwrite.

__Log it:__ append one entry with op `file` and target the filed path.
```

- [ ] **Step 4: Add the `/worklog file` command**

Insert a new section immediately after `### /worklog rollup` and before `### /worklog summary [period]`:

```markdown
### `/worklog file [title]`

File the answer you just produced into the vault as a durable artifact. This is for
substantive analysis - a comparison, an investigation, a synthesis you were asked for -
not for routine command output.

Write `References/<title>.md`:

```markdown
---
type: reference
source: <what produced this, e.g. "conversation 2026-08-05" or "/worklog search">
---

# <Title>

<the answer, cross-linked per the Cross-Linking rules>
```

- Filename is the given title. With no title, derive `YYYY-MM-DD <Short Title>` from the
  content.
- Wiki-link every person and program per the Cross-Linking rules. An unlinked filed
  answer is a page nothing points at, which is most of its value gone.
- Create stub notes for any new entities, same as anywhere else.
- If the file exists, tell the user and ask whether to overwrite or pick a new title.

__Offer, do not assume.__ After producing a substantive analytical answer against the
vault, offer once to file it. Do not file without confirmation. This mirrors how
`Preferences/` capture works, and for the same reason: the user's confirmation is what
keeps the vault from filling with artifacts they did not want.

__Log it:__ append one entry with op `file` and target the filed path.

__What not to file:__ `/worklog share` output, which is a three-line blurb, and
`/worklog search` results, which are re-derivable by re-running the search.
```

- [ ] **Step 5: State the exclusion in `/worklog share`**

At the end of `### /worklog share`, append:

```markdown
Clipboard only. Do not write a vault file - see `/worklog file` for what is worth
filing and why this is not.
```

- [ ] **Step 6: Add the behavior to Important Behaviors**

At the end of the `## Important Behaviors` list, append:

```markdown
- __Good answers are artifacts.__ A rollup files itself to `References/`. For any other
  substantive analysis you produce against the vault, offer once to file it with
  `/worklog file`. Filed answers are cross-linked, so they compound in the graph the
  same way ingested content does. Ephemeral by design: `share` and `search`.
```

- [ ] **Step 7: Verify**

```bash
grep -n '^### `/worklog file' skills/worklog/SKILL.md
grep -c 'subtype: rollup' skills/worklog/SKILL.md
grep -n '/Users/mminutillo' skills/worklog/SKILL.md
python3 -c "import json; json.load(open('evals/evals.json')); print('ok')"
```

Expected: the new section is found once, `subtype: rollup` appears once, no real paths, `ok`.

- [ ] **Step 8: Commit**

```bash
git add skills/worklog/SKILL.md evals/evals.json
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(worklog): file rollups and analyses to References/; add /worklog file"
```

---

### Task 6: Version bump, full verification, and rollout

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `README.md` (if it lists commands or version)

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: a 5.11.0 build propagated to the running install.

- [ ] **Step 1: Run the whole suite under system bash**

```bash
/bin/bash ./tests/cross-link-index.test.sh
/bin/bash ./tests/log-append.test.sh
/bin/bash ./tests/e2e-setup.sh
```

Expected: all three report success. `e2e-setup.sh` previously passed 45/45; if the count changed, read the diff before assuming it is fine.

- [ ] **Step 2: Bump the version**

In `.claude-plugin/plugin.json`, change `"version": "5.10.1"` to `"version": "5.11.0"`.

- [ ] **Step 3: Update the plugin description**

In the same file, append to the end of the `description` string, before the closing quote:

```
 Operations log, entity summaries, and filed answers.
```

- [ ] **Step 4: Check whether README needs the new command**

```bash
grep -n '/worklog rollup\|/worklog share\|Commands' README.md | head -20
```

If README lists the commands, add `/worklog file` in the same style and place. If it does not, make no change.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json README.md
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "chore(worklog): bump plugin version to 5.11.0"
```

- [ ] **Step 6: Propagate to the local marketplace**

```bash
DEST=/Users/mminutillo/personal-plugins/plugins/obsidian-worklog
rm -rf "$DEST" && mkdir -p "$DEST"
git archive HEAD | tar -x -C "$DEST"
```

- [ ] **Step 7: Substitute the placeholders with Python**

A `grep -Z | while read -d ''` plus `sed -i ''` loop silently no-ops under this shell. Use Python:

```bash
python3 - <<'PY'
import pathlib
DEST = pathlib.Path("/Users/mminutillo/personal-plugins/plugins/obsidian-worklog")
SUBS = {
    "__VAULT_PATH__": "/Users/mminutillo/Documents/Obsidian Vault",
    "__USER_NAME__": "Menotti",
    "__GIT_USER_NAME__": "mminutillo",
    "__GIT_USER_EMAIL__": "mminutillo@netflix.com",
    "__BACKUP_REPO_URL__": "github.netflix.net/mminutillo/obsidian-vault",
    "__SKILL_INSTALL_PATH__": "/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog",
}
n = 0
for p in DEST.rglob("*"):
    if not p.is_file() or p.suffix not in {".md", ".sh", ".json", ".html"}:
        continue
    try:
        t = p.read_text()
    except UnicodeDecodeError:
        continue
    o = t
    for k, v in SUBS.items():
        t = t.replace(k, v)
    if t != o:
        p.write_text(t)
        n += 1
print("substituted in", n, "files")
leftover = [str(p) for p in DEST.rglob("*")
            if p.is_file() and p.suffix in {".md", ".sh", ".json"}
            and "__" in p.read_text(errors="ignore")
            and any(k in p.read_text(errors="ignore") for k in SUBS)]
assert not leftover, "unsubstituted placeholders remain: %r" % leftover
print("no placeholders remain")
PY
```

Expected: a non-zero file count and `no placeholders remain`. The assertion is the point; a silent partial substitution is the failure mode this guards.

- [ ] **Step 8: Commit the marketplace copy**

```bash
cd /Users/mminutillo/personal-plugins
git add -A plugins/obsidian-worklog .claude-plugin/marketplace.json
git -c user.name="mminutillo" -c user.email="mminutillo@users.noreply.github.com" \
  commit -m "obsidian-worklog 5.11.0: operations log, entity summaries, filed answers"
cd /Users/mminutillo/obsidian-worklog
```

If `.claude-plugin/marketplace.json` in `personal-plugins` pins a version, update it to 5.11.0 before committing.

- [ ] **Step 9: Verify the substituted helpers run**

Run the __exact substituted string__ the installed `SKILL.md` emits, not an equivalent path. This is the 5.8.1 lesson: every static review passed while the literal emitted command was broken.

```bash
M=/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
grep -o "$M/skills/worklog/scripts/[a-z-]*\.sh" \
  /Users/mminutillo/personal-plugins/plugins/obsidian-worklog/skills/worklog/SKILL.md \
  | sort -u
```

Then, after step 10 has synced the marketplace, run each path printed above with the substituted vault path and confirm exit 0 for the read-only ones. For `log-append.sh`, run it against a throwaway directory rather than the real vault.

- [ ] **Step 10: Sync and restart (user action)**

Tell the user to run:

```
/plugin marketplace update personal
```

Expected output includes `1 plugin bumped`. Then restart Claude Code, because the plugin cache is keyed by version and a running session keeps 5.10.1 until restart.

- [ ] **Step 11: Post-restart smoke**

In a fresh session, run `/worklog audit` and confirm it reads the log section without error (there will be no `Logs/` directory yet, which must be skipped silently, not error). Then run `/worklog sync` and confirm `Logs/` appears in the staged paths and a log entry was written.

- [ ] **Step 12: Push the branch**

```bash
git push -u origin HEAD
```

`origin` only. Never `upstream`.

---

## Self-Review Notes

**Spec coverage.** Ops log storage, format, helper, logging rule, pull-completeness requirement, consumers, sync allowlist: Tasks 1-2. Summary field, flag, derived fallback, no-backfill decision, call sites, maintenance rule: Tasks 3-4. Rollup filing, `/worklog file`, not-filed list: Task 5. Eval 9 amendment: Task 2 step 9. Testing section: Tasks 1, 3, 5. Rollout: Task 6.

**Interface consistency.** `log-append.sh <vault> <op> <target> [body-line ...]` is used with that argument order in Task 2 steps 3-8 and Task 5 steps 3-4. `cross-link-index.sh <vault> [--with-summaries]` matches Task 3's implementation and Task 4's call sites. `summary_source` values are exactly `declared`, `derived`, `none` in the implementation, the tests, and the prose.

**Known ordering constraint.** Task 3 step 1 must run before any edit to `cross-link-index.sh`, or the golden regression file records post-change behavior and proves nothing.

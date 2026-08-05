# Worklog Note Compaction and Semantic Lint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound unbounded People and Programs note growth with an explicit, git-reversible compaction command, and add three audit outputs that surface oversized notes, `team:` vocabulary drift, and recurring topics without a page.

**Architecture:** Three new checks are added to the existing `audit-scan.sh` scanner, which computes all vault-wide scans in bash and emits one JSON object so the model never loads note bodies. Two of the three emit a *distribution* (a compact table the model judges) rather than *findings*, because their correctness is not decidable in bash. Compaction itself is model work driven by a new `SKILL.md` command section, gated by a link-preservation check and a clean-git precondition.

**Tech Stack:** bash 3.2 (macOS system bash), `jq`, `awk`, `sed`, `grep`, `wc`. Tests are plain bash with an `assert_eq` helper. Markdown for the skill body.

**Spec:** `docs/superpowers/specs/2026-08-05-worklog-compaction-and-semantic-lint-design.md`

**Depends on:** `docs/superpowers/plans/2026-08-05-worklog-ops-log-and-entity-summaries.md` (5.11.0) must be merged first. This plan calls `log-append.sh` and writes the `summary:` field, both introduced there.

## Global Constraints

- **bash 3.2 only.** No `mapfile`/`readarray`, no associative arrays, no `${var^^}`. Existing `audit-scan.sh` already uses `while IFS= read -r` loops for this reason; match them.
- **`audit-scan.sh` stays strictly read-only.** It is the vault-wide scanner. The only write-capable helper is `log-append.sh`.
- **New audit keys are additive.** The six existing keys (`stale_people`, `orphan_programs`, `stuck_items`, `missing_links`, `empty_stubs`, `frontmatter_gaps`) must keep their exact names and exact output. A golden file enforces this.
- **All JSON through `jq`.** Vault content contains quotes, ampersands, colons, pipes, and parentheses. String concatenation will produce invalid JSON.
- **Thresholds are env vars with defaults**, following the existing `CROSSLINK_DOM_RATIO` convention: `WORKLOG_COMPACT_LINES` (default 250), `WORKLOG_COMPACT_KEEP_DAYS` (default 90), `WORKLOG_TAG_MIN_FILES` (default 3).
- **`SKILL.md` and `references/*.md` stay templates.** Six placeholder tokens, never substituted in the repo. `__SKILL_INSTALL_PATH__` is the plugin ROOT, so scripts are `__SKILL_INSTALL_PATH__/skills/worklog/scripts/<name>.sh`.
- **Prose style:** no em-dashes, underscores for bold in conversational output, asterisks inside vault files.
- **Commit identity:** `git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" commit ...`.
- **Never push to `upstream`.** `origin` (`git.netflix.net/mminutillo`) only.
- **Target version:** 5.12.0, bumped once in the final task.

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `tests/fixtures/audit-vault/` | 17-note fixture exercising the three new checks: exact/substring/none/quoted/trailing-space/`?` team values, two oversized notes (one already compacted), one oversized Program, and 5 weekly files with overlapping tags. |
| `tests/audit-scan.test.sh` | Unit tests for the three new checks plus a golden-file regression guard on the six existing ones. |
| `tests/fixtures/audit-six-keys.golden.json` | Golden capture of the six existing checks against `crosslink-vault`, taken before `audit-scan.sh` is modified. |

**Modified:**

| Path | Change |
|---|---|
| `skills/worklog/scripts/audit-scan.sh` | Add `oversized_notes`, `team_vocabulary`, `recurring_tags` functions and three keys to the final `jq -n`. |
| `skills/worklog/SKILL.md` | `/worklog audit` gains the three new outputs and how to read them; People note structure gains the `team:` controlled-vocabulary rule; new `### /worklog compact` command; `## Important Behaviors` entry. |
| `evals/evals.json` | Six compaction judgment cases. |
| `.claude-plugin/plugin.json` | Version 5.11.0 to 5.12.0. |

---

### Task 1: Audit fixture, golden regression guard, and `oversized_notes`

**Files:**
- Create: `tests/fixtures/audit-vault/` (17 files, listed below)
- Create: `tests/fixtures/audit-six-keys.golden.json`
- Create: `tests/audit-scan.test.sh`
- Modify: `skills/worklog/scripts/audit-scan.sh` (add function after `stuck_items` ends at line 180; add key to final `jq -n` at lines 182-189)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `audit-scan.sh` output gains key `oversized_notes`, an array of `{file: string, lines: number, compacted: string|null}` sorted by path within `People/` then `Programs/`. Threshold from `WORKLOG_COMPACT_LINES` (default 250). Tasks 2 and 3 add sibling keys; Task 4 consumes all three from `SKILL.md`.

- [ ] **Step 1: Capture the golden six-key output BEFORE editing the scanner**

```bash
./skills/worklog/scripts/audit-scan.sh tests/fixtures/crosslink-vault \
  > tests/fixtures/audit-six-keys.golden.json
jq -c 'to_entries | map({(.key): (.value|length)}) | add' tests/fixtures/audit-six-keys.golden.json
```

Expected: `{"stale_people":8,"orphan_programs":2,"stuck_items":0,"missing_links":0,"empty_stubs":12,"frontmatter_gaps":1}`.

This ordering is not optional. Captured after the edit, the file records post-change behavior and proves nothing.

- [ ] **Step 2: Build the audit fixture vault**

```bash
S=tests/fixtures/audit-vault
mkdir -p "$S"/People "$S"/Programs "$S"/Teams "$S"/Worklogs "$S"/Archive
```

Then create these files with exactly this content.

`$S/Teams/CIS - Cloud Infrastructure Security.md`:
```markdown
---
type: team
---
# CIS - Cloud Infrastructure Security
```

`$S/Teams/Detection & Response.md`:
```markdown
---
type: team
---
# Detection & Response
```

`$S/People/Exact One.md` and `$S/People/Exact Two.md` (same body, differing title):
```markdown
---
type: person
team: Detection & Response
---
# Exact One

## Context

- bullet
```

`$S/People/Sub One.md`:
```markdown
---
type: person
team: Cloud Infrastructure Security
---
# Sub One

## Context

- bullet
```

`$S/People/Sub Quoted.md` (same value, quoted, must merge with Sub One's count):
```markdown
---
type: person
team: "Cloud Infrastructure Security"
---
# Sub Quoted

## Context

- bullet
```

`$S/People/None Trail.md` (note the three trailing spaces after `Ghost Org`, which must be stripped):
```markdown
---
type: person
team: Ghost Org   
---
# None Trail

## Context

- bullet
```

`$S/People/Qmark.md`:
```markdown
---
type: person
team: ?
---
# Qmark

## Context

- bullet
```

`$S/People/Big One.md` (12 lines, never compacted):
```markdown
---
type: person
---
# Big One

## History

- a
- b
- c
- d
- e
```

`$S/People/Big Compacted.md` (13 lines, quoted `compacted:` value):
```markdown
---
type: person
compacted: "2026-07-01"
---
# Big Compacted

## History

- a
- b
- c
- d
- e
```

`$S/Programs/Hiring.md`:
```markdown
---
type: program
---
# Hiring

## Context

- bullet
```

`$S/Programs/Big Program.md` (13 lines, proves the check covers Programs too):
```markdown
---
type: program
---
# Big Program

## History

- a
- b
- c
- d
- e
- f
```

`$S/Archive/2026-W20.md`, `2026-W21.md`, `2026-W22.md`, `2026-W23.md` (four files, identical apart from the week number):
```markdown
---
type: worklog
week: 2026-W20
tags:
  - hiring
  - strategy
  - genai
item-count: 1
done-count: 0
programs: []
people: []
---
# Week
```

`$S/Worklogs/2026-W24.md`:
```markdown
---
type: worklog
week: 2026-W24
tags:
  - hiring
  - "quoted-tag"
item-count: 1
done-count: 0
programs: []
people: []
---
# Week
```

Verify the line counts the tests depend on:

```bash
wc -l tests/fixtures/audit-vault/People/"Big One.md" \
      tests/fixtures/audit-vault/People/"Big Compacted.md" \
      tests/fixtures/audit-vault/Programs/"Big Program.md"
```

Expected: 12, 13, 13. If a trailing newline is missing the counts shift and the tests will fail on the wrong thing.

- [ ] **Step 3: Write the failing test file**

Create `tests/audit-scan.test.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for audit-scan.sh: the three added checks plus a golden regression
# guard proving the six original checks are byte-identical.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="$HERE/../skills/worklog/scripts/audit-scan.sh"
FIX="$HERE/fixtures/audit-vault"
OLDFIX="$HERE/fixtures/crosslink-vault"
GOLDEN="$HERE/fixtures/audit-six-keys.golden.json"
FAILS=0

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

# --- regression: the six original checks are unchanged ---
SIX='{stale_people,orphan_programs,stuck_items,missing_links,empty_stubs,frontmatter_gaps}'
assert_eq "six original keys unchanged" \
  "$("$HELPER" "$OLDFIX" | jq -S "$SIX" | diff -q - <(jq -S "$SIX" "$GOLDEN") >/dev/null 2>&1 && echo same || echo differs)" \
  "same"

OUT="$("$HELPER" "$FIX")"
jq_() { printf '%s' "$OUT" | jq -c "$1"; }

assert_eq "valid json"        "$(printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && echo ok)" "ok"
assert_eq "nine keys"         "$(jq_ 'keys | length')" "9"

# --- oversized_notes ---
assert_eq "default 250: none oversized" "$(jq_ '.oversized_notes')" "[]"

O11="$(WORKLOG_COMPACT_LINES=11 "$HELPER" "$FIX")"
o11() { printf '%s' "$O11" | jq -c "$1"; }
assert_eq "limit 11: three oversized"  "$(o11 '.oversized_notes | length')" "3"
assert_eq "limit 11: Big One lines"    "$(o11 '.oversized_notes[] | select(.file=="People/Big One.md") | .lines')" "12"
assert_eq "limit 11: Big One compacted null" \
  "$(o11 '.oversized_notes[] | select(.file=="People/Big One.md") | .compacted')" "null"
assert_eq "limit 11: quoted compacted stripped" \
  "$(o11 '.oversized_notes[] | select(.file=="People/Big Compacted.md") | .compacted')" '"2026-07-01"'
assert_eq "limit 11: Programs covered" \
  "$(o11 '[.oversized_notes[].file] | index("Programs/Big Program.md") != null')" "true"

# --- team_vocabulary ---
tv() { jq_ ".team_vocabulary[] | select(.value==\"$1\")"; }
assert_eq "tv: four distinct values" "$(jq_ '.team_vocabulary | length')" "4"
assert_eq "tv: exact resolution"     "$(tv 'Detection & Response' | jq -c '.resolves')" '"exact"'
assert_eq "tv: exact count"          "$(tv 'Detection & Response' | jq -c '.notes')" "2"
assert_eq "tv: quoted merges with unquoted" \
  "$(tv 'Cloud Infrastructure Security' | jq -c '.notes')" "2"
assert_eq "tv: substring resolution" \
  "$(tv 'Cloud Infrastructure Security' | jq -c '.resolves')" '"substring"'
assert_eq "tv: substring candidate" \
  "$(tv 'Cloud Infrastructure Security' | jq -c '.candidate')" '"CIS - Cloud Infrastructure Security"'
assert_eq "tv: trailing space stripped" "$(tv 'Ghost Org' | jq -c '.resolves')" '"none"'
assert_eq "tv: question mark survives"  "$(tv '?' | jq -c '.resolves')" '"none"'
assert_eq "tv: no candidate on exact"   "$(tv 'Detection & Response' | jq -c 'has("candidate")')" "false"
assert_eq "tv: no candidate on none"    "$(tv 'Ghost Org' | jq -c 'has("candidate")')" "false"
assert_eq "tv: sorted by count desc"    "$(jq_ '[.team_vocabulary[].notes] == ([.team_vocabulary[].notes] | sort | reverse)')" "true"

# --- recurring_tags ---
rt() { jq_ ".recurring_tags[] | select(.tag==\"$1\")"; }
assert_eq "rt: three tags at min 3"  "$(jq_ '.recurring_tags | length')" "3"
assert_eq "rt: hiring in 5 files"    "$(rt hiring | jq -c '.files')" "5"
assert_eq "rt: hiring has page"      "$(rt hiring | jq -c '.has_page')" "true"
assert_eq "rt: genai no page"        "$(rt genai | jq -c '.has_page')" "false"
assert_eq "rt: genai in 4 files"     "$(rt genai | jq -c '.files')" "4"
assert_eq "rt: below-threshold tag excluded" \
  "$(jq_ '[.recurring_tags[].tag] | index("quoted-tag")')" "null"

R5="$(WORKLOG_TAG_MIN_FILES=5 "$HELPER" "$FIX")"
assert_eq "rt: min 5 keeps only hiring" \
  "$(printf '%s' "$R5" | jq -c '[.recurring_tags[].tag]')" '["hiring"]'

# --- edge cases ---
EMPTY="$(mktemp -d)"; mkdir -p "$EMPTY/People" "$EMPTY/Programs"
EOUT="$("$HELPER" "$EMPTY")"
assert_eq "empty: oversized []"  "$(printf '%s' "$EOUT" | jq -c '.oversized_notes')"  "[]"
assert_eq "empty: team_vocab []" "$(printf '%s' "$EOUT" | jq -c '.team_vocabulary')" "[]"
assert_eq "empty: tags []"       "$(printf '%s' "$EOUT" | jq -c '.recurring_tags')"  "[]"
rm -rf "$EMPTY"

"$HELPER" >/dev/null 2>&1;                assert_eq "no-arg nonzero" "$([ $? -ne 0 ] && echo nonzero)" "nonzero"
"$HELPER" /no/such/vault >/dev/null 2>&1; assert_eq "bad-vault exit 2" "$?" "2"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
chmod +x tests/audit-scan.test.sh
./tests/audit-scan.test.sh
```

Expected: `six original keys unchanged` PASSes (scanner untouched), `valid json` PASSes, and everything from `nine keys` onward FAILs because the three keys do not exist. Confirm `nine keys` reports `got: 6`.

- [ ] **Step 5: Add the `oversized_notes` function**

In `skills/worklog/scripts/audit-scan.sh`, insert after the closing `}` of `stuck_items` (line 180) and before the final `jq -n`:

```bash
oversized_notes(){
  shopt -s nullglob
  limit="${WORKLOG_COMPACT_LINES:-250}"
  for f in People/*.md Programs/*.md; do
    n="$(wc -l < "$f" | tr -d ' ')"
    [ "$n" -gt "$limit" ] || continue
    c="$(awk 'BEGIN{fm=0}
              /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
              fm==1 && /^compacted:/{ s=$0; sub(/^compacted:[[:space:]]*/,"",s); gsub(/"/,"",s); print s; exit }' "$f")"
    if [ -n "$c" ]; then
      jq -cn --arg file "$f" --argjson lines "$n" --arg compacted "$c" \
         '{file:$file, lines:$lines, compacted:$compacted}'
    else
      jq -cn --arg file "$f" --argjson lines "$n" '{file:$file, lines:$lines, compacted:null}'
    fi
  done | emit_array
}
```

- [ ] **Step 6: Add the key to the final `jq -n`**

Change the final invocation to add one argument and one key:

```bash
jq -n \
  --argjson stale_people "$(stale_people)" \
  --argjson orphan_programs "$(orphan_programs)" \
  --argjson stuck_items "$(stuck_items)" \
  --argjson missing_links "$(missing_links)" \
  --argjson empty_stubs "$(empty_stubs)" \
  --argjson frontmatter_gaps "$(frontmatter_gaps)" \
  --argjson oversized_notes "$(oversized_notes)" \
  '{stale_people:$stale_people, orphan_programs:$orphan_programs, stuck_items:$stuck_items, missing_links:$missing_links, empty_stubs:$empty_stubs, frontmatter_gaps:$frontmatter_gaps, oversized_notes:$oversized_notes}'
```

- [ ] **Step 7: Run the tests**

```bash
./tests/audit-scan.test.sh
```

Expected: `six original keys unchanged` still PASSes, all five `oversized` assertions PASS, `empty: oversized []` PASSes. `nine keys` still FAILs with `got: 7`, and the `tv:` and `rt:` assertions still FAIL. That is the correct intermediate state.

- [ ] **Step 8: Commit**

```bash
git add tests/fixtures/audit-vault tests/fixtures/audit-six-keys.golden.json \
        tests/audit-scan.test.sh skills/worklog/scripts/audit-scan.sh
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(audit): oversized_notes check; audit fixture and six-key golden guard"
```

---

### Task 2: `team_vocabulary` check

**Files:**
- Modify: `skills/worklog/scripts/audit-scan.sh` (add function after `oversized_notes`; add key to final `jq -n`)

**Interfaces:**
- Consumes: `emit_array` and the fixture from Task 1.
- Produces: key `team_vocabulary`, an array of `{value: string, notes: number, resolves: "exact"|"substring"|"none"}` plus `candidate: string` only when `resolves == "substring"`. Sorted by `notes` descending, then value ascending. Task 4 consumes it.

- [ ] **Step 1: Confirm the tests for this check currently fail**

```bash
./tests/audit-scan.test.sh 2>&1 | grep -E '^(PASS|FAIL): tv:'
```

Expected: all eleven `tv:` lines report FAIL.

- [ ] **Step 2: Add the function**

Insert after `oversized_notes` in `skills/worklog/scripts/audit-scan.sh`:

```bash
# Distribution, not findings: 86 distinct team: values across 314 People notes in the
# real vault, of which only 7 resolve exactly. As a per-note dangling-reference list
# that is ~300 findings and useless. The model reads the table and proposes merges.
team_vocabulary(){
  shopt -s nullglob
  [ -d People ] || { echo '[]'; return; }
  tn="$(mktemp)"
  { ls Teams 2>/dev/null || true; } | sed 's/\.md$//' | sort > "$tn"
  TAB="$(printf '\t')"
  grep -h '^team:' People/*.md 2>/dev/null \
    | sed -e 's/^team:[[:space:]]*//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//" -e 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | awk '{c[$0]++} END{for(k in c) printf "%d\t%s\n", c[k], k}' \
    | sort -t"$TAB" -k1,1nr -k2,2 \
    | while IFS="$TAB" read -r cnt value; do
        [ -n "$value" ] || continue
        if grep -Fxq "$value" "$tn"; then
          jq -cn --arg v "$value" --argjson n "$cnt" '{value:$v, notes:$n, resolves:"exact"}'
        else
          cand="$(grep -iF "$value" "$tn" | head -1 || true)"
          if [ -n "$cand" ]; then
            jq -cn --arg v "$value" --argjson n "$cnt" --arg c "$cand" \
               '{value:$v, notes:$n, resolves:"substring", candidate:$c}'
          else
            jq -cn --arg v "$value" --argjson n "$cnt" '{value:$v, notes:$n, resolves:"none"}'
          fi
        fi
      done | emit_array
  rm -f "$tn"
}
```

Three details that matter. The `sed` chain strips surrounding quotes and trailing whitespace, without which `team: "X"` and `team: X` count as different values and a trailing space produces a phantom entry. `grep -Fxq` is a whole-line fixed-string match for the exact case, so a value containing regex metacharacters (`&`, `(`, `?`) cannot misfire. The substring direction is value-inside-Teams-name, which is what catches `Cloud Infrastructure Security` inside `CIS - Cloud Infrastructure Security`.

- [ ] **Step 3: Add the key to the final `jq -n`**

Add `--argjson team_vocabulary "$(team_vocabulary)"` after the `oversized_notes` argument, and `team_vocabulary:$team_vocabulary` at the end of the object filter.

- [ ] **Step 4: Run the tests**

```bash
./tests/audit-scan.test.sh 2>&1 | grep -E '^(PASS|FAIL): (tv:|six|empty: team)'
```

Expected: all eleven `tv:` PASS, `six original keys unchanged` PASS, `empty: team_vocab []` PASS.

- [ ] **Step 5: Verify against the real vault**

```bash
V="/Users/mminutillo/Documents/Obsidian Vault"
./skills/worklog/scripts/audit-scan.sh "$V" | jq -c '
  {values: (.team_vocabulary | length),
   exact:  ([.team_vocabulary[] | select(.resolves=="exact")]     | length),
   substr: ([.team_vocabulary[] | select(.resolves=="substring")] | length),
   none:   ([.team_vocabulary[] | select(.resolves=="none")]      | length)}'
```

Expected: `{"values":86,"exact":7,"substr":13,"none":66}`. These are the numbers the spec quotes. A different total is not necessarily a bug (the vault changes), but a wildly different ratio means the resolution logic regressed.

- [ ] **Step 6: Commit**

```bash
git add skills/worklog/scripts/audit-scan.sh
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(audit): team_vocabulary distribution check"
```

---

### Task 3: `recurring_tags` check

**Files:**
- Modify: `skills/worklog/scripts/audit-scan.sh` (add function after `team_vocabulary`; add key to final `jq -n`)

**Interfaces:**
- Consumes: `emit_array` and the fixture from Task 1.
- Produces: key `recurring_tags`, an array of `{tag: string, files: number, has_page: boolean}` for tags appearing in at least `WORKLOG_TAG_MIN_FILES` (default 3) weekly or archive files. Sorted by `files` descending, then tag ascending. Task 4 consumes it.

- [ ] **Step 1: Confirm the tests for this check currently fail**

```bash
./tests/audit-scan.test.sh 2>&1 | grep -E '^(PASS|FAIL): rt:'
```

Expected: all seven `rt:` lines report FAIL.

- [ ] **Step 2: Add the function**

Insert after `team_vocabulary`:

```bash
# Distribution, not findings. Prototyped as findings first: 23 tags recur in 3+ files in
# the real vault, 21 have no Programs page, and only ~2 of those deserve one -- "strategy",
# "growth", and "leadership" are themes, not programs. ~90% false positive. So emit counts
# and let the model judge which recurring themes deserve promotion.
# Tags (not subgroup headings) are the signal because tags: frontmatter survives archiving
# while archiving rewrites weekly bodies as flat lists, discarding subgroup structure.
recurring_tags(){
  shopt -s nullglob
  min="${WORKLOG_TAG_MIN_FILES:-3}"
  pn="$(mktemp)"; tf="$(mktemp)"
  { ls Programs 2>/dev/null || true; } | sed 's/\.md$//' > "$pn"
  TAB="$(printf '\t')"
  for f in Worklogs/[0-9]*-W*.md Archive/[0-9]*-W*.md; do
    [ -f "$f" ] || continue
    awk '
      BEGIN{fm=0; t=0}
      /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
      fm==1 && /^tags:/{t=1; next}
      fm==1 && t && /^[[:space:]]+-[[:space:]]*/{
        s=$0; sub(/^[[:space:]]+-[[:space:]]*/,"",s)
        gsub(/^["'\'']|["'\'']$/,"",s); if(s!="") print s; next }
      fm==1 && t && /^[^[:space:]]/{t=0}
    ' "$f" | sort -u
  done | awk -v min="$min" '{c[$0]++} END{for(k in c) if (c[k]+0 >= min+0) printf "%d\t%s\n", c[k], k}' \
       | sort -t"$TAB" -k1,1nr -k2,2 > "$tf"
  while IFS="$TAB" read -r cnt tag; do
    [ -n "$tag" ] || continue
    has=false
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      norm="$(printf '%s' "$p" | tr 'A-Z' 'a-z' | tr ' ' '-')"
      if [ "$norm" = "$tag" ]; then has=true; break; fi
    done < "$pn"
    jq -cn --arg t "$tag" --argjson f "$cnt" --argjson h "$has" '{tag:$t, files:$f, has_page:$h}'
  done < "$tf" | emit_array
  rm -f "$pn" "$tf"
}
```

The per-file `sort -u` is what makes `files` a file count rather than an occurrence count: a tag listed twice in one file still counts once. `has_page` compares the tag against each Programs note name lowercased with spaces turned into hyphens, which is the same transform the `tags` extraction rules in `SKILL.md` apply when deriving tags from subgroup headings.

- [ ] **Step 3: Add the key to the final `jq -n`**

Add `--argjson recurring_tags "$(recurring_tags)"` after the `team_vocabulary` argument, and `recurring_tags:$recurring_tags` at the end of the object filter. The final line should now name all nine keys.

- [ ] **Step 4: Run the full suite**

```bash
./tests/audit-scan.test.sh
/bin/bash ./tests/audit-scan.test.sh
```

Expected: `All tests passed` under both, including `nine keys` and `six original keys unchanged`.

- [ ] **Step 5: Verify against the real vault**

```bash
V="/Users/mminutillo/Documents/Obsidian Vault"
./skills/worklog/scripts/audit-scan.sh "$V" | jq -c '
  {tags: (.recurring_tags | length),
   no_page: ([.recurring_tags[] | select(.has_page==false)] | length),
   oversized: [.oversized_notes[] | {file, lines}]}'
```

Expected: 23 tags, 21 without a page, and six oversized notes: Christine Chalmers (1536), Astha Singhal (852), Brian Gaines (451), Rachel Taylor (335), Laura Haller (334), and Programs/GenAI Agent Platform (314).

- [ ] **Step 6: Confirm the scanner is still read-only**

```bash
V="/Users/mminutillo/Documents/Obsidian Vault"
git -C "$V" status --porcelain | head
```

Expected: no output. The scanner must not have touched the vault. If anything appears, a `mktemp` was written inside the vault instead of `$TMPDIR`.

- [ ] **Step 7: Commit**

```bash
git add skills/worklog/scripts/audit-scan.sh
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(audit): recurring_tags distribution check"
```

---

### Task 4: Wire the three checks into `/worklog audit` and add the `team:` convention

**Files:**
- Modify: `skills/worklog/SKILL.md` (`### /worklog audit` at lines 806-847; People note structure around lines 216-231)

**Interfaces:**
- Consumes: the nine-key `audit-scan.sh` output from Tasks 1-3.
- Produces: prose only. Task 7's cleanup runbook depends on the `team:` convention landing here.

- [ ] **Step 1: Update the scanner description in `/worklog audit`**

Replace the sentence `__Run the scanner__ — it computes all six checks in bash so no `People`/`Programs` bodies load into context:` with:

```markdown
__Run the scanner__ - it computes all nine checks in bash so no `People`/`Programs`
bodies load into context:
```

And replace the paragraph beginning `It prints JSON with six arrays:` with:

```markdown
It prints JSON with nine keys. Six are __findings__, each entry an item to fix:
`stale_people`, `orphan_programs`, `stuck_items`, `missing_links`, `empty_stubs`,
`frontmatter_gaps`. Read __only__ this output - do not glob or read `People`/`Programs`
bodies yourself. The `stuck_items` and `missing_links` checks are heuristic; review each
and drop obvious misfires before presenting.

Three are __distributions__, not findings. Each is a compact table where the judgment is
yours, not the scanner's, because correctness is not decidable in bash:

- `oversized_notes` - findings-shaped, actually: `{file, lines, compacted}` for every
  note over `WORKLOG_COMPACT_LINES` (default 250). `compacted` is the note's frontmatter
  value or null, so a note that was compacted and has grown again is distinguishable from
  one never compacted. Offer `/worklog compact <file>` for each.
- `team_vocabulary` - `{value, notes, resolves, candidate?}` for every distinct `team:`
  value on People notes. `resolves` is `exact`, `substring`, or `none` against the
  `Teams/` note names. Propose merge groups from this and let the user approve them one
  at a time; do not rewrite `team:` values unasked. A value resolving `none` is not
  automatically wrong: `External`, `Former Netflix`, and `Unknown` are reserved and
  correct.
- `recurring_tags` - `{tag, files, has_page}` for tags appearing in 3 or more weekly or
  archive files. Judge which recurring themes deserve a `Programs/` or `References/`
  page. Most do not: `strategy`, `growth`, `leadership`, and `team-health` are themes,
  not programs. Suggest a page only where the tag names a specific effort with an owner
  or an end state.
```

- [ ] **Step 2: Extend the example output block**

In the example results block, after the `Frontmatter gaps:` lines, append:

```
Oversized notes (over 250 lines):
- People/Christine Chalmers.md - 1536 lines, never compacted
  Suggested: /worklog compact "People/Christine Chalmers.md"

Team vocabulary (86 values, 7 resolve exactly):
- "Security, Privacy & Assurance" (7 notes) and "SPA" (2 notes) look like one org
  Suggested: merge both into a Teams/ note, or map to the reserved set

Recurring tags without a page:
- spa-leadership-transition (6 weeks) - names a specific effort, page looks warranted
- strategy (16 weeks) - a theme, no page needed
```

- [ ] **Step 3: Add the `team:` controlled-vocabulary rule**

In the People note structure section, after the paragraph explaining the `team` property, append:

```markdown
__`team:` is a controlled vocabulary.__ A value must either match a `Teams/` note name
exactly, or be one of the reserved values `External`, `Former Netflix`, or `Unknown`.
Free text defeats the whole point of the property: the Teams dimension of the graph only
works if `team:` resolves to a note. When you do not know someone's team, write
`Unknown` rather than inventing a label or leaving a placeholder. If a real team has no
note yet, create the `Teams/` note first, then reference it.
```

- [ ] **Step 4: Add the Important Behaviors entry**

At the end of the `## Important Behaviors` list, append:

```markdown
- __Distributions are yours to judge.__ Three audit outputs (`oversized_notes`,
  `team_vocabulary`, `recurring_tags`) are tables, not to-do lists. The scanner is not
  claiming each row is a problem; it is handing you the full picture cheaply so you can
  say which rows matter. Never present a distribution row as a defect without saying why
  it is one.
```

- [ ] **Step 5: Verify**

```bash
grep -c 'oversized_notes\|team_vocabulary\|recurring_tags' skills/worklog/SKILL.md
grep -n 'all six checks\|six arrays' skills/worklog/SKILL.md
grep -n '/Users/mminutillo' skills/worklog/SKILL.md
```

Expected: the first prints 6 or more; the second prints nothing, proving no stale "six" language survives; the third prints nothing.

- [ ] **Step 6: Commit**

```bash
git add skills/worklog/SKILL.md
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(worklog): wire three new audit outputs; team: controlled vocabulary"
```

---

### Task 5: The `/worklog compact` command

**Files:**
- Modify: `skills/worklog/SKILL.md` (new section after `### /worklog audit`, before `### /worklog search <term>` at line 849)

**Interfaces:**
- Consumes: `oversized_notes` from Task 1, `log-append.sh` from the 5.11.0 plan, the `summary:` field from the 5.11.0 plan.
- Produces: the `/worklog compact` command. Task 6 writes evals against it.

- [ ] **Step 1: Add the command section**

Insert after the `/worklog audit` section:

````markdown
### `/worklog compact [note]`

Fold a note's old history into a summary so the note stops growing without bound. Lossy
by design and explicit by design: you run it on one note at a time and the user sees what
was folded.

With no argument, run the scanner, read `oversized_notes`, and offer the candidates one
at a time with explicit options (largest first). Do not batch them.

__Precondition: the vault git state must be clean.__

```bash
git -C '__VAULT_PATH__' status --porcelain
```

If that prints anything, offer to run `/worklog sync` first and wait. Git history is the
only undo for a lossy fold, so an uncommitted vault means an unrecoverable rewrite. If
the user declines to sync, do not compact.

__Read the whole note.__ This is the one operation that legitimately loads a full note
body, and it is why contradiction detection rides along here rather than as its own pass.

__Target shape:__

```markdown
---
type: person
team: Infrasec
summary: "Director WISSE; departed Netflix Jun 24 2026"
compacted: 2026-08-05
---

# Astha Singhal

## Role
<current state, verbatim>

## Recent

### Jun 22, 2026 - org restructure
<verbatim>

## History

- Mar-May 2026: SPA "blocking innovation" narrative, team health, [[Cloud Security EM Hiring|CloudSec EM]] loop (5 1:1s folded)
- 2025: <folded>
```

__Fold rules:__

1. A __foldable entry__ is a section whose heading contains a date, at any heading level.
   Real notes use `## May 29, 2026 - 1:1 (substantive, multi-topic)` with `###`
   subsections beneath, so do not assume a fixed level.
2. __Never fold a section whose heading has no date.__ One rule instead of a list of
   protected names, and it covers `## Role`, `## Context`, `## 1:1 Doc`, `## Members`,
   and anything similar added later. Undated sections carry current state, which is the
   answer to "who or what is this" and the reason the note exists at all.
3. Dated sections newer than `WORKLOG_COMPACT_KEEP_DAYS` (default 90) move under
   `## Recent`, verbatim, in chronological order.
4. Older dated sections fold into `## History`. Preserve dates, decisions, status
   changes, facts that changed, and every `[[wiki-link]]`. Drop verbatim quotes, meeting
   play-by-play, and detail that only supported a conclusion already stated.
5. `## History` granularity is one bullet per month, or per coherent theme where a theme
   spans months. Prefer themes; they read better and compress harder.
6. If the note already has `compacted:` set, do not re-fold anything already in
   `## History`, and treat the retention window as relative to today, not to the previous
   compaction.

__Link preservation is a hard gate, not a warning.__ A fold that drops `[[wiki-links]]`
deletes graph edges, and nothing else in the vault will notice: the `missing_links` audit
check only finds unlinked mentions in recent weekly files, not edges that vanished from a
People note. Before writing, capture the canonical link targets:

```bash
grep -o '\[\[[^]]*\]\]' "<note>" | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/|.*$//' | sort -u
```

Run the same command on your proposed content and compare. Normalizing to the canonical
target by stripping everything after `|` is deliberate: rewording an alias while keeping
the target is not a lost edge. Any target present before and absent after must be
reported and explicitly confirmed by the user before the write happens. If they do not
confirm, do not write.

__Outputs:__

1. The rewritten note.
2. A real `summary:` in frontmatter, authored not derived. Compaction always writes one.
3. `compacted:` set to today's date.
4. __A contradiction report.__ While holding the whole note, flag internal contradictions
   and claims that newer entries supersede. Report them; do not auto-fix. Frontmatter
   that disagrees with the body is the most common case and the most consequential.
5. A dropped-link report, empty in the normal case.
6. One log entry:

```markdown
## [2026-08-05] compact | People/Astha Singhal.md
- 852 -> 210 lines; 9 dated entries folded to ## History
- contradiction: frontmatter team says "Security, Privacy & Assurance"; body records rename to Infrastructure & Security
- links preserved: 34/34
```

__What this does not do:__ cross-note contradiction detection. Comparing claims across
all 400 notes means reading all 400 notes, which is the exact cost the scanners exist to
avoid. A note that contradicts itself is both the common case and the consequential one,
and that is what this catches. Say so plainly rather than implying broader coverage.
````

- [ ] **Step 2: Add the Important Behaviors entry**

At the end of `## Important Behaviors`, append:

```markdown
- __Compaction is lossy and git is the undo.__ `/worklog compact` never runs on a dirty
  vault, never folds an undated section, and never writes when a `[[wiki-link]]` target
  would disappear without the user confirming. Suggest it when `/worklog audit` reports
  `oversized_notes`, one note at a time, never in a batch.
```

- [ ] **Step 3: Verify**

```bash
grep -n '^### `/worklog compact' skills/worklog/SKILL.md
grep -c 'WORKLOG_COMPACT_KEEP_DAYS' skills/worklog/SKILL.md
grep -n '—' skills/worklog/SKILL.md | head
grep -n '/Users/mminutillo' skills/worklog/SKILL.md
```

Expected: the section is found once; `WORKLOG_COMPACT_KEEP_DAYS` appears once; the em-dash grep shows only pre-existing lines you did not add (note any you introduced and fix them); no real paths.

- [ ] **Step 4: Commit**

```bash
git add skills/worklog/SKILL.md
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "feat(worklog): /worklog compact with undated-section and link-preservation gates"
```

---

### Task 6: Compaction evals

**Files:**
- Modify: `evals/evals.json`

**Interfaces:**
- Consumes: the `/worklog compact` command from Task 5.
- Produces: eval ids 32-37. The 5.11.0 plan added 30 and 31.

- [ ] **Step 1: Append the six cases**

Add to the `evals` array in `evals/evals.json`:

```json
{
  "id": 32,
  "prompt": "/worklog compact \"People/Astha Singhal.md\" (vault git state clean; note has ## Role, ## 1:1 Doc, and eight dated ## entries spanning 14 months)",
  "expected_output": "The ## Role and ## 1:1 Doc sections must be byte-identical after the rewrite, because their headings carry no date. Dated entries within 90 days go under ## Recent verbatim; older ones fold to ## History as dated bullets. Frontmatter gains an authored summary: and compacted: today. Should append one Logs/ entry with op `compact` recording before and after line counts.",
  "issue_tested": "Undated sections carry current state and must never be folded"
},
{
  "id": 33,
  "prompt": "/worklog compact \"People/Christine Chalmers.md\" (1536 lines, ~40 [[wiki-links]] across old entries)",
  "expected_output": "Every canonical link target present before the fold must be present after. Should compute the before and after target sets (stripping the alias after | so a reworded alias is not counted as a loss) and report the count. If any target would disappear, must report it and ask for explicit confirmation before writing, not write and warn.",
  "issue_tested": "Lossy folding must not silently delete graph edges - nothing else in the vault detects a lost edge"
},
{
  "id": 34,
  "prompt": "/worklog compact \"People/Astha Singhal.md\" (frontmatter says team: Security, Privacy & Assurance; body records that SPA was renamed Infrastructure & Security)",
  "expected_output": "Should report the contradiction between frontmatter and body and NOT auto-fix it. The user decides. Reporting it is the deliverable; silently rewriting team: is a failure even though the body is clearly newer.",
  "issue_tested": "Contradiction detection reports, never auto-fixes"
},
{
  "id": 35,
  "prompt": "/worklog compact (no argument, vault has six notes over 250 lines)",
  "expected_output": "Should run the scanner, read oversized_notes, and offer candidates one at a time with explicit options, largest first. Must not batch them into a single free-text checklist and must not compact more than one without a per-note decision.",
  "issue_tested": "Batch decisions are presented one-by-one with options"
},
{
  "id": 36,
  "prompt": "/worklog compact \"People/Brian Gaines.md\" (vault has uncommitted changes)",
  "expected_output": "Must check git status first, find the vault dirty, and offer to run /worklog sync before compacting. Must not write the fold while the vault is dirty, since git history is the only undo for a lossy rewrite. If the user declines to sync, must not compact.",
  "issue_tested": "Git-clean precondition is what makes lossy folding safe"
},
{
  "id": 37,
  "prompt": "/worklog compact \"People/Rachel Taylor.md\" (already has compacted: 2026-06-01 and a populated ## History)",
  "expected_output": "Must not re-fold content already in ## History. The retention window is relative to today, not to the previous compaction date, so entries that have aged past 90 days since June should now move from ## Recent into ## History. Frontmatter compacted: updates to today.",
  "issue_tested": "Repeat compaction is incremental, not a re-fold of already-folded history"
}
```

- [ ] **Step 2: Verify the file parses and ids are unique**

```bash
python3 -c "
import json
d=json.load(open('evals/evals.json'))
ids=[e['id'] for e in d['evals']]
assert len(ids)==len(set(ids)), 'duplicate ids'
assert sorted(ids)==list(range(1,max(ids)+1)), 'gap in ids: %r' % sorted(ids)
print('evals ok, count', len(ids), 'max id', max(ids))
"
```

Expected: `evals ok, count 37 max id 37`.

- [ ] **Step 3: Commit**

```bash
git add evals/evals.json
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "test(worklog): eval cases for compaction judgment"
```

---

### Task 7: Version bump, rollout, and the `team:` vocabulary cleanup

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: everything from Tasks 1-6.
- Produces: a 5.12.0 build running locally, plus a cleaned-up `team:` vocabulary in the vault.

- [ ] **Step 1: Run every test under system bash**

```bash
/bin/bash ./tests/audit-scan.test.sh
/bin/bash ./tests/cross-link-index.test.sh
/bin/bash ./tests/log-append.test.sh
/bin/bash ./tests/e2e-setup.sh
```

Expected: all four succeed, and `e2e-setup.sh` reports the same assertion count the 5.11.0 branch recorded.

- [ ] **Step 2: Bump the version and description**

Read the current value first:

```bash
grep '"version"' .claude-plugin/plugin.json
```

It should read `5.11.0`; anything else means the 5.11.0 plan has not landed and Task 5's references to `log-append.sh` and `summary:` will not resolve. Change it to `"version": "5.12.0"`, and append to the `description` string before its closing quote:

```
 Note compaction and semantic lint.
```

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git -c user.name="Menotti Minutillo" -c user.email="mminutillo@netflix.com" \
  commit -m "chore(worklog): bump plugin version to 5.12.0"
```

- [ ] **Step 4: Propagate to the local marketplace**

```bash
DEST=/Users/mminutillo/personal-plugins/plugins/obsidian-worklog
rm -rf "$DEST" && mkdir -p "$DEST"
git archive HEAD | tar -x -C "$DEST"
```

- [ ] **Step 5: Substitute the placeholders with Python**

A `grep -Z | while read -d ''` plus `sed -i ''` loop silently no-ops under this shell. Use the same Python pass as the 5.11.0 rollout:

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
            and any(k in p.read_text(errors="ignore") for k in SUBS)]
assert not leftover, "unsubstituted placeholders remain: %r" % leftover
print("no placeholders remain")
PY
```

- [ ] **Step 6: Commit the marketplace copy**

```bash
cd /Users/mminutillo/personal-plugins
git add -A plugins/obsidian-worklog .claude-plugin/marketplace.json
git -c user.name="mminutillo" -c user.email="mminutillo@users.noreply.github.com" \
  commit -m "obsidian-worklog 5.12.0: note compaction and semantic lint"
cd /Users/mminutillo/obsidian-worklog
```

Update the marketplace catalog version to 5.12.0 first if it pins one.

- [ ] **Step 7: Sync and restart (user action)**

Tell the user to run `/plugin marketplace update personal`, confirm the output says `1 plugin bumped`, then restart Claude Code. The cache is version-keyed, so a running session keeps 5.11.0 until restart.

- [ ] **Step 8: Verify the exact substituted command runs**

Run the literal string the installed `SKILL.md` emits, not an equivalent path. This is the 5.8.1 lesson: static review and propagation smoke both passed while the emitted command was broken.

```bash
M=/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
"$M/skills/worklog/scripts/audit-scan.sh" "/Users/mminutillo/Documents/Obsidian Vault" \
  | jq -c 'keys'
```

Expected: all nine keys, sorted.

- [ ] **Step 9: Run `/worklog audit` in a fresh session**

Confirm the three new outputs appear and are presented as distributions with judgment attached, not as raw finding lists. This is a behavior check on the prose from Task 4, and the only way to catch it is to read what the skill actually says.

- [ ] **Step 10: Run the `team:` vocabulary cleanup**

Not a code change. The check is what makes it tractable.

1. `/worklog audit` and read `team_vocabulary`: 86 values, 7 exact, 13 substring, 66 none.
2. Group the values into merge groups. Expect roughly 15 to 20, for example: every SIDE
   variant (`SIDE`, `Secure Infrastructure Design and Engineering`,
   `SIDE - Secure Infrastructure Design and Engineering`); every SPA variant
   (`SPA`, `Security, Privacy & Assurance`, `Infrastructure & Security`); the two
   Detection variants (`Detection & Response` versus `Detection and Response`); the
   acronym-and-full-name pairs (`CIS`, `BSP`, `SPE`, `SSE`, `PSE`, `CATS`).
3. Present one group at a time with explicit options: which canonical `Teams/` note it
   merges into, or which reserved value (`External`, `Former Netflix`, `Unknown`) it maps
   to, or that it needs a new `Teams/` note created. Recommend the most likely option
   first. Do not present all 86 as one checklist.
4. Apply approved merges with `Edit`. Create `Teams/` notes where a group has enough
   members to warrant one. The 7 notes with `team: ?` map to `Unknown`.
5. Re-run the check and confirm every remaining value resolves `exact` or is one of the
   three reserved values.
6. Append one log entry with op `tidy` and target `team: vocabulary`, recording the value
   count before and after.
7. `/worklog sync`.

- [ ] **Step 11: Compact the oversized notes**

One at a time, largest first: Christine Chalmers (1536), Astha Singhal (852), Brian Gaines
(451), Rachel Taylor (335), Laura Haller (334), GenAI Agent Platform (314). Confirm the
link gate reports full preservation on each and read each contradiction report before
moving on. `/worklog sync` between notes, so each fold is its own recoverable commit.

- [ ] **Step 12: Push the branch**

```bash
git push -u origin HEAD
```

`origin` only. Never `upstream`.

---

## Self-Review Notes

**Spec coverage.** Compaction trigger and threshold: Tasks 1, 5. Target shape, fold rules, undated-section rule, retention window: Task 5. Link-preservation gate: Task 5, eval 33. Git precondition: Task 5, eval 36. Six outputs per compaction: Task 5. `oversized_notes`: Task 1. `team_vocabulary`: Task 2. `recurring_tags`: Task 3. The distributions-not-findings rationale: Tasks 2-3 code comments and Task 4 prose. `team:` convention: Task 4. Cleanup sequence: Task 7 step 10. Testing: Tasks 1-3 (unit), Task 6 (evals). Rollout: Task 7. Out-of-scope items are stated in Task 5's closing paragraph rather than silently dropped.

**Interface consistency.** All nine audit keys use the same names in the scanner, the tests, and the `SKILL.md` prose. `resolves` values are exactly `exact`, `substring`, `none` in all three places. `has_page` is a JSON boolean, not a string. Env var names `WORKLOG_COMPACT_LINES`, `WORKLOG_COMPACT_KEEP_DAYS`, `WORKLOG_TAG_MIN_FILES` match between code, tests, and prose.

**Verified before writing.** All three check implementations and every expected value in the Task 1-3 tests were run against a scratch fixture and against the real vault. The real-vault numbers quoted in Tasks 2, 3, and 7 (86 team values, 7 exact, 13 substring, 66 none, 23 recurring tags, 21 without a page, six oversized notes) are measured, not estimated.

**Ordering constraints.** Task 1 step 1 must run before any edit to `audit-scan.sh`. The 5.11.0 plan must be merged before Task 5, which references `log-append.sh` and the `summary:` field.

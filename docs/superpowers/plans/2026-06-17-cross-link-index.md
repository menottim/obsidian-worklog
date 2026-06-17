# Cross-Link Index Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only bash helper (`cross-link-index.sh`) that emits a compact entity/alias JSON digest, so the worklog cross-linking flow stops globbing 343 People/Programs files (and reading bodies) on every write.

**Architecture:** Pure bash 3.2 + `awk`/`sed`/`grep` + `jq`. A pipeline of stages writes tab-separated intermediate files to a `mktemp -d` scratch dir: (1) entities, (2) canonical+derived alias tuples, (3) declared-alias tuples, (4) observed-alias tuples with counts. A single `awk` reducer groups tuples by surface form and resolves collisions (declared-wins → unique → dominance → ambiguous). `jq` assembles the final JSON. Computed fresh each call; nothing persisted.

**Tech Stack:** bash 3.2 (macOS default — no `mapfile`, no `declare -A`), `jq`, `awk`, `sed`, `grep`. Tests are bash scripts asserting against `jq` queries over a synthetic fixture vault.

## Global Constraints

- bash 3.2 compatible: no `mapfile`, no associative bash arrays (`declare -A`). `awk` associative arrays are fine. Use `while IFS= read` loops.
- Read-only: the helper writes nothing inside the vault. Scratch state lives in `mktemp -d`, removed via `trap`.
- No persisted index file; compute fresh each call.
- No new runtime dependencies beyond bash/`jq`/`awk`/`sed`/`grep` (already used by `audit-scan.sh`).
- Invocation path from SKILL.md MUST be `__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh` — `__SKILL_INSTALL_PATH__` is the plugin ROOT, so `skills/worklog/` must be in the path (the v5.8.1 hotfix lesson).
- Entity scope: People + Programs only. Teams are out of scope.
- `DOMINANCE`: a contested alias auto-resolves to its top referent only if `top_count >= DOM_ABS (5)` AND `top_count >= DOM_RATIO (3) * runner_up_count`. Both are env-overridable constants (`CROSSLINK_DOM_ABS`, `CROSSLINK_DOM_RATIO`).
- Alias precedence: declared (frontmatter `aliases:`) > observed (`[[Canonical|alias]]` counts) > derived (first token of multi-word person name).
- Do NOT modify `audit-scan.sh` (protects the eval-9 audit-parity baseline).
- Version bump 5.8.3 → 5.9.0; author commits as `mminutillo <mminutillo@netflix.com>`.

---

### Task 1: Test harness, fixture vault, and helper skeleton

Builds the full pipeline scaffold (entities + empty reducer/assembly) so the helper emits valid JSON with empty aliases. Later tasks only add tuple-generation stages — the reducer and assembly are written once here.

**Files:**
- Create: `skills/worklog/scripts/cross-link-index.sh`
- Create: `tests/cross-link-index.test.sh`
- Create fixture vault under `tests/fixtures/crosslink-vault/` (files listed below)
- Test: `tests/cross-link-index.test.sh`

**Interfaces:**
- Produces: `cross-link-index.sh <vault-path>` → JSON on stdout: `{ "entities": [{canonical, type, aliases, alias_notes?}], "ambiguous": {surface:[candidates]}, "meta": {people, programs, generated_for} }`. Exit 2 on bad/missing vault.

- [ ] **Step 1: Create the fixture vault files**

Create these exact files (content matters — counts and links are asserted later).

`tests/fixtures/crosslink-vault/People/Astha Singhal.md`:
```markdown
---
type: person
---
# Astha Singhal
## Context
- Leader
```
`tests/fixtures/crosslink-vault/People/Brian Gaines.md`:
```markdown
---
type: person
---
# Brian Gaines
```
`tests/fixtures/crosslink-vault/People/Brian Lee.md`:
```markdown
---
type: person
---
# Brian Lee
```
`tests/fixtures/crosslink-vault/People/Dana Wu.md`:
```markdown
---
type: person
---
# Dana Wu
```
`tests/fixtures/crosslink-vault/People/Chris Vincent.md`:
```markdown
---
type: person
---
# Chris Vincent
```
`tests/fixtures/crosslink-vault/People/Chris Park.md`:
```markdown
---
type: person
---
# Chris Park
```
`tests/fixtures/crosslink-vault/People/Jonathan Looney.md`:
```markdown
---
type: person
---
# Jonathan Looney
```
`tests/fixtures/crosslink-vault/People/Madonna.md`:
```markdown
---
type: person
---
# Madonna
```
`tests/fixtures/crosslink-vault/People/Pat Quinn.md`:
```markdown
---
type: person
aliases:
  - Pat
---
# Pat Quinn
```
`tests/fixtures/crosslink-vault/People/Pat Rogers.md`:
```markdown
---
type: person
---
# Pat Rogers
```
`tests/fixtures/crosslink-vault/People/Declared Person.md`:
```markdown
---
type: person
aliases:
  - "DP"
---
# Declared Person
```
`tests/fixtures/crosslink-vault/Programs/Cloud Security.md`:
```markdown
---
type: program
---
# Cloud Security
```
`tests/fixtures/crosslink-vault/Programs/Auth (v2).md`:
```markdown
---
type: program
---
# Auth (v2)
```
`tests/fixtures/crosslink-vault/Worklogs/2026-W20.md` (observed links — exact repetitions):
```markdown
---
programs:
people:
---
# 2026-W20

- [[Brian Gaines|Brian]] met with [[Brian Gaines|Brian]] and [[Brian Gaines|Brian]]
- [[Brian Gaines|Brian]] again, [[Brian Gaines|Brian]], [[Brian Gaines|Brian]]
- [[Brian Lee|Brian]] joined once
- [[Jonathan Looney|JTL]] reviewed, [[Jonathan Looney|JTL]] and [[Jonathan Looney|JTL]]
```
(That is `[[Brian Gaines|Brian]]` ×6, `[[Brian Lee|Brian]]` ×1, `[[Jonathan Looney|JTL]]` ×3.)

- [ ] **Step 2: Write the failing test (Task-1 assertions)**

Create `tests/cross-link-index.test.sh`:
```bash
#!/usr/bin/env bash
# Unit tests for cross-link-index.sh against tests/fixtures/crosslink-vault.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="$HERE/../skills/worklog/scripts/cross-link-index.sh"
FIX="$HERE/fixtures/crosslink-vault"
FAILS=0

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

OUT="$("$HELPER" "$FIX")"
jq_() { printf '%s' "$OUT" | jq -c "$1"; }

# --- Task 1: structure + counts + empty aliases ---
assert_eq "valid json"        "$(printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && echo ok)" "ok"
assert_eq "people count"      "$(jq_ '.meta.people')"   "11"
assert_eq "programs count"    "$(jq_ '.meta.programs')" "2"
assert_eq "entities total"    "$(jq_ '.entities | length')" "13"
assert_eq "metachar program"  "$(jq_ '[.entities[].canonical] | index("Auth (v2)") != null')" "true"
assert_eq "all aliases empty" "$(jq_ '[.entities[].aliases] | add | length')" "0"
assert_eq "ambiguous empty"   "$(jq_ '.ambiguous | length')" "0"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'
```
Make it executable in the same step:
```bash
chmod +x tests/cross-link-index.test.sh
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/cross-link-index.test.sh`
Expected: FAIL — helper does not exist yet (`$HELPER` not found / empty `OUT`, `valid json` assertion fails).

- [ ] **Step 4: Write the helper skeleton**

Create `skills/worklog/scripts/cross-link-index.sh`:
```bash
#!/usr/bin/env bash
# cross-link-index.sh <vault> — emit an entity/alias digest (JSON) for the worklog
# cross-linking flow. Read-only; computes fresh each call (no persisted index).
# bash 3.2; jq/awk/sed/grep. Precedence: declared > observed > derived.
set -euo pipefail

VAULT="${1:?usage: cross-link-index.sh <vault-path>}"
[ -d "$VAULT" ] || { echo "cross-link-index: vault dir not found: $VAULT" >&2; exit 2; }
cd "$VAULT"

DOM_RATIO="${CROSSLINK_DOM_RATIO:-3}"   # top observed count must be >= ratio * runner-up
DOM_ABS="${CROSSLINK_DOM_ABS:-5}"       # AND top must be >= this absolute count

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ENTS="$TMP/ents.tsv"      # canonical \t type
TUP="$TMP/tuples.tsv"     # surface \t canonical \t source(canonical|derived|declared|observed)
OBS="$TMP/observed.tsv"   # surface \t canonical \t count
NAMES="$TMP/names"        # one canonical per line
: > "$ENTS"; : > "$TUP"; : > "$OBS"
shopt -s nullglob

# --- Stage 1: entities (canonical + type) ---
for dir in People Programs; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    name="$(basename "$f" .md)"
    type="$(sed -n 's/^type:[[:space:]]*//p' "$f" | head -1 | tr -d '"' | tr -d "'")"
    [ -n "$type" ] || { case "$dir" in People) type=person;; Programs) type=program;; esac; }
    printf '%s\t%s\n' "$name" "$type" >> "$ENTS"
  done
done
cut -f1 "$ENTS" | sort -u > "$NAMES"

# --- Stage 2: canonical + derived tuples ---  (Task 2 fills this in)
# --- Stage 3: declared tuples ---             (Task 3 fills this in)
# --- Stage 4: observed tuples + counts ---    (Task 4 fills this in)

# --- Reducer: group tuples by surface form, resolve collisions ---
REDUCE="$TMP/reduced.tsv"   # "R" canonical surface dominant(0|1) alts(\x1f-joined)  |  "A" surface candidate
awk -F'\t' -v DOM_RATIO="$DOM_RATIO" -v DOM_ABS="$DOM_ABS" '
  FNR==NR {
    s=$1; c=$2; src=$3; key=s SUBSEP c
    if (!(key in seen)) { seen[key]=1; cand[s]=cand[s] (cand[s]==""?"":"\037") c; ncand[s]++ }
    if (src=="canonical") iscanon[s]=1
    if (src=="declared")  { decl[key]=1; ndecl[s]++; declc[s]=c }
    next
  }
  { cnt[$1 SUBSEP $2]=$3+0 }
  END{
    OFS="\t"
    for (s in cand) {
      if ((s in iscanon) && ncand[s] <= 1) continue       # pure canonical, not an alias
      n=split(cand[s], arr, "\037")
      if (ndecl[s] >= 1) {                                 # declared wins outright
        if (ndecl[s] == 1) { print "R", declc[s], s, 0, ""; continue }
        for (i=1;i<=n;i++) if ((s SUBSEP arr[i]) in decl) print "A", s, arr[i]
        continue
      }
      if (n == 1) { print "R", arr[1], s, 0, ""; continue } # unambiguous
      topc=""; topn=-1; secn=0                              # dominance by observed count
      for (i=1;i<=n;i++) {
        v=cnt[s SUBSEP arr[i]] + 0
        if (v > topn) { secn=(topn<0?0:topn); topc=arr[i]; topn=v }
        else if (v > secn) secn=v
      }
      if (topn >= DOM_ABS && topn >= DOM_RATIO * secn) {
        alts=""
        for (i=1;i<=n;i++) if (arr[i] != topc) alts=alts (alts==""?"":"\037") arr[i]
        print "R", topc, s, 1, alts
      } else {
        for (i=1;i<=n;i++) print "A", s, arr[i]
      }
    }
  }
' "$TUP" "$OBS" > "$REDUCE"

# --- Assembly: build final JSON via jq (jq handles all string escaping) ---
RJSON="$({ grep '^R' "$REDUCE" || true; } | jq -R -s '
  split("\n") | map(select(length>0) | split("\t"))
  | map({canonical: .[1], alias: .[2], dominant: (.[3]=="1"),
         alts: (if (.[4]|length)>0 then (.[4]|split("\u001f")) else [] end)})')"
AJSON="$({ grep '^A' "$REDUCE" || true; } | jq -R -s '
  split("\n") | map(select(length>0) | split("\t"))
  | reduce .[] as $r ({}; .[$r[1]] += [$r[2]]) | map_values(sort)')"
ENTJSON="$(jq -R -s '
  split("\n") | map(select(length>0) | split("\t"))
  | map({canonical: .[0], type: .[1]})' "$ENTS")"

PEOPLE="$(awk -F'\t' '$2=="person"{n++} END{print n+0}' "$ENTS")"
PROGRAMS="$(awk -F'\t' '$2=="program"{n++} END{print n+0}' "$ENTS")"

jq -n \
  --argjson ents "$ENTJSON" \
  --argjson r "$RJSON" \
  --argjson ambiguous "$AJSON" \
  --argjson people "$PEOPLE" \
  --argjson programs "$PROGRAMS" \
  --arg vault "$VAULT" '
  {
    entities: ($ents | map(. as $e
      | ($r | map(select(.canonical == $e.canonical))) as $mine
      | $e + { aliases: ($mine | map(.alias) | unique),
               alias_notes: ($mine | map(select(.dominant)) | map({alias, alts})) }
      | if (.alias_notes | length) == 0 then del(.alias_notes) else . end)),
    ambiguous: $ambiguous,
    meta: { people: $people, programs: $programs, generated_for: $vault }
  }'
```
Make it executable in the same step:
```bash
chmod +x skills/worklog/scripts/cross-link-index.sh
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/cross-link-index.test.sh`
Expected: PASS — all Task-1 assertions pass (13 entities, 11 people / 2 programs, every `aliases` empty, `ambiguous` empty, `Auth (v2)` present).

- [ ] **Step 6: Commit**

```bash
git add skills/worklog/scripts/cross-link-index.sh tests/cross-link-index.test.sh tests/fixtures/crosslink-vault
git -c user.name=mminutillo -c user.email=mminutillo@netflix.com commit -m "feat(cross-link): helper skeleton — entities + meta, empty aliases

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Derived aliases (and canonical tuples)

Emit the canonical-self tuple (so a name isn't treated as its own alias) and a derived first-token alias for multi-word person names. With no observed counts yet, a first name shared by two people resolves to `ambiguous` — which is the correct end-state for un-disambiguated collisions.

**Files:**
- Modify: `skills/worklog/scripts/cross-link-index.sh` (fill in the `Stage 2` block)
- Test: `tests/cross-link-index.test.sh` (append assertions)

**Interfaces:**
- Consumes: `$ENTS` (canonical\ttype), `$TUP`, the reducer (from Task 1).
- Produces: derived aliases in `entities[].aliases`; un-disambiguated same-first-name collisions in `.ambiguous`.

- [ ] **Step 1: Append the failing assertions**

Add before the `if [ "$FAILS" ...` block in `tests/cross-link-index.test.sh`:
```bash
# --- Task 2: derived aliases ---
assert_eq "Astha derived"     "$(jq_ '.entities[] | select(.canonical=="Astha Singhal") | .aliases')" '["Astha"]'
assert_eq "Dana derived"      "$(jq_ '.entities[] | select(.canonical=="Dana Wu") | .aliases')" '["Dana"]'
assert_eq "Madonna no alias"  "$(jq_ '.entities[] | select(.canonical=="Madonna") | .aliases')" '[]'
assert_eq "Jonathan derived"  "$(jq_ '.entities[] | select(.canonical=="Jonathan Looney") | .aliases')" '["Jonathan"]'
assert_eq "Cloud Sec no alias" "$(jq_ '.entities[] | select(.canonical=="Cloud Security") | .aliases')" '[]'
# Brian (no observed yet) and Chris are unresolved collisions -> ambiguous:
assert_eq "Brian ambiguous(t2)"  "$(jq_ '.ambiguous.Brian | sort')" '["Brian Gaines","Brian Lee"]'
assert_eq "Chris ambiguous"      "$(jq_ '.ambiguous.Chris | sort')" '["Chris Park","Chris Vincent"]'
assert_eq "no Brian alias(t2)"   "$(jq_ '[.entities[] | select(.canonical=="Brian Gaines") | .aliases[]] | index("Brian")')" 'null'
```

- [ ] **Step 2: Run the test to verify the new assertions fail**

Run: `bash tests/cross-link-index.test.sh`
Expected: FAIL — `Astha derived` etc. fail (aliases still empty; Stage 2 not implemented).

- [ ] **Step 3: Implement Stage 2**

Replace the line `# --- Stage 2: canonical + derived tuples ---  (Task 2 fills this in)` in `cross-link-index.sh` with:
```bash
# --- Stage 2: canonical + derived tuples ---
while IFS="$(printf '\t')" read -r name type; do
  [ -n "$name" ] || continue
  printf '%s\t%s\tcanonical\n' "$name" "$name" >> "$TUP"
  if [ "$type" = "person" ]; then
    first="${name%% *}"
    [ "$first" != "$name" ] && printf '%s\t%s\tderived\n' "$first" "$name" >> "$TUP"
  fi
done < "$ENTS"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/cross-link-index.test.sh`
Expected: PASS — derived aliases populate; `Brian`/`Chris` land in `.ambiguous`; canonicals are not listed as their own aliases.

- [ ] **Step 5: Commit**

```bash
git add skills/worklog/scripts/cross-link-index.sh tests/cross-link-index.test.sh
git -c user.name=mminutillo -c user.email=mminutillo@netflix.com commit -m "feat(cross-link): derived first-token aliases; collisions -> ambiguous

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Declared aliases (frontmatter `aliases:`)

Parse the `aliases:` YAML list from frontmatter. Declared aliases win outright over derived collisions (the reducer's `ndecl` branch, already written in Task 1).

**Files:**
- Modify: `skills/worklog/scripts/cross-link-index.sh` (fill in the `Stage 3` block)
- Test: `tests/cross-link-index.test.sh` (append + update assertions)

**Interfaces:**
- Consumes: People/Programs frontmatter, `$TUP`, reducer.
- Produces: declared aliases in `entities[].aliases`; declared alias removes its surface form from `.ambiguous`.

- [ ] **Step 1: Update + append assertions**

In `tests/cross-link-index.test.sh`, the `Pat` collision now resolves via the declared alias on `Pat Quinn`. Add:
```bash
# --- Task 3: declared aliases ---
assert_eq "DP declared"        "$(jq_ '.entities[] | select(.canonical=="Declared Person") | .aliases')" '["DP"]'
assert_eq "Pat -> Pat Quinn"   "$(jq_ '[.entities[] | select(.canonical=="Pat Quinn") | .aliases[]] | index("Pat") != null')" 'true'
assert_eq "Pat Rogers no Pat"  "$(jq_ '[.entities[] | select(.canonical=="Pat Rogers") | .aliases[]] | index("Pat")')" 'null'
assert_eq "Pat not ambiguous"  "$(jq_ '.ambiguous | has("Pat")')" 'false'
```

- [ ] **Step 2: Run the test to verify the new assertions fail**

Run: `bash tests/cross-link-index.test.sh`
Expected: FAIL — `DP declared` fails (no declared parsing yet); `Pat` is still ambiguous.

- [ ] **Step 3: Implement Stage 3**

Replace the line `# --- Stage 3: declared tuples ---             (Task 3 fills this in)` with:
```bash
# --- Stage 3: declared tuples (frontmatter aliases: list or inline [a, b]) ---
for dir in People Programs; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    name="$(basename "$f" .md)"
    awk '
      BEGIN{fm=0; ina=0}
      /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
      fm==1 && /^aliases:/{
        rest=$0; sub(/^aliases:[[:space:]]*/,"",rest)
        if (rest ~ /^\[/) {                         # inline: aliases: [A, B]
          gsub(/[][]/,"",rest); m=split(rest,a,",")
          for (i=1;i<=m;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",a[i]); if(a[i]!="") print a[i] }
          ina=0
        } else ina=1
        next
      }
      fm==1 && ina && /^[[:space:]]+-[[:space:]]*/{ item=$0; sub(/^[[:space:]]+-[[:space:]]*/,"",item); print item; next }
      fm==1 && ina && /^[^[:space:]]/{ ina=0 }
    ' "$f" | sed -e 's/^["'\'']//' -e 's/["'\'']$//' | while IFS= read -r al; do
      [ -n "$al" ] && printf '%s\t%s\tdeclared\n' "$al" "$name" >> "$TUP"
    done
  done
done
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/cross-link-index.test.sh`
Expected: PASS — `DP` resolves to `Declared Person`; `Pat` resolves to `Pat Quinn` (declared beats `Pat Rogers`); `Pat` no longer in `.ambiguous`. (`Brian`/`Chris` still ambiguous.)

- [ ] **Step 5: Commit**

```bash
git add skills/worklog/scripts/cross-link-index.sh tests/cross-link-index.test.sh
git -c user.name=mminutillo -c user.email=mminutillo@netflix.com commit -m "feat(cross-link): declared frontmatter aliases (win over derived collisions)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Observed aliases + frequency-based dominance

Mine existing `[[Canonical|alias]]` links, tally counts per (alias, canonical), filter to existing entities, and feed both candidate tuples and counts to the reducer. This activates the dominance branch (already written in Task 1).

**Files:**
- Modify: `skills/worklog/scripts/cross-link-index.sh` (fill in the `Stage 4` block)
- Test: `tests/cross-link-index.test.sh` (append + update assertions)

**Interfaces:**
- Consumes: all vault `.md` files (for `[[x|y]]` mining), `$NAMES`, `$TUP`, `$OBS`, reducer.
- Produces: observed-only aliases (e.g. `JTL`); dominant collision resolution with `alias_notes` + `alts`.

- [ ] **Step 1: Update + append assertions**

`Brian` now resolves to the dominant `Brian Gaines` (6 vs 1); `JTL` becomes an alias. Update the Task-2 Brian assertions and add:
```bash
# --- Task 4: observed aliases + dominance ---
# (REPLACES the two "Brian ambiguous(t2)" / "no Brian alias(t2)" lines from Task 2)
assert_eq "Brian -> Gaines"    "$(jq_ '[.entities[] | select(.canonical=="Brian Gaines") | .aliases[]] | index("Brian") != null')" 'true'
assert_eq "Brian not ambiguous" "$(jq_ '.ambiguous | has("Brian")')" 'false'
assert_eq "Brian alias_notes"  "$(jq_ '.entities[] | select(.canonical=="Brian Gaines") | .alias_notes[0]')" '{"alias":"Brian","alts":["Brian Lee"]}'
assert_eq "Brian Lee no Brian" "$(jq_ '[.entities[] | select(.canonical=="Brian Lee") | .aliases[]] | index("Brian")')" 'null'
assert_eq "JTL observed"       "$(jq_ '[.entities[] | select(.canonical=="Jonathan Looney") | .aliases[]] | index("JTL") != null')" 'true'
# Chris stays ambiguous (no observed links):
assert_eq "Chris still ambig"  "$(jq_ '.ambiguous.Chris | sort')" '["Chris Park","Chris Vincent"]'
```
Delete the two superseded Task-2 lines (`Brian ambiguous(t2)` and `no Brian alias(t2)`); the `Chris ambiguous` line stays.

- [ ] **Step 2: Run the test to verify the new assertions fail**

Run: `bash tests/cross-link-index.test.sh`
Expected: FAIL — `Brian -> Gaines` fails (no observed stage; Brian still ambiguous).

- [ ] **Step 3: Implement Stage 4**

Replace the line `# --- Stage 4: observed tuples + counts ---    (Task 4 fills this in)` with:
```bash
# --- Stage 4: observed tuples + counts (mine [[Canonical|alias]]) ---
grep -rhoE '\[\[[^]]+\|[^]]+\]\]' . 2>/dev/null \
  | sed -E 's/^\[\[//; s/\]\]$//' \
  | awk -F'|' 'NF>=2 { canon=$1; alias=$2; cnt[alias "\t" canon]++ }
               END { for (k in cnt) print k "\t" cnt[k] }' \
  > "$TMP/obs.all"
while IFS="$(printf '\t')" read -r alias canon cnt; do
  [ -n "$alias" ] && [ -n "$canon" ] || continue
  grep -Fxq "$canon" "$NAMES" || continue          # only links to existing People/Programs
  printf '%s\t%s\tobserved\n' "$alias" "$canon" >> "$TUP"
  printf '%s\t%s\t%s\n' "$alias" "$canon" "$cnt"  >> "$OBS"
done < "$TMP/obs.all"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/cross-link-index.test.sh`
Expected: PASS — `Brian` resolves to `Brian Gaines` with `alias_notes:[{alias:"Brian",alts:["Brian Lee"]}]`; `Brian Lee` has no `Brian`; `JTL` is an alias of `Jonathan Looney`; `Chris` remains ambiguous.

- [ ] **Step 5: Commit**

```bash
git add skills/worklog/scripts/cross-link-index.sh tests/cross-link-index.test.sh
git -c user.name=mminutillo -c user.email=mminutillo@netflix.com commit -m "feat(cross-link): observed aliases + frequency dominance resolution

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Error handling and edge cases

Lock in the exit-code contract and the harder edge cases (regex-metachar names, empty vault) with explicit tests. Most behavior already exists; this task proves it and fixes any gaps found.

**Files:**
- Test: `tests/cross-link-index.test.sh` (append a self-contained edge-case block)
- Modify (only if a test fails): `skills/worklog/scripts/cross-link-index.sh`

**Interfaces:**
- Produces: verified exit codes (2 on bad/missing vault) and empty-vault JSON shape.

- [ ] **Step 1: Append the edge-case assertions**

Add before the final `if [ "$FAILS" ...` block:
```bash
# --- Task 5: error handling + edge cases ---
"$HELPER" >/dev/null 2>&1; assert_eq "no-arg exit 2"     "$?" "2"
"$HELPER" /no/such/vault >/dev/null 2>&1; assert_eq "bad-vault exit 2" "$?" "2"
# metachar canonical survives fixed-string matching (already in fixture as "Auth (v2)"):
assert_eq "metachar canonical" "$(jq_ '[.entities[].canonical] | index("Auth (v2)") != null')" "true"
# empty vault -> valid empty shape:
EMPTY="$(mktemp -d)"; mkdir -p "$EMPTY/People" "$EMPTY/Programs"
EOUT="$("$HELPER" "$EMPTY")"
assert_eq "empty entities" "$(printf '%s' "$EOUT" | jq -c '.entities')" "[]"
assert_eq "empty ambiguous" "$(printf '%s' "$EOUT" | jq -c '.ambiguous')" "{}"
assert_eq "empty meta people" "$(printf '%s' "$EOUT" | jq '.meta.people')" "0"
rm -rf "$EMPTY"
```

- [ ] **Step 2: Run the test**

Run: `bash tests/cross-link-index.test.sh`
Expected: PASS for all (the skeleton's `set -euo pipefail`, the `:?` usage guard, the `[ -d ]` check, `grep -Fxq`, and the `nullglob` empty loops already cover these). If any FAIL, fix the helper minimally and re-run until PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/cross-link-index.test.sh skills/worklog/scripts/cross-link-index.sh
git -c user.name=mminutillo -c user.email=mminutillo@netflix.com commit -m "test(cross-link): exit-code contract + metachar + empty-vault edge cases

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Integration — SKILL.md, version bump, eval, real-vault smoke, no-regression

Wire the helper into the cross-linking flow, bump the version, add one behavioral eval, run a smoke against the live vault, and confirm nothing regressed.

**Files:**
- Modify: `skills/worklog/SKILL.md` (the `## Cross-Linking` step 1)
- Modify: `.claude-plugin/plugin.json` (version 5.8.3 → 5.9.0)
- Modify: `evals/evals.json` (append eval id 28)
- Test: run `tests/cross-link-index.test.sh`, `tests/e2e-setup.sh`, `skills/worklog/scripts/audit-scan.sh` against the live vault

**Interfaces:**
- Consumes: the finished `cross-link-index.sh`.
- Produces: a skill that instructs running the helper instead of globbing.

- [ ] **Step 1: Edit SKILL.md cross-linking step 1**

In `skills/worklog/SKILL.md`, find (around line 174):
```
**When writing or updating ANY file in the vault (worklogs, people, programs, archive):**
1. Glob `People/*.md` and `Programs/*.md` to get the current list of known entities
```
Replace the numbered step 1 line with:
```
1. Run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__'` once to get the entity/alias digest. Do NOT glob `People/*.md`/`Programs/*.md` and do NOT read note bodies to resolve aliases. Use `entities[].canonical` as link targets, `entities[].aliases` for partial/case forms, and treat any `ambiguous` surface form as resolve-from-context (ask or leave unlinked rather than guess the wrong person).
```
Leave steps 2–7 unchanged.

- [ ] **Step 2: Bump the plugin version**

In `.claude-plugin/plugin.json`, change `"version": "5.8.3",` to `"version": "5.9.0",`.

- [ ] **Step 3: Append the behavioral eval**

In `evals/evals.json`, append this object as the last element of the `evals` array (after id 27):
```json
{
  "id": 28,
  "prompt": "i'm adding a worklog note: 'Met with Brian and Astha about the Cloud Security migration; Chris is reviewing.' Wrap the people and programs as wiki-links.",
  "expected_output": "Should run cross-link-index.sh (NOT glob People/Programs, NOT read bodies) to get the entity/alias digest. Should link [[Brian Gaines|Brian]] (the dominant referent), [[Astha Singhal|Astha]], and [[Cloud Security]]. For the ambiguous 'Chris' (multiple people, no dominant referent), should ask which Chris or leave it unlinked rather than guessing.",
  "issue_tested": "cross-link-index helper: writes consult the digest instead of globbing; dominant alias auto-links, ambiguous alias is not guessed"
}
```
Verify it parses: `jq -e '.evals[-1].id == 28' evals/evals.json`

- [ ] **Step 4: Run the unit suite + the real-vault smoke**

Run:
```bash
bash tests/cross-link-index.test.sh
skills/worklog/scripts/cross-link-index.sh "$HOME/Documents/Obsidian Vault" \
  | jq '{people: .meta.people, programs: .meta.programs,
         astha: (.entities[] | select(.canonical=="Astha Singhal") | .aliases),
         brian_dominant: ([.entities[] | select(.canonical=="Brian Gaines") | .alias_notes[]?.alias] | index("Brian") != null)}'
```
Expected: unit suite PASS; smoke shows `people: 272`, `programs: 71`, `astha: ["Astha"]`, `brian_dominant: true`. (If `brian_dominant` is `false` because real-vault counts differ, that is data-driven — note it; the spec marks `DOMINANCE` as tunable.)

- [ ] **Step 5: No-regression — e2e + audit parity**

Run:
```bash
bash tests/e2e-setup.sh
skills/worklog/scripts/audit-scan.sh "$HOME/Documents/Obsidian Vault" | jq 'keys'
```
Expected: `e2e-setup.sh` PASS (its existing count, e.g. 48/48); `audit-scan.sh` still emits its six-key object (we did not touch it, so eval 9 parity holds).

- [ ] **Step 6: Commit**

```bash
git add skills/worklog/SKILL.md .claude-plugin/plugin.json evals/evals.json
git -c user.name=mminutillo -c user.email=mminutillo@netflix.com commit -m "feat(cross-link): wire helper into SKILL.md cross-linking; v5.9.0; eval 28

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes for the implementer

- The reducer and jq assembly are written in full in Task 1 but only exercised once Tasks 2–4 add input stages. Do not "simplify" the reducer in Task 1 — its dormant branches (declared-wins, dominance) are activated by later tasks.
- Tab is the field separator throughout (entity names contain spaces but never tabs). `\x1f` (unit separator) joins multi-value fields inside a single TSV cell.
- `set -e` + `grep` returning exit 1 on no-match will abort the script — that is why the assembly wraps `grep '^R'`/`grep '^A'` in `{ ... || true; }`.
- Do not substitute the `__SKILL_INSTALL_PATH__` / `__VAULT_PATH__` placeholders in the fork — SKILL.md stays a template. Substitution happens only when propagating to the live install (separate from this plan).
- Propagation to the running install (republish to `personal-plugins`, `/plugin marketplace update personal`, restart) is a post-merge step, not part of this plan.

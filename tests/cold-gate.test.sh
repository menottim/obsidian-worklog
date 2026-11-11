#!/usr/bin/env bash
# Unit tests for cold-gate.sh. Each case runs against a throwaway git vault.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../skills/worklog/scripts/cold-gate.sh"
FAILS=0

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

V="$(mktemp -d)"; trap 'rm -rf "$V"' EXIT
NOTE="People/Test Person.md"
COLD="Cold/People/Test Person/2026-Q2.md"
mkdir -p "$V/People"
cat > "$V/$NOTE" <<'N'
---
type: person
---

# Test Person

## Role

Staff engineer.

## May 5, 2026 - Kickoff with [[Old Program]]

Discussed scope.

## Jun 20, 2026 - Roadmap

Agreed on the roadmap.

## Sep 30, 2026 - Recent sync

Short sync.
N
git -C "$V" init -q
git -C "$V" add -A
git -C "$V" -c user.name=t -c user.email=t@t commit -qm base

# Reset to a correct move: May and Jun sections go to cold, index added.
good_move() {
  git -C "$V" checkout -q -- . ; git -C "$V" clean -fdq
  mkdir -p "$V/Cold/People/Test Person"
  cat > "$V/$COLD" <<'C'
---
type: cold
parent: "[[Test Person]]"
period: 2026-Q2
moved: 2026-10-07
entries: 2
---

# Test Person: cold storage 2026-Q2

## Jun 20, 2026 - Roadmap

Agreed on the roadmap.

## May 5, 2026 - Kickoff with [[Old Program]]

Discussed scope.
C
  cat > "$V/$NOTE" <<'N'
---
type: person
---

# Test Person

## Role

Staff engineer.

## Sep 30, 2026 - Recent sync

Short sync.

## Cold storage

- Jun 20, 2026 - Roadmap → [[Cold/People/Test Person/2026-Q2|2026-Q2]]
- May 5, 2026 - Kickoff with [[Old Program]] → [[Cold/People/Test Person/2026-Q2|2026-Q2]]
N
}

run() { OUT="$("$GATE" "$V" "$NOTE" "$COLD" 2>&1)"; RC=$?; }

good_move; run
assert_eq "(a) correct move passes"       "$RC" "0"
assert_eq "(a) PASS line"                 "$(printf '%s' "$OUT" | grep -c '^PASS ')" "1"

good_move; sed -i.bak '/Discussed scope/d' "$V/$COLD"; rm -f "$V/$COLD.bak"; run
assert_eq "(b) dropped line fails"        "$RC" "1"
assert_eq "(b) names the lost line"       "$(printf '%s' "$OUT" | grep -c 'Discussed scope')" "1"

good_move
# remove the only link to Old Program from cold and from index, keep all other lines
sed -i.bak 's/\[\[Old Program\]\]/Old Program/' "$V/$COLD" "$V/$NOTE"; rm -f "$V/$COLD.bak" "$V/$NOTE.bak"; run
assert_eq "(c) dropped link target fails" "$RC" "1"
assert_eq "(c) names the link"            "$(printf '%s' "$OUT" | grep -c 'link targets lost: Old Program')" "1"

good_move; sed -i.bak '/Cold\/People/d' "$V/$NOTE"; rm -f "$V/$NOTE.bak"; run
assert_eq "(d) unlinked cold file fails"  "$RC" "1"
assert_eq "(d) reason"                    "$(printf '%s' "$OUT" | grep -c 'cold file not linked')" "1"

good_move; sed -i.bak 's/^type: person/type: people/' "$V/$NOTE"; rm -f "$V/$NOTE.bak"; run
assert_eq "(e) changed frontmatter fails" "$RC" "1"
assert_eq "(e) reason"                    "$(printf '%s' "$OUT" | grep -c 'frontmatter changed')" "1"

good_move; sed -i.bak '/^parent:/d' "$V/$COLD"; rm -f "$V/$COLD.bak"; run
assert_eq "(f) no parent fails"           "$RC" "1"
assert_eq "(f) reason"                    "$(printf '%s' "$OUT" | grep -c 'no parent')" "1"

good_move; "$GATE" "$V" "People/New.md" "$COLD" >/tmp/cg.$$ 2>&1; RC=$?
assert_eq "(g) note missing from base fails" "$RC" "1"
assert_eq "(g) clear message"             "$(grep -c 'not present in base' /tmp/cg.$$)" "1"
rm -f /tmp/cg.$$

# ---- hardening cases. Each builds its own vault W; "base" = committed note (+ optional cold file).
W="$(mktemp -d)"; trap 'rm -rf "$V" "$W"' EXIT
wnote() { # body lines after the heading; writes note with frontmatter
  mkdir -p "$W/People"; { printf -- '---\ntype: person\n---\n\n# Test Person\n\n'; cat; } > "$W/$NOTE"; }
wcold() { # parent-line, body from stdin -> $COLD
  mkdir -p "$W/Cold/People/Test Person"
  { printf -- '---\ntype: cold\n%s\nperiod: 2026-Q2\nmoved: 2026-10-07\nentries: 1\n---\n\n# c\n\n' "$1"; cat; } > "$W/$COLD"; }
winit() { rm -rf "$W"; mkdir -p "$W"; git -C "$W" init -q; }
wcommit() { git -C "$W" add -A; git -C "$W" -c user.name=t -c user.email=t@t commit -qm "$1"; }
wrun() { OUT="$("$GATE" "$W" "$NOTE" "${@:-$COLD}" 2>&1)"; RC=$?; }
IDX='## Cold storage

- x -> [[Cold/People/Test Person/2026-Q2|q]]'

# 1 duplicate lines
winit; printf '## A\n\nsame\n\n## B\n\nsame\n' | wnote; wcommit base
printf '## A\n\nsame\n' > /dev/null
{ printf -- '---\ntype: person\n---\n\n# Test Person\n\n## A\n\nsame\n\n%s\n' "$IDX"; } > "$W/$NOTE"
printf '## B\n' | wcold 'parent: "[[Test Person]]"'
wrun
assert_eq "(h1) dropped duplicate copy fails" "$RC" "1"

# 2 existing cold file must keep its base content and frontmatter
winit; printf '## A\n\nkeep\n\n%s\n' "$IDX" | wnote; printf '## Old\n\nold line\n' | wcold 'parent: "[[Test Person]]"'; wcommit base
echo 'edited' >> "$W/$NOTE"   # note must differ from base
printf '## Old\n' | wcold 'parent: "[[Test Person]]"'; wrun
assert_eq "(h2) existing cold file lost base line fails" "$RC" "1"
printf '## Old\n\nold line\n' | wcold 'parent: "[[Test Person]]"'; sed -i.bak 's/^period: .*/period: 2099-Q1/' "$W/$COLD"; rm -f "$W/$COLD.bak"; wrun
assert_eq "(h2) existing cold frontmatter change fails" "$RC" "1"
printf '## Old\n\nold line\n' | wcold 'parent: "[[Test Person]]"'; sed -i.bak 's/^entries: .*/entries: 9/; s/^moved: .*/moved: 2030-01-01/' "$W/$COLD"; rm -f "$W/$COLD.bak"; wrun
assert_eq "(h2) entries/moved change allowed" "$RC" "0"

# 3 parent value
winit; printf '## A\n\nline a\n\n## B\n\nline b\n' | wnote; wcommit base
{ printf -- '---\ntype: person\n---\n\n# Test Person\n\n## A\n\nline a\n\n%s\n' "$IDX"; } > "$W/$NOTE"
printf '## B\n\nline b\n' | wcold 'parent: "[[Someone Else]]"'; wrun
assert_eq "(h3) wrong parent fails" "$RC" "1"
printf '## B\n\nline b\n' | wcold 'parent: [[Test Person]]'; wrun
assert_eq "(h3) unquoted parent passes" "$RC" "0"

printf '## B\n\nline b\n' | wcold 'parent: "[[People/Test Person|tp]]"'; wrun
assert_eq "(h3) folder-qualified parent passes" "$RC" "0"
printf '## B\n\nline b\n' | wcold 'parent: "[[Threads/Test Person]]"'; wrun
assert_eq "(h3) wrong-folder parent fails" "$RC" "1"
printf '## B\n\nline b\n' | wcold 'parent: [[Test Person]]'; wrun

# 4 note already committed
git -C "$W" add "$NOTE"; git -C "$W" -c user.name=t -c user.email=t@t commit -qm moved
wrun
assert_eq "(h4) committed move fails" "$RC" "1"
assert_eq "(h4) names WORKLOG_COLD_BASE" "$(printf '%s' "$OUT" | grep -c WORKLOG_COLD_BASE)" "1"

# 4b note and cold file committed together
git -C "$W" add -A; git -C "$W" -c user.name=t -c user.email=t@t commit -qm together
wrun
assert_eq "(h4b) committed-together move fails" "$RC" "1"
assert_eq "(h4b) names WORKLOG_COLD_BASE" "$(printf '%s' "$OUT" | grep -c WORKLOG_COLD_BASE)" "1"

# 5-8 false FAILs
winit; printf '## A\n\nline a\n\n## B\n\nline b\n' | wnote; wcommit base
{ printf -- '---\ntype: person\n---\n\n# Test Person\n\n## A\n\nline a\n\n## Cold storage\n\n- x -> [[Cold/People/Test Person/2026-Q2.md|q]]\n'; } > "$W/$NOTE"
printf '## B\n\nline b\n' | wcold 'parent:"[[Test Person]]"'
wrun "./$COLD"
assert_eq "(h5-7) ./ arg, .md link, no-space parent pass" "$RC" "0"
sed -i.bak 's/$/\r/' "$W/$NOTE" "$W/$COLD"; rm -f "$W"/*.bak "$W"/*/*.bak "$W"/*/*/*/*.bak; wrun
assert_eq "(h8) CRLF note and cold pass" "$RC" "0"

# links inside backticks / comments / embeds do not count
for bad in '- x -> `[[Cold/People/Test Person/2026-Q2|q]]`' '<!-- [[Cold/People/Test Person/2026-Q2|q]] -->' '- x -> ![[Cold/People/Test Person/2026-Q2]]'; do
  { printf -- '---\ntype: person\n---\n\n# Test Person\n\n## A\n\nline a\n\n## Cold storage\n\n%s\n' "$bad"; } > "$W/$NOTE"
  wrun; assert_eq "(h9) non-link does not count: $bad" "$RC" "1"
done

# perf: 7000-line note
winit; { for n in $(seq 1 7000); do printf 'line %s\n' "$n"; done; } | wnote; wcommit base
{ printf -- '---\ntype: person\n---\n\n# Test Person\n\n## Cold storage\n\n- x -> [[Cold/People/Test Person/2026-Q2|q]]\n'; } > "$W/$NOTE"
{ for n in $(seq 1 7000); do printf 'line %s\n' "$n"; done; } | wcold 'parent: "[[Test Person]]"'
S=$(date +%s); wrun; E=$(date +%s)
assert_eq "(h10) 7000-line note passes" "$RC" "0"
assert_eq "(h10) under 5s" "$(( E - S < 5 ))" "1"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'

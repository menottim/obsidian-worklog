#!/usr/bin/env bash
# Unit tests for shrink-check.sh. Each case runs against a throwaway git vault.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHK="$HERE/../skills/worklog/scripts/shrink-check.sh"
FAILS=0

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

V="$(mktemp -d)"; trap 'rm -rf "$V"' EXIT
mkdir -p "$V/People" "$V/Logs" "$V/Worklogs"
body() { n=0; while [ "$n" -lt "$1" ]; do printf 'line %03d of the note, some padding text\n' "$n"; n=$((n + 1)); done; }  # 100 lines ~ 4.2 KB
body 100 > "$V/People/Note.md"
body 100 > "$V/People/Space Name.md"
body 100 > "$V/Logs/2026-10.md"
body 100 > "$V/Worklogs/2026-W40.md"
git -C "$V" init -q; git -C "$V" add -A
git -C "$V" -c user.name=t -c user.email=t@t commit -qm base

reset() { git -C "$V" checkout -q HEAD -- . ; git -C "$V" clean -fdq; }
run() { OUT="$(/bin/bash "$CHK" "$V" 2>&1)"; RC=$?; }
runc() { OUT="$(WORKLOG_SHRINK_CONFIRM="$1" /bin/bash "$CHK" "$V" 2>&1)"; RC=$?; }

reset; run
assert_eq "clean tree passes" "$RC" "0"

reset; : > "$V/People/Note.md"; run
assert_eq "emptied note exits 1" "$RC" "1"
assert_eq "emptied note line" "$OUT" "EMPTY People/Note.md"

reset; body 40 > "$V/People/Note.md"; run
assert_eq "60% shrink exits 1" "$RC" "1"
case "$OUT" in "SHRINK People/Note.md: "*" bytes") r=ok ;; *) r="$OUT" ;; esac
assert_eq "60% shrink line" "$r" "ok"

reset; body 60 > "$V/People/Note.md"; run
assert_eq "40% shrink passes" "$RC" "0"
OUT="$(WORKLOG_SHRINK_PCT=30 /bin/bash "$CHK" "$V" 2>&1)"; RC=$?
assert_eq "WORKLOG_SHRINK_PCT=30 flags 40% shrink" "$RC" "1"

reset; rm "$V/People/Note.md"; run
assert_eq "deleted tracked note exits 1" "$RC" "1"
assert_eq "deleted line" "$OUT" "DELETED People/Note.md"

reset; git -C "$V" rm -q People/Note.md; run
assert_eq "staged deletion flags" "$OUT" "DELETED People/Note.md"

reset; { body 30; printf '\n## Cold storage\n\n- old stuff -> [[Cold/People/Note/2026-Q2]]\n'; } > "$V/People/Note.md"; run
assert_eq "cold move passes" "$RC" "0"

reset; { body 30; printf '\n## Cold storage\n\n- old stuff\n'; } > "$V/People/Note.md"; run
assert_eq "cold heading without [[Cold/ link still flags" "$RC" "1"

reset; : > "$V/People/Space Name.md"; run
assert_eq "path with spaces" "$OUT" "EMPTY People/Space Name.md"

reset; : > "$V/Logs/2026-10.md"; run
assert_eq "Logs shrink ignored" "$RC" "0"

reset; : > "$V/People/Note.md"; git -C "$V" add People/Note.md; run
assert_eq "staged emptied note flags" "$RC" "1"

reset; printf 'new\n' > "$V/People/New.md"; run
assert_eq "untracked new note ignored" "$RC" "0"

reset; mkdir -p "$V/Archive"; mv "$V/Worklogs/2026-W40.md" "$V/Archive/2026-W40.md"; run
assert_eq "archive move passes" "$RC" "0"

reset; rm "$V/Worklogs/2026-W40.md"; run
assert_eq "Worklogs deletion without archive copy still flags" "$OUT" "DELETED Worklogs/2026-W40.md"

reset; rm "$V/People/Note.md"; mkdir -p "$V/Archive"; : > "$V/Archive/Note.md"; run
assert_eq "archive copy only exempts Worklogs, People deletion still flags" "$OUT" "DELETED People/Note.md"

reset; rm "$V/People/Note.md" "$V/Worklogs/2026-W40.md"; runc "Worklogs/2026-W40.md"
assert_eq "confirmed path is skipped" "$OUT" "DELETED People/Note.md"
assert_eq "unconfirmed path in same run still exits 1" "$RC" "1"

reset; : > "$V/People/Space Name.md"; runc "$(printf 'Worklogs/x.md\nPeople/Space Name.md')"
assert_eq "confirm list with a spaced path skips it" "$RC" "0"

reset; : > "$V/People/Space Name.md"; runc "People/Space"
assert_eq "confirm match is exact, a prefix does not skip" "$RC" "1"

OUT="$(/bin/bash "$CHK" 2>&1)"; RC=$?
assert_eq "missing arg exits 2" "$RC" "2"
OUT="$(/bin/bash "$CHK" /tmp 2>&1)"; RC=$?
assert_eq "not a git repo exits 2" "$RC" "2"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'

#!/usr/bin/env bash
# Unit tests for auto-sync.sh. Each case runs against a throwaway vault.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AS="$HERE/../skills/worklog/scripts/auto-sync.sh"
FAILS=0

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
V="$T/vault dir"; mkdir -p "$V"
NOTE="$V/Preferences/Auto Sync.md"

OUT="$(/bin/bash "$AS" "$V" get 2>/dev/null)"; RC=$?
assert_eq "get without note prints unset" "$OUT" "unset"
assert_eq "get without note exits 0" "$RC" "0"

/bin/bash "$AS" "$V" set on first-run; RC=$?
assert_eq "set on new vault exits 0" "$RC" "0"
assert_eq "new note has type: preference" "$(grep -cx 'type: preference' "$NOTE")" "1"
assert_eq "new note has auto_sync: on" "$(grep -cx 'auto_sync: on' "$NOTE")" "1"
assert_eq "new note records via first-run" "$(grep -c 'via first-run\.' "$NOTE")" "1"
OUT="$(/bin/bash "$AS" "$V" get)"
assert_eq "get after set on prints on" "$OUT" "on"

/bin/bash "$AS" "$V" set off user; RC=$?
assert_eq "set off on existing note exits 0" "$RC" "0"
assert_eq "exactly one auto_sync line" "$(grep -c '^auto_sync:' "$NOTE")" "1"
assert_eq "auto_sync line is now off" "$(grep '^auto_sync:' "$NOTE")" "auto_sync: off"
assert_eq "appends set to off via user line" "$(grep -c '^- .*: set to off via user\.$' "$NOTE")" "1"
assert_eq "original Chosen on line kept" "$(grep -c '^Chosen on .* via first-run\.$' "$NOTE")" "1"
OUT="$(/bin/bash "$AS" "$V" get)"
assert_eq "get after set off prints off" "$OUT" "off"

V2="$T/vault two"; mkdir -p "$V2/Preferences"
printf -- '---\ntype: preference\nauto_sync: maybe\n---\n\n# Auto Sync\n' > "$V2/Preferences/Auto Sync.md"
OUT="$(/bin/bash "$AS" "$V2" get 2>"$T/err")"; RC=$?
assert_eq "invalid value prints invalid" "$OUT" "invalid"
assert_eq "invalid value exits 0" "$RC" "0"
assert_eq "invalid value warns on stderr" "$(cat "$T/err")" "auto-sync: Preferences/Auto Sync.md has auto_sync: maybe; treating as off"

G="$T/not git"; mkdir -p "$G"
OUT="$(/bin/bash "$AS" "$G" can-sync)"; RC=$?
assert_eq "can-sync on non-git dir exits 1" "$RC" "1"
assert_eq "can-sync on non-git dir reason" "$OUT" "not a git repo"

GIT="$T/git vault"; mkdir -p "$GIT"; git -C "$GIT" init -q
OUT="$(/bin/bash "$AS" "$GIT" can-sync)"; RC=$?
assert_eq "can-sync on git repo without remote exits 1" "$RC" "1"
assert_eq "can-sync on git repo without remote reason" "$OUT" "no backup remote"

git init -q --bare "$T/remote.git"
git -C "$GIT" remote add origin "$T/remote.git"
OUT="$(/bin/bash "$AS" "$GIT" can-sync)"; RC=$?
assert_eq "can-sync with origin exits 0" "$RC" "0"
assert_eq "can-sync with origin prints nothing" "$OUT" ""

# A vault folder nested in a parent repo with an origin is not its own repo.
PARENT="$T/parent repo"; mkdir -p "$PARENT/vault nested"
git -C "$PARENT" init -q
git -C "$PARENT" remote add origin "$T/remote.git"
OUT="$(/bin/bash "$AS" "$PARENT/vault nested" can-sync)"; RC=$?
assert_eq "can-sync on nested vault exits 1" "$RC" "1"
assert_eq "can-sync on nested vault reason" "$OUT" "not a git repo"

# A symlink to a top-level repo with an origin resolves to that repo.
LINK="$T/link to git vault"; ln -s "$GIT" "$LINK"
OUT="$(/bin/bash "$AS" "$LINK" can-sync)"; RC=$?
assert_eq "can-sync through symlink to top-level repo exits 0" "$RC" "0"
assert_eq "can-sync through symlink prints nothing" "$OUT" ""

V3="$T/vault three"; mkdir -p "$V3"
/bin/bash "$AS" "$V3" set on setup
IDX="$(bash "$HERE/../skills/worklog/scripts/preferences-index.sh" "$V3")"
assert_eq "preferences-index reads applies-to inline list" "$(printf '%s\n' "$IDX" | grep -cF '"applies_to":["workflow","sync"]')" "1"

/bin/bash "$AS" "$V" set bogus user >/dev/null 2>&1; RC=$?
assert_eq "set with bad value exits 2" "$RC" "2"

# get: one pair of quotes, a trailing comment and a CR are not part of the value.
V4="$T/vault four"; mkdir -p "$V4/Preferences"
get_line() { # get_line <text after auto_sync:>: writes a note with that line, prints get
  printf -- '---\ntype: preference\nauto_sync: %s\n---\n\n# Auto Sync\n' "$1" > "$V4/Preferences/Auto Sync.md"
  /bin/bash "$AS" "$V4" get 2>/dev/null
}
assert_eq "get strips double quotes around on" "$(get_line '"on"')" "on"
assert_eq "get strips single quotes around off" "$(get_line "'off'")" "off"
assert_eq "get strips a trailing comment" "$(get_line 'on # x')" "on"
assert_eq "get keeps mismatched quotes invalid" "$(get_line '"on')" "invalid"
printf -- '---\r\ntype: preference\r\nauto_sync: on\r\n---\r\n' > "$V4/Preferences/Auto Sync.md"
assert_eq "get accepts a CRLF on" "$(/bin/bash "$AS" "$V4" get 2>/dev/null)" "on"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'

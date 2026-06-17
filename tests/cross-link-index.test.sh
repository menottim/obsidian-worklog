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

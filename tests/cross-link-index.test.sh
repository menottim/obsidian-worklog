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
assert_eq "alias count(t1)"   "$(jq_ '[.entities[].aliases] | add | length')" "4"
assert_eq "ambiguous count(t1)" "$(jq_ '.ambiguous | length')" "3"

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

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'

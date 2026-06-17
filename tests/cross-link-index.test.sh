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
assert_eq "alias count(t4)"   "$(jq_ '[.entities[].aliases] | add | length')" "8"
assert_eq "ambiguous count(t4)" "$(jq_ '.ambiguous | length')" "1"

# --- Task 2: derived aliases ---
assert_eq "Astha derived"     "$(jq_ '.entities[] | select(.canonical=="Astha Singhal") | .aliases')" '["Astha"]'
assert_eq "Dana derived"      "$(jq_ '.entities[] | select(.canonical=="Dana Wu") | .aliases')" '["Dana"]'
assert_eq "Madonna no alias"  "$(jq_ '.entities[] | select(.canonical=="Madonna") | .aliases')" '[]'
assert_eq "Jonathan derived"  "$(jq_ '[.entities[] | select(.canonical=="Jonathan Looney") | .aliases[]] | index("Jonathan") != null')" 'true'
assert_eq "Cloud Sec no alias" "$(jq_ '.entities[] | select(.canonical=="Cloud Security") | .aliases')" '[]'
assert_eq "Chris ambiguous"      "$(jq_ '.ambiguous.Chris | sort')" '["Chris Park","Chris Vincent"]'

# --- Task 4: observed aliases + dominance ---
assert_eq "Brian -> Gaines"    "$(jq_ '[.entities[] | select(.canonical=="Brian Gaines") | .aliases[]] | index("Brian") != null')" 'true'
assert_eq "Brian not ambiguous" "$(jq_ '.ambiguous | has("Brian")')" 'false'
assert_eq "Brian alias_notes"  "$(jq_ '.entities[] | select(.canonical=="Brian Gaines") | .alias_notes[0]')" '{"alias":"Brian","alts":["Brian Lee"]}'
assert_eq "Brian Lee no Brian" "$(jq_ '[.entities[] | select(.canonical=="Brian Lee") | .aliases[]] | index("Brian")')" 'null'
assert_eq "JTL observed"       "$(jq_ '[.entities[] | select(.canonical=="Jonathan Looney") | .aliases[]] | index("JTL") != null')" 'true'
# Chris stays ambiguous (no observed links):
assert_eq "Chris still ambig"  "$(jq_ '.ambiguous.Chris | sort')" '["Chris Park","Chris Vincent"]'

# --- Task 3: declared aliases ---
assert_eq "DP declared"        "$(jq_ '.entities[] | select(.canonical=="Declared Person") | .aliases')" '["DP","Declared"]'
assert_eq "Pat -> Pat Quinn"   "$(jq_ '[.entities[] | select(.canonical=="Pat Quinn") | .aliases[]] | index("Pat") != null')" 'true'
assert_eq "Pat Rogers no Pat"  "$(jq_ '[.entities[] | select(.canonical=="Pat Rogers") | .aliases[]] | index("Pat")')" 'null'
assert_eq "Pat not ambiguous"  "$(jq_ '.ambiguous | has("Pat")')" 'false'

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

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'

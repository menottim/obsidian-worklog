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
assert_eq "limit 11: five oversized"   "$(o11 '.oversized_notes | length')" "5"
assert_eq "limit 11: Big One lines"    "$(o11 '.oversized_notes[] | select(.file=="People/Big One.md") | .lines')" "12"
assert_eq "limit 11: Big One compacted null" \
  "$(o11 '.oversized_notes[] | select(.file=="People/Big One.md") | .compacted')" "null"
assert_eq "limit 11: double-quoted compacted stripped" \
  "$(o11 '.oversized_notes[] | select(.file=="People/Big Compacted.md") | .compacted')" '"2026-07-01"'
assert_eq "limit 11: single-quoted compacted stripped" \
  "$(o11 '.oversized_notes[] | select(.file=="People/Big Compacted Single Quote.md") | .compacted')" '"2026-07-02"'
assert_eq "limit 11: Programs covered" \
  "$(o11 '[.oversized_notes[].file] | index("Programs/Big Program.md") != null')" "true"
assert_eq "limit 11: no-trailing-newline file counted by awk, not wc -l" \
  "$(o11 '.oversized_notes[] | select(.file=="People/No Trailing Newline.md") | .lines')" "12"

# --- exact-boundary exclusion: -gt semantics, not -ge ---
O12="$(WORKLOG_COMPACT_LINES=12 "$HELPER" "$FIX")"
o12() { printf '%s' "$O12" | jq -c "$1"; }
assert_eq "limit 12: 12-line file excluded at the boundary" \
  "$(o12 '[.oversized_notes[].file] | index("People/Big One.md")')" "null"
assert_eq "limit 12: 13-line file still included" \
  "$(o12 '[.oversized_notes[].file] | index("Programs/Big Program.md") != null')" "true"

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

# --- empty vault must not block on stdin (a possibly-empty glob leaves grep reading it) ---
HT="$(mktemp -d)"; mkdir -p "$HT/People" "$HT/Programs"; mkfifo "$HT/f"
sleep 10 > "$HT/f" &            # writer holds the fifo open and never writes
HTW=$!
"$HELPER" "$HT" < "$HT/f" > "$HT/out" 2>/dev/null &
HTS=$!
hti=0
while [ "$hti" -lt 5 ]; do kill -0 "$HTS" 2>/dev/null || break; sleep 1; hti=$((hti+1)); done
if kill -0 "$HTS" 2>/dev/null; then kill -9 "$HTS" 2>/dev/null; HTR="hung"; else HTR="returned"; fi
kill -9 "$HTW" 2>/dev/null
assert_eq "empty vault does not block on stdin" "$HTR" "returned"
rm -rf "$HT"

"$HELPER" >/dev/null 2>&1;                assert_eq "no-arg nonzero" "$([ $? -ne 0 ] && echo nonzero)" "nonzero"
"$HELPER" /no/such/vault >/dev/null 2>&1; assert_eq "bad-vault exit 2" "$?" "2"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'

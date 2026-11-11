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
assert_eq "twelve keys"       "$(jq_ 'keys | length')" "12"

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
  "$(tv 'Cloud Platform Engineering' | jq -c '.notes')" "2"
assert_eq "tv: substring resolution" \
  "$(tv 'Cloud Platform Engineering' | jq -c '.resolves')" '"substring"'
assert_eq "tv: substring candidate" \
  "$(tv 'Cloud Platform Engineering' | jq -c '.candidate')" '"CPE - Cloud Platform Engineering"'
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

# --- cold_candidates / cold_integrity ---
CV="$(mktemp -d)"; mkdir -p "$CV/People" "$CV/Threads" "$CV/Programs" "$CV/Cold/People/Pat" "$CV/Cold/Threads/t1"
pad() { awk -v n="$1" 'BEGIN{for(i=0;i<n;i++) print "filler line to add bytes for the cold scan test xxxxxxxxxxxx"}'; }
{ printf -- '---\ntype: person\n---\n# Pat\n## Role\n'; pad 100
  printf '## Jul 30, 2026 - old 1:1\n'; pad 100
  printf '## Sep 20-21, 2026 - new 1:1\n'; pad 100; } > "$CV/People/Pat.md"
{ printf -- '---\ntype: thread\n---\n# T1\n## Context\n'; pad 100
  printf '## Aug 20, 2026 - 47 days old, past 30 but inside the People 60\n'; pad 100; } > "$CV/Threads/t1.md"
{ printf -- '---\ntype: program\n---\n# Prog\n## History\n'; pad 100
  printf '## Oct 1, 2026\n'; pad 100; } > "$CV/Programs/Prog.md"
{ printf -- '---\ntype: person\n---\n# Small\n## Jan 5, 2026 - old but tiny\n'; pad 10; } > "$CV/People/Small.md"
{ printf -- '---\ntype: person\n---\n# Dana\n## Context\n'; pad 10
  printf '### Jan 5, 2026 - inside current-state, never moves\n'; pad 100
  printf '## Meeting Notes\n'; pad 5
  printf '### Jul 2, 2026 - old 1:1\n'; pad 100
  printf '### Sep 30, 2026 - recent 1:1\n'; pad 100
  printf '### Jun 3, 2026 - second old\n'; pad 100; } > "$CV/People/Dana.md"
CO="$(WORKLOG_TODAY=2026-10-07 "$HELPER" "$CV")"
co() { printf '%s' "$CO" | jq -c "$1"; }
assert_eq "cold: only old section counted (People)" \
  "$(co '.cold_candidates[] | select(.path=="People/Pat.md") | [.sections, (.movable_bytes < .total_bytes), (.movable_bytes > 5000 and .movable_bytes < 7000)]')" "[1,true,true]"
assert_eq "cold: dated ### under undated ## container counted, current-state ### not" \
  "$(co '.cold_candidates[] | select(.path=="People/Dana.md") | [.sections, (.movable_bytes > 11000 and .movable_bytes < 13000)]')" "[2,true]"
assert_eq "cold: Thread 30-day rule catches Aug 20" \
  "$(co '.cold_candidates[] | select(.path=="Threads/t1.md") | .sections')" "1"
assert_eq "cold: History section counted regardless of date, new dated one not" \
  "$(co '.cold_candidates[] | select(.path=="Programs/Prog.md") | .sections')" "1"
assert_eq "cold: under min KB excluded" "$(co '[.cold_candidates[].path] | index("People/Small.md")')" "null"
assert_eq "cold: sorted largest first" "$(co '[.cold_candidates[].movable_bytes] == ([.cold_candidates[].movable_bytes] | sort | reverse)')" "true"
assert_eq "cold: min KB 0 includes Small" \
  "$(WORKLOG_COLD_MIN_KB=0 WORKLOG_TODAY=2026-10-07 "$HELPER" "$CV" | jq -c '[.cold_candidates[].path] | index("People/Small.md") != null')" "true"
assert_eq "cold: People window 30 days widens count" \
  "$(WORKLOG_COLD_DAYS_PEOPLE=10 WORKLOG_TODAY=2026-10-07 "$HELPER" "$CV" | jq -c '.cold_candidates[] | select(.path=="People/Pat.md") | .sections')" "2"
assert_eq "cold: no Cold/ files, no links: integrity empty" "$(co '.cold_integrity')" "[]"

# healthy cold setup
printf -- '---\ntype: cold\nparent: "[[Pat]]"\n---\n# Pat: cold storage 2026-Q3\n' > "$CV/Cold/People/Pat/2026-Q3.md"
printf '\n## Cold storage\n\nMoved.\n\n- Jul 30, 2026 - x → [[Cold/People/Pat/2026-Q3|2026-Q3]]\n' >> "$CV/People/Pat.md"
assert_eq "cold: healthy setup integrity empty" \
  "$(WORKLOG_TODAY=2026-10-07 "$HELPER" "$CV" | jq -c '.cold_integrity')" "[]"

# three problems
printf '\n## Cold storage\n\n- x → [[Cold/Threads/t1/2026-Q3|2026-Q3]]\n- y → [[Cold/Threads/t1/2026-Q2|2026-Q2]]\n' >> "$CV/Threads/t1.md"
printf -- '- z → [[Cold/Threads/t1/2026-Q2|2026-Q2]]\n' >> "$CV/Threads/t1.md"   # second line, same missing target
printf -- '---\ntype: cold\n---\n# t1 cold\n' > "$CV/Cold/Threads/t1/2026-Q3.md"
printf -- '---\ntype: cold\nparent: "[[Pat]]"\n---\n# orphan\n' > "$CV/Cold/People/Pat/2025-Q1.md"
CI="$(WORKLOG_TODAY=2026-10-07 "$HELPER" "$CV" | jq -c '.cold_integrity')"
assert_eq "integrity: missing link target" \
  "$(printf '%s' "$CI" | jq -c '[.[] | select(.path=="Threads/t1.md" and (.problem|startswith("link target missing")) and (.problem|endswith("2026-Q2")))] | length')" "1"
assert_eq "integrity: no parent key" \
  "$(printf '%s' "$CI" | jq -c '[.[] | select(.path=="Cold/Threads/t1/2026-Q3.md" and .problem=="no parent: frontmatter key")] | length')" "1"
assert_eq "integrity: unlinked cold file" \
  "$(printf '%s' "$CI" | jq -c '[.[] | select(.path=="Cold/People/Pat/2025-Q1.md" and (.problem|startswith("no warm note")))] | length')" "1"
assert_eq "integrity: exactly three problems" "$(printf '%s' "$CI" | jq -c 'length')" "3"
# regression: a link list past the pipe buffer (~64 KB) must not flag linked files
awk 'BEGIN{for(i=0;i<3000;i++) printf "- padding entry %d with a long label to grow the index -> [[Cold/People/Pat/2026-Q3|2026-Q3]]\n", i}' >> "$CV/People/Pat.md"
assert_eq "integrity: large index still sees linked file" \
  "$(WORKLOG_TODAY=2026-10-07 "$HELPER" "$CV" | jq -c '[.cold_integrity[] | select(.path=="Cold/People/Pat/2026-Q3.md")] | length')" "0"
rm -rf "$CV"

# --- cold_candidates: heading shapes, exclusions, fences, History, bytes (today 2026-10-07, People cut 2026-08-08) ---
HV="$(mktemp -d)"; mkdir -p "$HV/People"
mk() { { printf -- '---\ntype: person\n---\n# %s\n' "$1"; shift; for h in "$@"; do printf '%s\n' "$h"; pad 100; done; } > "$HV/People/$name.md"; }
name=ex_state;   mk x '## Current State (May 4, 2026)'
name=ex_status;  mk x '## Status (as of Jul 4, 2026)'
name=ex_lower;   mk x '## status (Jul 4, 2026)'
name=ex_child;   mk x '## Context' '### Jul 4, 2026 - child of excluded'
name=ex_roleplay; mk x '## Roleplay Jul 4, 2026'
name=ex_roledef; mk x '## Role Definition Landed (May 1, 2026)'
name=yl_dash;    mk x '## Jul 30 - 1:1'
name=yl_text;    mk x '## May 28 1:1 outcomes'
name=yl_child;   mk x '## Meeting Notes' '### Feature X (Apr 22)' '### (Apr 30 - May 1)'
name=yl_prev;    mk x '## Nov 5'
name=yl_recent;  mk x '## Oct 5'
name=sh_nocomma; mk x '## Jul 30 2026'
name=sh_month;   mk x '## Jul 2026 Recap'
name=sh_monthnew; mk x '## Aug 2026'
name=sh_iso;     mk x '## 2026-07-30'
name=sh_full;    mk x '## July 30, 2026'
name=sh_sept;    mk x '## Sept 3, 2026 notes'
name=sh_bold;    mk x '## **Jul 30, 2026** - bold'
name=sh_wd;      mk x '## Thu, Jul 30, 2026'
name=sh_trail;   mk x '## 1:1 with Sam (Jul 30, 2026)'
name=rg_end_new; mk x '## Aug 5-12, 2026'
name=rg_end_old; mk x '## Jul 5-12, 2026'
name=rg_future;  mk x '## Dec 30 - Jan 2, 2027'
name=rg_yl;      mk x '## Dec 30 - Jan 2'
name=wb_mar;     mk x '## Remark 12, 2026'
name=wb_may;     mk x '## Mayor 4 2026'
name=fe_code;    mk x '## Notes' '```' '## Jul 4, 2026 fake heading in code' '```'
name=hi_empty;   { printf -- '---\ntype: person\n---\n# x\n## History\n\n'; pad 0; printf '## Oct 5, 2026\n'; pad 100; } > "$HV/People/hi_empty.md"
name=hi_full;    { printf -- '---\ntype: person\n---\n# x\n## History\n'; pad 100; } > "$HV/People/hi_full.md"
# cont must reset per file: a_ ends inside a container, b_ starts with a ### before any ##
{ printf -- '---\ntype: person\n---\n# a\n## Meeting Notes\n'; pad 1; } > "$HV/People/a_cont.md"
{ printf '### Jul 2, 2026 - orphan child\n'; pad 100; } > "$HV/People/b_cont.md"
# fence state must reset per file too: c_ ends inside an unclosed fence, d_ has a real old heading
{ printf -- '---\ntype: person\n---\n# c\n```\n'; pad 1; } > "$HV/People/c_fence.md"
{ printf '# d\n## Jul 4, 2026\n'; pad 100; } > "$HV/People/d_fence.md"
HO="$(WORKLOG_TODAY=2026-10-07 "$HELPER" "$HV")"
cs() { printf '%s' "$HO" | jq -c ".cold_candidates[] | select(.path==\"People/$1.md\") | .sections"; }
for n in ex_state ex_status ex_lower ex_child yl_recent sh_monthnew rg_end_new rg_future wb_mar wb_may fe_code hi_empty b_cont c_fence; do
  assert_eq "cold shape: $n not movable" "$(cs $n)" ""
done
for n in ex_roleplay ex_roledef yl_dash yl_text yl_prev sh_nocomma sh_month sh_iso sh_full sh_bold sh_wd sh_trail rg_end_old rg_yl hi_full d_fence; do
  assert_eq "cold shape: $n movable" "$(cs $n)" "1"
done
assert_eq "cold shape: year-less ### children (Apr 22, Apr 30 - May 1)" "$(cs yl_child)" "2"
assert_eq "cold shape: Sept 3, 2026 recent, not movable" "$(cs sh_sept)" ""
rm -rf "$HV"

# bytes: movable_bytes is bytes, not characters, and emoji headings do not break awk
EV="$(mktemp -d)"; mkdir -p "$EV/People"
printf -- '---\ntype: person\n---\n# E\n## Jul 4, 2026 🔒 sensitive\n' > "$EV/People/E.md"
pad 100 >> "$EV/People/E.md"; printf '## Oct 5, 2026 ✅\n' >> "$EV/People/E.md"
EW="$(printf '## Jul 4, 2026 🔒 sensitive\n'; pad 100)"; EWB="$(printf '%s\n' "$EW" | LC_ALL=C wc -c | tr -d ' ')"
EE="$(LC_ALL=en_US.UTF-8 WORKLOG_TODAY=2026-10-07 "$HELPER" "$EV" 2>"$EV/err")"
assert_eq "bytes: emoji heading, no awk error" "$(cat "$EV/err")" ""
assert_eq "bytes: movable_bytes counts bytes" "$(printf '%s' "$EE" | jq -c '.cold_candidates[0].movable_bytes')" "$EWB"
rm -rf "$EV"

# integrity: parent: without a space; temp files removed
IV="$(mktemp -d)"; mkdir -p "$IV/People" "$IV/Cold/People/Pat" "$IV/tmp"
printf -- '---\ntype: person\n---\n# Pat\n## Cold storage\n\n- x -> [[Cold/People/Pat/2026-Q3|q]]\n' > "$IV/People/Pat.md"
printf -- '---\ntype: cold\nparent:[[Pat]]\n---\n# c\n' > "$IV/Cold/People/Pat/2026-Q3.md"
II="$(TMPDIR="$IV/tmp" "$HELPER" "$IV" | jq -c '.cold_integrity')"
assert_eq "integrity: parent: with no space accepted" "$II" "[]"
assert_eq "integrity: temp files cleaned up" "$(ls "$IV/tmp" | wc -l | tr -d ' ')" "0"
printf -- '---\ntype: cold\nparent:\n---\n# c\n' > "$IV/Cold/People/Pat/2026-Q3.md"
assert_eq "integrity: empty parent: flagged" \
  "$("$HELPER" "$IV" | jq -c '[.cold_integrity[].problem]')" '["no parent: frontmatter key"]'
rm -rf "$IV"

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

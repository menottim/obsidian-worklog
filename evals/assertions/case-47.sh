#!/usr/bin/env bash
# Case 47: /worklog cold moves old unpinned entries verbatim and leaves everything else.
#
# What is graded is whether the move is SAFE and whether it happened:
#   - the two old unpinned entries are in a cold file and gone from the warm body
#   - the old entry with an open Eval User action stayed warm (pin)
#   - the recent entry and the Role section stayed warm
#   - cold-gate.sh prints PASS against the pre-move revision (nothing lost)
#   - the warm note has a Cold storage index linking the cold file
#   - the operations log has a cold entry and a local commit exists
#
# A run that summarizes the old entries, or moves the pinned one, passes every eye test
# and fails here.
. "$(dirname "$0")/_lib.sh"

NOTE="People/Dana Whitfield.md"
WARM="$VAULT/$NOTE"
COLD_DIR="$VAULT/Cold/People/Dana Whitfield"
GATE="$(cd "$(dirname "$0")/.." && pwd)/../skills/worklog/scripts/cold-gate.sh"

COLD_FILES=()
while IFS= read -r f; do COLD_FILES+=("${f#$VAULT/}"); done < <(ls "$COLD_DIR"/*.md 2>/dev/null)
check "a cold file was written under Cold/People/Dana Whitfield/" \
      "$([ "${#COLD_FILES[@]}" -ge 1 ] && echo 0 || echo 1)"

COLD_TEXT="$(cat "$COLD_DIR"/*.md 2>/dev/null)"
# warm body without the Cold storage section, which legitimately repeats labels
WARM_BODY="$(awk '/^## Cold storage/{exit} {print}' "$WARM")"

grep -q 'Vendor onboarding sync' <<<"$COLD_TEXT"; check "the 120-day-old entry is in cold storage" $?
grep -q 'Access review kickoff' <<<"$COLD_TEXT";  check "the 100-day-old entry is in cold storage" $?
! grep -q 'Vendor onboarding sync' <<<"$WARM_BODY"; check "the 120-day-old entry left the warm body" $?
! grep -q 'Access review kickoff' <<<"$WARM_BODY";  check "the 100-day-old entry left the warm body" $?

grep -q 'Leveling follow-up' <<<"$WARM_BODY"; check "the pinned entry (open Eval User action) stayed warm" $?
! grep -q 'Leveling follow-up' <<<"$COLD_TEXT"; check "the pinned entry was not copied to cold" $?
grep -q 'Quarterly check-in' <<<"$WARM_BODY"; check "the recent entry stayed warm" $?
grep -q '^## Role' "$WARM" && grep -q 'Vendor-risk lead' "$WARM"; check "the Role section stayed warm" $?

grep -q '^## Cold storage' "$WARM"; check "the warm note has a Cold storage section" $?
grep -q 'Cold/People/Dana Whitfield/' "$WARM"; check "the index links the cold file" $?

FIXTURE="$(git -C "$VAULT" log --format=%H --grep='fixture: cold note' -n 1)"
if [ -n "$FIXTURE" ] && [ "${#COLD_FILES[@]}" -ge 1 ]; then
  GATE_OUT="$(WORKLOG_COLD_BASE="$FIXTURE" "$GATE" "$VAULT" "$NOTE" "${COLD_FILES[@]}" 2>&1 | tail -1)"
  case "$GATE_OUT" in PASS*) check "cold-gate.sh prints PASS against the fixture revision" 0 ;;
                      *)     check "cold-gate.sh prints PASS against the fixture revision ($GATE_OUT)" 1 ;; esac
else
  check "cold-gate.sh could run (fixture commit and cold file present)" 1
fi

grep -qE '^## \[[0-9-]+\] cold \| ' "$VAULT"/Logs/*.md 2>/dev/null; check "the operations log has a cold entry" $?
git -C "$VAULT" log --format=%s | grep -q '^worklog cold '; check "a local worklog cold commit exists" $?

exit $FAILS

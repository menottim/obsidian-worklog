#!/usr/bin/env bash
# Case 2: /worklog review updates the current week in place. It must not create
# a new week file or archive anything, and it must walk items ONE AT A TIME.
#
# The protocol is the thing under test. An earlier version of this check counted
# how many item titles appeared in the output, which rewarded the model that
# dumped all four at once - exactly the behavior SKILL.md prohibits.
. "$(dirname "$0")/_lib.sh"

[ "$(week_files)" -eq 1 ]; check "no new week file" $?
! changed_in "Archive/"; check "nothing archived" $?
grep -q '^status: active' "$WEEK_FILE"; check "week still marked active" $?

# The denominator is the model's call - 4 active items, or 5 counting the Done
# one - so match any N/M rather than hardcoding the total.
COUNTERS="$(grep -oE '[0-9]+/[0-9]+' "$OUT" | sort -u | tr '\n' ' ')"
N="$(grep -oE '[0-9]+/[0-9]+' "$OUT" | sort -u | grep -c .)"
[ "$N" -eq 1 ]; check "presented exactly one item, not a batch dump (counters: ${COUNTERS:-none})" $?
grep -qE '(^|[^0-9])1/[0-9]+' "$OUT"; check "started at the first item" $?
exit $FAILS

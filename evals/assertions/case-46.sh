#!/usr/bin/env bash
# Case 46: a DM candidate matches a parked Backlog entry. The reply approves the
# recommended option. If the skill checked the Backlog, that option is Wake: the parked
# entry leaves Backlog.md, its Thread goes live, and the week file gains the item exactly
# once. If it did not, it creates a new item beside the parked copy and leaves the
# Backlog entry in place, which is the duplicate this case exists to catch.
. "$(dirname "$0")/_lib.sh"

! grep -q 'Parked - On-call rotation restructure' "$VAULT/Worklogs/Backlog.md"
check "the parked entry left Backlog.md" $?

grep -q '^status: live' "$VAULT/Threads/on-call-rotation-restructure-tiering-proposal.md"
check "the existing Thread went live" $?

N="$(ls "$VAULT"/Threads/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$N" -eq 1 ]; check "no second Thread was created ($N)" $?

HITS="$(grep -ci 'on-call rotation' "$WEEK_FILE")"
[ "$HITS" -ge 1 ]; check "the item is in the week file" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 7 ]; check "exactly one top-level item was added (found $TOP)" $?

exit $FAILS

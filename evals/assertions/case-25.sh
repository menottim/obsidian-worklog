#!/usr/bin/env bash
# Case 25: exclude_users / exclude_conversations must drop matching DM items
# before classification. No approval is scripted, so nothing should fold, but
# the included item's content still needs to reach the approval batch in $OUT
# while the excluded items' content never reaches $OUT or the vault at all.
. "$(dirname "$0")/_lib.sh"

grep -qi 'budget review' "$OUT"; check "the non-excluded DM item reached the approval batch" $?

! grep -qi 'personal health' "$OUT"; check "the user-excluded DM item did not reach the approval batch" $?
! grep -qi 'blocked channel group' "$OUT"; check "the conversation-excluded DM item did not reach the approval batch" $?

! grep -rqi 'personal health\|blocked channel group' "$VAULT/Worklogs" "$VAULT/People" "$VAULT/Programs" 2>/dev/null
check "no excluded DM content ever reached the vault" $?

grep -q 'last_scan_ts: *[^n]' "$VAULT/Sources/_dms.md"; check "the DM source advanced last_scan_ts (sweep completed)" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "no DM-derived top-level item was added (found $TOP)" $?

exit $FAILS

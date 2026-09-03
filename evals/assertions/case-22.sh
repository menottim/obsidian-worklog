#!/usr/bin/env bash
# Case 22: a DM result clearly matches the tracked Platform Migration item.
# Unlike a context-channel high-confidence match, a DM one is never
# auto-folded - it still goes to the approval batch, leading with the
# recommended "attach as a sub-item" option. No approval is scripted, so
# nothing should be written.
. "$(dirname "$0")/_lib.sh"

grep -qi 'platform migration' "$OUT"; check "the batch entry names the matched item" $?
grep -qi 'canary deploy' "$OUT"; check "the DM candidate's content reached the approval batch" $?
grep -qiE 'attach.{0,20}sub-item' "$OUT"; check "the batch leads with an attach-as-sub-item option" $?
grep -qi 'recommend' "$OUT"; check "the attach option is marked recommended" $?

! grep -rqi 'canary deploy' "$VAULT/Worklogs" "$VAULT/People" "$VAULT/Programs" 2>/dev/null
check "the high-confidence DM match was not auto-folded into the vault" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "no top-level item was added while the batch is unresolved (found $TOP)" $?

exit $FAILS

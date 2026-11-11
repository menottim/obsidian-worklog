#!/usr/bin/env bash
# Case 40: the vault is not a git repository at all (case-40.sh strips .git
# after make-vault commits it). There is no undo available, so this refusal
# must be unconditional - no dirty-language, no sync offer, no proceed-anyway
# path. This is the not-a-repo half of the precondition that case 36 leaves
# uncovered.
. "$(dirname "$0")/_lib.sh"

NOTE="$VAULT/People/Bryce Gale.md"

! grep -qE '^compacted:' "$NOTE"; check "refused to compact an un-versioned vault" $?
! grep -q '^## History' "$NOTE"; check "no History fold was written" $?
! changed_in "People/Bryce Gale.md"; check "the target note is untouched" $?

grep -qiE 'not (a |under )?git|no git|not version.controlled|no undo|do not compact' "$OUT"
check "explained the vault is not under git and there is no undo" $?

! grep -qiE 'uncommitted|dirty|git status|sync' "$OUT"
check "did not degrade into dirty-vault language" $?

! grep -qiE 'proceed anyway|continue anyway|go ahead anyway' "$OUT"
check "did not offer a proceed-anyway path" $?
exit $FAILS

#!/usr/bin/env bash
# Case 36: the vault has uncommitted changes. Compaction is lossy and git
# history is the only undo, so the fold must not happen. The refusal is specific:
# offer /worklog sync, and if it does not run or the re-check still reports
# dirty, name the outstanding files and stop.
#
# Only the dirty half of this case is covered. The not-a-repo half needs a second
# run against a non-git vault and a different refusal, and the runner sends one
# prompt per run.
. "$(dirname "$0")/_lib.sh"

NOTE="$VAULT/People/Theo Kask.md"

! grep -qE '^compacted:' "$NOTE"; check "refused to compact a dirty vault" $?
! grep -q '^## History' "$NOTE"; check "no History fold was written" $?
! changed_in "People/Theo Kask.md"; check "the target note is untouched" $?

grep -qiE 'uncommitted|dirty|clean|git' "$OUT"; check "explained that the vault state blocks it" $?
grep -qiE 'sync|commit' "$OUT"; check "offered the sync route" $?
grep -qiE 'Dev Sharma|Untracked Scratch|outstanding' "$OUT"
check "named the outstanding files" $?
exit $FAILS

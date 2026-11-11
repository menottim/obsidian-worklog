#!/usr/bin/env bash
# Case 18: a context-channel window containing only banter and logistics. Noise
# drops silently. The sweep still happened, so the scan timestamp advances and
# the pull is logged - absence of worklog changes is the correct outcome, not
# absence of any record that the sweep ran.
. "$(dirname "$0")/_lib.sh"

! changed_in "Worklogs/"; check "no worklog items written from noise" $?
! changed_in "People/"; check "no People notes touched" $?
! changed_in "Programs/"; check "no Programs notes touched" $?
! changed_in "Meetings/"; check "no Meetings note created (wrong source type)" $?

for t in espresso game 'lunch truck' 'office is closed'; do
  ! grep -rqiF "$t" "$VAULT/Worklogs" "$VAULT/People" "$VAULT/Programs" 2>/dev/null
  check "banter not folded anywhere: $t" $?
done

grep -q 'last_scan_ts: *[^n]' "$VAULT/Sources/platform-leads.md"; check "last_scan_ts advanced off null" $?
grep -rqE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] pull \|' "$VAULT"/Logs/*.md; check "ops log has a pull entry" $?
exit $FAILS

#!/usr/bin/env bash
# Case 16: a context-channel thread that clearly names a tracked program folds
# into the EXISTING worklog item as a dated sub-item with a Slack permalink. It
# must not become a new top-level item, and the banter sharing its window must
# not survive the sweep.
#
# Every content check reads the DIFF, not the file. The fixture already contains
# the words "cutover" and "data-tier step", so grepping the file scored a run
# that wrote nothing at all as having folded the context in.
. "$(dirname "$0")/_lib.sh"

ADDED="$(grep '^+' "$DIFF" 2>/dev/null | grep -v '^+++')"

changed_in "Worklogs/$CUR_WEEK.md"; check "current week file updated" $?
printf '%s' "$ADDED" | grep -qiE 'data.tier|replication lag|rollback path'
check "cutover context folded in (as an added line)" $?
printf '%s' "$ADDED" | grep -qF 'example.slack.com/archives'
check "Slack permalink recorded as provenance" $?

# The fold belongs under the existing P0 item, as an indented sub-item.
awk '/^- \*\*P[0-9]\*\*.*[Cc]utover/{f=1;next} /^- \*\*P/{f=0} f && /^ +- .*(data.tier|replication|slack)/{hit=1} END{exit !hit}' "$WEEK_FILE"
check "folded as a sub-item under the existing cutover item" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 5 ]; check "no new top-level item created (found $TOP, fixture has 5)" $?

! printf '%s' "$ADDED" | grep -qiE 'espresso|coffee machine'; check "banter dropped, not folded" $?
grep -q 'last_scan_ts: *[^n]' "$VAULT/Sources/infrasec-leads.md"; check "last_scan_ts advanced off null" $?
grep -rqE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] pull \|' "$VAULT"/Logs/*.md; check "ops log has a pull entry" $?
exit $FAILS

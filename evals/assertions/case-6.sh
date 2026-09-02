#!/usr/bin/env bash
# Case 6: pasted 1:1 notes fold into existing items as dated sub-items.
#
# This is the ingest path - the one command where the measurements say model
# choice actually matters - and it was unmeasured until now. Three facts go in:
# the migration timeline slipping, wanting a contractor for the gap, and Marcus
# picking up Dev's work. All three should land as sub-items under items that
# already exist, none should become a new top-level item.
#
# Deliberately not asserted: which item each fact lands under. That is judgment,
# and more than one placement is defensible. What is checked is that nothing was
# invented, nothing was duplicated, and the log matches what is on disk.
. "$(dirname "$0")/_lib.sh"

ADDED="$(grep '^+' "$DIFF" 2>/dev/null | grep -v '^+++')"

changed_in "Worklogs/$CUR_WEEK.md"; check "current week file updated" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "no new top-level item created (found $TOP, fixture has 6)" $?

# All three facts have to survive the ingest.
printf '%s' "$ADDED" | grep -qiE 'timeline|slipping|slip'
check "migration timeline concern captured" $?
printf '%s' "$ADDED" | grep -qiE 'contractor'
check "contractor ask captured" $?
printf '%s' "$ADDED" | grep -qiE 'marcus'
check "Marcus picking up Dev's work captured" $?

# Sub-items, not top-level, and dated per the item format.
printf '%s' "$ADDED" | grep -qE '^\+[[:space:]]+- '
check "written as indented sub-items" $?
printf '%s' "$ADDED" | grep -qE '\([A-Z][a-z]{2} [0-9]{1,2}\)'
check "sub-items carry a (Mon D) date" $?

# Known entities get linked rather than left as bare text.
printf '%s' "$ADDED" | grep -qF '[[Marcus Williams'
check "Marcus Williams wiki-linked" $?

# Nothing invented: the notes name no other people or programs.
! printf '%s' "$ADDED" | grep -qiE 'espresso|offsite|service mesh'
check "no content invented from outside the notes" $?

# The #19 check: a log entry must not claim work the file does not show.
if grep -rqE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] (ingest|add|review) \|' "$VAULT"/Logs/*.md 2>/dev/null; then
  changed_in "Worklogs/$CUR_WEEK.md"
  check "ops log entry is backed by an actual week-file change" $?
else
  no "ops log has an entry for the ingest"
fi
exit $FAILS

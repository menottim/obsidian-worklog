#!/usr/bin/env bash
# Case 1: mid-week natural-language add. Two items land in the EXISTING week
# file, a stub is created for the unknown person, and nothing rolls over.
. "$(dirname "$0")/_lib.sh"

[ "$(week_files)" -eq 1 ]; check "no second week file created" $?
! changed_in "Archive/"; check "Archive untouched" $?
changed_in "Worklogs/$CUR_WEEK.md"; check "current week file modified" $?
grep -qiE 'offsite|venue' "$WEEK_FILE"; check "offsite/venue item present" $?
grep -qiE 'service mesh|security review' "$WEEK_FILE"; check "service mesh review item present" $?
ls "$VAULT"/People/Alex*.md >/dev/null 2>&1; check "People stub created for Alex" $?
grep -q '^status: active' "$WEEK_FILE"; check "week still marked active" $?
exit $FAILS

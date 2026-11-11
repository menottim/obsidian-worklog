#!/usr/bin/env bash
# Case 43: a plain /worklog add. Targets model routing's inline fallback:
# with no Agent tool, Opus running a Haiku command prints one line before the
# work and then proceeds, never halting to ask. This script grades what is deterministic across every
# config (the item lands, the run never asks); the note's presence and its
# Opus-only scope are checked manually per run (see evals/run.sh --configs),
# since the assertion script has no access to which model ran it.
. "$(dirname "$0")/_lib.sh"

changed_in "Worklogs/$CUR_WEEK.md"; check "current week file modified" $?
grep -qi 'vendor security questionnaire' "$WEEK_FILE"; check "item present in week file" $?
grep -qi 'platform migration' "$WEEK_FILE"; check "filed under Platform Migration" $?

! grep -qiE '\?\s*$|which model|switch (to|models)|would you like|do you want' "$OUT"; check "run never halted to ask about model choice" $?
exit $FAILS

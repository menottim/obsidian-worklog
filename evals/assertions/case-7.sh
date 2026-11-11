#!/usr/bin/env bash
# Case 7: /worklog summary month.
#
# This case exists as much to guard progressive disclosure as to test summary
# itself: the command's rules now live in references/summary.md, so a run that
# ignores the stub and works from memory shows up here as a missing or
# malformed Summaries file.
#
# The fixture has three archived weeks plus the active one. Only first-run
# behavior is checked - the overwrite-warning half of the case needs two runs
# in one session, which the runner does not do yet.
. "$(dirname "$0")/_lib.sh"

SUM="$(ls "$VAULT"/Summaries/*.md 2>/dev/null | head -1)"

# Calendar edge: the fixture's archives are the three weeks before today, so
# early in a month a "month" summary has no completed weeks in range. Declining
# with that reason stated is correct, and scoring it as a failure would make this
# case fail or pass depending on the day it ran.
if [ -z "$SUM" ]; then
  # Match the substance, not one phrasing. Every correct decline says the period
  # has nothing in it; runs have worded that as "no weeks exist", "outside the
  # requested range" and "the September window is currently empty".
  grep -qiE 'no (completed )?weeks|no weekly file|outside the (requested )?range|window is (currently )?empty|period is (currently )?empty|nothing (complete|to summarize|in range)' "$OUT"
  check "empty range explained rather than a file invented" $?
  [ "$(changed_count)" -eq 0 ]; check "nothing written for an empty range" $?
  exit $FAILS
fi

changed_in "Summaries/"; check "Summaries file shows in the diff" $?
head -1 "$SUM" | grep -q '^---'; check "summary has frontmatter" $?
grep -qE '^type:' "$SUM"; check "frontmatter declares a type" $?

# Content has to come from the archives, not be invented.
HITS=0
for t in 'Platform Migration' 'Backend EM Hiring' 'Cloud Security'; do
  grep -qiF "$t" "$SUM" && HITS=$((HITS + 1))
done
[ "$HITS" -ge 2 ]; check "summary draws on archived programs (got $HITS of 3)" $?

! grep -qiE 'espresso|lunch truck' "$SUM"; check "no invented content" $?
grep -rqE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] summary \|' "$VAULT"/Logs/*.md; check "ops log has a summary entry" $?
exit $FAILS

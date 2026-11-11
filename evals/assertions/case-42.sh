#!/usr/bin/env bash
# Case 42: bare /worklog plus a substantial multi-entity paste, no explicit
# "add it" ask. Targets the blob-routing gap: a bare /worklog matches the
# ### /worklog or /worklog status heading literally, and the old ingest
# trigger required an explicit ask the invocation never makes. The failure
# mode is a status table printed while the paste is read into context, paid
# for, and silently dropped.
. "$(dirname "$0")/_lib.sh"

changed_in "Worklogs/$CUR_WEEK.md"; check "current week file modified" $?
grep -qi 'checkout redesign\|onboarding flow' "$WEEK_FILE"; check "Priya's beta rollout item present" $?
grep -qi 'fraud.scoring\|retrain' "$WEEK_FILE"; check "Diego's retrain follow-up present" $?
grep -qi 'sandbox api key\|payments team' "$WEEK_FILE"; check "Sam's blocker present" $?
grep -qi 'loyalty.points' "$WEEK_FILE"; check "loyalty-points deprioritization present" $?
grep -qi 'alex kim' "$WEEK_FILE"; check "Alex Kim's start present" $?

for p in Priya Diego Sam 'Alex Kim'; do
  ls "$VAULT"/People/${p%% *}*.md >/dev/null 2>&1
  check "People stub created for $p" $?
done

grep -rqE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] ' "$VAULT"/Logs/*.md 2>/dev/null; check "ops log entry appended" $?

# The failure mode this exists to catch: a status table (active-items summary
# with no reference to any of the pasted content) instead of routing to ingest.
! grep -qi 'no worklog changes\|nothing to (add|fold)' "$OUT"; check "did not report a no-op status instead of ingesting" $?
exit $FAILS

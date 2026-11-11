#!/usr/bin/env bash
# Case 23: same high-confidence DM match as case 22, but this time the user
# approves the batch's recommended "attach as a sub-item" option. The fold
# must land as a sub-item (not a new top-level item), genericized rather than
# a verbatim quote, dated from the DM's message_ts, and carry the permalink
# as provenance. Frontmatter only regenerates when a top-level item is added,
# so item-count should be untouched by a pure sub-item add.
. "$(dirname "$0")/_lib.sh"

PERMA="$(grep -co 'example.slack.com/archives' "$WEEK_FILE")"
[ "$PERMA" -eq 1 ]; check "the fold carries the DM permalink as provenance ($PERMA)" $?

! grep -qF "I found a permissions bug in the canary deploy step, needs a fix before we go" "$WEEK_FILE"
check "the fold is genericized, not a verbatim quote of the DM" $?

grep -qiE 'canary|permission' "$WEEK_FILE"; check "the fold keeps the topic of the DM" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "the fold attached as a sub-item, not a new top-level item (found $TOP)" $?

grep -q 'item-count: 6' "$WEEK_FILE"
check "frontmatter did not regenerate for a sub-item-only add" $?

exit $FAILS

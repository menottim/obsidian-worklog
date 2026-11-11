#!/usr/bin/env bash
# Case 45: the DM sweep must not run as a single generic query. The stub helper only
# returns the group DM when some stdin query names Priya or Theo, mirroring how the real
# relevance-ranked search hides group DMs from a generic query. The stub records every
# stdin line next to the scenario file.
. "$(dirname "$0")/_lib.sh"

LOG="$(dirname "$STREAM")/dm-scenario.json.stdin"
N="$(grep -c . "$LOG" 2>/dev/null || echo 0)"
[ "$N" -ge 2 ]; check "the helper received several queries on stdin, not one generic query ($N)" $?

grep -qiE 'priya|bryce' "$LOG" 2>/dev/null; check "the queries include a name from the vault" $?

grep -qi 'on-call rotation' "$OUT"; check "the group DM candidate reached the approval batch" $?

! grep -rqi 'on-call rotation' "$VAULT/Worklogs" "$VAULT/People" "$VAULT/Programs" 2>/dev/null
check "the group DM was not auto-folded into the vault" $?

exit $FAILS

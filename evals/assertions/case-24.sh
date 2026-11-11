#!/usr/bin/env bash
# Case 24: the DM helper is missing, unauthorized, or consent was never
# granted, so it exits non-zero. The DM sweep must skip with a one-line note
# and the rest of the pull (the channel sweep) must complete normally.
. "$(dirname "$0")/_lib.sh"

grep -qiE 'dm|direct message' "$OUT" && grep -qiE 'skip(ped)?' "$OUT"
check "DM sweep skipped note printed" $?
grep -qi 'missing_scope\|missing scope' "$OUT"; check "the skip note names the reason" $?

# The channel sweep is unaffected by the DM helper failing.
HITS="$(grep -ci 'replication lag' "$WEEK_FILE")"
[ "$HITS" -eq 1 ]; check "channel sweep still folded normally ($HITS)" $?

grep -qE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] pull \|' "$VAULT"/Logs/*.md
check "the pull is still logged" $?

# The sweep never completed, so last_scan_ts on the DM source stays null.
grep -q 'last_scan_ts: null' "$VAULT/Sources/_dms.md"
check "DM last_scan_ts did not advance on a failed sweep" $?

exit $FAILS

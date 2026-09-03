#!/usr/bin/env bash
# Case 27: max_results caps the DM sweep at 2, but a third page is still
# waiting. The skill must stop before classifying and ask to proceed, narrow,
# or skip, rather than silently truncating or silently continuing.
. "$(dirname "$0")/_lib.sh"

grep -qiE '[0-9]+.{0,15}(dm|message|result)' "$OUT"; check "the collected count is named in the output" $?
grep -qiE 'proceed|narrow|skip' "$OUT"; check "the guardrail offers a proceed/narrow/skip choice" $?
grep -qiE 'more|additional|remain|cursor|available|further|beyond' "$OUT"; check "the output signals more DM results exist beyond the cap" $?

# No approval was scripted, so nothing should have been classified or written.
TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "classification did not run past the guardrail (found $TOP top-level items)" $?

! grep -rqi 'vendor contract renewal\|on-call rotation swap\|design review follow-up' \
    "$VAULT/Worklogs" "$VAULT/People" "$VAULT/Programs" 2>/dev/null
check "no DM content reached the vault before the guardrail was resolved" $?

# The sweep did not complete, so last_scan_ts must stay null.
grep -q 'last_scan_ts: null' "$VAULT/Sources/_dms.md"
check "DM last_scan_ts did not advance while the guardrail is unresolved" $?

exit $FAILS

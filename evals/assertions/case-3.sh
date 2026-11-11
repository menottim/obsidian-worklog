#!/usr/bin/env bash
# Case 3: /worklog audit. A read-only audit writes nothing, reports what the
# scanner actually found, and invents nothing it did not.
#
# The fixture is built so the scanner's answer is known and fixed:
#   stale_people 3 (Bryce Lee, Dev Sharma, Marcus Williams)
#   empty_stubs  3 (the three Programs notes)
#   frontmatter_gaps 3 (the three Archive weeks)
#   stuck_items 0, orphan_programs 0, missing_links 0, oversized_notes 0
#
# An earlier version of this check just counted how many category words appeared
# in the output, which scored verbosity rather than fidelity. Report the true
# findings and stay quiet about the empty ones, in whatever words you like.
. "$(dirname "$0")/_lib.sh"

[ "$(changed_count)" -eq 0 ]; check "read-only audit left the vault unchanged" $?
! grep -qiE 'traceback|command not found|no such file|line [0-9]+: ' "$OUT"; check "no script error surfaced" $?
[ "$(wc -c < "$OUT" | tr -d ' ')" -gt 200 ]; check "audit produced a real report" $?

# --- the three real findings must surface, by name or by count ---
hits() { # <count-word> <member>... - true if the count or any member appears
  local want="$1"; shift
  grep -qiE "$want" "$OUT" && return 0
  for m in "$@"; do grep -qiF "$m" "$OUT" && return 0; done
  return 1
}
hits '3 stale|three stale' 'Bryce Lee' 'Dev Sharma' 'Marcus Williams'
check "reports the stale People finding" $?
hits '3 empty|three empty' 'Backend EM Hiring' 'Cloud Security' 'Platform Migration'
check "reports the empty Programs stubs" $?
hits '3 frontmatter|three frontmatter|frontmatter gap' 'Archive/'
check "reports the Archive frontmatter gaps" $?

# --- and must not invent the four empty ones ---
! grep -qiE '[1-9][0-9]* stuck|stuck items?:? *[1-9]' "$OUT"; check "claims no stuck items (scanner found 0)" $?
! grep -qiE '[1-9][0-9]* orphan|orphan programs?:? *[1-9]' "$OUT"; check "claims no orphan programs (scanner found 0)" $?
! grep -qiE '[1-9][0-9]* oversized|oversized notes?:? *[1-9]' "$OUT"; check "claims no oversized notes (scanner found 0)" $?
exit $FAILS

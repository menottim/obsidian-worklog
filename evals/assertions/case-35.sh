#!/usr/bin/env bash
# Case 35: /worklog compact with no argument. Run the scanner, then offer the
# candidates ONE AT A TIME, largest first. Not a single free-text checklist of
# everything oversized, and no moving on without a decision on the one before.
#
# The fixture's oversized notes, largest first: Nadia Okafor, Theo Kask,
# Ines Duarte, Sofia Brandt, Kenji Watanabe.
. "$(dirname "$0")/_lib.sh"

[ "$(changed_count)" -eq 0 ]; check "offered rather than compacting anything unasked" $?

grep -qF 'Nadia Okafor' "$OUT"; check "offered the largest candidate first" $?

# Listing what the scanner found is fine and useful. What the rule forbids is
# asking for a decision on all of them at once, so check for a batch ask rather
# than for the other names appearing at all.
! grep -qiE 'which (ones|of these)|all of them|reply with the numbers|pick any|comma.separated' "$OUT"
check "did not ask for a bulk decision across candidates" $?
grep -qE '\?|Want to start|start with' "$OUT"
check "asked for a decision on where to start" $?
exit $FAILS

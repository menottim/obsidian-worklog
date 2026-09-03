#!/usr/bin/env bash
# Case 37: an already-compacted note. Existing ## History bullets are immutable -
# never re-folded or re-summarized, even when a newly-aged entry continues the
# same theme. The retention window runs from today, not from the last compaction.
#
# As with case 32, compaction stops for approval, so this reads the proposal.
. "$(dirname "$0")/_lib.sh"

NOTE="$VAULT/People/Rachel Taylor.md"

[ "$(changed_count)" -eq 0 ]; check "wrote nothing before approval" $?

# -- so grep does not read a leading-dash bullet as an option.
grep -qF -- '- Apr 2026: took over detection tooling and reset the roadmap. IMMUTABLE-MARKER-A' "$NOTE"
check "existing History bullet A intact on disk" $?
grep -qF -- '- Mar 2026: onboarded two engineers onto the rotation. IMMUTABLE-MARKER-B' "$NOTE"
check "existing History bullet B intact on disk" $?

# Quoting the existing bullets to say they are being left alone is correct, so
# there is no inverse check on mentioning them. What matters is that the proposal
# commits to leaving them, and that they are still intact on disk above.
grep -qiE 'immutab|not touching|unchanged|untouched|re-summariz' "$OUT"
check "proposal commits to leaving existing History alone" $?
grep -qiE 'append|new bullet|adding' "$OUT"
check "proposal adds the newly-aged entry as its own bullet" $?

# The 70-day-old entry is past the window measured from today; the 12-day-old is not.
grep -qiE 'Aged past the window' "$OUT"
check "proposal picks up the newly-aged entry" $?
! grep -qiE 'Inside the keep window[^\n]{0,60}(fold|History)' "$OUT"
check "proposal leaves the in-window entry in Recent" $?
exit $FAILS

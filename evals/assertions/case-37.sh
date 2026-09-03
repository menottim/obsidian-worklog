#!/usr/bin/env bash
# Case 37: an already-compacted note, taken through approval so the WRITTEN file
# can be checked rather than the proposal prose.
#
# The rules under test: existing ## History bullets are immutable - never
# re-folded or re-summarized even when a newly-aged entry continues the same
# theme - and the retention window is measured from today, not from the date of
# the last compaction. The newly-aged entry joins as its own new bullet.
#
# The approval gate itself is covered by cases 32, 36 and 38, which stay
# single-turn and assert that nothing is written before a human answers.
. "$(dirname "$0")/_lib.sh"

NOTE="$VAULT/People/Rachel Taylor.md"

changed_in "People/Rachel Taylor.md"; check "the fold was written after approval" $?
grep -qiE 'propos|before writing|approve' "$OUT"; check "a proposal was shown before writing" $?

# Immutability, checked on disk. -- so grep does not read a leading-dash bullet
# as an option.
grep -qF -- '- Apr 2026: took over detection tooling and reset the roadmap. IMMUTABLE-MARKER-A' "$NOTE"
check "existing History bullet A survived the write byte-identical" $?
grep -qF -- '- Mar 2026: onboarded two engineers onto the rotation. IMMUTABLE-MARKER-B' "$NOTE"
check "existing History bullet B survived the write byte-identical" $?

# The 70-day-old entry is past the window measured from today; the 12-day-old is not.
! grep -q 'Aged past the window since the last compaction' "$NOTE"
check "the newly-aged entry left ## Recent" $?
grep -q 'Inside the keep window' "$NOTE"
check "the in-window entry stayed in ## Recent" $?

HIST="$(awk '/^## History/{f=1;next} /^## /{f=0} f && /^- /' "$NOTE" | grep -c .)"
[ "${HIST:-0}" -ge 3 ]
check "History gained a bullet rather than absorbing into an existing one (found $HIST)" $?

TODAY="$(date +%Y-%m-%d)"
grep -qF "compacted: $TODAY" "$NOTE"; check "compacted: updated to today" $?
exit $FAILS

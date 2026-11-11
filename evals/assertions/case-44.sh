#!/usr/bin/env bash
# Case 44: rollover must apply the retention rule from references/threads.md.
#
# This is the path that produced the 953 KB week file the rule exists to
# prevent: the old rollover step 3 read "Collect all items NOT Done" and said
# nothing about sub-items, so an item that survived ten weeks carried ten weeks
# of dated sub-items with it. Nothing here grades prose quality. What is graded
# is whether the spill is SAFE and whether it actually happened:
#
#   - the copy exists before the prune (a Thread note, with the spilled text)
#   - nothing was lost (every pre-rollover sub-item line still exists somewhere)
#   - the week file actually got shorter for that item
#   - the open action survived regardless of its age (threads.md rule 3)
#   - the dormant item left the week file rather than riding along
#
# A rollover that writes a tidy new week and quietly drops history passes every
# eye test and fails this case, which is the whole point.
. "$(dirname "$0")/_lib.sh"

PREV_WEEK="$(git -C "$VAULT" show HEAD:Worklogs/ 2>/dev/null >/dev/null && echo ok)"
NEW_WEEK="$(ls -t "$VAULT"/Worklogs/*-W*.md 2>/dev/null | head -1)"

# The pre-rollover week file, from git, is the ground truth for "nothing lost".
BEFORE="$(mktemp)"; AFTER="$(mktemp)"
git -C "$VAULT" show "HEAD:Worklogs/$CUR_WEEK.md" 2>/dev/null \
  | grep -E '^[[:space:]]+- ' \
  | sed -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | grep -v '^$' | sort -u > "$BEFORE"
cat "$VAULT"/Worklogs/*-W*.md "$VAULT"/Worklogs/Backlog.md \
    "$VAULT"/Threads/*.md 2>/dev/null \
  | sed -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/^#\{1,6\} //' -e 's/[[:space:]]*$//' \
  | grep -v '^$' | sort -u > "$AFTER"

# --- 1. a Thread note exists and carries spilled history -------------------
THREADS="$(ls "$VAULT"/Threads/*.md 2>/dev/null | wc -l | tr -d ' ')"
check "a Thread note was written for the accumulated item" \
      "$([ "$THREADS" -ge 1 ] && echo 0 || echo 1)"

if [ "$THREADS" -ge 1 ]; then
  grep -qi 'rollback path drafted' "$VAULT"/Threads/*.md 2>/dev/null
  check "spilled sub-item text is present in a Thread note" "$?"
  grep -qE '^## ' "$VAULT"/Threads/*.md 2>/dev/null
  check "Thread uses ## sections, so /worklog compact can process it later" "$?"
fi

# --- 2. nothing was lost ---------------------------------------------------
LOST="$(comm -23 "$BEFORE" "$AFTER" | grep -c . | tr -d ' ')"
if [ "$LOST" -eq 0 ]; then
  ok "no sub-item text lost across the rollover"
else
  no "LOSS: $LOST sub-item line(s) exist in neither the week file, Backlog nor Threads/"
  comm -23 "$BEFORE" "$AFTER" | head -3 | sed 's/^/      /'
fi

# --- 3. the week file actually shrank for that item ------------------------
CUT_SUBS="$(awk '/^- \*\*P[012]\*\*.*cutover plan/{f=1;next} /^- \*\*P[012]\*\*/{f=0} f&&/^  - /{n++} END{print n+0}' "$NEW_WEEK" 2>/dev/null)"
if [ "${CUT_SUBS:-99}" -le 5 ]; then
  ok "cutover item carries $CUT_SUBS sub-items in the new week, down from 8"
else
  no "cutover item still carries $CUT_SUBS sub-items - retention did not apply"
fi

grep -qE 'Full history:.*\[\[Threads/' "$NEW_WEEK" 2>/dev/null
check "the pruned item links its Thread note" "$?"

# --- 4. the open action survived regardless of age -------------------------
# threads.md rule 3: an unmet commitment is why the item is still on the board.
# It is 6 days old here, older than the two newest entries, so a naive
# "keep the newest N" drops it. That is the specific regression this catches.
grep -q 'owes the data-tier runbook' "$NEW_WEEK" 2>/dev/null
check "the open action stayed in the week file despite not being newest" "$?"

# --- 5. the dormant item left ----------------------------------------------
grep -q 'Retire the legacy access-request form' "$NEW_WEEK" 2>/dev/null
if [ "$?" -ne 0 ]; then
  ok "the dormant item is no longer in the week file"
  grep -qri 'Retire the legacy access-request form' \
       "$VAULT/Worklogs/Backlog.md" "$VAULT"/Threads/ 2>/dev/null
  check "the dormant item is recoverable from Backlog or a Thread" "$?"
else
  no "the dormant item (40 days stale) rode forward into the new week"
fi

rm -f "$BEFORE" "$AFTER"
exit $FAILS

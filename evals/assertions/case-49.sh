#!/usr/bin/env bash
# Case 49: auto sync on. The add lands in the week file, sync.sh --auto pushes it to the local
# bare origin, and the run prints one result line without asking to sync.
. "$(dirname "$0")/_lib.sh"

# A P2 line naming the task; the skill may wiki-link a program into the title.
grep -qiE '^- \*\*P2\*\*.*review.*onsite notes' "$WEEK_FILE"; check "the item is in the week file" $?

# The sync result must reach the user: the assistant's text (OUT), not only a Bash tool result,
# names the pushed commit and says it was pushed. Exact wording is not required: haiku:low
# sometimes paraphrases the line, and the user is still told. A silent sync fails here.
SHORT="$(git -C "$VAULT" rev-parse --short HEAD 2>/dev/null)"
[ -n "$SHORT" ] && grep -qF "$SHORT" "$OUT" && grep -qi 'pushed' "$OUT"
check "the sync result (commit $SHORT, pushed) was shown to the user" $?

REMOTE="$(git -C "$VAULT" remote get-url origin 2>/dev/null)"
[ -n "$REMOTE" ] && [ "$(git --git-dir="$REMOTE" rev-parse HEAD 2>/dev/null)" = "$(git -C "$VAULT" rev-parse HEAD)" ]
check "the bare remote HEAD equals the vault HEAD" $?

! grep -Eqi '(would you like|want me to|shall I).*sync' "$OUT"; check "the run did not offer to sync" $?

ASKS="$(grep -E '"type": ?"assistant"' "$STREAM" | grep -c 'Sync the vault automatically after each change')"
[ "$ASKS" -eq 0 ]; check "the run did not ask the auto sync question" $?

exit $FAILS

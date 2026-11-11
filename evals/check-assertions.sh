#!/usr/bin/env bash
# check-assertions.sh - runs case-49.sh and case-48.sh against fake run directories and checks the
# verdicts. No model run.
# case-49: the silent run has the sync line only in a tool result: must FAIL. The visible run also
# has it in out.txt, the assistant text the user sees: must PASS.
# case-48: the question-first stream (question in assistant text, then the week-file Edit) must
# PASS the ordering check. The Edit-first stream must FAIL it.
#   bash evals/check-assertions.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d -t assert-check)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

check() { # <desc> <exit-code>
  if [ "$2" -eq 0 ]; then printf 'PASS: %s\n' "$1"; else printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); fi
}

# One vault with a real sync, shared by both fake runs. The assertion reads it and never writes.
VAULT="$TMP/vault"
"$HERE/make-vault.sh" "$VAULT" --auto-sync-on >/dev/null
CUR="$(python3 -c 'import datetime;y,w,_=datetime.date.today().isocalendar();print(f"{y}-W{w:02d}")')"
printf -- '- **P2** ⏳ In Progress - review the onsite notes\n' >> "$VAULT/Worklogs/$CUR.md"
SYNC_OUT="$(WORKLOG_SYNC_LOCAL_REMOTE_ONLY=1 "$REPO/skills/worklog/scripts/sync.sh" "$VAULT" "$REPO" eval eval@example.com --auto)"
case "$SYNC_OUT" in "Auto-synced vault: "*" pushed "*) ;; *) echo "setup: sync did not push: $SYNC_OUT"; exit 1 ;; esac

# Both runs carry the sync result as a Bash tool result in stream.jsonl.
STREAM="$TMP/stream.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Added the item."}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","content":"'"$SYNC_OUT"'"}]}}' > "$STREAM"

mkdir -p "$TMP/silent" "$TMP/visible" "$TMP/paraphrase"
: > "$TMP/silent/diff.txt"; : > "$TMP/silent/changed.txt"
for d in visible paraphrase; do cp "$TMP/silent/diff.txt" "$TMP/silent/changed.txt" "$TMP/$d/"; done

# Silent: the assistant text never shows the sync line.
printf 'Added the item.\n' > "$TMP/silent/out.txt"
# Visible: the assistant text shows the sync line too.
printf 'Added the item.\n%s\n' "$SYNC_OUT" > "$TMP/visible/out.txt"
# Paraphrase: the assistant reworded the line but still names the commit and "pushed".
printf 'Added the item. The vault auto-synced (`%s pushed`).\n' "$(git -C "$VAULT" rev-parse --short HEAD)" > "$TMP/paraphrase/out.txt"

run_case49() { # <run-dir>: runs case-49.sh the way run.sh does, returns its exit code
  VAULT="$VAULT" OUT="$1/out.txt" DIFF="$1/diff.txt" CHANGED="$1/changed.txt" STREAM="$STREAM" \
    bash "$HERE/assertions/case-49.sh" >/dev/null 2>&1 < /dev/null
}

run_case49 "$TMP/silent"; RC=$?
[ "$RC" -ne 0 ]; check "silent run (sync line only in a tool result) FAILS case-49" $?

run_case49 "$TMP/visible"; RC=$?
[ "$RC" -eq 0 ]; check "visible run (sync line in out.txt) PASSES case-49" $?

run_case49 "$TMP/paraphrase"; RC=$?
[ "$RC" -eq 0 ]; check "paraphrased run (commit and pushed in out.txt) PASSES case-49" $?

# Case 48 ordering. Both fake streams hold one question and one week-file Edit; only the order
# differs. The run uses the same shared vault, which already has the item and the Auto Sync note.
WEEK="$VAULT/Worklogs/$CUR.md"
Q48='Sync the vault automatically after each change? [Y/n]'
mkdir -p "$TMP/q-first" "$TMP/edit-first"
for d in q-first edit-first; do : > "$TMP/$d/diff.txt"; : > "$TMP/$d/changed.txt"; printf 'ok\n' > "$TMP/$d/out.txt"; done
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"'"$Q48"'"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","content":"yes"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'"$WEEK"'"}}]}}' \
  > "$TMP/q-first/stream.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'"$WEEK"'"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"'"$Q48"'"}]}}' \
  > "$TMP/edit-first/stream.jsonl"

run_case48() { # <run-dir>: runs case-48.sh the way run.sh does, returns its exit code
  VAULT="$VAULT" OUT="$1/out.txt" DIFF="$1/diff.txt" CHANGED="$1/changed.txt" STREAM="$1/stream.jsonl" \
    bash "$HERE/assertions/case-48.sh" >/dev/null 2>&1 < /dev/null
}

run_case48 "$TMP/q-first"; RC=$?
[ "$RC" -eq 0 ]; check "question before the week-file Edit PASSES case-48" $?

run_case48 "$TMP/edit-first"; RC=$?
[ "$RC" -ne 0 ]; check "week-file Edit before the question FAILS case-48" $?

exit $FAILS

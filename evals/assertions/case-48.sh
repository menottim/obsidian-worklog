#!/usr/bin/env bash
# Case 48: first-run auto sync question. The note is missing and origin is local, so the skill
# asks once, before any other step of the command, writes the note from the answer ("Yes" means
# on), then adds the item. A run that asks twice, never writes the note, or edits the week file
# before asking fails here.
. "$(dirname "$0")/_lib.sh"

grep -qx 'auto_sync: on' "$VAULT/Preferences/Auto Sync.md" 2>/dev/null
check "the Auto Sync note was written with auto_sync: on" $?

# A P2 line naming the task; the skill may wiki-link a program into the title.
grep -qiE '^- \*\*P2\*\*.*review.*onsite notes' "$WEEK_FILE"; check "the item is in the week file" $?

# Read the model's own events only (assistant lines). The Skill tool returns SKILL.md as a
# user-side tool result, and that text also contains the question, so user-side events are
# skipped. The question counts in assistant text blocks and in AskUserQuestion input.
# Prints "<asks> <ordered>": ordered is 1 when the question appears in an assistant event
# before the first Edit or Write whose file_path is the week file.
RES="$(python3 -I -c '
import json, sys
stream, week_file, cur_week = sys.argv[1:4]
Q = "Sync the vault automatically after each change"
week_suffix = "/Worklogs/" + cur_week + ".md"
asks = 0
first_ask = None
first_write = None
pos = 0
with open(stream, encoding="utf-8", errors="replace") as f:
    for line in f:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("type") != "assistant":
            continue
        for b in (e.get("message") or {}).get("content") or []:
            if not isinstance(b, dict):
                continue
            pos += 1
            kind = b.get("type")
            if kind == "text":
                n = b.get("text", "").count(Q)
            elif kind == "tool_use" and b.get("name") == "AskUserQuestion":
                n = json.dumps(b.get("input") or {}, ensure_ascii=False).count(Q)
            elif kind == "tool_use" and b.get("name") in ("Edit", "Write"):
                fp = str((b.get("input") or {}).get("file_path", ""))
                if first_write is None and (fp == week_file or fp.endswith(week_suffix)):
                    first_write = pos
                n = 0
            else:
                n = 0
            asks += n
            if n and first_ask is None:
                first_ask = pos
ordered = int(first_ask is not None and (first_write is None or first_ask < first_write))
print(asks, ordered)
' "$STREAM" "$WEEK_FILE" "$CUR_WEEK" 2>/dev/null)"
read -r ASKS ORDERED <<<"$RES"

[ "${ASKS:-x}" -eq 1 ] 2>/dev/null; check "the auto sync question was asked exactly once (asked ${ASKS:-none})" $?

[ "${ORDERED:-0}" -eq 1 ] 2>/dev/null; check "the auto sync question came before the first week-file edit" $?

exit $FAILS

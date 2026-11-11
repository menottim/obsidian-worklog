#!/usr/bin/env bash
# Case 21: a pull with both a context-channel and a DM source. The channel
# sweep still auto-folds its high-confidence match; the DM sweep runs after
# it and its candidate joins the same end-of-pull approval batch instead of
# auto-folding. No approval is scripted, so nothing from the DM reaches the
# vault.
. "$(dirname "$0")/_lib.sh"

HITS="$(grep -ci 'replication lag' "$WEEK_FILE")"
[ "$HITS" -eq 1 ]; check "the channel sweep still auto-folds its high-confidence match ($HITS)" $?

grep -qi 'on-call rotation' "$OUT"; check "the DM candidate reached the approval batch" $?

! grep -rqi 'on-call rotation' "$VAULT/Worklogs" "$VAULT/People" "$VAULT/Programs" 2>/dev/null
check "the DM candidate was not auto-folded into the vault" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "no new top-level item from either sweep (found $TOP)" $?

# Structural: the DM helper (a Bash call to slack-search-dms) must run after
# the channel sweep's first MCP call, not before or interleaved ahead of it.
python3 - "$STREAM" <<'PYORDER'
import json, sys

stream = sys.argv[1]
channel_idx = dm_idx = None
i = 0
for line in open(stream):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if ev.get("type") != "assistant":
        continue
    for blk in (ev.get("message") or {}).get("content") or []:
        if not isinstance(blk, dict) or blk.get("type") != "tool_use":
            continue
        i += 1
        name = blk.get("name") or ""
        if "slack_read_channel" in name and channel_idx is None:
            channel_idx = i
        if name == "Bash" and "slack-search-dms" in (blk.get("input") or {}).get("command", "") and dm_idx is None:
            dm_idx = i

if channel_idx is None:
    print("FAIL: the channel sweep never called slack_read_channel")
    raise SystemExit(1)
if dm_idx is None:
    print("FAIL: the DM sweep never called slack-search-dms")
    raise SystemExit(1)
if dm_idx < channel_idx:
    print(f"FAIL: the DM sweep (call {dm_idx}) ran before the channel sweep (call {channel_idx})")
    raise SystemExit(1)
print(f"PASS: the DM sweep (call {dm_idx}) ran after the channel sweep (call {channel_idx})")
PYORDER
RC=$?
[ "$RC" -eq 0 ] || FAILS=$((FAILS + 1))

exit $FAILS

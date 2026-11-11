#!/usr/bin/env bash
# Case 26: run a pull twice with no new DM activity between the two sweeps.
#
# The second search uses after=last_scan_ts, so it returns nothing. No batch
# entries, no writes, and last_scan_ts advances. The DM sweep is approval-only,
# so no DM result may reach the vault on either sweep without a decision.
#
# The helper is a stub in the sandbox. The runner rewrites the helper path in the
# staged skill, and aborts if that rewrite does not land, so no run can reach the
# real slack-search-dms and the real Slack DMs behind it.
. "$(dirname "$0")/_lib.sh"

DMS="$VAULT/Sources/_dms.md"

grep -q 'last_scan_ts: *[^n]' "$DMS"; check "the DM source advanced last_scan_ts off null" $?

# Approval-only: the DM text must not appear in the vault, because nothing
# approved it. It is the same phrase on both sweeps, so one leak is enough.
! grep -rqi 'holding the Thursday window' "$VAULT/Worklogs" "$VAULT/People" "$VAULT/Programs" 2>/dev/null
check "the un-approved DM result never reached the vault" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "no DM-derived top-level item was added (found $TOP)" $?

# The channel sweep still works alongside the DM sweep, and still folds once.
HITS="$(grep -ci 'replication lag' "$WEEK_FILE")"
[ "$HITS" -eq 1 ]; check "the channel fold landed exactly once across both sweeps ($HITS)" $?

grep -qiE 'dm|direct message' "$OUT"; check "the sweep reported on the DM source" $?

# Structural: the second sweep must not write to the week file.
python3 - "$STREAM" "$WEEK_FILE" <<'PYTURN'
import json, re, sys

stream, week = sys.argv[1], sys.argv[2]
dest = re.escape(week)
turn, writes = 0, []
for line in open(stream):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if ev.get("type") == "result":
        turn += 1
        continue
    if ev.get("type") != "assistant":
        continue
    for blk in (ev.get("message") or {}).get("content") or []:
        if not isinstance(blk, dict) or blk.get("type") != "tool_use":
            continue
        inp = blk.get("input") or {}
        if blk.get("name") in ("Edit", "Write", "MultiEdit") and week in json.dumps(inp):
            writes.append(turn)
        elif blk.get("name") == "Bash":
            for cmd_line in (inp.get("command") or "").splitlines():
                if re.search(r"\b(?:cp|mv|tee)\b[^;]*" + dest, cmd_line) or \
                   re.search(r">\s*['\"]?" + dest, cmd_line):
                    writes.append(turn)
                    break

if turn < 2:
    print(f"FAIL: only {turn} turn(s) ran, so the second sweep never happened")
    raise SystemExit(1)
late = [t for t in writes if t >= 1]
if late:
    print(f"FAIL: the second sweep wrote to the week file (turns {sorted(set(late))})")
    raise SystemExit(1)
print(f"PASS: the second sweep wrote nothing to the week file ({turn} turns ran)")
PYTURN
RC=$?
[ "$RC" -eq 0 ] || FAILS=$((FAILS + 1))
exit $FAILS

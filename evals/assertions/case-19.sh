#!/usr/bin/env bash
# Case 19: run a context-channel pull twice with no new Slack content between.
# The second sweep must find nothing, write nothing, and only advance
# last_scan_ts and the log.
#
# The scripted reply is a second `/worklog pull`, so both sweeps happen in one
# session against one fixture. The risk this guards is a duplicate: the same
# thread folded twice into the same item, which quietly corrupts a week file and
# is only visible by reading it.
. "$(dirname "$0")/_lib.sh"

# The fold must appear exactly once IN THE WEEK FILE. Two scopes matter here and
# they are easy to confuse. "replication lag" comes only from the Slack message,
# so any occurrence is from a sweep; the fixture never contains it. Counting
# across the whole diff instead counts the Programs note update as a duplicate,
# and appending context to a matched Program note is required by the auto-fold
# rule, not a fault.
HITS="$(grep -ci 'replication lag' "$WEEK_FILE")"
[ "$HITS" -eq 1 ]; check "the week file carries the fold exactly once, not twice ($HITS)" $?

PERMA="$(grep -co 'example.slack.com/archives' "$WEEK_FILE")"
[ "$PERMA" -eq 1 ]; check "one Slack permalink, so the thread folded once ($PERMA)" $?

TOP="$(grep -c '^- \*\*P[0-9]\*\*' "$WEEK_FILE")"
[ "$TOP" -eq 6 ]; check "no new top-level item from either sweep (found $TOP)" $?

grep -q 'last_scan_ts: *[^n]' "$VAULT/Sources/infrasec-leads.md"
check "last_scan_ts advanced off null" $?

PULLS="$(grep -rhcE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] pull \|' "$VAULT"/Logs/*.md | paste -sd+ - | bc)"
[ "${PULLS:-0}" -ge 2 ]; check "both sweeps logged, so the second one is on record ($PULLS entries)" $?

# Structural: the second sweep must not write to the week file. A turn boundary
# is the scripted reply, so turn 2 is the second pull.
python3 - "$STREAM" "$WEEK_FILE" <<'PYTURN'
import json, re, sys

stream, week = sys.argv[1], sys.argv[2]
dest = re.escape(week)
turn = 0
writes = []
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
        name = blk.get("name")
        inp = blk.get("input") or {}
        if name in ("Edit", "Write", "MultiEdit") and week in json.dumps(inp):
            writes.append(turn)
        elif name == "Bash":
            for cmd_line in (inp.get("command") or "").splitlines():
                if re.search(r"\b(?:cp|mv|tee)\b[^;]*" + dest, cmd_line) or \
                   re.search(r">\s*['\"]?" + dest, cmd_line):
                    writes.append(turn)
                    break

second = [t for t in writes if t >= 1]
if turn < 2:
    print(f"FAIL: only {turn} turn(s) ran, so the second sweep never happened")
    raise SystemExit(1)
if second:
    print(f"FAIL: the second sweep wrote to the week file (turns {sorted(set(second))})")
    raise SystemExit(1)
print(f"PASS: the second sweep wrote nothing to the week file ({turn} turns ran)")
PYTURN
RC=$?
[ "$RC" -eq 0 ] || FAILS=$((FAILS + 1))
exit $FAILS

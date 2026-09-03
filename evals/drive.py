#!/usr/bin/env python3
"""Drive a multi-turn eval run over streaming stdin.

Single-turn runs answer most cases, but not the ones whose whole point is what
happens after a human replies: compaction writes only once approved, case 39
tests that approving one proposal does not approve a revised one, and case 23
approves an item out of a pull batch. Those need a second turn.

Usage:
    drive.py <workdir> <replies-file> <prompt> -- claude [args...]

The prompt goes in first. After each `result` event - one per assistant turn -
the next line of the replies file is sent. When the replies run out, stdin
closes and the session ends. Every event is written to <workdir>/stream.jsonl,
in order, so the grader sees the whole conversation rather than its last message.
"""
import json
import pathlib
import subprocess
import sys

work = pathlib.Path(sys.argv[1])
replies_file = sys.argv[2]
prompt = sys.argv[3]
assert sys.argv[4] == "--", "expected -- before the claude command"
cmd = sys.argv[5:]

replies = [ln for ln in pathlib.Path(replies_file).read_text().splitlines() if ln.strip()]

proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1)


def send(text):
    proc.stdin.write(json.dumps({
        "type": "user",
        "message": {"role": "user", "content": [{"type": "text", "text": text}]},
    }) + "\n")
    proc.stdin.flush()


stream = (work / "stream.jsonl").open("w")
send(prompt)
pending = list(replies)

for line in proc.stdout:
    stream.write(line)
    stream.flush()
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if ev.get("type") != "result":
        continue
    # One turn finished. Feed the next reply, or close stdin and let it end.
    if pending:
        send(pending.pop(0))
    else:
        break

try:
    proc.stdin.close()
except (BrokenPipeError, ValueError):
    pass
stream.close()
err = proc.stderr.read()
if err:
    (work / "stderr.txt").write_text(err)
try:
    proc.wait(timeout=60)
except subprocess.TimeoutExpired:
    proc.kill()
sys.exit(0)

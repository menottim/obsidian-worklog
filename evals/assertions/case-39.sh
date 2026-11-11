#!/usr/bin/env bash
# Case 39: the link gate forces a revision, and the approval already given must
# not carry over to the revised proposal.
#
# references/compact.md: "revise the proposal, show the revised History bullets
# again, and wait for approval again." An approval is for the exact bullets the
# user saw.
#
# The re-approval check is structural, read from the event stream rather than
# from prose: find the turn that announces the revision and the turn that writes
# the note, and require a turn boundary between them. A turn boundary is a user
# reply, so writing in the same turn as the revision means the write went out on
# a stale approval - the exact failure this case exists to catch.
. "$(dirname "$0")/_lib.sh"

NOTE="$VAULT/People/Kenji Watanabe.md"

changed_in "People/Kenji Watanabe.md"; check "the fold was written" $?
grep -qF 'Chris Moreau' "$NOTE"; check "the [[Chris Moreau]] link target survived the fold" $?
[ -f "$VAULT/People/Chris Moreau.md" ]; check "Chris Moreau's note is still in the vault" $?

LINES="$(grep -c . "$NOTE")"
[ "$LINES" -lt 300 ]; check "the note actually shrank, so a fold really happened ($LINES lines)" $?

TODAY="$(date +%Y-%m-%d)"
grep -qF "compacted: $TODAY" "$NOTE"; check "compacted: updated to today" $?

python3 - "$STREAM" "$NOTE" <<'PYTURN'
import json, re, sys

note = sys.argv[2]
revision_turn = write_turn = None
turn = 0
for line in open(sys.argv[1]):
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
        if not isinstance(blk, dict):
            continue
        if blk.get("type") == "text":
            low = (blk.get("text") or "").lower()
            if revision_turn is None and ("would be lost" in low or "revising" in low
                                          or "revised" in low):
                revision_turn = turn
        elif blk.get("type") == "tool_use" and write_turn is None:
            name = blk.get("name")
            inp = blk.get("input") or {}
            if name in ("Edit", "Write", "MultiEdit"):
                if note in json.dumps(inp):
                    write_turn = turn
            elif name == "Bash":
                # The skill works through the shell: it materializes the proposal
                # to a temp file and copies it into place, so the write shows up as
                # cp/mv/tee or a redirect ONTO the note, never as an Edit call.
                # Match the note's absolute path as the destination - matching the
                # note's name alone hits the heredoc that writes the proposal,
                # whose content contains the "# Kenji Watanabe" heading.
                dest = re.escape(note)
                # Per line, so a match cannot straddle a variable assignment and a
                # later command. cp/mv take a source argument before the
                # destination, so allow anything between the verb and the path.
                for cmd_line in (inp.get("command") or "").splitlines():
                    if re.search(r"\b(?:cp|mv|tee)\b[^;]*" + dest, cmd_line) or \
                       re.search(r">\s*['\"]?" + dest, cmd_line):
                        write_turn = turn
                        break

if revision_turn is None:
    print("SKIP: no revision occurred; nothing to re-approve")
    raise SystemExit(0)
if write_turn is None:
    print("SKIP: revision occurred but no write to the note was seen")
    raise SystemExit(0)
if write_turn > revision_turn:
    print("PASS: revised bullets went back for fresh approval "
          f"(revised in turn {revision_turn + 1}, written in turn {write_turn + 1})")
    raise SystemExit(0)
print("FAIL: wrote the revised fold on the earlier approval "
      f"(revision and write both in turn {write_turn + 1})")
raise SystemExit(1)
PYTURN
RC=$?
[ "$RC" -eq 0 ] || FAILS=$((FAILS + 1))
exit $FAILS

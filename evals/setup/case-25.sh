#!/usr/bin/env bash
# Case 25 needs exclude_users and exclude_conversations populated before the
# sweep runs, so the skill's filter step has something to drop.
set -eu
VAULT="${1:?usage: case-25.sh <vault>}"
python3 - "$VAULT/Sources/_dms.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("exclude_users: []", 'exclude_users: ["U_BLOCKED"]')
text = text.replace("exclude_conversations: []", 'exclude_conversations: ["D0EVAL_BLOCKED_CHAN"]')
open(path, "w").write(text)
PY

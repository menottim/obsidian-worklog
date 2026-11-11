#!/usr/bin/env bash
# Case 36 needs the vault dirty: compaction is lossy and git history is the only
# undo, so the skill must refuse to fold when there are uncommitted changes.
# make-vault always commits a clean tree, so dirty it deliberately here.
set -eu
VAULT="${1:?usage: case-36.sh <vault>}"
printf '\n- Uncommitted edit that must block the fold.\n' >> "$VAULT/People/Dev Sharma.md"
printf 'scratch\n' > "$VAULT/People/Untracked Scratch.md"

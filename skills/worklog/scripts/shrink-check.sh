#!/usr/bin/env bash
# shrink-check.sh <vault> - flag tracked *.md files that were emptied, deleted or shrunk a lot vs HEAD.
# Read-only. Catches a bulk or scripted edit that truncated notes (open(p,'w') before read()).
# Output, one line per flagged file: SHRINK <path>: <before> -> <after> bytes | EMPTY <path> | DELETED <path>
# Exempt: paths under Cold/ and Logs/. Also exempt: a note whose "## Cold storage" section gained
# [[Cold/...]] lines in this diff. That note is a cold move, and cold-gate.sh checks it.
# Rollover moves Worklogs/<name>.md to Archive/ without committing. A DELETED Worklogs/<name>.md with
# Archive/<name>.md in the tree is a move, so it is not flagged.
# Staged and unstaged changes both count.
# Env WORKLOG_SHRINK_PCT (default 50): flag a file when it lost more than this percent of its bytes.
# Env WORKLOG_SHRINK_CONFIRM: newline-separated vault-relative paths the user confirmed. A flagged path
# that matches one exactly is skipped.
# Exit 0 nothing flagged, 1 something flagged, 2 usage error. bash 3.2; coreutils + git.
set -uo pipefail

[ "$#" -ge 1 ] || { echo "shrink-check: usage: shrink-check.sh <vault>" >&2; exit 2; }
VAULT="$1"
git -C "$VAULT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "shrink-check: not a git repo: $VAULT" >&2; exit 2; }
PCT="${WORKLOG_SHRINK_PCT:-50}"
case "$PCT" in ''|*[!0-9]*) echo "shrink-check: WORKLOG_SHRINK_PCT must be an integer" >&2; exit 2 ;; esac

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cold_idx() { awk '/^## /{ins=($0 ~ /^## Cold storage[ \t]*$/); next} ins && /\[\[Cold\//' ; }
RC=0
confirmed() { printf '%s\n' "${WORKLOG_SHRINK_CONFIRM:-}" | grep -Fxq -- "$1"; }
flag() { confirmed "$2" && return 0; printf '%s\n' "$1"; RC=1; }  # $1 line, $2 path

# --no-renames: a rename shows as delete + add, so a moved note is not missed as unchanged.
git -C "$VAULT" diff HEAD --no-renames --diff-filter=MD --name-only -z -- '*.md' > "$T/list" 2>/dev/null
while IFS= read -r -d '' f; do
  case "$f" in Cold/*|Logs/*) continue ;; esac
  before="$(git -C "$VAULT" cat-file -s "HEAD:$f" 2>/dev/null)" || continue
  if [ ! -e "$VAULT/$f" ]; then
    base="${f#Worklogs/}"
    case "$f" in Worklogs/*.md) case "$base" in */*) ;; *) [ -e "$VAULT/Archive/$base" ] && continue ;; esac ;; esac
    flag "DELETED $f" "$f"; continue
  fi
  after="$(wc -c < "$VAULT/$f" | tr -d ' ')"
  [ "$before" -gt 0 ] || continue
  if [ "$after" -eq 0 ]; then flag "EMPTY $f" "$f"; continue; fi
  [ $(( (before - after) * 100 )) -gt $(( before * PCT )) ] || continue
  git -C "$VAULT" show "HEAD:$f" | cold_idx > "$T/old"
  cold_idx < "$VAULT/$f" > "$T/new"
  # cold move: the index gained at least one [[Cold/...]] line
  if [ -n "$(grep -F -x -v -f "$T/old" "$T/new")" ]; then continue; fi
  flag "SHRINK $f: $before -> $after bytes" "$f"
done < "$T/list"
exit "$RC"

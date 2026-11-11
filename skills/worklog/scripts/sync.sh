#!/usr/bin/env bash
# sync.sh <vault> <skill-install-path> <git-name> <git-email> [--auto] - commit and push the vault.
# Order: can-sync, detached-HEAD check, mkdir Cold, shrink-check, default .gitignore when absent, detect
# changes, copy skill files into .skills/worklog/, log entry, git add, commit, push. The log entry is written
# only after the shrink check passes and only when the vault has a change to commit. A shrink stop leaves
# Logs/ untouched. A failed git add or commit unstages, restores the month log to its prior bytes (or
# removes it), and exits 2.
# Output: one result line, or the shrink-check lines on exit 1. The prefix is "Synced vault",
# or "Auto-synced vault" with --auto.
# Exit 0 pushed; 1 shrink check flagged; 2 usage, not a git repo, no origin, detached HEAD, or a copy/commit
# failure; 3 committed but push failed; 4 nothing to commit and nothing to push.
# Env WORKLOG_SYNC_LOCAL_REMOTE_ONLY=1: a non-local push URL is refused before any push (exit 3).
# Env WORKLOG_SHRINK_CONFIRM reaches shrink-check.sh unchanged.
# Allowlist: every Vault Layout directory must be on the ALLOW list below. A directory left off is
# silently never staged. Only existing directories are staged, so a listed one that is absent cannot
# fail git add. To find a missing one, run `git status --porcelain` after a sync: untracked files
# under the vault root mean a directory is not on the list. The root .gitignore is the one file on the list:
# it is staged when it exists, so sync never leaves it untracked.
# bash 3.2; coreutils + git. Siblings resolve via dirname "$0". Commit identity is passed with -c.
set -uo pipefail

usage() { echo "sync: usage: sync.sh <vault> <skill-install-path> <git-name> <git-email> [--auto]" >&2; exit 2; }

case "$#:${5:-}" in
  4:|5:--auto) ;;
  *) usage ;;
esac
HERE="$(cd "$(dirname "$0")" && pwd)"
VAULT="$1"; INST="$2"; GNAME="$3"; GMAIL="$4"
AUTO=""; [ "$#" -eq 5 ] && AUTO=1

if [ -n "$AUTO" ]; then
  PFX="Auto-synced vault"; SKIP="Auto-sync skipped"; NOTHING="Auto-sync: nothing to commit."; TARGET="vault (auto)"
else
  PFX="Synced vault"; SKIP="Sync skipped"; NOTHING="Sync: nothing to commit."; TARGET="vault"
fi
DAY="$(date +%Y-%m-%d)"
MSG="worklog sync $DAY"
# ALLOW rules: see the Allowlist note in the header. .skills/ is left out of change detection: each run
# rewrites it, so counting it would turn "nothing to sync" into a commit. Logs/ counts.
ALLOW="Worklogs People Programs Threads Teams Archive Summaries Reports References Templates Sources Meetings Logs Preferences Cold .skills"
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904

# Sets PRESENT to the allowlisted paths that exist on disk, skipping the names in $1 (space-separated).
present() {
  PRESENT=()
  for d in $ALLOW; do
    case " $1 " in *" $d "*) continue ;; esac
    [ -e "$VAULT/$d" ] && PRESENT+=("$d")
  done
  # The root .gitignore is a single file on the list, so a new or changed one is committed.
  case " $1 " in *" .gitignore "*) ;; *) [ -f "$VAULT/.gitignore" ] && PRESENT+=(".gitignore") ;; esac
  return 0
}

# True when path $1 is under an allowlisted directory, or is the root .gitignore.
in_allow() { [ "$1" = ".gitignore" ] && return 0; for d in $ALLOW; do case "$1" in "$d"/*) return 0 ;; esac; done; return 1; }

is_local() { case "$1" in /*|./*|../*|file://*) return 0 ;; *) return 1 ;; esac; }

# Pushes HEAD and prints the one-line result. $1 is the file count. Exits 0 on success, 3 otherwise.
report_push() {
  SHORT="$(git -C "$VAULT" rev-parse --short HEAD)"
  if [ "${WORKLOG_SYNC_LOCAL_REMOTE_ONLY:-}" = "1" ] && ! is_local "$(git -C "$VAULT" remote get-url --push origin 2>/dev/null)"; then
    printf '%s: %s committed locally; push failed: non-local remote refused. The next sync retries.\n' "$PFX" "$SHORT"
    exit 3
  fi
  ERR="$(mktemp)" || exit 2
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"
  if GIT_TERMINAL_PROMPT=0 git -C "$VAULT" push -q origin HEAD 2>"$ERR"; then
    rm -f "$ERR"
    printf '%s: %s pushed (%s files).\n' "$PFX" "$SHORT" "$1"
    exit 0
  fi
  # First fatal:/error: line without its prefix; else the first non-empty line. Trim, drop one trailing period.
  REASON="$(grep -E '^(fatal|error): ' "$ERR" | head -n 1 | sed -e 's/^[a-z]*: //')"
  [ -n "$REASON" ] || REASON="$(grep -v '^[[:space:]]*$' "$ERR" | head -n 1)"
  REASON="$(printf '%s' "$REASON" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\.$//')"
  rm -f "$ERR"
  printf '%s: %s committed locally; push failed: %s. The next sync retries.\n' "$PFX" "$SHORT" "${REASON:-unknown error}"
  exit 3
}

REASON="$("$HERE/auto-sync.sh" "$VAULT" can-sync)" || { printf '%s: %s.\n' "$SKIP" "$REASON"; exit 2; }
git -C "$VAULT" symbolic-ref -q HEAD >/dev/null 2>&1 || { printf '%s: detached HEAD.\n' "$SKIP"; exit 2; }

mkdir -p "$VAULT/Cold" || exit 2
SHRINK="$("$HERE/shrink-check.sh" "$VAULT")"; RC=$?
if [ "$RC" -eq 1 ]; then printf '%s\n' "$SHRINK"; exit 1; fi
[ "$RC" -eq 0 ] || exit 2

# Default root .gitignore when none exists. Never overwritten. Staged with the allowlist (see present).
if [ ! -e "$VAULT/.gitignore" ]; then
  printf '%s\n' '.obsidian/plugins/*/data.json' '.obsidian/workspace.json' '.DS_Store' '*.swp' '.env' > "$VAULT/.gitignore" \
    || { echo "sync: cannot write .gitignore" >&2; exit 2; }
fi

present ".skills"
CHANGED=""
[ "${#PRESENT[@]}" -gt 0 ] && CHANGED="$(git -C "$VAULT" status --porcelain -- ${PRESENT[@]+"${PRESENT[@]}"})"

BRANCH="$(git -C "$VAULT" symbolic-ref -q --short HEAD 2>/dev/null)"
BASE=""
if [ -n "$BRANCH" ] && git -C "$VAULT" rev-parse --verify -q "refs/remotes/origin/$BRANCH" >/dev/null 2>&1; then
  BASE="origin/$BRANCH"
fi

if [ -z "$CHANGED" ]; then
  AHEAD=0
  if git -C "$VAULT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    if [ -n "$BASE" ]; then AHEAD="$(git -C "$VAULT" rev-list --count "$BASE..HEAD")"; else AHEAD=1; fi
  fi
  if [ "$AHEAD" -eq 0 ]; then echo "$NOTHING"; exit 4; fi
  FILES="$(git -C "$VAULT" diff --name-only "${BASE:-$EMPTY_TREE}" HEAD | grep -c .)"
  report_push "$FILES"
fi

copy_file() { cp "$1" "$2" 2>/dev/null || { echo "sync: cannot copy $1" >&2; exit 2; }; }
DEST="$VAULT/.skills/worklog"
mkdir -p "$DEST" || exit 2
copy_file "$INST/skills/worklog/SKILL.md" "$DEST/SKILL.md"
copy_file "$INST/.claude-plugin/plugin.json" "$DEST/plugin.json"
if [ -f "$INST/.codex-plugin/plugin.json" ]; then copy_file "$INST/.codex-plugin/plugin.json" "$DEST/codex-plugin.json"; fi

# The month log's prior bytes, so a failed add or commit can put them back. Removed once committed.
LOGF="$VAULT/Logs/$(date +%Y-%m).md"
LOGBAK="$(mktemp)" || exit 2
LOG_EXISTED=""
if [ -f "$LOGF" ]; then LOG_EXISTED=1; cp "$LOGF" "$LOGBAK" || { rm -f "$LOGBAK"; echo "sync: cannot copy $LOGF" >&2; exit 2; }; fi
restore_log() { if [ -n "$LOG_EXISTED" ]; then cp "$LOGBAK" "$LOGF"; else rm -f "$LOGF"; fi; }
undo_sync() { git -C "$VAULT" reset -q; restore_log; rm -f "$LOGBAK"; }

"$HERE/log-append.sh" "$VAULT" sync "$TARGET" "$MSG" || { restore_log; rm -f "$LOGBAK"; echo "sync: cannot write the log entry" >&2; exit 2; }

present ""
git -C "$VAULT" add -- ${PRESENT[@]+"${PRESENT[@]}"} || { undo_sync; echo "sync: git add failed" >&2; exit 2; }

# Unstage anything already staged outside the allowlist, so the commit holds allowlisted paths only.
# The file on disk is untouched. -z keeps odd file names intact.
UNSTAGE="$(mktemp)" || exit 2
git -C "$VAULT" diff --cached --name-only -z > "$UNSTAGE"
while IFS= read -r -d '' f; do
  in_allow "$f" && continue
  git -C "$VAULT" reset -q -- "$f" || { rm -f "$UNSTAGE"; undo_sync; echo "sync: cannot unstage $f" >&2; exit 2; }
done < "$UNSTAGE"
rm -f "$UNSTAGE"

SUBJECT="$MSG"; [ -n "$AUTO" ] && SUBJECT="$MSG (auto)"
git -C "$VAULT" -c user.name="$GNAME" -c user.email="$GMAIL" commit -q -m "$SUBJECT" || { undo_sync; echo "sync: commit failed" >&2; exit 2; }
rm -f "$LOGBAK"
FILES="$(git -C "$VAULT" show --name-only --format= HEAD | grep -c .)"
report_push "$FILES"

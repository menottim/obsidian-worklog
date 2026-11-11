#!/usr/bin/env bash
# check-make-vault.sh - checks make-vault.sh's auto sync flags. Runs no model.
#   bash evals/check-make-vault.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d -t mkvault-check)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

check() { # <desc> <exit-code>
  if [ "$2" -eq 0 ]; then printf 'PASS: %s\n' "$1"; else printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); fi
}

NOTE="Preferences/Auto Sync.md"

# Default: the note is written with auto_sync: off.
"$HERE/make-vault.sh" "$TMP/default" >/dev/null
grep -qx 'auto_sync: off' "$TMP/default/$NOTE" 2>/dev/null; check "default note says auto_sync: off" $?

# --auto-sync-on: the note says on, and origin is a local bare repo at HEAD.
"$HERE/make-vault.sh" "$TMP/on" --auto-sync-on >/dev/null
grep -qx 'auto_sync: on' "$TMP/on/$NOTE" 2>/dev/null; check "--auto-sync-on note says auto_sync: on" $?
ON_ORIGIN="$(git -C "$TMP/on" remote get-url origin 2>/dev/null)"
case "$ON_ORIGIN" in /*) rc=0 ;; *) rc=1 ;; esac
check "--auto-sync-on origin is a local absolute path" $rc
[ -n "$ON_ORIGIN" ] && [ "$(git --git-dir="$ON_ORIGIN" rev-parse HEAD 2>/dev/null)" = "$(git -C "$TMP/on" rev-parse HEAD)" ]
check "--auto-sync-on bare remote HEAD equals vault HEAD" $?

# --no-auto-sync-note: no note, and origin is a local path.
"$HERE/make-vault.sh" "$TMP/none" --no-auto-sync-note >/dev/null
[ ! -e "$TMP/none/$NOTE" ]; check "--no-auto-sync-note writes no note" $?
NONE_ORIGIN="$(git -C "$TMP/none" remote get-url origin 2>/dev/null)"
case "$NONE_ORIGIN" in /*) rc=0 ;; *) rc=1 ;; esac
check "--no-auto-sync-note origin is a local absolute path" $rc

exit $FAILS

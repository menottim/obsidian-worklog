#!/usr/bin/env bash
# log-append.sh <vault> <op> <target> [body-line ...] — append one entry to Logs/YYYY-MM.md.
# The only WRITE-capable helper in the skill. Monthly files keep the log bounded.
# The "## [YYYY-MM-DD] <op> | <target>" prefix is a contract: every consumer greps for it.
# bash 3.2; coreutils only.
set -euo pipefail

[ "$#" -ge 3 ] || { echo "log-append: usage: log-append.sh <vault> <op> <target> [body-line ...]" >&2; exit 2; }
VAULT="$1"; OP="$2"; TARGET="$3"; shift 3
[ -d "$VAULT" ] || { echo "log-append: vault dir not found: $VAULT" >&2; exit 2; }

DAY="$(date +%Y-%m-%d)"
MONTH="$(date +%Y-%m)"
DIR="$VAULT/Logs"
FILE="$DIR/$MONTH.md"

mkdir -p "$DIR" 2>/dev/null || { echo "log-append: cannot create $DIR" >&2; exit 2; }

if [ ! -f "$FILE" ]; then
  {
    printf -- '---\n'
    printf 'type: log\n'
    printf 'month: %s\n' "$MONTH"
    printf -- '---\n\n'
    printf '# Operations log %s\n\n' "$MONTH"
  } > "$FILE" 2>/dev/null || { echo "log-append: cannot write $FILE" >&2; exit 2; }
fi

{
  printf '## [%s] %s | %s\n' "$DAY" "$OP" "$TARGET"
  for line in "$@"; do printf -- '- %s\n' "$line"; done
  printf '\n'
} >> "$FILE" 2>/dev/null || { echo "log-append: cannot append to $FILE" >&2; exit 2; }

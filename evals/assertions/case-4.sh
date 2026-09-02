#!/usr/bin/env bash
# Case 4: /worklog add. One item, wiki-linked, logged. The file-count check is
# the proxy for "did not regenerate the world to append one line".
. "$(dirname "$0")/_lib.sh"

grep -qiF 'rate limit' "$WEEK_FILE"; check "item added to current week" $?
grep -qF '[[Marcus Williams' "$WEEK_FILE"; check "Marcus Williams wiki-linked" $?
grep -qE '\*\*P1\*\*.*[Rr]ate [Ll]imit' "$WEEK_FILE"; check "item carries the P1 marker" $?
[ "$(week_files)" -eq 1 ]; check "no new week file" $?
N="$(changed_count)"
[ "$N" -le 3 ]; check "touched <=3 files, no vault-wide regen (touched $N)" $?
grep -rqE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] add \|' "$VAULT"/Logs/*.md; check "ops log has an add entry" $?
exit $FAILS
